# Ability implementation: the 14 Mega-critical abilities, and the hook interface

**Status:** **IMPLEMENTED AND VERIFIED — 13 of 14 live, 1 declared-inert by design.** See
[section 11](#11-final-status--verified-by-the-reconciler) for the per-ability verdict, the evidence
behind each, and the reconciliation fixes. Sections 1–10 are the original spec and are kept as
written; where section 11 disagrees with them, section 11 is the record of what shipped.
**Scope:** the 14 abilities referenced by `data/megas.json` that sit at `tier: 3` (`hook: "none"`) in
`data/abilities.json`, plus the `src/battle/abilities/` interface they plug into.
**Written against:** `src/battle/` as of 2026-09-23 (`battle_engine.gd`, `damage.gd`, `status.gd`,
`stats.gd`, `turn_order.gd`, `mega.gd`, `ai.gd`, `deps.gd`), `docs/DATA_CONTRACT.md` §4 and §11.
**Baseline at time of writing:** `godot --headless --path . --script res://tests/run_tests.gd` →
`OK 2974 checks passed in 11 file(s)`.

---

## 0. Why this file exists

`data/megas.json` has 97 forms referencing 66 distinct abilities. 52 are `tier: 1`
(engine-implemented). **14 are `tier: 3` — data only, hook `none`, the engine does nothing.** None are
`tier: 2`. So there is no partial middle ground: for these 14 forms the ability line in the UI is a
lie.

The headline case is **Mega Gengar**. `docs/research/rosters-gyms14.md` line 83 already flags it:

> **Fantina's Mega Gengar has Shadow Tag**, which stops the player switching at all. … ruling **B9**
> forbids giving a boss an ability whose engine hook is not written. Two acceptable resolutions:
> (a) implement `shadow-tag` before gym 3 ships, or (b) run Fantina's Mega Gengar on **Cursed Body**.

Fantina is gym 3, the first boss in the game that Mega Evolves, and she hands over the Mega Ring.
This document exists so that resolution (a) is available. Ruling **B9** in `mega-design.md` also
currently forces two substitutions that this work reverses: **Mega Scizor stands in for Mega
Heracross** on Aaron's E4 team (needs `skill-link`, line 667) and **Mega Lucario Z is blocked** as a
boss Mega (needs `aura-guard`, line 660).

Six of the 14 are **not Mega-exclusive**, so implementing them fixes base-form species too:

| ability | other holders in `data/species.json` |
|---|---|
| `shadow-tag` | Wobbuffet (202) |
| `skill-link` | Cloyster (91) |
| `steadfast` | Lucario (448), Gallade (475) |
| `unseen-fist` | Urshifu (892) |
| `stalwart` | — (Mega Skarmory only here; Duraludon/Archaludon ship other abilities) |
| `parental-bond`, `delta-stream`, `aura-guard`, `piercing-drill`, `spicy-spray`, `mega-sol`, `dragonize`, `eelevate`, `fire-mane` | Mega-exclusive |

That Urshifu row decides a version question outright — see §2.2.

---

## 1. The engine as it stands: what the 14 abilities can and cannot lean on

Read before writing anything. These are grep-verified absences, not guesses.

**There is no ability dispatch anywhere.** The only two abilities with any engine effect are
hard-coded string compares: `damage.gd:177` (`adaptability`) and `status.gd:81` (`guts`). The
`hook` field in `data/abilities.json` is documentation — no code reads it. `DataRegistry` indexes
abilities by **int id**, not slug; `Deps.JsonRegistry` does not load them at all.

**None of these exist in the engine:** Protect / any protection move, Substitute, trapping or
switch-blocking, multi-hit moves, entry hazards, terrain, Long Reach, grounding, redirection,
weather-setting moves. `grep -ril` over `src/battle/` for `protect|substitute|trap|multihit|hazard|
spikes|terrain|grounded|levitate|contact` returns **nothing**.

**Weather** is two engine fields — `weather: String` and `weather_turns: int` — set only from
`start()`'s setup payload and decremented in `_end_of_turn()`. `Damage.weather_mult()` returns 1.0
for any string it does not recognise, so a new weather value is safe to introduce.

**`_use_move()` resolves exactly one hit** (`battle_engine.gd:432-472`): one accuracy check, one
`Damage.compute`, one `apply_hp_delta`, then `_apply_damage_side_effects`.

### 1.1 Two blockers in shared files. Fix these first, in this order.

**Blocker A — `Stats.make_move()` drops `flags` and `effectId`** (`stats.gd:245-266`). The battle-ready
move dict it returns carries `id, name, slug, type, category, power, accuracy, pp, maxPp, priority,
effect, effectChance` and nothing else. `data/moves.json` has a `flags` array
(`contact` on 245 moves, `protect` on 593, plus `punch`, `sound`, `authentic`, `charge`, …) and an
`effectId` int — **both are discarded before the engine ever sees a move.**

Four of the 14 abilities cannot be written until this is fixed: `aura-guard`, `unseen-fist`,
`piercing-drill` need `contact`; `skill-link` and `parental-bond` need `effectId`.

```gdscript
# src/battle/stats.gd, inside make_move()'s returned Dictionary — add two keys:
		"effectId": int(src.get("effectId", 0)) if src.get("effectId", null) != null else 0,
		"flags": PackedStringArray(src.get("flags", [])),
```

Additive, backward-compatible, and no existing test reads either key.

**Blocker B — `move.effect` is unreliable, `effectId` is not.** 57 Gen 9 moves in `data/moves.json`
have `"effect": null` (`population-bomb`, `triple-dive`, `tachyon-cutter`, `glaive-rush`, …). Worse,
`make_move` does `String(src.get("effect", ""))`, and **`String(null)` in GDScript 4 is `"<null>"`,
not `""`** — a trap `mega.gd:222-226` already documents and works around with its `_opt()` helper.
So `move.effect` for those moves is the literal five-character string `<null>`.

Consequence: **never branch on `move.effect` for multi-hit detection.** Use `effectId`. The
multi-hit families, confirmed by scanning `data/moves.json`:

| `effectId` | meaning | hits | per-hit accuracy | moves |
|---|---|---|---|---|
| 30 | `hits-2-5-times-in-one-turn` | 2–5 | no | double-slap, comet-punch, fury-attack, pin-missile, spike-cannon, barrage, fury-swipes, bone-rush, arm-thrust, bullet-seed, icicle-spear, rock-blast, tail-slap |
| 361 | `hits-2-5-times` | 2–5 | no | water-shuriken |
| 443 | Scale Shot | 2–5 | no | scale-shot |
| 105 | Triple Kick family | 3 | **yes** | triple-kick, triple-axel |
| 45 | `hits-twice-in-one-turn` | 2 fixed | no | double-kick, bonemerang, double-hit, dual-chop, gear-grind, double-iron-bash, dual-wingbeat |
| 78 | Twineedle | 2 fixed | no | twineedle |
| 450 | Dragon Darts | 2 fixed | no | dragon-darts |
| 486 | Surging Strikes | 3 fixed | no | surging-strikes |

**Data gap, worth one line in `tools/build_species.py`:** `population-bomb` (1–10, per-hit accuracy),
`triple-dive` (3 fixed) and `tachyon-cutter` (2 fixed) have `effectId: null` and so are invisible to
any multi-hit implementation. Population Bomb is the one that matters — it is Skill Link's biggest
payoff in Gen 9 and would silently hit once. Not a blocker for the 14 (no Mega learns it), but
record it.

### 1.2 The 2–5 hit distribution

Not needed by the two abilities here (both force the maximum) but the host loop needs it to exist.
Gen 5+: **3/8, 3/8, 1/8, 1/8** for 2, 3, 4, 5 hits. Implement as
`[2, 2, 2, 3, 3, 3, 4, 5][rng.randi_range(0, 7)]`.

---

## 2. Version decisions

The project's stated rule, from `status.gd`'s own docstring — *"where Gen 5 and Gen 6+ disagree this
file takes the modern behaviour"* — and `damage.gd`'s *"Critical hits multiply by 1.5, not the Gen 5
2.0"*. **Newest official behaviour wins.** Two of the 14 need that rule applied explicitly.

### 2.1 Parental Bond: the second hit is **0.25×**, not 0.5×

Three reasons, in order of weight:

1. **The version rule decides it.** Gen 6 was 0.5×; Generation VII onward is 0.25×. The project takes
   the newest official behaviour everywhere else, including in the same damage chain this multiplier
   lives in.
2. **The Mega ability table is sourced from Pokémon Champions (Gen 9).** `mega-abilities.md` §2
   resolves this game's Mega ability assignments from Champions. Using a Gen 6 number for a
   Gen 9-sourced table is internally inconsistent.
3. **Balance is *not* the deciding factor here, and that is worth saying plainly.** `kangaskhanite` is
   a **Battle Park BP purchase** (`mega-design.md:551`) — post-Hall-of-Fame, at cap 100, where the
   level-cap system no longer bites. Either number would be survivable. The version rule is left to
   decide it cleanly, which it does.

At 0.25× the ability is ~1.25× total power with two independent secondary-effect rolls; at 0.5× it is
~1.5× and was the defining banned Mega of Gen 6. If a future owner ruling wants the Gen 6 number, it
is one constant in one file (`SECOND_HIT_MULT`) and no other ability changes.

### 2.2 Unseen Fist: **full damage** through protection — mainline, not the Champions nerf

Bulbapedia records two different behaviours:

- **Generation VIII–IX (mainline):** contact moves bypass protection at **full damage**, every
  protection move except Max Guard.
- **Pokémon Champions:** contact moves that bypass protection deal only **25%** damage.

Take mainline. The deciding argument is one line of shipped data: **`data/species.json` gives
Urshifu (id 892) `unseen-fist` as its species ability.** Unseen Fist is a mainline ability that this
game's dex already hands to a non-Mega species, so it must follow mainline rules; implementing the
Champions nerf would silently wrong Urshifu. Two supporting points:

- `data/abilities.json` already ships the mainline text: *"Contact moves can strike through
  Protect/Detect."* No damage clause.
- Under the Champions reading, Unseen Fist and **Piercing Drill become byte-identical**, which would
  make Mega Excadrill's *signature* ability a duplicate. Keeping mainline for Unseen Fist and
  Champions for Piercing Drill (Champions-only, no mainline holder) keeps them distinct and keeps
  both faithful to their own source.
- Mega Golurk has Speed 55. Full-damage Protect-break is its only real trick.

**Flag for the owner.** A strict "Champions everywhere" ruling would set both to 0.25× and make them
duplicates. The `PIERCE_DAMAGE_MULT` constant is per-file, so reversing this is a one-line edit in
`unseen_fist.gd` and touches nothing else.

---

## 3. The 14 specs

Each entry gives the source text **verbatim**, then the rule restated as something implementable,
then the edge cases a naive implementation gets wrong. `confidence` is one of
*documented-exact* (published effect text covers the whole mechanic),
*documented-partial* (published text leaves a gap, named below),
*inferred* (no published text; reasoned from family behaviour, marked as such).

---

### 3.1 `shadow-tag` — Mega Gengar — **THE PRIORITY**

**Source:** https://bulbapedia.bulbagarden.net/wiki/Shadow_Tag_(Ability) · confidence: **documented-exact**

**Verbatim (Generation VI onward):** *"Ghost-type Pokémon are now immune to Shadow Tag. In Pokémon X
and Y, Shadow Tag will not prevent roaming Pokémon from fleeing because they will flee before the
battle even starts."* Plus, from the same Effect section: prevents opponent switching and fleeing;
holding a **Shed Shell** allows switching but not fleeing or Teleport; **U-turn, Volt Switch, Baton
Pass and Parting Shot** still switch; the **Run Away** ability permits fleeing but not switching.

**Rule.** While a Pokémon with Shadow Tag is on the field and not fainted, the opposing active
Pokémon may not choose the `switch` action and may not choose `run`. Blocked when **any** of:

- the would-be escaper has type `ghost` (Gen 6+; this is the exception that matters — Fantina's own
  team is Ghost-typed and the *player's* Ghosts walk free);
- the would-be escaper holds `shed-shell` (switch allowed, run still blocked);
- the would-be escaper itself has `shadow-tag` (mutual immunity);
- the trapper has fainted or left the field.

A **forced replacement** after a faint is never blocked. This is the single most important negative
rule in the file: `battle_engine._check_faints()` sets `awaiting_switch`, and if trapping applied
there the battle would deadlock with no legal action.

**Hooks:** `on_switch_attempt` (trapper-side).

**Edge cases a naive implementation gets wrong:**

1. **Ghost immunity.** Gen 4/5 Shadow Tag trapped everything. Gen 6+ exempts Ghost-types entirely.
   Get this wrong and Fantina's Mega Gengar traps the player's Ghost-type answers to it.
2. **Forced replacement must not be blocked** (deadlock, above).
3. **It must block the AI too.** `battle_engine.auto_action()` passes `can_switch` into
   `ai.choose_action()` (`ai.gd:63`). Trapping has to be folded into that boolean or a trapped AI
   will emit a `switch` action that `_execute` then performs anyway — `_execute` calls `_switch_in`
   directly and never re-validates.
4. **Three separate call sites**, and missing any one leaves a hole: `submit_action()` (the player's
   UI path, must return `false`), `auto_action()` (`can_switch`), `_try_run()` (wild flee).
5. **`_try_run` only exists for wild battles.** Mega Gengar is a trainer Mega, so the run path is
   reachable only via a wild Wobbuffet — which is exactly why Wobbuffet is in the dex.
6. **The trapper is checked live, not latched.** If Gengar faints on the same turn the player tries
   to switch, the switch is legal again next turn.
7. Message: `"%s can't escape!"` — `_try_run` already uses `"Can't escape!"` for the odds-based
   failure, so use the named form to tell them apart in the log.
8. `arena-trap` and `magnet-pull` are also `tier: 3 / hook: none` (Dugtrio, Trapinch, Nosepass…).
   They are the same hook with different predicates — Arena Trap needs `is_grounded()` (§3.13), Magnet
   Pull needs `types.has("steel")`. Write `on_switch_attempt` so they drop in without a second seam.

---

### 3.2 `parental-bond` — Mega Kangaskhan

**Source:** https://bulbapedia.bulbagarden.net/wiki/Parental_Bond_(Ability) · confidence: **documented-exact**

**Verbatim:** Gen VI — *"The second strike has its damage halved"*; Generation VII onward — *"The
second strike now deals 25% of its usual damage"*. On secondaries: *"Any attack which has a secondary
effect (except Secret Power) has the same secondary effect on both strikes"*, with independent
activation chances. On recoil: *"based on the damage dealt by both strikes, but will be taken after
the final strike."* On accuracy: *"There is only one accuracy check, so either both strikes hit or
both strikes miss."*

**Rule.** A damaging move that is not excluded hits **twice**. Hit 1 is normal; hit 2 is computed
identically with `damage_mult = 0.25` (§2.1). One accuracy check for the pair. Secondary-effect
chance rolls **once per hit**. Drain heals per hit. Recoil is computed from the **summed** damage and
applied once, after hit 2.

**Excluded** (verbatim list): multistrike moves, one-hit KO moves, Fling, Self-Destruct, Explosion,
Final Gambit, Uproar, Rollout, Ice Ball, moves with a charging turn (Fly, Solar Beam, …), Endeavor.
Also excluded, by category: status moves, and fixed-damage moves generally (Dragon Rage, Sonic Boom,
Night Shade, Seismic Toss) — the engine has none of these as special cases yet, so this reduces to:
**skip when the move already has a multi-hit `effectId`, has the `charge` flag, or is `category ==
"status"`.**

**Hooks:** `on_multi_hit_count` (returns 2), `on_damage_calc` (`damage_mult: 0.25` when
`ctx.hit_index == 1`).

**Edge cases:**

1. **One accuracy check, not two.** A per-hit accuracy loop would make Mega Kangaskhan miss half of a
   90%-accurate move twice as often. The host loop must roll accuracy once, outside it.
2. **`effectChance` rolls per hit** — that is the real reason Parental Bond was broken, not the raw
   damage. `_apply_damage_side_effects` must run per hit.
3. **Stop if the target faints on hit 1.** `_apply_damage_side_effects` already guards with
   `if Stats.is_fainted(defender): return`; the hit loop needs the same guard, and the KO hook
   (§3.13) must fire on hit 1 rather than after the loop.
4. **Do not stack with a multi-hit move.** Bullet Seed does not become 10 hits. Guard on `effectId`.
5. **Charge moves are excluded** — and the engine does not implement charging at all yet, so Solar
   Beam currently fires the turn it is used. Excluding by the `charge` flag is right today and stays
   right when charging lands.
6. **Recoil after the last hit, from summed damage.** `_apply_damage_side_effects` computes recoil
   from that hit's `dealt`; calling it twice would apply recoil twice, at the wrong size.
7. 0.25 is a *damage* multiplier, not a power multiplier — it is applied at the end of the chain, so
   it interacts correctly with the `maxi(1, dmg)` floor: a 0.25× hit still does at least 1.

---

### 3.3 `steadfast` — Mega Mewtwo X (also Lucario, Gallade)

**Source:** https://bulbapedia.bulbagarden.net/wiki/Steadfast_(Ability) · confidence: **documented-exact**

**Verbatim:** flavour (Gen IX) — *"The Pokémon's determination boosts its Speed stat every time it
flinches."* Effect — *"Steadfast increases the Pokémon's Speed stat by one stage whenever it flinches.
The Speed boost will only apply if the flinching message is displayed."*

**Rule.** When the bearer's flinch actually costs it its turn — i.e. exactly where
`"%s flinched and couldn't move!"` is printed — raise its Speed one stage. Every time, no cap beyond
the normal +6.

**Hooks:** `on_flinch`.

**Edge cases:**

1. **Tie it to the message, not to the volatile flag.** *"only apply if the flinching message is
   displayed"* is the mechanic. In this engine `Status.before_move()` (`status.gd:174-178`) is the one
   place that prints it, and it clears `vol.flinch` in the same breath — so a check after the fact
   sees nothing. Have `before_move` report it (§5.3).
2. **Ordering: the flinch still happens.** Speed rises and the turn is still lost. Since Mega Mewtwo
   X already moves at 130 Speed, the boost is felt on the *next* turn.
3. Do not fire when a flinch is *prevented* (Inner Focus, a Substitute). Neither is implemented, and
   routing through the message keeps it correct for free once they are.
4. **Not Mega-exclusive** — base Lucario and Gallade both have it, so the test matrix should include
   a non-Mega holder.
5. The flinch chain is unchanged: `Status.set_flinch()` from a secondary, consumed in `before_move`.
   Steadfast adds a stat change, never a `can_move` change.

---

### 3.4 `skill-link` — Mega Heracross (also Cloyster)

**Source:** https://bulbapedia.bulbagarden.net/wiki/Skill_Link_(Ability) · confidence: **documented-exact**

**Verbatim:** flavour (Gen VII+) — *"Maximizes the number of times multistrike moves hit."* Champions —
*"The Pokémon's multistrike moves always hit the maximum number of times."* Effect (Gen V onward): if
Skill Link is lost mid-move the user still hits the maximum that turn; it affects Triple Kick
(max 3) and Population Bomb (max 10); it gives *"one accuracy check for all strikes instead of
individual checks per strike."*

**Rule.** Two changes, both on moves with a **variable** hit count:

1. Hit count becomes the **maximum** of the range (2–5 → 5; Triple Kick/Axel → 3; Population Bomb → 10).
2. **Per-hit accuracy is switched off.** Triple Kick and Triple Axel normally roll accuracy before
   each strike; with Skill Link they roll once and all three land.

Moves with a fixed hit count (`effectId` 45, 78, 450, 486 — Double Kick, Twineedle, Dragon Darts,
Surging Strikes) are **not affected**: *"it does not affect moves that already hit a fixed number of
times."*

**Hooks:** `on_multi_hit_count` (return the range maximum, and clear `single_accuracy = false`).

**Edge cases:**

1. **Fixed-count moves are untouched.** Gear Grind stays 2 hits. Branch on `effectId`, per the table
   in §1.1 — this is the single most common way to get Skill Link wrong.
2. **Triple Kick's per-hit accuracy must actually be removed**, not just its count raised. This is the
   half people skip. Mechanically it is Showdown's `delete move.multiaccuracy`.
3. **Triple Kick's escalating power is unaffected** — 10/20/30 base power across the three hits
   (`effectId` 105: *"increasing power by 100% with each successful hit"*). Skill Link guarantees the
   hits; it does not flatten the power ramp. Mega Heracross does not learn it, but Hitmontop-style
   users will.
4. **Losing the ability mid-move keeps the max** (Gen 5+). Decide the count once, before the loop.
5. **This is the whole point of Mega Heracross:** five-hit Pin Missile / Arm Thrust breaks Sturdy and
   Focus Sash and out-damages a single big hit. `mega-design.md:667` reverts Aaron's Mega Scizor back
   to Mega Heracross the moment this lands.
6. **Population Bomb is invisible today** (`effectId: null`, §1.1). Not a Mega problem; note it so the
   next person does not conclude the hook is broken.
7. Cloyster has it too — Icicle Spear at 5 hits is a real early-game power spike if Cloyster is
   catchable before a cap that expects it.

---

### 3.5 `delta-stream` — Mega Rayquaza

**Sources:** https://bulbapedia.bulbagarden.net/wiki/Delta_Stream_(Ability) and
https://bulbapedia.bulbagarden.net/wiki/Strong_winds · confidence: **documented-exact**

**Verbatim (Delta Stream):** sets the weather **"strong winds"** on entry or on gaining the ability;
persists *"as long as there is an active Pokémon on the field with Delta Stream"*, ending when that
Pokémon switches out, faints or loses the ability. *"Electric-, Ice-, and Rock-type moves … deal
neutral damage to Flying-type Pokémon."* It *"can be replaced by Desolate Land or Primordial Sea"* and
by nothing else. Sunny Day, Rain Dance, Sandstorm and Hail *"fail if used"*; Drought, Drizzle, Sand
Stream and Snow Warning *"fail to activate."* If Delta Stream is suppressed or replaced, strong winds
*"will dissipate."*

**Verbatim (Strong winds), on dual types:** *"if a move is not super effective against the Pokémon's
other type, this no longer counts as a supereffective hit."* Messages: activation *"Mysterious strong
winds are protecting Flying-type Pokémon!"*; persistence *"The mysterious air current blows on
regardless!"*; on weakening *"The mysterious air current weakened the attack!"*; end *"The mysterious
air current has dissipated!"* Strong winds do **not** affect Stealth Rock or Anticipation.

**Rule — and this is the part that is easy to get wrong.** It is a **per-defending-type-component**
clamp, not a whole-move clamp:

> While the weather is `strong-winds`: when computing type effectiveness, for each of the defender's
> types, if that type is `flying` and its own multiplier against the incoming move type is **> 1**,
> use **1.0** for that component instead. Every other component is untouched.

That is exactly Showdown's rule (`type === 'Flying' && typeMod > 0 → 0`). Worked examples for Mega
Rayquaza (Dragon/Flying):

| move type | Dragon | Flying | normal total | under strong winds |
|---|---|---|---|---|
| Ice | 2 | 2 | **4×** | 2 × 1 = **2×** |
| Rock | 1 | 2 | **2×** | 1 × 1 = **1×** |
| Electric | 0.5 | 2 | **1×** | 0.5 × 1 = **0.5×** |
| Dragon | 2 | 1 | 2× | unchanged **2×** |
| Fighting | 1 | 0.5 | 0.5× | unchanged **0.5×** |

The Electric row is the famous quirk and the best single test case: a *neutral* matchup becomes
*resisted*, because the clamp is applied per component rather than to the product.

It is a **field state, not a mon state**: while strong winds are up they protect **every**
Flying-type on the field, including Mega Rayquaza's opponents.

**Hooks:** `on_field_enter`, `on_field_leave`, `field_state()` (returns `"strong-winds"`),
`on_effectiveness` (field-scoped), `blocks_weather_set`.

**Edge cases:**

1. **Per-component, not per-move.** Clamping the product to 1.0 would leave Ice at 1× instead of 2×
   and Electric at 1× instead of 0.5×. Both wrong, in opposite directions.
2. **Only weaknesses are removed.** Resistances and immunities are untouched; Ground still does 0 to
   a Flying-type.
3. **It occupies the weather slot.** Set `weather = "strong-winds"`, `weather_turns = 0` (the existing
   `_end_of_turn` code only decrements when `weather_turns > 0`, so 0 already means *infinite* — no
   new state needed). `Damage.weather_mult()` returns 1.0 for it, so no Fire/Water multiplier leaks in.
4. **It must be re-evaluated on every field change**, not only on switch-in: Mega Evolution mid-battle
   is how Mega Rayquaza *acquires* the ability (`mega.gd` sets `mon["ability"]` during `evolve()`), so
   the check belongs after `mega_evolve()`, after `_switch_in()`, and after a faint.
5. **It ends when the holder leaves** — and if the previous weather is gone with it, the field is
   simply clear. Do not try to restore what was there before; the games do not.
6. Weather-setting moves and abilities are not implemented, so `blocks_weather_set` has no caller
   today. Declare it anyway: `drizzle`/`drought`/`sand-stream`/`snow-warning` are all `tier: 1` and
   will arrive, and the failure mode (a grunt's Drizzle deleting Mega Rayquaza's field) is invisible.
7. Mega Rayquaza is the one stoneless Mega (`requiresMove: dragon-ascent`, DATA_CONTRACT §11.5) — a
   post-game fight, so there is no cap interaction to worry about.

---

### 3.6 `stalwart` — Mega Skarmory

**Source:** https://bulbapedia.bulbagarden.net/wiki/Stalwart_(Ability) · confidence: **documented-exact**

**Verbatim:** flavour — *"Ignores the effects of opposing Pokémon's Abilities and moves that draw in
moves."* Effect — bypasses target-redirecting effects from both moves and abilities, specifically
**Rage Powder, Follow Me, Ally Switch, Storm Drain, Lightning Rod**. *"The ability has no practical
effect in single battles since redirecting moves and abilities only function in double/triple
battles."* Identical to **Propeller Tail**.

**Rule.** `ignores_redirection()` returns `true`. Nothing else.

**This is a deliberate no-op in this engine, and the spec says so rather than inventing an effect.**
`battle_engine.gd` line 4: *"Single battles only, two sides."* There are no double battles in
`DATA_CONTRACT.md` or `game-design.md`. Redirection cannot occur, so Stalwart cannot do anything.
`data/moves.json` does carry `follow-me`, `rage-powder` and `spotlight`, and `lightning-rod` /
`storm-drain` are `tier: 1` — all inert for the same reason.

**Hooks:** `ignores_redirection` (declared, unreachable).

**Edge cases:**

1. **Do not invent a single-battle effect for it.** Some fan implementations give Stalwart
   "ignore the target's ability" — that is Mold Breaker, a different ability that *is* `tier: 1`.
   Conflating them would silently buff Mega Skarmory past its 140 Attack.
2. Ship the file anyway: flipping `tier: 3 → 1` for `stalwart` is what unblocks ruling **B9** for Mega
   Skarmory, and B9 is about *declared vs implemented*, not about observable effect. `propeller-tail`
   is also `tier: 3` and is the same file with a different slug.
3. Mega Skarmory is a **gym-leader Mega** (`mega-design.md:656`: all five gym Megas use tier-1
   abilities) — so this row exists to keep that claim true, cheaply.
4. If doubles ever land, the hook is already in the right place and the redirection resolver just has
   to ask.

---

### 3.7 `unseen-fist` — Mega Golurk (also Urshifu)

**Source:** https://bulbapedia.bulbagarden.net/wiki/Unseen_Fist_(Ability) · confidence: **documented-partial**

**Verbatim:** flavour (Gen VIII–IX) — *"If the Pokémon uses moves that make direct contact, it can
attack the target even if the target protects itself."* Effect, Gen VIII–IX — contact moves bypass
protection moves at full damage, **except Max Guard**; works while holding Protective Pads but **not**
while holding a Punching Glove. Effect, Pokémon Champions — *"Contact moves now deal only 25% damage
when bypassing protections. All other move effects still trigger."*

**Where the page is thin, plainly:** Bulbapedia names **only Max Guard** as not bypassed. It does not
enumerate behaviour against Crafty Shield, Wide Guard, Quick Guard, Mat Block, Obstruct, King's
Shield, Spiky Shield, Baneful Bunker, Silk Trap or Burning Bulwark. Do not invent per-move rules:
implement "bypasses protection, except Max Guard" and let the protection layer decide the rest.
(`max-guard` is in `data/moves.json` as a Gen 8 Dynamax move; Dynamax is excluded by DATA_CONTRACT
§11.4, so Max Guard should never be reachable and the exception is inert.)

**Rule.** When the bearer uses a move with the `contact` flag against a target that is protected, the
move **hits anyway, at full damage**, and everything the move would normally do still happens. See
§2.2 for why full damage and not the Champions 25%.

**Hooks:** `on_protect_check` → `{pierce: true, damage_mult: 1.0}`.

**Edge cases:**

1. **Contact only.** Mega Golurk's Shadow Punch and Earthquake are different cases: Shadow Punch has
   `contact`, Earthquake does not. Read `move.flags`, which requires Blocker A (§1.1).
2. **"Everything aside from the target's protective effects is still triggered"** — the protection is
   ignored, not the move's own secondaries. Hitting through Protect still lands the flinch chance.
3. **The protection move's own punish still applies.** Piercing King's Shield should still drop the
   attacker's Attack. Not implemented, so record it as a forward rule rather than a silent omission.
4. **Urshifu shares it** (§0). Any version choice made for Mega Golurk lands on Urshifu too. That is
   the argument in §2.2.
5. Protect does not exist in the engine (§1, §6.1), so this ability is **spec-complete and dormant**
   at merge. Its unit test sets `vol["protect"] = true` by hand — see §7.
6. Protective Pads / Punching Glove are not implemented; both are item-level modifiers to the
   *contact flag*, which is the right place for them later, not inside this ability.

---

### 3.8 `aura-guard` — Mega Lucario Z

**Source:** https://bulbapedia.bulbagarden.net/wiki/Aura_Guard_(Ability) · confidence: **documented-exact**

**Verbatim:** flavour — *"Halves the damage the Pokémon takes from contact moves."* Effect — *"A
Pokémon with Aura Guard takes half damage from moves that make contact. Moves affected by Long Reach
which make contact will deal regular damage."* Bearer only; does not protect allies. Mega Lucario Z
(0448) only; Generation IX, Pokémon Champions.

**Rule.** When the bearer is the **defender** and the incoming move has the `contact` flag, multiply
final damage by **0.5**.

**Hooks:** `on_damage_calc`, defender side → `{damage_mult: 0.5}`.

**Edge cases:**

1. **It is a final damage multiplier, not a Defence multiplier.** Fluffy is the exact precedent
   (Showdown: `onSourceModifyDamage → chainModify(0.5)`). Doubling Defence instead would give a
   different number after the formula's integer division and would wrongly interact with crits, which
   ignore positive Defence stages.
2. **Contact only** — so it halves Close Combat and does nothing to Aura Sphere. Requires Blocker A.
3. **Long Reach exception:** an attacker with Long Reach loses the contact flag, so Aura Guard does not
   apply. `long-reach` is `tier: 3 / hook: none`, so this is inert today. Implement the exception as
   "the contact flag is removed by the attacker" rather than as a special case inside `aura-guard`,
   and it resolves itself when Long Reach lands.
4. **Defender-side abilities must be reachable from the damage call site.** `Damage.compute` currently
   only reads the *attacker's* ability (for Adaptability). The dispatcher has to fold both sides —
   see §5.1.
5. Mega Lucario Z is 70/70/70 defensively at 164 SpA — a glass cannon whose whole survivability story
   is this ability. `mega-design.md:660` blocks it as a boss Mega until this lands.
6. It does **not** halve indirect damage: burn, poison, recoil, hazards. Only contact moves.

---

### 3.9 `piercing-drill` — Mega Excadrill

**Sources:** https://bulbapedia.bulbagarden.net/wiki/Piercing_Drill_(Ability) and
https://www.pokemon-zone.com/champions/abilities/piercing-drill/ · confidence: **documented-exact**

**Verbatim:** *"When the Pokémon uses contact moves, it can hit even targets that are protecting
themselves, dealing 1/4 of the damage that the move would otherwise deal. Everything aside from the
target's protective effects is still triggered."* Effect — contact moves hit through protection moves
for 25% of normal damage. Mega Excadrill (0530) only; Generation IX, Pokémon Champions.

**Rule.** Identical to Unseen Fist's plumbing, with `damage_mult = 0.25` on the pierced hit.
`data/abilities.json`'s stored text for this slug is **truncated** — it stops before the "1/4 of the
damage" clause. The Bulbapedia flavour text above is the complete one; the shipped row should be
corrected (§8).

**Hooks:** `on_protect_check` → `{pierce: true, damage_mult: 0.25}`.

**Edge cases:**

1. **The 0.25 applies only when protection was actually pierced.** An unprotected target takes full
   damage. This is the difference between a niche ability and a permanent 75% damage penalty.
2. **Contact only** (Blocker A). Mega Excadrill's Earthquake is not a contact move; Drill Run and
   Iron Head are.
3. **Secondaries still fire on the pierced hit** — *"everything aside from the target's protective
   effects."* Flinch chances, stat drops, the KO hook: all normal.
4. **Multiply, do not floor to zero.** A 0.25× hit still respects `maxi(1, dmg)`.
5. Same dormancy as §3.7: no Protect in the engine yet.
6. Mega Excadrill is a `za` form with 165 Attack and Speed 103 — post-game. No cap interaction.

---

### 3.10 `spicy-spray` — Mega Scovillain

**Source:** https://bulbapedia.bulbagarden.net/wiki/Spicy_Spray_(Ability) · confidence: **documented-exact**

**Verbatim:** flavour — *"When the Pokémon takes damage from a move, it burns the attacker."* Effect —
activates when hit by **any damaging move (not limited to contact moves)**; burns the attacker *"even
if the Spicy Spray user faints in the same turn"*; does not activate if the **Spicy Spray user** is
behind a Substitute; the burn still applies if the **attacker** is behind a Substitute; multistrike
moves trigger it **per hit**.

**Rule.** After any damaging move deals damage to the bearer, apply `burn` to the attacker via the
normal `Status.apply()` path. Fires even if the bearer fainted from that hit. Fires once per hit of a
multi-hit move.

**Hooks:** `on_hit_taken` (**not** `on_contact_taken` — see edge case 1).

**Edge cases:**

1. **Any damaging move, not contact moves.** This is the trap: it looks like Flame Body / Rough Skin
   and it is not. A contact-only implementation would fail to burn Flamethrower, Earthquake, Thunderbolt
   — i.e. most of what actually hits Mega Scovillain. This is precisely why the interface needs
   `on_hit_taken` alongside `on_contact_taken` (§4.2 hook 9).
2. **Fires from beyond the grave.** *"even if the Spicy Spray user faints."* In `_use_move`, the burn
   must be applied before the hit loop breaks out on the defender's faint, and before
   `_check_faints()` reverts the Mega.
3. **Per hit on a multi-hit move.** With a burn-curing item in play that can mean two burns. The
   engine has no Lum Berry, so practically it means: the hook is called from inside the hit loop, not
   after it.
4. **Normal burn rules still gate it**, all of them already in `status.gd`: Fire-types are immune
   (`IMMUNE_TYPES[BURN] == ["fire"]`), a target that already has a non-volatile status is refused
   (`reason: "already"`), a fainted target is refused. Just call `Status.apply(attacker, BURN, rng)`
   and let it say no — do not re-implement the checks.
5. **Mega Scovillain is Grass/Fire**, so it is immune to its own medicine in mirror matches, and the
   burn's physical-attack halving (`status.gd:79-83`) is the real payoff against physical attackers.
6. No `effectChance` roll — it is **100%**, unlike Flame Body's 30%.

---

### 3.11 `mega-sol` — Mega Meganium

**Sources:** https://pokemondb.net/ability/mega-sol (owner-supplied) and
https://bulbapedia.bulbagarden.net/wiki/Mega_Sol_(Ability) · confidence: **documented-exact**

**Verbatim (pokemondb, owner-supplied):** the ability allows a Pokémon to use moves *"as if the
weather is harsh sunlight."* Moves like Solar Beam only require one turn. *"The effect does not extend
to other Pokémon on the field."*

**Verbatim (Bulbapedia, the complete version):** flavour — *"Even when the sunlight has not turned
harsh, the Pokémon can use its moves as if the weather were harsh sunlight."* Effect — all moves used
by the bearer behave as though the weather is harsh sunlight, regardless of actual weather:

- Solar Beam and Solar Blade execute in one turn without charging; power is not halved in rain,
  sandstorm or snow
- Growth boosts Attack and Special Attack by **two** stages each
- Weather Ball becomes Fire-type with base power 100
- Synthesis, Moonlight and Morning Sun restore **⅔** maximum HP
- Thunder and Hurricane accuracy drops to **50%**
- **Fire-type moves gain 50% power; Water-type moves (except Hydro Steam) lose 50% power**
- moves ignore the sandstorm Sp. Def boost for Rock-types and the snow Def boost for Ice-types
- moves ignore accuracy reduction from Sand Veil and Snow Cloak

*"The ability does not alter actual weather and is unaffected by Cloud Nine."*

The owner-supplied pokemondb page gave only the Solar Beam clause; Bulbapedia supplies the rest,
including the Fire/Water damage multipliers, which are the part that actually matters in this engine.

**Rule.** A **per-mon weather view**. Everywhere the engine reads `weather` in order to resolve *this*
Pokémon's move, substitute `"sun"`. The field's real weather is unchanged — for the opponent, for
residual damage, for `_end_of_turn`, for everything else.

In today's engine that reduces to exactly two live effects, and both fall out for free:

- `Damage.weather_mult("sun", move_type)` → Fire ×1.5, Water ×0.5 on **Mega Meganium's own moves**
- the sandstorm Rock Sp. Def boost in `damage.gd:104-106` is skipped, since the view is `"sun"`, not
  `"sandstorm"`

The other bullets are dormant because their features do not exist (no charge turns, no Weather Ball
resolution, no weather-scaled healing, no weather-modified accuracy, no Sand Veil). All of them
become correct automatically if those features read the weather **through the view** rather than
through the field.

**Hooks:** `on_weather_view` → returns `"sun"`.

**Edge cases:**

1. **The bearer's moves only.** *"The effect does not extend to other Pokémon on the field."* If it
   were applied to the field, the opponent's Fire moves would get the boost too. So the view must be
   keyed on the mon whose move is resolving, and the AI's scoring call (`ai.gd`, which receives
   `weather` as a plain string) must use the same view or the AI will mis-price Mega Meganium's moves.
2. **It does not set weather**, so it never conflicts with Delta Stream's field state, never blocks a
   weather move, and is never displaced by one. Mega Meganium under rain is *simultaneously* rained on
   (for residual/opponent purposes) and sunlit (for its own moves).
3. **Unaffected by Cloud Nine / Air Lock** (which are `tier: 2` and inert) — if either lands, it must
   suppress the *field*, not the view.
4. **Mega Meganium is Grass/Fairy with 143 SpA and no Fire moves in a normal Grass learnset.** The
   honest read: today the Fire ×1.5 half is mostly theoretical and the Water ×0.5 half is a small
   self-nerf on Hidden Power–style coverage. The real payoff is one-turn Solar Beam, and **that needs
   charge turns to exist first**. Say so rather than overselling the ability.
5. Weather Ball at Fire/100 is the one line worth adding to Mega Meganium's movepool if the design
   wants the ability to be felt before charging lands.

---

### 3.12 `dragonize` — Mega Feraligatr

**Sources:** https://pokemondb.net/ability/dragonize (owner-supplied) and
https://bulbapedia.bulbagarden.net/wiki/Dragonize_(Ability) · confidence: **documented-partial**

**Verbatim (pokemondb, owner-supplied):** *"Dragonize causes all Normal-type attacking moves used by
the Pokémon to become Dragon-type, and increase in power by 20%."* Dragon-type Pokémon gain STAB from
those moves, *"resulting in an 80% effective increase."*

**Verbatim (Bulbapedia):** flavour — *"The Pokémon's Normal-type moves become Dragon-type moves and
their power is boosted by 20%."* Effect — all Normal-type moves used by the Pokémon become Dragon-type
and receive a 1.2× power boost. Listed as a variation of **Normalize**, alongside Aerilate, Pixilate,
Refrigerate and Galvanize.

**Where the pages are thin, plainly:** neither states the exclusion list, and neither states where in
the damage chain the 1.2× lands. Both gaps are filled from the documented behaviour of the rest of the
`-ate` family, and that inheritance is flagged as such below.

**Rule.** Before the move resolves: if `move.type == "normal"` and the move deals damage, set
`type = "dragon"` and apply `power_mult = 1.2`. The type change happens **before** STAB and before
type effectiveness, so Mega Feraligatr (Water/**Dragon**) gets Dragon STAB on it — that is the
pokemondb note's `1.2 × 1.5 = 1.8` figure.

**Hooks:** `on_modify_move` → `{type: "dragon", power_mult: 1.2}`.

**Edge cases:**

1. **Order matters and is the whole ability.** Convert first, then STAB, then type chart. Applying
   STAB from the original Normal type, or the 1.2× after the type multiplier, both give wrong numbers.
   Concretely: Body Slam at 85 power → 102 power, Dragon-type, ×1.5 STAB.
2. **1.2× is a *power* multiplier, not a damage multiplier.** It goes into the base formula
   (`power_mult`), not at the end of the chain. The two differ after the formula's integer divisions.
3. **Damaging moves only.** *"Normal-type attacking moves"* (pokemondb) is the precise phrasing; the
   `-ate` family does not convert status moves. Guard on `category != "status"`.
4. **Excluded moves — inherited from the `-ate` family, marked as inference:** moves whose type is
   determined by another mechanism are not converted — Hidden Power, Weather Ball, Natural Gift,
   Judgment, Multi-Attack, Techno Blast, Revelation Dance, Terrain Pulse, **Struggle**, and (excluded
   from this project anyway) Tera Blast. Bulbapedia's Dragonize page does not say this; the Aerilate
   and Pixilate pages do, and the family is explicitly named as identical. Of these, only **Struggle**
   and **Hidden Power** are realistically reachable here. Implement the list as a slug set in the
   ability file so it is visible and editable.
5. **Feraligatr's Normal moves are a short list** — Body Slam, Slash, Crunch is Dark, Ice Fang is Ice.
   The ability mostly upgrades Body Slam/Double-Edge into 1.8× Dragon STAB. Bulbapedia's own list
   names Endeavor and Flail as converted, which are fixed/variable-power moves where the 1.2× has
   nothing to multiply — harmless, and a good test case that the code does not divide by zero power.
6. **It makes the move Dragon-type for immunity purposes too.** A Fairy-type takes **0** from a
   Dragonized Body Slam and a Ghost-type takes normal damage where Normal did nothing. Both directions
   are the ability working correctly and both will look like bugs in a log.

---

### 3.13 `eelevate` — Mega Eelektross

**Source:** https://bulbapedia.bulbagarden.net/wiki/Eelevate_(Ability) (owner-supplied) ·
confidence: **documented-exact**

**Verbatim (Champions flavour):** *"The Pokémon floats off the ground, making it immune to Ground-type
moves, as well as the Spikes, Toxic Spikes, and Sticky Web statuses. When the Pokémon knocks out a
target with an attack, its highest stat is boosted by 1 stage."*

**Verbatim (Effect):** grants two functions. First, it renders the Pokémon **ungrounded**: immunity to
damaging Ground-type moves (**except Thousand Arrows**), and no damage or effect from Arena Trap,
Spikes, Toxic Spikes, Sticky Web, Rototiller and terrain effects; a Poison-type with the ability also
does not absorb Toxic Spikes on switch-in. These immunities are negated by **Gravity, Iron Ball,
Ingrain, Smack Down or Thousand Arrows**. Second, it **boosts the Pokémon's highest stat (excluding
HP) by one stage whenever it defeats another Pokémon using a damage-dealing move.** Mega Eelektross
only; Generation IX, Pokémon Champions.

**Rule — two independent halves.**

*Half 1, grounding.* `is_grounded(mon) == false`; damaging Ground-type moves do 0. In today's engine
that is the entire effect, because Arena Trap, hazards, terrain and Rototiller do not exist. Route it
through `on_type_immunity` so it shares a seam with `levitate` (`tier: 1`, `onTypeImmunity`, also
unimplemented) — Eelektross's *base* ability is Levitate, so the Mega is trading Levitate for
Levitate-plus-a-snowball and the two must behave identically on the Ground half.

*Half 2, the KO boost.* When the bearer KOs a target with a damaging move, raise its **highest
non-HP stat** by one stage. This is Beast Boost's rule, verbatim from
https://bulbapedia.bulbagarden.net/wiki/Beast_Boost_(Ability):

- stats considered: **Atk, Def, SpA, SpD, Spe** — **HP excluded**
- comparison uses the **raw calculated stat**, *not* stage-modified: *"does not account for stat stage
  changes, held items, or status condition reductions"* → read `mon["stats"][key]`, **never**
  `Stats.effective_stat()`
- tie-break order: **Attack → Defense → Special Attack → Special Defense → Speed**
- direct KOs from damaging moves only — not recoil, not hazards, not residual

For Mega Eelektross (145/80/135/90/80) the winner is **Attack**, every time, until Attack is capped —
so it snowballs physically despite 135 SpA. Worth knowing before someone "fixes" it.

**Hooks:** `on_type_immunity` (Ground), `on_after_hit` (with `ctx.ko == true`).

**Edge cases:**

1. **Raw stats, not effective stats.** Using `effective_stat` makes the choice drift as stages change
   and can flip the boosted stat mid-battle. This is the most common Beast Boost bug.
2. **Tie-break order is fixed, not arbitrary.** Iterate `["atk", "def", "spa", "spd", "spe"]` in that
   exact order with a strict `>` comparison.
3. **Direct KO only.** Fire it from the damage path, not from `_check_faints()` — `_check_faints` does
   not know who did the killing, and would also credit residual and recoil KOs.
4. **Fires once per KO, from inside the hit loop** — so a Parental Bond-style double hit that KOs on
   hit 1 gives exactly one boost.
5. **Thousand Arrows and Smack Down still hit it**, and Gravity / Iron Ball / Ingrain ground it. None
   exist in the engine. Read grounding through a single `Abilities.is_grounded(mon)` helper that also
   consults `vol["grounded_by"]`, so those five forward-grounders have one place to land instead of
   five.
6. **Base Eelektross has Levitate, so it is already Ground-immune** — the Mega's grounding half is
   continuity, not a gain. The KO snowball is the actual new thing, which means a naive "it's just
   Levitate" implementation silently ships half an ability.
7. Mega Eelektross is pure Electric, so its only weakness is Ground — the ability deletes its single
   weakness. That is deliberate, and it is a `za` post-game form.

---

### 3.14 `fire-mane` — Mega Pyroar

**Source:** https://bulbapedia.bulbagarden.net/wiki/Fire_Mane_(Ability) (owner-supplied) ·
confidence: **documented-exact**

**Verbatim:** flavour — *"Boosts the power of the Pokémon's Fire-type moves by 50%."* Effect (in
battle) — *"If a Fire-type move is used by a Pokémon with this Ability, its Attack or Special Attack
stat is multiplied by 1.5 during damage calculation, effectively increasing damage dealt by 50%."*
Mega Pyroar (0668) only; Generation IX, Pokémon Champions. The page contains **no** out-of-battle
effect.

**Rule.** When the bearer uses a Fire-type move, multiply the relevant **attacking stat** (Attack for
physical, Sp. Atk for special) by **1.5** during damage calculation.

**Hooks:** `on_damage_calc`, attacker side → `{atk_mult: 1.5}`.

**Edge cases:**

1. **Stat multiplier, not power multiplier, not damage multiplier.** The effect text is explicit about
   which. It matters: the base formula divides by Defence and floors, so
   `1.5 × A` then floor ≠ `1.5 × power` then floor ≠ `1.5 × damage`. Implement it as `atk_mult` — this
   is the same seam Blaze, Solar Power, Huge Power, Guts and Hustle (all `tier: 1`, all unimplemented)
   need, so getting the shape right pays for itself ten times over.
2. **The move's type after conversion is what counts.** If Mega Pyroar's type were ever changed by
   another ability, the check reads the *effective* move type, so `on_modify_move` must run before
   `on_damage_calc`. §4.3 fixes that order.
3. **It stacks multiplicatively with the sun's ×1.5** (which is a separate damage-chain step, not a
   stat step) — so Fire Mane under sun is 2.25× overall, correctly, with each step floored in turn.
4. **Applies to the bearer's own Fire moves only.** No field effect, no ally effect.
5. Mega Pyroar is Fire/**Normal** with 129 SpA: Fire STAB ×1.5 stat ×1.5 STAB is its whole identity.
   `dragonize` is the mirror-image lesson — one is a stat multiplier, the other a power multiplier, and
   swapping them produces numbers that look plausible and are wrong.
6. Bulbapedia notes **no out-of-battle effect** — so, unlike Flame Body or Flash Fire, nothing hatches
   eggs faster and nothing changes in the overworld. Do not add one.

---

## 4. The hook interface

### 4.1 Shape, and why

Five constraints drove this, in order:

1. **One file per ability**, so parallel implementers never touch the same file. Fourteen people can
   work at once.
2. **No-op by default**, so the other 300 abilities are untouched. Two layers of default: the base
   class defines every hook as a no-op, and the registry returns `null` for any slug it does not know,
   so an unknown ability costs one Dictionary lookup and nothing else.
3. **The engine calls unconditionally.** Every call site is one static call with a documented neutral
   return. No `if ability == "..."` anywhere, and no null checks scattered through `battle_engine.gd`.
4. **Fit the existing `hook` vocabulary.** `data/abilities.json` already carries camelCase hook names
   for 237 abilities (`onDamageCalc`, `onContactHit`, `onSwitchIn`, …) and `DATA_CONTRACT.md` §4
   documents the field. That vocabulary is the data-side contract; GDScript method names are its
   snake_case image. §4.2 gives the bijection.
5. **No autoload dependency.** `registry.gd` resolves everything from `const` + `preload`, the way
   `deps.gd` already avoids hard autoload references. Abilities work under
   `--script res://tests/run_tests.gd` with no `DataRegistry` alive.

Three files, plus one per ability:

```
src/battle/abilities/
  ability.gd      # base class: every hook, all no-ops. ~120 lines, never edited after review.
  registry.gd     # slug -> impl, the static dispatch facade. THE ONLY SHARED FILE.
  shadow_tag.gd   # one file per ability, extends ability.gd
  parental_bond.gd
  ...
```

**Verified on Godot 4.7.2** (probe run and removed): a `const` Dictionary of `preload()`s resolves at
compile time; `extends "res://path/ability.gd"` inheritance works without a `class_name`; `.new()` on
a `GDScript` pulled out of a const Dictionary works; a `static var` instance cache returns the same
object; `has_method()` correctly reports base-class methods on a path-extended script.

One hard rule: **an ability file must never `preload` `registry.gd`.** That is a preload cycle and it
will fail to compile. Abilities are leaves.

### 4.2 The hook catalogue

`ctx` is always a Dictionary. Every hook returns the neutral value when not overridden, so the
default is literally "do nothing".

| # | GDScript method | `hook` value in `abilities.json` | called from | `ctx` keys | returns | neutral | used by |
|---|---|---|---|---|---|---|---|
| 1 | `on_before_move(c)` | `onBeforeMove` | `_use_move`, after `Status.before_move` | `mon, move, foe, weather` | `{cancel: bool, messages: Array}` | `{}` | (seam: truant, gorilla-tactics) |
| 2 | `on_modify_move(c)` | `onModifyMoveType` | `_use_move`, before anything reads the move | `mon, move` | `{type: String, power_mult: float}` | `{}` | **dragonize** |
| 3 | `on_damage_calc(c)` | `onDamageCalc` | `Damage.compute` ctx, both sides folded | `attacker, defender, move, role, hit_index, hits, contact, weather` | `{atk_mult, power_mult, damage_mult}` | `{}` | **fire-mane, aura-guard, parental-bond** |
| 4 | `on_effectiveness(c)` | `onEffectiveness` | `Damage.type_multiplier`, **per defender type** | `mult, move_type, defender_type, defender, weather` | `float` | `c.mult` | **delta-stream** (field-scoped) |
| 5 | `on_type_immunity(c)` | `onTypeImmunity` | `Damage.type_multiplier` / `_use_move` | `mon, move_type, move` | `{immune: bool, heal_fraction: float}` | `{}` | **eelevate** (seam: levitate + 15 more) |
| 6 | `on_weather_view(c)` | `onWeatherView` | anywhere weather is read *for a mon's move* | `mon, weather` | `String` | `c.weather` | **mega-sol** |
| 7 | `on_multi_hit_count(c)` | `onMultiHitCount` | `_use_move`'s hit plan | `mon, move, hits, max_hits, single_accuracy` | `{hits: int, single_accuracy: bool}` | `{}` | **skill-link, parental-bond** |
| 8 | `on_protect_check(c)` | `onProtectCheck` | `_use_move`, when the target is protected | `mon, move, target, contact` | `{pierce: bool, damage_mult: float}` | `{}` | **unseen-fist, piercing-drill** |
| 9 | `on_hit_taken(c)` | `onHitTaken` | `_use_move`, after each connecting hit | `mon, attacker, move, dealt, contact, fainted` | `{status: String, messages: Array}` | `{}` | **spicy-spray** |
| 10 | `on_contact_taken(c)` | `onContactHit` | same, only when `contact` | same as 9 | same as 9 | `{}` | (seam: static, rough-skin, flame-body + 26 more) |
| 11 | `on_after_hit(c)` | `onAfterHit` | `_use_move`, after each hit, incl. on a KO | `mon, target, move, dealt, ko, hit_index` | `{stat_boosts: Dictionary, messages: Array}` | `{}` | **eelevate** (seam: moxie, beast-boost) |
| 12 | `on_flinch(c)` | `onFlinch` | `_use_move`, when the flinch message is printed | `mon` | `{stat_boosts: Dictionary, messages: Array}` | `{}` | **steadfast** |
| 13 | `on_switch_attempt(c)` | `onSwitchAttempt` | `submit_action`, `auto_action`, `_try_run` | `trapper, escaper, reason` (`"switch"` / `"run"`) | `{block: bool, message: String}` | `{}` | **shadow-tag** (seam: arena-trap, magnet-pull) |
| 14 | `on_field_enter(c)` / `on_field_leave(c)` | `onFieldEnter` | after switch-in, Mega Evolution, faint | `mon, weather, weather_turns` | `{weather: String, weather_turns: int, messages: Array}` | `{}` | **delta-stream** (seam: drizzle, drought, …) |
| 15 | `field_state()` | — | `registry.field_impls()` | — | `String` | `""` | **delta-stream** |
| 16 | `blocks_weather_set(c)` | `onWeatherSet` | weather-setting moves/abilities | `current, wanted` | `bool` | `false` | **delta-stream** |
| 17 | `ignores_redirection(c)` | `onRedirect` | redirection resolver (doubles) | `mon, move` | `bool` | `false` | **stalwart** |

Hooks 1, 2, 5, 10, 14 and 17 have no customer among the 14 that is strictly required, but each is
either (a) needed by one of the 14 as a shared seam (2, 5, 14) or (b) the documented home for a named
cluster of `tier: 1` abilities that will arrive next (1, 10, 17). Nothing in the table is speculative
— every row names its callers.

**New `hook` values for `abilities.json`:** `onEffectiveness`, `onWeatherView`, `onMultiHitCount`,
`onProtectCheck`, `onHitTaken`, `onAfterHit`, `onFlinch`, `onSwitchAttempt`, `onFieldEnter`,
`onWeatherSet`, `onRedirect`, `onBeforeMove`. Existing values reused unchanged: `onDamageCalc`,
`onModifyMoveType`, `onTypeImmunity`, `onContactHit`. `DATA_CONTRACT.md` §4 needs the new names added
to its list — the `hook` field is documentation-only, so this is a doc edit with no code impact.

### 4.3 Hook ordering within one move

Non-negotiable; three of the 14 break if it is wrong.

```
1. Status.before_move            (freeze/sleep/flinch/paralysis/confusion)
2. on_flinch                     <- steadfast, only if a flinch message was printed
3. on_before_move                (may cancel)
4. on_modify_move                <- dragonize: type + power_mult  (BEFORE ANYTHING READS THE MOVE)
5. on_weather_view               <- mega-sol: the weather this move sees
6. accuracy check                ONCE for the whole move, never per hit
7. on_multi_hit_count            <- skill-link, parental-bond: decide `hits` once
8. for each hit i in 0..hits-1:
     a. on_protect_check         <- unseen-fist, piercing-drill (if the target is protected)
     b. on_type_immunity         <- eelevate
     c. on_effectiveness         <- delta-stream, per defender type, inside Damage
     d. on_damage_calc           <- fire-mane (atk), aura-guard (dmg), parental-bond (dmg, i==1)
     e. apply damage
     f. on_hit_taken / on_contact_taken   <- spicy-spray
     g. on_after_hit             <- eelevate (ctx.ko)
     h. _apply_damage_side_effects        (secondaries roll per hit)
     i. break if the target fainted
9. recoil, from summed damage, once
10. on_field_enter / on_field_leave  <- delta-stream, after faints resolve
```

Step 4 before 5 and 8d is what makes Fire Mane correct on a type-converted move. Step 6 outside the
loop is what makes Parental Bond and Skill Link correct. Step 8f before 8i is what lets Spicy Spray
burn from beyond the grave.

### 4.4 `src/battle/abilities/ability.gd`

```gdscript
extends RefCounted
## Base class for every ability implementation. EVERY HOOK IS A NO-OP HERE.
##
## One file per ability under src/battle/abilities/<slug>.gd, extending this by
## path (not by class_name -- global class names live in
## .godot/global_script_class_cache.cfg, which only an editor or --import pass
## writes, so a class_name base breaks `--script res://tests/run_tests.gd` in a
## fresh checkout; tests/framework/test_case.gd documents the same trap).
##
##   extends "res://src/battle/abilities/ability.gd"
##
## NEVER preload registry.gd from here or from an ability: that is a preload
## cycle and it fails to compile. Abilities are leaves.
##
## Every hook takes one Dictionary `ctx` and returns either a Dictionary of
## overrides (empty == no change) or a scalar defaulting to the neutral value in
## ctx. Overriding nothing is always correct. See
## docs/research/ability-implementation.md section 4.2 for the ctx keys and
## section 4.3 for the order they fire in.
##
## Abilities are STATELESS. registry.gd caches one instance per slug for the life
## of the process, shared across every battle and both sides. All mutable state
## lives on the mon Dictionary or on the engine.

## Human-readable slug, for logs. Subclasses set it.
func slug() -> String:
	return ""

## Non-empty when this ability owns a persistent FIELD state (e.g. delta-stream
## returns "strong-winds"). registry.field_impls() consults every ability whose
## field_state() matches the current field, regardless of who is on the field.
func field_state() -> String:
	return ""

# -- move-time -------------------------------------------------------------

## {cancel: bool, messages: Array[String]}
func on_before_move(_c: Dictionary) -> Dictionary:
	return {}

## {type: String, power_mult: float} -- runs BEFORE anything reads the move.
func on_modify_move(_c: Dictionary) -> Dictionary:
	return {}

## {atk_mult: float, power_mult: float, damage_mult: float}
## `_c.role` is "attacker" or "defender": the same method serves both sides.
func on_damage_calc(_c: Dictionary) -> Dictionary:
	return {}

## The weather THIS mon's move should see. Return _c.weather to change nothing.
func on_weather_view(_c: Dictionary) -> String:
	return String(_c.get("weather", ""))

## Per defending TYPE component. Return _c.mult to change nothing.
func on_effectiveness(_c: Dictionary) -> float:
	return float(_c.get("mult", 1.0))

## {immune: bool, heal_fraction: float}
func on_type_immunity(_c: Dictionary) -> Dictionary:
	return {}

## {hits: int, single_accuracy: bool}
func on_multi_hit_count(_c: Dictionary) -> Dictionary:
	return {}

## {pierce: bool, damage_mult: float} -- only called when the target is protected.
func on_protect_check(_c: Dictionary) -> Dictionary:
	return {}

# -- reactions -------------------------------------------------------------

## Bearer took a damaging hit, contact or not. {status: String, messages: Array}
func on_hit_taken(_c: Dictionary) -> Dictionary:
	return {}

## Bearer took a CONTACT hit. Called after on_hit_taken, same ctx.
func on_contact_taken(_c: Dictionary) -> Dictionary:
	return {}

## Bearer's hit connected. _c.ko is true when it fainted the target.
## {stat_boosts: {stat: stages}, messages: Array}
func on_after_hit(_c: Dictionary) -> Dictionary:
	return {}

## Bearer flinched and the flinch message was printed.
func on_flinch(_c: Dictionary) -> Dictionary:
	return {}

# -- field and movement ----------------------------------------------------

## THE BEARER IS THE TRAPPER. {block: bool, message: String}
## _c.escaper is the mon trying to leave, _c.reason is "switch" or "run".
func on_switch_attempt(_c: Dictionary) -> Dictionary:
	return {}

## {weather: String, weather_turns: int, messages: Array}
func on_field_enter(_c: Dictionary) -> Dictionary:
	return {}

func on_field_leave(_c: Dictionary) -> Dictionary:
	return {}

## True to refuse a weather change while this ability's field state holds.
func blocks_weather_set(_c: Dictionary) -> bool:
	return false

## True when this ability's moves ignore redirection. No-op in single battles.
func ignores_redirection(_c: Dictionary) -> bool:
	return false
```

### 4.5 `src/battle/abilities/registry.gd`

The only shared file. Adding an ability is **one line in `IMPL`** plus one new file — the smallest
possible merge surface for 14 parallel implementers.

```gdscript
extends RefCounted
## slug -> ability implementation, and the static dispatch facade the engine calls.
##
## LOADED ONCE: `IMPL` is a const Dictionary of preload()s, so every ability
## script is resolved at compile time; `_cache` holds one instance per slug for
## the life of the process. Abilities are stateless, so sharing is safe.
##
## The engine calls the `static func`s below UNCONDITIONALLY and they return the
## neutral value when the ability is absent or does not override the hook. That
## is what keeps the other 300 abilities at zero cost and zero risk: an unknown
## slug is one Dictionary miss.
##
## ADDING AN ABILITY: one line in IMPL, one new file. Nothing else in this file
## changes, which is why fourteen people can work in parallel.

const Stats := preload("res://src/battle/stats.gd")

const IMPL: Dictionary = {
	"aura-guard":     preload("res://src/battle/abilities/aura_guard.gd"),
	"delta-stream":   preload("res://src/battle/abilities/delta_stream.gd"),
	"dragonize":      preload("res://src/battle/abilities/dragonize.gd"),
	"eelevate":       preload("res://src/battle/abilities/eelevate.gd"),
	"fire-mane":      preload("res://src/battle/abilities/fire_mane.gd"),
	"mega-sol":       preload("res://src/battle/abilities/mega_sol.gd"),
	"parental-bond":  preload("res://src/battle/abilities/parental_bond.gd"),
	"piercing-drill": preload("res://src/battle/abilities/piercing_drill.gd"),
	"shadow-tag":     preload("res://src/battle/abilities/shadow_tag.gd"),
	"skill-link":     preload("res://src/battle/abilities/skill_link.gd"),
	"spicy-spray":    preload("res://src/battle/abilities/spicy_spray.gd"),
	"stalwart":       preload("res://src/battle/abilities/stalwart.gd"),
	"steadfast":      preload("res://src/battle/abilities/steadfast.gd"),
	"unseen-fist":    preload("res://src/battle/abilities/unseen_fist.gd"),
}

static var _cache: Dictionary = {}

# -- resolution ------------------------------------------------------------

## The implementation for `slug`, or null when there is none.
static func of(slug: String) -> RefCounted:
	if slug.is_empty():
		return null
	if _cache.has(slug):
		return _cache[slug]
	if not IMPL.has(slug):
		return null
	var inst: RefCounted = (IMPL[slug] as GDScript).new()
	_cache[slug] = inst
	return inst


## The implementation of `mon`'s CURRENT ability. After Mega Evolution that is
## the Mega's ability: mega.gd writes mon["ability"] during evolve().
static func for_mon(mon: Dictionary) -> RefCounted:
	if mon.is_empty() or Stats.is_fainted(mon):
		return null
	return of(String(mon.get("ability", "")))


static func has_impl(slug: String) -> bool:
	return IMPL.has(slug)


## Every ability that owns the field state `state`. Field effects are not tied to
## whoever is attacking -- strong winds protect BOTH sides' Flying-types.
static func field_impls(state: String) -> Array:
	var out: Array = []
	if state.is_empty():
		return out
	for slug: String in IMPL:
		var impl := of(slug)
		if impl != null and impl.field_state() == state:
			out.append(impl)
	return out

# -- dispatch: the engine calls these, never IMPL directly -----------------

## Folds the attacker's and the defender's on_damage_calc into ctx multipliers
## for Damage.compute. Returns {atk_mult, power_mult, damage_mult}, all 1.0 by
## default. Roles are tagged so one method can serve both sides.
static func damage_mods(attacker: Dictionary, defender: Dictionary,
		move: Dictionary, ctx: Dictionary = {}) -> Dictionary:
	var out: Dictionary = {"atk_mult": 1.0, "power_mult": 1.0, "damage_mult": 1.0}
	for pair: Array in [[attacker, "attacker"], [defender, "defender"]]:
		var impl := for_mon(pair[0])
		if impl == null:
			continue
		var c := ctx.duplicate()
		c["attacker"] = attacker
		c["defender"] = defender
		c["move"] = move
		c["role"] = pair[1]
		var r: Dictionary = impl.on_damage_calc(c)
		for k: String in ["atk_mult", "power_mult", "damage_mult"]:
			if r.has(k):
				out[k] = float(out[k]) * float(r[k])
	return out


## The weather `mon`'s own move should see. mega-sol's whole implementation.
static func weather_view(mon: Dictionary, weather: String) -> String:
	var impl := for_mon(mon)
	if impl == null:
		return weather
	return impl.on_weather_view({"mon": mon, "weather": weather})


## One defending TYPE component's multiplier, after field effects.
static func effectiveness(mult: float, move_type: String, defender_type: String,
		defender: Dictionary, weather: String) -> float:
	var out := mult
	for impl: RefCounted in field_impls(weather):
		out = impl.on_effectiveness({
			"mult": out, "move_type": move_type, "defender_type": defender_type,
			"defender": defender, "weather": weather,
		})
	return out


## True when `escaper` may not leave. `reason` is "switch" or "run".
## Returns {block: bool, message: String}. NEVER call this for a forced
## replacement after a faint -- that would deadlock the battle.
static func escape_block(trapper: Dictionary, escaper: Dictionary,
		reason: String) -> Dictionary:
	var impl := for_mon(trapper)
	if impl == null:
		return {"block": false, "message": ""}
	var r: Dictionary = impl.on_switch_attempt({
		"trapper": trapper, "escaper": escaper, "reason": reason,
	})
	return {"block": bool(r.get("block", false)), "message": String(r.get("message", ""))}


## Is `mon` affected by Ground moves, hazards and terrain? The single seam for
## eelevate, levitate, air-balloon, and for Gravity / Smack Down / Ingrain /
## Iron Ball / Thousand Arrows when they land (vol["grounded_by"]).
static func is_grounded(mon: Dictionary) -> bool:
	var vol: Dictionary = mon.get("volatile", {})
	if bool(vol.get("grounded_by", false)):
		return true
	var impl := for_mon(mon)
	if impl != null:
		var r: Dictionary = impl.on_type_immunity({"mon": mon, "move_type": "ground", "move": {}})
		if bool(r.get("immune", false)):
			return false
	return not PackedStringArray(mon.get("types", PackedStringArray())).has("flying")
```

`hit_count()`, `protect_check()`, `hit_taken()`, `after_hit()`, `flinch()`, `modify_move()` and
`field_refresh()` follow the same three-line shape: resolve the impl, call the hook, coalesce to the
neutral value. They are mechanical; the four above are the ones with real logic and are given in full
because they are the ones worth reviewing.

### 4.6 Worked example: `src/battle/abilities/shadow_tag.gd`

The priority ability, complete, as the pattern for the other thirteen.

```gdscript
extends "res://src/battle/abilities/ability.gd"
## Shadow Tag -- Mega Gengar (and Wobbuffet).
##
## "Prevents opponents from fleeing or switching out."
##
## GENERATION VI+ RULE, and the one that matters here: GHOST-TYPES ARE IMMUNE.
## Fantina is gym 3 and her whole team is Ghost, so a Gen 4/5 implementation
## would trap the player's Ghost-type answers to a Mega Gengar that is itself
## Ghost/Poison. See docs/research/ability-implementation.md section 3.1.
##
## The engine must NEVER ask this for a forced replacement after a faint --
## battle_engine._check_faints() sets awaiting_switch, and blocking there
## deadlocks the battle with no legal action.

const SHED_SHELL := "shed-shell"

func slug() -> String:
	return "shadow-tag"


func on_switch_attempt(c: Dictionary) -> Dictionary:
	var escaper: Dictionary = c.get("escaper", {})
	if escaper.is_empty():
		return {}
	var reason := String(c.get("reason", "switch"))

	# Gen 6+: Ghost-types walk free, from both switching and fleeing.
	if PackedStringArray(escaper.get("types", PackedStringArray())).has("ghost"):
		return {}

	# Shadow Tag does not trap Shadow Tag.
	if String(escaper.get("ability", "")) == slug():
		return {}

	# Shed Shell allows SWITCHING but not fleeing.
	if reason == "switch" and String(escaper.get("item", "")) == SHED_SHELL:
		return {}

	return {
		"block": true,
		"message": "%s can't escape!" % Stats.display_name(escaper),
	}
```

(`Stats` is preloaded in `ability.gd` for `display_name`; abilities never preload `registry.gd`.)

---

## 5. Engine changes required

Small, additive, and each one is a seam a named cluster of `tier: 1` abilities also needs. Nothing
here changes existing behaviour when no ability overrides a hook — which is the property the 2974
passing checks have to keep.

### 5.1 `src/battle/damage.gd` — three ctx multipliers and a per-component type loop

**Three new optional ctx keys**, all defaulting to 1.0, documented in `compute()`'s docstring beside
the existing `roll` / `crit` / `weather` / `type_mult`:

| key | applied | line today | why there |
|---|---|---|---|
| `power_mult` | `power = maxi(1, floori(power * power_mult))` before the base formula | before :111 | dragonize (and technician, iron-fist, sheer-force, all `tier: 1`) |
| `atk_mult` | `a = maxi(1, floori(a * atk_mult))` after `Stats.effective_stat` | after :100 | fire-mane (and huge-power, guts, blaze, solar-power, hustle) |
| `damage_mult` | `dmg = floori(dmg * damage_mult)` after burn, **before** `maxi(1, dmg)` | :149 | aura-guard, parental-bond hit 2, piercing-drill (and multiscale, filter, tinted-lens) |

`roll_range()` and `average()` duplicate ctx, so the AI prices the multipliers correctly for free.

**`type_multiplier()` gains an optional third argument and loops per component:**

```gdscript
static func type_multiplier(move_type: String, defender_types: Variant,
		ctx: Dictionary = {}) -> float:
	var types := PackedStringArray(defender_types)
	var reg := Deps.registry()
	if reg == null:
		return 1.0
	var weather := String(ctx.get("weather", ""))
	var defender: Dictionary = ctx.get("defender", {})
	var mult := 1.0
	for t: String in types:
		var component := float(reg.get_type_effectiveness(move_type, t))
		mult *= Abilities.effectiveness(component, move_type, t, defender, weather)
	return mult
```

Both `DataRegistry` (`data_registry.gd:236`) and `Deps.JsonRegistry` expose
`get_type_effectiveness(atk, def)`, so the per-component loop works with the real autoload and with
the fallback. The default-`ctx` signature keeps the three existing 2-arg call sites (`ai.gd:90`,
`ai.gd:168`, `battle_engine.gd:521`) compiling and behaving identically — with no field state active,
`Abilities.effectiveness()` returns its input.

### 5.2 `src/battle/battle_engine.gd` — twelve call sites

| # | where | change |
|---|---|---|
| 1 | `_use_move`, after `Status.before_move` | if `before.flinched`, call `Abilities.flinch(attacker)` and apply its stat boosts |
| 2 | `_use_move`, before the PP decrement | `move = Abilities.modify_move(attacker, move)` — a duplicate with `type`/`power_mult`; never mutate the mon's stored move |
| 3 | `_use_move`, building `ctx` | `ctx["weather"] = Abilities.weather_view(attacker, weather)` |
| 4 | `_use_move`, building `ctx` | `ctx["defender"] = defender` so `type_multiplier` can reach it, then merge `Abilities.damage_mods(...)` |
| 5 | `_use_move`, after the accuracy check | build the hit plan: `Abilities.hit_count(attacker, move)`; loop |
| 6 | inside the loop, before `Damage.compute` | if the target is protected, `Abilities.protect_check(...)`; on `pierce` fold `damage_mult`, else print "protected itself!" and break |
| 7 | inside the loop, after `apply_hp_delta` | `Abilities.hit_taken(defender, attacker, move, dealt, contact)` — **before** the faint break, so Spicy Spray fires from beyond the grave |
| 8 | inside the loop, after 7 | `Abilities.after_hit(attacker, defender, move, dealt, ko)` and apply its stat boosts |
| 9 | `_apply_damage_side_effects` | called per hit; move the recoil block out of it so recoil is applied once from summed damage |
| 10 | `submit_action`, `"switch"` branch | `if Abilities.escape_block(active(1 - side), active(side), "switch").block: return false` |
| 11 | `auto_action` | `"can_switch"`: `… and not Abilities.escape_block(active(1 - side), me, "switch").block` |
| 12 | `_try_run` | check `escape_block(..., "run")` first and `_say()` its message instead of rolling odds |
| 13 | `_switch_in`, `mega_evolve`, `_check_faints` | `Abilities.field_refresh(self)` — set/clear field states like strong winds |
| 14 | `_end_of_turn` | clear `vol["protect"]` on both actives |

Item 2 matters: `resolve_turn()` puts the mon's live move Dictionary into the action
(`a["move"] = moves[idx]`) and `_use_move` writes `move["pp"]` straight into it. A Dragonized move
must be a **duplicate**, or Mega Feraligatr's Body Slam becomes permanently Dragon-type in the save.

### 5.3 `src/battle/status.gd` — one key

`before_move()` returns `{can_move, messages, self_damage}`. Add `"flinched": bool`, true only on the
branch that prints `"%s flinched and couldn't move!"`. Nothing else changes, and `status.gd` stays
below the ability layer — it does not know abilities exist. Existing tests read `can_move` only, so
this is additive.

### 5.4 `src/battle/stats.gd` — Blocker A

Two keys in `make_move()`: `effectId` and `flags`. §1.1.

### 5.5 `src/battle/ai.gd` — one line

`score_moves()` takes `weather` as a plain String. Pass `Abilities.weather_view(me, weather)` so the
AI prices Mega Meganium's Fire moves the way the engine will resolve them. Without it, an AI
Mega Meganium under-rates its own best move by 33%.

---

## 6. Prerequisites, and how each ability degrades without them

Nothing in the list blocks starting. State each honestly rather than letting an implementer discover
it halfway.

### 6.1 Protect does not exist — 2 abilities dormant

`unseen-fist` and `piercing-drill` need a protected target. `data/moves.json` has `protect`, `detect`,
`kings-shield`, `spiky-shield`, `baneful-bunker`, `obstruct`, `silk-trap`, `burning-bulwark` and a
`protect` flag on 593 moves, but `_apply_status_move` has no case for `effectId: 112` — Protect
currently falls through to `_apply_stat_change_effect`, fails, and prints *"But nothing happened!"*

Minimum viable Protect, ~20 lines and worth doing in the same pass:

1. `_apply_status_move`: on `effectId 112` set `vol["protect"] = true`, say *"X protected itself!"*
2. `_use_move`: before damage, if the target has `vol.protect` **and** the move has the `protect`
   flag, the move fails — unless `Abilities.protect_check()` returns `pierce`
3. `_end_of_turn`: clear `vol["protect"]`; `Status.clear_volatiles` already resets volatiles on switch
4. consecutive-use failure odds (1/3 each repeat) are a later refinement, not a blocker

Both abilities ship **spec-complete and dormant**: correct code, no live path. Their unit tests set
`vol["protect"] = true` by hand, so they are fully testable now and light up the day Protect lands.

### 6.2 Multi-hit does not exist — 2 abilities need the host loop

`skill-link` and `parental-bond` are hit-count *modifiers*; there is no hit count to modify. The loop
in §4.3 step 8 is engine work (`battle_engine.gd`), not ability work, and **it should be written
first, by one person, before the two ability files.** Both abilities are trivial once it exists —
Skill Link is about 12 lines.

### 6.3 Dormant by design, and that is the right answer

- **`stalwart`** — single battles only. Zero observable effect, forever, unless doubles land. §3.6.
- **`mega-sol`** — the Fire ×1.5 / Water ×0.5 half works immediately; the Solar Beam, Growth, Weather
  Ball, healing and accuracy halves need charge turns and weather-aware moves. §3.11.
- **`eelevate`** — the KO snowball works immediately; hazards, Arena Trap, terrain and the five
  forward-grounders do not exist. §3.13.
- **`unseen-fist`, `piercing-drill`** — §6.1.

### 6.4 Concurrency

The level-curve rebalance workflow is writing to `data/` and `tools/`. It owns
`data/level_caps.json`, `data/rom/` and `tools/scale_*.py` — **do not touch those.** The edits in §8
are to `data/abilities.json` only, which that workflow does not write. All engine work is under
`src/battle/`, which it does not touch at all.

---

## 7. Tests

`tests/run_tests.gd` discovers `res://tests` and `res://tests/cases`, so **`tests/cases/` is where
per-ability tests go** — one file per ability, matching the one-file-per-ability rule, so parallel
implementers do not collide in a test file either.

```
tests/cases/test_ability_shadow_tag.gd      extends "res://tests/framework/test_case.gd"
tests/cases/test_ability_parental_bond.gd
...
tests/cases/test_ability_registry.gd        the shared one: see below
```

Run: `"$GODOT" --headless --path "$PROJ" --script res://tests/run_tests.gd -- --filter=ability`

`test_case.gd` gives `check/eq/neq/almost/is_true/is_false`; `Deps.set_override()` injects a fake
`DataRegistry`; `tests/fixtures/*.json` already mirror the real data files. Pin `roll` and `crit` in
every damage assertion — `Damage.compute` is pure when you do, which is how `test_battle.gd` pins
exact numbers today.

**The shared registry test, which is the one that protects the other 300 abilities:**

1. every slug in `IMPL` exists in `data/abilities.json`
2. every slug in `IMPL` has `tier: 1` (catches a merged implementation with a stale data row)
3. every ability slug referenced by `data/megas.json` is either `tier: 1` or in `IMPL`
4. `Abilities.of("stench")` is `null`, and each dispatch function returns its neutral value for it —
   **the no-op guarantee, asserted rather than assumed**
5. `Abilities.for_mon({})` and `for_mon(fainted)` are `null`
6. `ability.gd` itself returns the neutral value from every hook (instantiate the base directly)
7. `mega-design.md` ruling **B9**: no trainer party in `data/rom/trainers.json` carries a `megaForm`
   whose ability is `tier: 3` (`mega-design.md:947` already asks for this test)

**Per-ability cases that would catch a wrong implementation.** The ones worth writing first:

| ability | the assertion that matters |
|---|---|
| `shadow-tag` | a Ghost-type escaper is **not** blocked; a non-Ghost is; `shed-shell` switches but cannot run; a forced replacement is never consulted; `ai.can_switch` goes false |
| `parental-bond` | exactly 2 hits; hit 2 damage ≈ 0.25 × hit 1 at a pinned roll; one accuracy check; no extra hit on Bullet Seed; recoil charged once from the sum |
| `skill-link` | Pin Missile (`effectId` 30) = 5 hits; Gear Grind (45) = 2; Triple Kick (105) = 3 with per-hit accuracy off; Cloyster as a non-Mega holder |
| `delta-stream` | Ice vs Dragon/Flying = 2.0 (not 4.0); **Rock = 1.0; Electric = 0.5**; Dragon still 2.0; Ground still 0.0; clears when the holder faints |
| `steadfast` | Speed stage +1 exactly when the flinch message is printed; turn still lost |
| `aura-guard` | a contact move does half; a non-contact move does full; not applied to burn damage |
| `unseen-fist` / `piercing-drill` | with `vol.protect` set by hand: contact pierces, non-contact does not; full damage vs 0.25× respectively |
| `spicy-spray` | a **non-contact** special move burns the attacker; a Fire-type attacker does not get burned; the burn lands when the bearer faints to that hit |
| `mega-sol` | the bearer's Fire move ×1.5 with `weather == ""`; the **opponent's** Fire move unchanged |
| `dragonize` | Body Slam becomes Dragon at 1.2× power, then takes Dragon STAB; a Fairy target takes 0; the mon's stored move is **not** mutated |
| `eelevate` | Ground move does 0; on a KO, **Attack** rises (145 atk beats 135 spa); raw stats, not stage-modified; residual KOs do not trigger it |
| `fire-mane` | ×1.5 on the attacking **stat**, verified against a hand-computed number, not against `damage × 1.5` |
| `stalwart` | `ignores_redirection()` is true and nothing else changes — a deliberately boring test that documents the no-op |

---

## 8. Data edits required

All in `data/abilities.json`. Not written by the concurrent level-curve workflow (§6.4).

1. **`tier: 3 → 1`** for all 14 slugs, as each implementation merges — not in one batch, or the
   registry test in §7 fails for whichever are not yet written.
2. **`hook: "none" → <value>`** per §4.2: `shadow-tag` → `onSwitchAttempt`, `parental-bond` →
   `onMultiHitCount`, `steadfast` → `onFlinch`, `skill-link` → `onMultiHitCount`, `delta-stream` →
   `onFieldEnter`, `stalwart` → `onRedirect`, `unseen-fist` → `onProtectCheck`, `aura-guard` →
   `onDamageCalc`, `piercing-drill` → `onProtectCheck`, `spicy-spray` → `onHitTaken`, `mega-sol` →
   `onWeatherView`, `dragonize` → `onModifyMoveType`, `eelevate` → `onTypeImmunity`, `fire-mane` →
   `onDamageCalc`.
3. **Fix `piercing-drill`'s truncated `text`.** It currently stops before the damage clause. The
   complete flavour text is: *"When the Pokémon uses contact moves, it can hit even targets that are
   protecting themselves, dealing 1/4 of the damage that the move would otherwise deal. Everything
   aside from the target's protective effects is still triggered."* A UI that shows the current text
   tells the player Mega Excadrill ignores Protect for free.
4. **`DATA_CONTRACT.md` §4**: add the twelve new `hook` values to the documented vocabulary.
5. **`docs/research/mega-design.md`**: once `skill-link` and `aura-guard` land, ruling **B9** no
   longer blocks them — revert Aaron's **Mega Scizor → Mega Heracross** (line 667, which already asks
   for exactly this) and unblock **Mega Lucario Z** as a boss Mega (line 660).
6. **`docs/research/rosters-gyms14.md` line 83**: resolution (a) is taken — Fantina's Mega Gengar
   keeps Shadow Tag. Strike the Cursed Body fallback.
7. *(optional, not a blocker)* `tools/build_species.py`: give `population-bomb`, `triple-dive` and
   `tachyon-cutter` multi-hit metadata (§1.1).

---

## 9. Build order

The dependency graph, so fourteen people are not all blocked on one another.

**Wave 0 — one person, shared files, must land first.** `ability.gd`, `registry.gd` (with an empty
`IMPL`), the `Damage.compute` ctx multipliers and per-component `type_multiplier` (§5.1),
`Stats.make_move`'s two keys (§5.4), `Status.before_move`'s `flinched` key (§5.3), the
`test_ability_registry.gd` skeleton. Nothing observable changes; `2974 checks` must still pass.

**Wave 1 — the four that need nothing else. Fully parallel.**
`shadow-tag` (call sites 10/11/12), `steadfast` (1), `fire-mane` (4), `stalwart` (nothing).
**Ship `shadow-tag` first: it is the one the gym-3 fight is waiting on.**

**Wave 2 — one shared prerequisite each, then parallel.**
`aura-guard` and `spicy-spray` need Blocker A merged (Wave 0) and call site 7.
`dragonize` needs call site 2, `mega-sol` needs 3 and §5.5, `eelevate` needs 8.

**Wave 3 — needs the multi-hit host loop (§6.2), written by one person first.**
`skill-link`, then `parental-bond`.

**Wave 4 — needs minimum-viable Protect (§6.1).**
`unseen-fist`, `piercing-drill`. Write them in Wave 1 against a hand-set `vol.protect` if it suits;
they are dormant either way.

**Wave 5 — the field-state one, alone because it touches `type_multiplier` and the weather slot.**
`delta-stream`, with call site 13.

---

## 10. Verified facts

Everything below was run, not recalled.

- `docs/DATA_CONTRACT.md` §4 `tier`: 1 = engine-implemented, 2 = declared but inert, 3 = data only.
- `data/abilities.json` holds **314** abilities. `hook` distribution: `none` 77, `onDamageCalc` 45,
  `onStatusApply` 29, `onContactHit` 29, `onFieldMisc` 27, `onSwitchIn` 23, `onTurnEnd` 16,
  `onTypeImmunity` 16, `onHpCross` 15, `onAccuracyCheck` 13, `onTurnOrder` 13, `onModifyMoveType` 11.
- `data/megas.json` holds **97** forms using **66** distinct abilities: **52 at tier 1, 14 at tier 3,
  0 at tier 2.** The 14 are exactly the list in this document.
- `data/moves.json` holds **919** moves. `flags` vocabulary: contact 245, mirror 590, protect 593,
  punch 21, charge 16, dance 10, snatch 79, distance 30, authentic 75, reflectable 88, gravity 10,
  non-sky-battle 40, bite 10, sound 30, mental 6, recharge 10, heal 32, powder 8, ballistics 25,
  defrost 10, pulse 7.
- `Stats.make_move()` drops `flags` and `effectId`. 57 Gen 9 moves have `"effect": null`.
- Nothing under `src/battle/` mentions protect, substitute, trap, multihit, hazard, spikes, terrain,
  grounded, levitate or contact.
- `Damage.type_multiplier` has exactly three call sites, all 2-arg: `ai.gd:90`, `ai.gd:168`,
  `battle_engine.gd:521`.
- `DataRegistry.get_type_effectiveness(atk, def)` (`data_registry.gd:236`) and
  `Deps.JsonRegistry.get_type_effectiveness` both exist — the per-component loop works with the real
  autoload and with the fallback.
- Species cross-check in `data/species.json`: Urshifu 892 `unseen-fist`; Wobbuffet 202 `shadow-tag`;
  Cloyster 91 `skill-link`; Lucario 448 and Gallade 475 `steadfast`; Dugtrio 51 and Trapinch 328
  `arena-trap`. `long-reach`, `fluffy`, `propeller-tail`, `arena-trap`, `magnet-pull` are all tier 3.
- Godot 4.7.2 probe (created under `tools/_probe/`, run, removed): a `const` Dictionary of
  `preload()`s works; `extends "res://path.gd"` works without `class_name`; `(IMPL[slug] as
  GDScript).new()` works; a `static var` cache returns the identical instance; `has_method()` sees
  base-class methods through a path extend.
- Test baseline before any of this work:
  `"$GODOT" --headless --path "$PROJ" --script res://tests/run_tests.gd` → `OK 2974 checks passed in
  11 file(s)`, exit 0. `$GODOT` is
  `C:/Users/James/Documents/GitHub/Godot_v4.7.2-stable_win64_console.exe` (the `_console` build — the
  plain one detaches from the console and prints nothing).

### Sources

| ability | source |
|---|---|
| mega-sol | https://pokemondb.net/ability/mega-sol · https://bulbapedia.bulbagarden.net/wiki/Mega_Sol_(Ability) |
| dragonize | https://pokemondb.net/ability/dragonize · https://bulbapedia.bulbagarden.net/wiki/Dragonize_(Ability) |
| eelevate | https://bulbapedia.bulbagarden.net/wiki/Eelevate_(Ability) · https://bulbapedia.bulbagarden.net/wiki/Beast_Boost_(Ability) (tie-break rule) |
| fire-mane | https://bulbapedia.bulbagarden.net/wiki/Fire_Mane_(Ability) |
| shadow-tag | https://bulbapedia.bulbagarden.net/wiki/Shadow_Tag_(Ability) |
| parental-bond | https://bulbapedia.bulbagarden.net/wiki/Parental_Bond_(Ability) |
| steadfast | https://bulbapedia.bulbagarden.net/wiki/Steadfast_(Ability) |
| skill-link | https://bulbapedia.bulbagarden.net/wiki/Skill_Link_(Ability) |
| delta-stream | https://bulbapedia.bulbagarden.net/wiki/Delta_Stream_(Ability) · https://bulbapedia.bulbagarden.net/wiki/Strong_winds |
| stalwart | https://bulbapedia.bulbagarden.net/wiki/Stalwart_(Ability) |
| unseen-fist | https://bulbapedia.bulbagarden.net/wiki/Unseen_Fist_(Ability) |
| aura-guard | https://bulbapedia.bulbagarden.net/wiki/Aura_Guard_(Ability) |
| piercing-drill | https://bulbapedia.bulbagarden.net/wiki/Piercing_Drill_(Ability) · https://www.pokemon-zone.com/champions/abilities/piercing-drill/ |
| spicy-spray | https://bulbapedia.bulbagarden.net/wiki/Spicy_Spray_(Ability) |

---

## 11. Final status — verified by the reconciler

**Date:** 2026-09-23. **Engine:** Godot `4.7.2.stable.official.ed1daf0bf`.
**Suite:** `tools/run_tests.sh` → `OK 3859 checks passed in 17 file(s), 1 pending`, exit 0.
(Baseline before the four ability groups landed: 2974 checks in 11 files. Baseline as the four
groups left it: 3567 in 16 files. The reconciler's own file adds 292.)

Verification file: **`tests/test_ability_reconciled.gd`** (292 checks). It does not trust any
group's own tests. Every ability is re-proved against one standard:

> a bearer and an otherwise identical control — same fixture, `ability` set to `""`, same seed —
> go through the same engine call, and the **outcome** must differ.

A number that comes out equal in both rows proves the ability inert no matter how much machinery
sits behind it. Nothing in that file asserts "the hook was called"; the measured quantities are HP
actually lost, a switch actually refused, a status actually inflicted, a stat stage actually moved,
and lines actually written to `battle_log`.

### 11.1 Per-ability verdict

| # | ability | Mega | tier | works | the outcome that was measured |
|---|---|---|---|---|---|
| 1 | `shadow-tag` | Mega Gengar | **1** | **yes** | `submit_action(switch)` returns **false** where the control returns true; run refused in a wild battle; Ghost-type still leaves |
| 2 | `parental-bond` | Mega Kangaskhan | **1** | **yes** | "Hit 2 time(s)!" and 1.25x a single hit; hit 2 carries `damageMult` 0.25, hit 1 carries 1.0; recoil charged once |
| 3 | `skill-link` | Mega Heracross | **1** | **yes** | 5 hits on every one of 12 seeds where the control varies 2-5; Triple Kick's per-hit accuracy removed; Gear Grind still 2 |
| 4 | `unseen-fist` | Mega Golurk | **1** | **yes** | contact move lands **full** damage through a **real Protect turn**; control deals 0 and is logged as blocked |
| 5 | `piercing-drill` | Mega Excadrill | **1** | **yes** | same, at **0.25x** through a real Protect turn; control deals 0; the two constants are asserted distinct |
| 6 | `aura-guard` | Mega Lucario Z | **1** | **yes** | contact damage taken x0.5, non-contact damage **unchanged**, its own attacks unchanged |
| 7 | `spicy-spray` | Mega Scovillain | **1** | **yes** | attacker ends the turn `burn`, control does not; fires on non-contact moves; fires from beyond the grave; a Fire-type attacker is still refused |
| 8 | `delta-stream` | Mega Rayquaza | **1** | **yes** | `engine.weather == "strong-winds"`; Rock damage halved on a Flying-type; per-component table (Electric 1 to 0.5, Ice 4 to 2, Ground stays 0) |
| 9 | `steadfast` | Mega Mewtwo X | **1** | **yes** | Speed stage **+1** after a flinch, control stays 0; reachable from a real Fake Out; silent at +6 |
| 10 | `stalwart` | Mega Skarmory | **2** | **no — by design** | see 11.2 |
| 11 | `mega-sol` | Mega Meganium | **1** | **yes** | own Fire move x1.5 and own Water move x0.5; real field weather untouched; sandstorm Rock Sp.Def boost skipped |
| 12 | `dragonize` | Mega Feraligatr | **1** | **yes** | a Fairy takes **0** from Body Slam and a Ghost takes damage where Normal did nothing; ~1.8x on a neutral target; the stored move is not mutated and PP still decrements |
| 13 | `eelevate` | Mega Eelektross | **1** | **yes** | Earthquake does **0**; a KO raises **Attack** (the highest raw stat), not the Sp. Atk it attacked with; no boost without a KO; `volatile.grounded_by` overrides it |
| 14 | `fire-mane` | Mega Pyroar | **1** | **yes** | Fire move up, non-Fire move unchanged, and the number is **identical** to an ability-less mon whose Sp. Atk is already 1.5x — which is what proves it is a *stat* multiplier and not a damage one |

**13 of 14 change a battle outcome.** All 14 are reachable from a real form in `data/megas.json`
(asserted in `test_no_mega_form_references_an_excluded_gimmick`).

### 11.2 `stalwart`: tier 1 to **tier 2**, the one honest negative

Stalwart bypasses target **redirection**. Redirection exists only in double battles;
`battle_engine.gd` is single-battles-only. There is nothing for the hook to change, and Bulbapedia
says so verbatim. It is registered, hooked, and tested — and observably inert.

`DATA_CONTRACT.md` section 4 defines **tier 2 = "declared but inert"**, which is exactly this. It was
shipped at tier 1, which overclaims; tier 3 ("data only") would be wrong in the other direction,
because it *does* have an implementation. It is now **tier 2**.

`test_stalwart_changes_no_battle_outcome_and_that_is_correct` pins the negative result: damage dealt
and damage taken must both be **identical** to the control, and the target's ability must still
apply. If someone later gives Stalwart an invented single-battle effect — the common fan error is
Mold Breaker's "ignore the target's ability", which would silently buff Mega Skarmory's 140 Attack —
those assertions fail and force a review.

### 11.3 What reconciliation actually had to fix

**1. A real cross-group bug: `mega-sol` deleted other Pokemon's `delta-stream`.**
`ctx.weather` carried two different meanings at once — the **field state** and a **per-mon weather
view**. `battle_engine._use_move` set it to `Abilities.weather_view(attacker, weather)`, and
`Damage.compute` passed that same value down into `type_multiplier`, where
`Abilities.effectiveness()` resolves field effects through `field_impls(weather)`. A Mega Meganium
attacking therefore looked up `field_impls("sun")`, found nothing, and another Pokemon's strong winds
simply vanished:

```
--- FIELD = strong-winds (Mega Rayquaza's Delta Stream is up) ---
no ability     weather_view=strong-winds   Rock vs pure Flying eff=1.00  dmg=35
mega-sol       weather_view=sun            Rock vs pure Flying eff=2.00  dmg=70   <-- BUG
```

Neither group could see it: each had only its own abilities on the field. Fixed by splitting the
two meanings — `ctx.weather` stays the attacker's **view**, and a new `ctx.field_weather` carries the
**real field state**, which is what the type chart and the field hooks read. `field_weather` falls
back to `weather`, so every pre-existing call site (the AI's 0x pre-checks, every existing test) is
unchanged. Three files, four lines: `damage.gd`, `battle_engine.gd`, `ai.gd` (two call sites).
Guarded permanently by `test_regression_mega_sol_cannot_delete_delta_stream`.

**2. Protect was implemented, because without it two abilities are unreachable.**
`unseen-fist` and `piercing-drill` were both spec-complete and both **dormant**: the engine had the
protection gate, the `volatile["protect"]` key and the end-of-turn clear, but no move set the key, so
the only way to reach either ability was to set the volatile by hand in a test. That is not a working
ability, it is dead code with a test around it.

Protect/Detect are now live in `battle_engine._apply_protect()` — one branch in `_apply_status_move`
on `effectId 112`, which both moves already carry in `data/moves.json`, along with their +4 priority.
Consecutive uses succeed at 1, 1/3, 1/9, 1/27 (Gen 6+), a failure resets the chain, and using any
other move resets it too; without that, +4-priority protection is an unbreakable stall. The
punishing protections (Spiky Shield 362, Baneful Bunker 384, Obstruct 472, King's Shield, Silk Trap,
Burning Bulwark) are deliberately **not** in `PROTECT_EFFECT_IDS`: each owes the attacker a recoil, a
poison or a stat drop, and shipping them as plain Protect would silently drop that half of the move.
Max Guard is a Dynamax move, excluded by `DATA_CONTRACT` section 11.4.

Both abilities are now proved against a defender that actually uses Protect
(`test_unseen_fist_pierces_through_a_real_protect_turn`,
`test_piercing_drill_pierces_a_real_protect_for_a_quarter`).

**3. Data corrections in `data/abilities.json`** (edited by index splice on the minified file; still
2 lines, still **0 non-ASCII bytes**, 314 rows parse):

- `stalwart` tier `1` to `2` (11.2).
- `fire-mane`'s **text** said "Boosts the *power* of the Pokemon's Fire-type moves by 50%". It is an
  Attack / Sp. Atk multiplier, and after the base formula's integer divisions the two give different
  numbers, so a UI showing that string taught the player the wrong mechanic. Now: "When the Pokemon
  uses a Fire-type move, its Attack or Sp. Atk is multiplied by 1.5." (Flagged by the implementing
  group, which correctly declined to edit data it did not own.)

**4. Hook order in the merged `_use_move` was verified by reading the final file, not the reports.**
`modify_move` fires once, before the hit loop, immediately *after* the PP decrement (PP is written
into the move dict, so duplicating first would stop PP from ever decrementing). The protect gate
fires once, outside the loop. `weather_view`, `hit_taken` and `after_hit` fire *inside* it, per hit.
Recoil is charged once from the summed damage; drain and secondaries are per hit. All confirmed by
outcome tests, not by inspection alone.

### 11.4 Cross-group interactions now under test

| interaction | assertion |
|---|---|
| `mega-sol` x `delta-stream` | a Mega Sol attacker cannot see through another Pokemon's strong winds; the field survives a whole turn with a Mega Sol holder on it |
| `skill-link` x `spicy-spray` | a 5-hit Arm Thrust burns its user, proving `hit_taken` moved *inside* the multi-hit loop; the burn message appears exactly once |
| `parental-bond` x `eelevate` | a pair that KOs on hit 1 stops there and pays exactly **one** boost |
| `parental-bond` x `skill-link` | Bullet Seed stays 2-5 under Parental Bond, `plan.by` is `""`, and hit 2 is **not** quartered |
| `fire-mane` x `aura-guard` | opposite sides of one damage calc compose: `atkMult` 1.5 and `damageMult` 0.5 in the same result |
| nothing implemented | an unimplemented slug (`torrent`, `immunity`, `levitate`) leaves damage bit-identical and all three multipliers at exactly 1.0 |
| a fainted bearer | `for_mon()` returns null, so a dead Shadow Tag traps nothing |

### 11.5 The priority case: Fantina, gym 3 — **verified end to end**

Built from her shipped row in `data/rom/bosses.json` (read-only): Drifblim 34, Cofagrigus 34,
Houndstone 34, Mimikyu 34, **Gengar 35 holding `gengarite`** (`megaSlot: 4`,
`megaForm: "gengar-mega"`, `megaAbilities: ["shadow-tag"]`), Mismagius 36 — cap 36, AI 7,
`keyStone: true`. Four tests, 30 checks:

- **`test_fantina_gengar_really_mega_evolves_into_shadow_tag`** — her Gengar leads with
  `cursed-body`; the engine's own `can_mega_evolve()` gate says yes; `mega_evolve(1)` succeeds; the
  active mon's ability becomes `shadow-tag` and resolves to a real implementation. Mega Evolution is
  how the ability is *acquired*, so this is the path that matters.
- **`test_fantina_mega_gengar_traps_the_player_and_a_ghost_escapes`** — **the fight.** Before the
  Mega, the player switches freely (so the test cannot pass vacuously). After it, a Normal-type's
  switch is **refused**, `"<Name> can't escape!"` reaches the log, and a move is still legal so the
  player is not deadlocked. A **Ghost-type switches out fine** — the Gen 6+ exemption, deliberately
  taken so the player's Ghost answers to a Ghost/Poison Mega Gengar are not the thing that gets
  punished.
- **`test_fantina_trap_ends_when_her_mega_gengar_faints`** — with Gengar on 1 HP, one turn kills it;
  the battle does not end (she has five more), her replacement does not have Shadow Tag, the player
  can switch again, and the fainted holder resolves to `null`.
- **`test_fantina_reverts_her_mega_when_the_battle_ends`** — her Gengar is back to `cursed-body` with
  no `megaForm` once the battle is over, so Shadow Tag cannot follow it into the save.

### 11.6 Still not done, and honest about it

- **`population-bomb` has `"effectId": null` in `data/moves.json`**, so it hits once and Skill Link
  cannot see it (should be 10). A generated-data row to fix in `tools/build_gamedata.py`, not a rule
  to special-case. Recorded as the suite's one **pending** check, which flips to asserting 10 hits
  the moment the row is fixed. Skill Link itself is proved through Pin Missile, Arm Thrust and
  Triple Kick, so the ability is not blocked on it.
- **Sturdy and Focus Sash do not exist**, so Skill Link's real payoff — five hits breaking both — is
  a hit count today and not yet a tactical difference.
- **Charge turns do not exist**, so `mega-sol`'s biggest effect (one-turn Solar Beam) and Parental
  Bond's charging-move exclusion are both dormant-but-correct. Growth at two stages, Weather Ball as
  Fire/100, the 2/3 healing moves, and the Thunder/Hurricane accuracy drop likewise wait on features
  that read weather through `Abilities.weather_view()`.
- **`blocks_weather_set` has no caller**: no weather-setting move or ability exists, so Delta
  Stream's "Sunny Day fails" half is tested directly but is not reachable in play.
- **Substitute, Long Reach, Protective Pads** — all absent; `spicy-spray` and `aura-guard` read them
  forward-compatibly.
- **`arena-trap`, `magnet-pull`, `propeller-tail`, `levitate`** are one-line drop-ins on hooks that
  now exist (`on_switch_attempt` with a different predicate; `stalwart.gd` with a different slug;
  `on_type_immunity` exactly as `eelevate` does it). All still tier 3, all out of scope here.
- **Pre-existing, not introduced here, and reported rather than fixed:** `data/moves.json` ships 5
  excluded-gimmick move rows — `max-guard` (743), `dynamax-cannon` (744), `behemoth-blade` (781),
  `behemoth-bash` (782), `tera-blast` (851). `DATA_CONTRACT` section 11.4 says such rows are dropped at
  import, so the fix belongs in `tools/build_gamedata.py`'s filter, not in a hand edit to generated
  data that the next build would overwrite. `data/megas.json`, `data/species.json`, `data/items.json`
  and `src/` are all clean: the only gimmick names in engine code are inside `mega.gd`'s `EXCLUDED`
  rejection list and `dragonize.gd`'s `EXCLUDED` non-conversion list, both of which exist to *refuse*
  the mechanic. `test_no_excluded_gimmick_leaked_into_the_ability_layer` encodes that rule.
- **`data/abilities.json` marks 224 rows tier 1 while the engine implements 14.** Pre-existing: the
  field is aspirational in the imported data rather than a statement about engine coverage. Worth a
  separate pass; not touched here beyond the 14 in scope.
- **The multi-hit loop is balance-visible.** 26 previously single-hit multi-strike moves now really
  hit 2-5 times for *every* Pokemon, not just Mega Heracross (Cloyster's Icicle Spear under an early
  level cap is the case to look at). No existing test asserted their damage and the suite is green,
  but this wants a rebalance pass.
