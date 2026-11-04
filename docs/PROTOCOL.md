# Bridge protocol (v1)

How the `factorio-3d-bridge` mod and the 3D client talk. The mock server
(`tools/mock_server.py`) speaks the same protocol, and `tools/protocol.py` checks every message
the mod and the mock send in the tests.

## Transport

- JSON text over UDP, **localhost only** (a Factorio limit): one message per datagram, or for a
  client whose `hello` has `b: 1` several joined by newlines (`\n`), up to 60,000 bytes a
  datagram. Sending a datagram costs the game about a millisecond whatever its size
  (`helpers.send_udp`, 2.1.23), so the mod fills each one and sends what is left at the end of the
  tick. Commands from the client stay one per datagram.
- Factorio binds the port given to `--enable-lua-udp <port>` (default here **34200**). The client
  sends commands to it.
- The client binds **34201** and sends from it. The mod replies to whatever port the client's
  `hello` came from, so nothing else needs configuring.
- On a server (headless or hosted) only the server instance talks to the client. In
  single-player the local game does.

## Conventions

- **Positions** are integers in 1/256 tile, the engine's own resolution: `x = round(tiles * 256)`.
  Factorio `x` is east and `y` is south. In Godot that is `(x, height, y)`.
- **Directions** are Factorio's 16-way `defines.direction`: north 0, east 4, south 8, west 12.
- **Orientation** (vehicles, trains) is sent as thousandths of a turn, clockwise from north.
- **Entity identity:** `unit_number` when the entity has one. Otherwise (trees, rocks, ore) it is
  the prototype id plus the exact fixed-point position.
- Every server message has `t` (type) and `k` (game tick when sent).

## Reliability

World data must not be lost, but UDP can drop packets, so:

- **Reliable** messages carry `r`, numbered 1, 2, 3… from each `welcome`. The mod queues them
  and sends at most `f3d-bytes-per-tick` (32 KB) per tick, so the client's receive buffer never
  overflows.
- If the client sees `r` jump ahead, it sends `resync`. That is `full: 1` while prototypes are
  still incomplete. Afterwards it is `full: 0` with `c`, the chunks to resend: those with a
  missing `ents` part or a missing header (parts arrived without one), or, if none are known
  to be incomplete, the 3x3 chunks around the focus. A chunk still empty 8 s after it was
  subscribed, while the reliable stream has been quiet for 2 s, is asked for the same way.
  If `r` goes backwards (the server reloaded a save), it sends `resync` with `full: 1`.
- **Immediate** messages (`me`, `mv`, `bi`, `ih`, `gi`, `sky`, `msg`, `gui`, `hp`, `tf`, `ts`, `afx`, `died`, `cq`, `rs`, `fl`, `pw`, `ai`, `clip`, `chat`, `stats`, `eq`, `cinfo`, `dead`, `pl`, `al`, `pedia`, `lnets`, `lnet`) have no `r`. Each one is replaced by the next.
- The mod also re-sends one subscribed chunk every 5 seconds, to heal anything a missed event
  left stale.

## Session

1. The client sends `hello` every second. A new `sid` (client restart) starts a fresh session.
2. The mod answers with `welcome`, then `protos`, `tprotos`, `iprotos`, `ready`, `eprops`, `inv`
   and `recipes`.
3. The client sends `sub` (chunks around its camera, nearest first) and `focus`.
4. The mod streams chunk snapshots, deltas and live state.
5. With no `hello` for 10 seconds, the mod drops the client and stops sending.
6. When the controlled character is replaced (it died and a new one took its place), the mod
   starts over from 2 with a new `welcome` naming it.
7. When the character moves to another surface (onto a space platform and back, or wherever the
   single-player player went), the mod sends `surface` and drops all chunk subscriptions. The
   client drops its world (prototypes, inventory, quickbar and research stay) and subscribes
   again. Everything reliable about the old surface came before `surface`; see "Space platforms".

### Work budget

A big request must never make one slow server tick, so the mod works through everything that can
be big in slices, a few a tick, paid for from a per-tick budget counted in work units (a mod can't
read a clock: it would differ between peers). One unit is about one entity read and turned into
a chart's pixels (15-30 us on the laptop it was measured on; a chunk snapshot's
record is two units); 16 tiles read are one unit. The default is 300 units a tick; `budget` changes it (clamped to 50-20000). What is sliced:

- chunk snapshots: how many entities, the tiles, the entities in 1-8 strips of rows, the
  decoratives; `chunk`, `ents` and `dec` go out together when the last slice is read, and a chunk
  something was built in meanwhile is read again;
- charts for `map` the same way, the `chart` sent after its last strip;
- the handshake after `welcome`: a stage a tick or more (dictionaries, `ready` and `eprops`,
  `iuse`, the character's initial state; meanwhile nothing else is sent), and the technologies
  (`techs`) a part at a time;
- one-off answers (`pedia_index`, `pedia`, `lnets`, `lnet`, `stats`, `bonuses`, `perms`,
  `trains_list`, `hinfo`) are queued and answered in order under the budget, so they can come a
  tick or more after the ask;
- the radars the map and the 3D remote view need (`mtr`, `cov`) and the cargo landing pads
  (`lpad`) are found by a scan of the surface in squares, kept current by build and removal events,
  instead of a search of the whole surface;
- the roboports for `mrp` are read from the force's logistic networks' cells, a slice of cells at a
  time.

A job's last slice may run past what is left of the tick's budget; `wb` counts those ticks.

### Several clients

On a server (headless or hosted) up to 8 clients can play at once, each from its own UDP port
(the client binds 34201, or the next free port up to 34208 when another client on the machine has
it). The first client is served as always. A `hello` from another port starts another session
with its own state (chunk subscriptions, focus, reliable numbering, screens, quickbar...) and its
own character; every message above goes to the client it concerns, and each sees the others'
characters as movers. A client that says `bye` or times out is dropped; its character waits for
the same `sid` to come back. In single-player the game plays one character, so a hello from a
new port takes over the session, as before.

## Client → mod

| `t` | Fields | Meaning |
|---|---|---|
| `hello` | `v` protocol, `sid` session id, `w` 1 if a welcome was received, `z` 1 for delta-coded `bi`, `ih` and `mv` (optional), `dc` 1 for decoratives (`dprotos`, `dec`; optional: turning it on later sends the dictionary and every subscribed chunk again, a hello without it turns them off), `b` 1 for several messages to a datagram (optional, see Transport), `bl` 1 to keep belt lanes that aren't sent again (optional, see `bi`) | Keep-alive and handshake. With `w: 0` the mod re-sends the welcome (at most every 2 s) |
| `bye` | | Client is closing |
| `sub` | `c`: `[[cx, cy], ...]` | The full set of chunks to stream, nearest first |
| `focus` | `x`, `y` (fixed), `r` (tiles), `rv`? | Centre and radius for movers and machine states. `rv` = 1 while the 3D remote view is on: then moving things (`mv`, `bi`, `ih`, `en`, `ts`, `tf`, `pj`, `gf`) are sent only where a working radar or the character sees (the chunks `cov` lists) or a roboport's construction area reaches (a chunk whose centre lies in one; the client has them from `mrp`), as Factorio's remote view shows them, and the mod sends `cov` |
| `resync` | `full`: 0 or 1, optional `c`: `[[cx, cy], ...]` | `full: 1` restarts the session. `full: 0` resends the listed subscribed chunks, or all of them without `c`. Rate-limited to once every 2 s, except `full: 0` with `c` |
| `walk` | `d`: direction, or -1 to stop; `a`? (0–999): walk at this angle, thousandths of a turn clockwise from north | Repeat every ~150 ms while held; it expires after 0.5 s. With `a` the mod steps each tick in whichever of the two 8-way directions either side of the angle brings the path back to the line (Factorio's character walks only 8 ways), so the path zig-zags a few hundredths of a tile about it; `d` (the nearest 8-way direction) is for mods without `a` |
| `mine` | `u`, `p`, `x`, `y` (the target's identity) | Repeat while held; mining continues as long as it is repeated |
| `mine_stop` | | |
| `pickup` | | Like holding F: repeat while held; picks up items on the ground within the character's `item_pickup_distance`, a couple per tick |
| `build` | `item`, `x`, `y` (fixed cursor position), `d`, optional `q` (quality), `ghost` (1), `m` (1), `sf` (1) | Place one item's entity, snapped to the grid like the game does (rails to their two-tile grid). Over the same entity it turns it; over one it can fast-replace (a faster belt) it replaces it and gives the old one back. Rolling stock goes onto the nearest rail. Built in quality `q` if the character has it, else normal, else whatever quality it has. `ghost: 1` places an entity ghost instead (Shift+click, or a pipette with none left): no item and no reach needed; with `sf: 1` (Ctrl+Shift+click, super-forced) what stands in the way is marked for deconstruction and the ghost goes there anyway. `m: 1` builds it flipped (`create_entity{mirror}`) |
| `rotate` | `u`, `p`, `x`, `y`, `rev` | Rotate an entity |
| `craft` | `recipe`, `n` | Hand-craft |
| `blueprint` | `i` (main inventory slot, or -1: the stack taken from the library), `x`, `y` (fixed), `d`, optional `sf` (1), optional `bm` (0 / 1 / 2) | Place the blueprint's ghosts there (a book: its active page). `bm` is Factorio's build mode: 0 normal (a click: nothing where something is in the way), 1 forced (Shift+click: trees and rocks in the way marked for deconstruction), 2 super-forced (Ctrl+Shift+click; `sf: 1` too). Without `bm`: forced. Optional `m` (1): flipped east-west (H; V is this with `d` + 8): the mod places a mirrored copy (positions, directions, rails to their mirror directions, the `mirror` flag of crafting machines, splitter sides, inserter vectors); blueprints with signals, train stops or rolling stock are refused |
| `decon` | `i` (slot of a deconstruction planner, -1 the library one, or 0 for everything), `x1`, `y1`, `x2`, `y2`, `cancel` (0/1), optional `nh` (1) | Mark an area for deconstruction, or unmark it; `nh: 1` isn't remembered for undo (the client's own undo of a building); optional `u`, `p`: only that entity (by unit number) in the area is marked (a train mined from the remote view, not the rail under it) |
| `upgrade` | `i` (slot of an upgrade planner, or -1), `x1`, `y1`, `x2`, `y2`, `cancel` (0/1), optional `down` (1) | Mark an area for upgrade by the planner's mappings, or unmark it; `down: 1` is Factorio's right-drag downgrade (the mappings the other way round) |
| `bp_get` | `q` (request id), `i` (slot or -1) | Answers `bp`: that blueprint, book or planner as Factorio's exchange string |
| `bp_set` | `q`, `i` (slot, 0: a new stack in an empty slot, -1: the library stack), `s` (the string), or the string in parts: `id`, `part`, `parts`, `d` | Writes the string into the stack (`import_stack`); answers `bp_ok` |
| `bp_page` | `i` (slot or -1), `a` (1-based) | A book's active page |
| `bp_lib` | | Answers `bpl` for the game's library and, when the bridge plays a save's player, theirs |
| `bp_del` | `i` (main inventory slot, or -1) | The planner window's delete button: destroys the blueprint, book or planner there (nothing else) |
| `bp_rec` | `q`, `src` (`game` / `player`), `ix`, optional `to` (-1) | Answers `bp` with that library record's string; with `to: -1` imports it into the library stack instead and answers `bp_ok` |
| `undo` / `redo` | `h` (from `hist`) | Undoes or redoes what the mod remembered |
| `shoot` | `m`, `x`, `y` (fixed aim point) | `m` 0: shoot at enemies near the character, the game picks the target (Factorio's Space); 1: shoot at the aim point (C); -1: stop. Repeat every ~150 ms while held; it expires after 0.5 s |
| `gun` | `i` | Use gun slot `i` (1-based); empty slots are ignored |
| `enter` | | Like Factorio's Enter: get out of the vehicle the character is in, or into the nearest one within 5 tiles (the driver's seat, or a car's passenger seat if someone drives it) |
| `drive` | `a` (0 nothing, 1 accelerate, 2 brake, 3 reverse), `s` (-1 left, 0 straight, 1 right) | Repeat every ~150 ms while held; it expires after 0.5 s, and `a: 0, s: 0` stops at once |
| `open` | `u`, `p`, `x`, `y` (the target's identity), `rv`?, `si`? | Open the entity's machine screen (needs a unit number, the character's force and reach). Replaces any open screen. With `rv` (from the remote view, on surface `si`) a building out of reach opens where radars cover it (a working radar's nearby chunks, worked out by the mod: a headless server reveals nothing itself), in a chunk whose centre lies in a roboport's construction area (Factorio's roboports don't reveal, Zenith's do) or within 96 tiles of the character; such a screen takes settings but `take`, `put` and transfers answer "Out of reach" |
| `close` | | Close the machine screen |
| `set_recipe` | `u`, `recipe` (name, `""` to clear) | Assemblers only. Items the machine gives back go to the character (spilled if full) |
| `take` | `u`, `item`, `n`, optional `inv` (role) | Move up to `n` of an item from the open machine (from that inventory, or any) to the character |
| `put` | `u`, `item`, `n` | Move up to `n` of an item from the character's main inventory into the open machine, wherever the game inserts it |
| `set_cb` | `u`, `cb` | Set the open combinator's settings, in the shape `gui.cb` has |
| `map` | `cx1`, `cy1`, `cx2`, `cy2`, `res`, `si`? | Charts of chunks `cx1..cx2` x `cy1..cy2` (inclusive) at `res` tiles per pixel (2, 4, 8, 16 or 32; else 4), and the tags; see "Map" |
| `tag_add` | `x`, `y`, `text`, `icon`?, `si`? | A map tag at a fixed position; `icon` is `[signal type, name]` |
| `modreq` | `u`, `p`, `x`, `y` (the target, as `open`; or `u` alone for the open screen's entity), `item`, `q`? (quality), `s`? (a module slot, 1-based, from the machine screen), `clr`? (1: take the requests back, slot `s`'s or all) | A module clicked on a building or ghost, Factorio 2.x's way: within the character's reach (its own surface, not from the remote view, no slot given) it goes in from the inventory; otherwise it is requested, in a ghost's insert plan or a building's item request proxy, for the robots or a platform's hub to bring. One module per free slot; refused with a message when the slots are full, the module isn't allowed there (an effect the machine or its recipe forbids, another category) or it isn't a module. Works from the remote view on another surface (`view`) and from a platform's hub |
| `unghost` | `x`, `y`, `si`?, `q` | Right-click on the map: removes the force's ghost under that point (a building's before a tile's), answered with `unghost` |
| `hinfo` | `q`, `u`, `p`, `x`, `y` (the target, as `open`) | The entity under the mouse is a machine with module slots, a beacon or anything electric: answered by `hinfo`, for the entity info panel's effects and electricity, and a roboport's links. Reads only; the client asks when the hovered entity changes and about once a second while it stays |
| `cmd` | `id`, `text` | A console command from the client's console ("/cheat all") for the bridge to run for its character (console.lua): `/cheat` [`all`, `off`, a planet or platform], `/version`, `/seed`, `/time`, `/evolution` [surface], `/players`, `/admins`, `/server-save` and the mod's `/f3d-*` commands; answered with `cmdr`. Lua (`/c`) is never run from a packet: the client sends it over RCON |
| `bfar` | `r`, `n`?, `m`? | Draw belt lanes as icons out to `r` tiles from the focus (0 stops): the mod starts sending `bfar` for subscribed chunks within it. `n` (0-640): send items on belts (`bi`) within `n` tiles instead of the map setting `f3d-detail-radius` (and not limited by the focus radius). `m` (200-100,000, or 0 for no cap; absent: the mod's 6,000): the most an update reads, counting each item (stack) and each lane checked, before it stops at the last whole ring round the focus (`fr`): the client's Belt updates, so items move as far out as `m` reaches within `n`, and lane icons start there. `u`, optional: work units of belt items read a tick (100 to 10,000,000; absent or 0: the mod's own slices of 1,000): a large `u` reads each update in one tick, so items update every interval |
| `rate` | `l` (0-3) | Send the costliest periodic updates less often, for a server under load (rate.lua): 0 as normal; each level doubles the interval of the jobs at that tier and above, up to each job's longest. From level 1: `bi` (at most every 48 ticks), far lanes (`bfar` rounds), `mv` (at most every 16); from 2: `st`, wire checks, `seg`, `en`; from 3: `fl`/`ht`/`pw`, `tr`, `ts`, `ih`, `gi`, `rc`. A stretched job runs on a tick of its own. `me` is never slowed. `mv`, `bi` and `ih` say how far apart they are (`p`); after a slow-down `mv` and `bi` also keep their old ticks for 120 more while `p` already says the new spacing, so the client can draw them further behind without running out of positions. A new client starts at 0; the level stays through resyncs. `/f3d-rate <0-3>` sets it from the console |
| `mtr` | `si`? | The map view or minimap is open: asks for the trains on that surface's map (about once a second; the mod ignores asks closer than 20 ticks), answered with `mtr` |
| `mrp` | `si`?, `q` | Asks for every roboport of the force on that surface (the character's without `si`), for the map's logistic networks layer and what counts as seen; answered with `mrp` parts. The client asks every 10 s while a map or the 3D remote view needs them. An ask for the same surface within 60 ticks of the last, or while it is being listed, is ignored; one for another surface waits for the listing in progress |
| `lpad` | `si`, `q` | The map view switched to a planet: where the force's cargo landing pad there is, answered with `lpad` (at most 10 s later, while the surface's scan looks for one) |
| `budget` | `u` | The mod's work budget per tick in work units (see "Work budget"), clamped to 50-20000; the default is 300 |
| `view` | `si`, `x`, `y` | The remote view looks at another surface (a planet, or one of the force's platforms) round (`x`, `y`): the mod streams that surface's world instead of the character's and answers with `surface` (`view` = 1); `si` 0 (or the character's) goes back. Meanwhile what Factorio's remote view allows acts on that surface: `build`, `tile` and `rails` place ghosts only, and planners, `rotate`, `paste_settings`, `copy`, `paste`, `undo`/`redo`, `unghost` and `modreq` work there; what needs the character's hands (`mine`, `pickup`, `shoot`, `drop`, `fast`, wires, `throw`) is refused with a message. Opening buildings works (`open` `rv`, `si`) |
| `tag_del` | `id` | Remove the map tag with that id |
| `set_schedule` | `u`, `records` | The open rolling stock's train gets these schedule records, in the shape `gui.tr.sched.records` has; see "Trains" |
| `train_go` | `u`, `i` | Send the open rolling stock's train to its schedule record `i` (1-based) |
| `train_mode` | `u`, `auto` | `auto` 1: the open rolling stock's train runs its schedule; 0: manual |
| `set_stop` | `u`, `name`?, `limit`?, `pri`?, `cb`? | Rename the open train stop, set its trains limit (-1: none), priority (0-255) and circuit settings; see "Trains" |
| `set_interrupts` | `u`, `interrupts` | The open train's schedule interrupts; see "Trains" |
| `train_temp` | `u`, `station` or `rail` | The open train goes to a stop (or rail position) now, as a temporary record |
| `trains_list` | | Factorio's trains overview: every train of the force (`trl`) |
| `train_mode_id` | `id`, `auto` | Automatic (1) or manual (0) for any train of the force, from the overview |
| `set_train_group` | `u`, `g`, `all`? | Factorio's "Change train group": the open rolling stock's train joins group `g` (a new name makes one, `""` leaves its group); `all: 1` (Ctrl) renames the train's whole group to `g` instead |
| `spider_go` | `l`, `x`, `y`, `q`? | The spidertron remote: the force's spidertrons with these unit numbers walk to `x`, `y` (fixed; their waypoints are replaced, several keep their formation); `q: 1` (Shift) adds it to each one's queue instead. Answers with `spd` |
| `spider_q` | `l` | The waypoints of these spidertrons (`spd`), while the remote is held |
| `set_requests` | `u`, `l` | The open requester or buffer chest's requests: `[[item, min, max (-1 none), quality?], ...]`; see "Logistics" |
| `set_storage_filter` | `u`, `item` | What the open storage chest takes (`""`: anything) |
| `set_chest_logistics` | `u`, `tu`?, `rb`? | The open requester or buffer chest's, landing pad's or rocket silo's "Trash unrequested" (`tu`, 1/0) and the requester's "Request from buffer chests" (`rb`, 1/0); see "Machine screens" |
| `land` | | From a platform stopped at a planet (in its hub or beside it), down to its surface in a cargo pod: to the force's landing pad there, else beside its spawn; see "Riding to a platform" |
| `set_char_requests` | `l`?, `on`?, `trash`? | The character's logistic requests (as `set_requests`), whether they are on (1/0), and auto-trash of unrequested items (1/0) |
| `set_char_color` | `c` | The character's colour `[r, g, b]` in 0-255 (`LuaEntity.color`), and its player's colour and chat colour when a player plays it; `ccol` answers |
| `move` | `from`, `fi`, `to`, `ti`, optional `n`, `u` | Move the stack in slot `fi` (1-based) of inventory `from` to slot `ti` of `to`, like a click in Factorio: into an empty slot or onto the same item (as much as fits), or swap with a different item. `n` moves only that many (0 or absent: all). Roles: the character's `main`, `guns`, `ammo`, `armor`, `trash`, or the open screen's `chest`, `input`, `output`, `fuel`, `burnt`, `modules`, `cargo`, `ammo` (with `u`) |
| `xfer` | `from`, `fi`, `k`, `u`? | Factorio's Shift / Ctrl clicks on slot `fi` of inventory `from` (`LuaPlayer.stack_transfers`' four actions): `k` `stack` (Shift+click: that stack), `half` (Shift+right click: the smaller half, 18 of 37), `all` (Ctrl+click: every stack of that item, or of everything from an empty slot), `allhalf` (Ctrl+right click: the smaller half of each). From the character to the open screen's entity (with `u`; wherever an inserter would put it: fuel to fuel, ingredients to the input), from the screen to the character, and with nothing open from the main inventory to the gun, ammo and armour slots (other items stay: "Nowhere to put that") and back. With a player playing the character the game's own `stack_transfers` does it |
| `sort` | `inv` (`main`, or the open screen's role with `u`) | Sort and merge an inventory |
| `inv_filter` | `i` (main inventory slot), `item` (`""` clears) | Filter a slot of the character's main inventory (Factorio's middle click; `LuaInventory.set_filter`) |
| `qb_set` | `i` (1–100), `item` (`""` clears) | Put an item in a quickbar slot (10 pages of 10) |
| `qb_sel` | `i` (0 for none) | Select a quickbar slot; its item is what the character holds for building |
| `qb_page` | `p` (1–10) | Show a quickbar page |
| `cancel_craft` | `i` (queue index from `cq`), `n` | Take `n` crafts off a crafting queue entry; the ingredients come back |
| `research` | `name` | Start researching a technology, or queue it |
| `research_cancel` | `name` | Take a technology off the queue, or stop it if it is the current research |
| `plat_go` | `i` (platform index), `to` (space location name) | Travel there and stay: a one-stop schedule, and unpause. Only unlocked locations (`plat.dest`) |
| `plat_sched` | `i`, `l` (location names), `c`? (the record to head for, 1-based) | Replace the platform's schedule with these stops (no wait conditions); unknown names are dropped, an empty list clears it |
| `plat_pause` | `i`, `p` (1 pause, 0 resume) | Pause or resume the platform's thrust and schedule |
| `drop` | `item`, `x`, `y` (fixed) | Factorio's Z: one of the item from the main inventory into the entity there if it takes it, else onto a belt or the ground there (`spill_item_stack{allow_belts}`), within the character's `drop_item_distance` |
| `fast` | `u`, `p`, `x`, `y`, `item`?, `n`?, `q`?, `half` (0/1) | Fast transfer (Ctrl+click, also dragged across entities): with `item`, the held stack (`n` of it, else a full stack; half of that with `half`; quality `q`) from the main inventory into the entity wherever an inserter would put it; without, everything (half of each) from its output and burnt fuel, else what it holds (chest, trunk, cargo, a lab's science packs), into the character. On a belt the items go onto its lanes (`insert_at_back`) or come off them. Needs reach |
| `paste_settings` | `f` (`[u, p, x, y]` of the source), `u`, `p`, `x`, `y` (the target) | Shift+left click after Shift+right click: `LuaEntity.copy_settings`; items the old settings held come back to the character |
| `flip` | `u`, `p`, `x`, `y`, `v` (0/1) | H / V over an entity: toggles its `mirroring`; `v: 1` also turns it half way |
| `copy` | `x1`, `y1`, `x2`, `y2`, `cut` (0/1), `bp` (0/1) | Copies the area into the bridge's clipboard (a blueprint in a script inventory) and answers with `clip`; `cut: 1` also marks the area for deconstruction; `bp: 1` instead puts a new blueprint of it in the main inventory (Alt+B); with `bp: 1` and optional `to` (a main slot or -1) it goes into that blueprint instead, its label and description kept (the blueprint window's "Select new contents"), answered with `bp_ok` `new: 1` |
| `paste` | `x`, `y`, `d` | Builds the clipboard's ghosts centred there (`build_blueprint`, forced) |
| `alt` | `on` (0/1) | Alt-mode, the old way (clients from before issue #9, 0.1.1): while on, `ai` lists the icons near the focus once a second, at most 400. Newer clients don't send it: the icons come with the records (`extra.ai`) |
| `chat` | `text` | Says it in the game's chat (`game.print`, as "[3D]") and echoes it as `chat` |
| `set_inserter` | `u`, `f`?, `m`?, `use`?, `st`?, `sp`? | The open inserter's filters (`[item or "", ...]` by slot), mode (`whitelist` / `blacklist`), whether it uses filters (0/1), stack size override (0: none), spoil priority (`none`, `fresh-first`, `spoiled-first`) |
| `bonuses` | | Factorio's Bonuses window: answered by `bonus` |
| `perms` | | Factorio's Permissions window: answered by `perms` |
| `stats` | `kind` (`item`, `fluid`, `kill`, `build`, `pollution`, `electric` with `u`, `p`, `x`, `y` of a pole), `prec` (1–8, or 9 for "All"), `si`? (a surface index, 0 all; the character's by default), `g`? (names to draw graph lines for, `[]` the five busiest) | Statistics over a time scale (5 s, 1 min, 10 min, 1 h, 10 h, 50 h, 250 h, 1000 h; "All" has the 1000 h rates and graph, its rows chosen and ordered by all-time totals); answered by `stats` |
| `pedia_index` | | Factoriopedia's index; answered by `pidx` (see "Information windows") |
| `pedia` | `kind`, `name` | One Factoriopedia page; answered by `pedia` |
| `lnets` | | Every logistic network of the force; answered by `lnets` |
| `lnet` | `id` | One logistic network's robots and items; answered by `lnet` |
| `set_splitter` | `u`, `i`?, `o`?, `f`? | The open splitter's input and output priority (`left`, `none`, `right`) and filter (`""` none) |
| `set_bar` | `u`, `n` | The open chest's limit: machines may use its first `n` slots (its size: no limit) |
| `set_switch` | `u`, `on` (0/1) | The open power switch |
| `eq_put` | `kind` (`char` or `veh`), `u` (the vehicle, for `veh`), `fi`, `x`?, `y`? | One of the equipment in main inventory slot `fi` into the grid with its top left at `x`, `y`; without them wherever it first fits (Factorio's Shift+click). See "The character's gear" |
| `eq_take` | `kind`, `u`?, `x`, `y`, `ti`? | The equipment covering grid cell `x`, `y` back into main inventory slot `ti` when that is empty, else wherever it fits |
| `eq_move` | `kind`, `u`?, `x`, `y`, `tx`, `ty` | The equipment covering `x`, `y` moves so its top left is at `tx`, `ty` |
| `eq_toggle` | `kind`?, `u`?, `what` (`roboport` or `movement`), `on` (0/1) | Factorio's Alt+F (personal roboport: `allow_dispatching_robots`) and Alt+E (exoskeletons: the grid's `inhibit_movement_bonus`) |
| `respawn` | | The death screen's Respawn button: a player waiting on it (single-player) respawns now. The bridge's own character respawns by itself when its time is up |
| `set_panel` | `u`, `text`?, `icon`?, `show`?, `chart`?, `msgs`? | The open display panel's text and icon (a signal, `{}` none), always show in Alt-mode and show in chart (0/1), and its messages `[{text, icon, cond}, ...]`; see "Circuit network" |
| `set_cc` | `u`, `f` | The open entity's circuit and logistic connection settings: `{field: value}` with any of `gui.cc.f`'s fields; see "Circuit network" |
| `set_color` | `u`, `c` | The open lamp's, train stop's, locomotive's or spidertron's colour, `[r, g, b]` in 0-255 |
| `set_vehicle` | `u`, `lbl`?, `wo`?, `wi`? | The open spidertron's name (`entity_label`) and auto targeting without / with a gunner (0/1) |
| `set_artillery` | `u`, `on` | The open artillery turret's or wagon's "Auto targeting" (0/1) |
| `flush` | `u`, `pipe` | The open storage tank's or pipe's flush buttons: `pipe: 0` empties the entity (`remove_fluid`), `pipe: 1` its whole fluid segment (`clear_fluid_segment_fluid`) |
| `set_lamp` | `u`, `ao` | The open lamp's "Always on" (0/1) |
| `set_desc` | `u`, `text` | The open combinator's description |
| `set_speaker` | `u`, `vol`?, `mode`?, `poly`?, `vctl`?, `vsig`?, `inst`?, `note`?, `pitch`?, `stop`?, `al`? | The open programmable speaker, in `gui.spk`'s shape (`al` may hold any of its keys) |
| `set_pump` | `u`, `f` | The open pump's fluid filter (`""` none) |
| `set_targets` | `u`, `l`?, `ign`? | The open turret's priority targets (entity names, in order) and whether it ignores the rest (0/1) |
| `wire` | `k`, `a`, `b` | Wire tools: a red (`r`), green (`g`) or copper (`w`) wire between ends `a` and `b`, each `{u, p, x, y, mx, my}` (the entity, and where it was clicked: a combinator's output is on the side it faces, a power switch's left or right copper connector by side). Disconnects them if that wire is there already. Both must be in reach; the wire must reach (`can_wire_reach`); copper needs Electronics, red and green Circuit network researched. Both ends are sent again as `upd` |
| `wire_clear` | `u`, `p`, `x`, `y` | Removes every copper cable of a pole (Factorio's "remove pole cables") |
| `tile` | `item`, `x`, `y` (fixed: the brush's centre), `n` (brush size, 1–32), optional `ghost` (1), `r` (1) | Lays the item's tile (`place_as_tile_result`) under an `n`×`n` brush (odd sizes centre on the tile, even ones on the nearest tile corner) where its condition lets it go and nothing collides, one item each, within reach (`surface.set_tiles`, raising `script_raised_set_tiles`, so `tiles` follows). A mineable tile under it comes back as its item. `ghost: 1` places tile ghosts (`tile-ghost` entities) instead; `r: 1` lays hazard concrete's other direction (`next_direction`). See "Tiles, capsules and the rail planner" |
| `tile_mine` | `x`, `y`, `n` | Mines the placed tiles under the brush back into the inventory (`LuaControl.mine_tile`: the tile it was laid on returns) and removes tile ghosts there |
| `throw` | `item`, `x`, `y` | Uses a capsule at the target (`LuaItemStack.use_capsule`): grenades, cliff explosives (only with a cliff in their radius), poison, slowdown and robot capsules thrown if within the capsule's range; fish and other use-on-self capsules used on the character |
| `rails` | `item` (a rail planner), `l`: `[[entity, x, y, d], ...]`, optional `ghost` (1) | Builds the rail planner's path in order: rails, half-diagonals, curves, their elevated kinds, ramps and supports (only what the planner's `rails` and `support` are). Pieces already there are skipped; the rest are paid for from the inventory (`items_to_place_this`) while it lasts and in reach, ghosts after that (`msg` says how many). Nothing is built if a piece can't go where it should |
| `plat_board` | `i` | `i > 0`: move the character onto platform `i`, which must be stopped at the planet the character is on (where a rocket would take it). `i = 0`: drop from the character's platform to the planet it is stopped at. See "Space platforms" |
| `smap` | | Asks for the solar system; answered by `smap`. See "Space Age's screens" |
| `plat_new` | `planet`?, `q`? | A new platform over the planet (default: the character's), waiting for one of the character's starter packs (`create_space_platform`) |
| `set_section` | `u`, `i` (0 adds one), `del`? 1, `f`?, `g`?, `on`?, `m`? | The open hub's, landing pad's, rocket silo's or requester / buffer chest's logistic section `i` (`g` on an existing section puts it in that logistic group, a new name makes one, `""` takes it out): its filters (`[[item, quality, min, max (-1 none), import from ("" anywhere), minimum delivery (-1 default)], ...]`), group, on/off, multiplier; `del: 1` removes it. `u: 0` is the character's own requester point (its sections in `clog.sec`) |
| `set_hub` | `u`, `prov`? 0/1, `pa`? 0/1 | The open hub: provide to other platforms; pause the platform |
| `set_silo` | `u`, `auto` 0/1 | The open rocket silo: send to orbit automatically |
| `silo_launch` | `u`, `to` (platform index) | Launch the open silo's ready rocket to a platform orbiting this planet: to its hub, or the starter pack it waits for |
| `ride` | `u`, `to` (platform index) | Get into the open silo's ready rocket and ride it up to platform `to`'s hub (the platform orbits this planet and has a hub; the silo is within reach) |
| `set_pad` | `u`, `read`?, `req`?, `empty`? (0/1) | The open landing pad's circuit settings: read contents, set requests, read empty slots |
| `set_collector` | `u`, `f` | The open asteroid collector's chunk filters (`[chunk or "", ...]` by slot) |

## Mod → client

Messages marked **R** are reliable.

| `t` | | Fields |
|---|---|---|
| `welcome` | R | `v`, `mod` (version), `surface`, `si` (surface index), `pf` (the platform's index, on a space platform) or `planet` (the planet's name, on a planet's surface), `u` (the controlled character's unit number), `x`, `y`, `mp` (on a server) |
| `surface` | R | `surface`, `si`, `pf` or `planet` as in `welcome`, `x`, `y`, `view`?: the character is now on another surface, there. See "Space platforms". With `view` = 1 the character hasn't moved: the remote view looks at that surface (`view`), so the world is that surface's round (`x`, `y`) and the avatar isn't drawn; a `surface` without `view` brings the character's world back |
| `protos` | R | `part`, `parts`, `l`: `[[id, name, type, x1, y1, x2, y2, r, g, b, tile_w, tile_h], ...]`. Box = selection box (tiles, north-facing); colour = map colour |
| `tprotos` | R | `part`, `parts`, `l`: `[[id, name, r, g, b], ...]` |
| `fprotos` | R | `part`, `parts`, `l`: `[[id, name, r, g, b], ...]`: fluid prototypes with their base colour, for `fl` |
| `iprotos` | R | `part`, `parts`, `l`: `[[id, name], ...]`: item prototypes, for `bi`, `ih` and `gi`. An item that builds an entity of another name has it third: `[id, "rail", "straight-rail"]` |
| `ready` | R | Prototype dictionaries are complete |
| `eprops` | R | `l`: `[[proto id, underground reach, wire reach, supply area, overlay?], ...]` for underground belts and pipes-to-ground (their `max_underground_distance`, tiles) and electric poles (`get_max_wire_distance()`, and `get_supply_area_distance()`: half the side of the square they power), for the build cursor's previews. `overlay` (optional) is what hover and the build cursor draw, for the entity facing north: `ip`, `id` an inserter's pickup and drop vectors `[x, y]` from its centre; `lr`, `cr` a roboport's logistic and construction radius; `mr` a mining drill's mining radius and `vp` where it drops (also on an assembling machine or furnace that puts its results out, a recycler: Alt-mode's arrow, issue #9); `fb` fluid connections `[[x, y, direction the pipe leaves by, "i"\|"o"\|"b" (input, output, both)], ...]` (ordinary ones the game shows), `fo: 1` when those show only while the recipe needs fluid; `cw` how far a circuit wire reaches from it (`get_max_circuit_wire_distance()`) and `ww` a power switch's copper wire reach, for the wire tools. Entries with only an overlay have 0 reaches. Right after `ready` |
| `iuse` | R | `part`, `parts`, `l`: `[[item, kind, ...], ...]`: what items do besides building their entity. `"t"` tiles: `[item, "t", tile, other direction's tile or "", [tile ids it may go on]]` (from `place_as_tile_result`'s condition, `invert` and `tile_condition`); `"c"` capsules: `[item, "c", action type ("throw", "destroy-cliffs", "use-on-self", ...), range, radius]`; `"r"` rail planners: `[item, "r", support entity or "", elevated rails allowed (0/1, the force's rail_planner_allow_elevated_rails)]`; `"b"` belts: `[item, "b", their underground belt's item]` (`related_underground_belt`); `"p"` pipes: `[item, "p", their pipe-to-ground's item]`; `"m"` modules: `[item, "m", module category]` (clicked on a building or ghost they go in or are asked for, `modreq`). Right after `eprops` |
| `chunk` | R | `cx`, `cy`, `tiles` (run-length `[id, count, ...]`, row by row, 1024 tiles), `parts`. Or `none: true` if the chunk isn't generated yet |
| `ents` | R | `cx`, `cy`, `part`, `parts`, `e`: entity records. Replaces the chunk's entities |
| `dprotos` | R | `part`, `parts`, `l`: `[[id, name], ...]`: decorative prototypes (grass, flowers, small rocks), only for a client with `dc`; in the handshake before `ready`, or when it turns `dc` on |
| `dec` | R | `cx`, `cy`, `part`, `parts`, `l`: `[decorative id, x, y, amount, ...]`, x and y the tile within the chunk (0-31), amount 1-255. After the chunk's `ents`, for a client with `dc`; replaces the chunk's decoratives (an empty list clears them). Sent again within half a second when tiles are placed or mined in the chunk or something is built in it (both remove decoratives; nothing says which), and with the chunk's periodic refresh, which also picks up `destroy_decoratives` by other mods |
| `add` / `upd` | R | `e`: one entity record |
| `del` | R | `u`, `p`, `x`, `y` |
| `tiles` | R | `l`: `[x, y, tile id, ...]` in whole tiles |
| `st` | R | `l`: `[unit, state, ...]`: machines that started or stopped working (1 working, 0 not); for rail and chain signals their colour (1 green, 2 yellow, 3 red, 4 blue: a chain signal with only some exits open), accumulators 1 charging, 2 discharging, 0 neither, power switches 1 on, 0 off |
| `inv` | R | `l`: `[[item, count], ...]`, sent when it changes |
| `recipes` | R | `l`: hand-craftable recipe names, sent when they change |
| `slots` | R | `l`: `{role: [slot, ...]}` for the character's inventories it has (`main`, `guns`, `ammo`, `armor`, `trash`), every slot in order; a slot is `[item, count]`, `[item, count, quality]` (not normal quality), `[item, count, quality, freshness]` for an item that spoils (freshness in thousandths, 1000 fresh; quality then always given) or `0` when empty. Machine screens' `slots` use the same form. Sent when anything changes (checked twice a second) and right after `move` or `sort`. `fl`: `[[slot, item], ...]`, the main inventory's slot filters, when it has any. `ic`: `[[slot, [[signal type, name], ...]], ...]`, the icons of the main inventory's blueprints, books and planners that have any (`preview_icons`, in order), which Factorio draws over the item |
| `qb` | R | `p` (page), `sel` (selected slot or 0), `held` (its item or `""`), `l`: 100 item names, `""` when empty. Sent at the handshake and after each quickbar command; in single-player the quickbar is the player's own (`get_quick_bar_slot`), also resent when it changes in the Factorio window |
| `clog` | R | `on` (1/0), `trash` (1/0), `l` (requests `[[item, min, max (-1 none), quality?], ...]`, every active section's), `sec` (its logistic sections one by one, as the hub's `sec`: `[{i, g, on, m, man, f}, ...]`; edited with `set_section` `u: 0`), `lgs` (the force's logistic group names): the character's logistic requests, at the handshake and when they change |
| `ccol` | R | `c`: the character's colour `[r, g, b]` in 0-255, at the handshake and when it changes |
| `planet` | R | `name` (`space` on a platform), `props` (surface properties: `gravity`, `pressure`, `magnetic-field`, `solar-power`, ...), `day` (ticks per day), `always` (1/0), `mb` (minimum brightness), `sol` (solar power multiplier), `dusk`, `evening`, `morning`, `dawn` (thousandths), `heat` (`[[entity proto id, heating radius], ...]`): at the handshake and on every surface change; see "Planets" |
| `rdet` | R | `part`, `parts`, `l`: `[[name, energy (s), categories, group, group order, subgroup, subgroup order, order, ingredients, products], ...]` for every enabled hand-craftable recipe; ingredients and products are `[[type, name, amount], ...]` (products' amount is the expected amount: probabilities and ranges averaged). At the handshake and when research changes the list |
| `craftable` | R | `l`: `[[recipe, count], ...]`: how many the character could craft now, non-zero only. Sent when it changes |
| `techs` | R | `part`, `parts`, `l`: `[[name, order, prerequisites, ingredients [[name, amount], ...], unit count, seconds per unit, state, trigger, effects, level, max level, trigger detail, saved progress, count formula, essential], ...]`; state 0 locked, 1 available, 2 researched; trigger is how a technology without science packs is unlocked (`craft-item`, `mine-entity`, ...) or `""`; effects `[[type, recipe or modifier target, value], ...]` (`unlock-recipe` with the recipe, bonuses with their modifier); max level -1 for infinite technologies (the level is the one being researched); trigger detail `[type, item or entity, count]` or `[]`; saved progress in thousandths (a stopped research's); the count formula of infinite technologies or `""`; essential 1 for the technologies Factorio's "Show only essential technologies" keeps, else 0. Older mods sent the first 8 or 14 values. Hidden technologies and disabled ones that aren't shown are left out. At the handshake and when research finishes or is undone |
| `guns` | R | `sel` (selected gun slot, 1-based), `l`: `[[gun, ammo, magazines, rounds, magazine size], ...]` one per gun slot, `""` and 0 when empty; rounds are what is left in the magazine in use (`LuaItemStack.ammo`) and the size is the ammo's `magazine_size`, for the ammo slot's green bar (older mods send only the first three). Sent when it changes (so after each shot while firing) |
| `me` | | `u`, `x`, `y`, `d`, `w` (walking), `hp`, `q` (crafting queue), `mhp` (max health), `sh` (1 while firing), and while mining `m` (0–100), `mx`, `my`. While walking at an angle, `a` (the `walk` command's, thousandths of a turn): the client draws the character along it rather than along the zig-zag. In a vehicle, `v` (its unit number) and `vs` (its speed in thousandths of a tile per tick, negative in reverse), and `x`, `y` are the vehicle's. With shields in the armour, `sd` and `msd` (its shield and most shield, whole points). Inside a space platform's hub, `hub` (its unit number): the character can't walk, builds ghosts and opens the platform's buildings as from the remote view. Riding a rocket or cargo pod, `pod` (its unit), `ps` (`cargo_pod_state`: `awaiting_launch`, `ascending`, `surface_transition`, `descending`, `parking`...), `up` (1 leaving this surface, 0 arriving) and `gx`, `gy`: the ground point the flight is seen from (where it set off, or where it comes down); `x`, `y` are the pod's, which Factorio moves north of that point by its height. See "Riding to a platform" |
| `eq` | | `kind` (`char`: the armour's grid; `veh`: the grid of the vehicle the character has open or sits in), `u` (its owner's unit, 0 none), `w`, `h` (0 without a grid), `l`: `[[name, x, y, w, h, quality, energy (J), max energy, shield, max shield, ghost 0/1], ...]`, and with a grid `sh`, `msh` (shields), `bat`, `mbat` (energy in batteries, J), `gen` (power made, W), `mv` (movement bonus, thousandths), `inv` (inventory bonus), `mvon` (exoskeletons on), `nv` (powered night vision), `rb` (personal roboports on, when the owner can have them). Twice a second when it changed, at once after a command, at least every 5 s |
| `cinfo` | | The character tab: `craft`, `mine`, `run` (crafting, mining and running speed, thousandths of normal), `speed` (running speed now, thousandths of a tile per tick), `eqmv` (equipment's movement bonus, thousandths), `reach`, `build`, `rreach`, `pick`, `loot`, `drop` (distances, tenths of a tile), `invb` (bonus inventory slots), `eqinv` (from the armour), `slots` (main inventory size), `trash`, `hp` (max health), `hpb` (health bonus), `robots` (follower robot bonus). Once a second when it changed |
| `dead` | | `left` (ticks until the respawn; 0 waiting for the Respawn button), `x`, `y` (where it died): every half second while the client's character is dead. No `me` meanwhile; the respawned character is a new one, so a new `welcome` follows |
| `bonus` | | `l`: `[[kind, value, [item names]], ...]`: the bridge's force's bonuses that aren't zero, after `bonuses`. Kind is a LuaForce modifier (`inserter_stack_size_bonus`, `mining_drill_productivity_bonus`, `laboratory_speed_modifier`, `worker_robots_speed_modifier`, ...), `ammo_damage:<ammo category>`, `gun_speed:<ammo category>` or `turret_attack:<turret>`; the value as the API gives it (fractions for modifiers, counts for bonuses); the items are the ones Factorio draws over that bonus |
| `perms` | | `me` (the permission group of the client's player, `""` for the bridge's own character), `l`: `[[group name, [player names]], ...]` Factorio's permission groups, after `perms` |
| `pl` | | `me` (the player the client plays, 0 for the bridge's own character), `u` (the client's character), `l`: `[[index, name, connected 0/1, r, g, b, character unit (0 none), surface, admin 0/1, afk ticks, tag, armour], ...]` every player of the game. `armour` is the item in the character's armour slot ("" none): the client draws that armour's look on the character (light armour plain, heavy and modular the level 2 look, power armour MK1/MK2 level 3, mech armour the mech); older mods leave it out. Once a second when it changed |
| `mv` | | `part`, `parts`, `l`: `[[unit, proto, x, y, orientation?], ...]`, every 2 ticks within the focus (`f3d-mover-interval`, longer at a `rate` level). `p`, optional: ticks between updates, so the client draws movers far enough behind to glide over the whole gap. Delta-coded for a client that asks |
| `bi` | | `part`, `parts`, `l`: `[unique id, item id, x, y, ...]` flat: every item on a belt within `f3d-detail-radius` (or the client's `bfar` `n`) of the focus, every `f3d-detail-interval` ticks (default 6). Parts of one update share `k`; an empty update means no items. `fx`, `fy` (1/256 tile) and `fr` (tiles), optional: the square the update covers, its centre and half side, where the client hands over to far lane icons: the update holds the items of every belt whose centre is less than `fr` from (`fx`, `fy`) in x and in y, and the client draws lane icons only for the belts outside. `p`, optional: ticks between updates (longer at a `rate` level, and on a big base, where an update is read over several ticks, a few milliseconds a tick: about half a second apart for 6,000 items): the client draws items about that far behind the game, so they glide evenly. Every position is where the item is on tick `k` (items read on earlier ticks of the update are carried on at the speed they moved), and an item read last time but not this time (it moved on to a belt read earlier, or was taken off) is carried on along its way for one update. Delta-coded for a client that asks (see "Delta-coded lists"). For a client whose hello says `bl`, only lanes that changed are sent: each lane (a belt's transport line) is checked by its item count and its front and back items' positions, and read and sent in full only when that differs from its last read, once more after a change (to see it settled), and every 64 updates; otherwise it is held. `ln`: `[lane key, count, ...]`, which lane each run of the part's items came from, in order (key = the belt's unit number × 8 + line index; key 0: an item carried on, in no lane), counts adding up to the part's items; each part also lists first, with count 0, the lanes read with nothing to send since the part before (a last part with no items may carry only those). `dl` (first part): lanes no longer read (out of the square, the belt gone). `st`, optional: `[unique id, size, ...]`, the part's items that are stacks of more than one (2-4: a stack inserter puts up to 4 in one place, one entry on the belt); the others are single items. A lane is checked by its item count too, so a stack an inserter takes part of is sent again. The client keeps the items of a lane not in an update where they are (a backed-up belt holds still), lets an item go when its lane is sent again without it, and drops a `dl` lane's items at once |
| `ih` | | `part`, `parts`, `l`: `[unit, hand x, hand y, held item id or 0, ...]` flat: every inserter within the same radius, every `f3d-detail-interval` ticks (longer at `rate` level 3). `p`, optional: ticks between updates. Delta-coded for a client that asks |
| `gi` | | `part`, `parts`, `l`: `[item id, x, y, ...]` flat: every item lying on the ground (`item-entity`) within the same radius, every 30 ticks, or at the `bi` interval while the character is picking up. Parts of one update share `k`; an empty update means none |
| `fl` | | `part`, `parts`, `l`: `[unit, box, fluid id, amount, capacity, temperature, ...]` flat: every fluid box with fluid in it (pipes, tanks, pumps, boilers, machines...) within `f3d-detail-radius` of the focus, once a second |
| `pw` | | `part`, `parts`, `l`: `[unit, 0, 1 or 2, ...]` flat: electric machines near the focus with no power (0), low power (1) or not connected to any pole (2), once a second; the rest have enough |
| `ht` | | `part`, `parts`, `l`: `[unit, temperature, ...]` flat: heat pipes, reactors and heat interfaces within `f3d-detail-radius` of the focus, in whole °C, once a second |
| `sky` | | `d`: daytime in thousandths (0 noon, 500 midnight), `n`: darkness in thousandths (0 in daylight, ~850 at night). Once a second |
| `msg` | | `text`: something to show the player ("Out of reach"). When research finishes, also `tech` (its name) and `unlocks` (the recipes it unlocks), so the client can say it in the player's language |
| `hp` | | `part`, `parts`, `l`: `[unit, health in thousandths, ...]` flat: every damaged entity near the focus, every 10 ticks. Entities at full health are left out; an empty update means none |
| `tf` | | `u` turret unit, `w` (`bullet`, `laser` or `flame`), `sx,sy` turret position and `x,y` target position in 1/256 tiles; sent when an ammo, electric or fluid turret actually damages a target |
| `ts` | | `l`: `[[unit, orientation, shots, gun, target x?, target y?], ...]`, every 6 ticks (turrets.lua): turrets (ammo, electric, fluid, artillery) and armed vehicles (car, tank, spidertron, artillery wagon) near the focus that have a target, fired or turned since the last report, and every one of them every 120 ticks. `orientation` in thousandths of a turn (0 north, 250 east): the weapon's (`LuaEntity.orientation`; an artillery turret's `relative_turret_orientation`), a vehicle's turret relative to its body (`relative_turret_orientation`), a spidertron's torso (`torso_orientation`). `shots` since the last report, from the ammo inventory going down (turret, car, spider and artillery ammo) or, for electric and fluid turrets, 1 when they hit something. `gun` a vehicle's `selected_gun_index` (0 for turrets). Target x, y (1/256 tiles): the turret's `shooting_target`, or where a vehicle's gunner shoots (`shooting_state`); left out without one. A turret missing from reports has no target |
| `afx` | | `fx` (`blood` or `burn`), `u` damaged character/unit number (0 for player character without one), `x,y` hit position in 1/256 tiles; immediate, for local creature/player hit effects |
| `en` | | `l`: `[unit, target x, target y, ...]` flat: enemies near the focus that are attacking, every 10 ticks: units (biters, spitters) in range of the target of their attack command or distraction, and worms (`turret`) with a shooting target; target positions in 1/256 tiles. Not sent while none attack; the client lets an attack lapse when its unit stops being listed (0.5 s). Old clients ignore it |
| `died` | | `u` (0 without a unit number), `p`, `x`, `y`: something died near the focus. A static entity also gets its `del` |
| `cq` | | `pr` (the first entry's progress in thousandths), `l`: `[[index, recipe, count, prerequisite 0/1], ...]`: the crafting queue, every 10 ticks while it has something in it and once when it empties |
| `rs` | | `cur` (the technology being researched or `""`), `pr` (its progress in thousandths), `q` (the research queue), `labs` (`[[unit, status name], ...]` for labs near the focus: `working`, `missing_science_packs`, `no_research_in_progress`, `no_power`...): once a second and after research commands |
| `chart` | | `cx`, `cy`, `n`, `pal`, `px`, `ov`?, `si`: one chunk of the map and its map view layers, after `map`; see "Map" |
| `terr` | `si` | `part`, `parts`, `l`: `[[x1, y1, x2, y2, ...], ...]`: every demolisher territory on the world's surface (`si`, the character's or the remote view's) as its chunk coordinates (Vulcanus); after the handshake, a surface change, and once a minute (territories grow as the planet is explored); an empty `l` clears them |
| `unghost` | | `q` (the request's), `n` (ghosts removed, 0 or 1): the answer to `unghost`; with 0 the client adds a tag there instead |
| `hinfo` | | `q`, `u` (the request's), and what Factorio's entity info shows: `eff`? `{sp, pr, co, po, q}` in thousandths (`LuaEntity.effects`: a machine's total from its modules and beacons; a beacon's its modules' sum before the distribution effectivity, as 2.1.23 reports it), `m`? its modules `[[name, count, quality?], ...]`, `b`? the beacons reaching a machine (`get_beacons`), `n`? the machines a beacon reaches (`get_beacon_effect_receivers`), `de`? a beacon's distribution effectivity (thousandths), `el`? `{e, b, mx, mn}` for something that draws electricity (not generators or accumulators): the joules in its buffer and the buffer's size (Factorio's Electricity bar), its Max. consumption (watts: the most it draws with its modules and beacons, plus its drain) and Min. consumption (its drain, watts), `rn`? `[x, y, ...]` for a roboport: the roboports its logistic cell is joined to (`LuaLogisticCell.neighbours`), in 1/256 tiles, which the client links it to. Nothing but `q` and `u` when there is no such entity |
| `cmdr` | | `id` (the request's), `l` (the answer's lines, strings), `ok` = 0 when the bridge doesn't run that command: the answer to `cmd` (reliable) |
| `mtr` | | `si`, `part`, `parts`, `l`: `[x, y, orientation, length, width, colour, ...]`, six integers per carriage that a working radar covers or within 96 tiles of the character (as Factorio's map shows trains only where it sees them): its centre (1/256 tile), its orientation in 1/1000 turns, its collision box's length and width (1/256 tile), and its map colour `0xRRGGBB` (the carriage's own colour, else Factorio's locomotive red or a wagon grey). Several parts on a big network; an empty `l` means none. The first part has `cov`: `[cx, cy, d, ...]`, each working radar's chunk and how many chunks round it it reveals (`max_distance_of_nearby_sector_revealed`); the map dims charted chunks outside these squares and the 96 tiles round the character. The mod looks for radars at most every 5 s |
| `tags` | | `l`: `[[id, x, y, text, icon type, icon name], ...]`, `si`: every map tag on the surface ("" for no icon); after `map`, tag commands and tag changes in the game |
| `trl` | | `part`, `parts`, `l`: Factorio's trains overview, after `trains_list`; see "Trains" |
| `spd` | | `l`: `[[unit, [[x, y], ...]], ...]`: each spidertron's queued autopilot waypoints (fixed), after `spider_go` and `spider_q` |
| `surfs` | yes | `l`: `[[index, name, planet, platform name, platform index], ...]`: the surfaces the map can show (planets, the force's platforms, then any other surface with planet and platform name both `""`: Factorio's "Other"); see "Map" |
| `tr` | | `l`: `[[train id, state, manual 0/1, speed, stop unit, destination, [carriage units]], ...]` for trains with a carriage near the focus, every 30 ticks; see "Trains" |
| `ln` | | `id` (0 outside any network), `log`, `con` (`[available, all]` logistic and construction robots): the logistic network the character stands in, once a second |
| `rc` | | `l`: `[unit, item id, count, ...]` flat: robots within `f3d-detail-radius` of the focus that carry something, every 10 ticks |
| `plat` | | `on` (index of the platform the character is on, 0 on a planet), `here` (the planet's name, on a planet), `dest` (space locations platforms can be sent to), `l`: the force's platforms; see "Space platforms". Once a second while the force has platforms or the character is on one, else every 10 s |
| `seg` | | `l`: `[[unit, proto id, [segment proto id, x, y, orientation, ...]], ...]`: segmented units (demolishers) with a segment near the focus, head first, every 2 ticks |
| `lt` | | `l`: `[[x, y, caught 0/1], ...]`: lightning strikes near the focus, each once; where it hit (an attractor's position when caught, otherwise within 15 tiles in x and 3 in y) |
| `legs` | | `l`: `[[unit, [x, y, ...]], ...]`: the feet of spider units (pentapods) and spidertrons near the focus, every 4 ticks |
| `pg` | | `l`: `[unit or 0, x, y, growth, ...]` flat: plants within `f3d-detail-radius`, growth in thousandths, once a second |
| `sp` | | `l`: `[unit, units out, ...]` flat: spawners (biter nests, egg rafts) near the focus, once a second |
| `fz` | | `l`: units of frozen machines near the focus (Aquilo), once a second |
| `cp` | | `l`: `[[unit, state, destination type, destination surface], ...]`: cargo pods near the focus, every 10 ticks |
| `rk` | | `u` (silo unit), `x`, `y`, `s` (surface): a rocket launch was ordered |
| `pst` | | `i`, `st`, `old` (space_platform_state names), `loc` (where it is, `""` travelling): a platform's state changed |
| `bf` | | `part`, `parts`, `l`: `[unique id, freshness, ...]` flat: spoiling items on belts (with `bi`), freshness in thousandths |
| `bq` | | `l`: `[[unique id, quality], ...]`: belt items better than normal (with `bi`); one empty list clears them |
| `bfar` | | `cx`, `cy`, `l`: `[x, y, direction, lane 1 item id, lane 2 item id, ...]`, five integers per belt in that chunk carrying anything (x, y its centre in 1/256 tile; item ids from `iprotos`, 0 an empty lane, by the item that lane carries most of). `c`, optional: `[lane 1 count, lane 2 count, ...]`, how many items each lane of each belt in `l` holds (0-4), so a full belt is drawn full. `h`, optional (only when some lane has stacks): `[lane 1 height, lane 2 height, ...]`, how high each lane's icons are piled (1-4: its items over its icons, rounded up), where stack inserters put more items on a lane than it has icons. For drawing lanes far away as icons of what they carry: sent while the client asks (`bfar` command), for subscribed chunks within that distance, read a few hundred belts per tick round and round, a chunk only when what it carries changed; an empty `l` clears the chunk |
| `wb` | | Once a second: `b` the work budget per tick (units), `avg` and `max` the units used per tick over the last `n` ticks, `over` how many of them went past `b` (a job's last slice), `q` `{name: length}` the queues still waiting (`chunks`, `map`, `reqs`, `radars` surfaces still being scanned, `techs` parts). See "Work budget" |
| `mrp` | | `si`, `q` (the ask's), `part` (from 1), `last` (1 on the final part), `l`: `[x, y, logistic radius, construction radius, ...]`, four integers per roboport (1/256 tile), up to 500 a part, from the force's logistic networks' cells (personal roboports left out). The map's logistic layer draws each one's two squares, and a chunk whose centre lies in a construction area counts as seen, as a radar's: not dimmed on the map, no fog over it in the 3D remote view |
| `lpad` | | `si`, `q` (the ask's), `x`, `y` (1/256 tile): the force's cargo landing pad on that surface (the lowest unit number found); no `x`, `y` when there is none. The map view centres there unless it was moved meanwhile |
| `cov` | | `si`, `l`: `[cx, cy, d, ...]`, and `x`, `y` (1/256 tile), `cr` (tiles) when the character is on that surface; `all` = 1 on a space platform (everything seen). While the client's `focus` has `rv` = 1, about once a second (and as it turns on): what the 3D remote view sees on the surface it shows. Each working radar's chunk and how many chunks round it it reveals, and the character's place: a chunk whose centre is within `cr` + 16 tiles of it is seen. The client greys out the rest and hides moving things there, except where a roboport's construction area reaches (from `mrp`) |
| `raise` | | none: the player pressed "Show in Zenith" (Ctrl+F9, the mod's custom input) in the real game, joined to the same world; the client playing their character brings its window to the front |
| `ach` | | `l`: `[[chunk name, x, y, vx, vy], ...]`: asteroid chunks near the focus on a platform every 10 ticks, movement in 1/256 tile per second; one empty list clears them |
| `acol` | | `l`: `[[unit, arms, arm speed, moving 0/1/2, [chunk filter, ...]], ...]`, `g`: `[[unit, chunk name, x, y], ...]`, either or both, every 10 ticks on a platform: the asteroid collectors near the focus (up to 64) when that list changes and every 2 s, and the chunks each caught. Arms: the prototype's `arm_count_base` plus one per quality level; speed in 1/1000 tile a tick (`arm_speed_base` plus 0.05 per level, times `unpowered_arm_speed_scale` on low power); moving 1 working (or slowed by low power), 0 held where they are (a full output), 2 switched off (no power, the circuit network, a script, marked for deconstruction): the arms fold back home; no filters takes every chunk. A caught chunk is one that was in the collector's catch circle (`collection_radius` 7.5 round a point `collection_box_offset` 5 tiles in front, plus the head's 0.6) and is gone from where its movement took it, at that place; 2.1.23 removes it the tick the arm's head reaches it. One empty `l` clears them off a platform |
| `smap` | | `loc`: `[[name, type, x, y, unlocked 0/1, has surface 0/1, magnitude, draw orbit 0/1, label orientation], ...]` (star map position, the prototype's `magnitude` and `label_orientation` in thousandths; older mods send the first six), `con`: `[[from, to, length km, danger 0-1000], ...]`: the solar system, answering `smap` |
| `aiu` | R | `l`: `[[unit, icon type, name, more?] or [unit, ""], ...]`: Alt-mode icons that changed with no new record (issue #9); `""`: it shows none now. The mod watches furnaces (their recipe follows what is put in) and the machines with a red or green wire (a circuit network may set their recipe or filters), a few a tick under the work budget (a round at most every 2 s); it also checks the client's open screen's entity twice a second and when it closes, and an entity after `on_gui_closed` or `on_entity_settings_pasted` in the real game. Scripts that change the others are seen when the chunk is next sent. `fa` (with every row): `[[unit, fluid mask 0-3], ...]`, the new `extra.fa` of each (0: none) |
| `ai` | | `l`: `[[unit, icon type (item, fluid, recipe), name, more?], ...]`: (only for `alt`, clients from before issue #9) Alt-mode icons near the focus (an assembler's or furnace's recipe, an inserter's, splitter's, loader's, mining drill's or storage chest's filter), once a second while `alt` is on; `more`: an inserter's or loader's other filters' item names, when it has several (all are drawn, shrunk to fit) |
| `clip` | | `l`: `[[proto id, x, y, direction], ...]`: the clipboard's entities after `copy`, positions relative to its centre (fixed); empty when nothing was copied |
| `bp` | R | `q` (the request's), `part`, `parts`, `s` (this part of the exchange string), `item` (the stack's item, `""` for a library record), `i` (the slot asked about), optional `err` (nothing there: `s` is empty), `src` and `ix` (a library record) |
| `bp_ok` | R | `q`, `i` (the slot the string went into; -1 the library stack), `item`, optional `new` (1: a blueprint Alt+B's area just made, whose window the client opens) |
| `bpl` | R | `src` (`game` / `player`), `who` (the player's name, `""` for the game's), `l`: `[[index, item, label, [[icon type, name], ...]], ...]` |
| `hist` | R | `h` (id), `what` (`blueprint`, `deconstruction`, `cancel deconstruction`, `upgrade`, `cancel upgrade`, `settings`, `rotation`): an action the mod remembers for undo |
| `quals` | R | `l`: `[[name, level, unlocked (0/1), colour "rrggbb"], ...]`, lowest level first, hidden qualities left out: what the client cycles through for `build`'s `q`. With the handshake and after research changes |
| `chat` | | `from` (a player's name, "3D" for this client's lines), `text`: a line of the game's chat (`on_console_chat`), `c`? the player's chat colour `[r, g, b]` (0–1). The text is Factorio rich text (`[item=…]`, `[gps=x,y,surface]`, `[color=…]`…); the client draws it |
| `stats` | | `kind`, `prec` as asked, `si` (the surface, 0 all; not for `electric`), `l`: `[[name, in, out, in total, out total], ...]`, at most 60, busiest first. `in` / `out` are `get_flow_count` rates per minute averaged over the time scale (items: produced / consumed; kills: kills / losses; build counts: built / removed; pollution: emitted / absorbed; electric: consumption / production in joules per minute); totals are all-time. With `g` in the request, `gr`: `[[name, [in...], [out...]], ...]`, 60 points each (every 5 of the 300 samples averaged), oldest first. `electric` also has `st`: `[[name, stored, stored now], ...]`, the network's accumulators by prototype (`storage_counts`; joules averaged over the time scale, and now), and `ef`?: `[met, demand, used, available, stored, capacity]`, the network's last update in joules per tick (2.1's `LuaElectricNetwork.flow_last_tick`: `maximum_consumption` × `consumption_satisfaction`, `maximum_consumption`, `maximum_production` × `production_satisfaction`, `maximum_production`, `accumulator_energy`, `accumulator_capacity`) for Factorio's three summary bars |
| `al` | | `l`: `[[kind, count, [[x, y, surface index, name, unit, subject?], ...]], ...]`: the force's alerts once a second (see "Information windows") |
| `pidx` | R | `part`, `parts`, `l`: `[[kind, name, group, subgroup, order], ...]`, `g` (first part): `[[group, order], ...]`: Factoriopedia's index, on request |
| `pedia` | | `kind`, `name`, `found` (0/1), `d`: one Factoriopedia page, on request |
| `lnets` | | `l`: `[[id, surface index, surface name, [logistic available, all], [construction available, all], cells, storages, providers, requesters, x, y, name], ...]` on request |
| `lnet` | | `id`, `found` (0/1), and when found `log`, `con` (`[available, all]`), `items` (`[[item, count, quality?], ...]`, most first, at most 200), on request |
| `gui` | | The open machine screen, every 30 ticks and right after a command: `u`, `p` (proto id), `kind`, `inv`, `slots` (role -> slot list, as in `slots`), `status`, `fb`, `pw` (see "Fluids and power"), and for crafters and furnaces `recipe` (absent when none) and `pr` (crafting progress in thousandths); crafters also get `rl` with the first message and every 10th; entities with module slots and requested modules `mrq` (each module slot's requested module, "" for none; `modreq`); a screen opened from the remote view out of reach `far` = 1 (items can't move; modules are asked for); combinators `cb`, entities on a circuit network `sig` (see "Circuit network"); rolling stock `tr`, train stops `stop` (see "Trains"). Or `u`, `closed: true` when the mod closed it |

An **entity record** is `[unit or 0, proto id, x, y, direction, extra?]`. `extra` is an object:
`{"s": "s"|"l"|"r"}` belt shape (straight, left or right curve), `{"u": "i"|"o"}` underground
belt input/output, `{"a": amount}` ore remaining, and `"q"`: the entity's quality when it isn't
normal (`{"q": "rare"}`, added to any of these), and wires: `"w"` (copper), `"r"`, `"g"` (circuit),
each a list of the unit numbers at the other ends (a wire may be listed by one end only).
`"gh"`: on an entity ghost, the prototype id of the entity it stands for (a ghost of an
underground belt also has `"u"`); `"tg"`: on a tile ghost, the tile id it stands for; `"d": 1` marked for
deconstruction; `"up"`: marked for upgrade, the target's prototype id. `"pc"`: on pipes,
infinity pipes and pipes-to-ground, the sides they connect on as a bitmask (1 north, 2 east,
4 south, 8 west; ordinary connections to something, not a pipe-to-ground's underground side).
`"col"`: on locomotives, wagons and train stops, the colour the player gave it, `[r, g, b]` 0-255.
`"n"`: a train stop's name. `"co"`: a cliff's `cliff_orientation` (`"west-to-east"`, `"north-to-west"`,
`"none-to-south"`, ...): the edges of its 4x4-tile cell it runs between, the high ground on its left;
the client picks and turns the matching cliff piece. Old clients ignore it.
A linked belt carries `"u"` like an underground belt (its `linked_belt_type`). `"rm"`: on
remnants (a `corpse` named "...remnants" that a building leaves when destroyed, and
`rail-remnants`), the prototype id of what left them (the entity of the same name, else the only
one listing it in `corpses`), 0 when several share them (`small-remnants`); the client draws that
entity's model broken. Remnants come in chunk snapshots and an `add` when a building dies
(`on_post_entity_died`); biters' and trees' corpses aren't sent. They vanish in the game without
an event (after their time, or when something is built over them): the client drops those under
a newly added entity, and the chunk refresh catches the rest. Old clients draw them as boxes.
`"ai"`: Alt-mode's icon (issue #9), `[icon type, name]` or `[icon type, name, [more names]]` like an
`ai` row without its unit: an assembler's, furnace's or rocket silo's recipe, an inserter's or
loader's filters (`more`: the others after the first), a splitter's, storage chest's or mining
drill's filter, a requester or buffer chest's first four requested items (`more`: the three after
the first; the client draws them as a 2 x 2 grid of quarter-size icons); left out when it shows none. Every loaded machine has its icon with its record,
whether Alt-mode is on or not, so the client shows them all at once with no scanning. What
changes it without a new record comes in `aiu`. `"fa"`: on an assembling machine or furnace whose
recipe uses fluid, 1 it takes fluid, 2 it makes fluid, 3 both: Alt-mode's machine arrows show at
the prototype's `eprops` `fb` connections of that kind only (all inputs, all outputs), as Factorio
2.1.23 draws them; left out with none. 2.1 has no `LuaEntity.fluidbox`, so it comes from the recipe.

Static entities (buildings, trees, ore) come in chunk snapshots and deltas. Moving ones
(units, characters, vehicles, rolling stock, robots, asteroids…) only come in `mv`.

Belt items are identified by the game's `unique_id` (DetailedItemOnLine). The client glides an
item with the same id from its last position to its new one, so ids that stay the same from belt
to belt give smooth motion; a new id just makes a new item appear.
Positions are where the game draws the item (`LuaTransportLine.get_line_item_position`), lane
included. Items inside an underground belt's tunnel aren't sent. Old clients ignore `iprotos`,
`bi`, `ih`, `gi` and `sky`, so the protocol version stays 1.

Items on the ground have no unit number, so `gi` has no ids: each update replaces the last.
The character picks them up by mining them (`LuaControl::mine_entity` on the item-entity; it works
without a player for buildings, and `tools/live_check.py` checks it for items); with a full inventory it stops and says "Inventory full" once, until the
client stops sending `pickup`. Old mods ignore `pickup`.

Inserter hands are `held_stack_position`; the inserter itself (and so the arm's base) is the
static entity with that unit number. `st` includes lamps: a working lamp has power, and the
client lights it when `darkness` is high enough. It includes rail and chain signals
(`signal_state`, and a chain signal's `chain_signal_state` for blue), accumulators (`status`
charging or discharging) and power switches (`power_switch_state`), whose values say more than
working or not; older clients ignore those types. The client lights the signal's lamp of that
colour, an accumulator's charge or discharge arcs, and slides the switch's contact in or out.

### Delta-coded lists

`bi`, `ih` and `mv` are most of the traffic on a busy base (`tools/net_cost.py` measures it). A
client whose `hello` has `z: 1` gets them delta-coded, marked `z: 1` on each part: in `bi` and
`ih` every number is the difference from the same field of the group before it in that part, and
in `mv` a record's first four numbers (unit, proto, x, y) are the differences from the record
before it, while the orientation stays as is. The first group or record of each part is as is,
so a lost part loses nothing else. Neighbours in these lists are neighbours in the world (items
lane by lane, inserters and movers chunk by chunk), so the differences are short. A client
without `z` gets the plain lists. Measured on the mock's busy base (`net_cost.py`), the steady
stream went from 272 to 131 KB/s; measured on a 20,000-entity test base.

## Combat

`shoot` sets the character's `shooting_state` (`shooting_enemies` for `m: 0`, `shooting_selected`
at the aim point for `m: 1`); the game aims, fires and uses ammo as it does for a player. `me.sh`
is 1 while the selected gun's ammo (magazines and rounds) went down in the last 20 ticks, so the
client only draws shots that happen. With no ammo the mod says "Out of ammo" once per press.

`hp` lists entities that took damage (`on_entity_damaged`) near the focus, while they are below
full health; the client draws health bars over them. `died` comes from `on_entity_died`; the
client shows a flash there and drops a dead mover at once. Old clients ignore `guns`, `hp`,
`tf`, `died` and the new `me` fields; old mods ignore `shoot` and `gun`. `tf` identifies the
turret from Factorio's damage cause, uses its current `shooting_target` when available, and gives
the client a short bullet tracer/muzzle flash or a sustained flame stream. The protocol version
stays 1.

### What weapons fire

`shot` `{u, g, a, x, y}` is one round from the character (`u`): its gun `g` and ammo `a`, sent
on the tick the selected gun's ammo went down (so at the gun's own cooldown). `x, y` is the target:
the selected enemy, else the enemy nearest the character within the gun's range
(`find_nearest_enemy`, as the game picks for `shooting_enemies`), else the aim point. Stream guns
(the flamethrower) send none: their streams are in `pj`.

`pj` `{p, b, x, e}` comes every other tick while anything flies near the focus (and once empty
after), from shots.lua. All four are flat lists:
- `p`: `[id, name, x, y, ...]` projectiles, artillery shells and streams (flamethrower and acid
  blobs) in flight. `id` is the entity's `register_on_object_destroyed` number (they have no unit
  number), the same for as long as it flies.
- `b`: `[id, name, sx, sy, tx, ty, ...]` beams (laser turrets, tesla chains) from their source to
  their target.
- `x`: `[name, x, y, ...]` explosion entities the game made, each reported once.
- `e`: `[id, x, y, ...]` projectiles and streams that ended (`on_object_destroyed`), where they were
  last seen.

A headless server with no player never creates explosions marked `only_when_visible` (checked in
2.1.23): the muzzle flash and bullet hits, a rocket's explosion, the railgun's beam. The client plays
those from the prototype data (`client/data/weapon_fx.json`) on `shot` and `pj.e`, and skips one
`pj.x` reports where it already played it.

`gf` `{l: [id, name, x, y, ticks to live, ...]}` lists the fires (`fire`) and clouds
(`smoke-with-trigger`: poison, slowdown) near the focus four times a second, as a full list; ticks
to live is `time_to_live` for clouds and -1 for fires. An empty list follows the last one. Names
are prototype names (these entities aren't in `protos`). Old clients ignore all three.

## The character's gear

`eq` is Factorio's equipment grid: the character's armour (`LuaEntity::grid` of the character)
and the grid of the vehicle whose screen is open or that the character drives (tank, spidertron,
a car with equipment). `eq_put` places with `LuaEquipmentGrid::put{name, position, quality}` the
item's `place_as_equipment_result`; `eq_take` uses `take{equipment}` and puts what it returns in
the inventory (on the ground when it is full); `eq_move` uses `move{equipment, position}`. The
roboport switch is the owner's `allow_dispatching_robots`, the exoskeleton switch the grid's
`inhibit_movement_bonus`. Factorio has no switch for night vision: it turns on by itself in the
dark while it has power, so `nv` says it is on and the client brightens the night.

When the client's character dies (`on_entity_died`), `dead` counts down to the respawn. A
player's character respawns by the game's rules (`LuaPlayer::ticks_to_respawn`); the bridge's
own character (no player, or standing in for one who is away) waits the character prototype's
`respawn_time` (10 s) and comes back at the force's spawn on the planet it died on (Nauvis after a
death on a platform), with an empty inventory: what it carried is in its corpse, as in Factorio.

`pl` lists the game's players for Factorio's players window; the client puts each connected
player's name, in their colour, over their character (a mover). Old clients ignore these
messages, old mods the commands, so the protocol version stays 1.

## Vehicles

`enter` uses `LuaEntity::set_driver` / `set_passenger` (nil to get out, which puts the character
beside the vehicle). `drive` sets the character's `riding_state` every tick while it is repeated
and back to nothing/straight when it stops, so the game drives cars, tanks, spidertrons and trains
as it does for a player. Driving a locomotive first switches its train to manual mode, as a player
starting to drive does. A burner vehicle with nothing to burn says "No fuel" once per press. The
vehicle itself is a mover (`mv`); the client hides the character and follows `me`. Old clients
ignore `v` and `vs`, old mods `enter` and `drive`, so the protocol version stays 1.

## Factorio's windows

The inventory, quickbar, crafting and research data are for a client UI drawn like Factorio's.
Names are internal (`iron-gear-wheel`): a headless server has no player to translate for, so the
client reads the player's own Factorio locale files for display names (`locale_names.gd`).
The quickbar is kept in the mod's storage for the bridge's character (it has no player and so no
quickbar of its own), so it survives client restarts. `move` uses `LuaItemStack::transfer_stack`
(with an amount, in 2.x) and `swap_stack`, so items keep their own data. Old clients ignore all of
these messages and `gui.slots`; old mods ignore the commands. The protocol version stays 1.

## Building

`build` resolves the item's entity (`place_result`, or for a 2.x rail planner the straight rail in
`rails`), snaps it, and then: the same entity of the same quality at that spot is turned to `d`
(`upd`, no item used) or left alone; otherwise, if an entity of the same fast-replaceable group
stands there and `can_fast_replace` agrees, it is replaced (`create_entity{fast_replace = true,
spill = false}`; in 2.1 `can_place_entity` also says yes there, but a plain `create_entity` then
builds nothing); otherwise `can_place_entity` (manual check) builds it.
Without a player the game gives nothing back and raises no event for the old entity, so the mod
sends its `del` and gives the character its mined products. Rolling stock is put on the nearest
straight rail within 3 tiles, facing along it. Curved rails come from the rail planner (`rails`).
Old clients ignore the third `iprotos` value and `extra.q`; old mods ignore `q`. The protocol
version stays 1.

## Tiles, capsules and the rail planner

Items that aren't built as entities are described by `iuse`. Tiles: the client draws the brush at
the cursor (Numpad + / -: Factorio's larger / smaller tile area, up to 32), green where the tile can
go, red on the wrong ground or out of reach, blue as ghosts; holding the left button sends `tile`
as the brush moves, the right button `tile_mine`. Tile ghosts are entities of type `tile-ghost`
with `extra.tg`; robots laying the tile raise nothing the mod could use, so the client drops a tile
ghost when `tiles` brings its tile. Laying a tile over a mineable one hands that one's item back,
and doesn't keep it under the new one (`set_tiles` leaves the hidden tile alone between two
mineable tiles), so mining concrete laid over stone path shows the ground (checked in 2.1.23).

Capsules: the client draws the throw range round the character and the blast at the cursor, and
sends `throw` on a click and every half second while held.

The rail planner: the client plans the path itself with Factorio's own rail geometry,
`client/data/rail_extensions.json`, read from 2.1.23 (`LuaRailEnd.get_rail_extensions("rail")`
from every end direction, every rail piece's ends, signal locations and a ramp's ends; elevated rails
have the same geometry with `elevated-` names). A click by a free rail end anchors the planner; the
path to the cursor is an A* search over those extensions; a click (or the end of a drag from the
end) sends `rails` and the planner carries on from the path's end. Toggle rail layer (Alt+R) starts
the path with a ramp (cardinal ends only) and lists a support every 14 tiles of elevated track
first: an elevated rail can only be placed next to supported track (rail-support's range is 11).

Drag building is the client's: belts follow the cursor and turn corners; with Smart belt building
an obstacle or a crossing belt line is jumped by building the belt's underground over the last belt
before it (a fast-replace) and again past it, which `build` makes the entrance and the exit; pipes
the same with pipes-to-ground (the entrance facing back along the line, the exit forward); poles
at their wire reach from the last one; other entities one footprint apart along the line.

## Blueprints, ghosts and planners

Entity ghosts are static entities like any other (they used to be left out), with `extra.gh`.
`blueprint` uses `LuaItemStack::build_blueprint{surface, force, position, direction, build_mode =
forced, raise_built = true}`, so each ghost arrives as an `add`. Building an item over its own
ghost revives the ghost (`revive{raise_revive = true}`: the ghost's `del`, the entity's `add`).
Robots building a ghost raise no event the mod could use to remove it, so the client drops a
ghost when its entity is added on the same spot. The client draws a ghost as the entity it stands
for in a translucent ghost material (`ghosts.gd`), and `d` / `up` as Factorio's marks over the entity. `decon` without a planner calls
`LuaSurface::deconstruct_area` (like Factorio's shortcut), with one `deconstruct_area` on the
planner stack; `upgrade` calls `LuaSurface::upgrade_area{area, force, item = planner stack}`
(upgrade planners have no area methods of their own in 2.1); `cancel` the matching `cancel_*`. Marks raise
`on_marked_for_*` / `on_cancelled_*`, which send an `upd` with `extra.d` / `extra.up`. Old clients
draw ghosts as their prototype and ignore the extras; old mods ignore the commands. The protocol
version stays 1.

### Exchange strings, the library, undo

Blueprints, books and planners travel as Factorio's own exchange strings ("0" + base64 of zlib
JSON, what the game's Export / Import string use), so the client's editors work on exactly what
the game stores: `bp_get` exports a stack (`LuaItemStack.export_stack`), `bp_set` imports one
(`import_stack`: 0 fine, -1 with errors, said in a `msg`, 1 refused). Strings are split into
parts of 16000 characters going to the client (reliable `bp`) and 8000 coming from it (`bp_set`
with `id`, `part`, `parts`, `d`; the mod keeps the parts in `storage.f3d.bp_up` until all are
there). A player-less character has no cursor stack, so slot -1 is a stack in a script inventory
(`storage.f3d.lib_cursor`): what the client takes from its library goes there and is placed or
used from there, as a library record in Factorio's cursor isn't in the inventory either.

The client's own library ("My blueprints") lives in `user://blueprint-library.json`. The game's
"Game blueprints" tab (`game.blueprints`, kept in the save) and, when the bridge plays a save's own
player (takeover), that player's library (`LuaPlayer.blueprints`: a multiplayer save keeps each
player's library, and 2.1.23 reads and exports an offline player's records) are listed by
`bpl` and read with `bp_rec` (`LuaRecord.export_record`). The API can't write records, so edits
to those are saved as copies in My blueprints. In the JSON, a book's pages and a planner's
filters and mappers are numbered from 0, icons from 1.

`LuaPlayer.undo_redo_stack` belongs to a player too, so the mod keeps its own entries
(`scripts/history.lua`, the last 100): a blueprint or paste placed (the ghosts it made and the
trees and rocks it marked; undo removes the ghosts, marks what robots already built for
deconstruction, unmarks the trees; redo builds the same string again), deconstruction and upgrade
marks and their cancelling (exactly the entities that changed; undo of an upgrade remembers the
target), pasted settings (a one-entity blueprint of the entity before and after, built over it to
put them back) and rotations. Each sends `hist`; the client puts it in one undo list with its own
building and mining and sends `undo` / `redo` with its id.

`build` with `sf: 1` (Ctrl+Shift+click) builds the held item's entity as a one-entity blueprint
with `build_mode = superforced`, which is what the game does: a ghost, and what stands in the way
marked for deconstruction. `quals` lists the qualities so the client can cycle the held item's
quality (Ctrl+mouse wheel) through those the force has; `build` carries it as `q`.

## Circuit network

Red and green wires are in the entity records (`extra.r`, `extra.g`, see "Fluids and power").
Arithmetic, decider, selector and constant combinators open as `kind: "combinator"`; their `gui`
has `cb`: for arithmetic, decider and selector combinators the control behavior's `parameters` as
the game gives them (2.x shapes: decider `conditions` with `compare_type` and
`first_signal_networks` / `second_signal_networks` `{red, green}`, `outputs` and `else_outputs` with
`copy_count_from_input`, `constant` and `networks`; selector `operation` and that mode's settings,
`quality_source_static` as `{name}`), for a constant combinator `{enabled, signals: [[type, name,
count, quality?], ...] (its first section), sections: [{g (logistic group, "" none), on (0/1), m
(multiplier), s (signals)}, ...]}`. `set_cb` takes the same shape back; with `sections` every
section is rewritten and extra ones removed (a section whose group changes takes the group's
signals). Any entity on a circuit network also has `sig`: `{r: [[type, name, count], ...], g: [...],
ri?, gi? (network ids)}`, what it sees on each (`get_signals`, a combinator's input side); a
combinator's adds `out` in the same shape for its output side. Entities with no inventory but a
network (poles, belts) can be opened to see it. Old clients ignore these.

Every other entity with a control behaviour has `cc` (`scripts/circuit_settings.lua`, made with
`get_or_create_control_behavior` when the screen opens, as Factorio does): `{o (the behaviour's
`defines.control_behavior.type` name: inserter, transport_belt, assembling_machine, furnace, lamp,
mining_drill, pump, generic_on_off, train_stop, turret, container, logistic_container, roboport,
wall, accumulator, programmable_speaker, splitter, rail_signal, radar, lab, rocket_silo, ...), w
(0/1: on a circuit network), ln (0/1: inside a logistic network, for those that can connect to
one), nets: {r, g} (network ids, 0 none), f: {field: value}}`. `f` has the behaviour class's fields
as the API names them, those the game version has: booleans as 0/1, signals as `{type, name}` or
`{}`, conditions as `{first_signal?, comparator, constant | second_signal, ful (0/1: fulfilled)}`,
enums by name (`circuit_hand_read_mode`: `hold` / `pulse`; `read_contents_mode`: `pulse` / `hold`
/ `entire_belt_hold`; `color_mode`: `color_mapping` / `components` / `packed_rgb`;
`resource_read_mode`; `read_items_mode`; `read_mode`; `mode`; ...). `set_cc` writes any of them back
(`{}` clears a signal). Combinators (`cb`), a train stop's own fields (`stop.cb`, see "Trains") and
display panel messages (`dp.msgs`) aren't in `cc`.

Wires are made and removed with `wire` and `wire_clear`; the mod sends both ends again as `upd`
with their new `extra.r` / `g` / `w`.

## Planets

Only what Space Age needs on top of the rest; on Nauvis without Space Age most of these never
come. Lists that can be empty are sent once more when they become empty, then not again until
something is in them.

- `planet`: the surface's planet (`surface.planet`, or `space` on a platform), every surface
  property (`get_property` for each of `prototypes.surface_property`), and the light: `ticks_per_day`,
  `always_day`, `min_brightness`, `solar_power_multiplier`, `dusk` / `evening` / `morning` /
  `dawn`. `sky` still gives the time of day and darkness. `heat`: every prototype with a
  `heating_radius` (heating towers, heat pipes), for drawing what keeps Aquilo's machines warm.
- Vulcanus: demolishers are `LuaSegmentedUnit`s (`surface.get_segmented_units()`), sent as `seg`
  with each segment's prototype, position and orientation. Lava is ordinary tiles (`lava`,
  `lava-hot`); nothing here models damage from it.
- Fulgora: 2.1 raises no event for lightning, so the mod looks for `lightning` entities near the
  focus every 3 ticks and sends each strike once (`lt`). A lightning entity stands where its bolt
  starts in the sky: the prototype's `source_offset` (0, -25) from where it strikes, give or take
  half its `source_variance` (30 x 6), and nothing in 2.1 says where it lands. So the ground point
  is the entity's position less the offset (within 15 tiles in x, 3 in y), and when a lightning
  attractor (rod, collector, or one of Fulgora's ruins) stands inside that window the strike is
  taken as caught and placed on the nearest one. Seen in 2.1.23. Attractors open (`gui`) with their
  charge (`pw`).
- Gleba: freshness is `1 - LuaItemStack.spoil_percent` for items whose prototype spoils
  (`get_spoil_ticks() > 0`), in slots and on belts (`bf`). Plants' growth (`pg`) comes from
  `tick_grown` and the prototype's `growth_ticks`; an agricultural tower's screen has `ag`
  (`{plants, ready}` from `owned_plants`), and the plants it plants or harvests are added and
  removed like built entities (`on_tower_planted_seed`, `on_tower_pre_mined_plant`). Spawners
  (`sp`): how many units they have out (`units`). Feet: `legs`, from `get_spider_legs` for spidertrons; it throws on a spider unit (pentapod),
  whose legs are `spider-leg` entities standing on its feet with the unit numbers right after its
  own (seen in 2.1.23), one per leg of the prototype's `spider_engine`.
- Aquilo: `fz` lists frozen machines (`frozen`, read on prototypes with `heating_energy`);
  temperatures come in `ht`. Ammoniacal ocean is ordinary tiles.
- Travel: `rk` when a rocket launch is ordered (`on_rocket_launch_ordered`), `cp` for cargo
  pods near the focus (`cargo_pod_state`, `cargo_pod_destination`), `pst` when a platform's
  state changes (`on_space_platform_changed_state`). `land` takes the character down from a
  platform stopped at a planet the way a player goes: the hub makes a cargo pod
  (`create_cargo_pod`), its destination is the planet's surface, the character is its passenger
  and it leaves at once (`force_finish_ascending`). If that fails (a player-less character may not
  be allowed to ride), the character is moved down directly, as `plat_board 0` does, and the
  `msg` says which happened.

## Logistics

Logistic chests open as `kind: "container"` and roboports as `kind: "roboport"`; both get `lg`:
`{mode, requests?, filter?, net?}`. `mode` is the chest's `logistic_mode` (`requester`, `buffer`,
`storage`, `active-provider`, `passive-provider`) or `roboport`. Requester and buffer chests have
`requests`, from their first logistic section (`get_logistic_sections().get_section(1).filters`):
`[[item, min, max (-1 for none), quality (only when not normal)], ...]`; `set_requests` writes
that section. Storage chests have `filter` (the item name from `get_filter(1)`, `""` for none); `set_storage_filter`
calls `set_filter(1, item)`, or `set_filter(1)` to clear it. `net` is the entity's
`logistic_network`: `{id, log: [available, all], con: [available, all], items: [[item, count,
quality?], ...]}`, items in its storage and provider chests, most first, at most 200.

The character's own requests (its requester point, `get_requester_point()`) come as `clog` at the
handshake and whenever they change, once the force has `character_logistic_requests` (researched;
before that there is no `clog` and `set_char_requests` answers with a `msg`) (checked twice a second, also for changes made in the game);
`set_char_requests` changes them, `enabled` (`on`) and `trash_not_requested` (`trash`). `ln`
names the network at the character's position (`force.find_logistic_network_by_position`) with
its robot counts. `rc` lists what robots near the focus carry (`robot_cargo` inventory); the
robots themselves move as movers (`mv`).

## Trains

`tr` lists every train with a carriage within the focus radius, every 30 ticks: its id, state
(the name in `defines.train_state`: `on_the_path`, `wait_station`, `manual_control`...), manual
mode (1) or automatic (0), speed in thousandths of a tile per tick (negative going backwards),
the unit of the train stop it is standing at (0 if none), the name of the stop it is heading for
("" if none) and its carriages' units, front first. The carriages themselves move as movers
(`mv`).

Train stops are static entities whose record has their name in `extra.n`; it is updated (`upd`)
when the stop is renamed, by `set_stop` or in the game.

Opening any carriage gives `kind: "train"`: the carriage's own inventories (a locomotive's
`fuel` and `burnt`, a cargo wagon's `cargo`, an artillery wagon's `ammo`, a fluid wagon's `fb`)
and `tr`: `{id, state, manual, station (name of the stop it is at, or ""), dest, sched, name (the open carriage's backer name)}`.
`sched` is `{current, records, group}` from the train's 2.x `LuaSchedule` (`get_schedule()`):
`records` as `get_records()` gives them (`station`, `wait_conditions` `[{type, compare_type,
ticks, condition...}]`, `temporary`, `allows_unloading`...), except that a temporary stop's
`rail` is its position `[x, y]` (fixed) instead of an entity. `set_schedule` takes records in the
same shape (`set_records`; a `rail` position finds the rail there), `train_go` calls
`go_to_station`, `train_mode` sets `manual_mode`. `sched.interrupts` lists the schedule's interrupts
as `get_interrupts()` gives them (`{name, conditions, targets, inside_interrupt}`, targets as records
with rails as positions); `set_interrupts` {`u`, `interrupts`} replaces them (`set_interrupts`).
Wait conditions and interrupt conditions are the game's `WaitCondition`s: `type` (`time`,
`inactivity`, `full`, `empty`, `not_empty`, `item_count`, `fluid_count`, `circuit`,
`passenger_present`, `passenger_not_present`, `fuel_item_count_all`, `fuel_item_count_any`,
`fuel_full`, `destination_full_or_no_path`, `specific_destination_full`, `specific_destination_not_full`,
`at_station`, `not_at_station`, `damage_taken`...), `compare_type` (`and` / `or`), `ticks`,
`condition` (a `CircuitCondition`: `{first_signal, comparator, constant | second_signal}`), `station`,
`damage`. `train_temp` {`u`, `station` or `rail` [x, y]} is Factorio's "go to": a temporary record
after the current one, and the train goes there now. `tr` also has `cargo` and `fuel` (`[[item,
count, quality?], ...]`, the whole train's cargo wagons and every locomotive's fuel), `fluids`
(`[[fluid, amount], ...]`), `stops` (the names of the force's stops on that surface, for new
records), `speed` (thousandths of a tile per tick) and `pos` (the front carriage, fixed), `groups`
(`[[group, trains], ...]`, the force's train groups, for "Change train group") and `gc` (how many
trains the train's own group has, Factorio's "[2]" after its name; absent outside a group).

Opening a train stop gives `kind: "stop"` and `stop`: `{name, limit (-1 for no limit; 2.1 reads
no limit as 4294967295), count (trains on their way, `trains_count`), pri (`train_stop_priority`,
0-255), train (id of the train stopped there, or 0), trs, cb}`. `trs` is the trains with the stop in
their schedule (`get_train_stop_trains`, at most 30): `[[train id, state, heading here 0/1, front
carriage unit], ...]`, for the window's "Trains on the way" and "Trains with this stop" tabs. `cb` is the stop's circuit settings:
`wired` (on a red or green network), `en` (enable/disable) with `cond` (`{first_signal,
comparator, constant | second_signal}`), `send` (send to train), `read` (read train contents),
`stopped` + `stopped_sig`, `limit` (set trains limit) + `limit_sig`, `count` (read trains count) +
`count_sig`, `pri` (set priority) + `pri_sig`; flags 0/1, signals `{type, name}`. `set_stop`
changes the name, limit, `pri`, and any of `cb`'s keys (`{}` as a signal clears it).

`trains_list` asks for Factorio's trains overview: `trl` (in parts) lists every train of the
character's force on every surface: `[id, state, manual 0/1, the stop it is at or heading for,
group, carriages, front unit, x, y (fixed), surface index, speed, [[item, count] up to 3],
[[fluid, amount] up to 1]]`. `train_mode_id` {`id`, `auto`} switches any of them between automatic
and manual (and sends `trl` again).

## Space platforms

Space Age's platforms are surfaces like any other: their chunks hold `space-platform-foundation`
tiles in `empty-space` (the client draws space under that, not ground), the hub, collectors and
thrusters are ordinary entities, and asteroids move as movers. Asteroid chunks aren't entities;
`ach` lists them.

`plat` describes each platform of the character's force (`l`, at most 32, by index):
`{i, n (name), st, pa, hub, sp, w?, loc?, nx?, from?, to?, d?, len?, sch?}`. `st` is the state's name in
`defines.space_platform_state` (`waiting_at_station`, `on_the_path`, `paused`, `no_path`...),
`pa` 1 when paused, `hub` the hub's unit number (0 before the starter pack is applied), `sp` the
speed in km/s (one decimal), `w` its mass in kg (`LuaSpacePlatform.weight`, for the remote view's
platform panel). Stopped somewhere, `loc` names the space location, and `nx` where its schedule
takes it next (the current record when that is elsewhere, else the next record that isn't `loc`;
absent without one; the platform panel's "Next stop" while it waits); travelling,
`from` names where it left and `to` where it is heading (the connection's ends, turned round
when it travels the connection from its `to` end: Factorio's `distance` then counts down), `d` is
how far it has come from `from` in thousandths and `len` the connection's length in km. `sch` is the schedule as `{c (current record), l: [station names]}`, absent
without one.

A player reaches a platform by rocket and comes back down in a cargo pod. The bridge's character
has no player to ride them, so `plat_board` teleports it, but only along those routes: up to a
platform stopped at the character's planet, down to the planet its platform is stopped at
(`LuaControl.teleport(position, surface)` moves a character across surfaces). It lands next to
the hub, or at the force's spawn point on the planet. For testing, the console command
`/f3d-platform` lists the platforms, builds one (`new [planet]`: `create_space_platform` and
`apply_starter_pack`, no rocket needed) and moves the character anywhere (`board <index or
name>`, `leave [planet]`).

After a surface change the mod sends `surface` (reliable) and forgets the client's
subscriptions; `plat` and the character's `me` follow at once. The client throws away its
chunks, entities and live layers, moves the avatar, and subscribes around the new position. The
map (`chart`, `tags`) is per surface too: a map open across the change should be asked for again.

## Space Age's screens

`scripts/space.lua`. Machine screens of Space Age's entities (`gui`, see "Machine screens"):

- **Space platform hub** (`kind` `hub`, inventories `chest` and `trash`): `hub` is
  `{i, n, st, pa, sp, w (weight, kg), th: [thrusters, working], fuel: [[fluid, amount, capacity]]
  (the thrusters' fuel and oxidizer), loc? | from?, to?, d?, len? (as in plat), sched, sec, prov
  (provides to other platforms, 0/1), dest (where it can go)}`. `sched` is the platform's
  LuaSchedule as `{current, records: [{station (a space location), wait_conditions, ...}], group,
  interrupts: [{name, conditions, targets, inside_interrupt}]}`; it is edited with the train
  commands `set_schedule`, `train_go` and `set_interrupts` on the hub's unit. `sec` is its
  logistic sections, the requests from planets: `[{i, g (group), on, m (multiplier), man (1:
  editable), f: [[item, quality ("" any), min, max (-1 none), import from ("" anywhere), minimum
  delivery count (-1 default)], ...]}]` (`LuaLogisticSection.filters`), set with `set_section`.
- **Rocket silo** (`silo`, inventories `input`, `rocket` (the rocket's cargo) and `trash`): `rk`
  adds `st` (`defines.rocket_silo_status` name), `auto` (send to orbit automatically, 0/1) and
  `to`: `[[platform index, name, state], ...]`, the platforms orbiting this planet that
  `silo_launch` can send its rocket to (`launch_rocket{destination}`: the hub as a `station`, or
  the platform itself while it waits for its starter pack).
- **Cargo landing pad** (`pad`, inventories `chest` and `trash`): `pad` is `{sec, cb?: {read,
  req, empty}}`, its requests from orbit and its circuit settings (absent until it has a control
  behaviour; `set_pad` makes one). **Cargo bay** (`bay`): `bay: {owner}`, the hub's or pad's
  unit (its inventory is theirs).
- **Asteroid collector** (`collector`, inventory `output`): `col: {n, f: [chunk or ""] * n}`.
  Crushers are assembling machines (`crafter`).
- Machines with modules or beacons (`crafter`, `furnace`, `lab`, `silo`, `other`): `eff`, their
  effects in thousandths (`sp` speed, `pr` productivity, `co` consumption, `po` pollution, `q`
  quality), only those not zero. A crafter or furnace whose recipe has a quality has `rq`; crafters,
  hubs and pads list the force's unlocked qualities in `ql` (normal first) when there is more than
  normal. `set_recipe` takes `q`, the recipe's quality.

The space map asks for `smap` when it opens. `plat_new` makes a platform the way Factorio's
remote view does: it waits over the planet for its starter pack, which a silo then launches.
`ach` lists asteroid chunks (they aren't entities; asteroids are movers). `acol` is what the
client needs to draw asteroid collectors' arms reaching for chunks: 2.1.23 shows scripts nothing
of the arms themselves (no count, position or target), so the client picks each arm's chunk from
`ach` as Factorio does (one in the catch circle its filters take, the head flying straight at it
at the arm's speed) and `g` tells it which chunk was really caught. `bq` gives belt
items' quality. `planet` has `nb`: `[[entity proto id, property, min, max], ...]`, the buildable
entities this surface's conditions forbid (pressure, gravity, magnetic field...), and a refused
build says why ("Can't build here: gravity is 0 m/s², it needs at least 0.1 m/s²").

## Map

`map` asks for a low-resolution chart of an area, like Factorio's map: each pixel is the map colour
of the tile at its centre, overdrawn by what covers it, in order ore, then trees and rocks, then
buildings (by their bounding boxes, so a belt shows even when it covers part of a pixel). Colours
are the prototype's `friendly_map_color` / `enemy_map_color` / `map_color`, else Factorio's chart
defaults (utility constants: by type, rails, ghosts, trees, the default friendly and enemy
colours); prototypes flagged `not-on-map` and things that move are left out. The mod sends a
`chart` per chunk, nearest the request's centre first, as many a tick as the work budget allows
(see "Work budget": a busy chunk is read in strips over several ticks); a new `map` replaces a
request still being sent, and at most the 1024 chunks nearest the centre are sent.
`chart`: `n` pixels a side (32 / `res`), `pal` the colours used (`[[r, g, b], ...]`), `px` the
`n * n` pixels row by row from the north-west as 0-based indices into `pal`. `n` is 0 for a chunk
the force hasn't charted. Charts are immediate (not resent): ask again for any that went missing.

`pol` (left out under 0.5) is the chunk's pollution (`LuaSurface.get_pollution`), for the map
view's pollution layer.

`ov` (left out when empty) carries what Factorio's map view switches draw over the chart, for the
character's force's entities whose position is in the chunk (at most 400): `[kind, x, y, ...]`
with `x`, `y` fixed. `["e", x, y, r]` an electric pole and its supply area (half the square's
side), `["w", x, y, x2, y2]` a copper wire from that pole to another (each wire once, from the pole
with the lower unit number), `["t", x, y, r]` a turret and its range (ammo, electric and fluid turrets), `["l", x, y,
logistic, construction]` a roboport's radii, `["s", x, y, name]` a train stop, `["g", x, y,
state]` a rail or chain signal and its `defines.signal_state` (0 open, 1 closed, 2 reserved, 3
reserved by circuit), `["c", x, y, recipe]` an assembler's or furnace's recipe, `["b", x, y]` a
construction or logistic robot. Radii are prototype values (normal quality). Old clients ignore it.

A player charts the map around themselves; the bridge's player-less character doesn't, so while a
client is connected the bridge charts 96 tiles around it every 2 seconds (`force.chart`). In
single-player the player does that. A headless server with no player connected queues those
requests but never carries them out (`is_chunk_charted` stays false, seen in 2.1.23), so the mod
also keeps the chunks its character has been near in `storage` and counts them as charted.

Tags (`force.find_chart_tags`, `add_chart_tag`, `LuaCustomChartTag.destroy`) are sent as `tags`
after `map`, after `tag_add` / `tag_del`, and when they change in the game. A tag can only go
where the map is charted (otherwise a `msg`). Pings (chat GPS links) aren't covered.

Other surfaces (Factorio's surface switcher on the map): `surfs` (reliable, at the handshake and
whenever the list changes, checked every 5 s) lists what the map can show: `[[index, name, planet,
platform name, platform index], ...]`, the planets that have a surface (`planet` is its name,
`platform name` "") and the force's space platforms (`planet` "", `platform index` as in
`plat`). `map` takes an optional `si` (a surface index from that list): its charts and tags are
that surface's; without it, or with a surface that doesn't exist, the character's. `chart` and
`tags` carry the `si` they show. `tag_add` and `tag_del` take an optional `si` too. Only the
character's surface is charted around it; other surfaces show what the force charted there.

Remote building: ghosts (`build` with `ghost`), `blueprint`, `paste`, `decon` and `upgrade` need
no reach, but only work where the force has charted the map, as in the game ("You can't build in
an uncharted area" otherwise). The client's remote view builds ghosts only.

## Fluids and power

Fluid contents come from each entity's fluid storages (2.1 has no `LuaEntity.fluidbox`:
`fluids_count`, `get_fluid(i)`, `get_fluid_capacity(i)`); amounts and temperatures are rounded to whole numbers. Wires come from 2.x wire
connectors (`get_wire_connectors(false)`, each connector's `wire_type` and `connections`), read
when a record is made. 2.x raises no event when a wire is added or removed between two existing
entities, so every 30 ticks the mod compares the wires of poles, power switches and combinators
within the focus radius with its last look and sends an `upd` for each one that changed. Power:
`status` of `no_power`, `low_power` or `not_plugged_in_electric_network` (2). 2.1 gives a consumer
out of reach of every pole `no_power` too (`not_plugged_in_electric_network` is for generators), so
`no_power` with no `electric_network_id` is also 2. Heat: `temperature`
of entities with a heat buffer. Pipe connections (`extra.pc`) come from
`get_fluid_box_pipe_connections`; building, rotating or removing anything with fluid boxes sends an
`upd` for the pipes around it (a removal on the next tick, once it is gone). Machine screens also
carry `status` (the entity status name), `fb` (`[[fluid or "", amount, capacity, temperature],
...]` per fluid box), `pw` (how full the electric buffer is, in thousandths, for electric
machines) and `temp` (whole °C, for entities with a heat buffer or heat energy source). Old clients ignore all of these; the
protocol version stays 1. The client (`wires.gd`) draws a wire listed by both ends once, owned by the
end with the lower unit number, attached at the pole's `connection_points` (scaled to 3D).

## Factorio's world controls

A player's cursor, clipboard, undo history and statistics GUI belong to the player; the bridge's
character has none (`scripts/ui_actions.lua`). So the client keeps what is held (and the stack's
slot), the copied entity for settings and the undo history of its own building and mining (undo
marks what it built for deconstruction, or puts a ghost where it mined; redo the other way), and
the mod keeps the clipboard: a blueprint in a script inventory (`game.create_inventory(1)`, in
`storage`), filled by `create_blueprint` and built with `build_blueprint`. Copied settings use
`LuaEntity.copy_settings`; flipping `LuaEntity.mirroring` (the entity record doesn't carry it, so the
client draws flipped entities unflipped). The game's chat reaches the client through
`on_console_chat`; console commands can't be run by a mod for a player-less character, so the client
runs them over RCON when it started the server. Old mods ignore these commands; old clients ignore
`eprops`, `ai`, `clip`, `chat` and `stats`. The protocol version stays 1.

## Machine screens

The client sends `open` for an entity; while it is open the mod sends `gui` twice a second.
`kind` is `container` (chests), `crafter` (assembling machines), `furnace`, `lab`, `combinator`,
`train` (locomotives and wagons), `stop` (train stops), `roboport`, `inserter`, `splitter` (and lane
splitters), `switch` (power switches), `turret`, `vehicle` (cars, spidertrons), `pole`, `silo` (rocket
silos), `panel` (display panels) or `other` (anything else with a fuel,
burnt-result, output or module inventory, or on a circuit network; entities with none of these
can't be opened). `inv` is an object from inventory role to `[[item, count], ...]` (qualities
summed), with the roles the entity has: `chest`, `input`, `output`, `fuel`, `burnt`, `modules`,
`cargo` (cargo wagons), `ammo` (artillery wagons), `trash` (requester and buffer chests), `robots` and
`repair` (roboports), `turret_ammo` (turrets), `trunk` and `car_ammo` (vehicles); a space platform
hub's and cargo landing pad's main inventory is `chest`. Like other lists, an empty one (or an `inv` without roles) may arrive as `{}`. `rl` lists the recipes the machine can make for the character's force: enabled, not
hidden, in one of its crafting categories. It is resent every 10th message (5 s) in case one is
lost or research unlocked more.

Entity windows beyond inventories (`scripts/entity_ui.lua`): an inserter has `ins`: `{n (filter
slots), f ([item or ""] by slot), st (stack size override, 0 none), max (the most it can carry),
use (0/1) and m (whitelist / blacklist) when it has filter slots}`; a splitter `spl`: `{i, o (left,
none, right), f (filter item or "")}`; a chest whose inventory supports a bar `bar` (how many slots
machines may use; its size when unlimited); a power switch `sw` (0/1); a rocket silo `rk`:
`{parts, need, st, auto, to}`; a display panel `dp`: `{text, icon, show (always in Alt-mode), chart (show in
chart), msgs: [{text, icon, cond}, ...] (with a circuit network, the first message whose condition
holds is shown)}`. An inserter's `ins` also has `sp` (spoil priority) where the game has it and `h`
(`[item, count]`, what its hand holds, absent when empty). A cargo wagon has `bar` too (`set_bar` moves
it). Anything with a burner has `bu`: how much of the fuel item burning now is left, in thousandths
(Factorio's red bar beside the fuel slot). A car, tank or spidertron has `guns` (its gun items in slot
order, each over its ammo slot) and `veh`: `{grid (0/1: it has an equipment grid), lbl (a
spidertron's name), at ([without gunner, with gunner], 0/1: a spidertron's auto targeting)}`. An
artillery turret or wagon has `art` (auto targeting, 0/1). A storage tank, pipe or pipe-to-ground has
`pl`: `[fluid or "", amount, capacity]`, the fluid segment its fluid box is in (Factorio's "Pipeline
contents"). A combinator has `desc` (its description). Lamps, train stops,
locomotives and spidertrons have `col` (`[r, g, b]`, 0-255) and a lamp `ao` (always on, 0/1); a pump `pf` (its fluid filter, `""` none); a turret
`tgt`: `{l: [entity names], ign (0/1)}`; a programmable speaker `spk`: `{vol (0-1), mode (local,
surface, global), poly, vctl (volume controlled by signal), vsig, inst, note (from 0), pitch (signal
value is pitch), stop (stop playing sounds), al: {show, map, icon, msg} (its alert), il:
[[instrument, [note, ...]], ...]}`. Space Age's hub, landing pad, bay and asteroid collector,
module effects and quality: see "Space Age's screens" (an asteroid collector's `col` is its
filters, a dictionary, not a colour). Accumulators, radars, tanks, pipes, heat pipes, land mines,
plain belts, beacons and the like open with their status, energy, fluids, signals and circuit
settings. What opens nothing in 2.1.23 opens nothing here either, silently: steam engines and
turbines, solar panels, walls, gates, underground belts, rails, rail ramps and supports, plants,
robots, fluid wagons, lightning rods and collectors, fusion generators, thrusters and a cargo bay
on its own (one against a hub or landing pad opens that); every buildable entity was opened in the
real game for this list (tools/ui_reference `--only rules_openable`). A pole's
electric network statistics come with `stats` (kind `electric`).

Production windows (`scripts/machine_info.lua`), what Factorio's windows show beyond inventories,
each field only where the entity has it: `rd` (crafters, furnaces and rocket silos with a recipe):
`{i: [[type, name, amount], ...], o: [...], e: seconds}`, the recipe's ingredients and products
(averaged over ranges and probabilities); `rp`, a furnace's previous recipe while it has none;
`fixed: 1`, an assembler whose recipe can't be changed (the captive biter spawner); `pb`, the
productivity bonus in thousandths (when above zero) with `bp`, the bonus progress (thousandths);
`bn`, the fuel left in the burning item (thousandths of its fuel value; 0 when nothing burns);
mining drills `mp` (progress, thousandths, from `crafting_progress`), `mt` (the resource entity's
name) and for fluid resources `mr` (yield per second in hundredths); `tc` (temperature in
hundredths of a degree) with `tmax` (the heat buffer's maximum); labs `li`, the science packs they
take (with the recipe list's messages) and `ld`, `[[slot, thousandths], ...]`, what is left of the pack the lab has started
on for the slots holding it (`get_stored_durability`); `lgs`, the force's logistic group names
(`get_logistic_groups`) for entities with logistic sections, with the recipe list's messages; a
rocket silo's `rw`, `[grams in the rocket, grams it lifts]`; `lc` for requester and buffer chests,
landing pads and rocket silos: `{tu, rb?, sec}`
(trash unrequested, the requester's request from buffer chests, its logistic sections as in the
hub's `sec`; `set_section` edits them on a chest too). With `rl` comes `rg`: `[[group, group order,
subgroup order + " " + subgroup, order], ...]` by recipe, for the recipe chooser's item group tabs.
A rocket silo also has `recipe` and `pr` (its rocket parts). Old clients ignore all of these.

`set_recipe`, `take` and `put` act on the open screen only, and only if `u` matches it and the
character can still reach it (`LuaControl::can_reach_entity`, measured to the entity's edge). The mod closes the screen (`gui` with `closed: true`, and a `msg`
saying why if there is a reason to give) when the entity is gone or the character walked out of
reach; it forgets it when the client times out or restarts. The client also drops the screen
after 3 s without a `gui` message. Old clients never send `open`, so the protocol version stays 1.

## Information windows

Factorio's alerts, Factoriopedia, the logistic networks window (L) and the richer statistics.
Added in protocol 1: old clients ignore the new messages, and old mods don't answer the new
commands (the client then keeps its own guesses for alerts).

**Alerts.** `LuaPlayer.get_alerts` needs a player, so `alerts.lua` works them out for the force:
`destroyed` (`on_entity_died`, 30 s), `attack` (`on_entity_damaged` by another force, 5 s after the
last hit), `fire` (a turret of the force did the damage, 5 s), and from a pass over every surface
chunk by chunk (32 chunks / 40 entities a tick, at most every 10 s; one pass took 145 ms in one go
on a large save): `no_ammo` (an ammo turret's `turret_ammo` inventory is empty), `no_power`,
`unplugged` (status `no_power` with no electric network), `low_power`, `no_fuel`, `output_full`
(machine statuses), `no_material` (a ghost inside a roboport's construction area,
`find_logistic_networks_by_construction_area`, whose networks lack its item; subject: the item),
`no_robots` (no construction robot free there), `launch` (a rocket silo waiting for space in its
destination or without a hub or pad) and `collector` (an asteroid collector that is full); every
40 ticks one of `no_repair` (a damaged building of the force in a construction area without repair
packs), `train_fuel` (an automatic train whose locomotives have no fuel left), `train_path`
(`no_path`), `platform_path` (a platform with `no_path`) and `platform_storage` (a hub whose main
inventory is full). Each kind lists at most 40 entities, on the character's surface first and
nearest the camera first; `count` is the full number. A ghost's `name` is the entity it will
build. Not covered: `no_storage`, `no_roboport_storage`, `fluid_mixing`, `pipeline_overextended`,
`unclaimed_cargo`, `platform_tile_building_blocked`, `collector_path_blocked` (no API shows them).

**Factoriopedia.** `pidx` lists what Factoriopedia's grid shows: items, fluids, entities that no
item builds (trees, rocks, enemies...), tiles no item places, recipes not named after an item or
fluid, technologies (group `technologies`), planets and other space locations, qualities; hidden
ones (`hidden`, `hidden_in_factoriopedia`, parameters) are left out. `pedia`'s `d` depends on the
kind (all fields optional): every page `group`, `sub`; items `type`, `stack`, `fuel` (J), `fcat`,
`facc`, `ftop`, `burnt`, `place`, `tile`, `equip`, `weight`, `spoil` (ticks), `spoil_to`, `module`
(effects), `mcat`, `tier`, `ammo`, `made` / `used` / `recycle` (recipe names), `mined` (entities),
`rocket` (launch products), `entity` (the page of the entity it builds); fluids `temp`, `max_temp`,
`heat` (J/°C), `fuel`, `made`, `used`, `mined`, `tiles`, `pumped`; entities `type`, `hp`, `res`
(`[[damage type, flat, percent], ...]`), `size`, `etype` (electric, burner, heat, fluid, void),
`drain` (W), `energy` (W, the maximum use), `power` (W), `poll` (`{pollutant: per minute}`), `craft`,
`mine_speed`, `belt` (items/s), `research`, `rot` (°/s), `modules`, `effects`, `cats`, `recipes`,
`mine` (`[[type, name, amount], ...]`), `mtime`, `fluid_req`, `items`, `next`, `wire` (poles),
`supply`, `range`, `under`, `inv`, `mradius`, `can_mine`, `packs`, `fuels`, `speed` (units);
recipes `ing`, `prod` (`[[type, name, amount], ...]`, amounts averaged over chances), `time`,
`cats`, `made_in`, `unlocked`, `enabled`, `poll_mult`, `max_prod`, `effects`; technologies `pre`,
`succ`, `cost`, `count`, `time`, `formula`, `level`, `max_level`, `effects`, `trigger`, `state`,
`saved`; tiles `walk`, `friction`, `absorb`, `items`, `mine`, `mtime`, `fluid`, `color`,
`foundation`; planets and space locations `props` (surface properties), `dist`, `solar`, `kind`,
`links` (`[[location, length], ...]`); qualities `level`, `next`, `prob`, `color`, `mult`.

## Riding to a platform

As in Factorio 2.x, the character goes up in a rocket and lives in the platform's hub:

- `ride {u, to}` from an open silo with a rocket ready: `LuaEntity.launch_rocket(destination, character)`
  puts the character in the rocket's cargo pod (it works without a player in 2.1.23). `me` then
  carries `pod`, `ps`, `up`, `gx`, `gy` every 2 ticks. Seen in 2.1.23: about 8 s `awaiting_launch`
  (the rocket rises out of the silo, the pod's `y` hardly moves), then `ascending` for 20 s while
  `y` runs north of the silo (Factorio draws height as a shift up the screen: 7 tiles by 5 s, 200 by
  20 s), `surface_transition` for a moment, then `surface` (the platform) with the pod `descending`
  for about 5 s from 40 tiles out onto the hub, `parking` 1.5 s at the hub's hatch, and the
  character is inside the hub (`me.hub`, `x`, `y` the hub's).
- Inside the hub the character can't walk, mine, pick up or drop; `build`, `tile` and `rails`
  place ghosts, and screens on the platform open as from the remote view (`rv`: settings only,
  except the hub itself, which is in reach).
- `land` from the hub: 2.1.23 won't put a character that is inside a hub into a pod and won't
  teleport it on its own surface, so the mod hops it to the planet and back beside the hub in the
  same tick, then the hub's pod takes it. The pod waits 1.5 s, climbs 7 s (`up` 1, ground point the
  hub), changes surface (`surface`) and comes down for 10 s onto the landing pad or the spot beside
  the spawn (`up` 0, `gx`, `gy` that spot). Then `me` has no `pod` and the character stands there.
- While riding, the commands that act on the world are refused with a `msg` ("Not while flying").
