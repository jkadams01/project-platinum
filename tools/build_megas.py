#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""
build_megas.py - build the Mega Evolution tables.

Outputs
    data/megas.json   (COMMITTED - design data)   contract section 11.1
    data/items.json   (COMMITTED - design data)   Mega Stones + the Key Stone

Both files are hand-authored design data transcribed from published sources. They
contain no ROM-derived content, so they are committed (contrast data/rom/*).

Mega Evolution is THE ONLY battle gimmick in this game. Dynamax/Gigantamax,
Z-Moves and Terastallization are excluded by the owner; verify() greps the
generated JSON for every one of those tokens and fails if any appears
(DATA_CONTRACT 11.4).

Roster provenance
    XY (28) + ORAS (20)   mainline canon: types, stats, ability, height, weight.
    Legends Z-A (49)      types + stats from Z-A; ABILITIES from Pokemon Champions,
                          because Z-A has no Ability system at all (DATA_CONTRACT
                          11.5 resolution step 1). Table: docs/research/mega-abilities.md
                          section 2 / tools/_work/megaability/champions-abilities.md.
    Z-A forms Champions does not cover (9) ship "abilities": [] with
                          "abilityStatus": "pending-owner" - never a guess (11.5).

DECIDED EXCLUSIONS baked into this file
    * Primal Reversion is OUT. No primal-groudon / primal-kyogre form, no red-orb /
      blue-orb item. verify() asserts their absence.
    * Mega Rayquaza is IN and is the one Mega with no stone: stone = null,
      requiresMove = "dragon-ascent". The engine must branch on stone == null and
      check the MOVESET instead of the held item, while still obeying
      one-Mega-per-side (DATA_CONTRACT 11.5).
    * Mega Starmie uses Attack 100 WITH Huge Power (Champions/Showdown), NOT
      Serebii's Z-A figure of 140. The Z-A tables inflate stats to compensate for
      that game having no abilities; 140 + Huge Power would double-count to an
      effective 280. Champions/Showdown stat lines win over Serebii Z-A throughout.

Run
    python tools/build_megas.py
    python tools/build_megas.py --apply-owner-overrides    # see OWNER OVERRIDES below

OWNER OVERRIDES
    DATA_CONTRACT 11.5 resolution step 2 allows an owner-approved ability for a
    form Champions does not cover. Those live in data/mega_ability_overrides.json.
    They are NOT applied by default: the standing decision for this build is that
    the nine uncovered forms ship visibly unresolved (abilities [], abilityStatus
    "pending-owner") rather than resolved from a recommendation. Pass
    --apply-owner-overrides to fold that file in; each applied row keeps the
    abilityStatus recorded in the file so provenance survives.
"""

from __future__ import print_function

import argparse
import json
import os
import re
import subprocess
import sys

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))

KEY_ITEM = "key-stone"
BATTLE_RULE = "one-per-battle"

# ---------------------------------------------------------------------------
# The roster.  One line per form:
#   id | base dex | display name | stone (or null) | types | abilities | stats | h | w | gen
# abilities "-"  -> [] + abilityStatus pending-owner (Champions does not cover it)
# h / w      "-"  -> inherited from the base species (no published Mega figure)
# stats are hp/atk/def/spa/spd/spe.  h = decimetres, w = hectograms.
# ---------------------------------------------------------------------------

FORMS = [
    # ---- Generation VI: X & Y (28) and Omega Ruby & Alpha Sapphire (20) -----
    "venusaur-mega | 3 | Mega Venusaur | venusaurite | grass,poison | thick-fat | 80/100/123/122/120/80 | 24 | 1555 | xy",
    "charizard-mega-x | 6 | Mega Charizard X | charizardite-x | fire,dragon | tough-claws | 78/130/111/130/85/100 | 17 | 1105 | xy",
    "charizard-mega-y | 6 | Mega Charizard Y | charizardite-y | fire,flying | drought | 78/104/78/159/115/100 | 17 | 1005 | xy",
    "blastoise-mega | 9 | Mega Blastoise | blastoisinite | water | mega-launcher | 79/103/120/135/115/78 | 16 | 1011 | xy",
    "beedrill-mega | 15 | Mega Beedrill | beedrillite | bug,poison | adaptability | 65/150/40/15/80/145 | 14 | 405 | oras",
    "pidgeot-mega | 18 | Mega Pidgeot | pidgeotite | normal,flying | no-guard | 83/80/80/135/80/121 | 22 | 505 | oras",
    "alakazam-mega | 65 | Mega Alakazam | alakazite | psychic | trace | 55/50/65/175/105/150 | 12 | 480 | xy",
    "slowbro-mega | 80 | Mega Slowbro | slowbronite | water,psychic | shell-armor | 95/75/180/130/80/30 | 20 | 1200 | oras",
    "gengar-mega | 94 | Mega Gengar | gengarite | ghost,poison | shadow-tag | 60/65/80/170/95/130 | 14 | 405 | xy",
    "kangaskhan-mega | 115 | Mega Kangaskhan | kangaskhanite | normal | parental-bond | 105/125/100/60/100/100 | 22 | 1000 | xy",
    "pinsir-mega | 127 | Mega Pinsir | pinsirite | bug,flying | aerilate | 65/155/120/65/90/105 | 17 | 590 | xy",
    "gyarados-mega | 130 | Mega Gyarados | gyaradosite | water,dark | mold-breaker | 95/155/109/70/130/81 | 65 | 3050 | xy",
    "aerodactyl-mega | 142 | Mega Aerodactyl | aerodactylite | rock,flying | tough-claws | 80/135/85/70/95/150 | 21 | 790 | xy",
    "mewtwo-mega-x | 150 | Mega Mewtwo X | mewtwonite-x | psychic,fighting | steadfast | 106/190/100/154/100/130 | 23 | 1270 | xy",
    "mewtwo-mega-y | 150 | Mega Mewtwo Y | mewtwonite-y | psychic | insomnia | 106/150/70/194/120/140 | 15 | 330 | xy",
    "ampharos-mega | 181 | Mega Ampharos | ampharosite | electric,dragon | mold-breaker | 90/95/105/165/110/45 | 14 | 615 | xy",
    "steelix-mega | 208 | Mega Steelix | steelixite | steel,ground | sand-force | 75/125/230/55/95/30 | 105 | 7400 | oras",
    "scizor-mega | 212 | Mega Scizor | scizorite | bug,steel | technician | 70/150/140/65/100/75 | 20 | 1250 | xy",
    "heracross-mega | 214 | Mega Heracross | heracronite | bug,fighting | skill-link | 80/185/115/40/105/75 | 17 | 625 | xy",
    "houndoom-mega | 229 | Mega Houndoom | houndoominite | dark,fire | solar-power | 75/90/90/140/90/115 | 19 | 495 | xy",
    "tyranitar-mega | 248 | Mega Tyranitar | tyranitarite | rock,dark | sand-stream | 100/164/150/95/120/71 | 25 | 2550 | xy",
    "sceptile-mega | 254 | Mega Sceptile | sceptilite | grass,dragon | lightning-rod | 70/110/75/145/85/145 | 19 | 552 | oras",
    "blaziken-mega | 257 | Mega Blaziken | blazikenite | fire,fighting | speed-boost | 80/160/80/130/80/100 | 19 | 520 | xy",
    "swampert-mega | 260 | Mega Swampert | swampertite | water,ground | swift-swim | 100/150/110/95/110/70 | 19 | 1020 | oras",
    "gardevoir-mega | 282 | Mega Gardevoir | gardevoirite | psychic,fairy | pixilate | 68/85/65/165/135/100 | 16 | 484 | xy",
    "sableye-mega | 302 | Mega Sableye | sablenite | dark,ghost | magic-bounce | 50/85/125/85/115/20 | 5 | 1610 | oras",
    "mawile-mega | 303 | Mega Mawile | mawilite | steel,fairy | huge-power | 50/105/125/55/95/50 | 10 | 235 | xy",
    "aggron-mega | 306 | Mega Aggron | aggronite | steel | filter | 70/140/230/60/80/50 | 22 | 3950 | xy",
    "medicham-mega | 308 | Mega Medicham | medichamite | fighting,psychic | pure-power | 60/100/85/80/85/100 | 13 | 315 | xy",
    "manectric-mega | 310 | Mega Manectric | manectite | electric | intimidate | 70/75/80/135/80/135 | 18 | 440 | xy",
    "sharpedo-mega | 319 | Mega Sharpedo | sharpedonite | water,dark | strong-jaw | 70/140/70/110/65/105 | 25 | 1303 | oras",
    "camerupt-mega | 323 | Mega Camerupt | cameruptite | fire,ground | sheer-force | 70/120/100/145/105/20 | 25 | 3205 | oras",
    "altaria-mega | 334 | Mega Altaria | altarianite | dragon,fairy | pixilate | 75/110/110/110/105/80 | 15 | 206 | oras",
    "banette-mega | 354 | Mega Banette | banettite | ghost | prankster | 64/165/75/93/83/75 | 12 | 130 | xy",
    "absol-mega | 359 | Mega Absol | absolite | dark | magic-bounce | 65/150/60/115/60/115 | 12 | 490 | xy",
    "glalie-mega | 362 | Mega Glalie | glalitite | ice | refrigerate | 80/120/80/120/80/100 | 21 | 3502 | oras",
    "salamence-mega | 373 | Mega Salamence | salamencite | dragon,flying | aerilate | 95/145/130/120/90/120 | 18 | 1126 | oras",
    "metagross-mega | 376 | Mega Metagross | metagrossite | steel,psychic | tough-claws | 80/145/150/105/110/110 | 25 | 9429 | oras",
    "latias-mega | 380 | Mega Latias | latiasite | dragon,psychic | levitate | 80/100/120/140/150/110 | 18 | 520 | oras",
    "latios-mega | 381 | Mega Latios | latiosite | dragon,psychic | levitate | 80/130/100/160/120/110 | 23 | 700 | oras",
    "rayquaza-mega | 384 | Mega Rayquaza | null | dragon,flying | delta-stream | 105/180/100/180/100/115 | 108 | 3920 | oras",
    "lopunny-mega | 428 | Mega Lopunny | lopunnite | normal,fighting | scrappy | 65/136/94/54/96/135 | 13 | 283 | oras",
    "garchomp-mega | 445 | Mega Garchomp | garchompite | dragon,ground | sand-force | 108/170/115/120/95/92 | 19 | 950 | xy",
    "lucario-mega | 448 | Mega Lucario | lucarionite | fighting,steel | adaptability | 70/145/88/140/70/112 | 13 | 575 | xy",
    "abomasnow-mega | 460 | Mega Abomasnow | abomasite | grass,ice | snow-warning | 90/132/105/132/105/30 | 27 | 1850 | xy",
    "gallade-mega | 475 | Mega Gallade | galladite | psychic,fighting | inner-focus | 68/165/95/65/115/110 | 16 | 564 | oras",
    "audino-mega | 531 | Mega Audino | audinite | normal,fairy | healer | 103/60/126/80/126/50 | 15 | 320 | oras",
    "diancie-mega | 719 | Mega Diancie | diancite | rock,fairy | magic-bounce | 50/160/110/160/110/110 | 11 | 278 | oras",

    # ---- Legends Z-A (49).  Abilities from Pokemon Champions. ---------------
    "raichu-mega-x | 26 | Mega Raichu X | raichunite-x | electric | electric-surge | 60/135/95/90/95/110 | - | - | za",
    "raichu-mega-y | 26 | Mega Raichu Y | raichunite-y | electric | no-guard | 60/100/55/160/80/130 | - | - | za",
    "clefable-mega | 36 | Mega Clefable | clefablite | fairy,flying | magic-bounce | 95/80/93/135/110/70 | - | - | za",
    "victreebel-mega | 71 | Mega Victreebel | victreebelite | grass,poison | innards-out | 80/125/85/135/95/70 | - | - | za",
    "starmie-mega | 121 | Mega Starmie | starminite | water,psychic | huge-power | 60/100/105/130/105/120 | - | - | za",
    "dragonite-mega | 149 | Mega Dragonite | dragoninite | dragon,flying | multiscale | 91/124/115/145/125/100 | - | - | za",
    "meganium-mega | 154 | Mega Meganium | meganiumite | grass,fairy | mega-sol | 80/92/115/143/115/80 | - | - | za",
    "feraligatr-mega | 160 | Mega Feraligatr | feraligite | water,dragon | dragonize | 85/160/125/89/93/78 | - | - | za",
    "skarmory-mega | 227 | Mega Skarmory | skarmorite | steel,flying | stalwart | 65/140/110/40/100/110 | - | - | za",
    "chimecho-mega | 358 | Mega Chimecho | chimechite | psychic,steel | levitate | 75/50/110/135/120/65 | - | - | za",
    "absol-mega-z | 359 | Mega Absol Z | absolite-z | dark,ghost | sharpness | 65/154/60/75/60/151 | - | - | za",
    "staraptor-mega | 398 | Mega Staraptor | staraptite | fighting,flying | contrary | 85/140/100/60/90/110 | - | - | za",
    "garchomp-mega-z | 445 | Mega Garchomp Z | garchompite-z | dragon | levitate | 108/130/85/141/85/151 | - | - | za",
    "lucario-mega-z | 448 | Mega Lucario Z | lucarionite-z | fighting,steel | aura-guard | 70/100/70/164/70/151 | - | - | za",
    "froslass-mega | 478 | Mega Froslass | froslassite | ice,ghost | snow-warning | 70/80/70/140/100/120 | - | - | za",
    "heatran-mega | 485 | Mega Heatran | heatranite | fire,steel | - | 91/120/106/175/141/67 | - | - | za",
    "darkrai-mega | 491 | Mega Darkrai | darkranite | dark | - | 70/120/130/165/130/85 | - | - | za",
    "emboar-mega | 500 | Mega Emboar | emboarite | fire,fighting | mold-breaker | 110/148/75/110/110/75 | - | - | za",
    "excadrill-mega | 530 | Mega Excadrill | excadrite | ground,steel | piercing-drill | 110/165/100/65/65/103 | - | - | za",
    "scolipede-mega | 545 | Mega Scolipede | scolipite | bug,poison | shell-armor | 60/140/149/75/99/62 | - | - | za",
    "scrafty-mega | 560 | Mega Scrafty | scraftinite | dark,fighting | intimidate | 65/130/135/55/135/68 | - | - | za",
    "eelektross-mega | 604 | Mega Eelektross | eelektrossite | electric | eelevate | 85/145/80/135/90/80 | - | - | za",
    "chandelure-mega | 609 | Mega Chandelure | chandelurite | ghost,fire | infiltrator | 60/75/110/175/110/90 | - | - | za",
    "golurk-mega | 623 | Mega Golurk | golurkite | ground,ghost | unseen-fist | 89/159/105/70/105/55 | - | - | za",
    "chesnaught-mega | 652 | Mega Chesnaught | chesnaughtite | grass,fighting | bulletproof | 88/137/172/74/115/44 | - | - | za",
    "delphox-mega | 655 | Mega Delphox | delphoxite | fire,psychic | levitate | 75/69/72/159/125/134 | - | - | za",
    "greninja-mega | 658 | Mega Greninja | greninjite | water,dark | protean | 72/125/77/133/81/142 | - | - | za",
    "pyroar-mega | 668 | Mega Pyroar | pyroarite | fire,normal | fire-mane | 86/88/92/129/86/126 | - | - | za",
    "floette-mega | 670 | Mega Floette | floettite | fairy | fairy-aura | 74/85/87/155/148/102 | - | - | za",
    "meowstic-mega-male | 678 | Mega Meowstic (Male) | meowsticite | psychic | trace | 74/48/76/143/101/124 | - | - | za",
    "meowstic-mega-female | 678 | Mega Meowstic (Female) | meowsticite | psychic | trace | 74/48/76/143/101/124 | - | - | za",
    "malamar-mega | 687 | Mega Malamar | malamarite | dark,psychic | contrary | 86/102/88/98/120/88 | - | - | za",
    "barbaracle-mega | 689 | Mega Barbaracle | barbaracite | rock,fighting | tough-claws | 72/140/130/64/106/88 | - | - | za",
    "dragalge-mega | 691 | Mega Dragalge | dragalgite | poison,dragon | regenerator | 65/85/105/132/163/44 | - | - | za",
    "hawlucha-mega | 701 | Mega Hawlucha | hawluchanite | fighting,flying | no-guard | 78/137/100/74/93/118 | - | - | za",
    "zygarde-mega | 718 | Mega Zygarde | zygardite | dragon,ground | - | 216/70/91/216/85/100 | - | - | za",
    "crabominable-mega | 740 | Mega Crabominable | crabominite | fighting,ice | iron-fist | 97/157/122/62/107/33 | - | - | za",
    "golisopod-mega | 768 | Mega Golisopod | golisopite | bug,steel | tough-claws | 75/150/175/70/120/40 | - | - | za",
    "drampa-mega | 780 | Mega Drampa | drampanite | normal,dragon | berserk | 78/85/110/160/116/36 | - | - | za",
    "magearna-mega | 801 | Mega Magearna | magearnite | steel,fairy | - | 80/125/115/170/115/95 | - | - | za",
    "magearna-mega-original | 801 | Mega Magearna (Original Color) | magearnite | steel,fairy | - | 80/125/115/170/115/95 | - | - | za",
    "zeraora-mega | 807 | Mega Zeraora | zeraorite | electric | - | 88/157/75/147/80/153 | - | - | za",
    "falinks-mega | 870 | Mega Falinks | falinksite | fighting | defiant | 65/135/135/70/65/100 | - | - | za",
    "scovillain-mega | 952 | Mega Scovillain | scovillainite | grass,fire | spicy-spray | 65/138/85/138/85/75 | - | - | za",
    "glimmora-mega | 970 | Mega Glimmora | glimmoranite | rock,poison | adaptability | 83/90/105/150/96/101 | - | - | za",
    "tatsugiri-mega-curly | 978 | Mega Tatsugiri (Curly) | tatsugirinite | dragon,water | - | 68/65/90/135/125/92 | - | - | za",
    "tatsugiri-mega-droopy | 978 | Mega Tatsugiri (Droopy) | tatsugirinite | dragon,water | - | 68/65/90/135/125/92 | - | - | za",
    "tatsugiri-mega-stretchy | 978 | Mega Tatsugiri (Stretchy) | tatsugirinite | dragon,water | - | 68/65/90/135/125/92 | - | - | za",
    "baxcalibur-mega | 998 | Mega Baxcalibur | baxcalibrite | dragon,ice | thermal-exchange | 115/175/117/105/101/87 | - | - | za",
]

# Forms that need something other than "hold the matching stone".
#   requiresMove: Mega Rayquaza holds no stone and needs Dragon Ascent (11.5).
#   requiresForm: the mon must already be in this cosmetic/alternate form.  This is
#   what makes a SHARED stone unambiguous: meowsticite, magearnite and
#   tatsugirinite each serve several forms of one species, and the runtime picks
#   the row whose requiresForm matches the mon.
REQUIRES_MOVE = {
    "rayquaza-mega": "dragon-ascent",
}
REQUIRES_FORM = {
    "floette-mega": "floette-eternal",          # Eternal Flower Floette only
    "meowstic-mega-male": "meowstic-male",
    "meowstic-mega-female": "meowstic-female",
    "zygarde-mega": "zygarde-complete",         # from Complete Forme
    "magearna-mega": "magearna",
    "magearna-mega-original": "magearna-original",
    "tatsugiri-mega-curly": "tatsugiri-curly",
    "tatsugiri-mega-droopy": "tatsugiri-droopy",
    "tatsugiri-mega-stretchy": "tatsugiri-stretchy",
}

# Abilities that exist only in Pokemon Champions and had to be authored by hand in
# data/abilities.json.  Three have public effect text; the other four are tier 3
# (row exists, hook none, inert) rather than a guessed mechanic.
CHAMPIONS_EXCLUSIVE = {
    "mega-sol": "Meganium - no public effect text; tier 3, data only",
    "dragonize": "Feraligatr - no public effect text; tier 3, data only",
    "aura-guard": "Lucario Z - halves damage from contact moves",
    "piercing-drill": "Excadrill - pierces Protect for 1/4 damage",
    "eelevate": "Eelektross - no public effect text; tier 3, data only",
    "fire-mane": "Pyroar - no public effect text; tier 3, data only",
    "spicy-spray": "Scovillain - burns an attacker that lands a damaging move",
}

# DATA_CONTRACT 11.5 / owner ruling: Primal Reversion is not in this game.
FORBIDDEN_FORM_IDS = ("primal-groudon", "primal-kyogre", "groudon-primal", "kyogre-primal")
FORBIDDEN_ITEM_IDS = ("red-orb", "blue-orb")

# DATA_CONTRACT 11.4: excluded gimmicks, asserted absent from the generated data.
EXCLUDED_TOKENS = ("dynamax", "gigantamax", "gmax", "zmove", "z-move", "tera", "terastal")

STAT_KEYS = ("hp", "atk", "def", "spa", "spd", "spe")


# ---------------------------------------------------------------------------
# Roster parsing
# ---------------------------------------------------------------------------

def parse_roster():
    """Turn the FORMS text table into dicts.  Raises on a malformed line."""
    out = []
    for line in FORMS:
        parts = [p.strip() for p in line.split("|")]
        if len(parts) != 10:
            raise ValueError("roster line has %d fields, want 10: %r" % (len(parts), line))
        fid, base, name, stone, types, abils, stats, height, weight, gen = parts
        nums = stats.split("/")
        if len(nums) != 6:
            raise ValueError("bad stat line for %s: %r" % (fid, stats))
        if gen not in ("xy", "oras", "za"):
            raise ValueError("bad introducedIn for %s: %r" % (fid, gen))
        abilities = [] if abils == "-" else [a.strip() for a in abils.split(",") if a.strip()]
        out.append({
            "id": fid,
            "base": int(base),
            "name": name,
            "stone": None if stone == "null" else stone,
            "types": [t.strip() for t in types.split(",")],
            "abilities": abilities,
            "stats": dict(zip(STAT_KEYS, [int(n) for n in nums])),
            "height": None if height == "-" else int(height),
            "weight": None if weight == "-" else int(weight),
            "introducedIn": gen,
        })
    return out


def ability_status(form):
    """DATA_CONTRACT 11.5 provenance tag."""
    if not form["abilities"]:
        return "pending-owner"
    if form["introducedIn"] == "za":
        return "champions"
    return "canon"


def alias_key(form_id):
    """Order-insensitive key so 'tatsugiri-curly-mega' == 'tatsugiri-mega-curly'."""
    return tuple(sorted(form_id.split("-")))


# ---------------------------------------------------------------------------
# Build
# ---------------------------------------------------------------------------

def load_species(repo):
    path = os.path.join(repo, "data", "species.json")
    with open(path) as fh:
        sp = json.load(fh)
    return dict((int(s["id"]), s) for s in sp)


def load_abilities(repo):
    path = os.path.join(repo, "data", "abilities.json")
    if not os.path.isfile(path):
        return {}
    with open(path) as fh:
        ab = json.load(fh)
    return dict((a["slug"], a) for a in ab)


def apply_owner_overrides(forms, path, log):
    """DATA_CONTRACT 11.5 step 2.  Off by default; see the module docstring."""
    with open(path) as fh:
        doc = json.load(fh)
    by_alias = dict((alias_key(f["id"]), f) for f in forms)
    applied = 0
    for row in doc.get("overrides", []):
        form = by_alias.get(alias_key(row["form"]))
        if form is None:
            log.append("  ! override for unknown form %s - IGNORED" % row["form"])
            continue
        if form["abilities"]:
            log.append("  ! override for %s which already has %s (Champions wins) - IGNORED"
                       % (form["id"], form["abilities"]))
            continue
        form["abilities"] = list(row["abilities"])
        form["abilityStatus"] = row.get("abilityStatus", "owner-decided")
        applied += 1
        log.append("  + %-24s %-14s (%s)" % (form["id"], ",".join(form["abilities"]),
                                             form["abilityStatus"]))
    log.append("  applied %d owner override(s) from %s" % (applied, os.path.basename(path)))
    return applied


def build_megas(forms, species):
    out_forms = []
    for f in forms:
        base = species[f["base"]]
        height = f["height"]
        weight = f["weight"]
        inherited = height is None or weight is None
        if height is None:
            height = int(base["height"])
        if weight is None:
            weight = int(base["weight"])
        entry = {
            "id": f["id"],
            "base": f["base"],
            "name": f["name"],
            "stone": f["stone"],
            "requiresMove": REQUIRES_MOVE.get(f["id"]),
            "requiresForm": REQUIRES_FORM.get(f["id"]),
            "types": f["types"],
            "stats": dict((k, f["stats"][k]) for k in STAT_KEYS),
            "bst": sum(f["stats"].values()),
            "abilities": f["abilities"],
            "abilityStatus": f.get("abilityStatus") or ability_status(f),
            "height": height,
            "weight": weight,
            # No published Mega figure for the Z-A forms, so the base species'
            # numbers stand in.  Flagged rather than invented.
            "metricsSource": "base-species" if inherited else "published",
            "introducedIn": f["introducedIn"],
            "sprite": {
                "front": "mega/%s.png" % f["id"],
                "back": "mega/back/%s.png" % f["id"],
                "icon": "mega/icon/%s.png" % f["id"],
            },
        }
        out_forms.append(entry)
    return {
        "keyItem": KEY_ITEM,
        "rule": BATTLE_RULE,
        "revertsAfterBattle": True,
        "forms": out_forms,
    }


def stone_display_name(stone_id):
    words = []
    for part in stone_id.split("-"):
        words.append(part.upper() if part in ("x", "y", "z") else part.capitalize())
    return " ".join(words)


def build_items(megas, species, repo):
    """Mega Stones + the Key Stone, merged into any existing data/items.json.

    Shape (there is no items section in DATA_CONTRACT yet, so this is the
    proposal): a flat array of item objects, matching species/moves/abilities.
    An existing file's shape and all of its non-Mega rows are preserved.
    """
    by_stone = {}
    order = []
    for form in megas["forms"]:
        stone = form["stone"]
        if stone is None:
            continue
        if stone not in by_stone:
            by_stone[stone] = []
            order.append(stone)
        by_stone[stone].append(form)

    items = [{
        "id": KEY_ITEM,
        "name": "Key Stone",
        "category": "key-stone",
        "pocket": "key-items",
        "price": 0,
        "sellable": False,
        "holdable": False,
        "consumable": False,
        "description": ("A stone that holds a hidden power. It responds to a Mega Stone, "
                        "letting one Pokemon per side change form once per battle."),
        "sprite": "items/key-stone.png",
    }]

    for stone in order:
        group = by_stone[stone]
        base_names = []
        for form in group:
            nm = species[form["base"]]["name"]
            if nm not in base_names:
                base_names.append(nm)
        if len(group) == 1:
            desc = ("A stone that lets %s change into %s in battle, if its Trainer "
                    "carries a Key Stone." % (base_names[0], group[0]["name"]))
        else:
            desc = ("A stone that lets %s change form in battle, if its Trainer carries "
                    "a Key Stone. Which form it takes follows the Pokemon: %s."
                    % (base_names[0], ", ".join(f["name"] for f in group)))
        items.append({
            "id": stone,
            "name": stone_display_name(stone),
            "category": "mega-stone",
            "pocket": "items",
            "price": 0,
            "sellable": False,
            "holdable": True,
            "consumable": False,
            "megaForms": [f["id"] for f in group],
            "baseSpecies": sorted(set(f["base"] for f in group)),
            "introducedIn": group[0]["introducedIn"],
            "description": desc,
            "sprite": "items/%s.png" % stone,
        })

    ours = dict((it["id"], it) for it in items)
    path = os.path.join(repo, "data", "items.json")
    merged, container, note = items, None, "created"
    if os.path.isfile(path):
        with open(path) as fh:
            existing = json.load(fh)
        if isinstance(existing, dict):
            container = existing
            rows = existing.get("items", [])
        else:
            rows = existing
        kept = [r for r in rows
                if r.get("id") not in ours
                and r.get("category") not in ("mega-stone", "key-stone")]
        dropped = len(rows) - len(kept)
        merged = kept + items
        note = "merged (kept %d existing row(s), replaced %d Mega row(s))" % (len(kept), dropped)
    payload = merged
    if container is not None:
        container["items"] = merged
        payload = container
    return payload, merged, note


# ---------------------------------------------------------------------------
# Verification
# ---------------------------------------------------------------------------

def check(label, ok, detail=""):
    print("  [%s] %s%s" % ("PASS" if ok else "FAIL", label, ("  -- %s" % detail) if detail else ""))
    return bool(ok)


def verify(megas, item_rows, species, abilities):
    forms = megas["forms"]
    ok = True
    print("\n=== 1. base dex ids resolve against data/species.json ===")
    bad = [f["id"] for f in forms if f["base"] not in species]
    ok &= check("all %d forms resolve a base species" % len(forms), not bad, str(bad))
    mismatch = [(f["id"], species[f["base"]]["name"]) for f in forms
                if f["base"] in species
                and species[f["base"]]["name"].lower().replace(" ", "-")
                not in f["id"]]
    ok &= check("form id carries the base species name", not mismatch, str(mismatch[:4]))

    print("\n=== 2. stone ids ===")
    ids = [f["id"] for f in forms]
    ok &= check("form ids unique (%d)" % len(ids), len(set(ids)) == len(ids))
    stones = [f["stone"] for f in forms if f["stone"] is not None]
    shared = {}
    for f in forms:
        if f["stone"]:
            shared.setdefault(f["stone"], []).append(f)
    dupes = dict((s, g) for s, g in shared.items() if len(g) > 1)
    ok &= check("%d distinct stones for %d stone-using forms" % (len(shared), len(stones)), True)
    # A shared stone is legal ONLY for cosmetic variants of one species: same base,
    # same types, same stats, and each row disambiguated by requiresForm.
    bad_share = []
    for stone, group in sorted(dupes.items()):
        bases = set(f["base"] for f in group)
        lines = set(json.dumps([f["types"], f["stats"]], sort_keys=True) for f in group)
        rf = [f["requiresForm"] for f in group]
        if len(bases) != 1 or len(lines) != 1 or None in rf or len(set(rf)) != len(rf):
            bad_share.append(stone)
        print("        shared: %-14s -> %s" % (stone, ", ".join(f["id"] for f in group)))
    ok &= check("every shared stone is one species' cosmetic variants, split by requiresForm",
                not bad_share, str(bad_share))
    ok &= check("no stone maps to two different species",
                all(len(set(f["base"] for f in g)) == 1 for g in shared.values()))
    no_stone = [f["id"] for f in forms if f["stone"] is None]
    ok &= check("exactly one stoneless form, and it is Mega Rayquaza",
                no_stone == ["rayquaza-mega"], str(no_stone))
    ok &= check("Mega Rayquaza requires the move dragon-ascent",
                [f for f in forms if f["id"] == "rayquaza-mega"][0]["requiresMove"]
                == "dragon-ascent")
    item_ids = set(r["id"] for r in item_rows)
    missing_items = sorted(set(stones) - item_ids)
    ok &= check("every stone exists in data/items.json", not missing_items, str(missing_items))
    ok &= check("the Key Stone exists in data/items.json", KEY_ITEM in item_ids)

    print("\n=== 3. abilities ===")
    pending = [f["id"] for f in forms if not f["abilities"]]
    named = [f for f in forms if f["abilities"]]
    empty_name = [f["id"] for f in named if not all(a and a.strip() for a in f["abilities"])]
    ok &= check("every declared ability name is non-empty", not empty_name, str(empty_name))
    ok &= check("%d form(s) carry abilities; %d pending-owner" % (len(named), len(pending)), True)
    ok &= check("every ability-less form is tagged abilityStatus pending-owner",
                all(f["abilityStatus"] == "pending-owner"
                    for f in forms if not f["abilities"]))
    ok &= check("no form has abilities AND pending-owner status",
                not [f["id"] for f in forms
                     if f["abilities"] and f["abilityStatus"] == "pending-owner"])
    print("        pending-owner (%d): %s" % (len(pending), ", ".join(pending)))
    if abilities:
        unknown = sorted(set(a for f in forms for a in f["abilities"] if a not in abilities))
        ok &= check("every ability slug exists in data/abilities.json", not unknown, str(unknown))
        inert = sorted(set(a for f in forms for a in f["abilities"]
                           if a in abilities and abilities[a].get("tier") == 3))
        print("        tier-3 (row exists, hook none, inert until written): %s" % ", ".join(inert))
        for slug in sorted(CHAMPIONS_EXCLUSIVE):
            row = abilities.get(slug)
            print("        Champions-exclusive %-16s tier %s  %s"
                  % (slug, row.get("tier") if row else "MISSING", CHAMPIONS_EXCLUSIVE[slug]))
    two = [f["id"] for f in forms if len(f["abilities"]) > 1]
    print("        forms with two abilities: %s" % (", ".join(two) if two else "none"))

    print("\n=== 4. stat plausibility ===")
    below = []
    for f in forms:
        base_bst = sum(species[f["base"]]["stats"].values())
        if f["bst"] < base_bst:
            below.append((f["id"], f["bst"], base_bst))
    ok &= check("no Mega BST below its base form's BST", not below, str(below))
    ok &= check("every BST in 300..900", all(300 <= f["bst"] <= 900 for f in forms),
                str([(f["id"], f["bst"]) for f in forms if not 300 <= f["bst"] <= 900]))
    ok &= check("every individual stat in 1..255",
                all(1 <= v <= 255 for f in forms for v in f["stats"].values()))
    starmie = [f for f in forms if f["id"] == "starmie-mega"][0]
    ok &= check("Mega Starmie ships Attack 100 with Huge Power (not Serebii Z-A's 140)",
                starmie["stats"]["atk"] == 100 and "huge-power" in starmie["abilities"])
    ok &= check("every form has 1 or 2 types, all lowercase",
                all(1 <= len(f["types"]) <= 2 and all(t == t.lower() for t in f["types"])
                    for f in forms))

    print("\n=== 5. two-Mega species ===")
    for dex, who in ((6, "Charizard"), (150, "Mewtwo")):
        got = [f["id"] for f in forms if f["base"] == dex]
        ok &= check("%s has exactly 2 forms" % who, len(got) == 2, ", ".join(got))
    counts = {}
    for f in forms:
        counts[f["base"]] = counts.get(f["base"], 0) + 1
    multi = sorted((species[b]["name"], n) for b, n in counts.items() if n > 1)
    print("        every multi-form species: %s"
          % ", ".join("%s x%d" % (n, c) for n, c in multi))

    print("\n=== 6. Primal Reversion is OUT (11.5) ===")
    blob = (json.dumps(megas) + json.dumps(item_rows)).lower()
    hits = [t for t in FORBIDDEN_FORM_IDS + FORBIDDEN_ITEM_IDS if t in blob]
    ok &= check("no primal form and no Red/Blue Orb item anywhere", not hits, str(hits))
    ok &= check("no form based on Groudon (383) or Kyogre (382)",
                not [f["id"] for f in forms if f["base"] in (382, 383)])

    print("\n=== 7. excluded gimmicks absent (11.4) ===")
    for tok in EXCLUDED_TOKENS:
        where = []
        if tok in blob:
            for m in re.finditer(re.escape(tok), blob):
                where.append(blob[max(0, m.start() - 30):m.start() + 30])
        ok &= check('token "%s" absent from the generated data' % tok, not where,
                    " | ".join(where[:2]))
    return ok


def git_tracked(repo, relpath):
    def run(args):
        p = subprocess.Popen(["git"] + args, cwd=repo,
                             stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        out, _ = p.communicate()
        return p.returncode, out.decode("utf-8", "replace").strip()
    rc, _ = run(["ls-files", "--error-unmatch", relpath])
    if rc == 0:
        return True, "tracked"
    rc2, why = run(["check-ignore", "-v", relpath])
    if rc2 == 0:
        return False, "IGNORED by %s" % why
    return False, "not tracked yet - run: git add %s" % relpath


def main():
    ap = argparse.ArgumentParser(description="Build data/megas.json and the Mega Stone items.")
    ap.add_argument("--out", default=REPO, help="repo root to write data/ into")
    ap.add_argument("--apply-owner-overrides", action="store_true",
                    help="fold data/mega_ability_overrides.json into the pending-owner forms")
    ap.add_argument("--overrides",
                    default=os.path.join(REPO, "data", "mega_ability_overrides.json"))
    args = ap.parse_args()

    forms = parse_roster()
    species = load_species(REPO)
    abilities = load_abilities(REPO)

    print("=== roster ===")
    by_gen = {}
    for f in forms:
        by_gen[f["introducedIn"]] = by_gen.get(f["introducedIn"], 0) + 1
    print("  %d forms: %s" % (len(forms), ", ".join("%s=%d" % (g, by_gen.get(g, 0))
                                                    for g in ("xy", "oras", "za"))))

    print("\n=== owner ability overrides (DATA_CONTRACT 11.5 step 2) ===")
    if args.apply_owner_overrides:
        log = []
        apply_owner_overrides(forms, args.overrides, log)
        print("\n".join(log))
    elif os.path.isfile(args.overrides):
        with open(args.overrides) as fh:
            n = len(json.load(fh).get("overrides", []))
        print("  %s exists (%d row(s)) and was NOT applied." % (args.overrides, n))
        print("  The nine Champions-uncovered forms ship abilities: []"
              " + abilityStatus pending-owner.")
        print("  Re-run with --apply-owner-overrides to fold it in.")
    else:
        print("  none on disk; nothing to apply.")

    megas = build_megas(forms, species)
    items_payload, item_rows, items_note = build_items(megas, species, args.out)

    data_dir = os.path.join(args.out, "data")
    if not os.path.isdir(data_dir):
        os.makedirs(data_dir)
    megas_path = os.path.join(data_dir, "megas.json")
    items_path = os.path.join(data_dir, "items.json")
    with open(megas_path, "w") as fh:
        json.dump(megas, fh, indent=2, sort_keys=True)
        fh.write("\n")
    with open(items_path, "w") as fh:
        json.dump(items_payload, fh, indent=2, sort_keys=True)
        fh.write("\n")
    print("\n=== wrote ===")
    print("  data/megas.json  %d forms, %d bytes"
          % (len(megas["forms"]), os.path.getsize(megas_path)))
    print("  data/items.json  %d items, %d bytes  (%s)"
          % (len(item_rows), os.path.getsize(items_path), items_note))

    ok = verify(megas, item_rows, species, abilities)

    print("\n=== 8. git tracking (both files are design data and ARE committed) ===")
    for rel in ("data/megas.json", "data/items.json"):
        tracked, why = git_tracked(args.out, rel)
        ok &= check("%s: %s" % (rel, why), tracked or "not tracked yet" in why)

    print("\n%s" % ("ALL CHECKS PASSED" if ok else "SOME CHECKS FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
