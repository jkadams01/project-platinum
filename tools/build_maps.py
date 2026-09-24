#!/usr/bin/env python3
"""Author the hand-drawn overworld maps for `data/maps/` (DATA_CONTRACT.md 9).

NOTHING HERE IS ROM-DERIVED. Every collision code, warp, obstacle and object in
this file was written by hand. The only ROM-adjacent values are the *tile
indices*, which are integer offsets into the gitignored
`assets/generated/tilesets/outdoor_sinnoh.png` atlas -- the same kind of index
the committed `tests/fixtures/maps/*.json` already carry. The maps are therefore
design data and are committed, exactly as CLAUDE.md's "Hard rules" table says
(`data/maps/**` (hand-authored) -> Committed).

WHY A GENERATOR AND NOT NINE HAND-TYPED JSON FILES
The three layer grids plus the collision grid are 4 x width x height numbers per
map. Typed by hand they drift: a row one cell short silently pads walkable
(map_loader.gd `_flatten` fills collision with 0), and a warp whose destination
cell landed in a wall strands the player. Here the grids come from one ASCII
drawing per map, and `validate()` proves -- on the emitted JSON, not on the
drawing -- that:

  * every layer and the collision grid are exactly width x height
  * every warp's own tile is walkable, its destination map exists, and the
    arrival cell is in bounds and walkable
  * every adjacency has a warp in BOTH directions
  * Routes 201/202/203 carry collision-4 tall grass AND their `encounterZone`
    exists in data/rom/encounters.json with a non-empty grass table
  * Oreburgh Gate's SMASH obstacle requires `badge:coal`
  * a badgeless player can still walk Twinleaf -> Roark (no soft-lock), proven
    by a cross-map BFS over the warp graph
  * the SMASH alcove is unreachable badgeless and reachable with Coal

Run:  python tools/build_maps.py          (writes + validates)
      python tools/build_maps.py --check  (validates what is on disk)
"""

import json
import os
import sys
from collections import deque

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT_DIR = os.path.join(ROOT, "data", "maps")
ENCOUNTERS = os.path.join(ROOT, "data", "rom", "encounters.json")
TILESET = os.path.join(ROOT, "data", "tilesets", "outdoor_sinnoh.json")

TILESET_NAME = "outdoor_sinnoh"
TILE = 16

# --------------------------------------------------------------------------
# Legend: char -> (ground tile index, collision code)
#
# Tile indices are real rows of data/tilesets/outdoor_sinnoh.json; the collision
# code is authoritative (DATA_CONTRACT 9) and is what the engine reads.
# `L` is the one place art and code deliberately disagree: the atlas ships no
# ledge tile, so a ledge is painted as road and carries collision 2.
# --------------------------------------------------------------------------
LEGEND = {
    ".": (17, 0),    # lgreenp    grass ground, walkable
    "g": (18, 0),    # lgreenp    grass ground, alternate
    ",": (196, 0),   # road01     path, walkable
    "p": (197, 0),   # road01     path, alternate
    "s": (23, 0),    # nsandp     sand, walkable
    "~": (220, 4),   # l_grass_m  TALL GRASS -- wild encounters
    "#": (8, 1),     # ki02ax     tree, blocked
    "T": (9, 1),     # ki02ax     tree, alternate
    "B": (13, 1),    # gate_1     building wall, blocked
    "b": (14, 1),    # gate_1     building wall, alternate
    "N": (15, 1),    # gate_1     blocked tile an NPC/boss/item stands on
    "C": (0, 0),     # dun_level  cave floor, walkable
    "X": (4, 1),     # dun_imped  cave wall, blocked
    "^": (156, 1),   # dun_allpeak cliff, blocked
    "W": (132, 3),   # blueglayp  DEEP WATER -- needs SURF (Fen badge)
    "w": (130, 5),   # puddlep    shallow water, walkable
    "L": (197, 2),   # road01     LEDGE -- one-way hop south
}

# Collision codes a walking player may stand on (mirrors Collision.LAND_CODES).
LAND_CODES = {0, 4, 5}


class Grid:
    """A char canvas. Origin top-left, +y south, matching row-major map JSON."""

    def __init__(self, width, height, fill="."):
        self.w = width
        self.h = height
        self.cells = [[fill] * width for _ in range(height)]

    def set(self, x, y, ch):
        assert 0 <= x < self.w and 0 <= y < self.h, "set out of bounds %d,%d" % (x, y)
        self.cells[y][x] = ch

    def get(self, x, y):
        return self.cells[y][x]

    def rect(self, x0, y0, x1, y1, ch):
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.set(x, y, ch)

    def border(self, ch):
        self.rect(0, 0, self.w - 1, 0, ch)
        self.rect(0, self.h - 1, self.w - 1, self.h - 1, ch)
        self.rect(0, 0, 0, self.h - 1, ch)
        self.rect(self.w - 1, 0, self.w - 1, self.h - 1, ch)

    def hline(self, y, x0, x1, ch):
        self.rect(x0, y, x1, y, ch)

    def vline(self, x, y0, y1, ch):
        self.rect(x, y0, x, y1, ch)

    def ground(self):
        return [[LEGEND[c][0] for c in row] for row in self.cells]

    def collision(self):
        return [[LEGEND[c][1] for c in row] for row in self.cells]

    def empty(self):
        return [[-1] * self.w for _ in range(self.h)]


def emit(grid, map_id, name, zone, warps, traversal=None, objects=None, note=""):
    # Objects the player interacts with are stamped BLOCKED here rather than
    # trusted to have been drawn blocked. src/overworld/ has no object-collision
    # layer -- the grid is the only thing that stops a step (collision.gd) -- so
    # an NPC on a walkable tile is an NPC you walk straight through, and you can
    # never face it to talk to it. Stamping in one place makes that impossible.
    for o in objects or []:
        if o["type"] in ("npc", "boss", "item"):
            grid.set(o["x"], o["y"], "N")
    return {
        "id": map_id,
        "name": name,
        "_comment": (
            "HAND-AUTHORED. Nothing here is ROM-derived: collision codes, warps, "
            "obstacles and objects were all written by hand in tools/build_maps.py. "
            + note
        ).strip(),
        "width": grid.w,
        "height": grid.h,
        "tileSize": TILE,
        "tileset": TILESET_NAME,
        "layers": {
            "ground": grid.ground(),
            "overlay": grid.empty(),
            "above": grid.empty(),
        },
        "collision": grid.collision(),
        "traversal": traversal or [],
        "encounterZone": zone,
        "warps": warps,
        "objects": objects or [],
        "connections": {},
    }


# ==========================================================================
# The nine maps of the vertical slice
# ==========================================================================

def twinleaf_town():
    g = Grid(24, 20, ".")
    g.border("#")
    # main road: north gate down the middle, one east-west street
    g.vline(12, 1, 18, ",")
    g.set(12, 0, ",")                    # the north gate tile (warp)
    g.hline(10, 3, 20, ",")
    # the player's house and the rival's house
    g.rect(4, 4, 7, 7, "B")
    g.set(5, 7, ",")                     # doorway (decor; interiors are not in the slice)
    g.rect(15, 4, 18, 7, "b")
    g.set(17, 7, ",")
    # Lake Verity's inlet, bottom-left: deep water needs SURF, so it is scenery
    g.rect(2, 13, 7, 17, "W")
    g.rect(2, 12, 8, 12, "w")
    g.set(8, 13, "w")
    # a tree line so the town reads as enclosed
    g.rect(19, 13, 22, 17, "#")
    return emit(
        g, "twinleaf_town", "Twinleaf Town", "twinleaf_town",
        warps=[{"x": 12, "y": 0, "to": "route_201", "toX": 5, "toY": 13}],
        objects=[
            {"type": "spawn", "id": "player_start", "x": 12, "y": 12},
            {"type": "npc", "id": "twinleaf_mum", "x": 6, "y": 8, "sprite": "mother",
             "script": "twinleaf_mum", "lines": [
                 "Take care out there, {player}!",
                 "Professor Rowan is waiting on Route 201."]},
            {"type": "npc", "id": "twinleaf_barry", "x": 16, "y": 8, "sprite": "rival",
             "script": "twinleaf_barry", "lines": [
                 "Hey, slowpoke! I'm going on ahead!",
                 "Oreburgh City has a GYM. Roark uses Rock types -- don't say I never help."]},
        ],
        note="Deep water at the lake inlet is scenery: SURF is the Fen badge, far past this slice.")


def route_201():
    g = Grid(40, 16, ".")
    g.border("#")
    # the through-road, west (Twinleaf spur) to east (Sandgem)
    g.hline(8, 1, 38, ",")
    g.set(39, 8, ",")                    # east seam tile (warp)
    g.set(38, 8, ",")
    # the Twinleaf spur runs south off the road
    g.vline(5, 8, 14, ",")
    g.set(5, 15, ",")                    # south seam tile (warp)
    # tall grass, north and south of the road so it can be skirted, as in vanilla
    g.rect(9, 4, 15, 6, "~")
    g.rect(9, 10, 15, 12, "~")
    g.rect(22, 3, 29, 6, "~")
    g.rect(23, 10, 31, 13, "~")
    # a ledge: hop south from the northern shelf back onto the road
    g.hline(5, 32, 36, "L")
    g.rect(32, 2, 36, 4, "g")
    g.rect(32, 6, 36, 7, ".")
    return emit(
        g, "route_201", "Route 201", "route_201",
        warps=[
            {"x": 5, "y": 15, "to": "twinleaf_town", "toX": 12, "toY": 1},
            {"x": 39, "y": 8, "to": "sandgem_town", "toX": 1, "toY": 10},
        ],
        objects=[
            {"type": "npc", "id": "r201_rowan", "x": 20, "y": 7, "sprite": "professor",
             "script": "r201_rowan", "lines": [
                 "Tall grass is where wild Pokemon hide.",
                 "Step in it and you will be battling before long."]},
        ],
        note="Tall grass (collision 4) is wired to encounter zone route_201.")


def sandgem_town():
    g = Grid(24, 20, ".")
    g.border("#")
    g.hline(10, 1, 22, ",")
    g.set(0, 10, ",")                    # west seam tile (warp to Route 201)
    g.vline(12, 1, 18, ",")
    g.set(12, 0, ",")                    # north seam tile (warp to Route 202)
    # Rowan's lab
    g.rect(5, 4, 9, 7, "B")
    g.set(7, 7, ",")
    # the beach on the east side
    g.rect(17, 12, 22, 18, "s")
    g.rect(19, 15, 22, 18, "w")
    g.rect(21, 17, 22, 18, "W")
    # Pokemon Center stand-in
    g.rect(3, 13, 6, 16, "b")
    g.set(4, 16, ",")
    return emit(
        g, "sandgem_town", "Sandgem Town", "sandgem_town",
        warps=[
            {"x": 0, "y": 10, "to": "route_201", "toX": 38, "toY": 8},
            {"x": 12, "y": 0, "to": "route_202", "toX": 12, "toY": 22},
        ],
        objects=[
            {"type": "spawn", "id": "sandgem_center", "x": 4, "y": 17},
            {"type": "npc", "id": "sandgem_aide", "x": 8, "y": 8, "sprite": "aide",
             "script": "sandgem_aide", "lines": [
                 "The lab keeps the regional Pokedex.",
                 "Head north on Route 202 for Jubilife City."]},
        ])


def route_202():
    g = Grid(26, 24, ".")
    g.border("#")
    g.vline(12, 1, 22, ",")
    g.set(12, 23, ",")                   # south seam tile (warp to Sandgem)
    g.set(12, 0, ",")                    # north seam tile (warp to Jubilife)
    g.rect(5, 5, 10, 10, "~")
    g.rect(14, 6, 20, 11, "~")
    g.rect(6, 14, 10, 19, "~")
    g.rect(15, 15, 21, 20, "~")
    # a short east spur with a ledge back down onto the road
    g.hline(12, 13, 20, ",")
    g.vline(20, 12, 13, ",")
    g.set(20, 14, "L")
    g.set(20, 15, ",")
    g.vline(20, 16, 20, ",")
    g.hline(21, 13, 20, ",")
    g.vline(12, 21, 22, ",")
    return emit(
        g, "route_202", "Route 202", "route_202",
        warps=[
            {"x": 12, "y": 23, "to": "sandgem_town", "toX": 12, "toY": 1},
            {"x": 12, "y": 0, "to": "jubilife_city", "toX": 16, "toY": 24},
        ],
        objects=[
            {"type": "npc", "id": "r202_youngster", "x": 11, "y": 8, "sprite": "youngster",
             "script": "r202_youngster", "lines": [
                 "I got flattened by the grass up ahead.",
                 "Heal up in Sandgem before you try it."]},
        ],
        note="Tall grass (collision 4) is wired to encounter zone route_202.")


def jubilife_city():
    g = Grid(32, 26, ".")
    g.border("#")
    # two avenues
    g.vline(16, 1, 24, ",")
    g.set(16, 25, ",")                   # south seam tile (warp to Route 202)
    g.hline(12, 1, 30, ",")
    g.set(31, 12, ",")                   # east seam tile (warp to Route 203)
    # city blocks
    g.rect(4, 4, 9, 8, "B")
    g.set(6, 8, ",")
    g.rect(21, 4, 27, 8, "b")
    g.set(24, 8, ",")
    g.rect(21, 16, 27, 21, "B")
    g.set(24, 16, ",")
    # the Trainers' School pond
    g.rect(3, 17, 8, 22, "W")
    g.rect(2, 16, 9, 16, "w")
    g.vline(2, 17, 22, "w")
    g.vline(9, 17, 22, "w")
    g.hline(23, 2, 9, "w")
    # keep the avenues clear of the pond
    g.hline(12, 1, 30, ",")
    g.vline(16, 1, 24, ",")
    return emit(
        g, "jubilife_city", "Jubilife City", "jubilife_city",
        warps=[
            {"x": 16, "y": 25, "to": "route_202", "toX": 12, "toY": 1},
            {"x": 31, "y": 12, "to": "route_203", "toX": 1, "toY": 8},
        ],
        objects=[
            {"type": "spawn", "id": "jubilife_center", "x": 16, "y": 13},
            {"type": "npc", "id": "jubilife_clerk", "x": 15, "y": 11, "sprite": "clerk",
             "script": "jubilife_clerk", "lines": [
                 "Oreburgh City is east, through Route 203 and the Gate.",
                 "Roark's Cranidos hits like a truck. Level up first."]},
            {"type": "item", "id": "jubilife_potion", "x": 17, "y": 20, "sprite": "ball",
             "script": "jubilife_potion", "item": "potion", "count": 2,
             "lines": ["{player} found 2 Potions!"]},
        ])


def route_203():
    g = Grid(36, 18, ".")
    g.border("#")
    g.hline(8, 1, 34, ",")
    g.set(0, 8, ",")                     # west seam tile (warp to Jubilife)
    g.set(35, 8, ",")                    # east seam tile (warp to Oreburgh Gate)
    g.rect(6, 3, 13, 6, "~")
    g.rect(7, 11, 14, 14, "~")
    g.rect(21, 3, 28, 6, "~")
    g.rect(22, 11, 29, 14, "~")
    # a northern shelf with a ledge back down onto the road
    g.rect(16, 4, 20, 5, "g")
    g.hline(6, 16, 20, "L")
    g.hline(7, 16, 20, ".")
    g.vline(16, 3, 4, ",")
    g.hline(2, 14, 20, ",")
    g.vline(14, 2, 7, ",")
    return emit(
        g, "route_203", "Route 203", "route_203",
        warps=[
            {"x": 0, "y": 8, "to": "jubilife_city", "toX": 30, "toY": 12},
            {"x": 35, "y": 8, "to": "oreburgh_gate", "toX": 1, "toY": 6},
        ],
        objects=[
            {"type": "npc", "id": "r203_hiker", "x": 30, "y": 7, "sprite": "hiker",
             "script": "r203_hiker", "lines": [
                 "Oreburgh Gate is just east of here.",
                 "There are cracked rocks inside. Nothing I can do about them."]},
        ],
        note="Tall grass (collision 4) is wired to encounter zone route_203.")


def oreburgh_gate():
    """The one map with a badge-gated obstacle.

    The SMASH rock sits on a SIDE ALCOVE, never on the main corridor: Roark is
    the boss who *awards* the Coal badge, so a rock across the only way through
    would make the slice unwinnable. validate() proves both halves of that --
    Roark reachable with no badges, the alcove reachable only with Coal.
    """
    g = Grid(20, 14, "X")
    # main corridor: west mouth -> south dogleg -> east mouth
    g.hline(6, 0, 9, "C")
    g.vline(9, 6, 10, "C")
    g.hline(10, 9, 18, "C")
    g.vline(18, 7, 10, "C")
    g.set(19, 7, "C")                    # east mouth tile (warp to Oreburgh City)
    # widen it so it reads as a cave, not a pipe
    g.hline(5, 2, 8, "C")
    g.hline(7, 2, 8, "C")
    g.hline(9, 10, 17, "C")
    g.hline(11, 10, 17, "C")
    # the SMASH alcove, north off the corridor at x=5
    g.vline(5, 2, 5, "C")
    g.rect(3, 1, 7, 2, "C")
    g.set(5, 4, "C")                     # the rock stands on this walkable tile
    return emit(
        g, "oreburgh_gate", "Oreburgh Gate", "oreburgh_gate_1f",
        warps=[
            {"x": 0, "y": 6, "to": "route_203", "toX": 34, "toY": 8},
            {"x": 19, "y": 7, "to": "oreburgh_city", "toX": 1, "toY": 14},
        ],
        traversal=[{"x": 5, "y": 4, "type": "smash", "requires": "badge:coal"}],
        objects=[
            {"type": "item", "id": "gate_escape_rope", "x": 4, "y": 1, "sprite": "ball",
             "script": "gate_escape_rope", "item": "super-potion", "count": 1,
             "lines": ["{player} found a Super Potion behind the rock!"]},
            {"type": "npc", "id": "gate_worker", "x": 12, "y": 9, "sprite": "worker",
             "script": "gate_worker", "lines": [
                 "That cracked rock up the north passage?",
                 "Gym Leaders teach you how to break those. Ours is Roark, east of here."]},
        ],
        note=("The smash rock at (5,4) gates a DEAD-END alcove only. The main corridor "
              "west mouth -> east mouth is always open, because Roark is the boss who "
              "awards badge:coal."))


def oreburgh_city():
    g = Grid(26, 22, ".")
    g.border("#")
    g.hline(14, 1, 24, ",")
    g.set(0, 14, ",")                    # west seam tile (warp to Oreburgh Gate)
    g.vline(13, 9, 20, ",")
    # the gym: a solid block whose bottom-middle tile is the walkable door
    g.rect(10, 4, 16, 8, "B")
    g.set(13, 8, ",")                    # the gym door (warp)
    # the mine entrance and a couple of houses, all scenery in this slice
    g.rect(3, 4, 7, 8, "^")
    g.rect(19, 5, 23, 9, "b")
    g.rect(4, 17, 8, 20, "b")
    g.rect(18, 17, 22, 20, "b")
    g.hline(16, 4, 22, ",")
    g.vline(6, 15, 16, ",")
    g.vline(20, 15, 16, ",")
    return emit(
        g, "oreburgh_city", "Oreburgh City", "oreburgh_city",
        warps=[
            {"x": 0, "y": 14, "to": "oreburgh_gate", "toX": 18, "toY": 7},
            {"x": 13, "y": 8, "to": "oreburgh_gym", "toX": 6, "toY": 12},
        ],
        objects=[
            {"type": "spawn", "id": "oreburgh_center", "x": 13, "y": 15},
            {"type": "npc", "id": "oreburgh_miner", "x": 12, "y": 9, "sprite": "worker",
             "script": "oreburgh_miner", "lines": [
                 "The Gym is right behind me. Roark is the Leader AND a miner.",
                 "Beat him and the Coal Badge lets you smash cracked rocks."]},
        ])


def oreburgh_gym():
    g = Grid(14, 14, "X")
    g.rect(1, 1, 12, 12, "C")
    g.set(6, 13, "C")                    # the door tile (warp back to the city)
    # a rock-strewn arena: pillars the player has to walk around
    for px, py in [(3, 5), (10, 5), (3, 9), (10, 9)]:
        g.set(px, py, "X")
    g.set(6, 3, "N")                     # Roark stands here (blocked, faced to talk)
    g.set(3, 7, "N")                      # gym trainer
    g.set(10, 7, "N")                     # gym trainer
    return emit(
        g, "oreburgh_gym", "Oreburgh Gym", "oreburgh_gym",
        warps=[{"x": 6, "y": 13, "to": "oreburgh_city", "toX": 13, "toY": 9}],
        objects=[
            {"type": "boss", "id": "roark", "x": 6, "y": 3, "sprite": "leader_roark",
             "script": "boss_roark", "boss": "roark", "lines": [
                 "I'm Roark, and I dig Rock-type Pokemon!",
                 "My Cranidos has a head like a drill. Let's see yours hold up!"],
             "afterLines": [
                 "You cracked me wide open. Take the Coal Badge.",
                 "And this -- Aerodactylite. A Mega Stone. You will want the Ring to use it."]},
            {"type": "npc", "id": "gym_trainer_left", "x": 3, "y": 7, "sprite": "youngster",
             "script": "gym_trainer_left", "lines": [
                 "Rock types shrug off Normal and Flying moves.",
                 "Grass and Water tear through them."]},
            {"type": "npc", "id": "gym_trainer_right", "x": 10, "y": 7, "sprite": "camper",
             "script": "gym_trainer_right", "lines": [
                 "Cranidos has Mold Breaker. Sturdy will not save you."]},
        ],
        note="Roark stands on a collision-1 tile; you talk to him by facing him.")


BUILDERS = [
    twinleaf_town, route_201, sandgem_town, route_202, jubilife_city,
    route_203, oreburgh_gate, oreburgh_city, oreburgh_gym,
]

# The adjacencies the slice must support, both ways.
ADJACENT = [
    ("twinleaf_town", "route_201"),
    ("route_201", "sandgem_town"),
    ("sandgem_town", "route_202"),
    ("route_202", "jubilife_city"),
    ("jubilife_city", "route_203"),
    ("route_203", "oreburgh_gate"),
    ("oreburgh_gate", "oreburgh_city"),
    ("oreburgh_city", "oreburgh_gym"),
]

GRASS_ROUTES = ["route_201", "route_202", "route_203"]

START = ("twinleaf_town", (12, 12))
ROARK_TILE = ("oreburgh_gym", (6, 4))          # the tile you stand on to face Roark
ALCOVE_TILE = ("oreburgh_gate", (5, 2))        # behind the smash rock


# ==========================================================================
# Validation -- run against the emitted JSON, never against the drawings
# ==========================================================================

def code_at(m, cell):
    x, y = cell
    if not (0 <= x < m["width"] and 0 <= y < m["height"]):
        return 1
    return m["collision"][y][x]


def walkable(m, cell):
    if code_at(m, cell) not in LAND_CODES:
        return False
    for t in m["traversal"]:
        if (t["x"], t["y"]) == cell:
            return False
    return True


def obstacle_at(m, cell):
    for t in m["traversal"]:
        if (t["x"], t["y"]) == cell:
            return t
    return None


def world_bfs(maps, start, badges):
    """Reachable (map_id, cell) states for a walking player holding `badges`."""
    seen = {start}
    q = deque([start])
    while q:
        map_id, cell = q.popleft()
        m = maps[map_id]
        # a warp on this tile moves you, and that is the only thing that happens
        for w in m["warps"]:
            if (w["x"], w["y"]) == cell:
                nxt = (w["to"], (w["toX"], w["toY"]))
                if nxt not in seen:
                    seen.add(nxt)
                    q.append(nxt)
                break
        for dx, dy in ((0, -1), (0, 1), (-1, 0), (1, 0)):
            tgt = (cell[0] + dx, cell[1] + dy)
            if not (0 <= tgt[0] < m["width"] and 0 <= tgt[1] < m["height"]):
                continue
            ob = obstacle_at(m, tgt)
            if ob is not None:
                need = ob.get("requires", "")
                verb_badge = need.split(":", 1)[1] if need.startswith("badge:") else None
                if verb_badge not in badges:
                    continue
                landed = tgt
            elif code_at(m, tgt) == 2:
                # a ledge is a one-way southbound hop onto the tile beyond it
                if (dx, dy) != (0, 1):
                    continue
                landed = (cell[0], cell[1] + 2)
                if not walkable(m, landed):
                    continue
            elif code_at(m, tgt) in LAND_CODES:
                landed = tgt
            else:
                continue
            state = (map_id, landed)
            if state not in seen:
                seen.add(state)
                q.append(state)
    return seen


def validate(maps, encounters):
    errors = []
    warns = []

    def err(msg):
        errors.append(msg)

    for map_id, m in sorted(maps.items()):
        cells = m["width"] * m["height"]
        if m["id"] != map_id:
            err("%s: id field is '%s'" % (map_id, m["id"]))
        if m["tileSize"] != TILE:
            err("%s: tileSize %s" % (map_id, m["tileSize"]))
        for layer_name, grid in m["layers"].items():
            if len(grid) != m["height"] or any(len(r) != m["width"] for r in grid):
                err("%s: layer '%s' is not %dx%d" % (map_id, layer_name, m["width"], m["height"]))
        if len(m["collision"]) != m["height"] or any(len(r) != m["width"] for r in m["collision"]):
            err("%s: collision grid is not %dx%d" % (map_id, m["width"], m["height"]))
        for row in m["collision"]:
            for c in row:
                if c not in (0, 1, 2, 3, 4, 5, 6, 7):
                    err("%s: collision code %r is not in the contract" % (map_id, c))
        flat = sum(len(r) for r in m["collision"])
        if flat != cells:
            err("%s: collision has %d cells, expected %d" % (map_id, flat, cells))

        # warps
        for w in m["warps"]:
            here = (w["x"], w["y"])
            if code_at(m, here) not in LAND_CODES:
                err("%s: warp tile %s has collision %d, so it can never be stepped on"
                    % (map_id, here, code_at(m, here)))
            dest = maps.get(w["to"])
            if dest is None:
                err("%s: warp -> '%s' which does not exist" % (map_id, w["to"]))
                continue
            cell = (w["toX"], w["toY"])
            if not (0 <= cell[0] < dest["width"] and 0 <= cell[1] < dest["height"]):
                err("%s: warp -> %s %s is out of bounds" % (map_id, w["to"], cell))
            elif not walkable(dest, cell):
                err("%s: warp -> %s %s lands on collision %d"
                    % (map_id, w["to"], cell, code_at(dest, cell)))

        # traversal
        for t in m["traversal"]:
            if t["type"] == "defog":
                err("%s: defog obstacle -- there is no defog verb" % map_id)
            if not t.get("requires", "").startswith(("badge:", "flag:")):
                err("%s: obstacle at %s has requires=%r" % (map_id, (t["x"], t["y"]), t.get("requires")))
            if code_at(m, (t["x"], t["y"])) not in LAND_CODES:
                err("%s: obstacle at %s stands on collision %d; clearing it would strand you"
                    % (map_id, (t["x"], t["y"]), code_at(m, (t["x"], t["y"]))))

        # objects
        for o in m["objects"]:
            cell = (o["x"], o["y"])
            if o["type"] in ("npc", "boss", "item"):
                if code_at(m, cell) != 1:
                    err("%s: %s '%s' at %s is on collision %d; it must be 1 so the "
                        "player bumps into it instead of walking through it"
                        % (map_id, o["type"], o["id"], cell, code_at(m, cell)))
            elif o["type"] == "spawn":
                if not walkable(m, cell):
                    err("%s: spawn '%s' at %s is not walkable" % (map_id, o["id"], cell))

    # both directions for every adjacency
    for a, b in ADJACENT:
        for src, dst in ((a, b), (b, a)):
            if not any(w["to"] == dst for w in maps[src]["warps"]):
                err("%s has no warp to %s" % (src, dst))

    # tall grass + encounter tables
    for map_id in GRASS_ROUTES:
        m = maps[map_id]
        grass = sum(row.count(4) for row in m["collision"])
        if grass < 20:
            err("%s: only %d tall-grass tiles" % (map_id, grass))
        zone = m["encounterZone"]
        z = encounters.get(zone)
        if z is None:
            err("%s: encounterZone '%s' is not in data/rom/encounters.json" % (map_id, zone))
        else:
            if int(z.get("grassRate", 0)) <= 0:
                err("%s: zone '%s' has grassRate %s" % (map_id, zone, z.get("grassRate")))
            if not z.get("grass") and not z.get("curated"):
                err("%s: zone '%s' has an empty grass table" % (map_id, zone))

    # the SMASH obstacle
    gate = maps["oreburgh_gate"]
    smashes = [t for t in gate["traversal"] if t["type"] == "smash"]
    if len(smashes) != 1:
        err("oreburgh_gate: expected exactly 1 smash obstacle, found %d" % len(smashes))
    elif smashes[0].get("requires") != "badge:coal":
        err("oreburgh_gate: smash requires %r, expected 'badge:coal'" % smashes[0].get("requires"))

    # reachability: Roark badgeless, alcove only with Coal
    nobadge = world_bfs(maps, START, set())
    withcoal = world_bfs(maps, START, {"coal"})
    if ROARK_TILE not in nobadge:
        err("SOFT-LOCK: %s is not reachable from %s with no badges" % (ROARK_TILE, START))
    if ALCOVE_TILE in nobadge:
        err("the smash alcove %s is reachable with no badges; the rock gates nothing"
            % (ALCOVE_TILE,))
    if ALCOVE_TILE not in withcoal:
        err("the smash alcove %s is still unreachable with badge:coal" % (ALCOVE_TILE,))
    for map_id in maps:
        if not any(s[0] == map_id for s in nobadge):
            err("map '%s' is unreachable from the start" % map_id)

    # informational
    for map_id, m in sorted(maps.items()):
        reach = len([s for s in nobadge if s[0] == map_id])
        warns.append("%-16s %2dx%-2d  warps %d  grass %3d  reachable cells %d"
                     % (map_id, m["width"], m["height"], len(m["warps"]),
                        sum(row.count(4) for row in m["collision"]), reach))
    return errors, warns


def main():
    check_only = "--check" in sys.argv
    os.makedirs(OUT_DIR, exist_ok=True)

    if check_only:
        maps = {}
        for f in sorted(os.listdir(OUT_DIR)):
            if f.endswith(".json"):
                with open(os.path.join(OUT_DIR, f), "r", encoding="utf-8") as fh:
                    m = json.load(fh)
                maps[m["id"]] = m
    else:
        maps = {}
        for build in BUILDERS:
            m = build()
            maps[m["id"]] = m

    # the tileset every map names must actually declare the indices they use
    if os.path.exists(TILESET):
        with open(TILESET, "r", encoding="utf-8") as fh:
            ts = json.load(fh)
        known = {t["index"] for t in ts["tiles"]}
        for ch, (idx, _c) in sorted(LEGEND.items()):
            if idx not in known:
                print("WARN legend '%s' uses tile %d, which %s does not declare"
                      % (ch, idx, TILESET_NAME))
    else:
        print("WARN %s missing; tile indices not cross-checked" % TILESET)

    encounters = {}
    if os.path.exists(ENCOUNTERS):
        with open(ENCOUNTERS, "r", encoding="utf-8") as fh:
            encounters = json.load(fh)
    else:
        print("WARN %s missing; encounter wiring not cross-checked" % ENCOUNTERS)

    errors, info = validate(maps, encounters)

    if not check_only and not errors:
        for map_id, m in sorted(maps.items()):
            path = os.path.join(OUT_DIR, "%s.json" % map_id)
            with open(path, "w", encoding="utf-8") as fh:
                json.dump(m, fh, indent=1, sort_keys=False)
                fh.write("\n")
        # re-read and re-validate what actually landed on disk
        disk = {}
        for map_id in maps:
            with open(os.path.join(OUT_DIR, "%s.json" % map_id), "r", encoding="utf-8") as fh:
                d = json.load(fh)
            disk[d["id"]] = d
        errors, info = validate(disk, encounters)

    for line in info:
        print("  " + line)
    if errors:
        print("")
        for e in errors:
            print("FAIL " + e)
        print("\n%d problem(s)" % len(errors))
        return 1
    print("\nOK %d maps, %d warps, %d adjacencies both ways"
          % (len(maps), sum(len(m["warps"]) for m in maps.values()), len(ADJACENT)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
