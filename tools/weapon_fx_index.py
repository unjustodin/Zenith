#!/usr/bin/env python3
"""Writes client/data/weapon_fx.json: how Factorio draws what weapons fire and what they leave,
read from its own prototype data (factorio --dump-data, as tools/icon_index.py does).

    python tools/weapon_fx_index.py [--factorio DIR] [--check]

Keeps only file names and numbers: the client loads the sheets from the player's own install at
runtime (client/scripts/fx/weapon_fx.gd). --check reports sheets missing from the install and
writes nothing.

Format (every key short, the file is loaded at start):
  "ex":   {explosion: {"v": [variation, ...], "l": light, "sm": [trivial smoke, count], "rot": 1,
           "beam": 1, "h": height, "snd": sound}}
  "pr":   {projectile or artillery-projectile: {"a": variations, "l": light, "smk": [[smoke, frequency,
           deviation [x, y]], ...], "acc": acceleration, "hit": effects, "art": 1}}
  "st":   {stream: {"p": particle, "sp": spine, "hs": horizontal speed, "va": vertical
           acceleration (tiles per tick), "psi": ticks between particles, "pst": ticks it spawns
           them for, "ss": start scale, "sa": start alpha, "smk": [[smoke, frequency], ...]}}
           A stream entity stays where it was made while its particles fly inside it (2.1.23),
           and the API tells neither its source nor its target.
  "bm":   {beam: {"w": width, "start"|"ending"|"head"|"tail"|"body": variations}}
  "fi":   {fire: {"a": variations, "bp": burnt patch variations, "fin": fade-in ticks,
           "fout": fade-out ticks, "alpha": flame alpha, "l": light}}
  "sw":   {smoke-with-trigger: {"a": variations, "c": colour, "n": particles, "spr": [x, y],
           "dur": ticks, "fade": ticks, "cyc": 1}}
  "ts":   {trivial-smoke: {"a": variations, "dur": ticks, "fin": ticks, "fade": ticks,
           "s0": start scale, "s1": end scale, "c": colour}}
  "sc":   {scorch-mark corpse: {"a": variations of its ground patch}}
  "pa":   {particle: {"a": variations, "life": ticks}}
  "ammo": {ammo or capsule item: {"k": "instant"|"projectile"|"stream"|"beam"|"line", "src": effects,
           "tgt": effects, "p": what it fires, "n": how many, "line": explosion along a line}}
  "gun":  {gun: {"cd": cooldown ticks, "pcd": projectile creation distance, "r": range,
           "k": attack type, "shell": [particle, creation distance, speed, vertical speed]}}
  "dying": {entity: explosion}

A variation is a list of layers; a layer is [files, width, height, frames, line length, speed
(frames per tick), scale, [shift x, shift y], additive, tint or null, [x, y] in the sheet, glow
(draw_as_glow: lit by itself, not dimmed at night)]. `files` lists one file, or Factorio's stripes as [[file, frames across,
frames down], ...]. Shadows and light-only layers are left out. Effects are [[name, only when
visible], ...]: explosions and scorch marks the effect creates. A headless server with no player
never creates the "only when visible" ones (checked in 2.1.23), so the client plays those itself.
"""

import argparse
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
REPO = os.path.dirname(HERE)
sys.path.insert(0, HERE)
import icon_index  # noqa: E402

OUT = os.path.join(REPO, "client", "data", "weapon_fx.json")
SHELL_PARTICLES = ("shell-particle", "shotgun-shell-particle", "railgun-shell-particle", "artillery-shell-particle")


def num(v, digits=4):
    return round(float(v), digits)


def shift_of(s):
    if isinstance(s, dict):
        return [num(s.get("x", 0)), num(s.get("y", 0))]
    if isinstance(s, (list, tuple)) and len(s) == 2:
        return [num(s[0]), num(s[1])]
    return [0, 0]


def tint_of(t):
    if t is None:
        return None
    if isinstance(t, dict):
        t = [t.get("r", 1), t.get("g", 1), t.get("b", 1), t.get("a", 1)]
    t = [float(v) for v in t] + [1.0] * (4 - len(t))
    if max(t[:3]) > 1.0:  # 0..255
        t = [v / 255.0 for v in t[:3]] + [t[3] / 255.0 if t[3] > 1.0 else t[3]]
    return [num(v, 3) for v in t[:4]]


def layer_of(x):
    """One sprite or animation layer, or None for shadows and light-only layers."""
    if not isinstance(x, dict) or x.get("draw_as_shadow") or x.get("draw_as_light"):
        return None
    if "hr_version" in x:
        x = x["hr_version"]
    frames = int(x.get("frame_count", 1) or 1)
    if "stripes" in x:
        files = [[icon_index.file_of(s["filename"]), int(s.get("width_in_frames", 1)), int(s.get("height_in_frames", 1))]
                 for s in x["stripes"]]
        line = files[0][1]
    elif "filenames" in x:
        line = int(x.get("line_length", frames) or frames)
        per = int(x.get("lines_per_file", 1) or 1)
        files = [[icon_index.file_of(f), line, per] for f in x["filenames"]]
    elif "filename" in x:
        files = [icon_index.file_of(x["filename"])]
        line = int(x.get("line_length", 0) or 0) or frames
    else:
        return None
    if "sheet" in x:
        return None
    w = int(x.get("width", x.get("size", 0)) or 0)
    h = int(x.get("height", x.get("size", 0)) or 0)
    if isinstance(x.get("size"), list):
        w, h = int(x["size"][0]), int(x["size"][1])
    repeat = int(x.get("repeat_count", 1) or 1)
    speed = num(x.get("animation_speed", 1))
    if repeat > 1 and frames == 1:
        speed = 0
    additive = x.get("blend_mode") in ("additive", "additive-soft")
    return [files, w, h, frames, line, speed, num(x.get("scale", 1)), shift_of(x.get("shift")), 1 if additive else 0,
            tint_of(x.get("tint")), [int(x.get("x", 0)), int(x.get("y", 0))], 1 if x.get("draw_as_glow") else 0]


def variation_of(x):
    if isinstance(x, dict) and "layers" in x:
        out = []
        for l in x["layers"]:
            out.extend(variation_of(l))
        return out
    if isinstance(x, dict) and "sheet" in x:
        return variation_of(x["sheet"])
    l = layer_of(x)
    return [l] if l else []


def variations(x):
    """Animation, AnimationVariations, Sprite or a list of them -> [[layer, ...], ...]."""
    if x is None:
        return []
    if isinstance(x, dict) and "sheet" in x and isinstance(x["sheet"], dict):
        # SpriteVariations / AnimationSheet: variation_count frames across, one per variation.
        sheet = x["sheet"]
        l = layer_of(dict(sheet, frame_count=1))
        if not l:
            return []
        count = int(sheet.get("variation_count", x.get("variation_count", 1)) or 1)
        line = int(sheet.get("line_length", count) or count)
        out = []
        for i in range(count):
            v = list(l)
            v[10] = [l[10][0] + (i % line) * l[1], l[10][1] + (i // line) * l[2]]
            out.append([v])
        return out
    if isinstance(x, list):
        out = []
        for v in x:
            out.extend(variations(v))
        return out
    v = variation_of(x)
    return [v] if v else []


def light_of(l):
    if isinstance(l, list):
        l = l[0] if l else None
    if not isinstance(l, dict):
        return None
    c = tint_of(l.get("color")) or [1, 1, 1, 1]
    return [num(l.get("intensity", 1)), num(l.get("size", 1)), c[:3]]


def sound_of(s):
    if isinstance(s, dict) and "variations" in s:
        s = s["variations"]
    if isinstance(s, dict):
        s = [s]
    if not isinstance(s, list):
        return None
    out = []
    for v in s:
        if isinstance(v, dict) and "filename" in v:
            vol = v.get("volume", v.get("max_volume", 1))
            out.append([icon_index.file_of(v["filename"]), num(vol, 3)])
    return out or None


def as_list(x):
    if x is None:
        return []
    return x if isinstance(x, list) else [x]


def effects(action, found=None, kinds=("explosion", "corpse")):
    """The explosions and scorch marks a trigger creates, through nested results."""
    found = [] if found is None else found
    for a in as_list(action):
        if not isinstance(a, dict):
            continue
        for delivery in as_list(a.get("action_delivery")):
            if not isinstance(delivery, dict):
                continue
            for key in ("target_effects", "source_effects"):
                for e in as_list(delivery.get(key)):
                    effect(e, found, kinds)
        for e in as_list(a.get("range_effects")):
            effect(e, found, kinds)
    return found


EXPLOSIONS = set()
CORPSES = set()


def effect(e, found, kinds):
    if not isinstance(e, dict):
        return
    t = e.get("type")
    if t in ("create-entity", "create-explosion"):
        name = e.get("entity_name")
        if name in EXPLOSIONS or name in CORPSES:
            pair = [name, 1 if e.get("only_when_visible") else 0]
            if pair not in found:
                found.append(pair)
    elif t == "nested-result":
        effects(e.get("action"), found, kinds)


def delivery_of(action):
    """(kind, what it fires, count, source effects, target effects, line explosion) of an ammo action."""
    kind, fired, count, src, tgt, line = "instant", "", 1, [], [], ""
    for a in as_list(action):
        if not isinstance(a, dict):
            continue
        if a.get("type") == "line":
            kind = "line"
            le = effects({"range_effects": a.get("range_effects")})
            line = le[0][0] if le else ""
        for d in as_list(a.get("action_delivery")):
            if not isinstance(d, dict):
                continue
            for e in as_list(d.get("source_effects")):
                effect(e, src, None)
            t = d.get("type")
            if t == "projectile":
                kind, fired = "projectile", d.get("projectile", "")
                count = max(count, int(a.get("repeat_count", 1) or 1))
            elif t == "stream":
                kind, fired = "stream", d.get("stream", "")
            elif t == "beam" and kind == "instant":
                kind, fired = "beam", d.get("beam", "")
            elif t == "artillery":
                kind, fired = "projectile", d.get("projectile", "")
            for e in as_list(d.get("target_effects")):
                if isinstance(e, dict) and e.get("type") == "nested-result":
                    k2, f2, n2, s2, t2, _ = delivery_of(e.get("action"))
                    if k2 in ("projectile", "beam", "stream"):
                        kind, fired = k2, f2
                        n = e.get("action")
                        n = n[0] if isinstance(n, list) else n
                        count = max(count, int((n or {}).get("repeat_count", 1) or 1))
                    tgt.extend(x for x in t2 if x not in tgt)
                else:
                    effect(e, tgt, None)
    return kind, fired, count, src, tgt, line


def build(d):
    EXPLOSIONS.update(d.get("explosion", {}))
    CORPSES.update(n for n in d.get("corpse", {}) if "scorchmark" in n)
    out = {k: {} for k in ("ex", "pr", "st", "bm", "fi", "sw", "ts", "sc", "pa", "ammo", "gun", "dying")}
    for name, p in d.get("explosion", {}).items():
        rec = {"v": variations(p.get("animations"))}
        if light_of(p.get("light")):
            rec["l"] = light_of(p.get("light"))
        if p.get("smoke"):
            rec["sm"] = [p["smoke"], int(p.get("smoke_count", 1))]
        if p.get("rotate"):
            rec["rot"] = 1
        if p.get("beam"):
            rec["beam"] = 1
        if p.get("height") is not None:
            rec["h"] = num(p["height"])
        if sound_of(p.get("sound")):
            rec["snd"] = sound_of(p.get("sound"))
        out["ex"][name] = rec
    for t in ("projectile", "artillery-projectile"):
        for name, p in d.get(t, {}).items():
            a = variations(p.get("animation") or p.get("picture"))
            rec = {"a": a, "hit": effects([p.get("action"), p.get("final_action")])}
            if light_of(p.get("light")):
                rec["l"] = light_of(p.get("light"))
            smk = []
            for s in as_list(p.get("smoke")):
                if isinstance(s, dict) and s.get("name"):
                    smk.append([s["name"], num(s.get("frequency", 1)), shift_of(s.get("deviation"))])
            if smk:
                rec["smk"] = smk
            if p.get("acceleration"):
                rec["acc"] = num(p["acceleration"], 5)
            if t == "artillery-projectile":
                rec["art"] = 1
            out["pr"][name] = rec
    for name, p in d.get("stream", {}).items():
        rec = {"p": variations(p.get("particle")), "sp": variations(p.get("spine_animation")),
               "hs": num(p.get("particle_horizontal_speed", 0.25)), "va": num(p.get("particle_vertical_acceleration", 0.01), 5),
               "psi": int(p.get("particle_spawn_interval", 2)), "pst": int(p.get("particle_spawn_timeout", 2)),
               "ss": num(p.get("particle_start_scale", 1)), "sa": num(p.get("particle_start_alpha", 1)),
               "hit": effects(p.get("action"))}
        smk = [[s["name"], num(s.get("frequency", 1))] for s in as_list(p.get("smoke_sources")) if isinstance(s, dict) and s.get("name")]
        if smk:
            rec["smk"] = smk
        out["st"][name] = rec
    for name, p in d.get("beam", {}).items():
        g = (p.get("graphics_set") or {}).get("beam") or {}
        rec = {"w": num(p.get("width", 0.5))}
        for part in ("start", "ending", "head", "tail", "body"):
            v = variations(g.get(part))
            if v:
                rec[part] = v
        out["bm"][name] = rec
    for name, p in d.get("fire", {}).items():
        rec = {"a": variations(p.get("pictures")), "bp": variations(p.get("burnt_patch_pictures")),
               "fin": int(p.get("fade_in_duration", 30)), "fout": int(p.get("fade_out_duration", 30)),
               "alpha": num(p.get("flame_alpha", 1))}
        if light_of(p.get("light")):
            rec["l"] = light_of(p.get("light"))
        out["fi"][name] = rec
    for name, p in d.get("smoke-with-trigger", {}).items():
        a = variations(p.get("animation"))
        if not a:
            continue
        spread = p.get("particle_spread")
        rec = {"a": a, "c": tint_of(p.get("color")), "n": int(p.get("particle_count", 1)),
               "spr": shift_of(spread) if spread else [0, 0], "dur": int(p.get("duration", 600)),
               "fade": int(p.get("fade_away_duration", 0) or 0)}
        if p.get("cyclic"):
            rec["cyc"] = 1
        out["sw"][name] = rec
    for name, p in d.get("trivial-smoke", {}).items():
        rec = {"a": variations(p.get("animation")), "dur": int(p.get("duration", 60)),
               "fin": int(p.get("fade_in_duration", 0) or 0), "fade": int(p.get("fade_away_duration", 0) or 0),
               "s0": num(p.get("start_scale", 1)), "s1": num(p.get("end_scale", 1)), "c": tint_of(p.get("color"))}
        out["ts"][name] = rec
    for name in CORPSES:
        p = d["corpse"][name]
        a = variations(p.get("ground_patch"))
        if a:
            out["sc"][name] = {"a": a}
    for name in SHELL_PARTICLES:
        p = d.get("optimized-particle", {}).get(name)
        if p:
            out["pa"][name] = {"a": variations(p.get("pictures")), "life": int(p.get("life_time", 600))}
    for t in ("ammo", "capsule"):
        for name, item in d.get(t, {}).items():
            if t == "ammo":
                at = item.get("ammo_type")
                if isinstance(at, list):
                    at = next((x for x in at if x.get("source_type", "default") == "default"), at[0])
            else:
                ap = (item.get("capsule_action") or {}).get("attack_parameters") or {}
                at = ap.get("ammo_type")
            if not isinstance(at, dict):
                continue
            kind, fired, count, src, tgt, line = delivery_of(at.get("action"))
            rec = {"k": kind}
            if fired:
                rec["p"] = fired
            if count > 1:
                rec["n"] = count
            if src:
                rec["src"] = src
            if tgt:
                rec["tgt"] = tgt
            if line:
                rec["line"] = line
            out["ammo"][name] = rec
    for name, g in d.get("gun", {}).items():
        ap = g.get("attack_parameters") or {}
        rec = {"cd": num(ap.get("cooldown", 1)), "pcd": num(ap.get("projectile_creation_distance", 0)),
               "r": num(ap.get("range", 0)), "k": ap.get("type", "projectile")}
        sp = ap.get("shell_particle")
        if isinstance(sp, dict) and sp.get("name"):
            rec["shell"] = [sp["name"], num(sp.get("creation_distance", 0)), num(sp.get("speed", 0.1)),
                            num(sp.get("vertical_speed", 0.04))]
        out["gun"][name] = rec
    for t, protos in d.items():
        if not isinstance(protos, dict):
            continue
        for name, p in protos.items():
            de = p.get("dying_explosion") if isinstance(p, dict) else None
            if isinstance(de, list):
                de = de[0] if de else None
            if isinstance(de, dict):
                de = de.get("name")
            if isinstance(de, str) and de in EXPLOSIONS:
                out["dying"][name] = de
    return out


def files_in(rec, acc):
    if isinstance(rec, list) and len(rec) == 12 and isinstance(rec[0], list) and isinstance(rec[1], int):
        for f in rec[0]:
            acc.add(f[0] if isinstance(f, list) else f)
        return
    if isinstance(rec, dict):
        for v in rec.values():
            files_in(v, acc)
    elif isinstance(rec, list):
        for v in rec:
            files_in(v, acc)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--factorio", default=icon_index.FACTORIO)
    parser.add_argument("--check", action="store_true")
    parser.add_argument("--dump", help="read a data-raw-dump.json instead of running Factorio")
    args = parser.parse_args()
    if args.dump:
        with open(args.dump, encoding="utf-8") as f:
            d = json.load(f)
    else:
        d = icon_index.dump(args.factorio)
    out = build(d)
    if args.check:
        files = set()
        files_in(out, files)
        missing = [f for f in sorted(files) if not os.path.exists(os.path.join(args.factorio, "data", f))]
        for f in missing:
            print("missing:", f)
        print("%d sheets, %d missing" % (len(files), len(missing)))
        return 1 if missing else 0
    with open(OUT, "w", encoding="utf-8", newline="\n") as f:
        json.dump(out, f, separators=(",", ":"), sort_keys=True)
        f.write("\n")
    print("wrote %s: %s" % (OUT, ", ".join("%s %d" % (k, len(v)) for k, v in out.items())))
    return 0


if __name__ == "__main__":
    sys.exit(main())
