#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
scale_encounters.py -- rescale every wild-Pokemon encounter level in Sinnoh onto
the raised level curve (Cynthia = 100, hard caps at boss fights).

WHY
---
The vanilla Platinum encounter tables top out around L40-50 because vanilla
Cynthia's ace is L62. The remake's cap table ends at 100, so the vanilla wilds
would be 30-50 levels of dead weight in the back half of the game and the
player could never reach 100 by the League.

MODEL
-----
1. Every encounter map is placed in the Sinnoh progression order
   (docs/research/game-design.md section 1) and thereby into the CAP SEGMENT
   that is in force while the player is standing in it.  The cap in force is
   the cap of the NEXT checkpoint boss (data/level_caps.json semantics:
   `raisedBy` is the event that ENDS the segment).
2. Each segment gets a band, expressed as a fraction of that segment's cap:
   the area CEILING rises linearly across the segment according to the area's
   position `u` in the visit order.  So two areas sharing a cap are not
   flattened onto the same level -- the later one is hotter.
3. Inside an area the vanilla structure is preserved exactly: the whole area is
   multiplied by one scale factor `A_hi / vanilla_max`, so relative spread,
   slot ordering and "this mon is the rare high-level one" all survive.
4. The scale is clamped to >= 1.0 -- scaling NEVER lowers a wild level below
   vanilla.  That is what keeps Route 201 a fair fight for a L5 starter: its
   band ceiling lands on its vanilla ceiling, so it comes out untouched.
5. Bands widen as a fraction of cap as the game goes on (0.21-0.62 of cap in
   the pre-Roark segment, 0.64-0.78 by Maylene, 0.82-0.93 at Victory Road,
   0.88-0.97 post-game), so wilds are always catchable and below boss parity
   but close enough to the player to actually pay exp.  Mid-game onward this
   lands wilds at the 70-90%-of-cap the brief asks for; the early game is held
   deliberately below it because the exp analysis already shows a 1.76-2.58x
   surplus there.

TRAVERSAL GATING
----------------
A table the player cannot physically reach at the area's story position is
scaled to the segment in which it first becomes reachable, not the area's own:
  surf     -> max(area segment, post-Wake)      SURF is the Fen Badge reward
  oldRod   -> area segment                      Old Rod is a Jubilife freebie
  goodRod  -> max(area segment, post-Fantina)   Good Rod sits on Route 209
  superRod -> max(area segment, post-Candice)   Super Rod is a late-game rod
This is what stops every early-town lake from being a L20 Psyduck pond you
swim into at L60.

ROD TABLES
----------
Vanilla rod tables are region-global constants (Old Rod 3-15, Good Rod 10-25,
Super Rod 30-55 on almost every map), so there is no per-area vanilla shape to
preserve.  Rods are instead re-derived from the area's water ceiling as a
three-tier ladder (old < good < super).

IDEMPOTENCE
-----------
data/rom/encounters.json is gitignored and is REWRITTEN IN PLACE by the ROM
build workflow.  Scaling in place twice would square the scale factor, so this
script always scales from a pinned vanilla snapshot at
tools/_work/rebalance/encounters.vanilla.json.  It refreshes that snapshot
automatically whenever the live file still looks unscaled (see looks_vanilla).

USAGE
  python tools/scale_encounters.py                      # scale in place
  python tools/scale_encounters.py --dry-run            # report only
  python tools/scale_encounters.py --refresh-source     # force re-snapshot
  python tools/scale_encounters.py --report route_201 route_210 victory_road
"""

from __future__ import print_function

import argparse
import copy
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
LIVE = os.path.join(ROOT, "data", "rom", "encounters.json")
WORK = os.path.join(HERE, "_work", "rebalance")
SNAPSHOT = os.path.join(WORK, "encounters.vanilla.json")
REPORT = os.path.join(WORK, "scale_report.json")

# ---------------------------------------------------------------------------
# The new cap table.  index -> cap in force while the player works toward that
# checkpoint.  Segment 0 and 1 are the same cap (18) so they are one band.
# ---------------------------------------------------------------------------
CAPS = {
    1: 18,   # -> Roark        (Cranidos 18)
    2: 27,   # -> Gardenia     (Roserade 27)
    3: 36,   # -> Fantina      (Mismagius 36)
    4: 45,   # -> Maylene      (Lucario 45)
    5: 54,   # -> Crasher Wake (Floatzel 54)
    6: 66,   # -> Byron        (Bastiodon 66)
    7: 78,   # -> Candice      (Froslass 78)
    8: 90,   # -> Volkner      (Electivire 90)
    9: 96,   # -> Elite Four   (Aaron 96) -- League + Victory Road
    14: 100,  # post-game (Hall of Fame, uncapped)
}

# Band as a fraction of the segment cap: (floor of the segment, ceiling of the
# segment).  An area's own ceiling is lerped between these by its position u.
# Chosen so the ceilings form one monotone, gap-free ramp:
#   9 -> 11..17 -> 20..26 -> 29..35 -> 37..43 -> 47..55 -> 58..66 -> 69..78
#     -> 79..89 -> 88..97
BANDS = {
    # The pre-Roark ceiling is deliberately low -- the exp analysis has the
    # early game already running a 1.76x surplus, so segment 1 needs no help
    # and Route 201 must stay a fair fight for a L5 starter.  0.62 at the top
    # is set by the Oreburgh Mine: any lower and the Mine comes out COLDER than
    # Oreburgh Gate B1F, which vanilla already leaves at L10 (selftest catches
    # this as a backwards ceiling).
    1:  (0.21, 0.62),
    2:  (0.42, 0.63),
    3:  (0.55, 0.72),
    4:  (0.64, 0.78),
    5:  (0.68, 0.80),
    6:  (0.71, 0.83),
    7:  (0.74, 0.85),
    8:  (0.77, 0.87),
    9:  (0.82, 0.93),
    14: (0.88, 0.97),
}

# Earliest segment in which each gated table can be entered at all.
SURF_SEGMENT = 6      # SURF is the Fen Badge reward (Crasher Wake)
OLD_ROD_SEGMENT = 1   # Jubilife City, before Roark
GOOD_ROD_SEGMENT = 4  # Route 209 fisherman, after Fantina
SUPER_ROD_SEGMENT = 8  # late-game rod, after Candice

# Rod tiers as a fraction of the area's water ceiling for that rod's segment.
ROD_TIERS = {
    "oldRod":   (0.45, 0.70),
    "goodRod":  (0.62, 0.85),
    "superRod": (0.80, 1.00),
}

MIN_LEVEL = 2

# Vanilla Sinnoh grass peaks at L55 (Stark Mountain). A scaled table peaks in
# the mid 90s, so this cleanly separates "unscaled ROM extract" from "already
# scaled" -- see looks_vanilla().
VANILLA_GRASS_PEAK_MAX = 60

LAND_TABLES = ("grass",)
WATER_TABLES = ("surf",)
ROD_TABLES = ("oldRod", "goodRod", "superRod")
# curated entries carry their own `table`; these route to the water scale.
CURATED_WATER = ("surf",)
CURATED_ROD = ("oldRod", "goodRod", "superRod")

# ---------------------------------------------------------------------------
# Area placement.  (map id, segment, u) in Sinnoh visit order.
# u = position within the segment, 0.0 at the start of the segment, 1.0 at the
# boss.  Ordered per docs/research/game-design.md section 1.
# ---------------------------------------------------------------------------
PLACEMENT = [
    # --- segment 1: Twinleaf -> Roark, cap 18 -------------------------------
    ("twinleaf_town",       1, 0.00),
    ("route_201",           1, 0.05),
    ("lake_verity",         1, 0.10),
    ("lake_verity_2",       1, 0.10),
    ("route_202",           1, 0.25),
    ("route_203",           1, 0.45),
    ("oreburgh_gate_1f",    1, 0.60),
    ("oreburgh_gate_b1f",   1, 0.62),
    ("oreburgh_mine_1f",    1, 0.80),
    ("oreburgh_mine_b1f",   1, 0.90),
    # --- segment 2: Coal Badge -> Gardenia, cap 27 --------------------------
    ("route_204_south",     2, 0.05),
    ("ravaged_path",        2, 0.15),
    ("route_204_north",     2, 0.25),
    ("route_205_south",     2, 0.40),
    ("valley_windworks",    2, 0.50),
    ("route_205_north",     2, 0.65),
    ("eterna_forest",       2, 0.80),
    ("eterna_city",         2, 0.95),
    # --- segment 3: Forest Badge -> Fantina, cap 36 -------------------------
    ("old_chateau",         3, 0.05),
    ("route_206",           3, 0.15),
    ("wayward_cave",        3, 0.25),
    ("wayward_cave_2",      3, 0.25),
    ("route_207",           3, 0.40),
    # Mt. Coronet south (the shallow, low-level tier) -- see MT_CORONET_TIERS
    ("route_208",           3, 0.70),
    # --- segment 4: Relic Badge -> Maylene, cap 45 --------------------------
    ("route_209",           4, 0.05),
    ("solaceon_ruins",      4, 0.30),
    ("ruin_maniac_cave",    4, 0.35),
    ("ruin_maniac_cave_2",  4, 0.37),
    ("route_210",           4, 0.50),   # Route 210 SOUTH (pre-Secret Potion)
    ("route_215",           4, 0.65),
    ("trophy_garden",       4, 0.80),
    # --- segment 5: Cobble Badge -> Crasher Wake, cap 54 --------------------
    ("route_214",           5, 0.10),
    ("maniac_tunnel",       5, 0.15),
    ("valor_lakefront",     5, 0.30),
    ("route_213",           5, 0.50),
    ("pastoria_city",       5, 0.70),
    # --- segment 6: Fen Badge -> Byron, cap 66 ------------------------------
    ("great_marsh",         6, 0.05),
    ("route_212",           6, 0.15),
    ("route_212_2",         6, 0.17),
    ("route_210_2",         6, 0.30),   # Route 210 NORTH (post-Secret Potion)
    ("celestic_town",       6, 0.35),
    ("fuego_ironworks",     6, 0.45),
    ("route_219",           6, 0.52),
    ("route_220",           6, 0.55),
    ("route_221",           6, 0.58),
    ("route_218",           6, 0.65),
    ("canalave_city",       6, 0.70),
    ("iron_island",         6, 0.85),
    # --- segment 7: Mine Badge -> Candice, cap 78 ---------------------------
    ("lake_valor",          7, 0.05),
    ("route_211",           7, 0.20),   # Route 211 WEST
    ("route_211_2",         7, 0.25),   # Route 211 EAST
    ("route_216",           7, 0.50),
    ("route_217",           7, 0.60),
    ("acuity_lakefront",    7, 0.70),
    # --- segment 8: Icicle Badge -> Volkner, cap 90 -------------------------
    ("lake_acuity",         8, 0.05),
    ("sendoff_spring",      8, 0.50),
    ("route_222",           8, 0.75),
    ("sunyshore_city",      8, 0.85),
    # --- segment 9: Beacon Badge -> Elite Four, cap 96 ----------------------
    ("route_223",           9, 0.10),
    ("pokemon_league",      9, 0.20),
    # victory_road_* -- see VICTORY_ROAD_U
    # --- segment 14: post-game, cap 100 ------------------------------------
    ("resort_area",        14, 0.10),
    ("route_224",          14, 0.15),
    ("route_230",          14, 0.25),
    ("route_229",          14, 0.30),
    ("route_228",          14, 0.35),
    ("route_226",          14, 0.40),
    ("route_225",          14, 0.45),
    ("route_227",          14, 0.55),
    ("stark_mountain",     14, 0.75),
    ("snowpoint_temple",   14, 0.85),
    # turnback_cave_* -- gated on the National Dex; see DEPTH_TIERS
]

# Prefix families: every `<prefix>_N` sub-map inherits the prefix's placement
# unless it is listed explicitly or handled by a tier rule below.
FAMILY_PREFIXES = [
    "old_chateau", "great_marsh", "iron_island", "solaceon_ruins",
    "snowpoint_temple", "stark_mountain",
]

# Mt. Coronet has 13 sub-maps with no geography in the ROM dump, but vanilla
# level tier encodes depth exactly: shallow south rooms are L13-16, the north
# half is L32-35, the summit interior is L36-41.  Tier by vanilla ceiling.
#   (inclusive vanilla-ceiling upper bound, segment, u)
MT_CORONET_TIERS = [
    (20, 3, 0.55),   # south, pre-Fantina through-path
    (35, 7, 0.35),   # north half, post-Byron (SMASH + STRENGTH)
    (99, 8, 0.30),   # summit interior, post-Candice (SURF + STRENGTH + CLIMB)
]

# Victory Road sub-maps: vanilla ceiling rises with depth, so depth -> u.
VICTORY_ROAD_TIERS = [
    (44, 9, 0.50),
    (99, 9, 0.90),
]

# Turnback Cave (Giratina's dungeon, gated on the National Dex) and the
# orphaned `unreferenced_*` room tables both tier by depth in vanilla
# (18 / 28 / 38 and 18 / 38 / 48).  Tier them the same way as Mt. Coronet so the
# depth gradient survives instead of flattening onto one ceiling.
DEPTH_TIERED = ("turnback_cave", "unreferenced_")
DEPTH_TIERS = [
    (20, 14, 0.30),
    (30, 14, 0.45),
    (40, 14, 0.60),
    (99, 14, 0.75),
]


# ---------------------------------------------------------------------------
# placement resolution
# ---------------------------------------------------------------------------

def _explicit_map():
    return dict((k, (s, u)) for (k, s, u) in PLACEMENT)


def area_ceiling(segment, u):
    """The level ceiling for an area sitting at position u of `segment`."""
    cap = CAPS[segment]
    lo, hi = BANDS[segment]
    return cap * (lo + u * (hi - lo))


def vanilla_ceiling(area, tables):
    """Highest vanilla level across `tables` (area-specific tables only)."""
    best = 0
    for t in tables:
        for e in area.get(t) or []:
            best = max(best, e["max"], e["min"])
    if "grass" in tables:
        for e in area.get("grassSlots") or []:
            best = max(best, e["max"], e["min"])
    for e in area.get("curated") or []:
        tab = e.get("table") or "grass"
        want_water = tab in CURATED_WATER
        is_water_call = "surf" in tables
        if want_water == is_water_call and tab not in CURATED_ROD:
            best = max(best, e["max"], e["min"])
    return best


def resolve_placement(map_id, area, explicit):
    """-> (segment, u, why).  Every map in encounters.json gets a placement."""
    if map_id in explicit:
        s, u = explicit[map_id]
        return s, u, "explicit"

    if map_id.startswith("mt_coronet"):
        ceil = vanilla_ceiling(area, LAND_TABLES) or 0
        for bound, s, u in MT_CORONET_TIERS:
            if ceil <= bound:
                return s, u, "mt-coronet-tier<=%d" % bound
        s, u = MT_CORONET_TIERS[-1][1:]
        return s, u, "mt-coronet-tier-top"

    if map_id.startswith("victory_road"):
        ceil = vanilla_ceiling(area, LAND_TABLES) or 0
        for bound, s, u in VICTORY_ROAD_TIERS:
            if ceil <= bound:
                return s, u, "victory-road-tier<=%d" % bound
        s, u = VICTORY_ROAD_TIERS[-1][1:]
        return s, u, "victory-road-tier-top"

    for pref in DEPTH_TIERED:
        if map_id == pref.rstrip("_") or map_id.startswith(pref):
            ceil = vanilla_ceiling(area, LAND_TABLES) or 0
            for bound, s, u in DEPTH_TIERS:
                if ceil <= bound:
                    return s, u, "depth-tier<=%d" % bound
            s, u = DEPTH_TIERS[-1][1:]
            return s, u, "depth-tier-top"

    for prefix in FAMILY_PREFIXES:
        if map_id == prefix or map_id.startswith(prefix + "_"):
            s, u = explicit[prefix]
            return s, u, "family:" + prefix

    # route_209_2..6, route_210_2 style siblings: inherit the base route.
    parts = map_id.rsplit("_", 1)
    if len(parts) == 2 and parts[1].isdigit() and parts[0] in explicit:
        s, u = explicit[parts[0]]
        # nudge later sub-maps slightly deeper into the segment
        n = int(parts[1])
        return s, min(1.0, u + 0.02 * (n - 1)), "sibling:" + parts[0]

    raise KeyError("no placement rule for map '%s'" % map_id)


# ---------------------------------------------------------------------------
# scaling
# ---------------------------------------------------------------------------

def applied_ceiling(vanilla_ceil, scale, cap):
    """The level the area's top slot actually comes out at.

    Must use the same rounding as scale_entry(), or the report and the selftest
    disagree with the data they are describing (int() truncation made the
    selftest report a ceiling one level below the file's real one).
    """
    return clamp(round(vanilla_ceil * scale), cap)


def clamp(level, cap):
    """Wilds must stay catchable and strictly under the cap in force."""
    return max(MIN_LEVEL, min(int(level), cap - 1))


def scale_entry(entry, scale, cap):
    lo = clamp(round(entry["min"] * scale), cap)
    hi = clamp(round(entry["max"] * scale), cap)
    if hi < lo:
        lo, hi = hi, lo
    entry["min"], entry["max"] = lo, hi


def rod_band(tier, water_ceiling, cap, vanilla_lo=0, vanilla_hi=0):
    """Rod band for one tier.

    Vanilla rod tables are region-global constants, so there is no per-area
    vanilla shape worth preserving -- the band is re-derived from the area's
    ceiling.  But it is floored at the entry's own vanilla band so no rod
    anywhere ends up weaker than vanilla (an early-route Old Rod would
    otherwise be dragged down to L2-3 by the deliberately gentle early ramp).
    """
    f_lo, f_hi = ROD_TIERS[tier]
    lo = clamp(max(round(water_ceiling * f_lo), vanilla_lo), cap)
    hi = clamp(max(round(water_ceiling * f_hi), vanilla_hi), cap)
    if hi < lo:
        hi = lo
    return lo, hi


def scale_area(map_id, area, explicit):
    """Scale one area in place.  Returns a record describing what happened."""
    seg, u, why = resolve_placement(map_id, area, explicit)
    cap = CAPS[seg]

    # --- land ------------------------------------------------------------
    land_ceil_v = vanilla_ceiling(area, LAND_TABLES)
    land_target = area_ceiling(seg, u)
    # never weaken a wild: scale is clamped at 1.0
    land_scale = max(1.0, land_target / float(land_ceil_v)) if land_ceil_v else 1.0

    # --- water (surf is SURF-gated, so it may belong to a later segment) --
    w_seg = max(seg, SURF_SEGMENT)
    w_cap = CAPS[w_seg]
    water_ceil_v = vanilla_ceiling(area, WATER_TABLES)
    water_target = area_ceiling(w_seg, u)
    water_scale = (max(1.0, water_target / float(water_ceil_v))
                   if water_ceil_v else 1.0)

    # --- rods: re-derived, not scaled (vanilla rod bands are global) ------
    rod_segments = {
        "oldRod":   max(seg, OLD_ROD_SEGMENT),
        "goodRod":  max(seg, GOOD_ROD_SEGMENT),
        "superRod": max(seg, SUPER_ROD_SEGMENT),
    }
    rod_ceilings = dict((t, area_ceiling(sg, u)) for t, sg in rod_segments.items())
    rod_bands = dict((t, rod_band(t, rod_ceilings[t], CAPS[rod_segments[t]]))
                     for t in rod_segments)

    def apply_rod(tier, entry):
        entry["min"], entry["max"] = rod_band(
            tier, rod_ceilings[tier], CAPS[rod_segments[tier]],
            entry["min"], entry["max"])

    # apply -------------------------------------------------------------
    for t in LAND_TABLES:
        for e in area.get(t) or []:
            scale_entry(e, land_scale, cap)
    for e in area.get("grassSlots") or []:
        scale_entry(e, land_scale, cap)
    for t in WATER_TABLES:
        for e in area.get(t) or []:
            scale_entry(e, water_scale, w_cap)
    for tier in ROD_TABLES:
        for e in area.get(tier) or []:
            apply_rod(tier, e)
    for e in area.get("curated") or []:
        tab = e.get("table") or "grass"
        if tab in CURATED_ROD:
            apply_rod(tab, e)
        elif tab in CURATED_WATER:
            scale_entry(e, water_scale, w_cap)
        else:
            scale_entry(e, land_scale, cap)

    return {
        "map": map_id, "segment": seg, "u": round(u, 3), "cap": cap,
        "why": why,
        "landVanillaCeiling": land_ceil_v,
        "landTargetCeiling": round(land_target, 1),
        "landScale": round(land_scale, 4),
        "landAppliedCeiling": (applied_ceiling(land_ceil_v, land_scale, cap)
                               if land_ceil_v else None),
        "landPctOfCap": (round(100.0 * applied_ceiling(land_ceil_v, land_scale, cap)
                               / cap, 1) if land_ceil_v else None),
        "waterSegment": w_seg, "waterScale": round(water_scale, 4),
        "rodSegments": rod_segments,
        "rodBands": rod_bands,
    }


def looks_vanilla(data):
    """Is this table still the unscaled ROM extract?

    The fingerprint MUST be taken somewhere the transform actually moves the
    needle.  Route 201 is the wrong probe -- scaling deliberately leaves it
    untouched, so an early version of this guard read every scaled file back as
    vanilla and re-pinned the snapshot from it.  Re-scaling is not a no-op: the
    Mt. Coronet / Victory Road / Turnback depth tiers classify rooms BY their
    vanilla level, so a second pass silently re-tiers them upward.

    Probe the top of the curve instead.  Vanilla Sinnoh grass peaks at L55
    (Stark Mountain); after scaling nothing under 80 remains at the top end.
    """
    grass_max = 0
    for area in data.values():
        for e in area.get("grass") or []:
            grass_max = max(grass_max, e["max"])
    if not grass_max:
        return True
    return grass_max <= VANILLA_GRASS_PEAK_MAX


def load(path):
    with open(path, "r") as fh:
        return json.load(fh)


def dump(path, obj, sort_keys=False):
    """Write JSON.  Key order is preserved by default so the scaled encounter
    file stays a minimal diff against what the ROM build workflow emits."""
    d = os.path.dirname(path)
    if d and not os.path.isdir(d):
        os.makedirs(d)
    with open(path, "w") as fh:
        json.dump(obj, fh, indent=1, sort_keys=sort_keys)
        fh.write("\n")


def sample(area, label):
    """Human-readable before/after line set for one area."""
    out = []
    for t in ("grass", "surf", "oldRod", "goodRod", "superRod"):
        rows = area.get(t) or []
        if not rows:
            continue
        out.append("  %-9s %s" % (t, ", ".join(
            "#%d L%d-%d@%d%%" % (e["species"], e["min"], e["max"], e.get("weight", 0))
            for e in rows)))
    cur = area.get("curated") or []
    if cur:
        out.append("  %-9s %s" % ("curated", ", ".join(
            "%s L%d-%d(%s)" % (e.get("name") or "#%d" % e["species"],
                               e["min"], e["max"], e.get("table") or "grass")
            for e in cur)))
    return ("%s\n" % label) + "\n".join(out)


def scale_all(vanilla):
    """Pure transform: vanilla table -> (scaled table, per-area records)."""
    explicit = _explicit_map()
    scaled = copy.deepcopy(vanilla)
    records = [scale_area(m, scaled[m], explicit) for m in sorted(scaled)]
    return scaled, records


def selftest(vanilla):
    """Regressions this script has actually shipped. Keep them.

    1. Route 201 must come out of the transform untouched -- it is the first
       route in the game and has to stay fair for a L5 starter.
    2. The transform must be a FIXED POINT.  It is not naturally: the depth-tier
       rules classify Mt. Coronet / Victory Road / Turnback rooms by their
       vanilla level, so feeding scaled data back in re-tiers them upward
       (Victory Road drifted 43 -> 84 -> 88).  The snapshot pin is what
       guarantees it in practice; this asserts the pin plus looks_vanilla()
       actually catch a scaled input.
    3. The area ceilings must form one monotone ramp across the whole run, or
       the player walks into a route that is colder than the one before it.
    """
    fails = []
    scaled, records = scale_all(vanilla)

    if scaled["route_201"]["grass"] != vanilla["route_201"]["grass"]:
        fails.append("Route 201 grass was modified: %s -> %s"
                     % (vanilla["route_201"]["grass"], scaled["route_201"]["grass"]))

    if looks_vanilla(scaled):
        fails.append("looks_vanilla() reads a SCALED table as vanilla -- the "
                     "snapshot guard would re-pin from it and double-scale")
    if not looks_vanilla(vanilla):
        fails.append("looks_vanilla() reads the vanilla table as scaled")

    # ceilings must not go backwards along the progression order
    ramp = [(r["segment"], r["u"], r["map"], r["landAppliedCeiling"])
            for r in records if r["landVanillaCeiling"]]
    ramp.sort(key=lambda t: (t[0], t[1]))
    for (s1, u1, m1, c1), (s2, u2, m2, c2) in zip(ramp, ramp[1:]):
        if c2 < c1:
            fails.append("ceiling goes backwards: %s(seg%d u%.2f)=%d -> "
                         "%s(seg%d u%.2f)=%d" % (m1, s1, u1, c1, m2, s2, u2, c2))

    # every wild must stay strictly under the cap it is reachable at
    for r in records:
        area = scaled[r["map"]]
        for e in area.get("grass") or []:
            if e["max"] >= r["cap"]:
                fails.append("%s grass #%d L%d >= cap %d"
                             % (r["map"], e["species"], e["max"], r["cap"]))
    return fails


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--in", dest="src", default=LIVE,
                    help="vanilla encounter table source (default data/rom/encounters.json)")
    ap.add_argument("--out", dest="out", default=LIVE,
                    help="where to write the scaled table (default: in place)")
    ap.add_argument("--snapshot", default=SNAPSHOT,
                    help="pinned vanilla snapshot used for idempotent re-runs")
    ap.add_argument("--refresh-source", action="store_true",
                    help="re-pin the snapshot from --in even if one exists")
    ap.add_argument("--dry-run", action="store_true", help="do not write --out")
    ap.add_argument("--selftest", action="store_true",
                    help="run the transform's regression checks and exit")
    ap.add_argument("--report", nargs="*", default=["route_201", "route_210", "victory_road"],
                    help="map ids to print a before/after sample for")
    args = ap.parse_args(argv)

    if not os.path.isfile(args.src):
        sys.stderr.write(
            "encounters source not found: %s\n"
            "The ROM build workflow has not produced it yet. Re-run this script\n"
            "once data/rom/encounters.json exists; the transform is unchanged.\n"
            % args.src)
        return 2

    live = load(args.src)

    # --- pin / refresh the vanilla snapshot so re-runs cannot double-scale --
    if args.refresh_source or not os.path.isfile(args.snapshot):
        vanilla = live
        dump(args.snapshot, vanilla)
        pinned = "written"
    else:
        vanilla = load(args.snapshot)
        pinned = "reused"
        # The ROM build workflow may have regenerated encounters.json with new
        # maps or new curated entries. If the live file is still unscaled, it is
        # the better source -- re-pin from it.
        if looks_vanilla(live) and live != vanilla:
            vanilla = live
            dump(args.snapshot, vanilla)
            pinned = "re-pinned (live file changed and is still unscaled)"

    if not looks_vanilla(vanilla):
        sys.stderr.write(
            "refusing to scale: snapshot %s already looks scaled (grass peaks "
            "above L%d). Regenerate a clean extract with\n"
            "  python tools/build_gamedata.py --out tools/_work/rebalance/regen\n"
            "then re-pin with --refresh-source --in "
            "tools/_work/rebalance/regen/data/rom/encounters.json\n"
            % (args.snapshot, VANILLA_GRASS_PEAK_MAX))
        return 3

    if args.selftest:
        fails = selftest(vanilla)
        for f in fails:
            print("  FAIL " + f)
        print("selftest: %s (%d failures)"
              % ("PASS" if not fails else "FAIL", len(fails)))
        return 0 if not fails else 1

    explicit = _explicit_map()
    scaled = copy.deepcopy(vanilla)
    records = []
    for map_id in sorted(scaled):
        records.append(scale_area(map_id, scaled[map_id], explicit))

    # --- invariants -------------------------------------------------------
    problems = []
    sentinels = []
    for rec in records:
        area = scaled[rec["map"]]
        # Each table is bounded by the cap of the segment in which that table
        # first becomes reachable, not the area's own segment: a Super Rod
        # table cannot be fished before the Super Rod exists.
        bounds = {"grass": rec["cap"], "surf": CAPS[rec["waterSegment"]]}
        for t, s in rec["rodSegments"].items():
            bounds[t] = CAPS[s]
        for t in ("grass", "surf", "oldRod", "goodRod", "superRod"):
            for e in area.get(t) or []:
                bound = bounds[t]
                if e["max"] >= bound:
                    problems.append("%s/%s #%d L%d >= cap %d"
                                    % (rec["map"], t, e["species"], e["max"], bound))
                if e["min"] > e["max"]:
                    problems.append("%s/%s #%d inverted" % (rec["map"], t, e["species"]))
        # never-weaken: no wild anywhere may come out below its vanilla level
        v = vanilla[rec["map"]]
        for t in ("grass", "surf", "oldRod", "goodRod", "superRod", "grassSlots"):
            for e_old, e_new in zip(v.get(t) or [], area.get(t) or []):
                if e_new["max"] < e_old["max"] or e_new["min"] < e_old["min"]:
                    msg = ("%s/%s #%d lowered L%d-%d -> L%d-%d"
                           % (rec["map"], t, e_old["species"],
                              e_old["min"], e_old["max"],
                              e_new["min"], e_new["max"]))
                    # A vanilla row spanning nearly the whole 1-100 range is a
                    # ROM sentinel for an unused slot, not real encounter data
                    # (Resort Area's Super Rod is the only one). Narrowing it
                    # is a fix, not a regression.
                    if (e_old["min"] <= 1 or e_old["max"] >= 100) and                             e_old["max"] - e_old["min"] >= 80:
                        sentinels.append(msg)
                    else:
                        problems.append(msg)

    # --- before/after samples --------------------------------------------
    for map_id in args.report:
        if map_id not in vanilla:
            print("!! no such map: %s" % map_id)
            continue
        print("=" * 72)
        rec = [r for r in records if r["map"] == map_id][0]
        print("%s  (%s)  segment %d  cap %d  u=%.2f  land x%.3f -> ceiling %.0f%% of cap"
              % (map_id, vanilla[map_id].get("locationName") or "-", rec["segment"],
                 rec["cap"], rec["u"], rec["landScale"], rec["landPctOfCap"] or 0))
        print(sample(vanilla[map_id], "BEFORE (vanilla ROM):"))
        print(sample(scaled[map_id], "AFTER (scaled):"))
    print("=" * 72)

    ceilings = [(r["map"], r["segment"], r["landVanillaCeiling"],
                 r["landAppliedCeiling"], r["landPctOfCap"])
                for r in records]
    dump(REPORT, {"snapshot": pinned, "areas": records,
                  "problems": problems, "sentinelsNarrowed": sentinels,
                  "ceilings": ceilings}, sort_keys=True)

    print("maps scaled: %d   snapshot: %s" % (len(records), pinned))
    print("invariant problems: %d   (ROM sentinel rows narrowed: %d)"
          % (len(problems), len(sentinels)))
    for p in problems[:20]:
        print("  !! " + p)
    print("report: %s" % REPORT)

    if args.dry_run:
        print("dry run -- %s not written" % args.out)
    else:
        dump(args.out, scaled)
        print("wrote %s" % args.out)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
