# HANDOFF — resume from here

Written 2026-09-23, updated 2026-09-26. Everything below was **verified by running it**,
not assumed. Read `CLAUDE.md` first for rules and traps; this file is the state snapshot and
the to-do list.

---

## 1. Where the project actually stands

**The game boots and passes its own test suite outright.**

```
tools/run_tests.sh -- --require-data
→ 9,578 of 9,578 checks pass across the whole suite
→ 0 failures, 0 pending
```

| Area | State |
|---|---|
| Data (species/moves/learnsets/abilities/typechart) | done — 1025 species, 919 moves, 314 abilities |
| Megas | done — 97 forms, every ability resolved, 0 pending |
| Level caps + per-segment EXP | done — 18→100, multipliers 1.0…3.4 |
| Bosses | done — 31 entries, all Gen 4 aces, 30×6 Pokémon + Barry R1 |
| Sprites / icons | done — 1025 + 1025, visually verified |
| Tilesets | done — atlas built from Platinum + White 2 + HeartGold |
| Engine (autoloads, battle, overworld, systems, UI) | built, tests green |
| Maps | 9 maps: Twinleaf → Route 201/202/203 → Sandgem → Jubilife → Oreburgh Gate/City/Gym |
| Scenes | `Boot.tscn`, `Overworld.tscn`, `Battle.tscn` all exist |
| Mega abilities (the 14) | implemented, all tier 1 |

---

## 2. What was fixed on 2026-09-26

**`test_beating_roark_awards_the_badge_the_cap_raise_and_aerodactylite` — fixed.**

`Bosses.apply_victory` built its `verbs` and `stones` through
`(out["stones"] as PackedStringArray).append(...)`. **`PackedStringArray` is a VALUE type
in GDScript**, so each append mutated a throwaway copy: the Coal badge, the cap raise, the
`smash` unlock and the stone in the bag were all applied for real, but the returned reward
reported neither the verb nor the stone. `messages` worked throughout only because `Array`
*is* a reference type — which is what made the bug look like a missing hookup rather than a
dropped write. Both sites now accumulate in locals and store back (`src/systems/bosses.gd`).

> **Trap, repo-wide:** never append through a `Dictionary[k] as Packed*Array` cast. A grep
> for `as Packed\w*Array)\.(append|push_back|insert|…)` finds every instance; those two
> were the only ones.

**`population-bomb` — fixed, and it was more than a data row.** veekun ships no `effect_id`
for it (93 moves have that gap), so the move read as ordinary single-hit damage. Assigning
the id was not enough: the engine branches on `effectId`, so both hit-count tables had to
learn it too.

- `tools/build_species.py` now owns `LOCAL_EFFECT_IDS` — project-local move-effect ids
  starting at **20001**, clear of veekun's space (its highest real id is 10006). Population
  Bomb is `20001`.
- `src/battle/multi_hit.gd` gained `PER_HIT_ACCURACY_HITS` — a fixed count *with* per-hit
  accuracy, so `battle_engine`'s hit loop stops at the first miss. That is the move's real
  behaviour and no loop change was needed.
- `src/battle/abilities/skill-link.gd` carries `20001: 10`, so Skill Link now takes it to a
  guaranteed ten hits, exactly as that file's own doc comment always claimed it would.
- The test is no longer a pending data-gap marker; it asserts both halves
  (`test_population_bomb_hits_ten_times_with_skill_link`).

**`tools/build_species.py` was not idempotent — fixed.** Re-running it silently reverted
hand-applied corrections in `data/abilities.json`: `hook` and `tier` for **all 14**
Mega-critical abilities (back to `none` / tier 3) and the effect text for `parental-bond`,
`piercing-drill` and `fire-mane` (back to veekun's outdated or truncated prose). Those
corrections now live in `ABILITY_HOOK_OVERRIDES` / `ABILITY_TEXT_OVERRIDES` in the script,
so a rebuild reproduces `abilities.json` byte for byte. Two new assertions (20 total) fail
loudly if an override or local-effect slug ever stops matching a real row.

> **Check this after any data rebuild:** `python tools/build_species.py` then
> `git status --short -- data/` — anything beyond what you meant to change is a
> regression, not noise.

**The dynamic rival starter — engine side DONE.** The predicted silent bug was real and is
covered. `tests/test_dynamic_starter.gd` is 21 tests / 165 checks; the rule itself is pure and
runs without the gitignored table.

- `GameState.starter_choice` + `set_starter_choice()`, normalised, in `to_dict`/`from_dict`.
  `SAVE_VERSION` is unchanged on purpose: a save predating the field loads and leaves the
  choice empty (tested both ways, on disk and off).
- `Bosses.resolve_rival_starter(choice, stage, lines, counter)` is **pure** — the maps are
  arguments, so the rule is testable with no `bosses.json` at all. `starter_lines()` /
  `starter_counter()` fall back to `FALLBACK_STARTER_*` constants, same policy as
  `DataRegistry.FALLBACK_CAPS`, because `data/rom/**` is gitignored and a fresh checkout has
  no table. The stage is clamped; every id is `int()`-cast (`_meta` is raw JSON — only
  `bosses` rows go through `_intify`, so these arrive as floats).
- `Bosses._build_member()` resolves the tag and hands the species to the builder.
  **`bosses.json` is never written to** — tested by deep-comparing the member row across a
  build, and by building the same fight twice under different choices.
- `PartyBuilder.from_boss_member(member, species_override)` is where the trap lives. On a real
  substitution the authored `moves` are **dropped** and rolled from the substituted species'
  learnset, `speciesName` is dropped, and the ability maps **by role, not by slug**: Barry's
  late slot is authored `iron-fist`, which is Infernape's *hidden* ability, so Torterra gets
  Shell Armor and Empoleon gets Competitive — never a copied `iron-fist`, which neither can
  legally have. `item` and `nature` are species-agnostic and carry over.
- Sprites and icons needed no change: `battle_screen._set_sprite` looks them up from
  `mon["species"]` at draw time, so the substituted id carries them. Pinned by a test anyway.
- An unresolvable tag falls back to the placeholder and warns once. A rival with the wrong
  starter is a bug; a rival fight that cannot start is a broken game.

### Three roster observations — *author to decide, not changed*

1. **`ace` disagrees with the party in Barry r1 and r2.** `barry_r2_route_203` declares its ace
   as slot 0 / species 391 Monferno, but slot 0 is species 77 **Ponyta** — the Monferno is at
   slot 5. `barry_r1_route_201` declares slot 0 / 391 Monferno against a party of one level-5
   species 390. `Bosses.ace_slot()` reads only `slot`, so nothing crashes, but any UI that says
   "this is the ace" points at the wrong Pokémon in those two fights.
2. **Only the Turtwig player meets a designed rival moveset.** The tagged slot is authored as
   the Chimchar line, so `turtwig → chimchar` is not a substitution and keeps its hand-picked
   four. The other two choices roll the learnset. That is correct behaviour for the data as
   written, and the test asserts both branches — but if all three choices should face *designed*
   movesets, the roster needs two more hand-authored sets.
3. `barry_r1_route_201`'s tagged slot has `"speciesName": "Monferno"` on species **390**
   (Chimchar). Harmless now — the name is dropped on substitution and the fight is
   turtwig-only otherwise — but it is wrong in the data.

## 3. Work that was stopped mid-flight

Three workflows were stopped deliberately. **Their scripts are on disk and re-runnable.**

> **Important:** `resumeFromRunId` is **same-session only**. In a fresh session it will not
> replay the cache — invoke with `scriptPath` alone, which re-runs the whole script. All
> three scripts are idempotent enough to re-run, but check §4 first: some of their work
> already landed.

| Workflow | Script | Got as far as |
|---|---|---|
| ~~Dynamic rival starter~~ | `…/workflows/scripts/dynamic-rival-starter-wf_a62c6c02-3b4.js` | **Superseded — §4b is done, do not re-run** |
| Integration | `…/workflows/scripts/platinum-integrate-wf_5b53999c-c91.js` | 3 fixes done, integrator **mostly done** (maps + scenes + UI exist) |
| Evolutions | `…/workflows/scripts/evolution-rework-wf_1e9f5bac-1a1.js` | Audit **done**, Design started, **nothing applied** |

Scripts live under
`C:\Users\James\.claude\projects\C--WINDOWS-system32\a73f5b2d-0c80-46b4-8c4a-4b379a448cba\workflows\scripts\`

---

## 4. Outstanding work, in priority order

**Next up is (c), the evolution rework** — (a), (b) and the `population-bomb` half of (d) are
done.


### a) ~~Fix the Roark reward hookup~~ — DONE 2026-09-26, see §2

### b) ~~Finish the dynamic rival starter~~ — DONE 2026-09-26, see §2

Data tagging (`tools/tag_dynamic_starter.py`) had already run; the engine side, the save
round-trip, the ability/move re-resolution and 21 tests all landed. Three roster observations
are listed in §2 for the owner to rule on.

### c) Apply the evolution rework — audit done, nothing applied

`docs/research/evolution-audit.md` exists. Of **500 evolutions, 73 are impossible**:

| Category | Count |
|---|---|
| wacky (hardware/mechanics we don't have) | 43 |
| trade-with-item | 16 |
| trade | 8 |
| other | 4 |
| trade-for-species (Karrablast ↔ Shelmet) | 2 |

Owner's rules: trade → level up at a level · trade+item → level up **holding that item**
· wacky → level up. **Evolution stones are NOT impossible and must be left alone.**

Design and apply phases never ran. `tools/fix_evolutions.py` exists but check whether it is
a stub. Levels must be chosen against the cap curve — an evolution level is an availability
gate here. Specifically: **Fantina is gym 3 (cap 36) and Mega Evolves Gengar**, so Gengar's
new evolution level should sit at or below 36 if the player is meant to own one by then.

Deliverable that proves it worked: a **reachability check** over all 1025 species,
distinguishing "unobtainable because the evolution is impossible" (the bug) from
"unobtainable because it isn't in this game yet" (expected).

### d) Known smaller gaps

- ~~`population-bomb` has `effectId: null`~~ — DONE 2026-09-26, see §2.
- **Protect is not implemented**, so `unseen-fist` and `piercing-drill` are spec-complete but
  dormant. Hooks and the volatile key exist; a Protect move only needs to set it.
- The new multi-hit loop changed behaviour for **26 multi-strike moves game-wide**. Suite is
  green, but it is balance-visible under level caps (Cloyster's Icicle Spear is the flagged case).
- 93 of 919 moves have null effects (upstream veekun gap, mostly Gen 8–9).
- `mega-design.md` §4.6 still reasons against the *old* vanilla cap table.
- EXP model rests on two soft inputs: trainer→segment attribution is inferred (no route data
  in `trainers.json`), and "20 incidental wilds per area" is an assumption that moves the
  multiplier more than anything else (0 wilds → ×3.2, 40 → ×2.1). Recompute once maps carry
  real trainer placement.

---

## 5. Locked decisions — do not relitigate

Full detail in `CLAUDE.md`; summary so a fresh session does not re-ask:

- **Level caps** 18/27/36/45/54/66/78/90/96/97/98/99/**100**, hard XP stop, **per-segment**
  EXP multipliers (top-level `expMultiplier` is permanently `null`).
- **Traversal** replaces HMs 1:1 with Platinum's badge bindings. **No defog verb — fog is deleted.**
- **Bosses**: 6 Pokémon each; every ace is Gen 4 (387–493). Barry's Route 201 fight is the
  **only** exception at 1 Pokémon — vanilla parity, and 6-v-1 is unwinnable by arithmetic.
- **Megas from gym 3.** Mega Ring from Dawn/Lucas in Hearthome **after** Fantina.
- **Gym stones**: Roark aerodactylite · Gardenia victreebelite · Fantina gengarite · Maylene
  lucarionite · Wake gyaradosite · Byron steelixite · Candice froslassite · Volkner
  raichunite-y **and** raichunite-x.
- **Primal Reversion OUT. Mega Rayquaza IN** (`stone: null`, `requiresMove: dragon-ascent`).
- Cynthia uses `garchompite`, **not** `garchompite-z`.
- The nine Champions-uncovered Mega abilities are owner-decided in
  `data/mega_ability_overrides.json` — **authoritative**. Heatran = **earth-eater**.
- **Tilesets**: Platinum ground + White 2 props + HeartGold roads; White 2 lifted ×1.08 value
  / ×1.04 saturation.
- Levels 85–100 deliberately teach no new moves. Decided; not a bug.

---

## 6. Quick verification on resume

```bash
cd "C:/Users/James/Documents/GitHub/project-platinum"

tools/run_tests.sh -- --require-data    # expect 9,412/9,412, no failures, no pendings

python -c "import json;d=json.load(open('data/level_caps.json'));print(d['expMultiplierMode'], [c['cap'] for c in d['caps']])"
python -c "import json;m=json.load(open('data/megas.json'));f=m['forms'];print(len(f),'forms;',sum(1 for x in f if not x.get('abilities')),'without ability')"
python -c "import json;b=json.load(open('data/rom/bosses.json'));bl=b.get('bosses',b);print(len(bl),'bosses')"

git check-ignore -v References/Roms/     # must report ignored

python tools/build_species.py           # 20 assertions; must pass
git status --short -- data/             # and must leave data/ CLEAN (rebuild is idempotent)
```

**Everything through 2026-09-26 is committed and pushed** on
`build/engine-data-and-vertical-slice`; `main` is still at the initial commit, so the branch
has not been merged. The ROMs and all ROM-derived output are gitignored — re-verify with the
`git check-ignore` line above before any commit.
