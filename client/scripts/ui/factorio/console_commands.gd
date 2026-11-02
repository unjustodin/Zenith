extends RefCounted
## Factorio 2.1's console commands for the 3D client's console (chat_window.gd), each run where it
## can be (checked one by one against a headless 2.1.23 over RCON):
## - CLIENT: the client does it itself (/clear, /color, /help, /ignore...);
## - MOD: the bridge runs it for the character it plays (`cmd`, console.lua: /cheat, /f3d-*);
## - EITHER: RCON when the client started the server, otherwise the bridge (/time, /seed...);
## - RCON: only Factorio's server console has it (/kick, /ban, /config...);
## - LUA: /c and friends over RCON, with `game.player` meaning the player the bridge plays
##   (data/console_prelude.lua: RCON has no player, so game.player was nil);
## - GAME: needs a real player's game window (/editor, /screenshot...): Ctrl+F9 opens this game in
##   Factorio itself, where they work.
## Lua never goes through the bridge: anything on localhost can send it UDP, and /c is for admins.

enum { CLIENT, MOD, EITHER, RCON, LUA, GAME }

const PRELUDE_PATH := "res://data/console_prelude.lua"
const ANSWER_MSEC := 5000

## name: [where, aliases, help]
const COMMANDS := {
	"help": [CLIENT, ["h"], "/help [command]: lists the commands, or says what one does and where it runs"],
	"clear": [CLIENT, [], "/clear: clears the console"],
	"color": [CLIENT, [], "/color <name or r g b>: the character's colour (default, red, green, blue, orange, yellow, pink, purple, white, black, gray, brown, cyan, acid)"],
	"shout": [CLIENT, ["s"], "/shout <message>: says it to everyone"],
	"ignore": [CLIENT, [], "/ignore <player>: hides their chat in this console"],
	"unignore": [CLIENT, [], "/unignore <player>: shows their chat again"],
	"ignores": [CLIENT, [], "/ignores: who this console hides"],
	"permissions": [CLIENT, [], "/permissions: opens the permissions window"],
	"command": [LUA, ["c"], "/c <lua>: runs Lua (needs RCON); game.player is the player the 3D client plays"],
	"silent-command": [LUA, ["sc"], "/sc <lua>: runs Lua without telling the other players (needs RCON)"],
	"measured-command": [LUA, ["mc"], "/mc <lua>: runs Lua and says how long it took (needs RCON)"],
	"cheat": [MOD, [], "/cheat [all | off | <planet> | <platform>]: researches everything (all: and gives a kit; off: cheat mode off), or moves the character to a planet or platform"],
	"version": [EITHER, [], "/version: Factorio's version"],
	"seed": [EITHER, [], "/seed: the map's seed"],
	"time": [EITHER, [], "/time: how old the map is"],
	"evolution": [EITHER, [], "/evolution [surface]: the enemies' evolution"],
	"players": [EITHER, ["p"], "/players [online | count]: the players in the game"],
	"admins": [EITHER, [], "/admins [online]: the game's admins"],
	"server-save": [EITHER, [], "/server-save: saves the game on the server"],
	"whisper": [RCON, ["w"], "/whisper <player> <message>: to one player (from the server)"],
	"kick": [RCON, [], "/kick <player> <reason>"],
	"ban": [RCON, [], "/ban <player> <reason>"],
	"bans": [RCON, [], "/bans: who is banned"],
	"unban": [RCON, [], "/unban <player>"],
	"banlist": [RCON, [], "/banlist <add | remove | get | clear> <player>"],
	"whitelist": [RCON, [], "/whitelist <enable | disable | add | remove | get | clear> <player>"],
	"promote": [RCON, [], "/promote <player>: makes them an admin"],
	"demote": [RCON, [], "/demote <player>"],
	"purge": [RCON, [], "/purge <player>: clears their messages from the chat log"],
	"mute": [RCON, [], "/mute <player>: stops them chatting"],
	"unmute": [RCON, [], "/unmute <player>"],
	"mutes": [RCON, [], "/mutes: who is muted"],
	"config": [RCON, [], "/config get | set <option> [value]: the server's settings (the window itself is Factorio's)"],
	"swap-players": [RCON, [], "/swap-players <player> <player>: swaps their characters"],
	"space-platform-delete-time": [RCON, [], "/space-platform-delete-time <ticks>"],
	"delete-blueprint-library": [RCON, [], "/delete-blueprint-library <player>: an offline player's library"],
	"large-blueprint-size": [RCON, [], "/large-blueprint-size <set | get> <bytes>"],
	"toggle-heavy-mode": [RCON, [], "/toggle-heavy-mode: looks for desyncs (makes multiplayer unplayable)"],
	"f3d-status": [MOD, [], "/f3d-status: the bridge's state"],
	"f3d-selftest": [MOD, [], "/f3d-selftest: checks the bridge's character API in this game"],
	"f3d-platform": [MOD, [], "/f3d-platform new [planet] | board <platform> | leave [planet] | list"],
	"f3d-player": [MOD, [], "/f3d-player [name | none]: which player's character the bridge plays"],
	"f3d-profile": [MOD, [], "/f3d-profile [trace]: times each part of the bridge (then /f3d-status)"],
	"f3d-rate": [MOD, [], "/f3d-rate <0-3>: the bridge sends its costliest updates less often"],
	"editor": [GAME, [], "/editor: the map editor"],
	"screenshot": [GAME, [], "/screenshot [x y zoom]: a screenshot of the game's view"],
	"reply": [GAME, ["r"], "/reply <message>: to whoever whispered to you"],
	"open": [GAME, ["o"], "/open <player>: another player's inventory"],
	"admin": [GAME, [], "/admin: the player management window"],
	"alerts": [GAME, [], "/alerts <enable | disable | mute | unmute> <alert>: a player's alert settings"],
	"perf-avg-frames": [GAME, [], "/perf-avg-frames <n>: the game window's performance counters"],
	"mute-programmable-speaker": [GAME, [], "/mute-programmable-speaker <mute | unmute> <local | everyone>"],
	"toggle-action-logging": [GAME, [], "/toggle-action-logging: logs the game window's input actions"],
	"unlock-shortcut-bar": [GAME, [], "/unlock-shortcut-bar"],
	"unlock-tips": [GAME, [], "/unlock-tips"],
	"reset-tips": [GAME, [], "/reset-tips"],
}

## Factorio's player colours (core utility-constants: player_colors' player_color).
const COLORS := {
	"default": [0.869, 0.5, 0.130], "red": [0.815, 0.024, 0.0], "green": [0.093, 0.768, 0.172],
	"blue": [0.155, 0.540, 0.898], "orange": [0.869, 0.5, 0.130], "yellow": [0.835, 0.666, 0.077],
	"pink": [0.929, 0.386, 0.514], "purple": [0.485, 0.111, 0.659], "white": [0.8, 0.8, 0.8],
	"black": [0.1, 0.1, 0.1], "gray": [0.4, 0.4, 0.4], "brown": [0.300, 0.117, 0.0],
	"cyan": [0.275, 0.755, 0.712], "acid": [0.559, 0.761, 0.157],
}

const IN_FACTORIO := "%s needs a player in Factorio's own window: press Ctrl+F9 (Show in Factorio) to open this game there and type it in its console"
const NEEDS_RCON := "%s needs RCON: start the server from this client's menu (it is then the server's console), or press Ctrl+F9 and type it in Factorio"

## Callable(command: String) -> String, awaitable: the server's console over RCON.
var rcon := Callable()
## Callable() -> bool: whether rcon works now.
var has_rcon := Callable()
## Callable(name: String): opens one of the HUD's windows (/permissions).
var open_window := Callable()
## ui_model.gd: the bridge (command, set_char_color, say).
var model
## The console (chat_window.gd): clear(), ignored.
var chat

static var _prelude := ""


## The command's own name for a name or alias ("c" -> "command"), or "" if Factorio has none.
static func canonical(name: String) -> String:
	name = name.to_lower()
	if COMMANDS.has(name):
		return name
	for n in COMMANDS:
		if name in COMMANDS[n][1]:
			return n
	return ""


## Every name Tab completes, with the aliases.
static func names() -> Array:
	var out: Array = []
	for n in COMMANDS:
		out.append(n)
		out.append_array(COMMANDS[n][1])
	out.sort()
	return out


## Tab on the console line: "/ev" -> "/evolution ", "/s" -> the longest shared start, with the
## choices when there are several. Returns [new text, choices].
static func complete(text: String) -> Array:
	if not text.begins_with("/") or text.contains(" "):
		return [text, []]
	var start := text.substr(1).to_lower()
	var found: Array = []
	for n in names():
		if str(n).begins_with(start):
			found.append(n)
	if found.is_empty():
		return [text, []]
	if found.size() == 1:
		return ["/" + str(found[0]) + " ", []]
	var shared := str(found[0])
	for n in found:
		while not str(n).begins_with(shared):
			shared = shared.substr(0, shared.length() - 1)
	return ["/" + shared, found]


## A Lua command made ready for RCON: `game.player` becomes the player the bridge plays (or a
## stand-in for its character), game.print and game.player.print also answer the console, and
## an error comes back as the answer instead of vanishing. "/c __mod__ code" keeps the mod.
static func lua_command(text: String) -> String:
	var sp := text.find(" ")
	if sp < 0:
		return text
	var head := text.substr(0, sp)
	var code := text.substr(sp + 1)
	var target := ""
	var m := RegEx.create_from_string("^(__\\S+__)\\s+").search(code)
	if m != null:
		target = m.get_string(1) + " "
		code = code.substr(m.get_end())
	return head + " " + target + prelude().replace("%USER%", rewrite_lua(code) + "\n")


static func rewrite_lua(code: String) -> String:
	code = RegEx.create_from_string("\\bgame\\s*\\.\\s*player\\s*\\.\\s*print\\s*\\(").sub(code, "__zprint(", true)
	code = RegEx.create_from_string("\\bgame\\s*\\.\\s*print\\s*\\(").sub(code, "__zgprint(", true)
	return RegEx.create_from_string("\\bgame\\s*\\.\\s*player\\b").sub(code, "__zp", true)


## data/console_prelude.lua on one line, so the user's code starts on line 1 (error lines match).
static func prelude() -> String:
	if _prelude == "":
		var lines: PackedStringArray = []
		for l in FileAccess.get_file_as_string(PRELUDE_PATH).split("\n"):
			if l.strip_edges() != "":
				lines.append(l.strip_edges())
		_prelude = " ".join(lines)
	return _prelude


## Runs a console line starting with "/"; the answer, "" for none.
func run(text: String) -> String:
	text = text.strip_edges()
	var sp := text.find(" ")
	var typed := (text.substr(1, sp - 1) if sp > 0 else text.substr(1))
	var args := text.substr(sp + 1).strip_edges() if sp > 0 else ""
	var name := canonical(typed)
	var online: bool = has_rcon.is_valid() and bool(has_rcon.call())
	if name == "":
		# Another mod's command, perhaps: the server knows; the bridge knows its own.
		if online:
			return await rcon.call(text)
		var known: Array = await _ask_mod(text)
		if known[0]:
			return known[1]
		return "Unknown command /%s (/help lists them). Another mod's command needs RCON, or Ctrl+F9 to type it in Factorio" % typed
	var where: int = COMMANDS[name][0]
	match where:
		CLIENT:
			return await _client(name, args)
		LUA:
			if args == "":
				return COMMANDS[name][2]
			if not online:
				return NEEDS_RCON % ("Lua (/%s)" % typed)
			return await rcon.call(lua_command(text))
		MOD:
			return (await _ask_mod(text))[1]
		EITHER:
			if online:
				return await rcon.call(text)
			return (await _ask_mod(text))[1]
		RCON:
			if not online:
				return NEEDS_RCON % ("/" + name)
			return await rcon.call(text)
		GAME:
			return IN_FACTORIO % ("/" + name)
	return ""


## [known, answer]: the bridge runs the command for its character (`cmd`).
func _ask_mod(text: String) -> Array:
	if model == null:
		return [false, ""]
	var got := []
	var got_id := [0]
	var on_answer := func(id: int, lines: Array, known: bool) -> void:
		if got.is_empty() and id == got_id[0]:
			got.append([known, "\n".join(PackedStringArray(lines))])
	model.command_answered.connect(on_answer)
	got_id[0] = model.command(text)
	var started := Time.get_ticks_msec()
	var tree := Engine.get_main_loop() as SceneTree
	while got.is_empty() and Time.get_ticks_msec() - started < ANSWER_MSEC:
		await tree.process_frame
	model.command_answered.disconnect(on_answer)
	if got.is_empty():
		return [true, "The bridge didn't answer (is the game paused or the mod older than the client?)"]
	return got[0]


func _client(name: String, args: String) -> String:
	match name:
		"help":
			return help(args)
		"clear":
			if chat != null:
				chat.clear()
			return ""
		"color":
			var c := parse_color(args)
			if c.a == 0.0:
				return COMMANDS["color"][2]
			if model != null:
				model.set_character_color(c)
			return ""
		"shout":
			if args != "" and model != null:
				model.say(args)
			return ""
		"ignore", "unignore":
			if args == "":
				return COMMANDS[name][2]
			if chat != null:
				if name == "ignore":
					chat.ignored[args] = true
				else:
					chat.ignored.erase(args)
			return ("Hiding %s's chat" if name == "ignore" else "Showing %s's chat again") % args
		"ignores":
			return "Ignored: " + (", ".join(PackedStringArray(chat.ignored.keys())) if chat != null and not chat.ignored.is_empty() else "nobody")
		"permissions":
			if open_window.is_valid():
				open_window.call("permissions")
			return ""
	return ""


## /help: every command by where it runs; /help <command>: what it does.
func help(args: String) -> String:
	if args != "":
		var name := canonical(args.trim_prefix("/").split(" ")[0])
		if name == "":
			return "No command /%s" % args.trim_prefix("/")
		var c: Array = COMMANDS[name]
		var aliases := "" if c[1].is_empty() else " (also /%s)" % ", /".join(PackedStringArray(c[1]))
		var where: String = ["here", "by the bridge", "over RCON, or by the bridge", "over RCON", "over RCON", "in Factorio itself (Ctrl+F9)"][int(c[0])]
		return "%s%s. Runs %s" % [c[2], aliases, where]
	var groups := {CLIENT: [], MOD: [], EITHER: [], RCON: [], LUA: [], GAME: []}
	for n in COMMANDS:
		groups[int(COMMANDS[n][0])].append("/" + n)
	var online: bool = has_rcon.is_valid() and bool(has_rcon.call())
	var lines := [
		"Here: " + " ".join(PackedStringArray(groups[CLIENT])),
		"By the bridge: " + " ".join(PackedStringArray(groups[MOD] + groups[EITHER])),
		"Over RCON%s: %s" % ["" if online else " (not connected: start the server from the menu)",
			" ".join(PackedStringArray(groups[LUA] + groups[RCON]))],
		"In Factorio itself (Ctrl+F9): " + " ".join(PackedStringArray(groups[GAME])),
		"/help <command> says more; Tab completes a command, Up and Down go through what you typed",
	]
	return "\n".join(PackedStringArray(lines))


## /color's argument: a Factorio colour name, or "r g b [a]" (0-1, or 0-255 when any is over 1).
## Alpha 0 when it isn't one.
static func parse_color(args: String) -> Color:
	var a := args.strip_edges().to_lower()
	if COLORS.has(a):
		var c: Array = COLORS[a]
		return Color(c[0], c[1], c[2])
	var parts := a.split(" ", false)
	if parts.size() < 3:
		return Color(0, 0, 0, 0)
	var v: Array = []
	for i in 3:
		if not parts[i].is_valid_float():
			return Color(0, 0, 0, 0)
		v.append(float(parts[i]))
	var scale := 255.0 if v.max() > 1.0 else 1.0
	return Color(clampf(v[0] / scale, 0, 1), clampf(v[1] / scale, 0, 1), clampf(v[2] / scale, 0, 1))
