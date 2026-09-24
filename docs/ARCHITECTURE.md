# Project Platinum — Architecture & Build Plan

**Status:** authoritative. This document supersedes the six research docs where they
disagree, and it is the single source of truth for *what we are building and in what
order*. The research docs in `docs/research/` remain the reference for *how* each format
works — read them for detail, read this for decisions.

**Synthesised from:** `nds-formats.md`, `platinum-data.md`, `gen5-assets.md`,
`species-data.md`, `godot-architecture.md`, `game-design.md`, plus an adversarial
verification pass that overturned three published claims (see §10).

**The game:** a Sinnoh remake of Pokémon Platinum in Gen 5 visual style, with hard level
caps at boss fights, HMs replaced by badge-gated automatic traversal, and species from all
nine generations available.

**The rule that constrains everything:** the owner's ROMs are his own, used locally.
**Nothing ROM-derived is ever committed to git.** Every extracted byte is regenerated on
demand by `tools/`, and every output path is gitignored.

---

## 1. Tech stack, and why

| Layer | Choice | Version |
|---|---|---|
| Engine | **Godot** | `4.7.2.stable.official.ed1daf0bf` |
| Language (game) | **GDScript** (statically typed) | GDScript 2.0 |
| Renderer | **GL Compatibility**, 256×192 viewport, integer scale | — |
| Language (tools) | **Python** | 3.8.3 + Pillow 7.2.0 + NumPy 1.24.4 |
| Data interchange | JSON (build-time) → binary `.res` (runtime) | — |
| Tests | Godot headless `SceneTree` harness | exit-code driven |

### 1.1 Why Godot 4.7.2

Every number below was measured on this machine against this binary
(`C:/Users/James/Documents/GitHub/Godot_v4.7.2-stable_win64_console.exe`). Use the
`_console.exe` build — the plain Windows build detaches from the console and you get no
stdout.

* **`TileMapLayer` + tile custom data is the right shape for this game.** Collision,
  encounter zone, ledge direction and traversal-obstacle type all live as per-tile
  metadata at **0.363 µs/lookup**. At ~4 lookups per step and ~4 steps/second that is under
  6 µs/second. No physics server, no collision shapes, no float tolerance, and — decisively
  — it is testable headlessly.
* **Headless testing actually works, with propagating exit codes.** `--headless --path .
  --script res://tests/run_tests.gd` returns 0 on pass and 1 on fail; `quit(3)` returns 3;
  a parse error returns 1; `--check-only` returns 1 on any type error, giving us a free
  static type-checker for a pre-commit hook. Autoloads instantiate in headless `--script`
  mode, so tests exercise the real singletons.
* **It is fast enough at the one place that matters.** 1,025 species load from a single
  binary `.res` in **26 ms**. The obvious design — one JSON file per species — takes
  **6,301 ms**, a 242× penalty, and the cost is file *opens*, not parsing. This single
  measurement dictates the whole data pipeline (§4).
* **2D-first, free, no build step, no licence entanglement** for a personal fan project.

### 1.2 Why GDScript, not C#

Static typing in GDScript buys **1.20×** on a 3M-iteration integer loop and **1.14×** on
500k property accesses — the honest number is 10–20%, not the 2× folklore. So performance
is *not* a reason to reach for C#, and the costs of C# are real: a build step before every
headless test run, a second toolchain to keep on PATH, and slower iteration.

Type everything anyway — for `--check-only`, for autocompletion, and because
`Array[SpeciesData]` makes a whole class of bug impossible. Just don't expect typing to
rescue a hot loop.

### 1.3 Why Python for extraction

* **The format knowledge is already written as working Python.** `nds-formats.md` is
  self-testing: `doc_selftest.py` execs all 25 Python fences out of the markdown and drives
  both ROMs using only that code — 25/25 blocks run, 28/28 symbols defined, correct sprites
  out. Porting that to another language would be re-deriving solved work.
* **Zero new dependencies.** Python 3.8.3, Pillow 7.2.0 and NumPy 1.24.4 are already on
  this machine. `csv` and `struct` are stdlib. There is **no Node.js** here, which is why
  Pokémon Showdown's `data/*.ts` is a cross-check and never a runtime dependency.
* **Extraction is a build step, not a runtime feature.** The game binary never opens a
  `.nds` file. That is both the legal posture and the performance posture.

> **Environment quirk, must be re-applied per shell.** Anaconda's `_ssl.pyd` and
> `_imaging` DLLs live in `Library/bin`, which only `conda activate` puts on PATH:
> ```bash
> export PATH="/c/Users/James/anaconda3:/c/Users/James/anaconda3/Library/bin:/c/Users/James/anaconda3/Library/mingw-w64/bin:/c/Users/James/anaconda3/Scripts:$PATH"
> ```
> `curl` uses Schannel and needs no fix — **so all downloading is done with `curl`** and
> Python stays offline-only. That keeps the quirk off the critical path.

### 1.4 The three command lines

The Godot project root **is the repo root**; `project.godot` sits at
`project-platinum/project.godot`.

```bash
GODOT="C:/Users/James/Documents/GitHub/Godot_v4.7.2-stable_win64_console.exe"
PROJ="C:/Users/James/Documents/GitHub/project-platinum"

"$GODOT" --headless --path "$PROJ" --import                                   # after ANY asset or class_name change
"$GODOT" --headless --path "$PROJ" --script res://tests/run_tests.gd          # exit 0 = pass
"$GODOT" --headless --path "$PROJ" --check-only --script res://src/foo.gd     # static type check
```

**`--import` must run before `--script`, always.** PNGs do not exist as loadable resources
until `.godot/imported/*.ctex` is written, and `class_name` globals do not exist until
`.godot/global_script_class_cache.cfg` is written. Both are produced only by the import
pass.

**Never gate CI on `--import`'s exit status.** It exits 0 even while logging fatal-looking
errors — verified against this repo's own `project.godot`, which declares six autoloads
whose script files do not exist and still exits 0. Gate on
`.godot/global_script_class_cache.cfg` being non-empty instead.

---

## 2. Repo layout

Everything in the tree, and what lives in it. `[git]` = tracked. `[ignored]` = gitignored,
regenerated by `tools/`.

```
project-platinum/
├── project.godot                  [git]  Godot project + autoload registry + input map
├── README.md                      [git]
├── .gitignore                     [git]  the enforcement point for the ROM rule
│
├── docs/                          [git]
│   ├── ARCHITECTURE.md                   this document — the build plan
│   └── research/                         the six verified format/design references
│       ├── nds-formats.md                NDS/NARC/LZ/Nitro-graphics, self-testing
│       ├── platinum-data.md              every Platinum narc path + struct, byte-verified
│       ├── gen5-assets.md                BW/B2W2 art archives, what is and isn't extractable
│       ├── species-data.md               PokeAPI/veekun data plan + sprite sourcing
│       ├── godot-architecture.md         measured Godot 4.7.2 patterns + test harness
│       └── game-design.md                progression, caps, HM removal, encounter tables
│
├── src/                           [git]  ALL game code. Nothing generated lives here.
│   ├── autoload/                         the six singletons (§6.1)
│   ├── data/                             Resource subclasses: SpeciesData, MoveData, …
│   ├── battle/                           headless battle engine + AI (§7)
│   ├── overworld/                        GridMover, Map, NPC, warps, traversal (§8)
│   ├── systems/                          caps, encounters, growth, type chart, RNG, scripts
│   └── ui/                               dialogue, party, bag, summary, battle HUD, town map
│
├── scenes/                        [git]  .tscn files
│   ├── Boot.tscn                         run/main_scene; hands off to Main
│   ├── Main.tscn                         persistent root (WorldHolder/BattleHolder/UILayer)
│   ├── battle/                           battle.tscn and its parts
│   ├── ui/                               reusable UI scenes
│   └── maps/                             one .tscn per map, generated then hand-painted
│
├── resources/                     [git]  hand-authored .tres: themes, shaders, curves,
│                                         input profiles, battle backgrounds
│
├── data/
│   ├── species.json moves.json abilities.json typechart.json  [git]  built from PokeAPI — NOT ROM-derived
│   ├── learnsets.json                                         [git]  built from PokeAPI
│   ├── level_caps.json traversal.json badges.json             [git]  hand-authored design tables
│   ├── tilesets/<atlas>.json                                  [git]  tile layout manifests (no ROM pixels)
│   ├── rom/                                                [IGNORED]  ★ every ROM-derived byte lives here
│   │   ├── trainers.json  encounters.json                             rosters, levels, movesets
│   │   ├── maps/<map_id>.json                                         collision, warps, events
│   │   └── text/<bank>.json                                           decrypted game text
│   └── *.res                                               [IGNORED]  built by Godot from the above
│
├── assets/
│   ├── ui/        [git]   icon.svg, window frames, cursors — hand-made or CC0
│   ├── fonts/     [git]   the UI font
│   ├── sprites/   [IGNORED]  1025×4 BW battle sprites (downloaded), icons
│   ├── tilesets/  [IGNORED]  tile atlases + generated .tres TileSets
│   ├── trainers/  [IGNORED]  trainer battle sprites, VS portraits
│   ├── overworld/ [IGNORED]  character sheets
│   ├── audio/     [IGNORED]  extracted SDAT
│   └── generated/ [IGNORED]  anything else a tool writes
│
├── tests/                         [git]
│   ├── run_tests.gd                      SceneTree runner, auto-discovers, exit 0/1
│   ├── test_case.gd                      TestCase base: check/eq/neq/almost
│   └── cases/                            test_*.gd, one file per subsystem
│
├── tools/                         [git]  the extraction + build toolchain (Python + GDScript)
│   ├── ndslib/                           reusable: nds.py narc.py lzss.py nitro.py nsbtx.py
│   ├── extract_platinum.py               Platinum → data/rom/**  (trainers, encounters, maps, text)
│   ├── extract_gen5_art.py               White 2 → assets/tilesets, trainers, overworld
│   ├── fetch_external.py                 curl PokeAPI CSVs + BW sprites + pokesprite icons
│   ├── build_species_json.py             veekun CSVs → species/moves/abilities/types JSON
│   ├── build_db.gd                       JSON → data/*.res      (headless Godot)
│   ├── build_tilesets.gd                 PNG atlases → .tres TileSets (headless Godot)
│   ├── build_maps.gd                     map JSON → scenes/maps/*.tscn skeletons
│   ├── run_tests.sh                      import-then-test CI entry point
│   └── _work/                     [IGNORED] scratch. One subdirectory per agent/task.
│
└── References/
    ├── Roms/                   [IGNORED]  the owner's cartridge dumps (§3.1)
    └── *.png *.webp *.import      [git]   BW2 / HGSS visual reference screenshots —
                                           the art target, not ROM-derived, safe to track
```

### 2.1 Three rules about this tree

1. **One ignore rule carries the whole ROM policy: `data/rom/`.** Every ROM-derived
   JSON goes under it, so the rule is a single line instead of a growing list that a future
   tool can forget to extend. If you add a ROM extractor, its output path starts with
   `data/rom/`. The corollary: **`data/species.json` and friends are NOT under it and ARE
   tracked**, because they come from PokeAPI, not from a cartridge.
2. **`src/` is hand-written; `data/*.res`, `data/rom/`, `assets/sprites`,
   `assets/tilesets` are generated.** If a file is generated, it is gitignored and there is
   a named tool that regenerates it. No exceptions — a generated file in git is a licence
   problem waiting to happen.
3. **`tools/_work/` is shared scratch and agents collide there.** Three separate research
   streams reported files being overwritten mid-session (`ndsfs.py` was clobbered and a
   parser was lost). **Every task writes to its own subdirectory** — `tools/_work/<task>/…`
   — never to `tools/_work/` directly.

---

## 3. The asset pipeline

```
  References/Roms/*.nds  ──┐
  (local, never in git)    │      tools/extract_*.py     ──►  data/rom/      ROM tables  [IGNORED]
                           ├──►   tools/fetch_external.py ─►  assets/**.png  art         [IGNORED]
  raw.githubusercontent ───┘      tools/build_species.py ──►  data/*.json    PokeAPI         [git]
  (curl: PokeAPI, sprites)          (Python 3.8.3)
                           │
                           ▼
       godot --headless --import   ──►  .godot/imported/*.ctex
                                        .godot/global_script_class_cache.cfg
                           │
                           ▼
       tools/build_db.gd           ──►  data/*.res            binary, 26 ms load
       tools/build_tilesets.gd     ──►  assets/tilesets/*.tres
       tools/build_maps.gd         ──►  scenes/maps/*.tscn    logic layer only; art painted by hand
                           │
                           ▼
       runtime: DataRegistry loads data/*.res in _ready()
```

### 3.1 Source ROMs (all local, all gitignored)

| Role | File under `References/Roms/` | Code | FAT |
|---|---|---|---|
| **Design + logic authority** | `Platinum/3541 - Pokemon Platinum Version (US)(XenoPhobia).nds` | `CPUE` | 462 |
| **Art authority (Gen 5)** | `White 2/Pokemon White 2 (Experience + Trade Evolution Patched).nds` | `IRDO` | 662 |
| Supplementary textures | `Heartgold/4780 - Pokemon HeartGold (U)(Xenophobia).nds` | `IPKE` | 513 |
| Cross-check only | `Black/5585 - Pokemon - Black Version …(SweeTnDs).nds` | `IRBO` | 484 |
| **Trade-evo patch source** | `*/[Platinum\|Heartgold\|Black\|White 2] no impossible evos.nds` | — | — |
| Out of scope | `Explorers of Sky/…` | — | different engine (PMD) |

**On the patched builds.** These are directly useful and one of them has already paid off.
Diffing `/poketool/personal/evo.narc` between vanilla Platinum and
`Platinum no impossible evos.nds` (both `CPUE`, both 508 entries) yields **exactly 16
differing species** — a ROM-authored substitution table for the trade evolutions, using two
rules and one hand-tuned exception:

| Vanilla method | Patched method | Species |
|---|---|---|
| `5` trade | `4` level-up at **L37** | Kadabra, Machoke, Graveler, Haunter |
| `6` trade holding item | `18`+`19` level-up holding that item, day **and** night | Poliwhirl→Politoed, Onix→Steelix, Scyther→Scizor, Seadra→Kingdra, Porygon→Porygon2, Porygon2→Porygon-Z, Rhydon→Rhyperior, Electabuzz→Electivire, Magmar→Magmortar, Dusclops→Dusknoir, Clamperl→Huntail **and** Gorebyss |
| exception | `7` use-item **Water Stone** | Slowpoke→Slowking (a level trigger would collide with Slowbro at L37) |

Adopt that scheme verbatim and extend the same two rules over the PokeAPI evolution data to
cover the Gen 5–9 trade lines (Boldore, Gurdurr, Karrablast/Shelmet, Phantump, Pumpkaboo,
Spritzee/Swirlix, Gimmighoul). Scratch proof: `tools/_work/arch/evodiff.py`.

**Caveat on the White 2 ROM:** the designated art ROM is itself a patched build
("Experience + Trade Evolution Patched"). That is harmless for graphics — an exp/evo patch
does not touch `/a/0/1/4` or `/a/0/0/4` — but **never read species, exp or evolution data
out of it.** Those come from Platinum and PokeAPI.

### 3.2 Platinum (`CPUE`) — the actual narc paths

**Address NARCs by path through the FNT, never by FAT file ID.** Of the 77 paths present in
both Platinum and HeartGold, **77/77 have a different FAT index**. File IDs are not portable
across games or regional builds.

| In-ROM path | n | What we take from it | Struct |
|---|---:|---|---|
| `/poketool/personal/pl_personal.narc` | 508 | Gen-4 base stats / TM-HM compat — **cross-check only** | 44 B fixed |
| `/poketool/personal/wotbl.narc` | 508 | Gen-4 level-up learnsets (optional period-accurate mode) | `u16`, move `&0x1FF`, level `>>9`, `0xFFFF` term |
| `/poketool/personal/evo.narc` | 508 | evolution methods + the trade-evo patch diff (§3.1) | 7 × `{u16 method, param, target}` + 2 pad |
| `/poketool/personal/pl_growtbl.narc` | 8 | EXP curves | `u32` per level |
| `/poketool/waza/pl_waza_tbl.narc` | 471 | Gen-4 move table — cross-check only | 16 B fixed |
| `/itemtool/itemdata/pl_item_data.narc` | 446 | item prices, held effects, pocket | 34 B fixed |
| **`/poketool/trainer/trdata.narc`** | **928** | **trainer headers** — class, sprite, party size, AI mask, battle type | **20 B fixed** |
| **`/poketool/trainer/trpoke.narc`** | **928** | **trainer parties** — the boss ladder and the cap table | 8/10/16/18 B per mon, **blob 4-byte aligned** |
| `/poketool/trmsg/trtbl.narc` | 1 | 2,497 `(trainerID, msgType)` pairs → battle dialogue | 4 B/pair |
| `/poketool/trmsg/trtblofs.narc` | 1 | 928 `u16` offsets into `trtbl` | 2 B |
| **`/fielddata/encountdata/pl_enc_data.narc`** | **183** | **wild encounter tables** (the live Platinum set) | **424 B fixed** |
| `/arc/encdata_ex.narc` | 12 | Feebas tile, honey trees, Trophy Garden + Great Marsh rotations | mixed |
| **`/fielddata/land_data/land_data.narc`** | **666** | **per-chunk 32×32 collision + behaviour grid**, props, NSBMD, BDHC | 4×`u32` sizes + 4 sections |
| **`/fielddata/mapmatrix/map_matrix.narc`** | **289** | **world layout** — which chunk/header/altitude at each cell | `w,h,flags,name` + 3 arrays |
| **`/fielddata/eventdata/zone_event.narc`** | **534** | **NPCs, trainers, warps, signs, step triggers** | 4 counted blocks: 20/32/12/16 B |
| `/fielddata/script/scr_seq.narc` | 1124 | event-script *structure* only — see §11.1 | `u32` rel-offset table, `0xFD13` term |
| `/fielddata/areadata/area_data.narc` | 75 | tileset/texture/lighting selector per area | 8 B (4×`u16`) |
| **`/msgdata/pl_msg.narc`** | **724** | **all game text** — species, items, moves, locations, trainers, dialogue | encrypted bank archive |
| **ARM9 file offset `0xE601C`** | **593** | **map header table** — the hub that ties everything together | **24 B fixed** |
| `/poketool/pokegra/pl_pokegra.narc` | 2964 | Gen-4 battle sprites — **fallback only**, see §3.4 | 494 × 6, XOR-obfuscated |
| `/poketool/icongra/pl_poke_icon.narc` | 547 | Gen-4 party icons — **not used** (palette index missing) | — |
| `/poketool/trgra/trfgra.narc` | 525 | Gen-4 trainer sprites — fallback | 105 × 5 |

**Text banks we actually read** (`pl_msg.narc` sub-file index == pret `TEXT_BANK_*` ordinal):
392 `ITEM_NAMES`, 412 `SPECIES_NAME`, **433 `LOCATION_NAMES`**, 610 `ABILITY_NAMES`,
**617 `NPC_TRAINER_MESSAGES`** (2,497), **618 `NPC_TRAINER_NAMES`** (928), 619
`TRAINER_CLASS_NAMES`, 624 `POKEMON_TYPE_NAMES`, 647 `MOVE_NAMES`, 699–707 dex entries,
711 `SPECIES_CATEGORY`.

**The map header is the hub.** It is *not* in a NARC — it is 593 × 24 bytes at ARM9 file
offset `0xE601C` (RAM `0x020E601C`), established two independent ways: a 593-value
`msgArchiveID` fingerprint from pret scored **593/593** there (runner-up 115), and DSPRE
hardcodes the same offset for Plat/English. From one header you reach area data, the map
matrix, the script archive, the event archive, the encounter table, the message bank and the
display name.

```
                           ┌── areaDataArchiveID ──> area_data.narc ──> map textures / props
                           ├── mapMatrixID ────────> map_matrix.narc
   MapHeader               │                          ├── maps[]      -> land_data.narc   (collision + model + BDHC)
   ARM9 0xE601C ───────────┤                          ├── headers[]   -> MapHeader (per cell, outdoor only)
   593 × 24 B              │                          └── altitudes[]
                           ├── eventsArchiveID ────> zone_event.narc (NPCs, warps, triggers, signs)
                           ├── wildEncountersArchiveID -> pl_enc_data.narc   (0xFFFF = none)
                           ├── msgArchiveID ───────> pl_msg.narc      (this map's dialogue)
                           └── mapLabelTextID ─────> pl_msg.narc[433] (the map's display name)
```

### 3.3 White 2 (`IRDO`) — the art paths

Gen 5 anonymises the filesystem: every asset is a NARC at a numbered path `/a/X/Y/Z`.
**Black and White 2 do not share numbering** — 102 of Black's 234 `/a/` archives are
byte-identical to a White 2 archive *at a different path*. **Hard-code White 2 paths.**

| Path | Entries | Content | Use |
|---|---:|---|---|
| **`/a/0/1/4`** | **409 banks, 35,076 slots, 3,998 names** | NSBTX terrain textures, **16×16 dominant**, PAL16 76% | **the tile library** |
| `/a/1/7/4` | 70 | building exteriors (`pc_kabe02`, `gate_1`) | tiles |
| `/a/1/7/5` | 93 | interiors/furniture (`idr_pc01`, `idr_tv01`) | tiles |
| `/a/0/4/8` | 975 | map objects + character shadow (`h_kage` 8×8) | props |
| **`/a/0/7/1`** | **1,504 = 188 × 8** | trainer battle sprites, full NCER/NANR/NMCR/NMAR rig | trainers (medium effort) |
| **`/a/2/6/7`** | 76 → 53 images | **VS portraits, flat 128×128**, block-grouped NCGR then NCLR | trainers (trivial) |
| **`/a/0/3/1`** | 97 → 32 sets | overworld characters: NCGR 32×128 (4 × 32×32 facings) + NCER(4 cells) + NANR(5 seqs) | overworld (low) |
| `/a/0/2/5` | — | items / Poké Balls, 32×32 NCGR+NCLR pairs from entry 2 | UI (trivial) |
| `/a/0/0/4` | 15,065 = **751** form blocks × 20 + 45 tail | Pokémon battle sprites | **NOT USED — see §3.4** |
| `/a/0/0/7` | 1,510, 774 NCGR | party icons, dex-ordered, 32×64 | **NOT USED — see §3.4** |
| ~~`/a/2/9/1`~~ | 472 | **trainer-class battle art, NOT overworld** | **do not chase** |
| HeartGold `/a/0/4/4` | 106 banks, 1,958 names | 32×32-dominant terrain textures | supplementary |

> **`/a/2/9/1` is a dead end for overworld characters.** The earlier identification was
> refuted by byte-identical tile intersection: 2,297 of its 3,575 unique tiles (64.3%) are
> shared with `/a/0/7/1`, the trainer battle-sprite rig, against 17 (0.5%) with `/a/0/3/1`.
> Set 0 renders as Nate, set 1 as Rosa. There is no missing NCER — placement is three
> hardcoded OAM objects in ARM9/overlay code. It is a B2W2 side-facility asset. See the
> correction block in `gen5-assets.md §2`.

### 3.4 Pokémon sprites: download, do not extract

This is the single biggest schedule saving in the plan, and it reverses the obvious
approach.

**There is no flat Pokémon battle sprite anywhere in the Gen 5 ROM.** Every species is a
sliced part atlas driven by an NNS multicell rig (NCER body parts + NANR per-part sequences
labelled in romaji `atama`/`ago` + NMCR node graph). Rendering `+0` or `+2` directly gives a
scattered pile of jaws, wings and feet. A research composer reached "unmistakably the right
Pokémon in the right colours with parts roughly placed" and stalled there — the per-node
`(x,y)` versus per-frame translation semantics are unresolved. Worse, the Gen 5 form index
is **not** a dex number (751 form blocks for 649 species) and the mapping table lives outside
the archive, in ARM9 or an overlay that White 2 **BLZ-compresses and signs**.

Meanwhile **`PokeAPI/sprites` already ships complete Gen-5-style front / back / shiny /
back-shiny PNGs for all 1025 species — 4,100 files, 3.83 MB total**, verified as genuine
96×96 with authentic 7–16 colour BW palettes. IDs 650+ are Smogon Sprite Project work that
PokeAPI has already ingested, deduplicated, renamed to dex-number convention and QA'd.

**Decision: download the sprites. Do not write the Gen 5 multicell composer for Pokémon.**
It converts an open-ended reverse-engineering problem with two unsolved sub-problems into a
3-minute download. Write the composer only if animated *trainer* sprites become a
requirement, and then point it at `/a/0/7/1`.

```bash
# the static 4-set: 1025/1025 coverage, 3.83 MB, ~3.3 min at 8 threads
BASE=https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white
# variants: ""  "shiny/"  "back/"  "back/shiny/"   ->  assets/sprites/{front,shiny,back,back_shiny}/
```

> **Do NOT `git clone --filter=blob:none --sparse` the sprite repo.** Cone-mode granularity
> cannot exclude the animated GIF folders, so it pulls 174 MB of working tree plus an 87 MB
> `.git` to obtain 3.83 MB of useful files — and it is what exhausted the disk during
> research. Use per-file HTTP fetches with an 8-thread pool.

**Icons:** `msikma/pokesprite` `pokemon-gen8/{regular,shiny}/<slug>.png` — **MIT-licensed**,
the only clean asset in the plan — covers 1–905. Join by name slug via its
`data/pokemon.json` (`idx` → `slug.eng`). For 906–1025 downscale the BW battle sprite. Do
**not** use the ROM icon archives: the per-species icon palette index is not in the NARC in
either Gen 4 or Gen 5, so ROM icons render with correct silhouettes and wrong hues.

**Animated GIFs (158 MB) are deferred.** They cover only 868/1025 front and 818/1025 back,
so a static fallback path is mandatory regardless. Build the battle scene against static
sprites; animation is a later, optional upgrade.

### 3.5 Tiles: extract a library, author the maps

**Correct the premise up front: neither Gen 5 nor HeartGold is a 2D tilemap game.** Both
render the overworld as 3D NSBMD geometry textured with NSBTX banks. What makes HGSS *look*
2D is a fixed near-top-down camera over flat ground quads, not a different data format. **So
there is no tileset image and no tilemap to extract from either game.**

What *is* extractable — and it is excellent — is the named texture library.

1. `tools/extract_gen5_art.py` decodes every `TEX0` bank in White 2 `/a/0/1/4` (+ `/a/1/7/4`,
   `/a/1/7/5`) to RGBA, **deduplicates by name plus decoded pixels** (the same tile recurs
   across hundreds of per-area banks), and writes `assets/tilesets/lib/<name>.png`.
   White 2 wins over HeartGold on all four axes: it matches the stated visual target, its
   dominant texture size is **16×16** (HGSS is 32×32, because its world grid is 32 units),
   it is the larger library (3,998 vs 1,958 distinct names), and its formats are
   overwhelmingly PAL16.
2. A human composes atlas PNGs per biome from that library. Texture names are romaji and
   self-documenting: `gake01a`/`gake_michi` (cliff, cliff path), `dansa01a` (step),
   `grass01ax`, `hana01.1` (flower), `doukutu01` (cave), `fence_01`, `chip_yuka`/`chip_kabe`
   (floor/wall).
3. `tools/build_tilesets.gd` turns each atlas into a `.tres` `TileSet` with the custom-data
   layers from §8.2.

**Do not attempt automatic map reconstruction.** Deriving which texture sits on which 16×16
ground cell requires parsing NSBMD geometry and per-quad UVs, and the source is genuinely 3D
(ramps, height variation, rotated camera) so it will not map cleanly onto a 2D grid even if
parsed. **But see §8.5 — the *logic* half of every map is importable, and that is most of
the work.**

#### Two TileSet codegen traps that silently corrupt data

* **Order is mandatory:** `TileSet.new()` → `add_custom_data_layer()` ×N → build
  `TileSetAtlasSource` + `create_tile()` → **`ts.add_source(src, id)`** → *then*
  `set_custom_data()`. Writing custom data before `add_source` fails, and after a later
  `add_source` the tile reads back as the **type default** (`false`), not `null` and not an
  error. Every grass tile would silently be non-grass. `tests/cases/test_tileset_codegen.gd`
  guards exactly this.
* **Always `load()` an imported PNG; never `ImageTexture.create_from_image()`.** An
  `ImageTexture` has no `resource_path`, so `ResourceSaver` inlines the entire pixel buffer:
  **78,183 bytes vs 436 bytes** for the same tileset. Pipeline order is therefore: Python
  writes the PNG → `--import` → codegen `load()`s it → save the tileset.

### 3.6 External data: the PokeAPI veekun CSV dump

27 files, **11.2 MB**, plain CSV, no runtime dependency, exactly **1025 species** through
Pecharunt. It is the only candidate that is simultaneously bulk, plain-text, complete and
runtime-free, and it uniquely carries `growth_rate`, `base_experience`, `capture_rate`,
`base_happiness`, `hatch_counter`, EV yield and structured evolution conditions — Showdown
is a battle sim and has no EXP curves at all.

Validated against Pokémon Showdown parsed in pure Python: **type chart 324/324 identical**,
base stats + types **1024/1025** (the one difference is Minior's form-default convention),
moves **439/440**. Build time 2.1 s, output 1.88 MB, **1025/1025 species complete, zero
incomplete**.

**Pin a commit SHA rather than tracking `master`** — PokeAPI was pushed the same day as the
research and version-group ids can change shape.

### 3.7 What is gitignored, and why

The reasoning, so nobody "tidies" it later:

| Ignored | Why |
|---|---|
| `References/Roms/`, `*.nds`, `*.nds.log`, `*.gba`, `*.sav`, `*.srm`, `*.dsv` | **Commercial ROMs.** Never in git, never in a build artefact, never uploaded. |
| **`data/rom/`** | **The single rule that carries the ROM policy.** All ROM-derived factual data — rosters, levels, movesets, collision grids, decrypted text — lands under this one prefix. |
| `assets/generated/ assets/sprites/ assets/tilesets/ assets/audio/ extracted/` | **ROM-derived or third-party fan art.** Regenerated by `tools/`. |
| `data/*.res` | Build output of the above. |
| `tools/_work/`, `tools/.cache/`, `__pycache__/` | Scratch. Per-task subdirectories. |
| `.godot/ .import/ export_presets.cfg builds/` | Engine caches and machine-local export config. |

**Explicitly NOT ignored, and that is correct:** `data/species.json`, `data/moves.json`,
`data/abilities.json`, `data/typechart.json`, `data/learnsets.json` (PokeAPI, BSD-3 data,
not cartridge data); `data/level_caps.json` and the other design tables (hand-authored);
`References/*.png` / `*.webp` (the BW2 and HGSS reference screenshots — these are the art
*target*, not extracted assets).

> **Open item for the owner.** `docs/research/platinum-data.md` and
> `docs/research/game-design.md` are at **git-tracked** paths and they contain ROM-derived
> factual data — full gym leader / Elite Four / Team Galactic rosters with levels, movesets
> and held items. That is in tension with the repo rule. The research briefs specified those
> paths, so they were written there and **nothing has been committed**. Decide before the
> first commit whether the roster tables stay in tracked docs or move to an ignored
> location; the structural knowledge (paths, structs, offsets) is fine either way — it is
> the extracted *content* that is at issue.

**Licence posture, stated plainly.** `PokeAPI/sprites` has **no LICENSE file**, and IDs 650+
are Smogon-community fan art of Nintendo-trademarked characters. The BSD-3 licence on
`PokeAPI/pokeapi` covers API code and data, **not** the sprite images. This is the same
footing every Pokémon fan game stands on: fine for a personal, non-distributed project;
**not** licence-clean, and **not** safe to monetize or redistribute. Credit the Smogon
Sprite Project. `msikma/pokesprite` (MIT) is the one genuinely clean asset in the plan.

---

## 4. The data model

Two representations. **JSON is the build-time interchange format** — human-inspectable,
diffable, produced by Python. **Binary `.res` holding typed Resources is the runtime
format** — 26 ms for 1,025 species, integers stay integers.

> **Godot's JSON parser returns every number as a float.** Verified on 4.7.2:
> `{"level": 1.0, "id": 85.0}`. Species IDs, move IDs, levels, EVs, IVs, money and RNG seeds
> are all integers, and a float used as a Dictionary key or array index is a bug that
> surfaces hours later. **Every `int()` cast happens once, at build time, in `build_db.gd`.**
> Runtime never sees JSON.

### 4.1 `data/species.json` — keyed by dex number as a string

```jsonc
"387": {
  "id": 387, "name": "turtwig", "display": "Turtwig", "generation": 4,
  "types": ["grass"],
  "base_stats": { "hp":55, "attack":68, "defense":64,
                  "special-attack":45, "special-defense":55, "speed":31 },
  "ev_yield": { "attack": 1 },
  "abilities": ["overgrow"], "hidden_ability": "shell-armor",
  "egg_groups": ["monster", "plant"],
  "growth_rate": "medium-slow", "base_exp": 64,
  "capture_rate": 45, "base_happiness": 70, "hatch_counter": 20,
  "gender_ratio_female": 1,              // eighths; null = genderless
  "height_dm": 4, "weight_hg": 102,
  "is_baby": false, "is_legendary": false, "is_mythical": false,
  "evolves_from": null, "evolution_chain": 163,
  "evolves_to": [ { "to": 388, "trigger": "level-up", "min_level": 18 } ],
  "learnset_source": "platinum",
  "learnset": {
    "level_up": [ {"move":"tackle","level":1}, {"move":"withdraw","level":5} ],
    "egg": ["growth","sand-tomb"], "tutor": [], "machine": ["cut","strength"]
  }
}
```

**Learnset fallback chain — three traps, all mandatory to avoid.** Gen 9 games contain only
777 of 1025 species, so a newest-first chain is required. Six version groups are **empty**
(ids 21, 22, 26, 27, 30, 31) and one is a **silent-failure trap**: `champions` (id 32) has
19,810 rows and **zero level-up rows**. Reaching it first hands 44 species — Kangaskhan,
Alakazam, Pidgeot, Beedrill — a completely empty movepool with no error. **Exclude all
seven, and keep the completeness assertion in the build; it is the only thing that caught
this.** Fail the build on any incomplete species.

For a Sinnoh remake, set `ORDER = [9, 10, 8, 14, 11, 25, 20, 23, …]` (Platinum → HGSS → DP
first) for period-accurate movepools on the 493 Gen-1–4 species, falling through to modern
data for 494–1025. That ordering is the script's single knob.

### 4.2 `data/moves.json` — keyed by identifier

```jsonc
"razor-leaf": {
  "id": 75, "name": "razor-leaf", "display": "Razor Leaf", "generation": 1,
  "type": "grass", "category": "physical",
  "power": 55, "accuracy": 95, "pp": 25, "priority": 0,
  "target": "all-opponents",
  "effect_id": 43, "effect_chance": null,
  "crit_stage": 1,
  "flags": ["protect", "mirror", "slicing"]
}
```

* `accuracy: null` means **never misses** — veekun encodes this as an empty string for 288
  moves *and* as the literal `"0"` for exactly three Gen-9 moves (`burning-bulwark`,
  `tachyon-cutter`, `dragon-cheer`). Read naively, `0` means *always misses*. Normalize both
  to `null`.
* **Flag names are normalized to Showdown vocabulary at build time.** veekun ships 21 flags;
  three are renames, each proven by exact move-set equality over the 789 shared moves:
  `authentic`→`bypasssub` (75/75), `ballistics`→`bullet` (25/25),
  `non-sky-battle`→`nonsky` (40/40). veekun's `mental` (Aroma Veil / Mental Herb) has no
  Showdown counterpart and is kept as-is.
* Genuinely missing modern flags are `wind`, `slicing`, `cantusetwice` — all Gen 8/9, **none
  of which exist in Gen 4**. A hand-maintained ~45-move supplemental table is cheaper than
  parsing Showdown's `moves.ts`, which defeats pure-Python regex (477/919 recovered) because
  move entries embed JavaScript callbacks.

### 4.3 `data/typechart.json`

```jsonc
{ "order": ["normal","fighting","flying","poison","ground","rock","bug","ghost","steel",
            "fire","water","grass","electric","psychic","ice","dragon","dark","fairy"],
  "chart": { "fairy": { "dragon": 2.0, "steel": 0.5, "fire": 0.5, "fighting": 2.0, … }, … } }
```

The modern **Gen 6+ 18-type chart**, 324/324 dense, diffed against Showdown with **zero
differences**. All eight canonical immunities present. `ghost→steel` and `dark→steel` are
correctly **1.0** (they were 0.5 in Gens 2–5).

**Decision: ship the modern chart, including Fairy.** This is a remake with nine
generations of species in it; a Gen-4 chart would leave 60+ Fairy-types with broken
matchups. `type_efficacy_past.csv` holds the two Gen-5 deltas if a "classic" toggle is ever
wanted.

### 4.4 `data/rom/encounters.json` *(ROM-derived — gitignored)*

The Platinum 424-byte struct, decoded. Grass slots carry a **single `s8 level`**; water
entries carry **`maxLevel` then `minLevel` (max first)** — the asymmetry is real.

```jsonc
"enc_140": {
  "index": 140, "area_hint": "route_201",
  "land_rate": 30,
  "grass": [ {"slot":0,"rate":20,"species":396,"level":2}, … ],   // 12 slots, rates 20,20,10,10,10,10,10,10,5,5,4,4
  "swarm":      [84, 84],
  "day_only":   [396, 399],     // replaces grass slots 2..3
  "night_only": [401, 399],
  "poke_radar": [29, 32, 202, 202],   // replaces grass slots 4,5,10,11
  "dual_slot":  { "firered": [58,58], "ruby": [], … },            // replaces slots 8..9
  "surf":     {"rate":0, "slots":[]},
  "old_rod":  {"rate":25, "slots":[{"species":129,"min":3,"max":15}]},
  "good_rod": {…}, "super_rod": {…},
  "curated": {                                  // the remake's overlay — hand-authored, git-tracked
    "grass": [ … §4.3 of game-design.md … ]
  }
}
```

The `curated` block is the remake's cross-generation table from `game-design.md §4.3`; the
vanilla block is kept beside it as provenance and as the fallback. **Guests inherit the
vanilla slot's level band** — no new level bands are invented, which keeps the cap
verification intact for free.

> **Known gap:** area *names* are inferred by composition, not read. Route 201 = index 140
> because Starly/Bidoof/Kricketot at L2–4. Species and levels are ROM-exact; the
> index→name mapping is inference. **Oreburgh Gate 1F vs B1F (53 vs 54) is the least certain
> pair.** Resolve every name by walking the 593 map headers'
> `wildEncountersArchiveID` + `mapLabelTextID` before hard-coding names into the build —
> `extract_platinum.py` does exactly that and writes `area_hint` from the header, not from a
> guess.

### 4.5 `data/rom/trainers.json` *(ROM-derived — gitignored)*

```jsonc
"246": {
  "id": 246, "class": "leader", "class_name": "Leader", "name": "Roark",
  "sprite": 26, "ai_mask": 7, "battle_type": "single",
  "items": ["super-potion","super-potion"],
  "party": [
    {"species":74,  "level":12, "iv_scale":200, "moves":[],  "item":null, "form":0},
    {"species":95,  "level":12, "iv_scale":200, "moves":[],  "item":null, "form":0},
    {"species":408, "level":14, "iv_scale":200, "moves":["headbutt","leer","focus-energy","take-down"],
                                                 "item":"oran-berry", "form":0}
  ],
  "is_boss": true, "cap_checkpoint": "badge_coal"
}
```

Three extraction rules that are not optional:
1. **`monDataType` selects the party-entry variant** — bit 0 = has moves, bit 1 = has item →
   8 / 16 / 10 / 18 bytes. Distribution: 672 / 198 / 4 / 54.
2. **The party blob is `partySize × entrySize` rounded up to a multiple of 4.** With the
   rule: **927/927 exact**. Without it, 43 entries mismatch — every one a `monDataType 3`
   trainer with an odd party size (3 × 18 = 54 stored in 56).
3. **`species` low 11 bits = species, upper bits = form.** `ivScale` low byte scales all IVs
   (255 = perfect); gym leaders use 200–250.

**Trainer names are `0xF100`-compressed** and pack 9-bit characters into only **15 usable
bits per `u16`**, not 16. A 16-bit accumulator decodes exactly the first character correctly
and garbles everything after, which makes the bug look like a charmap problem. This is
already solved in `platinum-data.md §3.9`.

### 4.6 `data/rom/maps/<map_id>.json` *(ROM-derived — gitignored)*

```jsonc
{
  "id": "route_201", "header_id": 191, "display_name": "Route 201",
  "map_type": "outdoors", "weather": 0, "camera": 0,
  "flags": { "bike": true, "run": true, "escape_rope": false, "fly": true },
  "music": { "day": 1120, "night": 1121 },
  "encounter_table": "enc_140",
  "matrix": { "id": 0, "cells": [[13,14],[43,44]] },      // land_data indices, row-major
  "size": [64, 64],                                        // tiles, after chunk assembly
  "terrain": {                                             // 32×32 per chunk, assembled
    "blocked":   "<base64 bitset>",                        // high byte 0x80
    "behaviour": "<base64 u8 grid>"                        // low byte, 94 distinct values
  },
  "warps":   [ {"x":10,"z":0,"to_header":3,"to_warp":2} ],
  "objects": [ {"local_id":0,"gfx":97,"movement":2,"trainer_type":0,"trainer_id":0,
                "flag":0,"script":231,"dir":"down","range":[0,0],"x":14,"z":20,"y":0} ],
  "signs":   [ {"script":312,"type":3,"x":9,"z":17,"facing":"up"} ],
  "triggers":[ {"script":401,"x":12,"z":3,"w":3,"h":1,"var":0x40A2,"value":1} ]
}
```

**The behaviour byte is the whole traversal system** (§8.3). Values derived empirically from
per-map histograms across all 666 chunks:

| Behaviour | Meaning | Evidence |
|---|---|---|
| high byte `0x80` | **impassable** | the high byte is exactly `{0x00, 0x80}` game-wide |
| `0x15` / `0x16` / `0x17` | **water** | `0x15` dominates all-water Seabreak Path / Route 223 |
| `0x13` | **waterfall** | only 55 tiles game-wide, 100% water-adjacent, only in League, Route 210, Mt. Coronet, Victory Road, Route 208, Distortion World |
| `0x4B` / `0x4C` | **Rock Climb wall** | 100% blocked, 247 tiles, only late-game areas. Adding `0x4C` fixed two otherwise-impossible Mt. Coronet maps |
| `0x3B` | **ledge, jump south** | 616 tiles, all horizontal runs — the only horizontal-ledge code |
| `0x38` / `0x39` | ledge east / west | 33 and 62 tiles, only vertical runs |
| `0x3A` | north ledge | **absent — unused in Platinum** |
| `0x5E`–`0x6F` | door / warp band | warp tiles land in this band 900+ times under row-major |

Row-major chunk order **and** row-major intra-chunk order are both proved: matrix-0
`heads[y//32*30 + x//32]` equals the owning map for every outdoor warp, and warp tiles under
row-major fall in the door band, versus mostly `0x00` under column-major.

**Obstacles come from `zone_event` object records, not from the terrain grid:**

| `scriptID` | `graphicsID` | Obstacle | Counts |
|---|---|---|---|
| 10000 | 86 | **Cut tree** | Eterna Forest, Galactic Eterna Building door, routes |
| 10001 | 85 | **Rock Smash rock** | Ravaged Path 27, Oreburgh Gate 16, Mt. Coronet 59, Victory Road 7 |
| 10002 | 84 | **Strength boulder** | Victory Road 26, Stark Mountain 10, Mt. Coronet 9, Snowpoint Temple 1 |

### 4.7 `data/level_caps.json` *(hand-authored — git-tracked)*

```jsonc
{ "version": 1, "start": 14, "postgame": 100,
  "tiers": [
    { "flag": "badge_coal",    "cap": 22, "checkpoint": "Gardenia / Roserade 22" },
    { "flag": "badge_forest",  "cap": 26, "checkpoint": "Fantina / Mismagius 26" },
    { "flag": "badge_relic",   "cap": 32, "checkpoint": "Maylene / Lucario 32" },
    { "flag": "badge_cobble",  "cap": 37, "checkpoint": "Crasher Wake / Floatzel 37" },
    { "flag": "badge_fen",     "cap": 41, "checkpoint": "Byron / Bastiodon 41" },
    { "flag": "badge_mine",    "cap": 44, "checkpoint": "Candice / Froslass 44" },
    { "flag": "badge_icicle",  "cap": 50, "checkpoint": "Volkner / Electivire 50" },
    { "flag": "badge_beacon",  "cap": 53, "checkpoint": "Aaron / Drapion 53" },
    { "flag": "e4_aaron",      "cap": 55, "checkpoint": "Bertha / Rhyperior 55" },
    { "flag": "e4_bertha",     "cap": 57, "checkpoint": "Flint / Magmortar 57" },
    { "flag": "e4_flint",      "cap": 59, "checkpoint": "Lucian / Gallade 59" },
    { "flag": "e4_lucian",     "cap": 62, "checkpoint": "Cynthia / Garchomp 62" },
    { "flag": "hall_of_fame",  "cap": 100, "checkpoint": "uncapped" }
  ] }
```

The active cap is the **cap of the last satisfied tier**, defaulting to `start`. Every
mandatory fight sits at or under the cap in force, with all eight gyms and the League
exactly level-matched. **Tightest margins: the Pastoria rival fight (+1) and Cyrus in the
Distortion World (+2).** Any upward rebalance of a boss requires re-running that
verification table.

**Per-member Elite Four caps are deliberate.** You gain exp *during* the gauntlet, so each
raise is live: you enter at ≤53 and climb to 62 by Cynthia, but only by actually winning.
A flat "62 for the whole League" would let you grind to 62 before Aaron and trivialise
E1–E3.

**One script-order dependency to enforce:** Jupiter's Eterna Building fight (ace 23) must
remain *after* Gardenia, because the pre-Gardenia cap is 22. Vanilla already does this — the
building door is behind Cut trees and Cut is the Forest Badge reward. Keep that dependency
and the table holds for free.

### 4.8 `data/traversal.json` and `data/badges.json` *(hand-authored — git-tracked)*

```jsonc
// badges.json — badge order is a 1:1 preservation of vanilla Platinum bindings
[ {"id":"badge_coal",   "n":1, "leader":"Roark",        "verb":"smash",     "cap_to":22},
  {"id":"badge_forest", "n":2, "leader":"Gardenia",     "verb":"cut",       "cap_to":26},
  {"id":"badge_relic",  "n":3, "leader":"Fantina",      "verb":null,        "cap_to":32},
  {"id":"badge_cobble", "n":4, "leader":"Maylene",      "verb":"fly",       "cap_to":37},
  {"id":"badge_fen",    "n":5, "leader":"Crasher Wake", "verb":"surf",      "cap_to":41},
  {"id":"badge_mine",   "n":6, "leader":"Byron",        "verb":"strength",  "cap_to":44},
  {"id":"badge_icicle", "n":7, "leader":"Candice",      "verb":"climb",     "cap_to":50},
  {"id":"badge_beacon", "n":8, "leader":"Volkner",      "verb":"waterfall", "cap_to":53} ]
```

**Platinum's gym order is Roark, Gardenia, FANTINA, Maylene, Wake, Byron, Candice,
Volkner — Fantina is gym 3, not gym 5 as in Diamond/Pearl.** Platinum also **swaps Relic and
Fen** relative to D/P (D/P: Fen = Defog, Relic = Surf). Getting either wrong is the single
most common mistake when porting Sinnoh data, and the level data confirms it (Fantina 24–26
sits between Gardenia 20–22 and Maylene 28–32).

`badge_relic` has `verb: null` by design — Defog gated nothing in vanilla and the fog is
deleted outright (§8.4). Option B in `game-design.md §3.4` (move FLY to Relic, add a shallow
WADE verb at Cobble) stays on the shelf; ship Option A first.

### 4.9 Runtime shape — one binary `.res`

```gdscript
class_name SpeciesData extends Resource
@export var id: int
@export var name_en: String
@export var types: PackedStringArray
@export var base_stats: PackedInt32Array        # hp atk def spa spd spe
@export var ev_yield: PackedInt32Array
@export var abilities: PackedInt32Array
@export var hidden_ability: int
@export var catch_rate: int
@export var base_exp: int
@export var growth_rate: StringName
@export var egg_groups: PackedInt32Array
@export var gender_ratio: int                   # eighths female, -1 = genderless
@export var hatch_cycles: int
@export var learnset_levels: PackedInt32Array   # parallel arrays beat Array[Dictionary]
@export var learnset_moves: PackedInt32Array    # for both size and speed
@export var tm_compat: PackedByteArray
@export var egg_moves: PackedInt32Array
@export var evolutions: Array[EvolutionEdge]
@export var dex_entry: String

class_name SpeciesDB extends Resource
@export var species: Array[SpeciesData] = []
```

Use `Packed*Array` for every numeric list — contiguous, compact in the binary `.res`, and
integers stay integers. **`.res`, not `.tres`, for generated data:** binary is 6.4× faster
to load (26 ms vs 165 ms) and 24% smaller. Text `.tres` is for things a human edits or
diffs.

### 4.10 Save format

| Data | Format | Why |
|---|---|---|
| Ship-with-the-game content (species DB, tilesets, maps) | `.res` / `.tres` | Inside the PCK, we authored it, fastest |
| **Player saves in `user://`** | **`FileAccess.store_var(v, false)`** | Preserves `int` and `Vector2i`; **refuses to instantiate Objects** |
| Settings | `ConfigFile` | Human-editable on purpose; supports encryption |

> **Never call `ResourceLoader.load()` on a save file.** This is demonstrated, not
> theoretical: a hand-written `.tres` embedding a `GDScript` sub-resource **executed its
> `_init()` during load**. In 4.7.2 there is no opt-out — the signature is
> `load(path, type_hint, cache_mode)` with no `allow_objects` flag, and `type_hint` does not
> help. Shared save files are normal in the fan-remake scene. **Treat `user://` as hostile.**

The `false` argument to `store_var`/`get_var` appears on both sides and is the whole
security story. Writing `{"payload": Resource.new()}` with `full_objects = false` reads back
as an inert `EncodedObjectAsID`, not a reconstructed object. Write to `<slot>.tmp` and
rename, so a crash mid-write cannot destroy the previous save.

---

## 5. Test harness

Three files, already proven, currently living in gitignored scratch
(`tools/_work/godottest/`). **Phase 0 copies them into `res://tests/`** — the doc reproduces
them in full but they will not survive a clean checkout otherwise.

* `tests/test_case.gd` — `TestCase extends RefCounted` with `check/eq/neq/almost`.
* `tests/run_tests.gd` — `SceneTree` runner. Auto-discovers `tests/cases/test_*.gd`,
  finds `test_*` methods via `get_method_list()`, supports `-- --filter=battle`.
* `tests/cases/*.gd` — one file per subsystem.

Four non-obvious rules the harness depends on:

1. **`await process_frame` is the first line of every `_initialize()`.** During
   `_initialize()`, `root` is not really in the tree: right after `root.add_child(n)`,
   `n.is_inside_tree()` is `false` and `n.get_tree()` errors. All three become correct after
   one frame.
2. **`push_error()` alone exits 0.** The harness must track failures itself and pass a code
   to `quit()`.
3. **Every `while` loop in a headless test needs an iteration cap.** This is not paranoia —
   the harness caught a real infinite-walk bug in the grid mover (a consumed input buffer
   that was never cleared) only because a 10,000-iteration guard fired after the character
   had walked **1,399 tiles east**. Without the cap it would have hung CI with no output.
4. **`await inst.call(name)` passes through non-coroutines**, so one runner handles sync and
   async tests with no branching.

Leak warnings at exit (`N RIDs of type "CanvasItem" were leaked`) do not affect the exit
code and are not failures — they mean the script ended with live nodes. Free nodes in
`after_each()`.

---

## 6. Engine modules

### 6.1 Autoloads

The six already declared in `project.godot` are the right set in the right order —
**autoloads initialise top to bottom**, so anything that connects to `EventBus` in `_ready()`
must be declared below it, and `Logger` first lets everything log during boot. Keep
`_ready()` cheap; an autoload that does heavy work slows every test run.

| # | Autoload | Path | Responsibility | Public API |
|---|---|---|---|---|
| 1 | **`Logger`** | `src/autoload/logger.gd` | Levelled logging, per-category filters, ring buffer for the debug overlay. No game state. | `debug/info/warn/error(cat: StringName, msg: String)`, `set_level(cat, lvl)`, `tail(n) -> PackedStringArray` |
| 2 | **`DataRegistry`** | `src/autoload/data_registry.gd` | Owns every immutable content DB. Loads `data/*.res` in `_ready()` (~30 ms total). Read-only after boot. | `species(id) -> SpeciesData`, `move(id) -> MoveData`, `ability(id)`, `item(id)`, `trainer(id) -> TrainerData`, `encounters(key) -> EncounterTable`, `type_mult(atk, def) -> float`, `exp_for(growth, level) -> int`, `caps() -> CapTable` |
| 3 | **`EventBus`** | `src/autoload/event_bus.gd` | **Signals only. No state, no logic.** Keeps the overworld from holding a hard reference to the battle scene and vice versa. Declare typed parameters — 4.7 checks them at emit. | `player_moved(cell)`, `tile_entered(cell, zone)`, `encounter_triggered(zone, band)`, `battle_started(setup)`, `battle_finished(result)`, `map_changed(map_id, spawn)`, `flag_set(flag, value)`, `badge_earned(badge)`, `cap_changed(old, new)`, `dialogue_requested(lines)`, `traversal_used(verb, cell)` |
| 4 | **`GameState`** | `src/autoload/game_state.gd` | **The entire mutable world, and nothing else.** Party, bag, flags, money, playtime, position, RNG seed. Serialises itself. | `party: Array[MonInstance]`, `bag`, `flags`, `badges`, `money`, `to_dict()`, `from_dict(d)`, `set_flag(f, v)`, `has_badge(b) -> bool`, `active_cap() -> int`, `apply_battle_result(r)` |
| 5 | **`SaveSystem`** | `src/autoload/save_system.gd` | Slot I/O via `store_var(v, false)`, magic + version header, atomic tmp-then-rename, full field validation on load. | `save_slot(i) -> Error`, `load_slot(i) -> bool`, `slot_info(i) -> Dictionary`, `delete_slot(i)` |
| 6 | **`SceneRouter`** | `src/autoload/scene_router.gd` | Owns the `Main`-root suspend/resume flow. **Never calls `change_scene_to_*`.** | `load_map(id, spawn)`, `enter_battle(setup)`, `exit_battle(result)`, `push_menu(scene)`, `pop_menu()`, `transition(kind) -> Signal` |

> **`change_scene_to_*` is banned.** It is deferred — immediately after it returns `OK`,
> `get_tree().current_scene` is still `null` — and, worse, it **frees the outgoing scene**.
> NPC positions, open doors, pushed boulders and cutscene progress would all be destroyed on
> every wild encounter. `SceneRouter` instead suspends: `world.process_mode =
> PROCESS_MODE_DISABLED` plus `visible = false` leaves the node fully in the tree with all
> state intact. Returning from a battle is instant, with zero save/restore code to keep
> correct. Cost is one suspended map in memory — 38.8 MB total process for a 200×200 layer,
> irrelevant on any machine that runs Godot 4.

**Scene root layout** (`scenes/Main.tscn`, the only entry in `run/main_scene` after Boot):

```
Main (Node)
├── WorldHolder     (Node)          current map; suspended during battle
├── BattleHolder    (Node)          empty until a battle starts
├── UILayer         (CanvasLayer)   HUD, dialogue box, menus
└── TransitionLayer (CanvasLayer)   fade/swirl ColorRect, always on top
```

### 6.2 Systems (`src/systems/`) — not autoloads

| Class | File | Responsibility | Public API |
|---|---|---|---|
| `CapSystem` | `cap_system.gd` | The level-cap rule. Pure functions over `GameState.flags` + `level_caps.json`. | `active_cap() -> int`, `is_capped(mon) -> bool`, `clamp_exp(mon)`, `can_rare_candy(mon) -> bool` |
| `Traversal` | `traversal.gd` | Maps obstacle type → required badge → verb; runs the verb animation. | `verb_for(obstacle) -> StringName`, `can_pass(obstacle) -> bool`, `perform(verb, cell) -> Signal` |
| `WildEncounters` | `wild_encounters.gd` | Step counter, rate roll, slot-ladder pick, day/night + radar + swarm substitution. | `step(zone) -> bool`, `roll(zone, method) -> MonInstance` |
| `Growth` | `growth.gd` | The 6 EXP curves. | `exp_for(curve, level) -> int`, `level_for(curve, exp) -> int` |
| `TypeChart` | `type_chart.gd` | 18×18 lookup, dual-type product. | `multiplier(atk_type, def_types) -> float` |
| `GameRNG` | `game_rng.gd` | One seeded `RandomNumberGenerator`, seed persisted in the save, so a reload reproduces. | `randi_range`, `chance(pct) -> bool`, `pick(arr)`, `fork(tag) -> GameRNG` |
| `ScriptRunner` | `script_runner.gd` | Executes hand-authored cutscene scripts (§11.1). Coroutine-based. | `run(script_id, ctx) -> Signal`, `register(id, Callable)` |
| `DialogueRunner` | `dialogue_runner.gd` | Text box pacing, page breaks, choices, `\v` variable substitution. | `say(lines) -> Signal`, `ask(prompt, options) -> int` |
| `EntityIndex` | `entity_index.gd` | Cell → entity occupancy for the current map. | `occupied(cell) -> bool`, `at(cell) -> Node`, `register/unregister` |

### 6.3 Data classes (`src/data/`)

`SpeciesData`, `MoveData`, `AbilityData`, `ItemData`, `TrainerData`, `EncounterTable`,
`EvolutionEdge`, `MapData`, `CapTable` — all `extends Resource`, all `@export`ed, all built
by `tools/build_db.gd`. Plus `MonInstance extends RefCounted` — a *live* Pokémon (species,
level, exp, IVs, EVs, nature, moves+PP, status, held item, nickname, OT), which is the only
one of these that is mutable and the only one that appears in a save.

---

## 7. Battle engine

### 7.1 The one architectural decision that matters

**`BattleEngine` is a pure headless `RefCounted`. It owns no nodes, touches no scene tree,
draws nothing, and awaits nothing.** It takes a `BattleSetup`, accepts `BattleAction`s, and
returns an ordered `Array[BattleEvent]` describing everything that happened. The battle
scene is a *player* of that event list.

```gdscript
class_name BattleEngine extends RefCounted

func begin(setup: BattleSetup) -> Array[BattleEvent]
func submit(actions: Array[BattleAction]) -> Array[BattleEvent]   # one turn, fully resolved
func request() -> BattleRequest                                    # what input is needed next
func is_over() -> bool
func result() -> BattleResult
```

```gdscript
class_name BattleEvent extends RefCounted
var kind: StringName     # &"move_used" &"damage" &"faint" &"stat_change" &"status" &"switch"
                         # &"message" &"exp_gain" &"level_up" &"cap_blocked" &"item_used"
var actor: int           # slot index
var target: int
var data: Dictionary
```

Why this is worth insisting on:

* **The entire engine is unit-testable headlessly** — no renderer, no timing, no animation.
  Damage rolls, turn order, status ticks, cap behaviour and the full Roark fight all become
  assertions in `tests/cases/test_battle_*.gd`.
* **Animation timing never influences game logic.** A whole class of "the crit happened
  twice because the tween restarted" bug cannot exist.
* **The AI can search.** Because the engine is a value-semantics object, the AI can `clone()`
  a state and try a move without touching the real battle.
* **Replays and bug reports come free** — a `BattleSetup` + the action list reproduces any
  battle exactly, given `GameRNG`'s persisted seed.

### 7.2 Turn structure

```
1. Request actions      player chooses; AI chooses (may look ahead by cloning)
2. Order actions        bracket, then priority, then effective speed, then RNG tie-break
3. Resolve in order     each action: pre-checks -> accuracy -> damage/effect -> post-hit
4. End of turn          weather -> residuals (Leech Seed, poison, burn) -> abilities -> counters
5. Faint handling       replacements requested, exp awarded (through the cap hook)
6. Win/lose check
```

**Action brackets, highest first:** run / switch / use-item → move. Within the move bracket:
**move priority** (−7…+5) descending, then **effective Speed** descending, then a random
tie-break.

```gdscript
static func effective_speed(m: MonInstance, field: BattleField) -> int:
    var s := m.stat(Stat.SPE)                       # includes nature + EV/IV
    s = int(s * STAGE_MULT[m.stages[Stat.SPE] + 6])
    if m.status == Status.PAR:  s = int(s * 0.25)   # Gen 5 value; Gen 7+ is 0.50
    if field.tailwind[m.side]:  s *= 2
    if m.item == &"choice-scarf": s = int(s * 1.5)
    s = AbilityHooks.speed(m, field, s)             # Swift Swim, Chlorophyll, Unburden…
    return s

static func faster(a, b, field) -> bool:
    var sa := effective_speed(a, field)
    var sb := effective_speed(b, field)
    return sa < sb if field.trick_room else sa > sb   # Trick Room inverts speed, not priority
```

### 7.3 Damage — the Gen 5 formula, explicitly

Gen 4 changed physical/special from per-type to per-move; **Platinum already stores
`category` per move** in byte `0x02` of `pl_waza_tbl`, so the Gen 5 formula is a drop-in.
We use Gen 5 because it is the visual and mechanical target, and because it is the last
generation whose numbers are unambiguously documented in integer form.

```gdscript
# src/battle/damage.gd
const CRIT_MULT := 2.0        # Gen 5. Gen 6+ is 1.5 — one constant to flip.

static func base_damage(atk: MonInstance, def: MonInstance, mv: MoveData, crit: bool) -> int:
    var phys := mv.category == Cat.PHYSICAL
    var a_stat := Stat.ATK if phys else Stat.SPA
    var d_stat := Stat.DEF if phys else Stat.SPD
    # A crit ignores the attacker's NEGATIVE stages and the defender's POSITIVE stages.
    var a_stage := atk.stages[a_stat]
    var d_stage := def.stages[d_stat]
    if crit:
        a_stage = maxi(a_stage, 0)
        d_stage = mini(d_stage, 0)
    var a := apply_stage(atk.stat(a_stat), a_stage)
    var d := apply_stage(def.stat(d_stat), d_stage)
    var lvl := floori(2.0 * atk.level / 5.0) + 2
    return floori(floori(floori(lvl * mv.power * a / float(d)) / 50.0)) + 2
```

Then the Gen 5 modifier chain, in this exact order, in **4096ths** with `poke_round`
(**rounds half DOWN**, unlike normal rounding):

```gdscript
static func poke_round(x: float) -> int:
    return floori(x) if fmod(x, 1.0) <= 0.5 else ceili(x)

dmg = poke_round(dmg * targets / 4096.0)     # 3072 when a move hits >1 target
dmg = poke_round(dmg * weather / 4096.0)     # 6144 water-in-rain / fire-in-sun, 2048 opposite
if crit:
    dmg = poke_round(dmg * CRIT_MULT)
dmg = floori(dmg * GameRNG.randi_range(85, 100) / 100.0)   # 16 discrete rolls
dmg = poke_round(dmg * stab / 4096.0)        # 6144, or 8192 with Adaptability
dmg = floori(dmg * TypeChart.multiplier(mv.type, def.types))
if atk.status == Status.BRN and mv.category == Cat.PHYSICAL and atk.ability != &"guts":
    dmg = poke_round(dmg * 2048 / 4096.0)
dmg = poke_round(dmg * final_mods / 4096.0)  # screens, Life Orb, Expert Belt, Multiscale, Tinted Lens…
dmg = maxi(1, dmg)                            # never less than 1 unless immune (type mult 0)
```

> **GDScript has no ternary `?:` operator** — it is `value_if_true if cond else
> value_if_false`. It also has no `++`/`--` and no `switch`. Writing `a ? b : c` is a parse
> error, which `--check-only` catches for free.

**Write the truncations explicitly.** GDScript `7 / 2` is integer division because both
operands are ints; Pokémon formulas are full of *intentional* truncation at specific steps.
Always `floori()`/`int()` at each truncation point so the intent is visible and matches the
reference.

**Stat calculation** (Gen 3+, used for both sides):

```
HP    = floor( (2*Base + IV + floor(EV/4)) * Level / 100 ) + Level + 10
Other = floor( floor( (2*Base + IV + floor(EV/4)) * Level / 100 + 5 ) * NatureMult )
```

**Accuracy:** `hit = move.accuracy == null or roll(1..100) <= floor(acc * stage_ratio(acc_stages - eva_stages))`.
Stage ratio is 3/3,4/3,5/3,… up, 3/4,3/5,… down.

**Abilities are implemented by hook, not by count.** The useful axis is not "the 60 most
common abilities" (they cover only 59.1% of slots and frequency is a poor proxy for
relevance — the single most common ability across all 1025 is Swift Swim). Implement
`on_switch_in` + a damage-formula multiplier hook + a type-immunity gate and you unlock
**97 distinct abilities behind roughly six hooks**, including Intimidate, all four weather
setters, all four terrain setters, Trace, Download, Levitate, Volt/Water Absorb, Flash Fire,
Overgrow/Blaze/Torrent/Swarm, Huge Power, Adaptability, Technician, Thick Fat and
Multiscale. **16 abilities are battle-inert** (Run Away, Pickup, Honey Gather, Illuminate,
Stench, Ball Fetch) — stub them as no-ops and move on.

### 7.4 Status

**Non-volatile — one at a time, persists out of battle.** Stored on `MonInstance`, saved.

| Status | Effect | Notes |
|---|---|---|
| `BRN` | 1/16 max HP end of turn; **×0.5 physical damage in the formula** (not an Atk stat change) | Fire-types immune; Guts ignores the damage cut |
| `PSN` | 1/8 max HP end of turn | Poison/Steel immune |
| `TOX` | `n/16` escalating; **counter resets on switch-out** (Gen 5 rule) | |
| `PAR` | 25% full-paralysis; **Speed ×0.25** (Gen 5) | **Electric-types are NOT immune in Gen 5** — that arrived in Gen 6. Config constant. |
| `SLP` | 1–3 turns (Gen 5); **counter resets on switch-out** | Insomnia / Vital Spirit immune |
| `FRZ` | 20% thaw per turn; any Fire move or a `defrost`-flagged move thaws | |

**Volatile — cleared on switch.** Confusion (1–4 turns, 50% self-hit for a 40-power typeless
physical in Gen 5), flinch, infatuation, trapping, Leech Seed, Substitute, Protect's
consecutive-use counter, stat stages (−6…+6), Taunt, Encore, Torment, Disable, charge/
recharge states.

### 7.5 The level-cap EXP hook

This is the headline feature, and it lives in exactly one function so it cannot be bypassed.

```gdscript
# src/battle/exp_award.gd
static func award(mon: MonInstance, defeated: MonInstance, participants: int,
                  traded: bool, lucky_egg: bool) -> Dictionary:
    var cap := CapSystem.active_cap()

    # THE RULE: at or above the cap, EXP and EVs are both zero. Not reduced — zero.
    if mon.level >= cap:
        EventBus.cap_blocked.emit(mon, cap)
        return { "exp": 0, "evs": PackedInt32Array([0,0,0,0,0,0]), "capped": true }

    # Gen 5 scaled EXP formula
    var b := float(DataRegistry.species(defeated.species).base_exp)
    var le := float(defeated.level)
    var lp := float(mon.level)
    var e := (b * le / 5.0) * (1.0 / participants) \
           * pow(2.0 * le + 10.0, 2.5) / pow(le + lp + 10.0, 2.5) + 1.0
    if traded:    e *= 1.5
    if lucky_egg: e *= 1.5
    var gained := int(e)

    mon.exp += gained
    var curve := DataRegistry.species(mon.species).growth_rate
    while mon.level < cap and mon.exp >= Growth.exp_for(curve, mon.level + 1):
        mon.level_up()                                    # evolution checks fire here
    mon.exp = mini(mon.exp, Growth.exp_for(curve, cap))   # clamp: cap is a hard ceiling
    mon.gain_evs(DataRegistry.species(defeated.species).ev_yield)
    return { "exp": gained, "capped": false }
```

Rules that go with it, all from `game-design.md §2.7`:

* **Zero EV gain as well as EXP** at or above the cap, or the cap becomes a soft cap you can
  farm around.
* **Rare Candy / Exp Candy refuse to apply** at or above the cap.
* **Day-care EXP is zeroed** at or above the cap.
* **A traded-in over-cap Pokémon has its EXP gain clamped to zero.** Obedience stays a
  separate, badge-gated system so a trade-in cannot bypass the cap.
* **Evolution is NOT capped.** A Pokémon that evolves *at* the cap level still evolves; only
  EXP is zeroed.
* **Surface it.** Party and summary screens read `Lv.14 (CAP)` in a distinct colour, and the
  battle EXP bar must visibly not move. A silent cap reads as a bug.

### 7.6 Trainer AI

`aiMask` from `trdata` is carried through: `0x7` is the common case, `0xF` marks the smarter
bosses (Lucian is the only Elite Four member with `0xF`). Implement three tiers:

* **Tier 0 (`aiMask & 1`)** — random legal move. Early route trainers.
* **Tier 1 (`0x7`)** — score moves by expected damage × type multiplier, prefer status when
  the target is healthy, avoid immunities. Every E4 member carries 2 Full Restores, Cynthia
  4; item usage triggers below 50% HP.
* **Tier 2 (`0xF`)** — Tier 1 plus one-ply lookahead using `BattleEngine.clone()`, plus
  switch evaluation.

---

## 8. Overworld

### 8.1 Scene layout

```
Map (Node2D, y_sort_enabled = true)
├── Ground     (TileMapLayer, z_index=-10, y_sort=false)
├── Decor      (TileMapLayer, z_index= -5, y_sort=false)
├── Objects    (TileMapLayer, z_index=  0, y_sort=true)    trees, signs, ledges
├── Entities   (Node2D,       z_index=  0, y_sort=true)    player + NPCs
├── Overhead   (TileMapLayer, z_index= 10, y_sort=false)   bridge decks, roofs
└── Logic      (TileMapLayer, visible=false)               imported collision/behaviour
```

> **Y-sort gotcha: a layer's `y_sort_enabled` does nothing unless every ancestor up to the
> sorting root also has it enabled.** Set it on `Map`, `Objects` **and** `Entities`, then
> tune per-tile pivots with `TileData.y_sort_origin` (for a 16 px tile whose trunk sits at
> the bottom edge, `y_sort_origin = 8` sorts the tree by its trunk, not its canopy).
> This is the most likely place for a visual surprise — it was verified only at the API
> level, never rendered.

### 8.2 TileSet custom data layers

```gdscript
const CUSTOM_DATA := {
    "solid":      TYPE_BOOL,
    "water":      TYPE_BOOL,
    "grass":      TYPE_BOOL,          # triggers encounter rolls
    "ledge_dir":  TYPE_VECTOR2I,      # ZERO = not a ledge
    "obstacle":   TYPE_STRING_NAME,   # &"" &"smash" &"cut" &"strength" &"climb" &"waterfall"
    "zone":       TYPE_STRING_NAME,   # encounter table key
    "warp":       TYPE_INT,           # index into MapData.warps, -1 = none
    "surface":    TYPE_STRING_NAME,   # footstep sound + dust
}
```

### 8.3 Grid movement

**Manual lerp in `_process`, with the overshoot carried into the next step.** Not `Tween`
(cannot be cleanly cancelled or redirected mid-step, and chaining loses the leftover frame
time so held-down running visibly stutters every tile). Not `CharacterBody2D`
(float drift, wall-sliding you never want, fighting the physics tick to stay tile-aligned).

Two lines in `GridMover.tick()` are load-bearing:

* **`_elapsed = over`** — the overshoot carry. Without it every tile boundary discards up to
  one frame, so a held run loses ~1 frame per tile and visibly hitches. With it, 40 tiles
  under randomised frame times between 4 ms and 50 ms land on **exactly 656 px = 41 × 16**,
  `position.y == 0.0`, zero accumulated error.
* **`_buffered = Vector2i.ZERO`** — clear the input buffer after consuming it. The first
  version did not, and the mover chained off the stale buffer forever. See §5.

The buffer holds **exactly one** queued direction, refreshed each frame while `MOVING` —
release the d-pad mid-step and you complete the current tile plus the buffered one, then
stop. Do not build a deeper queue; a 3-deep buffer reads as input lag.

Collision is an injected `Callable` against tile custom data — free (0.363 µs), exact, and
headlessly testable by injecting `m.solid = func(c): return c == Vector2i(1,0)`.

Keep `2d/snap/snap_2d_transforms_to_pixel=true` from `project.godot`: it snaps the
*rendered* transform to whole pixels while leaving the logical float `position` untouched, so
the sprite never shimmers and the drift-free maths still works on exact values. **Do not
round `position` yourself** — that reintroduces the very accumulation error the overshoot
carry exists to prevent.

> **Feel constants are placeholders.** `walk_time 0.24 s`, `run_time 0.12 s`,
> `turn_time 0.08 s` are plausible, not measured against DS Platinum. If DS-accurate feel
> matters, frame-count a DeSmuME capture and derive them.

### 8.4 Badge-gated traversal — the HM replacement

**Principle: no HM items exist, no move slots are consumed, no HM slave exists.** Each
*badge* grants a **traversal verb** the player performs automatically on walking into the
matching obstacle. The obstacle is a property of the map, not of the party.

```gdscript
func _on_bump(cell: Vector2i) -> void:
    var obstacle: StringName = Logic.get_cell_tile_data(cell).get_custom_data("obstacle")
    if obstacle == &"":
        return                                   # ordinary wall: turn, don't move
    if not Traversal.can_pass(obstacle):
        return                                   # no badge yet: same bump, no message spam
    await Traversal.perform(obstacle, cell)      # animation; then the step completes
    _begin_step(facing, false)
```

| Obstacle | Verb | Badge | Player-facing behaviour |
|---|---|---|---|
| cracked rock | `smash` | Coal (1) | Walk into it. Shatter + screen shake; player steps through on the same input. Respawns on map reload. |
| cuttable tree | `cut` | Forest (2) | Walk into it. Slash, tree falls, player continues. |
| deep-water edge | `surf` | Fen (5) | Walk into the shoreline. Mount a Gen-5-style water mount; dismount into land. Wild encounters use the surf table. |
| push-boulder | `strength` | Mine (6) | Walk into it. Boulder slides one tile. **Puzzle geometry is untouched** — only the party check is removed. |
| climbable rock face | `climb` | Icicle (7) | Walk into the chevron tile; ascend/descend at climb speed. Interruptible by wild encounters, as in vanilla. |
| waterfall (while surfing) | `waterfall` | Beacon (8) | Swim into the base and ascend; descend from the top ledge. |
| Fly destinations | `fly` | Cobble (4) | A **MAP** menu entry, not a move. See below. |
| fog | — | — | **Deleted globally.** No fog weather state, no visibility overlay, no accuracy modifier, no DEFOG verb, no obstacle type. |

**Fly is a menu, not a move.** The Cobble Badge adds a **MAP** entry to the main menu. Any
town whose Pokémon Center the player has *entered at least once* is selectable; the landing
point is that Center's door. Blocked inside dungeons, buildings and scripted sequences —
except a dedicated **ESCAPE** option that returns you to the current dungeon's entrance,
folding Escape Rope into the same UI. The unlock flag is "Center visited", not "map tile
exists", so **Fly can never reach content the story has not opened.**

**Fog deletion is safe** because fog never gated progress in vanilla D/P/Pt — it reduced
draw distance and lowered accuracy, but every fogged tile was walkable. The real gate on
Route 210 north is the **Psyduck blockade**, cleared with the **Secret Potion** story item,
and that stays exactly as it is. The consequence is honest: **the Relic Badge is the one
badge with no movement unlock**, exactly as its vanilla HM gated nothing. What it does grant
is the cap raise 26→32, the obedience tier bump, and the Route 209 / Solaceon story flag.

**The soft-lock proof holds because the bindings are 1:1 with vanilla.** Vanilla Platinum's
badge order is already a topological sort of the obstacle graph. Three facts carry the
proof and must not be changed:

1. **SMASH at badge 1 vs. Ravaged Path.** Ravaged Path is the **first mandatory HM gate in
   the whole game** and sits immediately after Roark. If a Rock Smash rock is ever moved
   earlier than Oreburgh Gym, that is the one place a soft-lock can appear.
2. **SURF at badge 5 (Fen); the first mandatory deep water is Route 218**, on the way to
   badge 6. Celestic Town — vanilla's source of HM Surf — is reachable on foot via Route 210
   north, so removing the HM item removes the dependency entirely.
3. **STRENGTH at badge 6 (Mine); the first mandatory boulder is Mt. Coronet north**, on the
   way to badge 7. Iron Island is visited before Byron, but its escorted critical path needs
   no boulders — exactly as in vanilla, where Riley hands you an HM you cannot yet legally
   use.

**Two gating facts corrected against the ROM's own collision data** (BFS over `land_data` +
`zone_event`, brute-forced over all 32 HM subsets):

* **Mt. Coronet — confirmed exactly.** North passage (Route 211A → Route 216) needs
  **STRENGTH + SMASH**. The summit from the Route 207/208 entrance needs
  **SURF + STRENGTH + CLIMB**. Surf is *entrance-specific*: from the Route 211 entrance the
  summit needs STRENGTH + SMASH + CLIMB instead. So the invariant is **STRENGTH + CLIMB on
  every summit route**, plus SURF or SMASH depending on which door you came in.
* **Victory Road gates nothing — the wiki is wrong.** The mandatory traversal (south
  entrance, map 244 tile 15,78 → north exit tile 34,5) has a **139-step walking path
  entirely on 1F needing no HM at all**, and it is genuinely mandatory (the League door is
  reachable from the north exit but not from the south entrance even with all five HMs).
  Map 244 contains zero boulders, zero rocks and no water; every obstacle is on optional side
  maps 245/246/247. Only the Route 224 back exit needs anything, and **SURF or STRENGTH
  alone suffices**. Robust under ledges-impassable and all-objects-block variants.

  **Consequence worth knowing before spending art budget: WATERFALL now gates nothing
  mandatory in the entire game.** It survives on flavour and on optional loops.

### 8.5 Map construction — import the logic, paint the art

This is what makes the schedule in §9 realistic, and it deserves stating loudly.

**You cannot auto-generate the art** (§3.5 — the source is 3D geometry). **You can
auto-generate everything else**, and everything else is most of the work:

`tools/extract_platinum.py --maps` walks the 593 map headers → map matrices → `land_data`
chunks → `zone_event` files and emits, per map, a complete `MapData` JSON containing:

* the assembled **walkable/blocked grid** (high byte `0x80`),
* the **behaviour grid** translated into `water` / `waterfall` / `ledge_dir` / `climb`
  custom data,
* every **warp** with its destination header and reciprocal index (reciprocals verified),
* every **NPC, trainer, sign and step trigger** with position, facing, graphics id and
  script id,
* every **obstacle** (Cut tree / Smash rock / Strength boulder) by script+graphics id,
* the **encounter table key** and the **display name**, both resolved from the header.

`tools/build_maps.gd` then emits `scenes/maps/<id>.tscn` with the `Logic` layer fully
populated and the `Ground`/`Decor`/`Objects` layers **empty**. A human paints art over a map
that is already correct. That is a fundamentally cheaper job than authoring a map from
scratch, and it means the collision, warp graph and event placement of all of Sinnoh are
*imported*, not hand-entered.

Evidence this works: the same walk was already run end-to-end in the verification pass —
BFS over tiles + warps with ledges as one-way 2-tile jumps and obstacles gated on HMs,
reaching **182 of 228 multi-warp maps fully connected** (the residual disconnects are
script-teleport maps: PC 2F, gym interiors, the Galactic HQ teleporters), with zero leakage
into the empty "void" chunk area.

> **`PackedScene.pack()` silently drops children without an `owner`.** Every descendant
> built in code needs `child.owner = scene_root` before `pack()`, or you save an empty scene
> with no error.

### 8.6 Encounters

Step on a `grass` (or `water`) tile → `WildEncounters.step(zone)` → on a hit, roll the slot
ladder `20,20,10,10,10,10,10,10,5,5,4,4`, apply day/night substitution into slots 2–3, Poké
Radar into 4/5/10/11 and swarm where active, then instantiate from the **`curated`** table
with the vanilla level band.

> **Open item:** the exact DPPt step-rate maths (how `landEncounterRate` converts to a
> per-step probability) is **not decoded** — it lives in overlay006. Ship a tuned placeholder
> (`chance = rate / 2.56` per step on encounter terrain) behind one constant, and replace it
> if it ever feels wrong. This is a feel parameter, not a correctness one.

---

## 9. The phased build order

**Honest framing first.** Sinnoh is 593 map headers, 666 land-data chunks, 468 live
overworld cells, 928 trainers, 183 encounter tables and 724 text banks. **It cannot be
hand-built in one sitting, or in ten.** The plan below is arranged so that a *playable,
complete-feeling vertical slice* — Twinleaf to the Oreburgh Gym, with real battles, real
caps and real traversal — exists at the end of Phase 5, and everything after it is
**repetition of a solved process**, not new engineering.

The one thing that makes this tractable is §8.5: the collision, warp graph, event placement
and encounter wiring of *every* map are **imported from the ROM**, not authored. The
irreducible hand work is painting art layers and writing story scripts.

Estimates are in **sessions** — a focused working block, not a calendar day. They are the
author's estimates and they are the least reliable numbers in this document.

---

### Phase 0 — Make the repo boot and CI go green · *1 session*

The project currently **cannot boot**: `project.godot` declares six autoloads whose script
files do not exist, and `.godot/global_script_class_cache.cfg` reads `list=[]`. Every
headless run logs six autoload errors and still exits 0 — so if CI is wired up before this
is fixed, **it will report green on a broken project.**

* Create all six autoload stubs under `src/autoload/` with real but minimal bodies.
* Copy the proven test harness out of gitignored scratch into `res://tests/`:
  `run_tests.gd`, `test_case.gd`, and `cases/test_grid_mover.gd` + `cases/test_tileset_codegen.gd`.
  **These files exist only in `tools/_work/godottest/` and will not survive a clean
  checkout.**
* Add `tools/run_tests.sh`: `--import`, assert `global_script_class_cache.cfg` is non-empty,
  then `--script res://tests/run_tests.gd`.
* Add a pre-commit hook running `--check-only` over changed `.gd` files.
* Add a disk preflight to every bulk tool (`shutil.disk_usage`, refuse under 2 GB).
  Disk is currently fine — **24 GB free** — but bulk extraction already ran a machine to
  zero once this project.

**Exit criteria:** `tools/run_tests.sh` exits 0, the class cache is non-empty, and
`git status` is clean of generated files.

---

### Phase 1 — The extraction toolchain · *2–3 sessions*

Turn research scripts into production tools. The format knowledge is settled; the code is
not — it is research-grade and lives in a gitignored directory.

* `tools/ndslib/` — `nds.py` (FNT/FAT), `narc.py`, `lzss.py` (LZ10/LZ11), `nitro.py`
  (NCLR/NCGR/NCER/NANR/NSCR), `nsbtx.py` (TEX0, all 7 formats), `text.py` (the bank
  decryptor + charmap + the `0xF100` 15-bit unpacker).
* `tools/extract_platinum.py` with subcommands `--species --moves --items --trainers
  --encounters --maps --text --evo-diff`, writing `data/rom/*.json` and `data/rom/maps/*.json`.
* `tools/fetch_external.py` — curl the 27 veekun CSVs, the 4,100 BW sprites (8-thread pool,
  **never** a sparse clone), and pokesprite's gen8 icons.
* `tools/build_species_json.py` — the veekun normalizer, **with the completeness assertion
  that fails the build on any incomplete species.**

**Ten traps to encode as tests, not comments:** path-not-file-ID addressing; the 4-byte
trpoke padding (927/927 vs 43 failures); 593 map headers not 596; the `0xF100` 15-bit
accumulator; `pl_`-prefixed files only (except `wotbl`/`evo`/`trdata`/`trpoke`, which have
no `pl_` twin); personal stat order HP/Atk/Def/**Speed**/SpA/SpD; water encounters storing
max before min; `0xFFFF` encounter index meaning "none" (439 of 593 headers); the `champions`
version-group trap; veekun's `""`-vs-`"0"` accuracy encoding.

**Exit criteria:** every tool is re-runnable from a clean checkout, `data/` + `data/rom/` JSON validates,
and `tests/cases/test_extract_*.gd` asserts the counts (508/928/183/666/593/724).

---

### Phase 2 — Data into Godot · *1–2 sessions*

* `src/data/*.gd` Resource classes.
* `tools/build_db.gd` — JSON → `data/*.res`, doing **every `int()` cast exactly once**.
* `DataRegistry` loads them in `_ready()`.

**Exit criteria:** boot loads 1,025 species + 919 moves + 314 abilities + the 18-type chart
in **under 50 ms**, `tests/cases/test_data_registry.gd` spot-checks Turtwig's stats,
Garchomp's typing, `fairy→dragon == 2.0`, and `ghost→steel == 1.0`, and every integer field
returns `TYPE_INT`.

---

### Phase 3 — The battle engine, headless · *4–6 sessions* · **the biggest engineering block**

No scene, no sprites, no animation. Pure `RefCounted` + tests.

1. `MonInstance`: stats, natures, IV/EV, moves + PP, status, held item.
2. `BattleEngine.begin/submit/request` and the `BattleEvent` list.
3. Turn order: brackets, priority, effective speed, Trick Room, random tie-break.
4. Damage: the Gen 5 formula with `poke_round`, crit stage handling, STAB, type, burn.
5. Status: all six non-volatile plus confusion, flinch, stat stages, Protect.
6. **The level-cap EXP hook** — and its tests, first-class. Test that a L14 mon at cap 14
   gains **zero** EXP *and* **zero** EVs; that a L13 mon levels *into* 14 and stops; that
   Rare Candy refuses; that a mon evolving at the cap still evolves.
7. Ability hooks: `on_switch_in`, the damage multiplier, the type-immunity gate (≈97
   abilities behind six hooks).
8. AI tiers 0 and 1.

**Exit criteria:** `tests/cases/test_battle_*.gd` runs the **full Roark fight** (Geodude 12,
Onix 12, Cranidos 14) against a scripted L12–14 party to a deterministic result with a fixed
RNG seed, and the cap suite passes. No renderer involved.

---

### Phase 4 — Art pipeline · *2–3 sessions*

Runs in parallel with Phase 3 if two people are working; otherwise here, because Phase 5
needs its output.

* `fetch_external.py` pulls the 4,100 BW sprites (3.83 MB) and pokesprite icons.
* `extract_gen5_art.py` decodes + dedupes White 2 `/a/0/1/4` into
  `assets/tilesets/lib/<name>.png`, and pulls VS portraits from `/a/2/6/7` and the 32
  overworld character sets from `/a/0/3/1`.
* **Hand-compose one atlas: the Route 201 / Sandgem / Jubilife biome.** Grass, path, cliff,
  water edge, tree, fence, house wall, roof, door, sign, ledge.
* `build_tilesets.gd` → `.tres`, obeying the custom-data ordering trap and the
  `load()`-don't-`create_from_image()` rule.

**Exit criteria:** `--import` succeeds, one TileSet loads with all custom-data layers
reading back correctly, and 1,025 front sprites render in a contact sheet.

---

### Phase 5 — The vertical slice: Twinleaf → Oreburgh Gym · *3–5 sessions*

**This is the milestone that proves the whole design.** Twelve maps, one badge, one cap tier,
one traversal verb, plus the Ravaged Path gate immediately past the gym to prove the verb
system end to end.

Maps (all logic **imported**, art hand-painted): Twinleaf Town (+ 2 interiors), Route 201,
Lake Verity, Sandgem Town (+ lab), Route 202, Jubilife City (+ 2 interiors), Route 203,
Oreburgh Gate 1F/B1F, Oreburgh City, Oreburgh Mine, **Oreburgh Gym**, Route 204 south,
**Ravaged Path**.

Systems to finish:
* `Main.tscn` + `SceneRouter` suspend/resume, transitions.
* `GridMover` + player controller + NPC movement + `EntityIndex`.
* Warps, ledges, encounter triggering, day/night substitution.
* Battle **scene**: the `BattleEvent` player, HUD, menus, sprite display, the cap-aware EXP
  bar that visibly does not move at cap.
* Dialogue box, party menu, bag, summary screen with `Lv.14 (CAP)` rendering.
* `ScriptRunner` + the ~15 hand-authored story scripts this stretch needs (Rowan's
  briefcase, the rival on Route 201, the Pokédex hand-off, the catching tutorial, the
  Jubilife Galactic grunts, the Oreburgh Mine Roark fetch, the gym).
* Save/load a real game.
* SMASH verb, badge grant, cap raise 14 → 22.

**Exit criteria — all of these, demonstrated in a real windowed run:**
walk Twinleaf → Oreburgh Gym; catch a Starly on Route 201; win the rival fight; beat Roark;
observe the party stop gaining EXP at exactly L14 before the badge and resume after it;
smash the Ravaged Path rocks with no party-member check and no HM item anywhere in the bag;
save, quit, reload, and be exactly where you were.

**Do not start Phase 6 until every one of those passes.** Everything after this is the same
work repeated.

---

### Phase 6 — Sinnoh build-out · *the long tail — plan it as a queue, not a sprint*

**Be honest: this is where the remaining 90% of the calendar goes, and almost none of the
remaining engineering.** Roughly 40 more outdoor areas plus interiors, 7 more gyms, 9
Galactic fights, 6 more rival fights, the Elite Four, ~900 trainers and ~170 more encounter
tables.

Work it as a repeatable per-area loop, one area at a time, each fully finished before the
next:

1. `extract_platinum.py --maps <header_ids>` → logic imported.
2. Compose or reuse the biome atlas; paint Ground / Decor / Objects.
3. Wire the area's trainers (already extracted) and its `curated` encounter table.
4. Author its story scripts.
5. **Play it.** Add a regression test for anything that broke.

Sequence it in the vanilla progression order from `game-design.md §1` — that order is
already a topological sort of the obstacle graph, so following it means **traversal verbs
land exactly when their first mandatory obstacle does, and the soft-lock proof stays valid
by construction.** The milestones that matter, because each unlocks a verb and a cap tier:

| Milestone | Unlocks | Cap becomes |
|---|---|---|
| Floaroma → Valley Windworks → **Eterna Gym (Gardenia)** | CUT | 26 |
| Galactic Eterna Building (**must stay behind Cut**) → Cycling Road → **Hearthome Gym (Fantina)** | — | 32 |
| Solaceon → **Veilstone Gym (Maylene)** | FLY (map menu) | 37 |
| Pastoria → **Pastoria Gym (Crasher Wake)** | **SURF** — the big one, unlocks all water | 41 |
| Celestic → Route 218 → **Canalave Gym (Byron)** | STRENGTH | 44 |
| Mt. Coronet north (**SMASH + STRENGTH**) → **Snowpoint Gym (Candice)** | CLIMB | 50 |
| Galactic HQ → Mt. Coronet summit (**STRENGTH + CLIMB** + SURF/SMASH by entrance) → Spear Pillar → Distortion World → **Sunyshore Gym (Volkner)** | WATERFALL | 53 |
| Route 223 → Victory Road (**gates nothing**) → **Elite Four → Cynthia** | — | 55/57/59/62 |

The ~40 areas beyond the first eight still need `game-design.md §4.3`'s per-slot curation
treatment; §4.4 of that doc gives the biome-reservation rules to work from (Steel/Ground/
Fighting held for Mt. Coronet south and Route 207; Ice for Routes 216/217; Dragon and the
pseudo-legendaries for Victory Road and Routes 224–230).

---

### Phase 7 — Post-game and polish · *after the credits roll*

Fight/Survival/Resort Areas, Stark Mountain, Turnback Cave, Snowpoint Temple, the rematch
ladder, uncapped levels. Plus: animated sprites as an optional upgrade, audio (SDAT
extraction — note the two sound banks are 7.5–7.9 MB each), and visual regression tests
against DeSmuME captures if that ever matters.

### Phase dependency graph

```
 P0 boot/CI ──► P1 extraction ──► P2 data ──► P3 battle ─┐
                     │                                    ├──► P5 vertical slice ──► P6 build-out ──► P7 post-game
                     └──────────► P4 art ─────────────────┘
```

P3 and P4 are independent of each other. Everything else is strictly serial.

---

## 10. Where this document overrides the research docs

Three published claims were proven wrong against real bytes during verification. The
research docs have been **edited in place with dated correction notes**; this is the index.

| Claim | Verdict | Where corrected |
|---|---|---|
| White 2 `/a/2/9/1` is the larger overworld-NPC archive (236 pairs of plain NCGR/NCLR, 64/128 px part strips, missing NCER) | **WRONG on identity and on four structural details.** It is trainer-class battle art (64.3% byte-identical tiles with `/a/0/7/1`); 171 live sets not 236; LZ10-compressed; 256×32 raster; two pixel clusters not four bands; 256-slot palettes with only sub-palette 0 used; no NCER exists to find (3 hardcoded OAM objects in code); B2W2-exclusive | `gen5-assets.md §2`, §7 table |
| veekun lacks Showdown's `wind, slicing, bypasssub, bludgeon, metronome` flags | **WRONG on two.** `bludgeon` is not a Showdown flag at all (0 occurrences). veekun *has* `bypasssub` as `authentic` — proven by 75/75 exact move-set equality. Genuinely missing: `wind`, `slicing`, `cantusetwice` — **none of which exist in Gen 4** | `species-data.md §8` |
| Victory Road requires Surf + Strength + Rock Smash + Waterfall + Rock Climb | **WRONG.** The mandatory through-route needs **no HM** — a 139-step walk on 1F. Every obstacle is on optional side maps. Only the Route 224 back exit needs anything (Surf **or** Strength). Mt. Coronet's requirements, by contrast, are confirmed exactly | `game-design.md §1, §3, §3.2, §3.5, App. B` |

Also confirmed and load-bearing, so they are restated here rather than left in footnotes:
the ARM9 map-header offset is **language-specific** (`0xE601C` English, `0xE56F0` Japanese,
plus ES/IT/FR/DE values); the Gen 6–9 sprites originate from the Smogon Sprite Project and
are already ingested by PokeAPI, so scraping Smogon is unnecessary; **Fantina is gym 3 in
Platinum**; Platinum **swaps Relic and Fen** relative to D/P; **Ravaged Path is the first
mandatory HM gate in the game**; and **Surf is not required before the badge that grants
it.**

---

## 11. Top risks and mitigations

### 11.1 Script bytecode is not decoded — **the largest schedule risk**

`scr_seq.narc`'s container format is verified (relative `u32` offset table, `0xFD13`
terminator, 1,124 files) but the `u16` opcode semantics are **not**. Platinum's command
table is large and game-specific, and every cutscene, gym gate, HM check and story trigger
lives in it.

**Mitigation: do not decode it. Author story scripts natively instead.** `zone_event`
already gives us *where* every script fires and *which* script id fires there — that is the
expensive, error-prone half, and it is already extracted. Write the ~250 story beats as a
small GDScript coroutine DSL (`ScriptRunner`, §6.2) keyed by the ROM's own script ids:

```gdscript
Scripts.register(231, func(ctx): 
    await ctx.face(&"rowan")
    await ctx.say(TEXT.rowan_briefcase)
    await ctx.choose_starter()
    ctx.set_flag(&"got_starter"))
```

This turns an open-ended reverse-engineering problem into bounded content work, and it lets
the remake's story diverge where the design wants it to (deleted HM gifts, new TM rewards).
Budget it as **content, one script per beat**, inside Phases 5 and 6.

### 11.2 The other nine

| # | Risk | Mitigation |
|---|---|---|
| 2 | **Gen 5 sprite extraction is not a dump.** No flat sprite exists; the composer is ~90% right with unresolved node-offset semantics; the form-index→dex table lives in a BLZ-compressed, signed White 2 overlay. If the plan assumed "650 PNGs in an afternoon", that assumption is wrong. | **Sidestepped entirely** (§3.4). Download PokeAPI's complete 1025-species BW set (3.83 MB). Write the composer only if animated *trainer* sprites become a requirement, and point it at `/a/0/7/1`. |
| 3 | **Neither ROM is a 2D tilemap game.** No tileset, no tilemap, in BW *or* HGSS. Any plan that expected a ready-made tileset must be rewritten. | Extract the *texture library* (White 2 `/a/0/1/4`, 16×16-dominant, 3,998 names) and **author maps in Godot** — but import every map's collision, warps, events and encounters from `land_data` + `zone_event` (§8.5), which is the bulk of the work. |
| 4 | **Map art is the true long pole** — ~40 outdoor areas plus interiors, and it cannot be automated. | Phase the build (§9) so a complete slice ships first; then work one area at a time, fully finished, in vanilla progression order. Reuse biome atlases aggressively — Sinnoh has perhaps eight distinct biomes, not forty. |
| 5 | **Sprite licence is not clean.** No LICENSE on `PokeAPI/sprites`; Gen 6–9 are Smogon fan art of trademarked characters. | Personal, non-distributed, non-commercial use only. Credit the Smogon Sprite Project. Keep every sprite gitignored. `msikma/pokesprite` (MIT) for icons 1–905. **Do not monetize or redistribute.** |
| 6 | **Silent data corruption** — Godot floats every JSON number; TileSet custom data written before `add_source` reads back as the type *default*, not an error; the `champions` version group hands 44 species an empty movepool with no warning. | Every `int()` cast happens once in `build_db.gd`; the tileset ordering has a regression test; the completeness assertion **fails the build** rather than shipping empty movepools. All three are tests, not conventions. |
| 7 | **Level-cap headroom is only +1** at the Pastoria rival fight and **+2** at the Distortion World Cyrus fight. Any upward boss rebalance, or a switch to boss-ace-minus-one caps, breaks the guarantee. | Keep `game-design.md §2.6` as an executable test over `data/rom/trainers.json` × `data/level_caps.json`: assert every mandatory fight's ace ≤ the cap in force. Run it in CI so a roster edit cannot silently create an unwinnable fight. |
| 8 | **Alternate-form indexing is unresolved on the ROM side.** `pl_personal`/`wotbl`/`evo` have 508 entries for 493 species; which of the 15 extras is Wormadam-Sandy vs Giratina-Origin is unenumerated. `pl_otherpoke` has a non-uniform layout with no arithmetic rule. | **Avoided by source choice:** stats, learnsets and evolutions come from **PokeAPI**, which is form-explicit and dex-keyed. ROM personal data is a cross-check only. The `is_default = 1` filter on `pokemon.csv` (1,351 rows vs 1,025 species) is mandatory or Mega stats blend into base species. |
| 9 | **Environment fragility** — the Anaconda PATH fix is per-shell and breaks `ssl` *and* PIL; Git Bash mangles `/a/0/0/4` into a Windows path (`MSYS_NO_PATHCONV=1`); disk hit zero bytes free twice during research. | Every Python tool sets its own PATH at import and asserts PIL loads. Every bulk tool runs a `shutil.disk_usage` preflight. `curl` does all downloading so `ssl` stays off the critical path. Currently **24 GB free**. |
| 10 | **Parallel agents clobber each other.** `ndsfs.py` was overwritten mid-session and a parser was lost; generic names (`nds.py`, `narc.py`, `gfx.py`) collide. | Production code goes in `tools/ndslib/` under version control. **Scratch goes in `tools/_work/<task>/`, never in `tools/_work/` directly.** |

### 11.3 Smaller, tracked, not blocking

* **Y-sort was verified only at the API level** — whether the player renders behind the
  correct half of a tree needs a windowed run. Most likely place for a visual surprise.
* **No visual regression path exists.** Headless has no renderer
  (`DisplayServer.get_name() == "headless"`); pixel-diffing against DeSmuME captures needs
  `--rendering-driver opengl3` in a real window or an offscreen `SubViewport`.
* **`TileMapLayer` rendering at scale is unmeasured** — only data-side costs were. Many
  layers + animated water + Y-sort may behave differently from the 40,000-cell benchmark.
* **Movement feel constants are placeholders**, not derived from DS frame timing.
* **The DPPt step-encounter-rate maths is undecoded** (overlay006) — shipped as a tuned
  constant.
* **Two `encdata_ex.narc` files are unidentified** (file 1, 1,068 B; file 11, 144 B). If
  either drives Poké Radar chaining or swarm scheduling, it needs separate work.
* **Non-US ROMs are unverified.** All non-English ARM9 offsets come from DSPRE only. If a
  non-US build is ever targeted, **re-derive by fingerprint** rather than trusting them.
* **The ARM9 is uncompressed in *this* dump**, which is why `0xE601C` is readable by raw
  scan. A differently-packed dump may ship a BLZ-compressed ARM9. The extractor should
  **detect** (`ModuleParams.compressed_static_end == 0`) rather than assume.
* **`land_data`'s objects section and the BDHC height mesh are undecoded** — sizes and
  boundaries verified, contents not. Only needed for 3D reconstruction, which we are not
  doing.
* **The BIOS RLE routine (0x30) is written but unverified** against a genuine asset; a scan
  of three ROMs found only false positives. These games appear not to use it for graphics.
  Do not build a pipeline that depends on it.
* **NSCR's colour-mode/screen-format fields** at `+0x0C`/`+0x0E` are unverified in meaning;
  the renderer derives everything from width/height and the NCGR instead, which may break on
  affine/extended BG modes.

---

## 12. Decision summary

| Question | Decision | Because |
|---|---|---|
| Engine | Godot 4.7.2, GL Compatibility, 256×192 | measured; TileMapLayer + headless tests + 26 ms data load |
| Language | GDScript, statically typed | typing is 1.20×, not 2× — type for correctness, not speed |
| Tooling | Python 3.8.3, stdlib + PIL | format knowledge already exists as self-testing Python; no Node here |
| Pokémon sprites | **Download** PokeAPI BW set (1025, 3.83 MB) | ROM has no flat sprite; composer unsolved; form index ≠ dex |
| Icons | `msikma/pokesprite` gen8 (MIT), 1–905 | ROM icon palette index is not in the NARC |
| Tiles | White 2 `/a/0/1/4` texture library → hand-composed atlases | 16×16-dominant, PAL16, 3,998 names; HGSS is 32×32 |
| Maps | **Import logic from `land_data` + `zone_event`; paint art by hand** | the 3D geometry can't be converted, but collision/warps/events can |
| Species data | PokeAPI veekun CSVs, pinned SHA | only bulk + plain-text + complete + runtime-free source |
| Type chart | modern Gen 6+ 18-type incl. Fairy | 324/324 vs Showdown; nine generations of species need it |
| Runtime data | one binary `.res` of `Array[SpeciesData]` | 26 ms vs 6,301 ms for per-file JSON |
| Save format | `FileAccess.store_var(v, false)` | preserves `int`; refuses Objects; `ResourceLoader` is demonstrated RCE |
| Overworld ↔ battle | persistent `Main` root, suspend with `PROCESS_MODE_DISABLED` | `change_scene_to_*` frees the world and is deferred |
| Movement | manual lerp in `_process` with overshoot carry | exact to the pixel over 40 jittered tiles |
| Collision | tile custom data + injected `Callable` | 0.363 µs, exact, headlessly testable, ledges are trivial |
| Battle engine | pure headless `RefCounted` returning a `BattleEvent` list | testable, replayable, AI can search, animation can't corrupt logic |
| Damage | Gen 5 formula, 4096ths, `poke_round` half-down | Platinum already stores per-move category |
| Caps | cap = next checkpoint boss's ace; **zero EXP and zero EVs** at cap | every mandatory fight verified at or under the cap in force |
| HMs | deleted; badges grant traversal verbs 1:1 with vanilla bindings | vanilla badge order is already a topological sort of the obstacle graph |
| Fog | deleted globally; Relic Badge grants no verb | fog never gated progress; the Psyduck blockade is the real gate |
| Story scripts | hand-authored GDScript coroutines keyed by ROM script ids | opcode semantics undecoded; `zone_event` already gives placement |
| Git | **nothing ROM-derived, ever** | `.gitignore` is the enforcement point |
