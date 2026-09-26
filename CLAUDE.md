# CLAUDE.md

Operational guide for working in this repo. Read this before touching anything.

## What this is

A **Pokémon Platinum remake in Godot 4.7.2** with four headline changes:

1. **Gen 5 visuals** — assets extracted from the owner's own DS ROMs
2. **Hard level caps at boss fights** — a Pokémon at or above the cap gains **zero** EXP
3. **No HMs** — field traversal is badge-gated and automatic
4. **Species from Gens 1–9** (1025) plus **Mega Evolution** (97 forms, through Legends Z-A)

Mega Evolution is the **only** gimmick. Dynamax/Gigantamax, Z-Moves and Terastallization
are deliberately excluded and must never appear in data or engine code.

---

## Hard rules

### 1. Never commit ROM-derived content

The owner supplies his own ROMs at `References/Roms/` (~1.7 GB, gitignored). Everything
extracted from them is regenerable and must stay out of git.

| Committed | Not committed (gitignored) |
|---|---|
| `data/species.json`, `moves`, `learnsets`, `abilities`, `typechart` (veekun-sourced) | `assets/generated/**` — all sprites, icons, tilesets |
| `data/level_caps.json`, `data/megas.json`, `data/mega_ability_overrides.json` (design data) | `data/rom/**` — encounters, trainers, bosses, text, sprite manifests |
| `data/maps/**` (hand-authored) | `References/Roms/**`, `*.nds` |
| `docs/**`, `src/**`, `tools/**` | `tools/_work/**`, `tools/.cache/**`, `.godot/` |

**The line:** factual data (stats, levels, rosters) is uncopyrightable and may be tracked.
**Art and in-game text are not** — sprites, tilesets and extracted dialogue stay ignored.

Always verify before adding a new output path:
```bash
git check-ignore -v <path>
```

### 2. Assert on content, never on exit code

A script that exits 0 having written garbage is a **failure**. This repo has already been
bitten twice (see Known traps). If you produce an image, **open it and look at it**. If you
write GDScript, **run it headless and read the output**.

### 3. `docs/DATA_CONTRACT.md` is authoritative

It is the single integration point between the Python pipelines and the Godot runtime.
Both sides code against it. Changing a shape there is a breaking change and must be made
**in that file first**.

---

## Environment

| | |
|---|---|
| OS | Windows. Use the Bash tool with POSIX syntax. |
| Python | 3.8.3, with PIL 7.2.0 + numpy |
| Godot | `C:/Users/James/Documents/GitHub/Godot_v4.7.2-stable_win64_console.exe` |
| ROMs | `References/Roms/{Platinum,Black,White 2,Heartgold}/` |

### PIL fails under Git Bash unless you fix PATH first

This is a known anaconda quirk on this machine. **Every bash call that imports PIL must
start with:**

```bash
source tools/_work/gen5/env.sh
```

Verify with `python -c "from PIL import Image; print('ok')"`. Without it you get
`ImportError: DLL load failed while importing _imaging`.

---

## Commands

```bash
# Godot test suite — exits nonzero on failure
tools/run_tests.sh
tools/run_tests.sh -- --filter=battle
tools/run_tests.sh -- --require-data     # pendings become failures

# Data pipelines (committed output)
python tools/build_species.py            # 1025 species, moves, learnsets, abilities, typechart
python tools/build_megas.py              # 97 Mega forms

# Data audits (read-only; build_species.py already APPLIES the evolution pass)
python tools/fix_evolutions.py           # the 73-edge rework; --apply, --verify, --markdown
python tools/check_reachability.py       # who can the player actually get, and why not
python tools/check_reachability.py --list

# ROM pipelines (gitignored output — needs the ROMs present)
python tools/build_gamedata.py           # encounters, trainers, bosses, text
python tools/build_sprites.py            # 1025 front/back/icon sprites
python tools/build_tilesets.py           # tileset atlas + Godot TileSet
python tools/scale_encounters.py         # rescale wilds to the level curve
python tools/scale_trainers.py           # rescale ordinary trainers

# ROM library tests (Python)
python -m pytest tests/test_rom.py
```

`tools/run_tests.sh` runs `--import` first on purpose: `class_name` globals and imported
PNGs don't exist until it has. `--import` **exits 0 even when it logs fatal errors**, so the
script gates on the class cache existing instead of on its exit status.

---

## Layout

```
src/
  autoload/   Logger, DataRegistry, EventBus, GameState, SaveSystem, SceneRouter
  battle/     battle_engine, damage, turn_order, status, stats, exp, mega, ai
  battle/abilities/   one file per ability + registry.gd
  overworld/  map_loader, player, collision, encounters, traversal, warps
  systems/    level caps, badges
tools/
  rom/        production ROM reader: ndsfs, narc, lz, nitrogfx, nsbtx, rom
  build_*.py  pipelines
data/         the contract's JSON (see table above for what's tracked)
docs/
  DATA_CONTRACT.md      authoritative schemas
  research/             verified findings — read before re-deriving anything
tests/        Godot headless suite + Python ROM tests
```

`docs/research/` holds the output of a large verification effort. **Read it before
researching anything about ROM formats, Platinum data, Gen 5 assets, the level curve or
Mega Evolution** — it is byte-verified and will save you hours. `nds-formats.md` is
self-testing: `doc_selftest.py` executes all 25 Python blocks out of the markdown.

---

## Locked design decisions

Do not relitigate these. They were decided by the owner.

**Level caps** — hard XP stop. Cap table (`data/level_caps.json`), **per-segment EXP
multipliers**:

| Roark | Gardenia | Fantina | Maylene | Wake | Byron | Candice | Volkner | E4 | Cynthia |
|---|---|---|---|---|---|---|---|---|---|
| 18 | 27 | 36 | 45 | 54 | 66 | 78 | 90 | 96–99 | **100** |

Raised EXP rates are **not optional**: level 100 needs 1,000,000 EXP versus ~238,000 at
vanilla's level 62. Without them the player stalls below every cap and the curve breaks.

But the multiplier is **PER-SEGMENT, never global** (DATA_CONTRACT 8). Each of the 15 cap
rows carries its own `expMultiplier`; the top-level one is permanently `null` and nothing
may read it. Caps are hard, so surplus EXP inside a segment is discarded rather than carried
forward and every segment must supply its own cap's worth on its own. Segments 1-5 already
run a 1.76-2.58 surplus at ×1.0 while the League runs as low as ×0.39, so one flat number
cannot serve both ends: an earlier build's flat ×2.5 capped the player about four trainers
in and left ~50 early battles awarding nothing. Values are
`1.0` ×6 → byron `1.35` → candice `2.95` → volkner `1.8` → aaron `1.3` → bertha `2.05` →
flint `2.55` → lucian `3.3` → cynthia `3.4` → post-game `1.0`.

Engine side: `GameState.current_exp_multiplier()` returns the active segment's value and
`src/battle/exp.gd` applies it **before** the cap check, so the cap always wins — a Pokemon
at the cap gains exactly 0 no matter how large the multiplier. Tests:
`tests/test_exp_multiplier.gd`.

**Traversal** — preserves Platinum's badge→HM bindings 1:1, which is why route order cannot
break. `smash`(coal) `cut`(forest) `fly`(cobble) `surf`(fen) `strength`(mine) `climb`(icicle)
`waterfall`(beacon). **There is no `defog` verb — fog is deleted from the game.** The Relic
badge grants the cap raise and story flag only.

**Bosses** — every boss has exactly **6 Pokémon**. Every boss's **ace is a Gen 4 species**
(dex 387–493). Gym leaders Mega Evolve **from gym 3 onward**; the Mega goes on the ace when
the ace can Mega (Maylene/Lucario, Candice/Froslass, Lucian/Gallade, Cynthia/Garchomp),
otherwise on a teammate.

**Mega Ring** — given by Dawn/Lucas in Hearthome **after** Fantina. So Fantina is the first
boss to Mega Evolve and the player gets the Ring immediately after.

**Gym stone awards** — Roark `aerodactylite` · Gardenia `victreebelite` · Fantina `gengarite`
· Maylene `lucarionite` · Wake `gyaradosite` · Byron `steelixite` · Candice `froslassite` ·
Volkner `raichunite-y` **and** `raichunite-x`.

**Megas** — 97 forms. **Primal Reversion is OUT.** **Mega Rayquaza is IN** and is the only
stoneless Mega (`stone: null`, `requiresMove: "dragon-ascent"`) — `can_mega_evolve()` branches
on that. Cynthia uses `garchompite`, **not** `garchompite-z`.

**Tilesets** — Platinum ground (grass/sand/snow/`dun_*`) + White 2 props (cliff edge strips,
32×64 trees, doors/fences) + HeartGold roads. White 2 assets get a **×1.08 value / ×1.04
saturation** lift at import to close a measured 12% tonal gap. Provenance is recorded per
tile in the manifest.

---

## Known traps

Each of these has already cost real time. Do not rediscover them.

**GDScript `Packed*Array` is a VALUE type.** `(dict["k"] as PackedStringArray).append(x)`
appends to a throwaway copy and the stored array never changes — silently, with no error.
`Array` and `Dictionary` *are* references, so a function that fills both looks half-working,
which is the trap: the `Array` field populates and the `Packed*` one comes back empty.
Accumulate in a local and assign back. This cost the Roark reward hookup a whole debugging
pass. Grep: `as Packed\w*Array)\.(append|push_back|insert|resize|set)`.

**`tools/build_species.py` must be idempotent, and it silently was not.** Re-running it used
to revert hand-applied corrections in `data/abilities.json` (14 ability hooks/tiers, 3 effect
texts) and the whole 73-edge evolution rework in `data/species.json`, with no warning at all.
Post-generator corrections belong **inside the build**: the override tables
`ABILITY_HOOK_OVERRIDES`, `ABILITY_TEXT_OVERRIDES`, `LOCAL_EFFECT_IDS`, and the
`fix_evolutions.apply_table()` call — never in the emitted JSON, and never as a "remember to
re-run X afterwards" note. **After any data rebuild:** `git status --short -- data/`, and treat
anything you did not mean to change as a regression.

**An "idempotent" tool is not idempotent until you re-run it and check.** `fix_evolutions.py`
claimed idempotence in its docstring and was wrong for 25 of its 73 rows: the already-applied
check sat below the drift diagnostic, so rows that only DROP a condition (keeping
`method: "level-up"`) reported errors on data that was already correct. Re-run every data pass
twice before believing it.

**NSBTX palette binding is by NAME, not index.** TEX0 stores textures and palettes in two
*separately name-sorted* dictionaries, so `palette[i]` is not `texture[i]`'s palette. Bind
`<tex>_pl` with a fallback chain. Index binding silently recolours a large fraction of the
library. Working implementation: `tools/rom/nsbtx.py`.

**Gen 5 Pokémon sprites are not XOR-obfuscated** — they're LZ11-compressed. Running the Gen 4
XOR on them destroys the image. The real problem is layout: a 96×96 sprite is **four 1D-mapped
OAM objects** (64×64 + 32×64 + 64×32 + 32×32 = 144 chars).

**The Gen 4 XOR direction is per-authoring-game, not per-generation.** Platinum/HGSS seed from
the *first* halfword forward; Diamond/Pearl seed from the *last* backward — and D/P's
`pokegra.narc` still ships inside the Platinum ROM.

**Showdown carries base-species abilities onto Mega forms.** The nine Z-A Megas that Champions
doesn't cover (Heatran, Darkrai, Zygarde, Magearna ×2, Zeraora, Tatsugiri ×3) show abilities in
Showdown, but that is **form-inheritance, not real data**. Their abilities are owner-decided in
`data/mega_ability_overrides.json`, which is authoritative. Never "confirm" them off Showdown.

**Serebii's Z-A stat tables double-count stat-multiplier abilities.** Z-A has no Ability system,
so it compensates (e.g. Mega Starmie's Attack shown as 140 instead of 100 + Huge Power). This
game *has* abilities — use Champions/Showdown stat lines. Starmie is the only case, but check
any new Z-A import.

**Reject the "Champions mega abilities leak."** A widely-reposted Chinese-forum list claiming
localisation insider access. Not a datamine, and wrong where testable (claims Mega Lucario Z has
Prankster; the official ability is Aura Guard). Never seed data from it, not even as a placeholder.

**Platinum's gym order is Roark → Gardenia → *Fantina* → Maylene → Wake → Byron → Candice →
Volkner.** Fantina is gym **3** in Platinum, not gym 5 as in Diamond/Pearl.

**The Platinum map header table is in the ARM9 at `0xE601C`**, not in a NARC — 593 entries × 24
bytes, and the offset is **language-specific** (that value is for the English ROM). The count is
593, not 596; the decomp's list ends in three enum sentinels.

**Trainer party blobs are 4-byte aligned.** 43 of 928 entries mis-parse without that rule.

---

## Open items

- Integration landed: `data/maps/` carries the 9 Twinleaf→Oreburgh maps and `Boot.tscn`,
  `Overworld.tscn` and `Battle.tscn` all exist. The vertical slice boots. Remaining work is
  tracked in `HANDOFF.md` §4.
- **`data/items.json` has no evolution items.** It holds 93 entries: 92 Mega Stones and the Key
  Stone. The evolution data references 40 distinct items (23 `item`, 17 `heldItem`) and **none
  of them exist**, so 23 species that the evolution rework unblocked are still unobtainable and
  every one of the 67 `use-item` evolutions is dead. `tools/check_reachability.py` reports the
  exact list (`NEEDS_ITEM`). Required minimum is listed in `docs/research/evolution-audit.md`
  §6.1. This is the single highest-value data gap left.
- **Vulpix → Ninetales is an Ice Stone evolution, not Fire Stone** — a veekun per-version-group
  dedupe artifact where the Alolan row won (evolution-audit.md §6.2). Owner decision: add a Fire
  Stone route back, or accept it. Meowth → Persian is friendship rather than L28 for the same
  reason; both its routes are reachable, so that one is harmless.
- Gen 4 party-icon palette index table not located (icons use a PokeAPI-intersection workaround).
- Gen 5 dex-number → form-index mapping for `/a/0/0/4` not located; callers supply the mapping.
- Platinum script bytecode opcodes not decoded — the largest remaining unknown for story events.
- 92 of 919 moves have null effects (upstream veekun gap, mostly Gen 8–9). The engine must
  tolerate null. Where a gap actually matters, fill it through `LOCAL_EFFECT_IDS` in
  `tools/build_species.py` (ids from 20001) and teach the engine table that branches on it —
  `population-bomb` is the worked example.
- `mega-design.md` lists Latias/Latios as ORAS; they are **XY** forms.
