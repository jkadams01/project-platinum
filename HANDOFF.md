# HANDOFF — resume from here

Written 2026-09-23, updated 2026-09-26. Everything below was **verified by running it**,
not assumed. Read `CLAUDE.md` first for rules and traps; this file is the state snapshot and
the to-do list.

---

## 1. Where the project actually stands

**The game boots and passes its own test suite outright.**

```
tools/run_tests.sh -- --require-data
→ 9,757 of 9,757 checks pass across the whole suite
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
| Scenes | `Title.tscn` (main scene) -> `Boot.tscn` or `CustomBattle.tscn`; `Overworld.tscn`, `Battle.tscn` all exist |
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

**The evolution rework — APPLIED.** All 73 impossible edges are gone from
`data/species.json`; `tools/check_reachability.py` is the proof and
`tests/test_evolutions.gd` is the regression guard (12 tests / 70 checks, 10 of which fail
against the pre-rework data, so the sweeps are not vacuous).

`tools/fix_evolutions.py` was **not** a stub — the design phase had completed, levels and
rationale included. Three things were wrong with it, all now fixed:

- **It could not write at all.** `find()` matched edges on `(to, method)` only. Feebas has
  two routes to Milotic — `level-up beauty=170` and `trade heldItem=prism-scale` — so once
  the trade edge became `level-up`, the row that deletes the Beauty edge saw two `level-up`
  edges, reported "2 edges share method level-up", and the pass refused to write *anything*.
  Matching on the design table's own `old` condition (`find_exact`) makes every row
  unambiguous and order-independent.
- **It was not idempotent, for 25 of its 73 rows.** The "already applied" check sat *below*
  the drift diagnostic, so it was unreachable for every row that only DROPS a dead condition
  (those keep `method: "level-up"`, so the loose search still found them and compared the
  already-converted edge against the pre-conversion design row). Re-running reported 25
  errors on a file that was simply already correct. The check now comes first, and all 73
  rows report "already applied".
- **A rebuild reverted it.** Its own docstring said "this script must be re-run after every
  `build_species.py` run" — the same trap as `abilities.json`. `build_species.py` now imports
  and applies the table itself before writing, with two assertions (22 total) that fail the
  build if a row stops matching or an impossible edge survives. Both directions verified
  byte-stable.

### The headline finding: the rework is correct, and it unblocked 5 species, not 17

`tools/check_reachability.py` walks the obtainability graph over all 1025 species and
separates the reasons, which is exactly the distinction §4c asked for:

| bucket | before | after | meaning |
|---|---:|---:|---|
| obtainable (wild + gift + evolution) | 181 | **186** | |
| `BROKEN_EVO` | 17 | **0** | reachable parent, unperformable edge — **the bug** |
| `NEEDS_ITEM` | 11 | **23** | fine edge, but the item does not exist in `items.json` |
| `NOT_IN_GAME` | 816 | 816 | nothing in its line is obtainable — expected for a slice |

Only **Alakazam, Machamp, Golem, Gengar and Overqwil** became genuinely obtainable. The other
twelve — Politoed, Scizor, Kingdra, Weavile, Magnezone, Rhyperior, Electivire, Magmortar,
Gliscor, Probopass, Dusknoir, Sneasler — moved from *impossible* to *needs an item that does
not exist*, because rule 2 converts trade-with-item into hold-and-level and
**`data/items.json` contains 93 entries: 92 Mega Stones and the Key Stone, and none of the 40
items the evolution data references.** Audit §6.1 predicted this exactly. The evolution work
is complete; the payoff is gated on `items.json`, which is a different owner.

**`data/items.json` — the 40 evolution items now exist, and the last blocker bucket is
empty.** `tools/build_items.py` builds them; `tests/test_items.gd` guards the linkage (8 tests /
109 checks, 4 of which fail against the old file).

| bucket | after §4c | now |
|---|---:|---:|
| obtainable | 186 | **209** |
| `BROKEN_EVO` | 0 | **0** |
| `NEEDS_ITEM` | 23 | **0** |
| `NEEDS_FRIEND` | 0 | **0** |
| `NOT_IN_GAME` | 816 | 816 |

The item list is **derived from `data/species.json`'s evolution edges**, not typed out, so it
cannot drift: add an evolution needing a new item and the build fails until the item is
described. Prices come from the cached veekun `items.csv`; names, descriptions and the
use/hold role are authored design data, the same status as the Mega Stone descriptions.
`evolves` is derived, so each row records what it is actually for.

`check_reachability.py` now **fails** on a non-empty `NEEDS_ITEM` as well as `BROKEN_EVO`
(`--allow-missing-items` opts out). Both buckets were non-empty and are now closed, so both are
defended rather than merely reported.

> **Two owners, one file.** `build_megas.py` owns the Mega Stones and Key Stone;
> `build_items.py` owns the 40 evolution items. Each preserves the other's rows and both sort
> with `build_items.sort_rows()`, so the bytes are identical whichever ran last — verified by
> alternating the two five times. Nothing in the engine loads `items.json` yet, so
> `tests/test_items.gd` is the only thing that would notice a break.

### A plain `build_megas.py` run was erasing nine owner decisions

Found while checking whether it was safe to run at all, and it is the worst instance of this
session's recurring trap because it destroyed *authorial* data, not derived data.

`data/mega_ability_overrides.json` is authoritative — DATA_CONTRACT §11.5 says so, and CLAUDE.md
lists Heatran = `earth-eater` as a locked decision — but folding it in was **opt-in** behind
`--apply-owner-overrides`. A plain `python tools/build_megas.py` therefore shipped all nine
Champions-uncovered Megas as `abilities: []` / `abilityStatus: pending-owner`, silently, with
every one of its own checks still passing. Worse, it never emitted `abilityNote` at all, so the
recorded *reasoning* for each of the nine decisions existed only as a hand-edit in `megas.json`
and died on any rebuild — even with the flag passed.

Fixed: overrides are applied by default, the note is generated from the overrides file's `note`,
and `--no-owner-overrides` remains for inspecting the pre-decision state. `abilityNote` is now
emitted on all 97 forms (null where there is none), which is how `requiresMove` and
`requiresForm` already behave — it was the odd one out precisely because it was hand-added. The
nine notes are byte-identical to what was committed, and the rebuild is byte-stable.

**The general rule this session has now proved three times: if a file is authoritative, the
default path must apply it. An authoritative input that the default rebuild ignores is a
data-loss bug, not a safety flag.**

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
| ~~Evolutions~~ | `…/workflows/scripts/evolution-rework-wf_1e9f5bac-1a1.js` | **Superseded — §4c is done, do not re-run** |

Scripts live under
`C:\Users\James\.claude\projects\C--WINDOWS-system32\a73f5b2d-0c80-46b4-8c4a-4b379a448cba\workflows\scripts\`

---

## 4. Outstanding work, in priority order

**(a), (b), (c), the `population-bomb` half of (d), and the `items.json` follow-on are all
done.** What is left is (d)'s remaining gaps — chiefly **Protect**, which would activate
`unseen-fist` and `piercing-drill`, and the balance review of the 26 multi-strike moves —
and **(e), multi-slot battle formats**, which is now the largest single piece of engine work
left and is blocking a finished Custom Battle mode.


### a) ~~Fix the Roark reward hookup~~ — DONE 2026-09-26, see §2

### b) ~~Finish the dynamic rival starter~~ — DONE 2026-09-26, see §2

Data tagging (`tools/tag_dynamic_starter.py`) had already run; the engine side, the save
round-trip, the ability/move re-resolution and 21 tests all landed. Three roster observations
are listed in §2 for the owner to rule on.

### c) ~~Apply the evolution rework~~ — DONE 2026-09-26, see §2

All 73 edges converted or deleted, applied as part of `build_species.py`, proved by
`tools/check_reachability.py` and guarded by `tests/test_evolutions.gd`. `fix_evolutions.py`
was not a stub; it had three defects that stopped it writing, stopped it being idempotent, and
let a rebuild revert it. All fixed. **The follow-on is `data/items.json`** — 23 species are now
blocked only by the 40 missing evolution items.

**Still open, and an authorial call:** the cap-vs-availability check could not be completed.
An evolution level is an availability gate only relative to *where the line is found*, and
`data/maps/**` still carries no trainer or encounter placement for the 174 unbuilt areas — the
same gap that makes the EXP model's segment attribution inferred (see §4d). The levels are
sane in the absolute (369 levelled edges, max L64, nothing above 100, 20 edges at the new L37
and 19 at L40, matching the existing curve), but "is Gengar reachable *when* the player is
meant to have one" is only answerable for the nine built maps today. Gengar specifically was
checked and is correct: L37 lands it the moment Fantina is beaten and the Gengarite awarded.

### e) Double / triple / rotation battles — the engine is single-slot

**Custom Battle mode landed on 2026-09-27** (`src/custom/`, `scenes/Title.tscn`,
`scenes/CustomBattle.tscn`, `docs/CUSTOM_BATTLE.md`, `tests/test_custom_battle.gd`): pick both
teams from any species, set level / nature / ability / stone / moves, pre-fill either side
from any of the 31 boss rosters, pin the seed, watch the AI play itself, rematch. It shares
the engine and `Battle.tscn` with the campaign and writes nothing to the save.

Its format selector offers single / double / triple / rotation and **only single is
playable**. A non-single matchup is refused with the reason on screen rather than downgraded.
Making the other three real is an engine job, not a builder job:

* `sides[side]["active"]` is a single int, and `active(side)` returns one Pokemon;
* `damage.gd` targets `active(1 - side)` with no target parameter at all;
* actions carry no target — `{kind:"move", move_index:i}` has nowhere to put one;
* `turn_order.gd` sorts exactly two actions;
* `ai.gd` chooses one move for one Pokemon against one foe;
* spread moves need the 0.75 multiplier and redirection (Lightning Rod, Storm Drain, Follow
  Me) that single battles never exercise;
* triples need adjacency, rotations need rotating as a free action;
* every `onFieldEnter` / `onWeatherSet` / `onRedirect` ability hook needs re-checking against
  more than one opposing Pokemon.

When it lands, `format` goes into DATA_CONTRACT 13 **first**, and
`BattleSpec.IMPLEMENTED_FORMATS` is the single switch that unlocks it in the builder.

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

python tools/build_species.py           # 22 assertions; must pass
git status --short -- data/             # and must leave data/ CLEAN (rebuild is idempotent)

python tools/fix_evolutions.py          # expect "already-applied 73, errors 0"
python tools/check_reachability.py      # expect BROKEN_EVO 0, NEEDS_ITEM 0, RESULT: PASS

python tools/build_megas.py             # overrides applied by DEFAULT; 9 rows logged
python tools/build_items.py --apply     # 133 items (93 preserved + 40 evolution items)
git status --short -- data/             # still CLEAN, in either order
```

**Everything through 2026-09-26 is committed and pushed** on
`build/engine-data-and-vertical-slice`; `main` is still at the initial commit, so the branch
has not been merged. The ROMs and all ROM-derived output are gitignored — re-verify with the
`git check-ignore` line above before any commit.
