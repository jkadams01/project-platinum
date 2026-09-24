#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
build_gamedata.py - extract Pokemon Platinum (US, CPUE) game data.

Outputs
    data/rom/encounters.json   (GITIGNORED - ROM-derived)  contract section 6
    data/rom/trainers.json     (GITIGNORED - ROM-derived)  contract section 7
    data/rom/text.json         (GITIGNORED - ROM-derived)  in-game name tables
    data/level_caps.json       (COMMITTED  - design table)  contract section 8

Everything ROM-derived lands under data/rom/. `data/level_caps.json` is a design
table transcribed from docs/research/game-design.md 2.5 and contains no
copyrighted ROM content, so it is committed.

References (all verified against the real cartridge dump):
    docs/DATA_CONTRACT.md
    docs/research/platinum-data.md   sections 3.1, 3.3, 3.9, 3.12
    docs/research/game-design.md     sections 2.5, 4.3

Run:
    python tools/build_gamedata.py
    python tools/build_gamedata.py --rom <path-to-platinum.nds>
"""

from __future__ import print_function

import argparse
import io
import json
import os
import re
import struct
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
DEFAULT_ROM = os.path.join(
    REPO, "References", "Roms", "Platinum",
    "3541 - Pokemon Platinum Version (US)(XenoPhobia).nds")

# ---------------------------------------------------------------------------
# NDS filesystem + NARC  (platinum-data.md section 1)
# ---------------------------------------------------------------------------

class NDS(object):
    """Nintendo DS ROM filesystem (FNT/FAT).  Resolve by PATH, never by file id."""

    def __init__(self, path):
        with open(path, "rb") as fh:
            self.d = fh.read()
        self.code = self.d[0x0C:0x10].decode("ascii", "replace")
        self.fnt_off, self.fnt_size = struct.unpack_from("<II", self.d, 0x40)
        self.fat_off, self.fat_size = struct.unpack_from("<II", self.d, 0x48)
        self.arm9_off, _, _, self.arm9_size = struct.unpack_from("<IIII", self.d, 0x20)
        self.files = []
        for i in range(self.fat_size // 8):
            self.files.append(struct.unpack_from("<II", self.d, self.fat_off + i * 8))
        self.paths = {}
        self._walk(0, "")

    def _walk(self, dir_id, prefix):
        off = self.fnt_off + (dir_id & 0xFFF) * 8
        sub, fid, _parent = struct.unpack_from("<IHH", self.d, off)
        p = self.fnt_off + sub
        while True:
            t = self.d[p] if isinstance(self.d[p], int) else ord(self.d[p])
            p += 1
            if t == 0:
                break
            if t < 0x80:
                name = self.d[p:p + t].decode("ascii", "replace")
                p += t
                self.paths[prefix + "/" + name] = fid
                fid += 1
            else:
                ln = t & 0x7F
                name = self.d[p:p + ln].decode("ascii", "replace")
                p += ln
                sub_id = struct.unpack_from("<H", self.d, p)[0]
                p += 2
                self._walk(sub_id, prefix + "/" + name)

    def read_id(self, fid):
        s, e = self.files[fid]
        return self.d[s:e]

    def read(self, path):
        return self.read_id(self.paths[path])

    def arm9(self):
        return self.d[self.arm9_off:self.arm9_off + self.arm9_size]


def narc_files(blob):
    """Split a NARC container into its sub-files."""
    if blob[:4] != b"NARC":
        raise ValueError("not a NARC: %r" % blob[:4])
    hdr_size = struct.unpack_from("<H", blob, 12)[0]
    fatb = hdr_size
    if blob[fatb:fatb + 4] != b"BTAF":
        raise ValueError("expected BTAF at %d" % fatb)
    fatb_size = struct.unpack_from("<I", blob, fatb + 4)[0]
    n = struct.unpack_from("<H", blob, fatb + 8)[0]
    ents = [struct.unpack_from("<II", blob, fatb + 12 + i * 8) for i in range(n)]
    fntb = fatb + fatb_size
    fntb_size = struct.unpack_from("<I", blob, fntb + 4)[0]
    fimg = fntb + fntb_size
    if blob[fimg:fimg + 4] != b"GMIF":
        raise ValueError("expected GMIF at %d" % fimg)
    base = fimg + 8
    return [blob[base + s:base + e] for s, e in ents]


# ---------------------------------------------------------------------------
# Text archive  (platinum-data.md section 3.9)
# ---------------------------------------------------------------------------

# Game Freak charmap, the slice this project needs. Every code below was read
# out of the real ROM and identified from context (see the probe log in the
# stream report): 0x188 appears only in "Poke(e) Ball"/"Pokemon League",
# 0x1BB/0x1BC only in NIDORAN and Swimmer, etc.
_CHARMAP_EXTRA = {
    0x0000: u"",
    0x0188: u"é",   # e-acute   -> Poke'mon
    0x01AC: u"?",        # used only in the unused "???" item slots
    0x01AE: u".",
    0x01B3: u"'",
    0x01BB: u"♂",   # male sign
    0x01BC: u"♀",   # female sign
    0x01BE: u"-",
    0x01C2: u"&",
    0x01DE: u" ",
    0x01E0: u"Pk",       # two-tile "Pkmn" ligature
    0x01E1: u"mn",
    0xE000: u"\n",
}


def _charcode(c):
    if 0x0121 <= c <= 0x012A:
        return chr(ord("0") + c - 0x0121)
    if 0x012B <= c <= 0x0144:
        return chr(ord("A") + c - 0x012B)
    if 0x0145 <= c <= 0x015E:
        return chr(ord("a") + c - 0x0145)
    if c in _CHARMAP_EXTRA:
        return _CHARMAP_EXTRA[c]
    return u"�"


def decode_bank(blob):
    """Decrypt one pl_msg bank -> list of unicode strings."""
    n, key0 = struct.unpack_from("<HH", blob, 0)
    key = (key0 * 0x2FD) & 0xFFFF
    out = []
    for i in range(n):
        k = (key * (i + 1)) & 0xFFFF
        mask = (k | (k << 16)) & 0xFFFFFFFF
        off, size = struct.unpack_from("<II", blob, 4 + i * 8)
        off ^= mask
        size ^= mask
        ck = (0x91BD3 * (i + 1)) & 0xFFFF
        msg = []
        for j in range(size):
            msg.append(struct.unpack_from("<H", blob, off + j * 2)[0] ^ ck)
            ck = (ck + 0x493D) & 0xFFFF
        if msg and msg[0] == 0xF100:
            msg = _unpack_f100(msg)
        else:
            msg = [c for c in msg if c != 0xFFFF]
        out.append(u"".join(_charcode(c) for c in msg))
    return out


def _unpack_f100(msg):
    """9-bit-per-char bitstream with only 15 USABLE BITS per u16.

    platinum-data.md gotcha 3: a 16-bit accumulator decodes exactly the first
    character correctly and garbles the rest, which reads like a charmap bug.
    This is pret MessagesDecoder::DecodeTrainerNameMessage, verbatim.
    """
    out = []
    bit = 0
    p = 1
    while p < len(msg):
        c = (msg[p] >> bit) & 0x1FF
        bit += 9
        if bit >= 15:
            p += 1
            bit -= 15
            if bit != 0 and p < len(msg):
                c |= (msg[p] << (9 - bit)) & 0x1FF
        if c == 0x1FF:
            break
        out.append(c)
    return out


BANK_ITEM_NAMES = 392
BANK_SPECIES_NAMES = 412
BANK_LOCATION_NAMES = 433
BANK_ABILITY_NAMES = 610
BANK_MOVE_NAMES = 647
BANK_TRAINER_NAMES = 618
BANK_TRAINER_CLASSES = 619


def titlecase_species(s):
    """ROM species names are ALL CAPS. HO-OH -> Ho-Oh, FARFETCH'D -> Farfetch'd."""
    out = []
    for i, ch in enumerate(s):
        prev = s[i - 1] if i else " "
        out.append(ch.upper() if prev in u" -" else ch.lower())
    return u"".join(out)


def slug(s):
    s = s.replace(u"♂", u"-m").replace(u"♀", u"-f")
    s = s.replace(u"é", u"e")
    s = s.replace(u"'", u"")          # Farfetch'd -> farfetchd, King's Rock -> kings-rock
    s = s.lower()
    s = re.sub(u"[^a-z0-9]+", u"-", s)
    return s.strip(u"-")


# ---------------------------------------------------------------------------
# Map headers  (platinum-data.md section 3.12) - 593 entries at ARM9 0xE601C
# ---------------------------------------------------------------------------

MAP_HEADER_OFFSET = 0xE601C
MAP_HEADER_COUNT = 593


def read_map_headers(arm9):
    hdrs = []
    for i in range(MAP_HEADER_COUNT):
        b = arm9[MAP_HEADER_OFFSET + i * 24: MAP_HEADER_OFFSET + i * 24 + 24]
        flags = struct.unpack_from("<H", b, 0x16)[0]
        hdrs.append({
            "id": i,
            "areaDataArchiveID": b[0] if isinstance(b[0], int) else ord(b[0]),
            "mapMatrixID": struct.unpack_from("<H", b, 0x02)[0],
            "scriptsArchiveID": struct.unpack_from("<H", b, 0x04)[0],
            "msgArchiveID": struct.unpack_from("<H", b, 0x08)[0],
            "wildEncountersArchiveID": struct.unpack_from("<H", b, 0x0E)[0],
            "eventsArchiveID": struct.unpack_from("<H", b, 0x10)[0],
            "mapLabelTextID": struct.unpack_from("<B", b, 0x12)[0],
            "mapType": flags & 0x7F,
        })
    return hdrs


# ---------------------------------------------------------------------------
# Wild encounters  (platinum-data.md section 3.1) - 424 bytes fixed
# ---------------------------------------------------------------------------

# The real Gen 4 land slot ladder; sums to exactly 100.
# NOTE: game-design.md 4.1 quotes "20,20,10,10,10,10,10,10,5,5,4,4", which sums
# to 118 and is not the game's table. Vanilla rows use the correct rates below;
# curated rows keep the per-row weights the design document assigns them.
GRASS_SLOT_RATES = [20, 20, 10, 10, 10, 10, 5, 5, 4, 4, 1, 1]
WATER_SLOT_RATES = [60, 30, 5, 4, 1]
assert sum(GRASS_SLOT_RATES) == 100 and sum(WATER_SLOT_RATES) == 100


def _water(blob, off):
    rate = struct.unpack_from("<I", blob, off)[0]
    slots = []
    for i in range(5):
        # NOTE: water stores maxLevel BEFORE minLevel (gotcha 6).
        # entry = u8 maxLevel; u8 minLevel; u8 pad[2]; u32 species  -> 8 bytes
        mx, mn = struct.unpack_from("<BB", blob, off + 4 + i * 8)
        sp = struct.unpack_from("<I", blob, off + 4 + i * 8 + 4)[0]
        slots.append({"slot": i, "species": sp, "min": mn, "max": mx,
                      "rate": WATER_SLOT_RATES[i]})
    return rate, slots


def _merge(slots):
    """Collapse per-slot rows into contract {species,min,max,weight} entries."""
    order, acc = [], {}
    for s in slots:
        sp = s["species"]
        if sp == 0:
            continue
        if sp not in acc:
            acc[sp] = {"species": sp, "min": s["min"], "max": s["max"],
                       "weight": 0}
            order.append(sp)
        e = acc[sp]
        e["min"] = min(e["min"], s["min"])
        e["max"] = max(e["max"], s["max"])
        e["weight"] += s["rate"]
    return [acc[sp] for sp in order]


def parse_encounter_set(blob):
    if len(blob) != 424:
        raise ValueError("encounter file is %d bytes, expected 424" % len(blob))
    grass_rate = struct.unpack_from("<I", blob, 0x000)[0]
    grass_slots = []
    for i in range(12):
        lvl, sp = struct.unpack_from("<b3xI", blob, 0x004 + i * 8)
        grass_slots.append({"slot": i, "species": sp, "min": lvl, "max": lvl,
                            "rate": GRASS_SLOT_RATES[i]})

    def u32s(off, n):
        return list(struct.unpack_from("<%dI" % n, blob, off))

    surf_rate, surf = _water(blob, 0x0CC)
    old_rate, old_rod = _water(blob, 0x124)
    good_rate, good_rod = _water(blob, 0x150)
    super_rate, super_rod = _water(blob, 0x17C)

    return {
        "grassRate": grass_rate,
        "grass": _merge(grass_slots),
        "surf": _merge(surf),
        "oldRod": _merge(old_rod),
        "goodRod": _merge(good_rod),
        "superRod": _merge(super_rod),
        "curated": [],
        "rates": {"surf": surf_rate, "oldRod": old_rate,
                  "goodRod": good_rate, "superRod": super_rate},
        "grassSlots": grass_slots,
        "variants": {
            "swarm": u32s(0x064, 2),
            "dayOnly": u32s(0x06C, 2),
            "nightOnly": u32s(0x074, 2),
            "pokeRadar": u32s(0x07C, 4),
            "unownTableID": struct.unpack_from("<I", blob, 0x0A0)[0],
            "dualSlot": {
                "ruby": u32s(0x0A4, 2), "sapphire": u32s(0x0AC, 2),
                "emerald": u32s(0x0B4, 2), "firered": u32s(0x0BC, 2),
                "leafgreen": u32s(0x0C4, 2),
            },
        },
    }


# Encounter-set index -> stable map key.
#
# Derived from the ARM9 map-header table (each of the 154 live sets is claimed
# by exactly one header) and cross-checked against the decoded table contents.
#
# CORRECTION vs docs/research/game-design.md 4.3, which lists
# "Oreburgh Gate 1F = #53 / B1F = #54" and "Ravaged Path = #55". The ROM says
# the opposite: header 254 (label "Ravaged Path") -> set 53, headers 258/259
# (label "Oreburgh Gate") -> sets 54/55. The table contents agree with the ROM:
# set 53 is Zubat/Psyduck L3-6 with no Geodude (Ravaged Path), set 55 carries
# Golbat L10 + Geodude L6-8 (Oreburgh Gate B1F). Keys below follow the ROM.
ENCOUNTER_KEY_OVERRIDES = {
    5:   "oreburgh_mine_1f",
    6:   "oreburgh_mine_b1f",
    8:   "eterna_forest",
    53:  "ravaged_path",
    54:  "oreburgh_gate_1f",
    55:  "oreburgh_gate_b1f",
    140: "route_201",
    141: "route_202",
    142: "route_203",
    143: "route_204_south",
    144: "route_204_north",
    145: "route_205_south",
    146: "route_205_north",
}


# ---------------------------------------------------------------------------
# Curated Gen 1-9 additions  (game-design.md section 4.3, first 8 areas)
#
# Only the CROSS-GEN GUESTS live here; vanilla rows are already in "grass".
# Fields: (species, gen, minLvl, maxLvl, weight, note)
# ---------------------------------------------------------------------------

def _c(species, gen, lo, hi, weight, note, table="grass", time=None):
    e = {"species": species, "name": note.split(",")[0].strip(),
         "min": lo, "max": hi, "weight": weight,
         "gen": gen, "note": note, "table": table}
    if time:
        e["time"] = time
    return e


_OREBURGH_GATE_CURATED = [
    _c(524, 5, 5, 5, 10, "Roggenrola, gen 5 - pure Rock, no edge on Roark"),
    _c(837, 8, 5, 5, 10, "Rolycoly, gen 8 - coal, the Oreburgh signature"),
    _c(744, 7, 6, 6, 5, "Rockruff, gen 7"),
    _c(932, 9, 6, 6, 5, "Nacli, gen 9"),
    _c(527, 5, 6, 6, 4, "Woobat, gen 5 - bat variety against Zubat monotony"),
    _c(714, 6, 6, 6, 4, "Noibat, gen 6 - evolves L48, a long-term project"),
    _c(833, 8, 20, 40, 5, "Chewtle, gen 8", table="surf"),
    _c(535, 5, 20, 40, 5, "Tympole, gen 5", table="surf"),
    _c(60, 1, 10, 25, 5, "Poliwag, gen 1", table="goodRod"),
    _c(938, 9, 10, 25, 5, "Tadbulb, gen 9", table="goodRod"),
]

_OREBURGH_MINE_CURATED = [
    _c(837, 8, 6, 6, 10, "Rolycoly, gen 8 - coal seam"),
    _c(524, 5, 6, 6, 10, "Roggenrola, gen 5"),
    _c(932, 9, 7, 7, 10, "Nacli, gen 9 - salt vein"),
    _c(299, 3, 7, 7, 5, "Nosepass, gen 3 - magnetic ore"),
    _c(744, 7, 7, 7, 5, "Rockruff, gen 7"),
    _c(213, 2, 8, 8, 4, "Shuckle, gen 2 - the deep-mine find"),
    _c(703, 6, 8, 8, 4, "Carbink, gen 6 - the mine's treasure"),
]

CURATED = {
    "route_201": [
        _c(915, 9, 3, 3, 10, "Lechonk, gen 9 - rural forager, evolves L18"),
        _c(659, 6, 3, 3, 10, "Bunnelby, gen 6 - hedgerow digger, evolves L20"),
        _c(29, 1, 4, 4, 5, "Nidoran-f, gen 1 - promoted from the vanilla Poke Radar slot"),
        _c(32, 1, 4, 4, 5, "Nidoran-m, gen 1 - promoted from the vanilla Poke Radar slot"),
        _c(819, 8, 4, 4, 5, "Skwovet, gen 8 - berry thief"),
        _c(163, 2, 4, 4, 4, "Hoothoot, gen 2", time="night"),
        _c(831, 8, 4, 4, 4, "Wooloo, gen 8", time="day"),
    ],
    "route_202": [
        _c(263, 3, 4, 4, 10, "Zigzagoon, gen 3 - promoted from the vanilla swarm slot"),
        _c(161, 2, 4, 4, 10, "Sentret, gen 2 - promoted from the vanilla Poke Radar slot"),
        _c(506, 5, 4, 4, 5, "Lillipup, gen 5 - farm dog, evolves L16"),
        _c(921, 9, 4, 4, 5, "Pawmi, gen 9 - second electric option beside Shinx"),
        _c(661, 6, 5, 5, 4, "Fletchling, gen 6"),
        _c(736, 7, 5, 5, 4, "Grubbin, gen 7 - gen 7's temperate-forest entry"),
    ],
    "route_203": [
        _c(522, 5, 5, 5, 10, "Blitzle, gen 5 - pasture electric, evolves L27"),
        _c(280, 3, 5, 5, 5, "Ralts, gen 3 - slow bloomer, evolves L20"),
        _c(187, 2, 5, 5, 5, "Hoppip, gen 2"),
        _c(919, 9, 6, 6, 4, "Nymble, gen 9"),
        _c(819, 8, 6, 6, 4, "Skwovet, gen 8 - fills the slot Cubone is held out of"),
    ],
    "oreburgh_gate_1f": list(_OREBURGH_GATE_CURATED),
    "oreburgh_gate_b1f": list(_OREBURGH_GATE_CURATED),
    "oreburgh_mine_1f": list(_OREBURGH_MINE_CURATED),
    "oreburgh_mine_b1f": list(_OREBURGH_MINE_CURATED),
    "route_204_south": [
        _c(742, 7, 5, 5, 5, "Cutiefly, gen 7 - meadow verge"),
        _c(540, 5, 5, 5, 5, "Sewaddle, gen 5"),
        _c(824, 8, 6, 6, 4, "Blipbug, gen 8"),
        _c(191, 2, 6, 6, 4, "Sunkern, gen 2 - promoted from the vanilla Poke Radar slot"),
    ],
    "route_204_north": [
        _c(742, 7, 10, 10, 5, "Cutiefly, gen 7 - meadow verge"),
        _c(540, 5, 10, 10, 5, "Sewaddle, gen 5"),
        _c(824, 8, 11, 11, 4, "Blipbug, gen 8"),
        _c(191, 2, 11, 11, 4, "Sunkern, gen 2 - promoted from the vanilla Poke Radar slot"),
        _c(664, 6, 10, 10, 10, "Scatterbug, gen 6 - north only, swaps the Kricketot slot"),
        _c(43, 1, 10, 10, 10, "Oddish, gen 1 - north only, swaps the Wurmple slot"),
    ],
    "ravaged_path": [
        _c(194, 2, 8, 8, 10, "Wooper, gen 2 - cave pool"),
        _c(535, 5, 8, 8, 10, "Tympole, gen 5"),
        _c(751, 7, 9, 9, 10, "Dewpider, gen 7 - bubble spider on the cave water"),
        _c(270, 3, 9, 9, 5, "Lotad, gen 3"),
        _c(833, 8, 10, 10, 4, "Chewtle, gen 8"),
        _c(938, 9, 10, 10, 4, "Tadbulb, gen 9 - a glowing bulb in a dark cave"),
        _c(60, 1, 10, 25, 5, "Poliwag, gen 1 - post-Fen return visit", table="goodRod"),
    ],
    "route_205_south": [
        _c(183, 2, 10, 10, 10, "Marill, gen 2 - riverbank"),
        _c(283, 3, 10, 10, 10, "Surskit, gen 3"),
        _c(580, 5, 11, 11, 5, "Ducklett, gen 5"),
        _c(669, 6, 11, 11, 5, "Flabebe, gen 6 - riverside flowers"),
        _c(751, 7, 12, 12, 4, "Dewpider, gen 7"),
        _c(938, 9, 12, 12, 4, "Tadbulb, gen 9"),
    ],
    "route_205_north": [
        _c(840, 8, 13, 13, 5, "Applin, gen 8 - orchard verge"),
        _c(917, 9, 13, 13, 5, "Tarountula, gen 9"),
        _c(165, 2, 14, 14, 4, "Ledyba, gen 2 - day half of the day/night split", time="day"),
        _c(167, 2, 14, 14, 4, "Spinarak, gen 2 - night half of the day/night split", time="night"),
    ],
    "eterna_forest": [
        _c(543, 5, 12, 12, 10, "Venipede, gen 5"),
        _c(46, 1, 12, 12, 10, "Paras, gen 1 - mushroom forest"),
        _c(755, 7, 13, 13, 5, "Morelull, gen 7 - glowing caps under the canopy", time="night"),
        _c(708, 6, 14, 14, 4, "Phantump, gen 6 - pairs with Gastly; needs a non-trade evo", time="night"),
        _c(285, 3, 14, 14, 4, "Shroomish, gen 3"),
        _c(948, 9, 13, 13, 0, "Toedscool, gen 9 - swarm slot", table="swarm"),
        _c(759, 7, 13, 13, 0, "Stufful, gen 7 - alternate swarm if Toedscool reads too strange",
           table="swarmAlt"),
        _c(736, 7, 12, 12, 0, "Grubbin, gen 7 - Poke Radar slot", table="pokeRadar"),
        _c(824, 8, 12, 12, 0, "Blipbug, gen 8 - Poke Radar slot", table="pokeRadar"),
    ],
}


# ---------------------------------------------------------------------------
# Trainers  (platinum-data.md section 3.3)
# ---------------------------------------------------------------------------

# monDataType -> (entry size, has moves, has item)
MON_VARIANTS = {0: (8, False, False), 1: (16, True, False),
                2: (10, False, True), 3: (18, True, True)}

GYM_LEADERS = {
    246: ("roark", "coal"), 315: ("gardenia", "forest"),
    318: ("fantina", "relic"), 317: ("maylene", "cobble"),
    316: ("crasher_wake", "fen"), 250: ("byron", "mine"),
    319: ("candice", "icicle"), 320: ("volkner", "beacon"),
}
ELITE_FOUR = {261: "aaron", 262: "bertha", 263: "flint",
              264: "lucian", 267: "cynthia"}
GALACTIC = {
    295: "mars_windworks", 406: "jupiter_eterna", 913: "cyrus_celestic",
    408: "saturn_lake_valor", 405: "mars_lake_verity", 409: "saturn_galactic_hq",
    403: "cyrus_galactic_hq", 528: "mars_spear_pillar", 407: "jupiter_spear_pillar",
    404: "cyrus_distortion_world",
}
RIVAL = {851: "rival_1_route_201", 248: "rival_2_route_203",
         471: "rival_3_route_209", 474: "rival_4_pastoria",
         477: "rival_5_canalave", 619: "rival_6_spear_pillar",
         480: "rival_7_league"}


def trainer_key(tid):
    if tid in GYM_LEADERS:
        return GYM_LEADERS[tid][0]
    if tid in ELITE_FOUR:
        return ELITE_FOUR[tid]
    if tid in GALACTIC:
        return GALACTIC[tid]
    if tid in RIVAL:
        return RIVAL[tid]
    return "trainer_%03d" % tid


def trainer_category(tid):
    if tid in GYM_LEADERS:
        return "gym-leader"
    if tid == 267:
        return "champion"
    if tid in ELITE_FOUR:
        return "elite-four"
    if tid in GALACTIC:
        return "galactic-boss"
    if tid in RIVAL:
        return "rival"
    return "trainer"


def parse_trainers(trdata, trpoke, names, classes, move_names, item_names):
    out = {}
    for tid in range(len(trdata)):
        h = trdata[tid]
        if len(h) != 20:
            raise ValueError("trdata[%d] is %d bytes, expected 20" % (tid, len(h)))
        mdt, cls, sprite, psize = struct.unpack_from("<4B", h, 0)
        items = list(struct.unpack_from("<4H", h, 4))
        ai, battle_type = struct.unpack_from("<II", h, 12)
        esize, has_moves, has_item = MON_VARIANTS[mdt & 0x3]

        blob = trpoke[tid]
        # gotcha 1: the blob is partySize*entrySize rounded UP to a multiple of 4.
        need = psize * esize
        if len(blob) < need:
            raise ValueError("trpoke[%d]: %d bytes < %d needed" % (tid, len(blob), need))
        if len(blob) != ((need + 3) // 4) * 4 and psize:
            raise ValueError("trpoke[%d]: size %d, expected %d (4-byte padded)"
                             % (tid, len(blob), ((need + 3) // 4) * 4))

        party = []
        for i in range(psize):
            p = i * esize
            iv_scale, level, sp_raw = struct.unpack_from("<3H", blob, p)
            q = p + 6
            item_id = None
            if has_item:
                item_id = struct.unpack_from("<H", blob, q)[0]
                q += 2
            move_ids = None
            if has_moves:
                move_ids = list(struct.unpack_from("<4H", blob, q))
                q += 8
            seal = struct.unpack_from("<H", blob, q)[0]
            species = sp_raw & 0x3FF
            form = sp_raw >> 10
            mon = {
                "species": species,
                "level": level,
                # move id 0 = the empty slot; emit null, not "".
                "moves": ([(slug(move_names[m]) if 0 < m < len(move_names) else None)
                           for m in move_ids] if move_ids else None),
                "item": (slug(item_names[item_id])
                         if item_id else None),
                "ability": 0,
                "nature": None,
                # extras beyond the contract minimum, for a faithful runtime
                "moveIds": move_ids,
                "itemId": item_id,
                "form": form,
                "ivScale": iv_scale & 0xFF,
                "ballSeal": seal,
            }
            party.append(mon)

        name = names[tid] if tid < len(names) else u""
        entry = {
            "id": tid,
            "name": name,
            "class": trainer_category(tid),
            "trainerClass": cls,
            "trainerClassName": classes[cls] if cls < len(classes) else None,
            "ai": ai,
            # Gen 4 prize money = classPrizeRate * lastMonLevel. The per-class
            # rate table was NOT located in this ROM, so this is left null
            # rather than guessed; see the stream report.
            "prizeMoney": None,
            "party": party,
            "monDataType": mdt,
            "sprite": sprite,
            "battleType": "double" if battle_type == 2 else "single",
            "battleItems": [i for i in items if i],
        }
        if tid in GYM_LEADERS:
            entry["badge"] = GYM_LEADERS[tid][1]
        out[trainer_key(tid)] = entry
    return out


# ---------------------------------------------------------------------------
# Level caps  (game-design.md section 2.5) - COMMITTED design table
# ---------------------------------------------------------------------------

LEVEL_CAPS = {
    "caps": [
        {"index": 0, "checkpoint": "start", "location": "Twinleaf Town",
         "ace": None, "cap": 14, "raisedBy": None},
        {"index": 1, "checkpoint": "roark", "location": "Oreburgh Gym",
         "ace": "Cranidos 14", "cap": 14, "raisedBy": "badge:coal"},
        {"index": 2, "checkpoint": "gardenia", "location": "Eterna Gym",
         "ace": "Roserade 22", "cap": 22, "raisedBy": "badge:forest"},
        {"index": 3, "checkpoint": "fantina", "location": "Hearthome Gym",
         "ace": "Mismagius 26", "cap": 26, "raisedBy": "badge:relic"},
        {"index": 4, "checkpoint": "maylene", "location": "Veilstone Gym",
         "ace": "Lucario 32", "cap": 32, "raisedBy": "badge:cobble"},
        {"index": 5, "checkpoint": "crasher_wake", "location": "Pastoria Gym",
         "ace": "Floatzel 37", "cap": 37, "raisedBy": "badge:fen"},
        {"index": 6, "checkpoint": "byron", "location": "Canalave Gym",
         "ace": "Bastiodon 41", "cap": 41, "raisedBy": "badge:mine"},
        {"index": 7, "checkpoint": "candice", "location": "Snowpoint Gym",
         "ace": "Froslass 44", "cap": 44, "raisedBy": "badge:icicle"},
        {"index": 8, "checkpoint": "volkner", "location": "Sunyshore Gym",
         "ace": "Electivire 50", "cap": 50, "raisedBy": "badge:beacon"},
        {"index": 9, "checkpoint": "aaron", "location": "Elite Four",
         "ace": "Drapion 53", "cap": 53, "raisedBy": "flag:aaron_defeated"},
        {"index": 10, "checkpoint": "bertha", "location": "Elite Four",
         "ace": "Rhyperior 55", "cap": 55, "raisedBy": "flag:bertha_defeated"},
        {"index": 11, "checkpoint": "flint", "location": "Elite Four",
         "ace": "Magmortar 57", "cap": 57, "raisedBy": "flag:flint_defeated"},
        {"index": 12, "checkpoint": "lucian", "location": "Elite Four",
         "ace": "Gallade 59", "cap": 59, "raisedBy": "flag:lucian_defeated"},
        {"index": 13, "checkpoint": "cynthia", "location": "Pokemon League",
         "ace": "Garchomp 62", "cap": 62, "raisedBy": "flag:hall_of_fame"},
        {"index": 14, "checkpoint": "post-game", "location": None,
         "ace": None, "cap": 100, "raisedBy": "flag:hall_of_fame"},
    ],
    "postGameCap": 100,
    "rule": "hard-xp-stop",
    "notes": [
        "A Pokemon whose level >= the active cap gains 0 EXP and 0 EVs from every source.",
        "Rare Candy and Exp Candy refuse to apply at or above the cap.",
        "Evolution is NOT capped: a Pokemon that evolves at the cap level still evolves.",
        "Day-care and traded-in Pokemon have their exp gain zeroed at or above the cap too.",
        "Jupiter's Eterna Building fight (ace 23) must stay behind the Forest Badge; "
        "the pre-Gardenia cap is 22.",
    ],
}


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def write_json(path, obj):
    d = os.path.dirname(path)
    if d and not os.path.isdir(d):
        os.makedirs(d)
    with io.open(path, "w", encoding="utf-8") as fh:
        fh.write(json.dumps(obj, indent=1, sort_keys=False, ensure_ascii=False))
        fh.write(u"\n")
    return os.path.getsize(path)


def build(rom_path, out_root):
    rom = NDS(rom_path)
    if rom.code != "CPUE":
        raise SystemExit("expected Platinum US (CPUE), got %r" % rom.code)
    print("ROM %s  code=%s  %d FAT entries  %d named files"
          % (os.path.basename(rom_path), rom.code, len(rom.files), len(rom.paths)))

    rom_dir = os.path.join(out_root, "data", "rom")
    data_dir = os.path.join(out_root, "data")

    # --- text -------------------------------------------------------------
    msg = narc_files(rom.read("/msgdata/pl_msg.narc"))
    print("pl_msg.narc: %d banks" % len(msg))
    species_raw = decode_bank(msg[BANK_SPECIES_NAMES])
    species_names = [titlecase_species(s) for s in species_raw]
    move_names = decode_bank(msg[BANK_MOVE_NAMES])
    ability_names = decode_bank(msg[BANK_ABILITY_NAMES])
    item_names = decode_bank(msg[BANK_ITEM_NAMES])
    location_names = decode_bank(msg[BANK_LOCATION_NAMES])
    trainer_names = decode_bank(msg[BANK_TRAINER_NAMES])
    class_names = decode_bank(msg[BANK_TRAINER_CLASSES])

    text = {
        "_source": "pl_msg.narc, Pokemon Platinum (US, CPUE)",
        "species": species_names,
        "speciesRaw": species_raw,
        "moves": move_names,
        "abilities": ability_names,
        "items": item_names,
        "locations": location_names,
        "trainerClasses": class_names,
        "trainerNames": trainer_names,
        "slugs": {
            "species": [slug(s) for s in species_names],
            "moves": [slug(s) for s in move_names],
            "abilities": [slug(s) for s in ability_names],
            "items": [slug(s) for s in item_names],
            "locations": [slug(s) for s in location_names],
        },
    }
    n = write_json(os.path.join(rom_dir, "text.json"), text)
    print("data/rom/text.json          %7d bytes  "
          "species=%d moves=%d abilities=%d items=%d locations=%d"
          % (n, len(species_names), len(move_names), len(ability_names),
             len(item_names), len(location_names)))

    # --- encounters -------------------------------------------------------
    enc_blobs = narc_files(rom.read("/fielddata/encountdata/pl_enc_data.narc"))
    headers = read_map_headers(rom.arm9())
    owner = {}
    for h in headers:
        e = h["wildEncountersArchiveID"]
        if e != 0xFFFF:
            owner.setdefault(e, []).append(h)

    used_keys = {}
    encounters = {}
    for idx, blob in enumerate(enc_blobs):
        table = parse_encounter_set(blob)
        hs = owner.get(idx, [])
        if idx in ENCOUNTER_KEY_OVERRIDES:
            key = ENCOUNTER_KEY_OVERRIDES[idx]
        elif hs:
            base = (slug(location_names[hs[0]["mapLabelTextID"]])
                    or "zone").replace("-", "_")
            used_keys.setdefault(base, 0)
            used_keys[base] += 1
            key = base if used_keys[base] == 1 else "%s_%d" % (base, used_keys[base])
        else:
            key = "unreferenced_%03d" % idx
        table["encIndex"] = idx
        table["mapHeaders"] = [h["id"] for h in hs]
        table["locationName"] = (location_names[hs[0]["mapLabelTextID"]]
                                 if hs else None)
        table["curated"] = CURATED.get(key, [])
        encounters[key] = table

    missing = sorted(set(CURATED) - set(encounters))
    if missing:
        raise SystemExit("curated tables have no ROM home: %s" % missing)

    n = write_json(os.path.join(rom_dir, "encounters.json"), encounters)
    curated_n = sum(len(t["curated"]) for t in encounters.values())
    print("data/rom/encounters.json    %7d bytes  %d tables, %d referenced by a "
          "map header, %d curated rows across %d areas"
          % (n, len(encounters), len(owner), curated_n, len(CURATED)))

    # --- trainers ---------------------------------------------------------
    trdata = narc_files(rom.read("/poketool/trainer/trdata.narc"))
    trpoke = narc_files(rom.read("/poketool/trainer/trpoke.narc"))
    if len(trdata) != len(trpoke):
        raise SystemExit("trdata/trpoke length mismatch")
    trainers = parse_trainers(trdata, trpoke, trainer_names, class_names,
                              move_names, item_names)
    n = write_json(os.path.join(rom_dir, "trainers.json"), trainers)
    named = sum(1 for k in trainers if not k.startswith("trainer_"))
    print("data/rom/trainers.json      %7d bytes  %d trainers (%d named by key)"
          % (n, len(trainers), named))

    # --- level caps (committed) ------------------------------------------
    n = write_json(os.path.join(data_dir, "level_caps.json"), LEVEL_CAPS)
    print("data/level_caps.json        %7d bytes  %d cap rows"
          % (n, len(LEVEL_CAPS["caps"])))

    return encounters, trainers, text


# ---------------------------------------------------------------------------
# Content assertions - "exited 0" is not success
# ---------------------------------------------------------------------------

def check(label, ok, detail=""):
    print("  [%s] %s%s" % ("PASS" if ok else "FAIL", label,
                           ("  -- " + detail) if detail else ""))
    return bool(ok)


def verify(encounters, trainers, text):
    print("\nCONTENT CHECKS")
    sp = text["species"]
    ok = True

    roark = trainers["roark"]
    cran = [m for m in roark["party"] if sp[m["species"]] == "Cranidos"]
    ok &= check("Roark's party has Cranidos at level 14",
                bool(cran) and cran[0]["level"] == 14,
                "party = " + ", ".join("%s %d" % (sp[m["species"]], m["level"])
                                       for m in roark["party"]))

    cyn = trainers["cynthia"]
    garch = [m for m in cyn["party"] if sp[m["species"]] == "Garchomp"]
    ok &= check("Cynthia's party has Garchomp at level 62",
                bool(garch) and garch[0]["level"] == 62,
                "party = " + ", ".join("%s %d" % (sp[m["species"]], m["level"])
                                       for m in cyn["party"]))

    ok &= check("level cap table has 15 rows",
                len(LEVEL_CAPS["caps"]) == 15,
                "caps = %s" % [c["cap"] for c in LEVEL_CAPS["caps"]])

    r201 = encounters["route_201"]
    g = set(sp[e["species"]] for e in r201["grass"])
    ok &= check("Route 201 vanilla grass weights sum to 100",
                sum(e["weight"] for e in r201["grass"]) == 100,
                "sum = %d" % sum(e["weight"] for e in r201["grass"]))
    ok &= check("Route 201 vanilla grass contains Starly and Bidoof",
                "Starly" in g and "Bidoof" in g,
                "grass = " + ", ".join("%s L%d-%d w%d"
                                       % (sp[e["species"]], e["min"], e["max"], e["weight"])
                                       for e in r201["grass"]))

    # supporting checks
    ok &= check("928 trainers parsed", len(trainers) == 928)
    ok &= check("183 encounter tables parsed", len(encounters) == 183)
    ok &= check("all 8 gym leaders + 5 E4/champion keyed by name",
                all(k in trainers for k in
                    ["roark", "gardenia", "fantina", "maylene", "crasher_wake",
                     "byron", "candice", "volkner", "aaron", "bertha", "flint",
                     "lucian", "cynthia"]))
    ok &= check("Route 201 curated array carries Lechonk (gen 9)",
                any(e["name"] == "Lechonk" and e["species"] == 915
                    for e in r201["curated"]),
                "curated = " + ", ".join("%s #%d (gen %d) w%d"
                                         % (e["name"], e["species"], e["gen"], e["weight"])
                                         for e in r201["curated"]))
    ok &= check("vanilla and curated stay separate on Route 201",
                not (set(e["species"] for e in r201["grass"]) &
                     set(e["species"] for e in r201["curated"])))
    ok &= check("all 9 generations present across the curated first-8 areas",
                set(e["gen"] for rows in CURATED.values() for e in rows) ==
                set(range(1, 10)) - {4},
                "cross-gen guests cover gens %s (gen 4 is the vanilla baseline)"
                % sorted(set(e["gen"] for rows in CURATED.values() for e in rows)))
    ok &= check("text.json species table is 496 long and reads correctly",
                len(sp) == 496 and sp[1] == "Bulbasaur" and sp[445] == "Garchomp"
                and sp[83] == "Farfetch'd" and sp[250] == "Ho-Oh",
                "1=%s 445=%s 83=%s 250=%s" % (sp[1], sp[445], sp[83], sp[250]))
    ok &= check("trainer names decoded (0xF100 15-bit unpack)",
                trainers["roark"]["name"] == "Roark"
                and trainers["cynthia"]["name"] == "Cynthia",
                "246=%r 267=%r" % (trainers["roark"]["name"], trainers["cynthia"]["name"]))
    return ok


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--rom", default=DEFAULT_ROM)
    ap.add_argument("--out", default=REPO)
    args = ap.parse_args()
    if not os.path.isfile(args.rom):
        raise SystemExit("ROM not found: %s" % args.rom)
    encounters, trainers, text = build(args.rom, args.out)
    ok = verify(encounters, trainers, text)
    print("\n%s" % ("ALL CHECKS PASSED" if ok else "SOME CHECKS FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
