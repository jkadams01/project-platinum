# Species, Move, Ability & Type Data for All 1025 Pokémon

Research + tested build plan for sourcing complete Gen 1–9 data and Gen-5-style sprites
for the Godot fan game. Everything below was executed on this machine on 2026-09-23
unless explicitly marked as *inferred*.

**Bottom line:** the whole dataset is solved by one bulk source (PokeAPI's veekun CSV
dump, 11.2 MB, 27 files) plus one sprite repo (PokeAPI/sprites), and the sprite situation
is dramatically better than expected — **complete Gen-5-style front/back/shiny/back-shiny
sprites already exist for all 1025 species**, including Gen 9. A working end-to-end build
was run and validated: 1025/1025 species complete, cross-checked against Pokémon Showdown
with a 324/324 type-chart match and 1024/1025 base-stat match.

The one blocker is not data — **it's disk space. C: has 265 MB free of 487 GB.**

> **UPDATE (2026-09-23, verification pass):** the disk blocker is **cleared** — `C:` now
> reports **24 GB free** of 488 GB. The data plan (11.2 MB CSV + 3.83 MB sprites + Godot
> import cache) fits comfortably. The *rule* still stands: check free space before any bulk
> extraction, and never `git clone --sparse` the sprite repo (§7).

---

## 0. Environment findings (tested)

### Internet + SSL: works, with one caveat

| Path | Result |
|---|---|
| `curl` (MinGW 8.18.0, **Schannel** backend) | **Works out of the box.** `https://raw.githubusercontent.com` → HTTP 200, `ssl_verify_result=0` |
| `python -c "import ssl"` (bare) | **Fails:** `ImportError: DLL load failed while importing _ssl` |
| `python` after PATH fix | **Works.** `OpenSSL 1.1.1g` |

### The anaconda SSL/PATH quirk — diagnosed

`python` on PATH resolves to `C:\Users\James\anaconda3\python.exe`. Its `_ssl.pyd` lives in
`anaconda3\DLLs\`, but the OpenSSL DLLs it links against —
`libssl-1_1-x64.dll` and `libcrypto-1_1-x64.dll` — live in `anaconda3\Library\bin\`,
which is **only added to PATH by `conda activate`**. Launched from Git Bash or any
non-activated shell, the DLLs aren't found and `import ssl` dies before any network call.
This also breaks `pip`, `requests`, and `urllib`.

**Workaround** (prepend once per Bash session; verified):

```bash
export PATH="/c/Users/James/anaconda3:/c/Users/James/anaconda3/Library/bin:/c/Users/James/anaconda3/Scripts:$PATH"
```

For PowerShell: `$env:PATH = "C:\Users\James\anaconda3;C:\Users\James\anaconda3\Library\bin;C:\Users\James\anaconda3\Scripts;$env:PATH"`

Since `curl` needs no such fix, **the download script should use `curl`** and keep Python
purely for offline parsing. That removes the quirk from the critical path entirely.

### No Node.js on this machine

`node` and `npm` are both absent. This is decisive for source selection (see §1) — it rules
out anything that ships data as JavaScript modules rather than plain data files.

### Disk space — the actual blocker

```
C:  488G total,  487G used,  265 MB free  (100%)
```

A `git clone --filter=blob:none --sparse` of PokeAPI/sprites **failed mid-checkout** with
`No space left on device` after pulling ~266 MB. **Free at least 2–3 GB before running any
of this.** The full asset plan needs ~175 MB (11 MB CSVs + 162 MB sprites), and Godot's
`.godot/` import cache for ~4,100 sprite files will want a few hundred MB more.

---

## 1. Primary data source — recommendation

### Recommended: **PokeAPI veekun CSV dump** (`PokeAPI/pokeapi`, `data/v2/csv/`)

**Fallback: Pokémon Showdown `data/*.ts`** (for battle-engine semantics; see §3).

### Comparison

| Source | Bulk? | Offline? | Covers 1025? | Node needed? | License | Verdict |
|---|---|---|---|---|---|---|
| **PokeAPI veekun CSVs** | Yes — 27 files, **11.2 MB** | Yes | **Yes, exactly 1025** | No | BSD-3-Clause | **PRIMARY** |
| PokeAPI REST (`pokeapi.co/api/v2`) | No — per-species HTTP | No | Yes | No | BSD-3 | Rejected: 1025+ round trips, rate-limited |
| PokeAPI `api-data` repo | Yes, but **~302 MB** | Yes | Yes | No | BSD-3 | Rejected: 27× larger for same data; won't fit on this disk |
| Showdown `data/*.ts` | Yes — 5 files, ~5 MB | Yes | Yes | **Partly** | MIT | **FALLBACK** — see parse caveat |
| `@pkmn/dex` (npm) | Yes, but **bundled JS only** | Yes | Yes | **Yes** | MIT | Rejected: no plain JSON, no Node here |
| veekun/pokedex (original) | Yes | Yes | **No** | No | MIT | Rejected: last push **2022-07-21**, pre-Gen-9 |

### Why PokeAPI's CSVs win

- **It is the only candidate that is simultaneously bulk, plain-text, complete, and
  runtime-free.** 11.2 MB of CSV parsed by Python's stdlib `csv` — no dependencies.
- **Actively maintained**: `pushed_at` was **2026-09-23** (today), 5,384 stars.
- **Complete through Gen 9**: `pokemon_species.csv` has exactly **1025 rows, max id 1025**,
  ending at `pecharunt`. Generation spread verified:
  `{1:151, 2:100, 3:135, 4:107, 5:156, 6:72, 7:88, 8:96, 9:120}` = 1025.
- **It carries the fields Showdown does not** — `growth_rate`, `base_experience`,
  `capture_rate`, `base_happiness`, `hatch_counter`, EV yield, and structured evolution
  conditions. Showdown is a battle sim; it has no EXP curves at all. This alone settles it.
- `base_experience` is populated for **all 1025** (verified: 0 missing), including Gen 9
  (Gholdengo 275, Pecharunt 300).

### `@pkmn/dex` — why it's out

Inspected the published package (v0.10.11) file listing on jsDelivr. It ships **only
bundled JS**: `build/index.js` (2.39 MB), `build/index.min.js` (1.83 MB),
`build/learnsets.min.js` (3.20 MB). There is **no `.json` file in the package**. Extracting
it requires evaluating JavaScript, and there's no Node on this machine. It's an excellent
library if you're writing TypeScript; it is the wrong shape for a Godot/Python pipeline.

---

## 2. Download manifest (exact URLs and measured sizes)

Base: `https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv/`

All 27 sizes below were measured by actual download, not estimated.

| File | Bytes | Supplies |
|---|---:|---|
| `pokemon_moves.csv` | 10,733,699 | learnsets (all methods, all version groups) |
| `ability_prose.csv` | 268,704 | ability effect text (en) |
| `move_effect_prose.csv` | 253,898 | move effect text (en) |
| `pokemon_stats.csv` | 94,392 | base stats + EV yield |
| `items.csv` | 59,564 | evolution item names |
| `pokemon_species.csv` | 56,884 | growth rate, capture rate, gender, legendary flags |
| `pokemon.csv` | 47,082 | base EXP, height, weight, form defaults |
| `moves.csv` | 42,322 | power/acc/PP/type/category/priority/target |
| `pokemon_abilities.csv` | 37,224 | ability slots + hidden |
| `pokemon_evolution.csv` | 32,293 | evolution conditions |
| `locations.csv` | 23,389 | location-based evolutions |
| `pokemon_types.csv` | 19,058 | type slots |
| `move_flag_map.csv` | 11,840 | move → flags |
| `pokemon_egg_groups.csv` | 8,141 | egg groups |
| `abilities.csv` | 7,074 | ability list |
| `type_efficacy.csv` | 2,883 | **the 18×18 chart** |
| `growth_rates.csv` | 879 | 6 EXP curves + formulae |
| `version_groups.csv` | 726 | learnset source resolution |
| `evolution_triggers.csv` | 304 | trigger vocabulary |
| `types.csv` | 321 | type list |
| `move_targets.csv` | 278 | 16 targeting modes |
| `move_flags.csv` | 235 | 21 flags |
| `stats.csv` | 202 | stat names |
| `pokemon_move_methods.csv` | 187 | level-up/egg/tutor/machine |
| `egg_groups.csv` | 163 | egg group names |
| `type_efficacy_past.csv` | 118 | historical chart deltas |
| `move_damage_classes.csv` | 44 | physical/special/status |
| **TOTAL** | **11,701,904 (11.2 MB)** | |

Optional: `machines.csv` (32,831 B) if you want TM numbers.

### Download script

```bash
# curl uses Schannel — no anaconda PATH fix needed for this step
BASE=https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv
DEST=tools/_work/dl && mkdir -p "$DEST"
for f in pokemon_species pokemon pokemon_stats stats pokemon_types types \
         type_efficacy type_efficacy_past pokemon_abilities abilities ability_prose \
         pokemon_egg_groups egg_groups growth_rates pokemon_evolution evolution_triggers \
         moves move_damage_classes move_targets move_flags move_flag_map \
         move_effect_prose pokemon_moves pokemon_move_methods version_groups \
         items locations machines; do
  curl -sSL --retry 3 --max-time 300 -o "$DEST/$f.csv" "$BASE/$f.csv" \
    && echo "ok $f.csv" || echo "FAIL $f.csv"
done
```

Measured: the full set downloads in well under a minute on this connection.

---

## 3. Normalized JSON shape (built and tested)

Working build script: `tools/_work/build/build_species.py`
Output: `tools/_work/build/out/`

### Measured results

```
species: 1025 | moves: 919 | abilities: 314 | types: 18
evolution edges: 500 (after dedup) | species with no learnset: 0
  species.json      1.65 MB
  moves.json        0.21 MB
  abilities.json    0.02 MB
  types.json        0.00 MB
INCOMPLETE species: 0
```

Build time: **2.1 seconds**. Total output: **1.88 MB** — small enough to ship in the
Godot project and parse at boot.

"INCOMPLETE" = missing any of types, 6 base stats, abilities, egg groups, base EXP, or a
level-up learnset. **Zero of 1025 are incomplete.**

### `species.json` — keyed by dex number as string

```jsonc
"1000": {
  "id": 1000, "name": "gholdengo", "generation": 9,
  "types": ["steel", "ghost"],
  "base_stats": { "hp":87, "attack":60, "defense":95,
                  "special-attack":133, "special-defense":91, "speed":84 },
  "ev_yield": { "special-attack": 3 },
  "abilities": ["good-as-gold"], "hidden_ability": null,
  "egg_groups": ["no-eggs"],
  "growth_rate": "slow", "base_exp": 275,
  "capture_rate": 45, "base_happiness": 50, "hatch_counter": 50,
  "gender_ratio_female": null,          // null = genderless
  "height_dm": 12, "weight_hg": 300,
  "is_baby": false, "is_legendary": false, "is_mythical": false,
  "evolves_from": 999, "evolution_chain": 548,
  "evolves_to": [],
  "learnset_source": "scarlet-violet",
  "learnset": {
    "level_up": [ { "move": "astonish", "level": 1 }, ... ],
    "egg": [], "tutor": [...], "machine": [...]
  }
}
```

`evolves_to` entries carry only the keys that apply:

```jsonc
{ "to": 134, "trigger": "use-item", "trigger_item": "water-stone" }
{ "to": 196, "trigger": "level-up", "min_happiness": 160, "time_of_day": "day" }
{ "to": 700, "trigger": "level-up", "known_move_type": "fairy", "min_affection": 2 }
```

### `moves.json` — keyed by identifier

```jsonc
"thunderbolt": {
  "id": 85, "name": "thunderbolt", "generation": 1,
  "type": "electric", "category": "special",
  "power": 90, "accuracy": 100, "pp": 15, "priority": 0,
  "target": "selected-pokemon",
  "effect_id": 7, "effect_chance": 10,
  "flags": ["mirror", "protect"]
}
```

### `types.json`

```jsonc
{ "order": ["normal","fighting",...,"fairy"],      // canonical 18, ids 1-18
  "chart": { "fairy": { "dragon": 2.0, "steel": 0.5, ... }, ... } }   // attacker -> defender -> multiplier
```

---

## 4. Validation — cross-checked against Pokémon Showdown

Independently parsed Showdown's `data/pokedex.ts`, `moves.ts`, and `typechart.ts` (pure
Python regex, no Node) and diffed against the built output.

| Check | Result |
|---|---|
| **Type chart, all 324 cells** | **324/324 identical. Zero differences.** |
| Base stats + types, base forms | **1024 / 1025 identical** |
| Move type/category/power/accuracy/PP/priority | **439 / 440 identical** |

### The two discrepancies — both explained, neither is an error

1. **Minior (#774).** Showdown's default `minior` entry is the **Core** form
   (60/100/60/100/60/120); PokeAPI's default is **Minior-Meteor**
   (60/60/100/60/100/60). Both databases contain both forms — they simply pick different
   defaults. In-game Minior *enters battle* in Meteor form, so PokeAPI's default is the
   right one for an overworld/encounter game. Not a data error; a form-default convention.

2. **Tachyon Cutter accuracy.** This surfaced a genuine **veekun encoding
   inconsistency** worth guarding against — see the gotchas below.

---

## 5. Gotchas found while building (all reproduced, all fixed in the script)

These cost real debugging time; each is a concrete rule.

### 5a. Never-miss accuracy is encoded two different ways

veekun writes "no accuracy check" as an **empty string** for 288 moves (Swift, Aerial Ace,
Shock Wave…) — but as the literal string **`"0"`** for exactly three Gen-9 moves:
`burning-bulwark`, `tachyon-cutter`, `dragon-cheer`. Read naively, `0` means *always
misses*. Normalize both to `null`:

```python
'accuracy': (i(r['accuracy']) or None)    # '' -> None, '0' -> None
```

After the fix: 288 moves correctly have `accuracy: null`.

### 5b. Evolution rows are per-version-group, so branches duplicate massively

`pokemon_evolution.csv` stores one row **per version group**, not per evolution.
Raw Eevee → **19 rows** for 8 real targets; Pikachu → 2 identical Raichu rows. Dedupe on
`(target, trigger)` keeping the highest `version_group_id`:

- Before: 614 edges, Eevee has 19.
- After: **500 edges**, Eevee has 10 (correctly keeping both the modern stone route *and*
  the legacy location route for Leafeon/Glaceon, which are genuinely different triggers).

### 5c. The learnset fallback chain is mandatory, and three version groups are traps

Gen 9 games contain only **777 of 1025** species, so there is no single version group with
full coverage. A newest-first fallback chain is required. **But** these version groups must
be excluded:

| VG | id | Rows | Level-up rows | Problem |
|---|---:|---:|---:|---|
| `the-isle-of-armor` | 21 | 0 | 0 | empty |
| `the-crown-tundra` | 22 | 0 | 0 | empty |
| `the-teal-mask` | 26 | 0 | 0 | empty |
| `the-indigo-disk` | 27 | 0 | 0 | empty |
| `legends-za` | 30 | 0 | 0 | empty |
| `mega-dimension` | 31 | 0 | 0 | empty |
| **`champions`** | **32** | **19,810** | **0** | **the trap** |

`champions` looks populated (19,810 rows) but has **zero level-up rows**. An
ordering that reaches it first silently hands 44 species — Kangaskhan, Alakazam, Pidgeot,
Beedrill and other Mega-capable mons absent from SV — a **completely empty movepool**. This
was caught only by the completeness assertion.

Working chain (newest usable first):

```python
ORDER = [25,           # scarlet-violet          (gen 9)
         20, 23, 24,   # sword-shield, BDSP, legends-arceus
         18, 17, 19,   # USUM, SM, LGPE
         16, 15,       # ORAS, XY
         14, 11,       # B2W2, BW
         10, 9, 8,     # HGSS, Platinum, DP
         7, 6, 5, 13, 12,
         4, 3, 2, 1]
```

Resulting spread — every species resolves, all from Gen 7–9 games:

```
scarlet-violet 733 | sword-shield 244 | brilliant-diamond-shining-pearl 39 | ultra-sun-ultra-moon 9
```

> **Platinum-flavoured alternative:** for a Sinnoh remake you may prefer Gen-4 movepools
> where they exist. Reordering to `[9, 10, 8, 14, 11, 25, 20, 23, ...]` (Platinum → HGSS →
> DP first) gives period-accurate learnsets for the 493 species that had them and falls
> through to modern data for 494–1025. The script's `ORDER` is the single knob.

### 5d. Join through `pokemon.csv`, not `pokemon_species.csv`

Stats/types/abilities key on `pokemon_id` (1,351 rows — includes Megas, regional forms,
Gigantamax), while egg groups and growth rate key on `species_id` (1,025). Build a
`pokemon_id → species_id` map filtered to `is_default = 1` or you'll silently blend
Mega Charizard X's stats into Charizard.

### 5e. Godot's JSON parser returns every number as a float

Verified on **Godot 4.7.2 headless**: `JSON.parse_string` yields
`{"level": 1.0, "id": 85.0, "power": 90.0}`. Integer fields need `int()` casts, or a
one-time conversion pass into typed Resources. Silent bugs otherwise (`level == 1` fails
against `1.0` in some comparisons; array indexing with a float errors).

### 5f. veekun uses legacy internal names for egg groups

`ground` = **Field**, `plant` = **Grass**, `humanshape` = **Human-Like**,
`indeterminate` = **Amorphous**, `no-eggs` = **Undiscovered**. Keep a display map;
don't show these raw.

---

## 6. Godot load test (actually run)

`Godot_v4.7.2-stable_win64_console.exe --headless --script test.gd`:

```
parsed species: 1025 in 121 ms
  #1000 gholdengo ["steel", "ghost"] BST=550
  #1000 levelup moves: 12 first={ "level": 1.0, "move": "astonish" }
  fairy->dragon = 2.0 | dark->steel = 1.0
  moves: 919 thunderbolt={ "accuracy": 100.0, ... "power": 90.0, ... }
TOTAL ms: 195
```

All three JSON files load and parse in **195 ms total**. Boot-time parsing is fine; no
need for a binary format. If you later want faster, convert once to `.res` Resources.

---

## 7. Sprites — the headline finding

### Gen-5-style sprites for all 1025 species **already exist and are complete**

**Repo:** `https://github.com/PokeAPI/sprites`
**Path:** `sprites/pokemon/versions/generation-v/black-white/`

Coverage was computed from the untruncated Git tree API for that subtree (11,489 entries),
not sampled:

| Set | Path | Coverage 1–1025 | Size |
|---|---|---|---|
| **Front** | `{id}.png` | **1025 / 1025** | 1.02 MB |
| **Front shiny** | `shiny/{id}.png` | **1025 / 1025** | 0.99 MB |
| **Back** | `back/{id}.png` | **1025 / 1025** | 0.88 MB |
| **Back shiny** | `back/shiny/{id}.png` | **1025 / 1025** | 0.94 MB |
| Front animated | `animated/{id}.gif` | 868 / 1025 | 41.9 MB |
| Front anim. shiny | `animated/shiny/{id}.gif` | 865 / 1025 | 41.8 MB |
| Back animated | `animated/back/{id}.gif` | 818 / 1025 | 36.9 MB |
| Back anim. shiny | `animated/back/shiny/{id}.gif` | 817 / 1025 | 37.0 MB |

> **The static 4-set is 100% complete for all 1025 species and totals only 3.83 MB.**
> Animated GIFs cover gens 1–5 fully plus **218 of the 376** Gen 6–9 species.

### Verified as genuine, not placeholders

Downloaded and inspected with PIL. All are **96×96 PNG with 7–16 colours** — the authentic
BW palette constraint. Back sprites are true rear views (different opaque-pixel counts from
the front: Gholdengo front 2,236 px vs back 1,578 px); shinies share the silhouette with a
recoloured palette, exactly as expected. Animated GIFs carry real BW frame counts
(Gholdengo 93 frames, Eternatus 120). A rendered contact sheet of Charizard, Victini,
Chespin, Sylveon, Necrozma, Eternatus, Sprigatito, Gholdengo and Pecharunt showed a single
consistent visual style across all nine generations.

### Provenance and licence

`CONTRIBUTING_SPRITES.md` states the project's explicit goal: *"to provide a complete set of
'Gen 5 style' (Black & White) sprites for the entire National Dex"*, and that for IDs 650+
*"Since official Gen 5 sprites do not exist for newer Pokémon, we source community-made
assets from Smogon"* via `scripts/smogon_download.py`, synced from Smogon community
spreadsheets. **So the Smogon Sprite Project dumps are already ingested, deduplicated,
renamed to dex-number convention, and manually QA'd — you do not need to scrape Smogon
yourself.** That repo is the aggregation you'd otherwise have to build.

**Licence caveat — read before shipping:** `PokeAPI/sprites` has **no LICENSE file** (404).
The sprites are Smogon-community fan art of Nintendo-trademarked characters. The parent
`PokeAPI/pokeapi` repo is **BSD-3-Clause**, but that covers the API code and data, not the
sprite images. Practically: this is the same footing every Pokémon fan game stands on —
fine for a personal, non-commercial, non-distributed project; **not** license-clean in any
strict sense, and not safe to monetize. Credit the Smogon Sprite Project.

### Sprite download — tested

Individual `raw.githubusercontent.com` fetches, 8 threads: **108/108 files, 20.8 files/s,
zero failures.** Projected time for the full static 4-set (~4,100 files, 3.83 MB): **~3.3
minutes.**

```bash
# static 4-set only — 3.83 MB, the complete 1025 coverage
BASE=https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon/versions/generation-v/black-white
for variant in "" "shiny/" "back/" "back/shiny/"; do
  out="assets/sprites/${variant:-front/}"; mkdir -p "$out"
  for n in $(seq 1 1025); do
    curl -sSL --retry 2 -o "$out/$n.png" "$BASE/$variant$n.png"
  done
done
```

Use a thread pool (8 workers) rather than this serial loop — it's ~20× faster.

> **Do not use `git clone --filter=blob:none --sparse` here.** Tried it: the sparse
> checkout of `generation-v/black-white` pulls **174 MB** (it can't exclude the animated
> GIFs at cone granularity) plus an 87 MB `.git`, and **it ran the disk out of space and
> failed.** Direct per-file fetches of just the 4 static sets cost 3.83 MB.

### Icons — the one real gap

No complete Gen-5-style **box/menu icon** set exists for 1025:

| Source | Coverage | Licence |
|---|---|---|
| `PokeAPI/sprites` `generation-v/icons` | 1–649 only | none |
| `PokeAPI/sprites` `generation-vii/icons` | 1–809 | none |
| `PokeAPI/sprites` `generation-viii/icons` | 1–898 | none |
| `msikma/pokesprite` `pokemon-gen8/` | **1–905** (verified: 906–1025 all missing) | **MIT** |

**Recommendation:** use `msikma/pokesprite` (`pokemon-gen8/regular/{slug}.png` and
`/shiny/`) for 1–905 — it's the only genuinely **MIT-licensed** asset in this whole
document — and for the 120 Gen-9 species either downscale the BW battle sprites to 40×30,
or skip icons initially. Note pokesprite keys by **name slug**, not dex number; join via
its `data/pokemon.json` (525 KB, `idx` → `slug.eng`).

---

## 8. Moves, Gens 1–9

**919 moves** (ids ≤ 10000; the other 18 are Colosseum/XD Shadow moves, excluded).
Generation spread: `{1:165, 2:86, 3:121, 4:113, 5:92, 6:62, 7:121, 8:108, 9:69}`.

Everything the battle engine needs is present:

- **power / accuracy / pp / type / category / priority** — direct columns in `moves.csv`.
  `category` comes from `move_damage_classes.csv`: `physical` / `special` / `status`.
- **target** — `move_targets.csv`, 16 values: `selected-pokemon`, `all-opponents`,
  `all-other-pokemon`, `user`, `users-field`, `opponents-field`, `entire-field`,
  `user-and-allies`, `all-allies`, `ally`, `user-or-ally`, `random-opponent`,
  `specific-move`, `selected-pokemon-me-first`, `all-pokemon`, `fainting-pokemon`.
  Enough to drive single **and** double battles.
- **flags** — `move_flags.csv` + `move_flag_map.csv`, 21 flags: `contact`, `charge`,
  `recharge`, `protect`, `reflectable`, `snatch`, `mirror`, `punch`, `sound`, `gravity`,
  `defrost`, `distance`, `heal`, `authentic` (bypasses Substitute), `powder`, `bite`,
  `pulse`, `ballistics` (= Showdown's `bullet`), `mental`, `non-sky-battle`, `dance`.
- **effect** — `effect_id` + `effect_chance`, with prose in `move_effect_prose.csv`.

### Where Showdown is genuinely better, and how to use it

> ### ⚠ CORRECTION (adversarial verification pass, 2026-09-23)
>
> The original text here read: *"veekun's 21 flags predate several modern ones. Showdown
> additionally carries `wind`, `slicing`, `bypasssub`, `bludgeon`, `metronome`,
> `failencore`, `noparentalbond`…"* — **two of those entries are wrong.**
>
> * **`bludgeon` is not a Showdown flag at all.** It appears **zero** times
>   (case-insensitive) in `data/moves.ts` and `sim/dex-moves.ts`. The authoritative
>   `interface MoveFlags` has 38 keys and `bludgeon` is not among them. Fabricated entry —
>   delete it.
> * **`bypasssub` does not belong in the "missing" list.** veekun HAS this flag, under the
>   name `authentic`; the same paragraph said so two sentences later, contradicting itself.
>   Proven by exact set equality, not inference: joining `move_flag_map.csv` → `moves.csv`
>   and diffing against the flags regex-parsed out of `moves.ts`, over the 789 moves both
>   DBs know, veekun `authentic` and Showdown `bypasssub` are **75 moves each, 0 in
>   veekun-only, 0 in Showdown-only**.
> * **`metronome` is genuinely absent from veekun but is not a "modern" battle mechanic.**
>   It is Showdown-internal bookkeeping ("can be called by Metronome", set on 696 moves),
>   the same class as `failcopycat`, `noassist`, `nosketch`, `nosleeptalk`, `allyanim`.
>
> **Corrected statement.** veekun ships 21 move flags; Showdown's `MoveFlags` interface has
> 38. Genuinely-missing modern battle mechanics: **`wind` (17 moves), `slicing` (26),
> `cantusetwice` (2)** — all Gen 8/9. Missing Showdown bookkeeping/engine flags (not game
> mechanics): `allyanim, failcopycat, failencore, failinstruct, failmefirst, failmimic,
> futuremove, metronome, minimize, mustpressure, noassist, noparentalbond, nosketch,
> nosleeptalk, pledgecombo`.
>
> **Rename map (veekun → Showdown)** — all three verified by exact move-set equality:
>
> | veekun | Showdown | moves each | disagreements |
> |---|---|---:|---:|
> | `authentic` | `bypasssub` | 75 | **0** |
> | `ballistics` | `bullet` | 25 | **0** |
> | `non-sky-battle` | `nonsky` | 40 | **0** |
>
> Flip side of the gap: veekun's **`mental`** (blocked by Aroma Veil, cured by Mental Herb —
> `move_flag_prose.csv` row 19) has **no Showdown counterpart**; Showdown implements Aroma
> Veil via a hardcoded move list, and no flag containing "mental" or "aroma" exists in
> `moves.ts`.
>
> **Scope note that settles this for our purposes:** veekun `moves.csv` tops out at
> `generation_id 8` with 844 moves vs Showdown's 954, so 165 Showdown moves have no veekun
> row at all — the flag gap is a symptom of veekun being frozen mid-Gen-8. **For a Platinum
> (Gen 4) remake this is irrelevant: none of the missing flags exist in Gen 4, and the 21
> veekun flags are a superset of what Platinum's move table encodes.**

veekun's 21 flags **predate** several genuinely modern ones — `wind`, `slicing` and
`cantusetwice`. If you implement Wind Rider / Wind Power / Sharpness, you need those three
(a hand-maintained ~45-move supplemental table; see the parse caveat below).

**Parse caveat (tested):** `pokedex.ts` and `typechart.ts` parse cleanly in pure Python
(1,481 of 1,518 species blocks extracted by regex). **`moves.ts` does not** — a naive
block-split recovered only **477 of 919** moves, because move entries embed JavaScript
callbacks (`onHit`, `onTryMove`, `condition`) whose nested braces defeat regex. To use
Showdown's move flags you must either write a brace-matching parser that skips function
bodies, or install Node and dump to JSON in three lines. Given the flags are the only thing
you'd want, **hand-maintaining a ~30-move supplemental flag table is probably cheaper** than
either.

---

## 9. Abilities

**314** main-series abilities in the dataset; **284** are actually carried by the 1025
species. Short effect text is available in English for all 314 (`ability_prose.csv`,
`local_language_id = 9`) — e.g. `good-as-gold` → *"Gives immunity to status moves."*

### On the "~60 abilities covering 95% of battles" framing

Tested this and it **doesn't hold as stated**: the 60 most *common* abilities by species
count cover only **59.1%** of the 2,411 ability slots, and frequency is a poor proxy for
battle relevance anyway. The most common ability across all 1025 is Swift Swim (44
species); several others in the top 20 — Keen Eye, Run Away, Pickup, Gluttony, Big Pecks —
are nearly inert in battle.

**The useful axis is not frequency, it's which hook in the turn pipeline the ability
needs.** Implement by hook, and each new hook unlocks a whole group at once. Tiering below
was verified against the built dataset — **all 250 identifiers listed exist; zero typos.**
Script: `tools/_work/build/ability_tiers.py`.

| Tier | Hook needed | Count | Species slots |
|---|---|---:|---:|
| **T0** switch-in / on-entry | `on_switch_in(user, field)` | 22 | 95 |
| **T0** type-immunity redirect | gate damage to 0 **+** side effect | 16 | 184 |
| **T1** damage-formula multipliers | multiplier in the damage calc | 45 | 392 |
| **T1** speed / priority / turn-order | order resolution | 13 | 147 |
| **T1** move type-changing | rewrite move type pre-calc | 11 | 21 |
| **T1** accuracy / evasion / bypass | accuracy check + ignore-ability flag | 14 | 205 |
| **T2** end-of-turn residual | `on_turn_end` | 18 | 140 |
| **T2** contact / on-hit reaction | `on_damaged(move, attacker)` | 29 | 211 |
| **T2** status / condition immunity | status-application gate | 29 | 371 |
| **T2** KO / HP-threshold | `on_faint`, `on_hp_cross` | 15 | 114 |
| **T3** field / item / misc | assorted | 28 | 240 |
| **T4** **battle-inert** | **none — stub as no-op** | 16 | 215 |

### Build order

1. **T0 (38 abilities, 2 hooks).** `on_switch_in` alone buys Intimidate, all four weather
   setters, all four terrain setters, Trace, Download, Protosynthesis, Quark Drive,
   Intrepid Sword, Orichalcum Pulse. The type-immunity group (Levitate, Volt Absorb, Water
   Absorb, Flash Fire, Lightning Rod, Storm Drain, Sap Sipper, Dry Skin, Earth Eater,
   Well-Baked Body, Wind Rider, Bulletproof, Soundproof, Good as Gold, Purifying Salt)
   needs one gate in the damage path and changes battle outcomes more than anything else.
2. **T1 (83 abilities, ~4 hooks).** A single multiplier hook in the damage formula covers
   45 abilities — the starter trio's Overgrow/Blaze/Torrent/Swarm, Huge Power, Adaptability,
   Technician, Sheer Force, Thick Fat, Multiscale, Tough Claws, Sharpness…
3. **T2 (91 abilities, 4 hooks).** Where most remaining flavour lives.
4. **T3 (28).** Long tail.
5. **T4 (16) — do nothing.** Run Away, Pickup, Honey Gather, Illuminate, Stench, Ball Fetch
   etc. have no single-player battle effect. Stub them.

**T0 + T1 core = 97 distinct abilities behind roughly six hooks**, and that is the real
"covers most battles" set. 64 abilities remain untiered (Rock Head, Steadfast, Skill Link,
Magnet Pull, Shadow Tag, Corrosion…) — all genuinely niche; add on demand.

---

## 10. The 18-type chart

Delivered in `types.json` as `attacker → defender → multiplier`. Source:
`type_efficacy.csv` — **exactly 324 rows = 18 × 18**, fully dense, covering
`normal, fighting, flying, poison, ground, rock, bug, ghost, steel, fire, water, grass,
electric, psychic, ice, dragon, dark, fairy` (ids 1–18; id 19 `stellar` and the
pseudo-types `unknown`/`shadow` are excluded).

**This is the modern Gen 6+ chart** — verified explicitly on both requested points:

| Interaction | Value | Note |
|---|---|---|
| `ghost → steel` | **1.0** | Gen 2–5 was 0.5. **Correctly removed.** |
| `dark → steel` | **1.0** | Gen 2–5 was 0.5. **Correctly removed.** |
| `fairy → dragon` | 2.0 | |
| `dragon → fairy` | **0.0** | immune |
| `poison → fairy` | 2.0 | |
| `steel → fairy` | 2.0 | |
| `fighting → fairy` | 0.5 | |
| `fairy → fighting` | 2.0 | |
| `fairy → dark` | 2.0 | |
| `fairy → fire`, `fairy → poison`, `fairy → steel` | 0.5 | |
| `bug → fairy`, `dragon`-vs — see chart | 0.5 | |

All **eight** canonical immunities are present and correct:
`normal→ghost`, `fighting→ghost`, `poison→steel`, `ground→flying`, `ghost→normal`,
`electric→ground`, `psychic→dark`, `dragon→fairy`.

**Independently confirmed:** diffed all 324 cells against Showdown's `typechart.ts`
(which encodes defensively as `0=neutral, 1=weak, 2=resist, 3=immune`) — **zero
differences**.

### Older charts, if you ever want them

`type_efficacy_past.csv` holds only **6 delta rows**:

```
gen 1:  poison→bug 2.0,  bug→poison 2.0,  ghost→psychic 0.0,  ice→fire 1.0
gen 5:  ghost→steel 0.5, dark→steel 0.5
```

So a Gen-4/Platinum-era chart = the modern chart with the two gen-5 rows applied
(Ghost and Dark resisted by Steel) and Fairy removed. Note this file does **not** capture
every historical nuance — treat the modern chart as authoritative and these as the only
two switches you'd realistically flip.

---

## 11. Recommended plan

1. **Free disk space first** — 265 MB available is not enough. Target 2–3 GB.
2. **Data:** `curl` the 27 CSVs (11.2 MB) → run `build_species.py` → 1.88 MB of JSON.
   2 seconds, zero dependencies beyond the Python stdlib. Re-runnable offline.
3. **Sprites:** fetch the four static BW sets (4,100 files, 3.83 MB, ~3 min at 8 threads).
   Add animated GIFs later only if the battle scene needs them — they're 158 MB for
   partial Gen 6–9 coverage.
4. **Icons:** `msikma/pokesprite` gen8 for 1–905 (MIT); defer the 120 Gen-9 icons.
5. **Validate every build** with the completeness assertion — it's what caught the
   `champions` trap. Fail the build on any incomplete species rather than shipping silent
   empty movepools.
6. **Keep the Showdown `.ts` files as a cross-check**, not a runtime dependency. Re-running
   the 324-cell type diff and the base-stat diff after any data refresh is cheap and
   catches upstream regressions.
7. Nothing ROM-derived and nothing downloaded here goes into git — `tools/_work/` is
   already gitignored (`.gitignore:34`).

## 12. Risks

- **Disk space (blocking).** 265 MB free; a sparse clone already failed here.
- **Sprite licence.** No LICENSE on `PokeAPI/sprites`; fan art of trademarked characters.
  Personal-use only. Credit the Smogon Sprite Project.
- **Animated Gen 6–9 is incomplete** (868/1025 front). If the battle scene assumes
  animation, 157 species need a static fallback path.
- **No Gen-9 icons** anywhere clean (906–1025).
- **Upstream churn.** PokeAPI was pushed today; version-group ids and the `champions` stub
  can change. Pin a commit SHA rather than `master` if you want reproducibility.
- **Showdown `moves.ts` is not Python-parseable** (477/919). Adding modern move flags means
  a real parser or Node.
- **Godot float coercion** will bite silently if integer fields aren't cast.
