# Project Platinum

A **Pokémon Platinum remake** built in Godot 4.7, with Gen 5 visuals, hard level caps at
boss fights, no HMs, Pokémon from all nine generations, and Mega Evolution.

> **Status: in development — not yet playable.** The engine systems, data and assets are
> built and tested; scene integration and the Sinnoh maps are not finished. See
> [Current status](#current-status) for an honest breakdown.

---

## The four changes

### Gen 5 visuals

Graphics are extracted from DS ROMs you supply yourself. Pokémon sprites come from
**White 2** (front, back and party icon for all 1025 species), and the tileset is composed
from three games, each used for what it does best:

| Layer | Source | Why |
|---|---|---|
| Grass, sand, snow, dungeon kit | **Platinum** | Sinnoh's own identity — and the only library with 121 sand + 80 snow textures |
| Cliff edge strips, trees, doors, fences | **White 2** | The only game shipping authored transition pieces and stamp-ready 32×64 trees |
| Roads and shoulders | **HeartGold** | The best road set of the three, with proper `_r`/`_sub` edge variants |

White 2 art is measurably ~12% darker than Platinum's, so it gets a fixed **×1.08 value /
×1.04 saturation** lift at import to make the three sit together.

### Hard level caps

A Pokémon **at or above the current cap gains zero EXP**. The cap rises when you beat the
boss it's set for, so you can't grind past a wall — you have to actually beat it.

| Checkpoint | Roark | Gardenia | Fantina | Maylene | Wake | Byron | Candice | Volkner | Elite Four | Cynthia |
|---|---|---|---|---|---|---|---|---|---|---|
| **Cap** | 18 | 27 | 36 | 45 | 54 | 66 | 78 | 90 | 96–99 | **100** |

The curve is built so natural progression brings your team to **level 100 for Cynthia**,
whose entire six-Pokémon team is level 100. Because level 100 needs 1,000,000 EXP against
vanilla's ~238,000 at level 62, the game applies a **×2.5 EXP multiplier** — without it you
would stall below every cap.

Every boss fight has **six Pokémon**, and every boss's ace is a Sinnoh (Gen 4) species.

### No HMs

HM moves don't exist. Field traversal is **badge-gated and automatic** — walk into an
obstacle and, if you have the badge, your character just does it. No menu, no move slot, no
party check.

| Badge | Verb | Behaviour |
|---|---|---|
| Coal | `smash` | Walk into a cracked rock; it shatters and you step through |
| Forest | `cut` | Walk into a cuttable tree; it falls away |
| Cobble | `fly` | Adds a **MAP** menu entry — any Pokémon Center you've visited |
| Fen | `surf` | Walk into the shoreline; you mount and slide onto the water |
| Mine | `strength` | Walk into a boulder; it slides one tile |
| Icicle | `climb` | Walk into a chevron rock face; you ascend |
| Beacon | `waterfall` | Swim into a waterfall base; you ascend |

The badge→verb mapping preserves Platinum's original badge→HM bindings exactly, which is
why route order can't break: every obstacle opens precisely when a vanilla player could
have passed it, never earlier.

**Fog is removed entirely** — no fog weather, no accuracy penalty, no Defog. It never gated
progress in vanilla, so the Relic badge grants the cap raise and story flag only.

### Gens 1–9 and Mega Evolution

All **1025 species** exist with full data. Sinnoh's encounter tables are hand-curated: each
route keeps its Platinum natives and gains cross-gen additions chosen to fit the route's
tone and level band, so Route 201 still feels like Route 201.

**97 Mega forms**, including the Legends Z-A additions. Mega Evolution is the **only**
gimmick — there is no Dynamax, no Z-Moves, no Terastallization.

- The **Mega Ring** is given by Dawn/Lucas in Hearthome City, after you beat Fantina.
- **Gym leaders Mega Evolve from gym 3 onward** — Fantina is the first, fought just before
  you receive the Ring.
- Each gym leader awards a Mega Stone: Roark *Aerodactylite*, Gardenia *Victreebelite*,
  Fantina *Gengarite*, Maylene *Lucarionite*, Wake *Gyaradosite*, Byron *Steelixite*,
  Candice *Froslassite*, Volkner *Raichunite Y* and *Raichunite X*.
- **Primal Reversion is not included.** **Mega Rayquaza is**, and is the only Mega needing
  no stone — it Mega Evolves by knowing Dragon Ascent.

---

## Setup

### You need

- **Godot 4.7.2** — [godotengine.org](https://godotengine.org/download)
- **Python 3.8+** with `Pillow` and `numpy`
- **Your own legally-obtained DS ROMs.** None are included and none ever will be.

### ROMs

Place your own dumps here:

```
References/Roms/
  Platinum/     Pokémon Platinum (US)      — maps, encounters, trainers, text, base tiles
  White 2/      Pokémon White 2 (US)       — Pokémon sprites, props, cliff and tree art
  Heartgold/    Pokémon HeartGold (US)     — road tiles
  Black/        Pokémon Black (US)         — optional; White 2 is a superset
```

This directory is gitignored. **No ROM content is committed to this repository**, and the
pipelines regenerate every extracted asset on demand.

### Build

```bash
# Data — committed, no ROM needed
python tools/build_species.py     # 1025 species, moves, learnsets, abilities, type chart
python tools/build_megas.py       # 97 Mega forms

# Assets and game data — needs your ROMs
python tools/build_gamedata.py    # encounters, trainers, bosses, text
python tools/build_sprites.py     # front/back/icon for all 1025
python tools/build_tilesets.py    # tileset atlas + Godot TileSet resource
```

> If `PIL` fails with `DLL load failed` on Windows, run `source tools/_work/gen5/env.sh`
> first — an anaconda PATH quirk, not a code problem.

### Run

```bash
tools/run_tests.sh                # headless test suite; exits nonzero on failure
```

Open the project folder in Godot to play — once integration lands, see below.

---

## Current status

**Working and verified**

- ROM extraction library (`tools/rom/`) — NDS filesystem, NARC, LZ10/LZ11, Nitro graphics, NSBTX
- 1025 species with stats, types, abilities, learnsets and evolutions; 919 moves; 314 abilities; type chart
- 1025 Pokémon sprites (front/back/icon) extracted and visually verified across all nine generations
- Tileset atlas composed from all three ROMs, with tonal correction
- 97 Mega forms with abilities fully resolved
- Level cap table and EXP economy, validated computationally
- 31 boss rosters, six Pokémon each
- Battle engine, overworld systems, autoloads and save system, with a headless test suite

**Not finished**

- **Sinnoh beyond the vertical slice** — the game boots and plays Twinleaf → Oreburgh; the rest of the region is not authored
- **Sinnoh maps** — `data/maps/` is empty; the Twinleaf → Oreburgh slice is not authored
- **UI** — menus, bag, party and Pokédex screens
- Story events and scripted cutscenes (Platinum's script bytecode is not decoded)

---

## Documentation

| | |
|---|---|
| [`CLAUDE.md`](CLAUDE.md) | Working guide — rules, commands, locked decisions, known traps |
| [`docs/DATA_CONTRACT.md`](docs/DATA_CONTRACT.md) | Authoritative schemas between pipelines and runtime |
| [`docs/CUSTOM_BATTLE.md`](docs/CUSTOM_BATTLE.md) | Custom Battle mode — controls, legality rules, preset format |
| [`docs/research/`](docs/research/) | Byte-verified findings on ROM formats, Platinum data, Gen 5 assets, the level curve and Megas |

---

## Legal

This is a **non-commercial fan project**. It contains **no copyrighted Nintendo assets** —
no ROMs, sprites, tilesets, music or in-game text. Every asset is extracted at build time
from ROM files you supply yourself, and stays on your machine.

Pokémon and all related names are trademarks of Nintendo, Creatures Inc. and GAME FREAK Inc.
This project is not affiliated with or endorsed by any of them.
