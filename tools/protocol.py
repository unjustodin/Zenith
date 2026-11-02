"""Checks server-to-client messages against docs/PROTOCOL.md.

Used by the tests for both the real bridge mod (tools/mod_tests) and the mock server, so the
two can't drift apart. `problems(msg)` returns a list of strings; empty means valid.
"""

RELIABLE = {"cmdr", "welcome", "protos", "tprotos", "iprotos", "fprotos", "ready", "chunk", "ents", "add", "upd", "del", "tiles", "st", "inv", "recipes",
            "guns", "slots", "qb", "rdet", "craftable", "techs", "clog", "surface", "eprops", "surfs", "planet",
            "bp", "bp_ok", "bpl", "hist", "quals", "iuse", "pidx", "dprotos", "dec", "ccol"}
IMMEDIATE = {"me", "mv", "bi", "ih", "gi", "sky", "msg", "gui", "hp", "tf", "ts", "afx", "died", "cq", "rs", "fl", "pw", "ht", "chart", "tags", "tr", "ln", "rc", "plat",
             "ai", "clip", "chat", "stats", "trl", "seg", "lt", "legs", "cp", "pg", "sp", "fz", "rk", "pst", "bf",
             "eq", "cinfo", "dead", "pl", "ach", "bq", "smap", "al", "pedia", "lnets", "lnet", "bonus", "perms", "spd", "unghost", "hinfo", "terr", "mtr", "mrp", "lpad", "cov", "bfar", "raise", "pj", "gf", "shot", "en", "acol", "wb"}
CHARACTER_ROLES = {"main", "guns", "ammo", "armor", "trash"}
DICTIONARY_WIDTH = {"protos": 12, "tprotos": 5, "iprotos": 2, "fprotos": 5, "dprotos": 2}
GUI_KINDS = {"container", "crafter", "furnace", "lab", "combinator", "train", "stop", "roboport", "other",
             "inserter", "splitter", "switch", "turret", "vehicle", "pole", "silo", "panel", "hub", "pad", "bay", "collector"}
GUI_ROLES = {"chest", "input", "output", "fuel", "burnt", "modules", "cargo", "ammo", "trash", "robots", "repair",
             "trunk", "turret_ammo", "car_ammo", "rocket"}
LOGISTIC_MODES = {"requester", "active-provider", "passive-provider", "buffer", "storage", "none", "roboport"}
PRIORITIES = {"left", "none", "right"}
PLANNER_ITEMS = {"", "blueprint", "blueprint-book", "deconstruction-planner", "upgrade-planner"}
RECORD_TYPES = {"blueprint", "blueprint-book", "deconstruction-planner", "upgrade-planner"}
STATS_KINDS = {"item", "fluid", "kill", "electric", "build", "pollution"}
ALERT_KINDS = {"destroyed", "attack", "fire", "no_ammo", "no_material", "no_robots", "no_repair", "train_fuel", "train_path",
               "platform_path", "platform_storage", "collector", "launch", "no_power", "unplugged", "low_power", "no_fuel",
               "output_full"}
PEDIA_KINDS = {"item", "fluid", "entity", "recipe", "technology", "tile", "planet", "space-location", "quality"}


def split_datagram(data):
    """The messages in one datagram: one JSON object, or for a client whose hello says `b` several
    joined by newlines (docs/PROTOCOL.md, Transport)."""
    import json
    if isinstance(data, (bytes, bytearray)):
        data = data.decode("utf-8")
    return [json.loads(line) for line in data.split("\n") if line]


def _int(v):
    return isinstance(v, int) and not isinstance(v, bool)


def _num(v):
    return (isinstance(v, (int, float))) and not isinstance(v, bool)


def _list(v):
    # Factorio's table_to_json may write an empty table as {}.
    return isinstance(v, list) or v == {}


def _items(v):
    return v if isinstance(v, list) else []


def entity_record_problems(rec, where):
    if not isinstance(rec, list) or len(rec) not in (5, 6):
        return [f"{where}: entity record must be a list of 5 or 6 values: {rec!r}"]
    out = []
    if not all(_int(v) for v in rec[:5]):
        out.append(f"{where}: unit, proto, x, y, direction must be integers: {rec!r}")
    elif not 0 <= rec[4] <= 15:
        out.append(f"{where}: direction out of range: {rec!r}")
    if len(rec) == 6 and not isinstance(rec[5], dict):
        out.append(f"{where}: extra must be an object: {rec!r}")
    elif len(rec) == 6 and "q" in rec[5] and not isinstance(rec[5]["q"], str):
        out.append(f"{where}: extra.q is a quality name: {rec!r}")
    elif len(rec) == 6 and any(k in rec[5] and not _int(rec[5][k]) for k in ("gh", "up", "tg")):
        out.append(f"{where}: extra.gh (ghost's entity) and extra.up (upgrade target) are prototype ids: {rec!r}")
    elif len(rec) == 6 and "d" in rec[5] and rec[5]["d"] != 1:
        out.append(f"{where}: extra.d (marked for deconstruction) is 1 when present: {rec!r}")
    elif len(rec) == 6 and any(k in rec[5] and not (_list(rec[5][k]) and all(_int(u) for u in _items(rec[5][k])))
                               for k in ("w", "r", "g")):
        out.append(f"{where}: extra.w/r/g are lists of unit numbers: {rec!r}")
    elif len(rec) == 6 and "pc" in rec[5] and not (_int(rec[5]["pc"]) and 0 <= rec[5]["pc"] <= 15):
        out.append(f"{where}: extra.pc (pipe connections) is a 4-bit mask: {rec!r}")
    elif len(rec) == 6 and "col" in rec[5] and not (_list(rec[5]["col"]) and len(rec[5]["col"]) == 3 and all(_int(v) and 0 <= v <= 255 for v in rec[5]["col"])):
        out.append(f"{where}: extra.col (a painted entity's colour) is [r, g, b] 0-255: {rec!r}")
    elif len(rec) == 6 and "n" in rec[5] and not isinstance(rec[5]["n"], str):
        out.append(f"{where}: extra.n (train stop name) is a string: {rec!r}")
    elif len(rec) == 6 and "rm" in rec[5] and not (_int(rec[5]["rm"]) and rec[5]["rm"] >= 0):
        out.append(f"{where}: extra.rm (what left the remnants) is a prototype id or 0: {rec!r}")
    elif len(rec) == 6 and "co" in rec[5] and rec[5]["co"] not in CLIFF_ORIENTATIONS:
        out.append(f"{where}: extra.co is a cliff orientation like \"west-to-east\": {rec!r}")
    return out


# Every pair of different sides, "none" included: 20 orientations.
_SIDES = ("west", "north", "east", "south", "none")
CLIFF_ORIENTATIONS = {f"{a}-to-{b}" for a in _SIDES for b in _SIDES if a != b}


def item_counts_problems(v, where):
    out = []
    if not _list(v):
        return [f"{where}: must be a list of [name, count]: {v!r}"]
    for rec in _items(v):
        if not (isinstance(rec, list) and len(rec) == 2 and isinstance(rec[0], str) and _int(rec[1])):
            out.append(f"{where}: entry must be [name, count]: {rec!r}")
    return out


def slot_list_problems(v, where):
    """[[item, count] or [item, count, quality], or 0 for an empty slot, ...]"""
    if not _list(v):
        return [f"{where}: must be a list of slots: {v!r}"]
    out = []
    for slot in _items(v):
        if slot == 0:
            continue
        if not (isinstance(slot, list) and len(slot) in (2, 3, 4) and isinstance(slot[0], str) and _int(slot[1])
                and slot[1] > 0 and (len(slot) == 2 or isinstance(slot[2], str))
                and (len(slot) < 4 or (_int(slot[3]) and 0 <= slot[3] <= 1000))):
            out.append(f"{where}: slot must be 0 or [item, count, quality?, freshness (0-1000)?]: {slot!r}")
    return out


def _strs(v):
    return _list(v) and all(isinstance(x, str) for x in _items(v))


def amount_list_problems(v, where):
    if not _list(v):
        return [f"{where}: must be a list: {v!r}"]
    return [f"{where}: entry must be [type, name, amount]: {x!r}" for x in _items(v)
            if not (isinstance(x, list) and len(x) == 3 and isinstance(x[0], str) and isinstance(x[1], str) and _num(x[2]))]


def recipe_detail_problems(rec):
    if not (isinstance(rec, list) and len(rec) == 10):
        return [f"rdet: record must have 10 values: {rec!r}"]
    name, energy, cats, group, gorder, sub, sorder, order, ings, prods = rec
    out = []
    if not (isinstance(name, str) and _num(energy) and _strs(cats) and all(isinstance(x, str) for x in (group, gorder, sub, sorder, order))):
        out.append(f"rdet: bad record {rec!r}")
    return out + amount_list_problems(ings, f"rdet {name} ingredients") + amount_list_problems(prods, f"rdet {name} products")


def eprops_overlay_problems(x):
    """eprops' fifth entry: {ip, id: [x, y]} inserter vectors, {lr, cr} roboport radii, {mr, vp?}
    mining radius and drop vector, {fb: [[x, y, direction, "i"|"o"|"b"], ...]} fluid connections, fo: 1
    when those show only while the recipe needs fluid, cw the circuit wire reach, ww a power switch's copper
    wire reach."""
    if not isinstance(x, dict) or not x:
        return [f"must be a non-empty object: {x!r}"]
    out = []
    vec = lambda v: isinstance(v, list) and len(v) == 2 and all(_num(c) for c in v)
    for k, v in x.items():
        if k in ("ip", "id", "vp"):
            ok = vec(v)
        elif k == "fo":
            ok = v == 1
        elif k in ("lr", "cr", "mr", "cw", "ww"):
            ok = _num(v) and v >= 0
        elif k == "fb":
            ok = isinstance(v, list) and all(isinstance(c, list) and len(c) == 4 and _num(c[0]) and _num(c[1]) and _int(c[2])
                                             and c[3] in ("i", "o", "b") for c in v)
        else:
            ok = False
        if not ok:
            out.append(f"bad {k}: {v!r}")
    return out


def tech_problems(rec):
    # 8 values from older mods; 14 with effects, levels, the trigger's detail, saved progress and the
    # count formula.
    # 15: whether it is essential (Factorio's "Show only essential technologies").
    if not (isinstance(rec, list) and len(rec) in (8, 14, 15)):
        return [f"techs: record must have 8, 14 or 15 values: {rec!r}"]
    name, order, pre, ings, count, seconds, state, trigger = rec[:8]
    out = []
    if not (isinstance(name, str) and isinstance(order, str) and _strs(pre) and _int(count) and _num(seconds)
            and state in (0, 1, 2) and isinstance(trigger, str)):
        out.append(f"techs: bad record {rec!r}")
    if not _list(ings) or not all(isinstance(x, list) and len(x) == 2 and isinstance(x[0], str) and _num(x[1]) for x in _items(ings)):
        out.append(f"techs: ingredients must be [[name, amount], ...]: {rec!r}")
    if len(rec) == 15 and rec[14] not in (0, 1):
        out.append(f"techs: essential is 0 or 1: {rec!r}")
    if len(rec) >= 14:
        effects, level, max_level, detail, saved, formula = rec[8:14]
        if not (_list(effects) and all(isinstance(e, list) and len(e) == 3 and isinstance(e[0], str) and isinstance(e[1], str)
                                       and _num(e[2]) for e in _items(effects))):
            out.append(f"techs: effects must be [[type, target, value], ...]: {rec!r}")
        if not (_int(level) and _int(max_level) and (max_level == -1 or max_level >= 1)):
            out.append(f"techs: level and max level (-1 infinite) must be integers: {rec!r}")
        if not (_list(detail) and (len(_items(detail)) == 0 or (len(detail) == 3 and isinstance(detail[0], str)
                                                                and isinstance(detail[1], str) and _num(detail[2])))):
            out.append(f"techs: trigger detail is [] or [type, target, count]: {rec!r}")
        if not (_int(saved) and 0 <= saved <= 1000 and isinstance(formula, str)):
            out.append(f"techs: saved progress (thousandths) and formula: {rec!r}")
    return out


def alert_problems(msg):
    out = []
    if not _list(msg.get("l")):
        return [f"al: l must be a list: {msg.get('l')!r}"]
    for rec in _items(msg.get("l")):
        if not (isinstance(rec, list) and len(rec) == 3 and rec[0] in ALERT_KINDS and _int(rec[1]) and _list(rec[2])):
            out.append(f"al: alert must be [kind, count, entities]: {rec!r}")
            continue
        for e in _items(rec[2]):
            if not (isinstance(e, list) and len(e) in (5, 6) and all(_int(v) for v in e[:3]) and isinstance(e[3], str)
                    and _int(e[4]) and (len(e) == 5 or isinstance(e[5], (str, int)))):
                out.append(f"al: entity must be [x, y, surface index, name, unit, subject?]: {e!r}")
        if len(_items(rec[2])) > rec[1]:
            out.append(f"al: more entities listed than counted: {rec!r}")
    return out


def _amounts(v):
    return _list(v) and all(isinstance(a, list) and len(a) == 3 and isinstance(a[0], str) and isinstance(a[1], str)
                            and _num(a[2]) for a in _items(v))


def pedia_problems(msg):
    out = []
    if msg.get("kind") not in PEDIA_KINDS and msg.get("found") != 0:
        out.append(f"pedia: unknown kind {msg.get('kind')!r}")
    if not isinstance(msg.get("name"), str) or msg.get("found") not in (0, 1):
        out.append(f"pedia: name and found (0/1): {msg!r}")
    d = msg.get("d")
    if not (isinstance(d, dict) or d == []):
        return out + [f"pedia: d must be an object: {d!r}"]
    d = d or {}
    for k in ("made", "used", "recycle", "mined", "recipes", "made_in", "unlocked", "pre", "succ", "items", "cats",
              "can_mine", "tiles", "packs", "fuels", "fcat"):
        if k in d and not _strs(d[k]):
            out.append(f"pedia: {k} must be a list of names: {d[k]!r}")
    for k in ("ing", "prod", "mine", "rocket"):
        if k in d and not _amounts(d[k]):
            out.append(f"pedia: {k} must be [[type, name, amount], ...]: {d[k]!r}")
    for k in ("stack", "fuel", "hp", "energy", "power", "craft", "time", "modules", "level"):
        if k in d and not _num(d[k]):
            out.append(f"pedia: {k} must be a number: {d[k]!r}")
    if "res" in d and not (_list(d["res"]) and all(isinstance(r, list) and len(r) == 3 and isinstance(r[0], str)
                                                    and _num(r[1]) and _num(r[2]) for r in _items(d["res"]))):
        out.append(f"pedia: res must be [[damage type, flat, percent], ...]: {d['res']!r}")
    for k in ("poll", "absorb", "props", "module", "mult"):
        if k in d and not (isinstance(d[k], dict) or d[k] == []):
            out.append(f"pedia: {k} must be an object: {d[k]!r}")
    if "entity" in d:
        out += pedia_problems({"kind": "entity", "name": msg.get("name"), "found": 1, "d": d["entity"]})
    return out


def lnets_problems(msg):
    out = []
    if not _list(msg.get("l")):
        return [f"lnets: l must be a list: {msg.get('l')!r}"]
    for rec in _items(msg.get("l")):
        if not (isinstance(rec, list) and len(rec) == 12 and _int(rec[0]) and _int(rec[1]) and isinstance(rec[2], str)
                and all(isinstance(rec[i], list) and len(rec[i]) == 2 and all(_int(v) for v in rec[i]) for i in (3, 4))
                and all(_int(v) for v in rec[5:11]) and isinstance(rec[11], str)):
            out.append(f"lnets: network must be [id, si, surface, [log], [con], cells, storages, providers, requesters, x, y, name]: {rec!r}")
    return out


def gui_problems(msg):
    out = []
    if not _int(msg.get("u")):
        out.append(f"gui: bad or missing u: {msg.get('u')!r}")
    if msg.get("closed") is True:
        return out
    if "closed" in msg:
        out.append(f"gui: closed must be true when present: {msg['closed']!r}")
    if not _int(msg.get("p")):
        out.append(f"gui: bad or missing p: {msg.get('p')!r}")
    kind = msg.get("kind")
    if kind not in GUI_KINDS:
        out.append(f"gui: unknown kind {kind!r}")
    inv = msg.get("inv")
    if isinstance(inv, dict):
        for role, contents in inv.items():
            if role not in GUI_ROLES:
                out.append(f"gui: unknown inventory role {role!r}")
            out += item_counts_problems(contents, f"gui inv {role}")
    elif inv != []:
        out.append(f"gui: inv must be an object of role -> [[name, count], ...]: {inv!r}")
    slots = msg.get("slots")
    if isinstance(slots, dict):
        for role, lst in slots.items():
            if role not in GUI_ROLES:
                out.append(f"gui: unknown slots role {role!r}")
            out += slot_list_problems(lst, f"gui slots {role}")
    elif "slots" in msg and slots != []:
        out.append(f"gui: slots must be an object of role -> slot list: {slots!r}")
    if "cb" in msg and not isinstance(msg["cb"], dict):
        out.append(f"gui: cb (combinator settings) must be an object: {msg['cb']!r}")
    if "cb" in msg and kind != "combinator":
        out.append(f"gui: only combinators have cb: {msg!r}")
    sig = msg.get("sig")
    if sig is not None:
        out += signals_problems(sig, "gui sig")
        if isinstance(sig, dict) and "out" in sig:
            out += signals_problems(sig["out"], "gui sig.out")
            if kind != "combinator":
                out.append(f"gui: only combinators have sig.out: {sig!r}")
    if "cc" in msg:
        out += circuit_settings_problems(msg["cc"]) if kind != "combinator" else [f"gui: combinators have cb, not cc: {msg!r}"]
    if kind == "combinator" and isinstance(msg.get("cb"), dict) and "sections" in msg["cb"]:
        out += cb_sections_problems(msg["cb"]["sections"])
    if "status" in msg and not isinstance(msg["status"], str):
        out.append(f"gui: status must be a name: {msg['status']!r}")
    if "pw" in msg and not (_int(msg["pw"]) and 0 <= msg["pw"] <= 1000):
        out.append(f"gui: pw must be thousandths: {msg['pw']!r}")
    if "far" in msg and msg["far"] != 1:
        out.append(f"gui: far must be 1 when present: {msg['far']!r}")
    if "mrq" in msg and not (_list(msg["mrq"]) and all(isinstance(v, str) for v in _items(msg["mrq"]))):
        out.append(f"gui: mrq must be each module slot's requested module or '': {msg['mrq']!r}")
    if "temp" in msg and not _int(msg["temp"]):
        out.append(f"gui: temp must be whole degrees: {msg['temp']!r}")
    if "fb" in msg and not (_list(msg["fb"]) and all(isinstance(b, list) and len(b) == 4 and isinstance(b[0], str)
                                                      and all(_int(v) for v in b[1:]) for b in _items(msg["fb"]))):
        out.append(f"gui: fb must be [[fluid, amount, capacity, temperature], ...]: {msg['fb']!r}")
    if "recipe" in msg and not isinstance(msg["recipe"], str):
        out.append(f"gui: recipe must be a name: {msg['recipe']!r}")
    if "pr" in msg and not (_int(msg["pr"]) and 0 <= msg["pr"] <= 1000):
        out.append(f"gui: pr must be thousandths: {msg['pr']!r}")
    if "rl" in msg and not (_list(msg["rl"]) and all(isinstance(v, str) for v in _items(msg["rl"]))):
        out.append(f"gui: rl must be recipe names: {msg['rl']!r}")
    if kind not in ("crafter", "furnace", "silo") and ("recipe" in msg or "pr" in msg):
        out.append(f"gui: only crafters, furnaces and silos have a recipe and progress: {msg!r}")
    out += machine_info_problems(msg, kind)
    if kind != "crafter" and "rl" in msg:
        out.append(f"gui: only crafters have a recipe list: {msg!r}")
    if "tr" in msg:
        out += train_info_problems(msg["tr"]) if kind == "train" else [f"gui: only rolling stock has tr: {msg!r}"]
    out += entity_ui_problems(msg, kind)
    out += space_problems(msg, kind)
    if "ag" in msg and not (isinstance(msg["ag"], dict) and _int(msg["ag"].get("plants")) and _int(msg["ag"].get("ready"))):
        out.append(f"gui: ag (agricultural tower) is {{plants, ready}}: {msg['ag']!r}")
    if "lg" in msg:
        out += logistics_problems(msg["lg"]) if kind in ("container", "roboport") else [f"gui: only logistic chests and roboports have lg: {msg!r}"]
    if "stop" in msg:
        stop = msg["stop"]
        if kind != "stop":
            out.append(f"gui: only train stops have stop: {msg!r}")
        elif not (isinstance(stop, dict) and isinstance(stop.get("name"), str) and _int(stop.get("limit"))
                  and stop["limit"] >= -1 and _int(stop.get("count"))):
            out.append(f"gui: stop must be {{name, limit (-1 none), count}}: {stop!r}")
        else:
            if "pri" in stop and not (_int(stop["pri"]) and 0 <= stop["pri"] <= 255):
                out.append(f"gui: stop.pri is 0-255: {stop!r}")
            if "train" in stop and not _int(stop["train"]):
                out.append(f"gui: stop.train is a train id or 0: {stop!r}")
            if "trs" in stop and not (_list(stop["trs"]) and all(
                    isinstance(t, list) and len(t) == 4 and _int(t[0]) and isinstance(t[1], str) and t[2] in (0, 1) and _int(t[3])
                    for t in _items(stop["trs"]))):
                out.append(f"gui: stop.trs is [[train id, state, heading here, front unit], ...]: {stop!r}")
            cb = stop.get("cb")
            if cb is not None:
                flags = ("wired", "en", "send", "read", "stopped", "limit", "count", "pri")
                if not (isinstance(cb, dict) and all(cb.get(f) in (0, 1) for f in flags)):
                    out.append(f"gui: stop.cb needs 0/1 for {flags}: {cb!r}")
                elif not all(isinstance(cb[k], dict) and isinstance(cb[k].get("name"), str)
                             for k in ("stopped_sig", "limit_sig", "count_sig", "pri_sig") if k in cb):
                    out.append(f"gui: stop.cb signals are {{type, name}}: {cb!r}")
    return out


def signal_id_ok(v):
    """A SignalID on the wire: {type, name, quality?}, or {} for none."""
    if v == []:  # an empty Lua table, as some JSON writers put it
        return True
    return isinstance(v, dict) and (v == {} or (isinstance(v.get("type"), str) and isinstance(v.get("name"), str)
                                                and isinstance(v.get("quality", ""), str)))


def condition_ok(c):
    """A circuit condition: {comparator, first_signal?, second_signal? | constant, ful? (0/1)}."""
    return (isinstance(c, dict) and c.get("comparator") in ("<", ">", "=", "\u2265", "\u2264", "\u2260", ">=", "<=", "!=")
            and all(signal_id_ok(c[k]) for k in ("first_signal", "second_signal") if k in c)
            and ("second_signal" in c or _int(c.get("constant", 0))) and c.get("ful", 0) in (0, 1))


def signals_problems(sig, where):
    if not (isinstance(sig, dict) and all(
            _list(sig.get(w, [])) and all(isinstance(x, list) and len(x) == 3 and isinstance(x[0], str) and isinstance(x[1], str) and _int(x[2])
                                          for x in _items(sig.get(w, []))) for w in ("r", "g"))):
        return [f"{where}: must be {{r, g: [[type, name, count], ...], ri?, gi?}}: {sig!r}"]
    if not all(_int(sig[k]) and sig[k] > 0 for k in ("ri", "gi") if k in sig):
        return [f"{where}: ri and gi are network ids: {sig!r}"]
    return []


CC_FIELD_KINDS = {"b": lambda v: v in (0, 1), "s": signal_id_ok, "c": condition_ok, "e": lambda v: isinstance(v, str)}
# circuit_settings.lua's fields by kind (b: 0/1, s: signal, c: condition, e: enum name).
CC_SIGNAL_SUFFIX = ("_signal",)


def circuit_settings_problems(cc):
    """gui.cc: {o, w, ln?, nets: {r, g}, f: {field: value}} (circuit_settings.lua)."""
    if not (isinstance(cc, dict) and isinstance(cc.get("o"), str) and cc.get("w") in (0, 1) and cc.get("ln", 0) in (0, 1)
            and isinstance(cc.get("nets"), dict) and all(_int(cc["nets"].get(k)) for k in ("r", "g"))
            and isinstance(cc.get("f"), (dict, list)) and (cc["f"] == [] or isinstance(cc["f"], dict))):
        return [f"gui: cc must be {{o, w, ln?, nets: {{r, g}}, f}}: {cc!r}"]
    out = []
    for k, v in (cc["f"] if isinstance(cc["f"], dict) else {}).items():
        if k.endswith("_condition") and k != "circuit_condition_enabled" and not k.startswith("enable_"):
            ok = condition_ok(v)
        elif k.endswith(CC_SIGNAL_SUFFIX) and k not in ("close_signal", "read_signal"):
            ok = signal_id_ok(v)
        elif k.endswith("_mode") or k == "mode" or k == "circuit_exclusive_mode_of_operation":
            ok = isinstance(v, str)
        else:
            ok = v in (0, 1)
        if not ok:
            out.append(f"gui: cc.f.{k} has a bad value: {v!r}")
    return out


def cb_sections_problems(sections):
    """A constant combinator's cb.sections: [{g (group), on (0/1), m (multiplier), s: [[type, name, count, quality?], ...]}]."""
    if not _list(sections):
        return [f"gui: cb.sections must be a list: {sections!r}"]
    out = []
    for sec in _items(sections):
        if not (isinstance(sec, dict) and isinstance(sec.get("g"), str) and sec.get("on") in (0, 1) and _num(sec.get("m"))
                and _list(sec.get("s")) and all(isinstance(x, list) and len(x) in (3, 4) and isinstance(x[0], str)
                                                and isinstance(x[1], str) and _int(x[2]) for x in _items(sec.get("s")))):
            out.append(f"gui: cb section must be {{g, on, m, s}}: {sec!r}")
    return out


def entity_ui_problems(msg, kind):
    """The fields entity_ui.lua adds to `gui` (inserters, splitters, chests' bars...)."""
    out = []
    owners = {"ins": "inserter", "spl": "splitter", "sw": "switch", "rk": "silo", "dp": "panel", "desc": "combinator",
              "guns": "vehicle", "veh": "vehicle"}
    for field, owner in owners.items():
        if field in msg and kind != owner:
            out.append(f"gui: only {owner} screens have {field}: {msg!r}")
    if "bar" in msg and kind not in ("container", "train"):
        out.append(f"gui: only chests and cargo wagons have bar: {msg!r}")
    if "desc" in msg and not isinstance(msg["desc"], str):
        out.append(f"gui: desc (a combinator's description) is a string: {msg['desc']!r}")
    if "guns" in msg and not (_list(msg["guns"]) and all(isinstance(g, str) for g in _items(msg["guns"]))):
        out.append(f"gui: guns are gun item names: {msg['guns']!r}")
    if "bu" in msg and not (_int(msg["bu"]) and 0 <= msg["bu"] <= 1000):
        out.append(f"gui: bu (burning fuel left) is thousandths: {msg['bu']!r}")
    if "ao" in msg and msg["ao"] not in (0, 1):
        out.append(f"gui: ao (a lamp's always on) is 0 or 1: {msg['ao']!r}")
    ins = msg.get("ins")
    if ins is not None and not (isinstance(ins, dict) and _int(ins.get("n")) and _list(ins.get("f", []))
                                and len(_items(ins.get("f", []))) == ins["n"] and all(isinstance(v, str) for v in _items(ins.get("f", [])))
                                and _int(ins.get("st")) and _int(ins.get("max"))
                                and (ins["n"] == 0 or (ins.get("use") in (0, 1) and ins.get("m") in ("whitelist", "blacklist")))):
        out.append(f"gui: ins must be {{n, f: [item or \"\"] * n, st, max, use?, m?}}: {ins!r}")
    if ins is not None and isinstance(ins, dict) and ins.get("sp", "none") not in ("none", "fresh-first", "spoiled-first"):
        out.append(f"gui: ins.sp is a spoil priority: {ins!r}")
    if ins is not None and isinstance(ins, dict) and "h" in ins and not (
            isinstance(ins["h"], list) and len(ins["h"]) == 2 and isinstance(ins["h"][0], str) and _int(ins["h"][1])):
        out.append(f"gui: ins.h (the hand) is [item, count]: {ins!r}")
    spl = msg.get("spl")
    if spl is not None and not (isinstance(spl, dict) and spl.get("i") in PRIORITIES and spl.get("o") in PRIORITIES
                                and isinstance(spl.get("f"), str)):
        out.append(f"gui: spl must be {{i, o: left|none|right, f: item or \"\"}}: {spl!r}")
    if "sw" in msg and msg["sw"] not in (0, 1):
        out.append(f"gui: sw must be 0 or 1: {msg['sw']!r}")
    rk = msg.get("rk")
    if rk is not None and not (isinstance(rk, dict) and _int(rk.get("parts")) and _int(rk.get("need"))):
        out.append(f"gui: rk must be {{parts, need}}: {rk!r}")
    elif rk is not None and not (isinstance(rk.get("st", ""), str) and rk.get("auto", 0) in (0, 1) and _list(rk.get("to", []))
                                 and all(isinstance(t, list) and len(t) == 3 and _int(t[0]) and isinstance(t[1], str)
                                         and t[2] in PLATFORM_STATES for t in _items(rk.get("to", [])))):
        out.append(f"gui: rk.st is a status name, auto 0/1, to [[platform, name, state], ...]: {rk!r}")
    dp = msg.get("dp")
    if dp is not None and not (isinstance(dp, dict) and isinstance(dp.get("text"), str)
                               and signal_id_ok(dp.get("icon", {})) and dp.get("show", 0) in (0, 1) and dp.get("chart", 0) in (0, 1)
                               and _list(dp.get("msgs", [])) and all(isinstance(m, dict) and isinstance(m.get("text"), str)
                                                                    and signal_id_ok(m.get("icon")) and condition_ok(m.get("cond"))
                                                                    for m in _items(dp.get("msgs", [])))):
        out.append(f"gui: dp must be {{text, icon?, show?, chart?, msgs?: [{{text, icon, cond}}]}}: {dp!r}")
    # `col` is a lamp's or train stop's colour, except on an asteroid collector (space_problems).
    if "col" in msg and msg.get("kind") != "collector" and not (isinstance(msg["col"], list) and len(msg["col"]) == 3 and all(_int(v) and 0 <= v <= 255 for v in msg["col"])):
        out.append(f"gui: col must be [r, g, b] in 0-255: {msg['col']!r}")
    veh = msg.get("veh")
    if veh is not None and not (isinstance(veh, dict) and veh.get("grid") in (0, 1) and isinstance(veh.get("lbl", ""), str)
                                and (veh.get("at") is None or (isinstance(veh["at"], list) and len(veh["at"]) == 2
                                                               and all(v in (0, 1) for v in veh["at"])))):
        out.append(f"gui: veh must be {{grid 0/1, lbl?, at?: [without gunner, with gunner] 0/1}}: {veh!r}")
    if "art" in msg and msg["art"] not in (0, 1):
        out.append(f"gui: art (artillery auto targeting) is 0 or 1: {msg['art']!r}")
    pl = msg.get("pl")
    if pl is not None and not (isinstance(pl, list) and len(pl) == 3 and isinstance(pl[0], str) and _int(pl[1]) and _int(pl[2])):
        out.append(f"gui: pl (pipeline contents) is [fluid or \"\", amount, capacity]: {pl!r}")
    if "pf" in msg and not isinstance(msg["pf"], str):
        out.append(f"gui: pf (pump filter) is a fluid name or \"\": {msg['pf']!r}")
    tgt = msg.get("tgt")
    if tgt is not None and not (kind == "turret" and isinstance(tgt, dict) and _list(tgt.get("l"))
                                and all(isinstance(v, str) for v in _items(tgt.get("l"))) and tgt.get("ign") in (0, 1)):
        out.append(f"gui: tgt must be {{l: [entity names], ign}} on a turret: {tgt!r}")
    spk = msg.get("spk")
    if spk is not None:
        al = spk.get("al") if isinstance(spk, dict) else None
        if not (isinstance(spk, dict) and _num(spk.get("vol")) and spk.get("mode") in ("local", "surface", "global")
                and all(spk.get(k) in (0, 1) for k in ("poly", "vctl", "pitch", "stop")) and signal_id_ok(spk.get("vsig"))
                and _int(spk.get("inst")) and _int(spk.get("note")) and isinstance(al, dict)
                and all(al.get(k) in (0, 1) for k in ("show", "map")) and signal_id_ok(al.get("icon")) and isinstance(al.get("msg"), str)
                and _list(spk.get("il")) and all(isinstance(i, list) and len(i) == 2 and isinstance(i[0], str) and _list(i[1])
                                                  for i in _items(spk.get("il")))):
            out.append(f"gui: spk must be {{vol, mode, poly, vctl, vsig, inst, note, pitch, stop, al, il}}: {spk!r}")
    if "bar" in msg and not (_int(msg["bar"]) and msg["bar"] >= 0):
        out.append(f"gui: bar must be the usable slot count: {msg['bar']!r}")
    return out



def _amounts_ok(v):
    return _list(v) and all(isinstance(x, list) and len(x) == 3 and x[0] in ("item", "fluid", "research-progress")
                            and isinstance(x[1], str) and _num(x[2]) for x in _items(v))


def machine_info_problems(msg, kind):
    """machine_info.lua's fields of a gui message (production windows)."""
    out = []
    rd = msg.get("rd")
    if rd is not None:
        if not (isinstance(rd, dict) and _amounts_ok(rd.get("i", [])) and _amounts_ok(rd.get("o", [])) and _num(rd.get("e", 0))):
            out.append(f"gui: rd is {{i: [[type, name, amount]], o: [...], e: seconds}}: {rd!r}")
        if kind not in ("crafter", "furnace", "silo"):
            out.append(f"gui: only crafters, furnaces and silos have rd: {msg!r}")
    if "fixed" in msg and not (msg["fixed"] == 1 and kind == "crafter"):
        out.append(f"gui: fixed is 1 on a crafter with a fixed recipe: {msg['fixed']!r}")
    if "rp" in msg and not (isinstance(msg["rp"], str) and kind == "furnace"):
        out.append(f"gui: rp is a furnace's previous recipe: {msg['rp']!r}")
    for k in ("bp", "bn", "mp"):
        if k in msg and not (_int(msg[k]) and 0 <= msg[k] <= 1000):
            out.append(f"gui: {k} must be thousandths: {msg[k]!r}")
    for k in ("pb", "mr", "tc"):
        if k in msg and not _int(msg[k]):
            out.append(f"gui: {k} must be an integer: {msg[k]!r}")
    if "tmax" in msg and not _num(msg["tmax"]):
        out.append(f"gui: tmax must be degrees: {msg['tmax']!r}")
    if "mt" in msg and not isinstance(msg["mt"], str):
        out.append(f"gui: mt must be a resource name: {msg['mt']!r}")
    if "rw" in msg and not (isinstance(msg["rw"], list) and len(msg["rw"]) == 2 and all(_int(v) and v >= 0 for v in msg["rw"])
                            and kind == "silo"):
        out.append(f"gui: rw is a silo's [grams in the rocket, grams it lifts]: {msg['rw']!r}")
    if "ld" in msg and not (_list(msg["ld"]) and all(isinstance(r, list) and len(r) == 2 and _int(r[0]) and _int(r[1])
                                                    and 0 <= r[1] <= 1000 for r in _items(msg["ld"]))):
        out.append(f"gui: ld is [[slot, thousandths], ...]: {msg['ld']!r}")
    if "lgs" in msg and not (_list(msg["lgs"]) and all(isinstance(v, str) for v in _items(msg["lgs"]))):
        out.append(f"gui: lgs must be logistic group names: {msg['lgs']!r}")
    if "li" in msg and not (_list(msg["li"]) and all(isinstance(v, str) for v in _items(msg["li"]))):
        out.append(f"gui: li must be item names: {msg['li']!r}")
    rg = msg.get("rg")
    if rg is not None:
        if not (_list(rg) and all(isinstance(r, list) and len(r) == 4 and all(isinstance(v, str) for v in r) for r in _items(rg))):
            out.append(f"gui: rg is [[group, group order, subgroup key, order], ...]: {rg!r}")
        elif len(_items(rg)) != len(_items(msg.get("rl", []))):
            out.append(f"gui: rg must match rl: {msg!r}")
    lc = msg.get("lc")
    if lc is not None:
        if not (isinstance(lc, dict) and lc.get("tu") in (0, 1) and lc.get("rb", 0) in (0, 1)):
            out.append(f"gui: lc is {{tu, rb?, sec}}: {lc!r}")
        else:
            out += sections_problems(lc.get("sec", []), "gui lc.sec")
    return out

def sections_problems(v, where):
    """Logistic sections (space.lua): [{i, g, on, m, man, f: [[item, quality, min, max, from, mdc]]}]"""
    if not _list(v):
        return [f"{where}: sections must be a list: {v!r}"]
    out = []
    for sec in _items(v):
        if not (isinstance(sec, dict) and _int(sec.get("i")) and isinstance(sec.get("g"), str) and sec.get("on") in (0, 1)
                and _num(sec.get("m")) and sec.get("man") in (0, 1) and _list(sec.get("f"))):
            out.append(f"{where}: a section is {{i, g, on, m, man, f}}: {sec!r}")
            continue
        for f in _items(sec["f"]):
            if not (isinstance(f, list) and len(f) == 6 and isinstance(f[0], str) and isinstance(f[1], str) and _int(f[2])
                    and _int(f[3]) and f[3] >= -1 and isinstance(f[4], str) and _int(f[5]) and f[5] >= -1):
                out.append(f"{where}: a filter is [item, quality, min, max (-1), import from, min delivery (-1)]: {f!r}")
    return out


def space_problems(msg, kind):
    """The fields space.lua adds to `gui`: hub, pad, bay, col, eff, rq, ql."""
    out = []
    owners = {"hub": "hub", "pad": "pad", "bay": "bay", "col": "collector"}
    for field, owner in owners.items():
        if field in msg and kind != owner and not (field == "col" and isinstance(msg[field], list)):
            out.append(f"gui: only {owner} screens have {field}: {msg!r}")
    hub = msg.get("hub")
    if hub is not None:
        if not (isinstance(hub, dict) and _int(hub.get("i")) and isinstance(hub.get("n"), str) and hub.get("st") in PLATFORM_STATES
                and hub.get("pa") in (0, 1) and _num(hub.get("sp")) and _int(hub.get("w")) and hub.get("prov") in (0, 1)
                and isinstance(hub.get("th"), list) and len(hub["th"]) == 2 and all(_int(v) for v in hub["th"])
                and _strs(hub.get("dest"))):
            out.append(f"gui: hub needs i, n, st, pa, sp, w, th [count, working], prov, dest: {hub!r}")
        else:
            if not all(isinstance(f, list) and len(f) == 3 and isinstance(f[0], str) and _int(f[1]) and _int(f[2])
                       for f in _items(hub.get("fuel", []))):
                out.append(f"gui: hub.fuel is [[fluid, amount, capacity], ...]: {hub!r}")
            sched = hub.get("sched")
            if sched is not None:
                if not (isinstance(sched, dict) and _int(sched.get("current")) and _list(sched.get("records"))):
                    out.append(f"gui: hub.sched is {{current, records, group, interrupts}}: {sched!r}")
                else:
                    for rec in _items(sched.get("records")):
                        out += [f"gui: hub.sched: {p}" for p in schedule_record_problems(rec)]
            if "sec" in hub:
                out += sections_problems(hub["sec"], "gui hub.sec")
            if ("from" in hub) != ("to" in hub):
                out.append(f"gui: hub from and to come together: {hub!r}")
    pad = msg.get("pad")
    if pad is not None:
        if not isinstance(pad, dict):
            out.append(f"gui: pad must be an object: {pad!r}")
        else:
            if "sec" in pad:
                out += sections_problems(pad["sec"], "gui pad.sec")
            cb = pad.get("cb")
            if cb is not None and not (isinstance(cb, dict) and all(cb.get(k) in (0, 1) for k in ("read", "req", "empty"))):
                out.append(f"gui: pad.cb is {{read, req, empty}} (0/1): {cb!r}")
    bay = msg.get("bay")
    if bay is not None and not (isinstance(bay, dict) and _int(bay.get("owner"))):
        out.append(f"gui: bay is {{owner (unit or 0)}}: {bay!r}")
    col = msg.get("col") if kind == "collector" else None
    if col is not None and not (isinstance(col, dict) and _int(col.get("n")) and _strs(col.get("f"))
                                and len(_items(col.get("f"))) == col["n"]):
        out.append(f"gui: col is {{n, f: [chunk or \"\"] * n}}: {col!r}")
    eff = msg.get("eff")
    if eff is not None and not (isinstance(eff, dict) and all(k in ("sp", "pr", "co", "po", "q") and _int(v) for k, v in eff.items())):
        out.append(f"gui: eff is {{sp, pr, co, po, q}} in thousandths: {eff!r}")
    if "rq" in msg and not (isinstance(msg["rq"], str) and kind in ("crafter", "furnace")):
        out.append(f"gui: rq (recipe quality) is a name on crafters and furnaces: {msg!r}")
    if "ql" in msg and not (_strs(msg["ql"]) and _items(msg["ql"])[:1] == ["normal"]):
        out.append(f"gui: ql is the unlocked qualities, normal first: {msg['ql']!r}")
    return out


def requests_problems(v, where):
    if not _list(v):
        return [f"{where}: requests must be a list: {v!r}"]
    out = []
    for r in _items(v):
        if not (isinstance(r, list) and len(r) in (3, 4) and isinstance(r[0], str) and _int(r[1]) and r[1] >= 0
                and _int(r[2]) and r[2] >= -1 and (len(r) == 3 or isinstance(r[3], str))):
            out.append(f"{where}: request must be [item, min, max (-1 none), quality?]: {r!r}")
    return out


def network_problems(net, where):
    if not (isinstance(net, dict) and _int(net.get("id")) and all(
            isinstance(net.get(k), list) and len(net[k]) == 2 and all(_int(v) for v in net[k]) for k in ("log", "con"))):
        return [f"{where}: a network is {{id, log: [available, all], con: [available, all], items?}}: {net!r}"]
    if "items" in net and not (_list(net["items"]) and all(
            isinstance(r, list) and len(r) in (2, 3) and isinstance(r[0], str) and _int(r[1]) for r in _items(net["items"]))):
        return [f"{where}: items must be [[item, count, quality?], ...]: {net['items']!r}"]
    return []


def logistics_problems(lg):
    if not (isinstance(lg, dict) and lg.get("mode") in LOGISTIC_MODES):
        return [f"gui: lg must have a logistic mode: {lg!r}"]
    out = []
    if "requests" in lg:
        out += requests_problems(lg["requests"], "gui lg")
    if "filter" in lg and not isinstance(lg["filter"], str):
        out.append(f"gui: lg.filter is an item name or \"\": {lg!r}")
    if "net" in lg:
        out += network_problems(lg["net"], "gui lg.net")
    return out


def schedule_record_problems(rec):
    if not isinstance(rec, dict):
        return [f"schedule record must be an object: {rec!r}"]
    out = []
    if not (isinstance(rec.get("station"), str) or (isinstance(rec.get("rail"), list) and len(rec["rail"]) == 2
                                                    and all(_int(v) for v in rec["rail"]))):
        out.append(f"schedule record needs a station or a rail [x, y]: {rec!r}")
    for w in _items(rec.get("wait_conditions", [])):
        if not (isinstance(w, dict) and isinstance(w.get("type"), str)):
            out.append(f"wait condition needs a type: {w!r}")
    return out


def train_info_problems(tr):
    if not isinstance(tr, dict):
        return [f"gui: tr must be an object: {tr!r}"]
    out = []
    if not (_int(tr.get("id")) and isinstance(tr.get("state"), str) and tr.get("manual") in (0, 1)
            and isinstance(tr.get("station"), str) and isinstance(tr.get("dest"), str)):
        out.append(f"gui: tr must have id, state, manual (0/1), station and dest: {tr!r}")
    if not isinstance(tr.get("name", ""), str):
        out.append(f"gui: tr.name is the open rolling stock's name: {tr!r}")
    sched = tr.get("sched")
    if sched is not None:
        if not (isinstance(sched, dict) and _int(sched.get("current")) and _list(sched.get("records"))
                and isinstance(sched.get("group", ""), str)):
            out.append(f"gui: tr.sched must be {{current, records, group}}: {sched!r}")
        else:
            for rec in _items(sched.get("records")):
                out += [f"gui: tr.sched: {p}" for p in schedule_record_problems(rec)]
            for it in _items(sched.get("interrupts", [])):
                if not (isinstance(it, dict) and isinstance(it.get("name"), str) and _list(it.get("conditions", []))
                        and _list(it.get("targets", []))):
                    out.append(f"gui: tr.sched.interrupts are {{name, conditions, targets, inside_interrupt}}: {it!r}")
                    continue
                for w in _items(it.get("conditions", [])):
                    if not (isinstance(w, dict) and isinstance(w.get("type"), str)):
                        out.append(f"gui: tr interrupt condition needs a type: {w!r}")
                for rec in _items(it.get("targets", [])):
                    out += [f"gui: tr interrupt target: {p}" for p in schedule_record_problems(rec)]
    for key in ("cargo", "fuel"):
        if key in tr and not all(isinstance(r, list) and len(r) in (2, 3) and isinstance(r[0], str) and _int(r[1])
                                 for r in _items(tr[key])):
            out.append(f"gui: tr.{key} must be [[item, count, quality?], ...]: {tr[key]!r}")
    if "fluids" in tr and not all(isinstance(r, list) and len(r) == 2 and isinstance(r[0], str) and _num(r[1])
                                  for r in _items(tr["fluids"])):
        out.append(f"gui: tr.fluids must be [[fluid, amount], ...]: {tr['fluids']!r}")
    if "gc" in tr and not _int(tr["gc"]):
        out.append(f"gui: tr.gc (trains in its group) is an integer: {tr['gc']!r}")
    if "groups" in tr and not (_list(tr["groups"]) and all(isinstance(g, list) and len(g) == 2 and isinstance(g[0], str) and _int(g[1])
                                                          for g in _items(tr["groups"]))):
        out.append(f"gui: tr.groups is [[group, trains], ...]: {tr['groups']!r}")
    if "stops" in tr and not _strs(tr["stops"]):
        out.append(f"gui: tr.stops must be names: {tr['stops']!r}")
    if "pos" in tr and not (isinstance(tr["pos"], list) and len(tr["pos"]) == 2 and all(_int(v) for v in tr["pos"])):
        out.append(f"gui: tr.pos must be [x, y] fixed: {tr['pos']!r}")
    return out


PLATFORM_STATES = {"waiting_for_starter_pack", "starter_pack_requested", "starter_pack_on_the_way", "on_the_path",
                   "waiting_for_departure", "no_schedule", "no_path", "waiting_at_station", "paused"}


def surface_field_problems(msg, t):
    """The surface fields of welcome and surface: name, index, and pf (platform) or planet."""
    out = []
    if not isinstance(msg.get("surface"), str):
        out.append(f"{t}: bad or missing surface: {msg.get('surface')!r}")
    if "si" in msg and not _int(msg["si"]):
        out.append(f"{t}: si is the surface index: {msg['si']!r}")
    if "pf" in msg and not (_int(msg["pf"]) and msg["pf"] > 0):
        out.append(f"{t}: pf is the platform's index: {msg['pf']!r}")
    if "planet" in msg and not isinstance(msg["planet"], str):
        out.append(f"{t}: planet is a name: {msg['planet']!r}")
    if "pf" in msg and "planet" in msg:
        out.append(f"{t}: a surface is a platform (pf) or a planet's, not both")
    return out


def platform_problems(rec):
    if not isinstance(rec, dict):
        return [f"plat: platform must be an object: {rec!r}"]
    out = []
    if not (_int(rec.get("i")) and isinstance(rec.get("n"), str) and rec.get("st") in PLATFORM_STATES
            and rec.get("pa") in (0, 1) and _int(rec.get("hub")) and _num(rec.get("sp"))):
        out.append(f"plat: platform needs i, n, st (a state name), pa (0/1), hub and sp: {rec!r}")
    for k in ("loc", "from", "to", "nx"):
        if k in rec and not isinstance(rec[k], str):
            out.append(f"plat: {k} is a location name: {rec!r}")
    if ("from" in rec) != ("to" in rec) or ("from" in rec) != ("d" in rec):
        out.append(f"plat: from, to and d come together (travelling): {rec!r}")
    if "d" in rec and not (_int(rec["d"]) and 0 <= rec["d"] <= 1000):
        out.append(f"plat: d is thousandths of the way: {rec!r}")
    if "len" in rec and not _int(rec["len"]):
        out.append(f"plat: len is the connection's length in km: {rec!r}")
    if "nx" in rec and "loc" not in rec:
        out.append(f"plat: nx (the next stop) comes with loc (stopped somewhere): {rec!r}")
    if "w" in rec and not (_int(rec["w"]) and rec["w"] >= 0):
        out.append(f"plat: w is the platform's mass in kg: {rec!r}")
    sch = rec.get("sch")
    if sch is not None and not (isinstance(sch, dict) and _int(sch.get("c")) and _strs(sch.get("l"))):
        out.append(f"plat: sch must be {{c, l = [station names]}}: {sch!r}")
    return out


def equipment_grid_problems(msg):
    """eq: an equipment grid (kind "char": the character's armour, "veh": a vehicle's, with its unit)."""
    out = []
    if msg.get("kind") not in ("char", "veh"):
        out.append(f"eq: kind is \"char\" or \"veh\": {msg.get('kind')!r}")
    for k in ("u", "w", "h"):
        if not (_int(msg.get(k)) and msg[k] >= 0):
            out.append(f"eq: bad or missing {k}: {msg.get(k)!r}")
    if not _list(msg.get("l")):
        out.append(f"eq: l must be a list: {msg.get('l')!r}")
    for rec in _items(msg.get("l")):
        if not (isinstance(rec, list) and len(rec) == 11 and isinstance(rec[0], str) and all(_int(v) for v in rec[1:5])
                and isinstance(rec[5], str) and all(_int(v) and v >= 0 for v in rec[6:10]) and rec[10] in (0, 1)):
            out.append(f"eq: equipment must be [name, x, y, w, h, quality, energy, max energy, shield, max shield, ghost 0/1]: {rec!r}")
        elif _int(msg.get("w")) and _int(msg.get("h")) and not (0 <= rec[1] and rec[1] + rec[3] <= msg["w"]
                                                                and 0 <= rec[2] and rec[2] + rec[4] <= msg["h"]):
            out.append(f"eq: equipment outside the {msg.get('w')}x{msg.get('h')} grid: {rec!r}")
    if msg.get("w"):
        for k in ("sh", "msh", "bat", "mbat", "gen", "mv", "inv"):
            if not _int(msg.get(k)):
                out.append(f"eq: bad or missing {k}: {msg.get(k)!r}")
        for k in ("mvon", "nv"):
            if msg.get(k) not in (0, 1):
                out.append(f"eq: {k} must be 0 or 1: {msg.get(k)!r}")
    if "rb" in msg and msg["rb"] not in (0, 1):
        out.append(f"eq: rb (roboport on) must be 0 or 1: {msg['rb']!r}")
    return out


def item_use_problems(rec):
    """[item, kind, ...]: "t" tiles, "c" capsules, "r" rail planners, "b" belts, "p" pipes, "m" modules."""
    if not (isinstance(rec, list) and len(rec) >= 3 and isinstance(rec[0], str) and rec[1] in ("t", "c", "r", "b", "p", "m")):
        return [f"entry must start with item name and kind t|c|r|b|p|m: {rec!r}"]
    kind = rec[1]
    if kind == "t" and not (len(rec) == 5 and isinstance(rec[2], str) and isinstance(rec[3], str) and _list(rec[4])
                            and all(_int(v) for v in _items(rec[4]))):
        return [f"tile entry must be [item, \"t\", tile, other direction or \"\", [tile ids]]: {rec!r}"]
    if kind == "c" and not (len(rec) == 5 and isinstance(rec[2], str) and _num(rec[3]) and _num(rec[4])):
        return [f"capsule entry must be [item, \"c\", action type, range, radius]: {rec!r}"]
    if kind == "r" and not (len(rec) == 4 and isinstance(rec[2], str) and rec[3] in (0, 1)):
        return [f"rail planner entry must be [item, \"r\", support, elevated 0|1]: {rec!r}"]
    if kind in ("b", "p") and not (len(rec) == 3 and isinstance(rec[2], str)):
        return [f"belt / pipe entry must be [item, kind, underground item]: {rec!r}"]
    if kind == "m" and not (len(rec) == 3 and isinstance(rec[2], str)):
        return [f"module entry must be [item, 'm', category]: {rec!r}"]
    return []


def problems(msg):
    out = []
    if not isinstance(msg, dict):
        return [f"message is not an object: {msg!r}"]
    t = msg.get("t")
    if t not in RELIABLE | IMMEDIATE:
        return [f"unknown message type {t!r}"]
    if not _int(msg.get("k")):
        out.append(f"{t}: missing tick k")
    if t in RELIABLE and not _int(msg.get("r")):
        out.append(f"{t}: reliable message without sequence number r")
    if t in IMMEDIATE and "r" in msg:
        out.append(f"{t}: immediate message must not carry r")

    def need(*fields, check=_int):
        for f in fields:
            if not check(msg.get(f)):
                out.append(f"{t}: bad or missing {f}: {msg.get(f)!r}")

    if t == "welcome":
        need("v", "u", "x", "y")
        need("mp", check=lambda v: isinstance(v, bool))
        out += surface_field_problems(msg, t)
    elif t == "surface":
        need("si", "x", "y")
        out += surface_field_problems(msg, t)
    elif t == "plat":
        need("on")
        need("l", check=_list)
        need("dest", check=_strs)
        if "here" in msg and not isinstance(msg["here"], str):
            out.append(f"plat: here is a planet name: {msg['here']!r}")
        for rec in _items(msg.get("l")):
            out += platform_problems(rec)
    elif t in DICTIONARY_WIDTH:
        need("part", "parts")
        need("l", check=_list)
        width = DICTIONARY_WIDTH[t]
        for rec in _items(msg.get("l")):
            # An item record may add the name of the entity it builds when that differs.
            widths = (2, 3) if t == "iprotos" else (width,)
            if not isinstance(rec, list) or len(rec) not in widths:
                out.append(f"{t}: record must have {width} values: {rec!r}")
            elif t == "iprotos" and len(rec) == 3 and not isinstance(rec[2], str):
                out.append(f"iprotos: the third value is the entity it builds: {rec!r}")
            elif not (_int(rec[0]) and isinstance(rec[1], str)):
                out.append(f"{t}: record must start with id and name: {rec!r}")
            elif t == "protos" and not (isinstance(rec[2], str) and all(_num(v) for v in rec[3:7]) and all(_int(v) for v in rec[7:12])):
                out.append(f"protos: bad record {rec!r}")
            elif t in ("tprotos", "fprotos") and not all(_int(v) for v in rec[2:5]):
                out.append(f"tprotos: bad colour {rec!r}")
    elif t == "chunk":
        need("cx", "cy")
        if msg.get("none") is not True:
            need("parts")
            tiles = msg.get("tiles")
            if not isinstance(tiles, list) or len(tiles) % 2 or not all(_int(v) for v in tiles):
                out.append("chunk: tiles must be [id, count, ...] integers")
            elif sum(tiles[1::2]) != 1024:
                out.append(f"chunk: tiles cover {sum(tiles[1::2])} tiles, not 1024")
    elif t == "ents":
        need("cx", "cy", "part", "parts")
        need("e", check=_list)
        for rec in _items(msg.get("e")):
            out += entity_record_problems(rec, "ents")
            if isinstance(rec, list) and len(rec) >= 4 and _int(rec[2]) and _int(rec[3]):
                if (rec[2] // 256 // 32, rec[3] // 256 // 32) != (msg.get("cx"), msg.get("cy")):
                    out.append(f"ents: entity {rec!r} is not inside chunk ({msg.get('cx')}, {msg.get('cy')})")
    elif t == "dec":
        need("cx", "cy", "part", "parts")
        l = msg.get("l")
        if not _list(l) or len(_items(l)) % 4 or not all(_int(v) for v in _items(l)):
            out.append("dec: l must be [decorative id, x, y, amount, ...] integers")
        else:
            items = _items(l)
            for i in range(0, len(items), 4):
                if not (0 <= items[i + 1] < 32 and 0 <= items[i + 2] < 32 and items[i] > 0 and items[i + 3] > 0):
                    out.append(f"dec: decorative {items[i:i + 4]!r} must be an id, a tile within the chunk and an amount")
                    break
    elif t in ("add", "upd"):
        out += entity_record_problems(msg.get("e"), t)
    elif t in ("del", "died"):
        need("u", "p", "x", "y")
    elif t == "tiles":
        l = msg.get("l")
        if not isinstance(l, list) or len(l) % 3 or not all(_int(v) for v in l):
            out.append("tiles: l must be [x, y, id, ...] integers")
    elif t == "st":
        l = msg.get("l")
        if not isinstance(l, list) or len(l) % 2 or not all(_int(v) for v in l) or not all(v in (0, 1, 2, 3, 4) for v in l[1::2]):
            out.append("st: l must be [unit, state 0-4, ...]")
    elif t == "mv":
        need("part", "parts")
        if msg.get("z", 1) != 1:
            out.append(f"mv: z must be 1 (delta-coded) or absent: {msg.get('z')!r}")
        if "p" in msg and not (_int(msg["p"]) and msg["p"] >= 1):
            out.append(f"mv: p (ticks between updates) must be a positive integer: {msg['p']!r}")
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not isinstance(rec, list) or len(rec) not in (4, 5) or not all(_int(v) for v in rec):
                out.append(f"mv: mover must be 4 or 5 integers: {rec!r}")
    elif t in ("bi", "ih", "gi", "fl", "pw", "ht"):
        need("part", "parts")
        l = msg.get("l")
        width = {"gi": 3, "fl": 6, "pw": 2, "ht": 2}.get(t, 4)
        if not _list(l) or len(_items(l)) % width or not all(_int(v) for v in _items(l)):
            out.append(f"{t}: l must be flat groups of {width} integers")
        elif t in ("bi", "ih") and msg.get("z", 1) != 1:
            out.append(f"{t}: z must be 1 (delta-coded) or absent: {msg.get('z')!r}")
        elif t in ("bi", "ih") and "p" in msg and not (_int(msg["p"]) and msg["p"] >= 1):
            out.append(f"{t}: p (ticks between updates) must be a positive integer: {msg['p']!r}")
        elif t == "bi" and any(k in msg for k in ("fx", "fy", "fr")) and not (
                all(_int(msg.get(k)) for k in ("fx", "fy", "fr")) and msg["fr"] >= 0):
            out.append(f"bi: fx, fy (1/256 tile) and fr (tiles, >= 0) come together, as integers: {msg.get('fx')!r} {msg.get('fy')!r} {msg.get('fr')!r}")
        elif t == "pw" and not all(v in (0, 1, 2) for v in _items(l)[1::2]):
            out.append(f"pw: states must be 0 (no power), 1 (low power) or 2 (not connected): {l!r}")
    elif t == "en":
        l = msg.get("l")
        if not _list(l) or not _items(l) or len(_items(l)) % 3 or not all(_int(v) for v in _items(l)):
            out.append("en: l must be flat groups of 3 integers (unit, target x, target y), not empty")
        elif not all(v > 0 for v in _items(l)[0::3]):
            out.append(f"en: units must be positive: {l!r}")
    elif t == "sky":
        need("d", "n")
        if _int(msg.get("d")) and _int(msg.get("n")) and not (0 <= msg["d"] < 1000 and 0 <= msg["n"] <= 1000):
            out.append(f"sky: d and n must be thousandths: {msg!r}")
    elif t == "me":
        need("u", "x", "y", "d", "w", "hp", "q")
        if "m" in msg:
            need("m", "mx", "my")
        if "mhp" in msg:
            need("mhp")
        if "sh" in msg and msg["sh"] not in (0, 1):
            out.append(f"me: sh must be 0 or 1: {msg['sh']!r}")
        if "a" in msg and not (_int(msg["a"]) and 0 <= msg["a"] < 1000):
            out.append(f"me: a must be thousandths of a turn: {msg['a']!r}")
        if ("sd" in msg) != ("msd" in msg):
            out.append(f"me: sd (shield) and msd (most shield) come together: {msg!r}")
        elif "sd" in msg:
            need("sd", "msd")
        if "hub" in msg:
            need("hub")
        if "pod" in msg:
            need("pod", "gx", "gy", "up")
            if not isinstance(msg.get("ps"), str):
                out.append(f"me: ps (the pod's state) must be a string: {msg.get('ps')!r}")
            if msg.get("up") not in (0, 1):
                out.append(f"me: up must be 0 or 1: {msg.get('up')!r}")
    elif t == "eq":
        out += equipment_grid_problems(msg)
    elif t == "cinfo":
        need("craft", "mine", "run", "speed", "eqmv", "reach", "build", "rreach", "pick", "loot", "drop", "invb", "eqinv",
             "trash", "hp", "hpb", "robots", "slots")
    elif t == "dead":
        need("left")
        if ("x" in msg) != ("y" in msg):
            out.append(f"dead: x and y come together: {msg!r}")
        elif "x" in msg:
            need("x", "y")
    elif t == "bonus":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 3 and isinstance(rec[0], str) and _num(rec[1]) and _list(rec[2])
                    and all(isinstance(v, str) for v in _items(rec[2]))):
                out.append(f"bonus: entry must be [kind, value, [item names]]: {rec!r}")
    elif t == "perms":
        need("me", check=lambda v: isinstance(v, str))
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 2 and isinstance(rec[0], str) and _list(rec[1])
                    and all(isinstance(v, str) for v in _items(rec[1]))):
                out.append(f"perms: entry must be [group name, [player names]]: {rec!r}")
    elif t == "pl":
        need("me", "u")
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) in (11, 12) and _int(rec[0]) and isinstance(rec[1], str) and rec[2] in (0, 1)
                    and all(_int(v) and 0 <= v <= 255 for v in rec[3:6]) and _int(rec[6]) and isinstance(rec[7], str)
                    and rec[8] in (0, 1) and _int(rec[9]) and isinstance(rec[10], str)
                    and all(isinstance(v, str) for v in rec[11:])):
                out.append(f"pl: entry must be [index, name, connected 0/1, r, g, b, character unit, surface, admin 0/1, "
                           f"afk ticks, tag, armour?]: {rec!r}")
    elif t == "guns":
        need("sel")
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) in (3, 5) and isinstance(rec[0], str) and isinstance(rec[1], str)
                    and all(_int(v) for v in rec[2:])):
                out.append(f"guns: slot must be [gun, ammo, count, rounds?, magazine size?]: {rec!r}")
    elif t == "ts":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) in (4, 6) and all(_int(v) for v in rec)
                    and 0 <= rec[1] < 1000 and rec[2] >= 0 and rec[3] >= 0):
                out.append(f"ts: entry must be [unit, orientation 0-999, shots, gun, target x?, target y?]: {rec!r}")
    elif t == "hp":
        need("part", "parts")
        l = msg.get("l")
        if not _list(l) or len(_items(l)) % 2 or not all(_int(v) for v in _items(l)):
            out.append("hp: l must be flat pairs of integers")
        elif not all(0 <= v <= 1000 for v in _items(l)[1::2]):
            out.append(f"hp: health must be thousandths: {l!r}")
        if "v" in msg or "vs" in msg:
            need("v", "vs")
    elif t == "inv":
        out += item_counts_problems(msg.get("l"), "inv")
    elif t == "gui":
        out += gui_problems(msg)
    elif t == "chart":
        need("cx", "cy", "n")
        if "si" in msg:
            need("si")
        n = msg.get("n")
        if _int(n) and n > 0:
            if n not in (1, 2, 4, 8, 16):
                out.append(f"chart: n must be 32 / (2, 4, 8, 16 or 32): {n!r}")
            pal, px = msg.get("pal"), msg.get("px")
            if not (isinstance(pal, list) and pal and all(
                    isinstance(c, list) and len(c) == 3 and all(_int(v) and 0 <= v <= 255 for v in c) for c in pal)):
                out.append(f"chart: pal must be [[r, g, b], ...] (0-255): {pal!r}")
                pal = []
            if not (isinstance(px, list) and len(px) == n * n and all(_int(v) and 0 <= v < len(pal) for v in px)):
                out.append(f"chart: px must be n * n indices into pal: {px!r}")
        elif n != 0:
            out.append(f"chart: n must be 0 (not charted) or the side in pixels: {n!r}")
        if "pol" in msg and not (_int(msg["pol"]) and msg["pol"] >= 0):
            out.append(f"chart: pol must be a whole number >= 0: {msg['pol']!r}")
        ov = msg.get("ov")
        if ov is not None:
            sizes = {"e": 4, "w": 5, "t": 4, "l": 5, "s": 4, "g": 4, "c": 4, "b": 3}
            if not isinstance(ov, list):
                out.append(f"chart: ov must be a list: {ov!r}")
            else:
                for r in ov:
                    if not (isinstance(r, list) and r and r[0] in sizes and len(r) == sizes[r[0]]
                            and _int(r[1]) and _int(r[2])):
                        out.append(f"chart: ov entries are [kind, x, y, ...] (e t l s g c b): {r!r}")
                        break
                    if r[0] in ("e", "t", "l") and not all(isinstance(v, (int, float)) and v >= 0 for v in r[3:]):
                        out.append(f"chart: ov radii must be numbers >= 0: {r!r}")
                    if r[0] == "w" and not (_int(r[3]) and _int(r[4])):
                        out.append(f"chart: ov wire needs the other pole's x, y: {r!r}")
                    if r[0] in ("s", "c") and not isinstance(r[3], str):
                        out.append(f"chart: ov {r[0]} needs a name: {r!r}")
                    if r[0] == "g" and r[3] not in (0, 1, 2, 3):
                        out.append(f"chart: ov signal state must be 0-3: {r!r}")
    elif t == "planet":
        need("name", check=lambda v: isinstance(v, str))
        props = msg.get("props")
        if not (isinstance(props, dict) or props == []) or not all(isinstance(k, str) and _num(v) for k, v in (props or {}).items()):
            out.append(f"planet: props is {{property: value}}: {props!r}")
        for k in ("day", "always", "mb", "sol", "dusk", "evening", "morning", "dawn"):
            if k in msg and not _int(msg[k]):
                out.append(f"planet: {k} must be an integer: {msg[k]!r}")
        if not (_list(msg.get("heat")) and all(isinstance(h, list) and len(h) == 2 and _int(h[0]) and _num(h[1])
                                                for h in _items(msg.get("heat")))):
            out.append(f"planet: heat is [[entity prototype id, heating radius], ...]: {msg.get('heat')!r}")
        if "nb" in msg and not (_list(msg["nb"]) and all(isinstance(r, list) and len(r) == 4 and _int(r[0]) and isinstance(r[1], str)
                                                        and _num(r[2]) and _num(r[3]) for r in _items(msg["nb"]))):
            out.append(f"planet: nb is [[entity prototype id, property, min, max], ...]: {msg['nb']!r}")
    elif t == "seg":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 3 and _int(rec[0]) and _int(rec[1]) and _list(rec[2])
                    and len(_items(rec[2])) % 4 == 0 and all(_int(v) for v in _items(rec[2]))):
                out.append(f"seg: entry must be [unit, proto id, [segment proto id, x, y, orientation, ...]]: {rec!r}")
    elif t == "lt":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 3 and _int(rec[0]) and _int(rec[1]) and rec[2] in (0, 1)):
                out.append(f"lt: strike must be [x, y, caught 0/1]: {rec!r}")
    elif t == "legs":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 2 and _int(rec[0]) and _list(rec[1])
                    and len(_items(rec[1])) % 2 == 0 and all(_int(v) for v in _items(rec[1]))):
                out.append(f"legs: entry must be [unit, [x, y, ...]]: {rec!r}")
    elif t == "cp":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 4 and _int(rec[0]) and all(isinstance(v, str) for v in rec[1:])):
                out.append(f"cp: entry must be [unit, state, destination type, destination surface]: {rec!r}")
    elif t in ("pg", "sp", "fz", "bf"):
        if t == "bf":
            need("part", "parts")
        l = msg.get("l")
        width = {"pg": 4, "sp": 2, "fz": 1, "bf": 2}[t]
        if not (_list(l) and len(_items(l)) % width == 0 and all(_int(v) for v in _items(l))):
            out.append(f"{t}: l must be flat groups of {width} integers: {l!r}")
        elif t in ("pg", "bf") and not all(0 <= v <= 1000 for v in _items(l)[width - 1::width]):
            out.append(f"{t}: growth or freshness is in thousandths: {l!r}")
    elif t == "pj":
        # Flat groups: p [id, name, x, y], b [id, name, sx, sy, tx, ty], x [name, x, y], e [id, x, y].
        for key, width, names in (("p", 4, (1,)), ("b", 6, (1,)), ("x", 3, (0,)), ("e", 3, ())):
            l = msg.get(key)
            items = _items(l) if _list(l) else None
            if items is None or len(items) % width:
                out.append(f"pj: {key} must be flat groups of {width}: {l!r}")
                continue
            for i, v in enumerate(items):
                if (i % width in names and not (isinstance(v, str) and v)) or (i % width not in names and not _int(v)):
                    out.append(f"pj: {key} group {i // width} is wrong: {items[i - i % width:i - i % width + width]!r}")
                    break
    elif t == "gf":
        l = msg.get("l")
        items = _items(l) if _list(l) else None
        if items is None or len(items) % 5 or not all(
                (isinstance(v, str) and v) if i % 5 == 1 else _int(v) for i, v in enumerate(items)):
            out.append(f"gf: l must be flat groups of [id, name, x, y, ticks to live or -1]: {l!r}")
    elif t == "shot":
        need("u", "x", "y")
        if not (isinstance(msg.get("g"), str) and msg.get("g") and isinstance(msg.get("a"), str)):
            out.append(f"shot: g (gun) and a (ammo) must be names: {msg!r}")
    elif t == "ach":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 5 and isinstance(rec[0], str) and all(_int(v) for v in rec[1:])):
                out.append(f"ach: chunk must be [name, x, y, vx, vy]: {rec!r}")
    elif t == "acol":
        if "l" not in msg and "g" not in msg:
            out.append(f"acol: needs l (collectors) or g (caught chunks): {msg!r}")
        if "l" in msg:
            need("l", check=_list)
            for rec in _items(msg.get("l")):
                filters = _items(rec[4]) if isinstance(rec, list) and len(rec) == 5 and _list(rec[4]) else None
                if not (filters is not None and all(_int(v) for v in rec[:4]) and rec[1] >= 1 and rec[2] >= 0 and rec[3] in (0, 1, 2)
                        and all(isinstance(f, str) and f for f in filters)):
                    out.append(f"acol: collector must be [unit, arms, speed, moving 0/1/2, [chunk filter, ...]]: {rec!r}")
        if "g" in msg:
            need("g", check=_list)
            for rec in _items(msg.get("g")):
                if not (isinstance(rec, list) and len(rec) == 4 and _int(rec[0]) and isinstance(rec[1], str) and rec[1]
                        and _int(rec[2]) and _int(rec[3])):
                    out.append(f"acol: caught chunk must be [unit, chunk name, x, y]: {rec!r}")
    elif t == "bq":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 2 and _int(rec[0]) and isinstance(rec[1], str) and rec[1] != "normal"):
                out.append(f"bq: entry must be [unique id, quality (not normal)]: {rec!r}")
    elif t == "smap":
        need("loc", "con", check=_list)
        for rec in _items(msg.get("loc")):
            if not (isinstance(rec, list) and len(rec) in (6, 9) and isinstance(rec[0], str) and isinstance(rec[1], str)
                    and _int(rec[2]) and _int(rec[3]) and rec[4] in (0, 1) and rec[5] in (0, 1)
                    and (len(rec) == 6 or (_int(rec[6]) and rec[7] in (0, 1) and _int(rec[8])))):
                out.append(f"smap: location must be [name, type, x, y, unlocked, has surface, magnitude, draw orbit, "
                           f"label orientation]: {rec!r}")
        for rec in _items(msg.get("con")):
            if not (isinstance(rec, list) and len(rec) == 4 and isinstance(rec[0], str) and isinstance(rec[1], str)
                    and _int(rec[2]) and _int(rec[3]) and 0 <= rec[3] <= 1000):
                out.append(f"smap: connection must be [from, to, length, danger 0-1000]: {rec!r}")
    elif t == "rk":
        need("u", "x", "y")
        need("s", check=lambda v: isinstance(v, str))
    elif t == "pst":
        need("i")
        need("st", "old", "loc", check=lambda v: isinstance(v, str))
    elif t == "ln":
        need("id")
        if msg.get("id"):
            out += network_problems(msg, "ln")
    elif t == "rc":
        l = msg.get("l")
        if not (_list(l) and len(_items(l)) % 3 == 0 and all(_int(v) for v in _items(l))):
            out.append(f"rc: l must be flat [unit, item id, count, ...]: {l!r}")
    elif t == "clog":
        if not (msg.get("on") in (0, 1) and msg.get("trash") in (0, 1)):
            out.append(f"clog: on and trash are 0 or 1: {msg!r}")
        out += requests_problems(msg.get("l"), "clog")
        if "sec" in msg:
            out += sections_problems(msg["sec"], "clog.sec")
        if "lgs" in msg and not (_list(msg["lgs"]) and all(isinstance(g, str) for g in _items(msg["lgs"]))):
            out.append(f"clog: lgs are group names: {msg['lgs']!r}")
    elif t == "ccol":
        c = msg.get("c")
        if not (isinstance(c, list) and len(c) == 3 and all(_int(v) and 0 <= v <= 255 for v in c)):
            out.append(f"ccol: c must be [r, g, b] in 0-255: {c!r}")
    elif t == "tr":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 7 and _int(rec[0]) and isinstance(rec[1], str) and rec[2] in (0, 1)
                    and _int(rec[3]) and _int(rec[4]) and isinstance(rec[5], str) and _list(rec[6])
                    and all(_int(u) for u in _items(rec[6]))):
                out.append(f"tr: entry must be [id, state, manual 0/1, speed, station unit, destination, [units]]: {rec!r}")
    elif t == "spd":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 2 and _int(rec[0]) and _list(rec[1])
                    and all(isinstance(p, list) and len(p) == 2 and _int(p[0]) and _int(p[1]) for p in _items(rec[1]))):
                out.append(f"spd: entry must be [unit, [[x, y], ...]]: {rec!r}")
    elif t == "trl":
        need("part", "parts")
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 13 and _int(rec[0]) and isinstance(rec[1], str) and rec[2] in (0, 1)
                    and isinstance(rec[3], str) and isinstance(rec[4], str) and all(_int(v) for v in rec[5:11])
                    and _list(rec[11]) and _list(rec[12])):
                out.append(f"trl: entry must be [id, state, manual, stop, group, carriages, front unit, x, y, surface, speed, "
                           f"[[item, count]...], [[fluid, amount]]]: {rec!r}")
    elif t == "surfs":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 5 and _int(rec[0]) and all(isinstance(v, str) for v in rec[1:4])
                    and _int(rec[4]) and ((rec[2] == "") != (rec[3] == "") or (rec[2] == rec[3] == "" and rec[4] == 0))):
                out.append(f"surfs: entry must be [index, name, planet or \"\", platform name or \"\", platform index] "
                           f"(both \"\" for another surface): {rec!r}")
    elif t == "unghost":
        need("q", "n")
    elif t == "hinfo":
        need("q", "u")
        if "eff" in msg and not (isinstance(msg["eff"], dict) and all(k in ("sp", "pr", "co", "po", "q") and _int(v) for k, v in msg["eff"].items())):
            out.append(f"hinfo: eff is {{sp, pr, co, po, q}} in thousandths: {msg!r}")
        for rec in _items(msg.get("m", [])):
            if not (_list(rec) and len(rec) >= 2 and isinstance(rec[0], str) and _int(rec[1])):
                out.append(f"hinfo: a module is [name, count, quality?]: {rec!r}")
        for k in ("b", "n", "de"):
            if k in msg:
                need(k)
        if "el" in msg and not (isinstance(msg["el"], dict) and set(msg["el"]) == {"e", "b", "mx", "mn"}
                                and all(_num(v) and v >= 0 for v in msg["el"].values())):
            out.append(f"hinfo: el is {{e, b, mx, mn}}: joules in the buffer, its size, max. and min. consumption (W): {msg!r}")
        if "rn" in msg and not (_list(msg["rn"]) and len(_items(msg["rn"])) % 2 == 0 and all(_int(v) for v in _items(msg["rn"]))):
            out.append(f"hinfo: rn is [x, y, ...]: the linked roboports' positions in 1/256 tiles: {msg!r}")
    elif t == "cmdr":
        need("id")
        need("l", check=_list)
        if not all(isinstance(v, str) for v in _items(msg.get("l"))):
            out.append(f"cmdr: l is the answer's lines as strings: {msg.get('l')!r}")
        if msg.get("ok", 0) not in (0,):
            out.append(f"cmdr: ok is only sent as 0 (the bridge doesn't run that command): {msg.get('ok')!r}")
    elif t == "bfar":
        need("cx", "cy")
        need("l", check=_list)
        lanes = _items(msg.get("l"))
        if len(lanes) % 5 or not all(_int(v) for v in lanes) or any(not 0 <= lanes[i + 2] < 16 for i in range(0, len(lanes), 5)):
            out.append(f"bfar: l is [x, y, direction (0-15), lane 1 item, lane 2 item, ...] as integers: {lanes[:10]!r}")
        elif "c" in msg:
            counts = _items(msg.get("c"))
            if not _list(msg.get("c")) or len(counts) != len(lanes) // 5 * 2 or not all(_int(v) and 0 <= v <= 4 for v in counts):
                out.append(f"bfar: c is two counts (0-4) per belt in l: {counts[:10]!r}")
    elif t == "mtr":
        need("si", "part", "parts")
        need("l", check=_list)
        cars = _items(msg.get("l"))
        if len(cars) % 6 or not all(_int(v) for v in cars):
            out.append(f"mtr: l is [x, y, orientation, length, width, colour, ...] as integers: {cars[:12]!r}")
        elif any(not (0 <= cars[i + 2] < 1000 and cars[i + 3] > 0 and cars[i + 4] > 0 and 0 <= cars[i + 5] <= 0xFFFFFF)
                 for i in range(0, len(cars), 6)):
            out.append(f"mtr: orientation 0-999, sizes above 0, colour 0xRRGGBB: {cars[:12]!r}")
        if "cov" in msg:
            cov = _items(msg.get("cov"))
            if not _list(msg.get("cov")) or len(cov) % 3 or not all(_int(v) for v in cov):
                out.append(f"mtr: cov is [cx, cy, d, ...] as integers: {msg.get('cov')!r}")
    elif t == "mrp":
        need("si", "q", "part", "last")
        need("l", check=_list)
        ports = _items(msg.get("l"))
        if len(ports) % 4 or not all(_int(v) for v in ports):
            out.append(f"mrp: l is [x, y, logistic radius, construction radius, ...] as integers: {ports[:12]!r}")
        elif any(ports[i + 2] < 0 or ports[i + 3] < 0 for i in range(0, len(ports), 4)):
            out.append(f"mrp: radii are not negative: {ports[:12]!r}")
        if msg.get("last") not in (0, 1):
            out.append(f"mrp: last is 0 or 1: {msg!r}")
    elif t == "lpad":
        need("si", "q")
        if ("x" in msg) != ("y" in msg) or ("x" in msg and not (_int(msg["x"]) and _int(msg["y"]))):
            out.append(f"lpad: x and y together, as integers: {msg!r}")
    elif t == "wb":
        need("b", "avg", "max", "over", "n")
        if _int(msg.get("b")) and msg["b"] <= 0:
            out.append(f"wb: the budget b is above 0: {msg!r}")
        q = msg.get("q")
        if not (isinstance(q, dict) or q == []) or not all(isinstance(k, str) and _int(v) and v >= 0 for k, v in (q or {}).items()):
            out.append(f"wb: q maps queue names to lengths: {q!r}")
    elif t == "cov":
        need("si")
        need("l", check=_list)
        cov = _items(msg.get("l"))
        if len(cov) % 3 or not all(_int(v) for v in cov):
            out.append(f"cov: l is [cx, cy, d, ...] as integers: {msg.get('l')!r}")
        if ("x" in msg) != ("y" in msg) or ("x" in msg) != ("cr" in msg):
            out.append(f"cov: the character's x, y and cr come together: {msg!r}")
        elif "x" in msg and not (_int(msg["x"]) and _int(msg["y"]) and _num(msg["cr"]) and msg["cr"] > 0):
            out.append(f"cov: x, y integers (1/256 tile), cr a radius in tiles: {msg!r}")
        if "all" in msg and msg["all"] != 1:
            out.append(f"cov: all is 1 when given: {msg!r}")
    elif t == "terr":
        need("part", "parts")
        if "si" in msg:
            need("si")
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (_list(rec) and len(_items(rec)) % 2 == 0 and all(_int(v) for v in _items(rec))):
                out.append(f"terr: a territory is its chunks [x1, y1, x2, y2, ...]: {rec!r}")
                break
    elif t == "tags":
        if "si" in msg:
            need("si")
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 6 and _int(rec[0]) and _int(rec[1]) and _int(rec[2])
                    and all(isinstance(v, str) for v in rec[3:])):
                out.append(f"tags: entry must be [id, x, y, text, icon type, icon name]: {rec!r}")
    elif t == "recipes":
        need("l", check=_list)
        if not all(isinstance(v, str) for v in _items(msg.get("l"))):
            out.append("recipes: l must be names")
    elif t == "msg":
        need("text", check=lambda v: isinstance(v, str))
        if "tech" in msg and not (isinstance(msg["tech"], str) and _strs(msg.get("unlocks", []))):
            out.append(f"msg: a research notification has tech (name) and unlocks (recipe names): {msg!r}")
    elif t == "slots":
        lists = msg.get("l")
        if not isinstance(lists, dict) or not lists:
            out.append(f"slots: l must be an object of role -> slot list: {lists!r}")
        else:
            for role, lst in lists.items():
                if role not in CHARACTER_ROLES:
                    out.append(f"slots: unknown role {role!r}")
                out += slot_list_problems(lst, f"slots {role}")
        fl = msg.get("fl", [])
        if not (_list(fl) and all(isinstance(f, list) and len(f) == 2 and _int(f[0]) and f[0] >= 1 and isinstance(f[1], str)
                                  for f in _items(fl))):
            out.append(f"slots: fl must be [[slot, item], ...]: {fl!r}")
        ic = msg.get("ic", [])
        if not (_list(ic) and all(isinstance(e, list) and len(e) == 2 and _int(e[0]) and e[0] >= 1 and _list(e[1])
                                  and all(isinstance(i, list) and len(i) == 2 and all(isinstance(v, str) for v in i) for i in _items(e[1]))
                                  for e in _items(ic))):
            out.append(f"slots: ic must be [[slot, [[type, name], ...]], ...]: {ic!r}")
    elif t == "qb":
        need("p", "sel")
        need("held", check=lambda v: isinstance(v, str))
        l = msg.get("l")
        if not (isinstance(l, list) and len(l) == 100 and all(isinstance(v, str) for v in l)):
            out.append("qb: l must be 100 item names or \"\"")
    elif t == "rdet":
        need("part", "parts")
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            out += recipe_detail_problems(rec)
    elif t == "craftable":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 2 and isinstance(rec[0], str) and _int(rec[1]) and rec[1] > 0):
                out.append(f"craftable: entry must be [recipe, count > 0]: {rec!r}")
    elif t == "cq":
        need("pr")
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 4 and _int(rec[0]) and isinstance(rec[1], str) and _int(rec[2]) and rec[3] in (0, 1)):
                out.append(f"cq: entry must be [index, recipe, count, prerequisite 0|1]: {rec!r}")
    elif t == "techs":
        need("part", "parts")
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            out += tech_problems(rec)
    elif t == "eprops":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) in (4, 5) and _int(rec[0]) and all(_num(v) and v >= 0 for v in rec[1:4])):
                out.append(f"eprops: entry must be [proto id, underground reach, wire reach, supply area, overlay?]: {rec!r}")
            elif len(rec) == 5:
                out += [f"eprops: overlay of {rec[0]}: {p}" for p in eprops_overlay_problems(rec[4])]
    elif t == "iuse":
        need("part", "parts")
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            out += [f"iuse: {p}" for p in item_use_problems(rec)]
    elif t == "ai":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) in (3, 4) and _int(rec[0]) and rec[1] in ("item", "fluid", "recipe", "virtual")
                    and isinstance(rec[2], str) and (len(rec) == 3 or (_list(rec[3]) and all(isinstance(v, str) for v in _items(rec[3]))))):
                out.append(f"ai: entry must be [unit, icon type, name, more filters?]: {rec!r}")
    elif t == "clip":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 4 and all(_int(v) for v in rec)):
                out.append(f"clip: entry must be [proto id, x, y, direction]: {rec!r}")
    elif t == "bp":
        need("q", "part", "parts", "i")
        need("s", check=lambda v: isinstance(v, str))
        need("item", check=lambda v: v in PLANNER_ITEMS)
        if _int(msg.get("part")) and _int(msg.get("parts")) and not 1 <= msg["part"] <= msg["parts"]:
            out.append(f"bp: part {msg['part']} of {msg['parts']}")
        if "err" in msg and not isinstance(msg["err"], str):
            out.append("bp: err must be a string")
        if "src" in msg and msg["src"] not in ("game", "player"):
            out.append(f"bp: src must be game or player: {msg['src']!r}")
    elif t == "bp_ok":
        need("q", "i")
        need("item", check=lambda v: v in PLANNER_ITEMS)
    elif t == "bpl":
        need("src", check=lambda v: v in ("game", "player"))
        need("who", check=lambda v: isinstance(v, str))
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 4 and _int(rec[0]) and rec[1] in RECORD_TYPES
                    and isinstance(rec[2], str) and _list(rec[3])
                    and all(isinstance(i, list) and len(i) == 2 and all(isinstance(s, str) for s in i) for i in _items(rec[3]))):
                out.append(f"bpl: record must be [index, type, label, [[icon type, name], ...]]: {rec!r}")
    elif t == "hist":
        need("h")
        need("what", check=lambda v: v in ("blueprint", "deconstruction", "cancel deconstruction", "upgrade", "cancel upgrade",
                                           "settings", "rotation"))
    elif t == "quals":
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 4 and isinstance(rec[0], str) and _int(rec[1]) and rec[2] in (0, 1)
                    and isinstance(rec[3], str) and len(rec[3]) == 6):
                out.append(f"quals: entry must be [name, level, unlocked 0|1, colour rrggbb]: {rec!r}")
    elif t == "chat":
        need("from", "text", check=lambda v: isinstance(v, str))
        if "c" in msg and not (isinstance(msg["c"], list) and len(msg["c"]) == 3 and all(_num(v) for v in msg["c"])):
            out.append(f"chat: c is the player's colour [r, g, b]: {msg['c']!r}")
    elif t == "al":
        out += alert_problems(msg)
    elif t == "pidx":
        need("part", "parts")
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 5 and rec[0] in PEDIA_KINDS and all(isinstance(v, str) for v in rec[1:])):
                out.append(f"pidx: entry must be [kind, name, group, subgroup, order]: {rec!r}")
        if "g" in msg and not (_list(msg["g"]) and all(isinstance(g, list) and len(g) == 2 and all(isinstance(v, str) for v in g)
                                                        for g in _items(msg["g"]))):
            out.append(f"pidx: g must be [[group, order], ...]: {msg['g']!r}")
    elif t == "pedia":
        out += pedia_problems(msg)
    elif t == "lnets":
        out += lnets_problems(msg)
    elif t == "lnet":
        need("id")
        if msg.get("found") == 1:
            out += network_problems(msg, "lnet")
        elif msg.get("found") != 0:
            out.append(f"lnet: found must be 0 or 1: {msg!r}")
    elif t == "stats":
        need("prec")
        need("kind", check=lambda v: v in STATS_KINDS)
        need("l", check=_list)
        for rec in _items(msg.get("l")):
            if not (isinstance(rec, list) and len(rec) == 5 and isinstance(rec[0], str) and all(_num(v) for v in rec[1:])):
                out.append(f"stats: row must be [name, in rate, out rate, in total, out total]: {rec!r}")
        if "si" in msg and not _int(msg["si"]):
            out.append(f"stats: si is a surface index (0 all): {msg['si']!r}")
        for g in _items(msg.get("gr", [])):
            if not (isinstance(g, list) and len(g) == 3 and isinstance(g[0], str) and all(
                    _list(g[i]) and all(_num(v) for v in _items(g[i])) for i in (1, 2))):
                out.append(f"stats: graph line must be [name, [in...], [out...]]: {g!r}")
        for rec in _items(msg.get("st", [])):
            if not (isinstance(rec, list) and len(rec) == 3 and isinstance(rec[0], str) and all(_num(v) for v in rec[1:])):
                out.append(f"stats: storage row must be [name, stored over the time scale, stored now]: {rec!r}")
        if "prec" in msg and not (_int(msg["prec"]) and 1 <= msg["prec"] <= 9):
            out.append(f"stats: prec is 1-8 (5 s ... 1000 h) or 9 (All): {msg['prec']!r}")
        if "ef" in msg and not (isinstance(msg["ef"], list) and len(msg["ef"]) == 6 and all(_num(v) for v in msg["ef"])):
            out.append(f"stats: ef must be [met, demand, used, available, stored, capacity]: {msg['ef']!r}")
    elif t == "rs":
        need("pr")
        need("cur", check=lambda v: isinstance(v, str))
        need("q", check=_strs)
        labs = msg.get("labs", [])
        if not (_list(labs) and all(isinstance(x, list) and len(x) == 2 and _int(x[0]) and isinstance(x[1], str) for x in _items(labs))):
            out.append(f"rs: labs must be [[unit, status name], ...]: {labs!r}")
    return out
