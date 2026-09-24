# Mega Evolution — Sinnoh Design

**Status:** authoritative design reference for the game's single battle gimmick.
**Revision:** 2026-09-23**b** — **corrected against the shipped data.** The previous revision
contradicted the owner's locked decisions in five places (roster split, the BST rule, the boss
Mega assignments, the Team Galactic ruling and the cap table). **Where this document and the data
disagreed, the data won** — no data file was changed by this pass. Every correction is listed in
§10. Earlier revision archived at `tools/_work/mega/mega-design.prev.md`.
**Codes against:** `docs/DATA_CONTRACT.md` §11 (§11.1 shape, §11.2 engine, §11.3 cap
interaction, §11.4 exclusions, §11.5 decided special cases).
**Depends on:** `docs/research/level-curve.md` §1.1 (**the cap table — authoritative for every
cap number in this file**) and §1.3 (headroom); `docs/research/game-design.md` §1 (progression
order), §4 (cross-gen encounter placement), §5.2 (type discipline vs gyms 1–3);
`docs/research/mega-abilities.md` §2 (Champions ability table — authoritative) and §4 (the nine
owner-decided forms); `docs/research/rosters-gyms14.md`, `rosters-gyms58.md`, `rosters-e4.md`,
`rosters-story.md` (**the shipped boss rosters**).

**Reads against:** `data/megas.json` (97 forms), `data/mega_ability_overrides.json` (the nine
owner-decided abilities), `data/level_caps.json` (15 rows, 18→100), `data/rom/bosses.json`
(31 bosses × 6 Pokémon), `data/abilities.json` (tiers and hooks).

**Scope:** when the Key Stone is granted, where all 92 Mega Stones are placed, which bosses
Mega Evolve, the Primal ruling, the dangerous-Mega list, and the excluded-gimmick
confirmation.

---

## 0. Decisions, in two tables

### 0.1 The six questions this document answers

| # | Question | Decision |
|---|---|---|
| 1 | **When is the Key Stone granted?** | **After Fantina.** `mega_unlocked_at = "badge:relic"`, handed over in Hearthome City. Exactly two stones exist in the world at that moment. §2 |
| 2 | **Where do the stones go?** | Seven flag-gated tiers keyed to the badge ladder: **2 / 7 / 14 / 19 / 26 / 9 / 15 stones**. Full table §3.4. |
| 3 | **Do bosses Mega Evolve?** | **Yes — 24 of the 31 bosses do.** Every gym leader from **Fantina (gym 3)** on, all four Elite Four, Cynthia, **seven of the nine Team Galactic fights**, Charon, and Barry from **R3**. §4 |
| 4 | **Primal Reversion?** | **OUT.** Ruling A. Reasoning kept in §5 so the build can defend it. |
| 5 | **Dangerous Megas?** | Named in §6 in **four classes** — A (base species available too early), B (BST ≥ 700), C (the ability, not the stat line) and D (the four *under*-powered forms that must not be "fixed"). Handling is **late tier placement in every case**; nothing is excluded for power. |
| 6 | **Dynamax / Z-Moves / Tera?** | **None. Nowhere.** Confirmation + enforcement checklist §7. |

### 0.2 The seven final rulings this revision applies

Not open. Recorded here so no downstream pass relitigates them.

| Ruling | Content | Where applied |
|---|---|---|
| **A** | **Primal Reversion is OUT.** Drop Primal Groudon and Primal Kyogre entirely; no Red Orb / Blue Orb item. Build asserts absence from `data/megas.json`. | §5, §7.2 |
| **B** | **Mega Rayquaza is IN and is the one Mega with no stone**: `stone: null`, `requiresMove: "dragon-ascent"`. `can_mega_evolve()` branches on `stone == null` and checks the MOVESET, still obeying one-Mega-per-side. | §1.3, §8.2 |
| **C** | The contract field is **`"abilities": [ … ]`** — an array, not a single string. | §1.5, §8.1 |
| **D** | **Z-A ability sourcing is RESOLVED.** Z-A has no Ability system; abilities come from **Pokémon Champions**. Use `docs/research/mega-abilities.md` §2 and `tools/_work/megaability/champions-abilities.md` — do not re-research. **Nine forms are absent from Champions**; they were `"abilities": []` + `"abilityStatus": "pending-owner"` and are now **owner-decided** — `data/mega_ability_overrides.json` is authoritative for all nine (§1.5). | §1.5 |
| **E** | **The so-called Champions mega abilities leak is REJECTED** — a Chinese-forum claim of localisation insider access, not a datamine, and wrong where testable (it claimed Lucario Z = Prankster; official is Aura Guard). Never seed data from it, not even as a placeholder. | §1.5, §6.5 |
| **F** | **Mega Starmie uses Attack 100 with Huge Power** (Champions/Showdown), **not** Serebii's Z-A figure of 140. Serebii's Z-A tables compensate for Z-A having no abilities; this game has abilities, so 140 + Huge Power double-counts. **Prefer Champions/Showdown stat lines over Serebii Z-A tables throughout.** | §1.4 |
| **G** | **Seven Champions-exclusive abilities must be authored by hand** — Mega Sol, Dragonize, Aura Guard, Piercing Drill, Eelevate, Fire Mane, Spicy Spray. Only three have public effect text; the other four stay tier 3 (data-only, inert) rather than guessing a mechanic. | §1.5 |

**The one-sentence thesis.** The Key Stone is only *permission*; the stone table is the
*power curve*. Gating the Key Stone on the Relic Badge starts Mega Evolution exactly where
`game-design.md` §5.2's type-discipline guard ends, so the two balance systems never overlap
and neither has to be re-verified against the other.

---

## 1. Roster reconciliation — read this before generating `data/megas.json`

### 1.1 Count audit of the roster handed to this pass

| Claim | Reality |
|---|---|
| Header: *145 forms; 145 multi-source-confirmed* | **Does not reconcile.** The enumerated block contains **120 lines**. |
| 120 enumerated lines | **48 XY/ORAS listed twice** (once with slug abilities, once Title-Cased) **+ 24 Z-A** = 120 lines, **72 distinct forms**. |
| XY | **30 forms / 28 species** — the 28 XY species, with **Charizard and Mewtwo each doubled** (x/y). Includes **Mega Latias and Mega Latios**. |
| ORAS | **18 new Megas** — the ORAS era's 22 minus the 2 Primals (ruling A) minus Latias and Latios, which are **XY** forms. |
| Legends Z-A | **49** distinct in the shipped roster. The handed roster enumerated only 24 — a **subset** (§1.2). |

**Gen 6 totals, stated once so nothing re-derives them:** **XY 30 + ORAS 18 = 48 Gen 6 rows, 46
Gen 6 species.** Those are the numbers §1.2 and §8.1 use.

**Two data defects in the roster text, both build-breaking if copied verbatim:**

| Defect | Correct value |
|---|---|
| Block 1 tags **Mega Latias / Mega Latios** `[xy]`; block 2 tags them `[oras]`. | **`xy`** — **owner ruling; block 1 is right.** The previous revision of this document adopted block 2 and was wrong. |
| Block 1 renders Mega Rayquaza as `stone=` (empty string); block 2 as `stone=null`. | **JSON `null`.** An empty string is not null and will fall through the `stone == null` branch in `can_mega_evolve()` (ruling B), silently making Mega Rayquaza unreachable. |

> **Open data discrepancy, reported not fixed.** `data/megas.json` currently ships
> `latias-mega` and `latios-mega` with `"introducedIn": "oras"`, which disagrees with the ruling
> above. This pass corrects documents only and changes no data file. Fixing it is a one-field
> edit in `tools/build_megas.py` plus a rebuild; **it moves no stone, no tier and no stat** —
> `introducedIn` is provenance metadata, and both forms stay T7 on BST grounds (§6.2).

**Resolution:** this document is authored against the **union** of the handed roster and
`docs/research/mega-abilities.md`, which ruling D makes authoritative for every Z-A form, and is
then reconciled against the shipped `data/megas.json`.

### 1.2 The shipped roster — 97 rows, 92 stones, 93 distinct forms

| Set | Rows in `data/megas.json` | Stones | Source of record |
|---|---|---|---|
| XY | **30** | 30 | canon — incl. Latias / Latios (§1.1) |
| ORAS | **18** | **17** — Mega Rayquaza has no stone (ruling B) | canon, minus 2 Primals (ruling A) |
| Legends Z-A — in Champions | **40** | 39 — Meowstic M/F share one stone | `mega-abilities.md` §2 |
| Legends Z-A — absent from Champions | **9** | 6 — Magearna ×2 share one, Tatsugiri ×3 share one | `data/mega_ability_overrides.json` (owner-decided, §1.5) |
| **Total** | **97 rows** | **92 stones + 1 Key Stone** | |

> **Why three different totals are all correct.** **97** = JSON rows (every cosmetic variant
> gets its own row). **93** = distinct Mega *forms* if cosmetic variants collapse — the number
> the previous revision used. **92** = Mega Stone items. Always quote the number with its
> unit: `data/items.json` gets 92 + 1, `data/megas.json` gets 97.

### 1.3 Groups that share something — three kinds, only one of which the contract handles

| Kind | Members | Disambiguated by | Contract status |
|---|---|---|---|
| **Split stones** — one base species, two Megas, two stones | Charizard #6 (x/y), Mewtwo #150 (x/y), Raichu #26 (x/y), Absol #359 (`absolite`/`absolite-z`), Garchomp #445 (`garchompite`/`garchompite-z`), Lucario #448 (`lucarionite`/`lucarionite-z`) | **The held stone.** | **Handled** — §11.1 says exactly this. |
| **Cosmetic variants** — one base species, **one** stone, several base forms | Meowstic Male/Female (#678, `meowsticite`, both Trace); Magearna + Magearna Original Colour (#801, `magearnite`); Tatsugiri Curly/Droopy/Stretchy (#978, `tatsugirinite`) | **Nothing.** Same `base`, same `stone`. | **CLOSED IN DATA** — the discriminator ships as **`requiresForm`** (`meowstic-male`, `meowstic-female`, `magearna`, `magearna-original`, `tatsugiri-{curly,droopy,stretchy}`), *not* the `baseForm` this document proposed. The **contract** still does not document it — §8.3 proposal 1. |
| **Form-dependent base** — the Mega is built on a non-default form | **Mega Zygarde** derives from **Zygarde Complete** (708 → **778**, the roster's one exception to base+100, §1.4); **Mega Floette** derives from **Floette Eternal Flower** (551 → 651) | **`requiresForm`** — shipped on both (`zygarde-complete`, `floette-eternal`) | **Content dependency — §8.2.** Power Construct is vetoed (`mega-abilities.md` §6), so Zygarde Complete needs its own obtain path or Mega Zygarde is unreachable content. Floette Eternal Flower needs one too. |

**Split-pair rule (unchanged):** the two stones of a split pair never appear in the same
tier, and the strictly stronger form is always later. Tier is carried by the item's spawn
flag, so `data/megas.json` needs no new field for it.

| Base | Tiers | Rule applied |
|---|---|---|
| Charizard | `charizardite-x` T5 · `charizardite-y` T6 | Drought is the stronger effect. |
| Mewtwo | both T7 | 780 BST; the species is not in the Sinnoh story. |
| Raichu | `raichunite-x` T5 · `raichunite-y` T6 | Y is Volkner's gift (§4.2). |
| Absol | `absolite` T2 · `absolite-z` T5 | Dark/Ghost + Sharpness is a pure offensive upgrade. |
| Garchomp | both T7 | §6.1 — this line is the single biggest hazard in the game. |
| Lucario | `lucarionite` T2 · `lucarionite-z` T6 | T2 is Maylene's gift; Aura Guard is stronger **and** unimplemented (§1.5). |

### 1.4 Stats — the Z-A double-count trap (ruling F)

**The rule, corrected.** `base BST + 100` holds for **96 of the 97 shipped forms**. **Mega
Zygarde is the sole exception, at BST 778.** It is built on **Zygarde-Complete** (708), not the
50% Forme (600), so the +100 shape would predict 808; the shipped spread is
216/70/91/216/85/100 = **778**. The previous revision asserted base+100 with *no exceptions*,
which is wrong twice over — it also implied the rule is evaluated against the default species
row.

**How to check the rule without false positives.** Resolve `requiresForm` **first**, then apply
+100:

| Form | Naive check vs `data/species.json` default row | Real base | Verdict |
|---|---|---|---|
| **Mega Zygarde** | 778 vs 600 + 100 = 700 | Zygarde-**Complete** 708 | **The one real exception** — 778, i.e. +70. |
| Mega Floette | 651 vs 371 + 100 = 471 | Floette-**Eternal Flower** 551 | **Not an exception** — 551 + 100 = 651 exactly. |

Both rows declare their base in the shipped data as `requiresForm`
(`zygarde-complete`, `floette-eternal`), which is what makes this machine-checkable: **resolve
`requiresForm`, apply +100, and expect exactly one failure — Zygarde.**

**Ruling F, stated as arithmetic.** Serebii's Legends Z-A tables inflate raw stats because
**Z-A has no Ability system** — the stat line *is* the compensation. This game has abilities,
so taking both double-counts.

| Source | Mega Starmie Attack | With Huge Power | Comparison |
|---|---|---|---|
| **Champions / Showdown — USE THIS** | **100** | **200 effective** | already above Mega Mewtwo X's 190, the highest Attack in the roster |
| Serebii Z-A table — do not use | 140 | **280 effective** | higher than any base stat any Pokémon has ever had |

Base Starmie is 60/75/85/100/85/115 = 520, so Mega Starmie is 620 at base+100 and its Attack
rises 75 → 100 (shipped: 60/100/105/130/105/120). **Even the correct figure is a T7 stat line
(§6.3).**

**Double-count watchlist.** Ruling F generalises: any Z-A Mega whose Champions ability multiplies
damage or halves it is a candidate for the same inflation. All 97 rows now ship stats, so this
table is a **re-check list for any new import**, not an open question.

| Form | Champions ability | What to suspect in Serebii's Z-A spread |
|---|---|---|
| **Mega Starmie** | Huge Power | **CONFIRMED inflated** — Atk 140 vs 100. The template case. |
| Mega Absol Z | Sharpness | inflated Atk (Sharpness is +50% to slicing moves) |
| Mega Dragonite | Multiscale | inflated HP/Def/SpD (Multiscale halves damage at full HP) |
| Mega Lucario Z | Aura Guard | inflated Def (halves contact damage) |
| Mega Barbaracle · Mega Golisopod | Tough Claws | inflated Atk |
| Mega Crabominable | Iron Fist | inflated Atk |
| Mega Glimmora | Adaptability | inflated SpA |
| Mega Floette | Fairy Aura | inflated SpA |

**Shipped spreads for the nine owner-decided forms** (§1.5) — these are in `data/megas.json`, not
assumptions:

| Form | Type | HP/Atk/Def/SpA/SpD/Spe | BST |
|---|---|---|---|
| Mega Heatran | Fire/Steel | 91/120/106/175/141/67 | **700** |
| Mega Darkrai | Dark | 70/120/130/165/130/85 | **700** |
| Mega Zygarde | Dragon/Ground | 216/70/91/216/85/100 | **778** *(built on Complete, not 50%)* |
| Mega Magearna · Mega Magearna (Original Colour) | Steel/Fairy | 80/125/115/170/115/95 | **700** (identical) |
| Mega Zeraora | Electric | 88/157/75/147/80/153 | **700** |
| Mega Tatsugiri Curly · Droopy · Stretchy | Dragon/Water | 68/65/90/135/125/92 | **575** (identical) |

### 1.5 Abilities — the array, the provenance, and the 14 hooks that used to be missing

**Shape (ruling C).** `"abilities": [ … ]`, an array.

> **Contract conflict, resolved.** `DATA_CONTRACT.md` §11.1's comment says *"a few Z-A Megas
> have two (e.g. Mega Heatran)"* and cites Mega Heatran = Flash Fire + Flame Body. **That
> comment is wrong and ruling D supersedes it.** Flash Fire and Flame Body are base Heatran's
> normal and hidden abilities in every mainline game — not a published Mega ability pair. No
> source assigns any Mega two abilities, and none of the 40 Champions rows has two.
> **Therefore `abilities` always has length exactly 1** in the shipped data — it was *0 or 1*
> while the nine forms were pending, and the owner has since decided all nine (below). Keep the
> array — it is the right shape and costs nothing — but the contract comment must be corrected
> (§8.3) and a test must assert length ≤ 1 (§7.2). **Mega Heatran ships `["earth-eater"]`** (owner
> write-in), not the `flash-fire` + `flame-body` pair the contract comment implies.

**Provenance (rulings D and E), as shipped.** Four `abilityStatus` values, and **no row is
empty or pending any more**:

| `abilityStatus` | Count | Meaning |
|---|---|---|
| `"canon"` | 48 XY/ORAS rows | Mainline canon; never in doubt. *(The previous revision expected no status field on these; the build writes `"canon"`.)* |
| `"champions"` | 40 Z-A rows | Traceable to Pokémon Champions; Serebii and Game8 agree row-for-row. Do not substitute a *better* ability for any of these. |
| `"owner-decided"` | **6** | Absent from Champions, decided by the owner. |
| `"owner-decided-by-recommendation"` | **3** | Taken as recommended, **not** explicitly confirmed — flagged for review if the owner wants to revisit. |

**The nine former `pending-owner` forms are RESOLVED.** `data/mega_ability_overrides.json` is the
authoritative record (DATA_CONTRACT §11.5 step 2) and `data/megas.json` matches it row for row:

| Form | Ability | Status | Engine |
|---|---|---|---|
| Mega Heatran | **`earth-eater`** | `owner-decided` — a **write-in**, not one of `mega-abilities.md` §4.0's three options | tier **1**, `onTypeImmunity` |
| Mega Darkrai | **`dark-aura`** | `owner-decided` | tier **1**, `onDamageCalc` |
| Mega Zygarde | **`thick-fat`** | `owner-decided-by-recommendation` | tier **1**, `onDamageCalc` |
| Mega Magearna | **`soul-heart`** | `owner-decided-by-recommendation` | tier **1**, `onHpCross` |
| Mega Magearna (Original Colour) | **`soul-heart`** | `owner-decided-by-recommendation` — mirrors the standard colour by rule | tier **1**, `onHpCross` |
| Mega Zeraora | **`transistor`** | `owner-decided` | tier **1**, `onDamageCalc` |
| Mega Tatsugiri (Curly / Droopy / Stretchy) | **`storm-drain`** ×3 | `owner-decided` — one decision, three rows | tier **1**, `onTypeImmunity` |

**All nine are tier 1 on an existing hook, so the decision added zero engine work.** Ruling E
still bars the forum leak as a source, and note that the leak's Darkrai (Bad Dreams), Magearna
(Soul Heart) and Zeraora (Speed Boost) guesses are **not** what shipped for two of the three —
the agreement on Soul-Heart is coincidence with canon, not evidence (§6.5).

> **Reported, not fixed: the override file's `form` ids do not match `data/megas.json` for four
> rows.** The overrides use `magearna-original-mega`, `tatsugiri-curly-mega`,
> `tatsugiri-droopy-mega`, `tatsugiri-stretchy-mega`; the shipped form ids are
> `magearna-mega-original`, `tatsugiri-mega-curly`, `tatsugiri-mega-droopy`,
> `tatsugiri-mega-stretchy`. The *abilities* agree, so nothing is wrong in the game data — but a
> test that joins the two files on `form` will silently match only 5 of 9. Fix by id, in the data,
> in a separate pass.

**Engine reality — RESOLVED DURING THIS PASS.** The previous revision listed **14 forms whose
ability was `tier: 3` with `hook: "none"`** — the data row existed, the behaviour did not. An
ability-implementation workflow landed **all 14 hooks while this correction was being written**:
as of `data/abilities.json` at 2026-09-23 21:30, **every one of the 97 forms' abilities is
`tier: 1` with a real hook**, so the ‡ blocker set is empty and rule B9 is satisfied for every
boss.

> **This is a snapshot of another workflow's output, so verify rather than trust it.** One line:
> ```bash
> python -c "import json;a={x['name'].lower().replace(' ','-'):x for x in json.load(open('data/abilities.json'))};m=json.load(open('data/megas.json'))['forms'];print([(f['id'],f['abilities'][0]) for f in m if a[f['abilities'][0]]['tier']!=1])"
> ```
> An empty list means this section is still true. A non-empty one means a hook regressed — put the
> affected forms back behind ‡ and re-read rule B9 and §6.4.

The 14, with the hook that landed:

| ‡ Form | Ability | Class | Effect text published? | Hook now in `data/abilities.json` | Tier |
|---|---|---|---|---|---|
| **Mega Rayquaza** | `delta-stream` | canon | yes | `onFieldEnter` | T7 |
| **Mega Gengar** | `shadow-tag` | canon | yes | `onSwitchAttempt` | T7 · **is Fantina's gym-3 Mega (§4.2)** — was the only hook-blocked ability a boss brought to the field before the League |
| **Mega Kangaskhan** | `parental-bond` | canon | yes | `onMultiHitCount` | T7 |
| **Mega Heracross** | `skill-link` | canon | yes | `onMultiHitCount` | T5 · **not** a boss Mega — Aaron runs Mega Scizor (§4.3) and keeps a non-Mega Heracross, so the revert is now a stone swap |
| **Mega Mewtwo X** | `steadfast` | canon | yes | `onFlinch` | T7 |
| **Mega Skarmory** | `stalwart` | canon (Gen 8) | yes | `onRedirect` | T4 |
| **Mega Golurk** | `unseen-fist` | canon (Gen 8) | yes | `onProtectCheck` | T4 |
| **Mega Lucario Z** | `aura-guard` | **Champions-exclusive** | **yes — halves contact damage** | `onDamageCalc` | T6 |
| **Mega Excadrill** | `piercing-drill` | **Champions-exclusive** | **yes — pierces Protect for 1/4** | `onProtectCheck` | T4 · **is Bertha's E4 Mega (§4.3)** |
| **Mega Scovillain** | `spicy-spray` | **Champions-exclusive** | **yes — burns an attacker that lands a damaging move** | `onHitTaken` | T5 |
| **Mega Meganium** | `mega-sol` | **Champions-exclusive** | **NO** ⚠ | `onWeatherView` | T4 — **tier priced as inert; see §6.4** |
| **Mega Feraligatr** | `dragonize` | **Champions-exclusive** | **NO** ⚠ | `onModifyMoveType` | T4 — **same** |
| **Mega Eelektross** | `eelevate` | **Champions-exclusive** | **NO** ⚠ | `onTypeImmunity` | T4 — **same** |
| **Mega Pyroar** | `fire-mane` | **Champions-exclusive** | **NO** ⚠ | `onDamageCalc` | T4 — **same** |

**Ruling G — now in tension with the data, and the owner has to settle it.** Ruling G says the
four Champions-exclusive abilities with **no published mechanic** — `mega-sol`, `dragonize`,
`eelevate`, `fire-mane` — **stay `tier: 3`, inert, and must not be guessed.**
`data/abilities.json` now ships all four at **tier 1 with hooks** (`onWeatherView`,
`onModifyMoveType`, `onTypeImmunity`, `onDamageCalc`).

> **Flagged for the owner (§9), not resolved here.** Either those four implementations are sourced
> from something this document has not seen — in which case record the source in
> `mega-abilities.md` §2 and ruling G is satisfied — or a mechanic has been invented for an
> ability TPC has not published, which is exactly what ruling G forbids. **The balance consequence
> is real either way:** Mega Meganium (625), Mega Feraligatr (630), Mega Eelektross (615) and Mega
> Pyroar (607) were placed at T4/T5 *on the assumption that they play as +100 BST and a type change
> and nothing else* (§6.4). If they now do something, their tiers were priced wrong.

**One marker now, not two.** `mega-abilities.md` §5.3 split the old flag in two; the owner's
decisions have since retired half of it.

| Marker | Meaning | Members | Tier consequence |
|---|---|---|---|
| **◊** | **provenance-pending** — no sourced ability | **none — retired.** All 97 rows have a sourced ability (canon / Champions / owner-decided). | — |
| **‡** | **engine-hook-pending** — ability sourced, hook unwritten | **none as of 2026-09-23b** — all 14 hooks landed mid-pass (above). The marks are kept in §3.4 and §6 as a *history* of which forms were blocked, because that is where a regression would show up first. | **no tier consequence**; blocked shipping, not placement |

**◊ is dead but its *effect* is not thrown away:** the tier placements in §3.4 and §6 that were
set "one tier late" for provenance reasons stay where they are. They were argued on power as well
(all nine are T7 bar Tatsugiri), and nothing in the owner's picks makes any of them safer.

### 1.6 Sinnoh-native coverage, and the starter gap

**33 of the 93 forms have a base species already present in vanilla Platinum.** The other 60
ride on `game-design.md` §4's cross-gen placements, which is exactly what that system is for.
§3.6 lists every base species that still needs a §4 slot.

> **Surfaced to the owner: the three Sinnoh starters have no Mega.** Turtwig, Chimchar and
> Piplup lines are absent from the roster, so **the player's own starter can never Mega
> Evolve**, and neither can Barry's (§4.5).
>
> **Design response: accept it, and compensate structurally.** The Tier-1 gift stone
> (`lopunnite`) keys off Buneary — a vanilla Eterna Forest **20% slot** every player walks
> past — so no player is ever Mega-less. The starter stays the constant and the Mega is the
> guest. Do **not** invent a Sinnoh-starter Mega: it would be the only non-canon form in a
> roster whose entire value is being traceable to a source.

---

## 2. Question 1 — when does the player get the Key Stone?

### 2.1 Recommendation

> **After Fantina. The Relic Badge is the unlock flag.**
>
> ```jsonc
> GameState.mega_unlocked_at = "badge:relic"     // gym 3, Hearthome City, cap 36 -> 45
> ```
>
> Handed over in **Hearthome City** the moment the Relic Badge is set — **by the player's NPC
> counterpart, Dawn or Lucas**, per `DATA_CONTRACT.md` §12.5 (which supersedes §2.4's proposal of
> Cynthia; the *checkpoint* is unchanged) — together with **one tier-1 stone** (`lopunnite`). One
> more (`chimechite`) is findable on the Route 209 / Lost Tower leg that immediately follows.
>
> **Correction to the old "exactly two stones exist" claim.** The owner's gym-award list is
> locked, and its first three awards land *before* the Ring: Roark gives `aerodactylite`,
> Gardenia `victreebelite`, Fantina `gengarite`. Those three are **dormant rewards** — handed over
> with no Key Stone to use them — so the player reaches Hearthome holding **three dead stones plus
> `lopunnite`**, with `chimechite` one route away. Scarcity of *usable* choice at T1 is intact;
> the sentence "two Mega Stones exist in the world" is not, and §3.3 carries the tier conflict this
> creates.

Using the badge flag rather than a bespoke story flag is deliberate: contract §11.2's
`mega_unlocked_at` is already badge-shaped, the badge ladder is already the game's universal
progression spine, and it makes the gate self-documenting in save data. It also matches
`data/level_caps.json`, whose gym-3 row already carries `raisedBy: "badge:relic"`.

### 2.2 Justification against the cap table

The cap rule is `cap = next checkpoint boss's ace level`, so **the player meets every gym
exactly level-matched and can never be above it.** Level is unavailable as a lever in both
directions: the player cannot grind past a wall, and the designer cannot assume the player
out-levels anything. That makes **+100 BST plus a type change plus an ability change** the
single largest edge available to either side — far larger than in a vanilla game where the
player is routinely 5–10 levels up on a gym.

So the question is not *when is a Mega fun*, it is **at which cap does +100 BST stop being
decisive on its own?** The boss teams answer it:

Re-run against the shipped six-Pokémon rosters (`data/rom/bosses.json`) and the real caps
(`level-curve.md` §1.1). The argument survives the rebalance unchanged — the numbers are bigger,
the ratios are not:

| Checkpoint | Cap | Boss's total party BST | Boss's best single BST | A Tier-1 Mega at that cap | Verdict |
|---|---|---|---|---|---|
| Roark | **18** | 2,127 across **6** | Klawf 450 | 580 | **1.3× the biggest thing on the team, and 27% of the whole party budget. One-mon sweep.** |
| Gardenia | **27** | 2,790 across **6** | Roserade 515 | 580 | Gym 2 becomes a formality. |
| Fantina | **36** | 2,940 across **6**, incl. a 600 Mega | Gengar 500 → **Mega Gengar 600** | 580 | **She already answers it herself** — and the player has no Ring yet, by design (§4.2). |
| **Maylene** | **45** | **2,963 across 6, incl. a 625 Mega** | **Mega Lucario 625** | 580 | **The boss's Mega is the biggest thing on the field. Correct.** |

Three independent reasons the line falls exactly here:

| # | Reason | Detail |
|---|---|---|
| 1 | **It is where §5.2 ends.** | `game-design.md` §5.2 guards gyms **1, 2 and 3 only** — banning Fighting/Ground/Steel before Roark, Steel/Ice/Fire before Gardenia, Dark/Ghost before Fantina. A Key Stone inside that window makes the whole guard moot: a 580-BST Mega beats a type ban. Granting it **on the Relic Badge — the badge Fantina gives — starts Mega Evolution on the first turn after §5.2 stops applying.** The two systems never overlap and §5.2 needs **zero** re-verification. |
| 2 | **It fills the empty badge.** | `game-design.md` §3.4: Defog is deleted, so **Relic is the one badge in the game with no traversal verb** — it grants only a cap raise, an obedience bump and a story flag, and that section explicitly flags badge 3 as at risk of *feeling hollow*. Mega Evolution is the largest unlock in the game and badge 3 is the only slot with room for it. This also makes §3.4's *Option B* (shuffling FLY to Relic and inventing a WADE verb) unnecessary. |
| 3 | **Runway.** | **24 of the 31 boss fights come after Fantina** — 5 gym leaders, 4 Elite Four, Cynthia, 9 Galactic/Charon fights and 5 Barry fights — and **all 24 are designable around Megas** (§4). Held any later and the mechanic is a coda. |

And one piece of luck worth taking: **the very next boss after the unlock is Maylene, whose ace is
Lucario 45 — and Lucario has a Mega.** So **the first fight in which the player *can* Mega Evolve is
a mirror match** against the most iconic Mega in the franchise, at exactly matched level, with no
roster edit of any kind. The *mechanic* itself debuts one fight earlier, on Fantina's Gengar
(§4.2), which is what makes the mirror land: threat first, tool second.

### 2.3 Alternatives considered and rejected

| Checkpoint | Cap | Verdict | Why |
|---|---|---|---|
| Prologue / Sandgem | 18 | **No** | See the table above. Also strands the mechanic with zero usable stones. |
| After **Roark** (`badge:coal`) | 18→27 | **No** | Gardenia is already the softest gym in vanilla. §5.2's careful *no Steel/Ice/Fire before Eterna* ban is pointless against a 580-BST Normal/Fighting. |
| After **Gardenia** (`badge:forest`) | 27→36 | **No — and this is the trap option** | Fantina is six Pokémon peaking at a Mismagius 36, and **she already Megas** (§4.2) — handing the player a Mega here turns the intended demonstration into a mirror a gym early. Worse: **the Forest Badge is also when the Bicycle arrives** (Rad Rickshaw), which opens Wayward Cave and its **Gible L17–20**. Granting the Key Stone here hands the player permission at the exact moment they can start raising the game's worst Mega candidate (§6.1). |
| **After Fantina** (`badge:relic`) | 36→45 | **ADOPTED** | §2.2. |
| After **Maylene** (`badge:cobble`) | 45→54 | Defensible, second choice | Costs the free Lucario mirror. Veilstone is better used as the *second* beat — the meteorite lore and the Game Corner stone counter (§3.4 T2) — than as the unlock. Leaves 22 boss fights instead of 24. |
| After **Wake** (`badge:fen`) | 54→66 | **No** | SURF opens roughly half the map at once; the player would collect a dozen stones in one act with no permission to use them, then receive everything simultaneously. Pacing collapse. |

**Direct answer to the brief's question: after Fantina, not before.** Fantina is the last boss
`game-design.md` §5.2 protects by type discipline, and the protection and the permission must
not overlap.

### 2.4 The fiction — Sinnoh already owns this

Sinnoh does not need an imported Kalos legend. It has meteorites.

| Beat | Where | Content |
|---|---|---|
| **The grant** | Hearthome City, Amity Square gate, on the Relic Badge | **SUPERSEDED — the giver is the player's counterpart, Dawn or Lucas** (`DATA_CONTRACT.md` §12.5, an owner decision; `data/events/mega_ring.json` implements it). The *place, checkpoint and framing* below are unchanged, and the bond reading works better from a rival-friend than from the Champion: Amity Square is the game's existing affection space and Fantina's Ghost gym is its existing *spirit* gym, so the Relic Badge is thematically the bond badge. |
| **The rhyme** | — | Both Tier-1 stones key off **friendship evolutions** — Buneary→Lopunny, Chingling→Chimecho. The first two Megas in the game are earned by Pokémon that evolve through affection. Deliberate. |
| **The explanation** | **Veilstone City**, on arrival (T2) | Veilstone is canonically named for its meteorites and has them on display. They are the Key Stone's origin: one impact, one shower of fragments. This is why stones are scattered across Sinnoh and why the mines, the riverbeds and the Underground hold them. |
| **The antagonist** | Galactic arc | **SUPERSEDED — Team Galactic *does* Mega Evolve** in seven of its nine fights (§4.4), plus Charon. Cyrus's *world without spirit* framing survives only as dialogue, never as a mechanic: **do not write a line, a tutorial or a test that depends on Galactic being unable to Mega Evolve.** |

### 2.5 Data and flags

| Field | Value |
|---|---|
| `GameState.mega_unlocked_at` | `"badge:relic"` |
| Key Stone item class | **Key Item.** Never occupies a held-item slot; cannot be sold, tossed, Knocked Off or Tricked. |
| Mega Stone item class | Ordinary **held item**, one per Pokémon. Immune to Knock Off / Trick / Thief / Covet / Fling (canon). |
| Battle UI | The Mega button renders only when `GameState.has_key_stone()` is true. **It is the only gimmick button that will ever exist** (§7). |
| Stone spawn gating | Every stone's overworld spawn, shop row and prize row is gated on a **tier flag** (§3.1), not on geography. |

---

## 3. Question 2 — where does every Mega Stone go?

### 3.1 The seven tiers

**A tier is a story flag, not a place.** The stone's spawn/shop/prize row is gated on the
flag; the *location* is chosen for flavour. This lets a late stone sit on an early route
(Floaroma Meadow can hold a Tier-2 stone) with no risk of early access, and it makes the whole
system one boolean per item to the engine.

| Tier | Unlock flag | Cap in force | Region it opens | Stones | Running total |
|---|---|---|---|---|---|
| **T0** | *(game start)* | 18 → 36 | Twinleaf → Hearthome | **0** | 0 |
| **T1** | `badge:relic` | **45** | Hearthome, Amity Square, Rt 209, Lost Tower, Solaceon, Rt 210 S, Rt 215 | **2** | 2 |
| **T2** | `badge:cobble` | **54** | Veilstone (Game Corner, Dept. Store, meteorites), Rt 214, Maniac Tunnel, Valor Lakefront, Rt 213, Pastoria | **7** | 9 |
| **T3** | `badge:fen` — SURF | **66** | Great Marsh, Rt 212, Rt 210 N, Celestic, Fuego Ironworks, Rts 218–221, Canalave, Iron Island | **14** | 23 |
| **T4** | `badge:mine` — STRENGTH | **78** | Lake Valor, Lake Verity, Rt 211, Mt. Coronet north, Rts 216/217, Acuity, Snowpoint | **19** | 42 |
| **T5** | `badge:icicle` — CLIMB | **90** | Lake Acuity, Galactic HQ, Mt. Coronet summit, Spear Pillar, Distortion World, Sendoff Spring, Rt 222, Sunyshore | **26** | 68 |
| **T6** | `badge:beacon` | **96 → 99** | Rt 223, Victory Road, Pokémon League | **9** | 77 |
| **T7** | `flag:hall-of-fame` | **100** (uncapped) | Fight / Survival / Resort Areas, Stark Mountain, Turnback Cave, Snowpoint Temple, Rts 224–230 | **15** | **92** |

> **Caps corrected this revision.** The column above previously carried the vanilla ladder
> (14→62). Every number is now `data/level_caps.json` / `level-curve.md` §1.1, read as *the cap in
> force once that badge closes the previous window*. **No stone moved tier** — the tiers are story
> flags, and none of the flags changed.

**Shape of the curve:** 2 stones for the whole of gym 4, then a widening fan. The player's
*first* Mega is a considered choice between two; their tenth is a collection. That ordering is
the point — scarcity is what makes the Tier-1 decision matter, and it costs nothing later.

### 3.2 Placement rules

| # | Rule | Why |
|---|---|---|
| **R1** | **Availability.** A stone's tier is at least the tier at which its base species is obtainable. | A stone you cannot use is dead weight and a broken promise. |
| **R1a** | *Exception:* a **gym leader's own stone** may be handed over one tier before its base species is reachable. | Maylene's `lucarionite` (T2) vs. Riolu at Iron Island (T3). A promissory reward is a good beat; a random item ball is not. |
| **R2** | **Power.** A stone's tier is at least its power tier: **≤580 → T1+ · 581–615 → T3+ · 616–640 → T4+ · 641–699 → T5+ · 700+ → T6+**. | The only cap-safe way to scale a mechanic when levels are fixed is to scale *access*. |
| **R3** | **Ability override.** A blowout ability (§6.3) overrides R2 and pushes the stone to T5, T6 or T7 regardless of BST. | Under a hard cap an ability is worth more than a stat line. Mega Mawile is 480 BST and a T5 stone. |
| **R4** | **Coverage.** No stone may hand the player a type answer that `game-design.md` §5.2 denied them. | **Satisfied for free**: §5.2 covers gyms 1–3, and no stone is *usable* until the Key Stone lands after gym 3. The three pre-Ring gym awards (§3.3) are inert while the player holds them, so they grant no type answer either. Zero rows to check. |
| **R5** | **Split pairs never share a tier**; the stronger form is later (§1.3). | Prevents a species getting two upgrades in one act. |
| **R6** | **Scarcity.** T1 at most 2 stones, T2 at most 7. Then unconstrained. | The first choice must be a choice. |
| **R7** | **RETIRED** — *"◊ provenance-pending forms ship one tier late"*. No form is provenance-pending any more (§1.5): the owner decided all nine. **The placements R7 produced stay where they are**, because each was also justified on power (eight of the nine are T7 regardless), but R7 is no longer a live rule and must not be cited for a new stone. | An unsourced ability could not be balance-checked. There are none left. |
| **R8** | **‡ engine-hook-pending forms keep their tier** (§1.5) but are held out of the shipping build until the hook exists. **Currently vacuous — no form is hook-blocked (§1.5)** — but keep the rule: it is the correct response to the next unimplemented ability, and to a regression. | A missing hook is a schedule problem, not a balance one. Moving the tier would be the wrong fix. |

### 3.3 The spine — every Mega-using gym leader gives you their stone

The most legible rule in the table, and it does most of the work on its own. Beat a leader who
Mega Evolved on you, and you inherit the stone. **The award list itself is locked by the owner**
(CLAUDE.md, *Gym stone awards*), and `data/rom/bosses.json` carries it as `awardsStone`:

| Leader | Their Mega | Stone you receive | §3.4 tier | Effect |
|---|---|---|---|---|
| **Roark** (1) | *none* (pre-Ring) | `aerodactylite` | **T5** ⚠ | Dormant reward — no Key Stone yet. |
| **Gardenia** (2) | *none* (pre-Ring) | `victreebelite` | T3 ⚠ | Dormant reward. |
| **Fantina** (3) | **Mega Gengar** | `gengarite` | **T7** ⚠ | The fight that unlocks the mechanic hands you its stone. |
| **Maylene** (4) | Mega Lucario | `lucarionite` | T2 | Usable from Iron Island (R1a). |
| **Crasher Wake** (5) | Mega Gyarados | `gyaradosite` | T3 | Magikarp is everywhere; instantly usable. |
| **Byron** (6) | Mega Steelix | `steelixite` | T4 | Turns §6.1's *Onix is a pre-badge-1 catch* hazard into the fight's reward. |
| **Candice** (7) | Mega Froslass | `froslassite` | T5 | Snorunt is on Routes 216/217, one tier earlier. |
| **Volkner** (8) | Mega Raichu Y | `raichunite-y` **and** `raichunite-x` | T6 / **T5** ⚠ | Both Raichu stones, per the locked list. |
| **Cynthia** (Champion) | **Mega Garchomp** | `garchompite` | **T7** | Not an `awardsStone` row — `awardsStone` is gym-leaders-only in the contract (§7.1). It is a **T7 post-game placement** handed over after the Hall of Fame. |

> ### ⚠ OPEN CONFLICT — the locked award list outruns §3.4's tier table, and this document cannot resolve it alone
>
> Five awards arrive earlier than the tier §3.4/§6 assigns their stone:
> `aerodactylite` (given at gym 1, tiered **T5** on §6.1 grounds — the Old Amber is an early
> Underground find), `victreebelite` (gym 2, T3), `gengarite` (gym 3, tiered **T7** because
> **Shadow Tag is §6.3's worst ability under a hard cap**), `raichunite-x` (gym 8, T5) and
> `raichunite-y` (gym 8, T6 — this one is only just early).
>
> **Both halves are owner decisions, so the conflict is real and needs a ruling, not a guess:**
> the award list is locked in CLAUDE.md, and the power tiering is this document's §6. Three
> resolutions, in the order this document recommends them:
>
> 1. **Award beats tier — the stone is granted, and its *overworld/shop spawn* stays at its §3.4
>    tier.** One stone in the player's hands early is a designed exception; a hundred item balls
>    are not. This keeps both decisions intact and is the smallest change: the tier flag governs
>    *world placement only*, and §3.1's "a tier is a story flag" wording already allows it.
> 2. **Re-tier the five stones to their award point**, and re-run §6.1/§6.3 for each. This is the
>    honest version if the owner wants one rule; it costs the Shadow Tag containment argument.
> 3. **Change the award list.** Not recommended — it is locked, and Fantina awarding `gengarite`
>    is load-bearing for the Mega Ring beat (§2.1, `DATA_CONTRACT.md` §12.5).
>
> Until it is ruled on, **the data is right and the tier column above is advisory.**
> `data/rom/bosses.json` ships the locked awards.

This mirrors the badge→traversal ladder the game already runs on, gives every leader a
keepsake, and lands the strongest stone at the only moment it cannot distort anything.

### 3.4 Placement tables

Columns: **BST** = the shipped `bst` in `data/megas.json` — base + 100 for 96 of 97 forms, with
**Mega Zygarde the sole exception at 778** (§1.4). **◊** is retired: no form is
provenance-pending any more (§1.5), and the rows it once marked keep their tier. **‡** =
engine-hook-pending (R8).

#### Tier 1 — `badge:relic`, cap 45 — 2 stones

| Stone | Mega (types / ability) | BST | Where | How | Base line — earliest access |
|---|---|---|---|---|---|
| *(key item)* | **Key Stone** | — | Hearthome City, Amity Square gate | **Gift — Cynthia**, on the Relic Badge | — |
| `lopunnite` | Mega Lopunny · Normal/Fighting · Scrappy | 580 | Hearthome City, Amity Square gate | **Gift**, bundled with the Key Stone | Buneary — **Eterna Forest 20%** (vanilla). Every player has one. |
| `chimechite` | Mega Chimecho · Psychic/Steel · Levitate | 555 | **Lost Tower**, top floor bell | Overworld item ball | Chingling — Mt. Coronet south (vanilla), pre-Hearthome |

**Why these two.** One offensive, one defensive; 580 and 555, the two lowest ceilings worth
building around; both base species are vanilla Sinnoh and both are in the player's pocket by
Hearthome; both evolve by friendship (§2.4). Neither is a harder counter to Maylene than the
Staraptor and Alakazam vanilla already hands out before Veilstone, so R4 holds with room.

#### Tier 2 — `badge:cobble`, cap 54 — 7 stones · *Veilstone is the Mega hub*

| Stone | Mega (types / ability) | BST | Where | How | Base line — earliest access |
|---|---|---|---|---|---|
| `lucarionite` | Mega Lucario · Fighting/Steel · Adaptability | 625 | Veilstone Gym | **Gift — Maylene**, on the Cobble Badge (R1a) | Riolu — Riley's egg, Iron Island (T3) |
| `medichamite` | Mega Medicham · Fighting/Psychic · **Pure Power** | 510 | **Veilstone Game Corner** | 8,000 coins | Meditite — Mt. Coronet (vanilla) |
| `absolite` | Mega Absol · Dark · Magic Bounce | 565 | Route 213, cliff ledge above the beach | Overworld item ball | Absol — Route 213 (vanilla) |
| `houndoominite` | Mega Houndoom · Dark/Fire · Solar Power | 600 | Route 214, night | Hidden item (Dowsing Machine) | Houndour — Routes 214/215 night (vanilla) |
| `meowsticite` | Mega Meowstic (M **and** F) · Psychic · Trace | 566 | Route 215 | **Gift** — the Psychic trainer outpost | Espurr — §4.4 Routes 210/214/215 |
| `audinite` | Mega Audino · Normal/Fairy · Healer | 545 | **Veilstone Dept. Store 4F** | Purchase, 6,000 — the cheapest stone in the game | Audino — **needs a §4 slot** (§3.6) |
| `floettite` | Mega Floette · Fairy · Fairy Aura | **471** | Floaroma Meadow *(flag-gated, §3.1)* | Overworld item ball | Flabébé — Route 205 south 5% |

`floettite` at 471 is the **weakest Mega in the game** and is placed as such — a deliberate
low-ceiling option so the tier has a floor as well as a roof. `houndoominite` is a 600 at T2
only because **Solar Power does nothing without sun**: a 600-BST stone that plays like a 550
unless the player builds for it. That is exactly the kind of stone that belongs early, and it
is the same reasoning that makes it safe on Flint (§4.3). **`meowsticite` is one stone serving
two rows** — Meowstic Male and Female both take Trace (§1.3).

#### Tier 3 — `badge:fen` / SURF, cap 66 — 14 stones

| Stone | Mega (types / ability) | BST | Where | How | Base line — earliest access |
|---|---|---|---|---|---|
| `gyaradosite` | Mega Gyarados · Water/Dark · Mold Breaker | 640 | Pastoria Gym | **Gift — Crasher Wake**, on the Fen Badge | Magikarp — every fishing table |
| `aggronite` | Mega Aggron · Steel · Filter | 630 | Iron Island B2F | Overworld item ball | Aron — Iron Island (vanilla) |
| `chandelurite` | Mega Chandelure · Ghost/Fire · Infiltrator | 620 | Fuego Ironworks, furnace floor | Overworld item ball | Litwick — §4.4 Fuego Ironworks |
| `cameruptite` | Mega Camerupt · Fire/Ground · Sheer Force | 560 | Fuego Ironworks, slag heap | Hidden item | Numel — §4.4 Fuego / Stark fire biome |
| `ampharosite` | Mega Ampharos · Electric/Dragon · Mold Breaker | 610 | Valley Windworks *(return visit, flag-gated)* | **Gift** — the Windworks engineer | Mareep — **needs a §4 slot** |
| `manectite` | Mega Manectric · Electric · Intimidate | 575 | Route 212 north | Overworld item ball | Electrike — **needs a §4 slot** |
| `altarianite` | Mega Altaria · Dragon/Fairy · Pixilate | 590 | Route 210 north, Café Cabin | **Gift** — the café owner, after the Secret Potion beat | Swablu — **needs a §4 slot** |
| `sharpedonite` | Mega Sharpedo · Water/Dark · Strong Jaw | 560 | Route 220, sea floor | Underground-style find | Carvanha — §4.4 Routes 218–221 coastal |
| `dragalgite` | Mega Dragalge · Poison/Dragon · Regenerator | 594 | Route 221, kelp bed | Overworld item ball | Skrelp — §4.4 coastal |
| `barbaracite` | Mega Barbaracle · Rock/Fighting · Tough Claws | 600 | Route 218, tide rocks | Hidden item | Binacle — §4.4 coastal |
| `crabominite` | Mega Crabominable · Fighting/Ice · Iron Fist | 578 | Route 219, shingle beach | Overworld item ball | Crabrawler — §4.4 coastal |
| `scolipite` | Mega Scolipede · Bug/Poison · Shell Armor | 585 | Great Marsh, observation deck | **Prize** — Safari warden | Venipede — Eterna Forest 10% |
| `drampanite` | Mega Drampa · Normal/Dragon · Berserk | 585 | Route 210 north, mountainside | Overworld item ball | Drampa — **needs a §4 slot** |
| `falinksite` | Mega Falinks · Fighting · Defiant | 570 | Iron Island, Riley's escort route | **Gift — Riley**, alongside the Riolu Egg | Falinks — **needs a §4 slot** |

#### Tier 4 — `badge:mine` / STRENGTH, cap 78 — 19 stones

| Stone | Mega (types / ability) | BST | Where | How | Base line — earliest access |
|---|---|---|---|---|---|
| `steelixite` | Mega Steelix · Steel/Ground · Sand Force | 610 | Canalave Gym | **Gift — Byron**, on the Mine Badge | Onix — Oreburgh Mine (pre-badge-1) — **power-gated, §6.1** |
| `swampertite` | Mega Swampert · Water/Ground · Swift Swim | 635 | Lake Valor, cavern | Overworld item ball | Mudkip — §4.2 Great Marsh (T3) |
| `sceptilite` | Mega Sceptile · Grass/Dragon · Lightning Rod | 630 | Route 211, canopy grove | Overworld item ball | Treecko — §4.2 Eterna Forest (T0) — power-gated |
| `feraligite` ‡ | Mega Feraligatr · Water/Dragon · Dragonize *(inert)* | 630 | Lake Verity, spring floor | Overworld item ball | Totodile — §4.2 Great Marsh (T3) |
| `meganiumite` ‡ | Mega Meganium · Grass/Fairy · Mega Sol *(inert)* | 625 | Route 211, flowering grove | Hidden item | Chikorita — §4.2 Eterna Forest (T0) — power-gated |
| `excadrite` ‡ | Mega Excadrill · Ground/Steel · Piercing Drill | 608 | Mt. Coronet north, drill seam | Overworld item ball | Drilbur — §4.4 Mt. Coronet south / Rt 207 — power-gated |
| `eelektrossite` ‡ | Mega Eelektross · Electric · Eelevate *(inert)* | 615 | Lake Valor, flooded chamber | Hidden item | Tynamo — **needs a §4 slot** |
| `clefablite` | Mega Clefable · Fairy/Flying · Magic Bounce | 583 | Mt. Coronet north, moonlit shelf | Overworld item ball, **night only** | Clefairy — Mt. Coronet (vanilla, T0) — power-gated |
| `skarmorite` ‡ | Mega Skarmory · Steel/Flying · Stalwart | 565 | Mt. Coronet north, cliff nest | Overworld item ball | Skarmory — **needs a §4 slot**; §5.3 bans it early |
| `abomasite` | Mega Abomasnow · Grass/Ice · Snow Warning | 594 | Route 216, treeline | Overworld item ball | Snover — Routes 216/217 |
| `glalitite` | Mega Glalie · Ice · Refrigerate | 580 | Route 217, blizzard drift | Hidden item | Snorunt — Routes 216/217 |
| `scraftinite` | Mega Scrafty · Dark/Fighting · Intimidate | 588 | Route 211 east, ruin wall | Overworld item ball | Scraggy — §4.4 Routes 210/214/215 |
| `victreebelite` | Mega Victreebel · Grass/Poison · Innards Out | 590 | Great Marsh, deep blind *(flag-gated)* | Safari prize | Bellsprout — **needs a §4 slot** |
| `pyroarite` ‡ | Mega Pyroar · Fire/Normal · Fire Mane *(inert)* | 607 | Route 211 east, sun ridge | Overworld item ball | Litleo — **needs a §4 slot** |
| `golurkite` ‡ | Mega Golurk · Ground/Ghost · Unseen Fist | 583 | **Solaceon Ruins**, sealed chamber *(flag-gated)* | Overworld item ball | Golett — **needs a §4 slot** (Solaceon Ruins) |
| `tatsugirinite` | Mega Tatsugiri (Curly · Droopy · Stretchy) · Dragon/Water · **Storm Drain** | 575 | Lake Valor shallows | Hidden item | Tatsugiri — **needs a §4 slot** |
| `beedrillite` | Mega Beedrill · Bug/Poison · Adaptability | **495** | Eterna Forest, hive *(flag-gated)* | Overworld item ball | Weedle — **needs a §4 slot** |
| `slowbronite` | Mega Slowbro · Water/Psychic · Shell Armor | 590 | Lake Verity shore | Overworld item ball | Slowpoke — **needs a §4 slot** |
| `banettite` | Mega Banette · Ghost · **Prankster** | 555 | Old Chateau, dining room *(flag-gated)* | Overworld item ball | Shuppet — §4.4 Ghost biome, Old Chateau (T1) — **ability-gated, R3** |

> **`tatsugirinite` is one stone serving three rows**, and it was the only one of the nine
> owner-decided forms inside capped content — so it is the only one where the decision could have
> mattered for balance. **It is decided: `storm-drain`** (`data/mega_ability_overrides.json`), which
> is base Tatsugiri's own hidden ability, so nothing new enters the game at a capped checkpoint;
> Dragon's Maw and Adaptability were both rejected as too strong here. 575 at **cap 78** is
> conservative either way.
>
> **Four T4 stones ship an inert ability** (`feraligite`, `meganiumite`, `eelektrossite`,
> `pyroarite`) per ruling G. They are the *weakest* 607–630 stones in the game, not the
> strongest, until their hooks are written (§1.5).

#### Tier 5 — `badge:icicle` / CLIMB, cap 90 — 26 stones · *the widest tier*

| Stone | Mega (types / ability) | BST | Where | How | Base line / gate reason |
|---|---|---|---|---|---|
| `froslassite` | Mega Froslass · Ice/Ghost · Snow Warning | 580 | Snowpoint Gym | **Gift — Candice**, on the Icicle Badge | Snorunt (T4) |
| `alakazite` | Mega Alakazam · Psychic · Trace | 600 | Galactic HQ, Veilstone — the lab | Overworld item ball | **Abra is a Route 203 10% slot — power-gated from T0 to T5 (§6.1)** |
| `gardevoirite` | Mega Gardevoir · Psychic/Fairy · Pixilate | 618 | Sendoff Spring | Overworld item ball | **Ralts is a Route 203 5% slot — power-gated (§6.1)** |
| `galladite` | Mega Gallade · Psychic/Fighting · Inner Focus | 618 | Route 222 | Overworld item ball | Same Ralts line |
| `aerodactylite` | Mega Aerodactyl · Rock/Flying · Tough Claws | 615 | Mt. Coronet summit | Overworld item ball | **Old Amber is an Underground dig from T1 — power-gated (§6.1)** |
| `heracronite` ‡ | Mega Heracross · Bug/Fighting · **Skill Link** | 600 | Route 222, honey grove | Overworld item ball | **Heracross is a honey-tree mon from Route 205 — ability-gated (§6.3)** |
| `scizorite` | Mega Scizor · Bug/Steel · **Technician** | 600 | Sunyshore City | **Gift — Jasmine**, replacing the `game-design.md` §3.6 TM | Scyther — §5.3 late placement |
| `pinsirite` | Mega Pinsir · Bug/Flying · **Aerilate** | 600 | Route 222, honey grove | Hidden item | Pinsir — §5.3 late placement |
| `mawilite` | Mega Mawile · Steel/Fairy · **Huge Power** | **480** | Mt. Coronet summit, ore pocket | Hidden item | **R3: 480 BST, roughly 210 effective Atk (§6.3)** |
| `sablenite` | Mega Sableye · Dark/Ghost · **Magic Bounce** | **480** | **Distortion World** | Overworld item ball | Sableye — §4.4 Distortion World. R3. |
| `venusaurite` | Mega Venusaur · Grass/Poison · Thick Fat | 625 | Route 212 south, greenhouse | **Gift** — Rowan's aide, seed-stock programme | Bulbasaur — §4.2 Rt 212 south (T3) |
| `charizardite-x` | Mega Charizard X · Fire/Dragon · Tough Claws | 634 | Stark Mountain approach *(flag-gated)* | Overworld item ball | Charmander — §4.2 Fuego / Stark (T3) |
| `blastoisinite` | Mega Blastoise · Water · Mega Launcher | 630 | Sunyshore City, lighthouse cove | Overworld item ball | Squirtle — §4.2 Great Marsh / Rts 219–221 (T3) |
| `chesnaughtite` | Mega Chesnaught · Grass/Fighting · Bulletproof | 630 | Eterna Forest, deep wood *(flag-gated)* | **Gift** — Rowan's aide | Chespin — §4.2 Eterna Forest (T0) — power-gated |
| `delphoxite` | Mega Delphox · Fire/Psychic · Levitate | 634 | Fuego Ironworks *(flag-gated)* | **Gift** — Rowan's aide | Fennekin — §4.2 Fuego (T3) |
| `greninjite` | Mega Greninja · Water/Dark · **Protean** | 630 | Great Marsh *(flag-gated)* | **Gift** — Rowan's aide | Froakie — §4.2 Great Marsh (T3). R3. |
| `emboarite` | Mega Emboar · Fire/Fighting · Mold Breaker | 628 | Fuego Ironworks *(flag-gated)* | **Gift** — Rowan's aide | Tepig — §4.2 Fuego (T3) |
| `golisopite` | Mega Golisopod · Bug/Steel · Tough Claws | 630 | Route 223, reef shelf | Overworld item ball | Wimpod — §4.4 coastal (T3). Tough Claws removes Emergency Exit's drawback entirely. |
| `malamarite` | Mega Malamar · Dark/Psychic · **Contrary** | 582 | Distortion World | Hidden item | Inkay — **needs a §4 slot**. R3. |
| `hawluchanite` | Mega Hawlucha · Fighting/Flying · **No Guard** | 600 | Mt. Coronet summit, ledge | Overworld item ball | Hawlucha — **needs a §4 slot**. R3. |
| `pidgeotite` | Mega Pidgeot · Normal/Flying · **No Guard** | 579 | Route 222 | Hidden item | Pidgey — **needs a §4 slot**. R3 (No Guard plus Hurricane). |
| `raichunite-x` | Mega Raichu X · Electric · Electric Surge | 585 | Sunyshore City, solar panels | Overworld item ball | Pikachu — Trophy Garden (T3) |
| `absolite-z` | Mega Absol Z · Dark/Ghost · Sharpness | 565 | Lake Acuity | Overworld item ball | Absol (T2). R5 — strictly stronger than `absolite`. |
| `blazikenite` | Mega Blaziken · Fire/Fighting · **Speed Boost** | 630 | Stark Mountain approach *(flag-gated)* | **Gift** — Rowan's aide | Torchic — §4.2 Fuego (T3). R3. |
| `glimmoranite` | Mega Glimmora · Rock/Poison · Adaptability | 625 | Mt. Coronet summit, crystal vein | Overworld item ball | Glimmet — **needs a §4 slot** |
| `scovillainite` ‡ | Mega Scovillain · Grass/Fire · **Spicy Spray** | 586 | Route 212 south, farm plot | **Gift** — the Berry farmer | Capsakid — **needs a §4 slot**; §5.3 holds it late |

> **`starminite` is deliberately NOT in T5.** Huge Power on a 115-base-Speed special attacker's
> body is §6.3's problem, and ruling F makes the arithmetic worse, not better: even the
> *correct* Attack of 100 doubles to 200. **T7.** Its old `conf=uncertain` flag is retired —
> Huge Power is Champions-confirmed — but the tier stands on power alone.

#### Tier 6 — `badge:beacon`, cap 96 → 99 — 9 stones

A deliberately short tier: Victory Road and the League have no shops and no return trips. Five
of the nine are **700-BST pseudo-legendaries** whose base species `game-design.md` §4.4 already
reserves for Victory Road and Routes 224–230 — so R1 and R2 agree, and the player can *see* them
without realistically raising one under the caps before Cynthia. That is the intent: a visible
post-game promise.

| Stone | Mega (types / ability) | BST | Where | How | Base line |
|---|---|---|---|---|---|
| `raichunite-y` | Mega Raichu Y · Electric · **No Guard** | 585 | Sunyshore Gym | **Gift — Volkner**, on the Beacon Badge | Pikachu, Trophy Garden |
| `tyranitarite` | Mega Tyranitar · Rock/Dark · Sand Stream | **700** | Victory Road 1F | Overworld item ball | Larvitar — §4.4 Victory Road |
| `salamencite` | Mega Salamence · Dragon/Flying · Aerilate | **700** | Victory Road, map 245 *(optional loop)* | Overworld item ball | Bagon — §4.4 Rts 224–230 |
| `metagrossite` | Mega Metagross · Steel/Psychic · Tough Claws | **700** | Victory Road, map 247 *(optional loop)* | Overworld item ball | Beldum — §4.4 Rts 224–230 |
| `dragoninite` | Mega Dragonite · Dragon/Flying · Multiscale | **700** | Route 223, sea shelf | Underground-style find | Dratini — §5.3 late |
| `baxcalibrite` | Mega Baxcalibur · Dragon/Ice · Thermal Exchange | **700** | Victory Road, ice chamber | Hidden item | Frigibax — §4.4 **L45+ only** |
| `lucarionite-z` ‡ | Mega Lucario Z · Fighting/Steel · **Aura Guard** | 625 | Victory Road 1F | Overworld item ball | Riolu (T3). R5 after `lucarionite`. |
| `charizardite-y` | Mega Charizard Y · Fire/Flying · **Drought** | 634 | Victory Road, map 246 *(optional loop)* | Overworld item ball | Charmander (T3). R5 — Drought is strictly stronger than Tough Claws, so Y lands a tier after X. |
| `staraptite` | Mega Staraptor · Fighting/Flying · **Contrary** | 585 | Pokémon League plaza | **Gift — Barry**, after rival battle R7 | **Starly is a Route 201 20% slot — the hardest power-gate in the table (§6.1)** |

> `staraptite` is a 585 sitting in the 700 tier on purpose. Starly is the **first Pokémon most
> players catch**, and Contrary turns Close Combat — a move with a drawback — into a setup move
> with no drawback. Barry using it at R5 and R7 and then handing it over is the cleanest way to
> show the trick before you own it (§4.5).

#### Tier 7 — `flag:hall-of-fame`, uncapped (100) — 15 stones (16 rows)

| Stone | Mega (types / ability) | BST | Where | How | Gate reason |
|---|---|---|---|---|---|
| `garchompite` | Mega Garchomp · Dragon/Ground · Sand Force | **700** | Pokémon League, after the credits | **Gift — Cynthia** | §6.1 — Gible is a pre-Hearthome catch; the game's number-one hazard |
| `garchompite-z` | Mega Garchomp Z · Dragon · Levitate | **700** | Stark Mountain, inner chamber | Overworld item ball | Same line. Pure Dragon with **Levitate** is a strictly better defensive profile. R5 after `garchompite`. |
| `gengarite` ‡ | Mega Gengar · Ghost/Poison · **Shadow Tag** | 600 | Turnback Cave, final room | Overworld item ball | §6.3 — **the single worst ability to allow under a level cap** |
| `kangaskhanite` ‡ | Mega Kangaskhan · Normal · **Parental Bond** | 590 | Fight Area, Battle Park | BP purchase | §6.3 — every move hits twice |
| `starminite` | Mega Starmie · Water/Psychic · **Huge Power** | 620 | Resort Area, tide pool | Overworld item ball | §6.3 + ruling F — Atk **100**, not 140, and 100 still doubles to 200 |
| `mewtwonite-x` ‡ | Mega Mewtwo X · Psychic/Fighting · Steadfast | **780** | Turnback Cave, deepest room | Overworld item ball | 780 BST; the species is not in the Sinnoh story |
| `mewtwonite-y` | Mega Mewtwo Y · Psychic · Insomnia | **780** | Snowpoint Temple, lowest floor | Overworld item ball | Same. R5 separates them by location, not tier — both are already terminal. |
| *(none)* ‡ | **Mega Rayquaza** · Dragon/Flying · Delta Stream | **780** | — | **No stone.** `stone: null`, `requiresMove: "dragon-ascent"` (ruling B) | Dragon Ascent tutor at **Stark Mountain**, post-Hall-of-Fame. §8.2. |
| `latiasite` | Mega Latias · Dragon/Psychic · Levitate | **700** | Resort Area, villa | **Gift** — the villa owner | 700 BST, legendary |
| `latiosite` | Mega Latios · Dragon/Psychic · Levitate | **700** | Resort Area, villa | **Gift** — the villa owner | 700 BST, legendary |
| `diancite` | Mega Diancie · Rock/Fairy · Magic Bounce | **700** | Fight Area, Battle Park | BP purchase | Mythical |
| `heatranite` | Mega Heatran · Fire/Steel · **Earth Eater** | **700** | **Stark Mountain**, magma chamber | Overworld item ball | Heatran is Stark Mountain post-game in vanilla. Absent from Champions; **owner write-in** (§1.5) — Earth Eater turns the 4× Ground weakness into healing. |
| `darkranite` | Mega Darkrai · Dark · **Dark Aura** | **700** | Fullmoon / Newmoon Island | Overworld item ball | Mythical, event-gated. Absent from Champions; **owner-decided** (§1.5) — its Speed *drops* 125→85, so it is a bulky wallbreaker. |
| `magearnite` | Mega Magearna **and** Magearna (Original Colour) · Steel/Fairy · **Soul-Heart** | **700** | Fight Area, Battle Park | BP purchase | One stone, two rows (§1.3). Absent from Champions; **owner-decided by recommendation** (§1.5) — both colours mirror, per the Meowstic precedent. |
| `zeraorite` | Mega Zeraora · Electric · **Transistor** | **700** | Fight Area, Battle Park | BP purchase | Mythical. Absent from Champions; **owner-decided** (§1.5). Speed Boost was rejected on merit (§6.5). |
| `zygardite` | Mega Zygarde · Dragon/Ground · **Thick Fat** | **778** | Sendoff Spring, deep cell chamber *(flag-gated)* | Overworld item ball | **Built on Zygarde Complete** (§1.3/§1.4) — needs its own obtain path (§8.2). **The roster's one exception to base+100**, and the highest BST after the Mewtwos and Rayquaza. Thick Fat is **owner-decided by recommendation**. |

> **Eight of the nine owner-decided forms are T7; only `tatsugirinite` is not.** That was the
> point of the retired R7 rule (§3.2) — park the undecided abilities where the hard cap is already
> gone — and it paid off: when the decisions landed, **eight of them could not affect a capped
> fight at all**, and the ninth was deliberately given the base form's own hidden ability.

### 3.5 Acquisition-method mix

Counts are **exact**, derived from the §3.4 tables, and sum to 92 stones with every stone
classified once. Mega Rayquaza is listed separately because it has no stone.

| Method | Count | Tiers | Notes |
|---|---|---|---|
| Overworld item ball | **48** | T1–T7 | The default. One (`clefablite`) is night-only. |
| Hidden item (Dowsing Machine) | **12** | T2–T6 | Rewards the Pokétch app the game already ships. |
| **Gift — gym leader** | **6** | T2–T7 | The §3.3 spine: Maylene, Wake, Byron, Candice, Volkner, Cynthia. |
| Gift — other NPC | **15** | T1–T7 | Cynthia (the Key Stone bundle), Riley, Jasmine, Barry, the café owner, the Windworks engineer, the Psychic outpost, the Berry farmer, the Resort villa owner (×2), and **6 from Rowan's aide's seed-stock programme** — the NPC `game-design.md` §4.2 already invents to hand out cross-gen starters. The starter and its stone arrive together. |
| Shop (money) | **1** | T2 | Veilstone Dept. Store 4F — `audinite`, 6,000. |
| **Veilstone Game Corner** | **1** | T2 | `medichamite`, 8,000 coins. The one grind-purchasable stone; Pure Power justifies the price. |
| Safari / Great Marsh prize | **2** | T3, T4 | |
| Underground-style find | **2** | T3, T6 | Uses Sinnoh's own signature system. |
| BP purchase (Battle Park) | **5** | T7 | Mythicals plus Diancie. |
| **Subtotal — stones** | **92** | | |
| **No stone** | **1 row** | T7 | Mega Rayquaza — move-gated (ruling B). |

### 3.6 Base species that still need a `game-design.md` §4 placement

These 20 base lines are assumed above to have an encounter slot at or before the stated tier.
**Each is a dependency on §4, not a decision made here.** If a slot is refused, the stone moves
to T7 rather than shipping unusable.

| Base line | Needed by tier | Suggested biome (consistent with §4.4) |
|---|---|---|
| Audino | T2 | Routes 209/215 pastoral |
| Mareep | T3 | Valley Windworks pasture / Route 205 |
| Electrike | T3 | Route 212 north |
| Swablu | T3 | Route 210 north / Route 211 |
| Drampa | T3 | Route 210 north, mountainside |
| Falinks | T3 | Iron Island |
| Crabrawler | T3 | Routes 218–221 coastal *(§4.4 already reserves this biome for Alola coastal picks)* |
| Tynamo | T4 | Valley Windworks / Sunyshore |
| Skarmory | T4 | Mt. Coronet north cliffs *(§5.3 bans it early — T4 satisfies that)* |
| Bellsprout | T4 | Great Marsh / Route 212 |
| Litleo | T4 | Route 211 east |
| Golett | T4 | **Solaceon Ruins** — an ancient automaton in the Unown ruins is the best flavour fit in the list |
| Tatsugiri | T4 | Lake Valor shallows |
| Weedle | T4 | Eterna Forest |
| Slowpoke | T4 | Lake Verity / Great Marsh |
| Inkay | T5 | Distortion World / Route 213 |
| Hawlucha | T5 | Mt. Coronet summit / Route 211 |
| Pidgey | T5 | Routes 209/210 |
| Glimmet | T5 | Mt. Coronet summit / Stark Mountain |
| Capsakid | T5 | Route 212 south farmland *(§5.3 holds it late — satisfied)* |

> None is a §5.2 risk: **every one is needed at T2 or later, and §5.2 only governs the window
> before the Relic Badge.**

---

## 4. Question 3 — do gym leaders and the Elite Four Mega Evolve?

**Yes, and this is the reason Megas stay interesting under a level cap.** If only the player
Mega Evolves, the cap stops being a difficulty tool the moment the Key Stone lands: every
remaining boss faces a level-matched team with a 100-BST head start and no way to answer it.
Boss Megas restore the symmetry the cap depends on.

### 4.1 The boss Mega rule

Source of record for every boss party in this section is **`data/rom/bosses.json`** — 31 bosses,
six Pokémon each, documented in `rosters-gyms14.md`, `rosters-gyms58.md`, `rosters-e4.md` and
`rosters-story.md`. **24 of the 31 Mega Evolve.**

| # | Rule |
|---|---|
| **B1** | A boss Mega Evolves **exactly one** Pokémon — the same `rule: "one-per-battle"` the player obeys (contract §11.1). |
| **B2** | **Party, species and levels come from `data/rom/bosses.json`**, which is generated by the rebalance and overrides the ROM record (contract §7.1). *(Superseded: the previous revision took parties from the ROM tables and permitted level permutations inside them. Parties are now authored at six members and the permutation lever no longer exists.)* |
| **B3** | **The ace is the party's highest level and equals the cap in force.** This document changes no cap and no level. |
| **B4** | **The Mega'd member is either the ace, or is sent immediately before it.** In the gym and Elite Four rosters that is **slot 5 of 6, one level below the ace**; in the rival and Galactic rosters the ace leads and the Mega is sent **second**. *(Superseded: the previous revision's "used exactly once: Volkner" exception is now the general shape.)* |
| **B5** | **Species substitution is no longer a special case** — the rebalance authored every party from scratch. It survives as a design note on exactly one boss: **Bertha's vanilla party contained no Mega-capable member**, which is why Excadrill is on her team at all (§4.3). |
| **B6** | The boss Megas **on the turn its holder is sent out**, so the player always sees it happen and can respond. Never mid-Pokémon, never as a surprise on a low-HP turn. |
| **B7** | A boss's Mega'd Pokémon **holds its Mega Stone, so it loses its ROM-assigned held item.** A real and automatic difficulty offset — §4.7. |
| **B8** | **No boss Mega Evolves before gym 3. Fantina is the first, and she Megas in the fight that *earns* the Relic Badge.** Roark and Gardenia never Mega, in any circumstance; nor do Barry R1/R2, Mars at Valley Windworks or Jupiter at the Eterna Building. *(**Corrected**: the previous revision read B8 as "not until `badge:relic` is *set*", which excluded Fantina. The owner's decision — gym leaders Mega Evolve **from gym 3 onward**, and the Mega Ring is granted immediately after Fantina — governs. `data/rom/bosses.json` gives Fantina `megaForm: "gengar-mega"`, and `DATA_CONTRACT.md` §7.1/§12.5 both say Fantina is the first boss with a `megaForm`.)* |
| **B9** | **No boss may be assigned a Mega whose ability is ‡ engine-hook-pending unless the hook is written first** (§1.5). **Satisfied as of 2026-09-23b:** the last two exposures — **Fantina / `shadow-tag`** and **Bertha / `piercing-drill`** — had their hooks landed mid-pass (`onSwitchAttempt`, `onProtectCheck`), so **all 24 boss Megas run tier-1 abilities**. The named fallbacks below stay on the page in case a hook regresses. |
| **B10** | **Every boss's ace is a Gen 4 species, dex 387–493** (contract §7.1, asserted by the build). **The Mega goes on the ace only when the ace itself has a Mega form** — Maylene/Lucario, Candice/Froslass, Lucian/Gallade, Cynthia/Garchomp. Otherwise it rides a **non-ace teammate one level below the ace**, and *the ace stays the ace*. **A Mega must never be promoted above the ace**: that is how the previous revision broke the Gen 4 rule on Wake and Byron. |

### 4.2 Gym leaders

**Eight leaders, six Mega Evolutions.** Caps are `data/level_caps.json` (`level-curve.md` §1.1);
parties are `data/rom/bosses.json`.

| Badge | Leader | Cap | Ace (Gen 4) | **Mega** | On the ace? | BST | Ability | Tier | Stone awarded |
|---|---|---|---|---|---|---|---|---|---|
| Coal | Roark | **18** | Cranidos 18 | **no** | — | — | — | — | `aerodactylite` |
| Forest | Gardenia | **27** | Roserade 27 | **no** | — | — | — | — | `victreebelite` |
| Relic | **Fantina** | **36** | Mismagius 36 | **Mega Gengar** *(Gengar 35, slot 5)* | non-ace | 600 | `shadow-tag` | **1** *(hook landed mid-pass — §1.5)* | `gengarite` |
| Cobble | **Maylene** | **45** | **Lucario 45** | **Mega Lucario** | **ACE** | 625 | `adaptability` | 1 | `lucarionite` |
| Fen | **Crasher Wake** | **54** | **Floatzel 54** | **Mega Gyarados** *(Gyarados 53, slot 5)* | non-ace | 640 | `mold-breaker` | 1 | `gyaradosite` |
| Mine | **Byron** | **66** | **Bastiodon 66** | **Mega Steelix** *(Steelix 65, slot 5)* | non-ace | 610 | `sand-force` | 1 | `steelixite` |
| Icicle | **Candice** | **78** | **Froslass 78** | **Mega Froslass** | **ACE** | 580 | `snow-warning` | 1 | `froslassite` |
| Beacon | **Volkner** | **90** | Electivire 90 | **Mega Raichu Y** *(Raichu 89, slot 5)* | non-ace | 585 | `no-guard` | 1 | `raichunite-y` **and** `raichunite-x` |

**Four corrections to the previous revision — the first three are the same mistake, made three times: promoting the Mega above the ace, or refusing to let a boss Mega at all:**

1. **Fantina Megas, and she is the debut.** Not Maylene. She runs **Mega Gengar in slot 5 at
   level 35, one below her Mismagius ace** — so the player *watches* a Mega Evolution in the fight
   that earns the Relic Badge, and is handed the Ring immediately afterwards. That ordering is the
   owner's, and it is better design than the old B8 reading: the mechanic is introduced as a threat
   before it is given as a tool. **Maylene is now the first Mega-*vs*-Mega fight**, which is what
   the old text was really describing.
2. **Wake's ace is FLOATZEL and Byron's is BASTIODON.** The previous revision promoted Gyarados
   to 37 and Steelix to 38 "so the Mega'd member is the highest-level member" — which made a
   **non-Gen-4 species the ace** and broke contract §7.1's dex 387–493 rule outright. Both Megas
   ride a **non-ace teammate one level under the ace** (Gyarados 53 under Floatzel 54; Steelix 65
   under Bastiodon 66). No permutation, no cap change, rule B10 satisfied.
3. **Volkner needs no special case.** The old B4 exception ("Raichu sent 4th, immediately before
   Electivire") is just B4's normal shape on a six-member party: **Raichu 89 in slot 5, Electivire
   90 closing.**
4. **Mega Raichu Y cannot use Zap Cannon.** The old justification was "No Guard makes Zap Cannon a
   guaranteed 120-BP paralysis". `data/learnsets.json` gives Raichu **no Zap Cannon in any list** —
   level-up, machine, egg or tutor (`rosters-gyms58.md` §8). No Guard's real payoff is
   perfect-accuracy **Thunder** and **Focus Blast**, which is still a genuine threat at a
   level-matched 90 and still the right pick; the claim was simply false.

**Per-leader reasoning** (unchanged where the fight is unchanged):

| Leader | Why this Mega |
|---|---|
| **Fantina** | The debut, and the one boss Mega the player cannot answer. Mega Gengar is 600 BST of 170 SpA / 130 Speed behind a Mismagius closer. **Shadow Tag is the problem** — see the B9 note below. |
| **Maylene** | Adaptability Close Combat at exactly your level is the hardest single hit in the first half of the game, and it is the first fight where the player has a Mega of their own. Her ace needs no edit: Lucario *is* the Mega. |
| **Crasher Wake** | Mold Breaker turns off the player's Levitate / Water Absorb / Filter / Sturdy answers — a *tactical* threat, not just a stat one — and it arrives on a **teammate**, so Floatzel still closes. |
| **Byron** | The purest wall in the game at the gym designed around walls: 230 base Defense on a Steel/Ground body, in front of a Bastiodon ace. Also turns §6.1's *Onix is a pre-badge-1 catch* hazard into the fight's reward (§3.3). |
| **Candice** | 580 is the lowest boss Mega in the game and still the scariest of the three Ice options: **Snow Warning is permanent weather** and her whole team is Ice. Chosen on synergy, not BST. |
| **Volkner** | Electivire is Volkner's identity and stays the closer; the Mega sits in the slot before it. Perfect-accuracy Thunder off 160 SpA at cap 90. |

> **Fantina's Shadow Tag — the B9 exposure, now closed on the engine side and still live as a
> balance question.** `shadow-tag` was **tier 3 / `hook: none`**; it is now **tier 1 /
> `onSwitchAttempt`** (landed during this pass), so outcome (a) below happened and B9 is satisfied.
> **§6.3 still calls Shadow Tag the single worst ability to allow under a hard level cap** — and
> Fantina brings it at **gym 3, against a player with no Mega of their own**. The options, kept in
> order, because this is now a *design* call and not a schedule one:
> **(a)** ship it as implemented — the hook exists and the player inherits `gengarite` immediately
> afterwards; **(b)** run her Mega Gengar on **Cursed Body**, its pre-Mega ability, which is what
> the party row already carries, and reserve Shadow Tag for the player's own Gengarite;
> **(c)** never leave it inert on a boss — that is the silent difficulty regression B9 exists to
> stop. Both (a) and (b) keep the owner's requirement that Fantina Mega Evolves Gengar and awards
> `gengarite`. **Recommend (b) for the gym-3 fight specifically**: removing switching from a player
> who cannot answer the Mega at all is the one place the ability has no counterplay.

**All six gym Megas now use tier-1 abilities**, so no gym leader blocks on engine work.

**Alternatives held in reserve** (roster-legal swaps that keep the leader's type): Candice →
Mega Abomasnow (594, also Snow Warning). Maylene → Mega Lucario Z (625, Aura Guard) —
**blocked by B9**: `aura-guard` is tier 3.

### 4.3 Elite Four and Champion

| # | Member | Cap | Ace (Gen 4) | **Mega** | On the ace? | BST | Ability | Tier | Stone |
|---|---|---|---|---|---|---|---|---|---|
| E1 | **Aaron** | **96** | Drapion 96 | **Mega Scizor** *(Scizor 95, slot 5)* | non-ace | 600 | `technician` | 1 | `scizorite` |
| E2 | **Bertha** | **97** | **Rhyperior 97** | **Mega Excadrill** *(Excadrill 96, slot 5)* | non-ace | 608 | `piercing-drill` | **1** *(hook landed mid-pass — §1.5)* | `excadrite` |
| E3 | **Flint** | **98** | Magmortar 98 | **Mega Houndoom** *(Houndoom 97, slot 5)* | non-ace | 600 | `solar-power` | 1 | `houndoominite` |
| E4 | **Lucian** | **99** | **Gallade 99** | **Mega Gallade** | **ACE** | 618 | `inner-focus` | 1 | `galladite` |
| CH | **Cynthia** | **100** | **Garchomp 100** | **Mega Garchomp** | **ACE** | **700** | `sand-force` | 1 | `garchompite` |

**Corrections to the previous revision:**

1. **Bertha's ace is RHYPERIOR, not her Mega.** The old text substituted Excadrill *and then
   permuted it to level 55 above Rhyperior 52*, which made a Gen 5 species the ace of a Gen 4-ace
   fight. The shipped fight keeps **Rhyperior 97** as the ace and puts **Mega Excadrill at 96 in
   slot 5** — Ground/Steel, consistent with her Ground identity, exactly as rule B10 requires.
   Excadrill is on the team because **Bertha's vanilla party contained no Mega-capable member** —
   still the only boss in the game where that is true (B5).
2. **Every cap is +43 to +38 above the number the old table used** (96/97/98/99/100 against
   53/55/57/59/62). No argument in this section depends on the absolute level, because both sides
   are level-matched by construction.
3. **Aaron's Mega Scizor stands.** Mega Heracross needs `skill-link`, which is **tier 3 /
   `hook: none`** — B9 blocks it. Mega Scizor is the same 600 BST, the same Bug specialism, and
   Technician is implemented. **Aaron keeps a non-Mega Heracross on the team**, so reverting the
   moment the Skill Link hook lands is a stone swap and nothing else.
4. **Flint's sun is authored in the data**: Rapidash 95 leads with **Sunny Day + Heat Rock** (8
   turns), which is what makes Solar Power worth having and turns "kill the Rapidash" into the
   fight's first real decision.

**Fair-play check: the Elite Four shows the player nothing they could not already own.**
`scizorite` is T5, `excadrite` T4, `houndoominite` **T2**, `galladite` T5 — all four are
reachable before the League. Only Cynthia's `garchompite` is withheld, and it is handed over
immediately afterwards (§3.3).

**Engine-hook exposure, stated once: it is now ZERO.** Of the **24** boss Megas in this document,
the last two that depended on an unwritten hook — **Fantina's Mega Gengar (`shadow-tag`, gym 3)**
and **Bertha's Mega Excadrill (`piercing-drill`, E2)** — had their hooks landed during this pass
(§1.5). **All 24 run tier-1 abilities.** The named fallbacks stay documented in case of a
regression: Cursed Body for Fantina (§4.2), and **Mega Steelix** (`sand-force`, Steel/Ground, same
shape) for Bertha — re-using Byron's Mega is a flavour cost but keeps Bertha a Mega fight.

### 4.4 Team Galactic — never

> ### WITHDRAWN: "no Team Galactic boss ever Mega Evolves."
>
> The previous revision ruled Galactic out entirely on thematic grounds. **`data/rom/bosses.json`
> gives seven of the nine Galactic fights a Mega, plus Charon in the post-game.** The data is the
> owner's decision and it wins. The reason it changed is structural, not narrative: Galactic holds
> the difficulty line *between* gyms, at caps 66–90, and a boss side with no Mega against a player
> who has several is the fight that goes soft. `rosters-story.md` is the source of record.

| Fight | Cap | Gen 4 ace | Mega rides | Form | BST | Ability | Tier |
|---|---|---|---|---|---|---|---|
| Mars — Valley Windworks | 27 | Purugly 27 | — | **none** — pre-Ring (B8) | — | — | — |
| Jupiter — Eterna Building | 36 | Skuntank 36 | — | **none** — pre-Ring (B8) | — | — | — |
| **Cyrus — Celestic Town** | 66 | Honchkrow 66 | Houndoom 64 | `houndoom-mega` | 600 | `solar-power` | 1 |
| **Saturn — Lake Valor** | 78 | Toxicroak 78 | Alakazam 76 | `alakazam-mega` | 600 | `trace` | 1 |
| **Mars — Lake Verity** | 78 | Purugly 78 | Absol 76 | `absol-mega` | 565 | `magic-bounce` | 1 |
| **Saturn — Galactic HQ** | 90 | Toxicroak 90 | Alakazam 88 | `alakazam-mega` | 600 | `trace` | 1 |
| **Cyrus — Galactic HQ** | 90 | Weavile 90 | Gyarados 88 | `gyarados-mega` | 640 | `mold-breaker` | 1 |
| Mars — Spear Pillar *(double)* | 90 | Purugly 90 | — | **none** — see below | — | — | — |
| **Jupiter — Spear Pillar** *(double)* | 90 | Skuntank 90 | Dragalge 88 | `dragalge-mega` | 594 | `regenerator` | 1 |
| **Cyrus — Distortion World** | 90 | Giratina 90 | Gyarados 88 | `gyarados-mega` | 640 | `mold-breaker` | 1 |
| **Charon — Stark Mountain** *(post-game)* | 100 | Porygon-Z 100 | Metagross 98 | `metagross-mega` | 700 | `tough-claws` | 1 |

**What survives from the withdrawn ruling, and what does not:**

| Claim | Status |
|---|---|
| **Mars and Jupiter's first fights Mega nothing** | **Holds** — both are pre-`badge:relic` (B8), and the reason is the unlock gate, not characterisation. |
| **Only one of the Spear Pillar pair carries a stone** | **Holds, and it is the contract's rule, not a theme** — a double battle is one *side*, so `doublePartner` pairs Mars and Jupiter and **Jupiter carries the side's single Mega** (B1, contract §7.1). Mars had her Mega moment at Lake Verity. |
| **Cyrus's Distortion World fight has no headroom for a Mega** | **Void** — that was an argument about the *vanilla* +2 margin at ace Weavile 48 / cap 50. His Distortion World ace is now **Giratina 90 at cap 90**, and the Mega rides Gyarados 88. |
| **"A world without spirit" means Galactic cannot Mega Evolve** | **Withdrawn.** Keep the characterisation in dialogue if it earns its place, but **no mechanic, test or tutorial may depend on it.** |

**Every Galactic Mega is tier 1**, so none of them blocks on engine work (B9), and **every one
rides a non-ace teammate** — none of the Gen 4 aces Galactic fields (Purugly, Skuntank,
Honchkrow, Toxicroak, Weavile, Giratina, Porygon-Z) has a Mega form (B10).

### 4.5 Rival — Barry

| # | Location | Cap | Gen 4 ace | **Mega** | Level | Note |
|---|---|---|---|---|---|---|
| R1 | Route 201 | 18 | Monferno 18 | **no** | — | Pre-Ring (B8) |
| R2 | Route 203 | 18 | Monferno 18 | **no** | — | Pre-Ring (B8) |
| R3 | Route 209 | **45** | Infernape 45 | **Mega Staraptor** | 43 | **First rival Mega** — the Ring lands in Hearthome one route earlier. |
| R4 | Pastoria | **54** | Infernape 54 | **Mega Staraptor** | 52 | |
| R5 | Canalave | **66** | Infernape 66 | **Mega Staraptor** | 64 | |
| R6 | Spear Pillar | **90** | Infernape 90 | **Mega Staraptor (ally)** | 88 | He fights **for** you; the side's one Mega is his. |
| R7 | Pokémon League | **96** | Infernape 96 | **Mega Staraptor** | 94 | Then hands you the `staraptite` afterwards (§3.4 T6). |

**Corrected: Barry's first Mega is R3, not R5.** The previous revision claimed his R3 and R4
parties held *no Mega-capable member* and that the constraint therefore "enforced itself". The
rebalanced parties put **Staraptor in slot 2 of every Barry team from R3 onward**, holding
`staraptite`, so he Megas in **five** fights — R3, R4, R5, R6 (as your ally) and R7. `contrary` is
tier 1.

**The old "+1 headroom at R4, the tightest margin in the game" worry is void.** Headroom is
`level-curve.md` §1.3's table now, and **every Barry ace sits exactly at the cap in force** (18,
18, 45, 54, 66, 90, 96) — level-matched by construction, like every other boss.

> **Barry's Infernape can never Mega Evolve, and neither can your starter** — the Sinnoh starter
> lines are absent from the roster (§1.6). The rival's counter-pick identity is untouched by this
> system; his *bird* is what changes. **Contrary + Close Combat** is exactly Barry's character.

### 4.6 Cap re-verification

> ### SUPERSEDED AND RE-RUN
> The previous revision's table reasoned against the **vanilla** ladder —
> 14 / 22 / 26 / 32 / 37 / 41 / 44 / 50 / 53–59 / 62 — and against `game-design.md` §2.6. **That
> table no longer exists.** The curve is
> **18 / 27 / 36 / 45 / 54 / 66 / 78 / 90 / 96 / 97 / 98 / 99 / 100**, derived in
> **`docs/research/level-curve.md` §1.1** and shipped in `data/level_caps.json` (15 rows).
> `level-curve.md` is authoritative for every cap number in this document; where any older cap
> number survives in this file, it is a bug — report it.
>
> Two further consequences of that document, recorded here so this section cannot mislead again:
> **EXP multipliers are PER-SEGMENT** (`expMultiplierMode: "per-segment"`, top-level
> `expMultiplier` is permanently `null` — `DATA_CONTRACT.md` §8), not the flat ×2.5 the old text
> assumed; and **cap = the next checkpoint boss's ace level**, which is why every ace below is
> exactly at its cap.

**Level verification is `level-curve.md`'s job, not this document's.** Mega Evolution changes no
level, so §1.3's headroom table (no mandatory fight sits above the cap in force) holds line for
line — exactly what contract §11.3 asserts. Nothing here edits a cap, an ace level or a party's
highest level (B3).

The *difficulty* check is the different table: for every boss that Megas, can the player Mega back
at that moment?

| Boss | Cap | Boss's Mega | BST | Player's tier | Stones reachable | Player's best available BST | Symmetric? |
|---|---|---|---|---|---|---|---|
| **Fantina** | **36** | Mega Gengar | 600 | **T0** | **0** | — | **no — and deliberately.** The Ring arrives *after* this fight. The debut is a demonstration, not a duel. |
| **Maylene** | **45** | Mega Lucario | 625 | T1 | 2 usable (+3 dormant gym awards, §2.1) | 580 | **no — boss ahead by design**, the first Mega-vs-Mega fight |
| Crasher Wake | **54** | Mega Gyarados | 640 | T2 | 9 | 625 (`lucarionite`) | yes |
| Byron | **66** | Mega Steelix | 610 | T3 | 23 | 640 (`gyaradosite`) | yes — player ahead |
| Candice | **78** | Mega Froslass | 580 | T4 | 42 | 635 (`swampertite`) | yes — player ahead |
| Volkner | **90** | Mega Raichu Y | 585 | T5 | 68 | 634 | yes — player ahead |
| Aaron → Lucian | **96–99** | Scizor / Excadrill / Houndoom / Gallade | 600–618 | T6 | 77 | 640 realistic | yes |
| **Cynthia** | **100** | **Mega Garchomp** | **700** | T6 | 77 | 640 realistic | **no — boss ahead, deliberately** |

**Galactic and Barry need no row each.** All 12 of their Megas (§4.4, §4.5) sit between 565 and 700
at caps 45–100, with the player at **T1 or later in every case** — i.e. never without a stone of
their own. The only one worth naming is **Charon's Mega Metagross (700)**, and it is
post-Hall-of-Fame where the cap is gone.

**Three fights are deliberately asymmetric, and they are the three that should be: the debut
(Fantina — unanswerable, by one fight), the first mirror (Maylene) and the Champion.** Everywhere
in between the player is ahead, which is the correct shape for a game whose difficulty comes from
the cap rather than from the boss.

### 4.7 The held-item offset — the balance lever that comes free

A Mega Stone occupies the **held-item slot**. Under a hard level cap, where neither side can
out-level the other, the held item is a large fraction of a Pokémon's power budget.

| Consequence | Effect |
|---|---|
| **For the boss** | Every ROM boss ace carries a held item (Sitrus Berry on Roark's Cranidos, etc., per contract §7). A Mega'd ace **gives that up**. Rely on this instead of nerfing movesets — it is automatic, invisible and symmetric. |
| **For the player** | No Leftovers, no Life Orb, no Focus Sash, no berry on the Mega'd Pokémon. This is why a sub-580 Mega such as `floettite` (471) or `chimechite` (555) is an *honest* pick rather than a free one, and it is the single biggest reason the tier table can be as generous as it is from T3 onward. |
| **Rule** | Mega Stones are immune to Knock Off / Trick / Thief / Covet / Fling (canon). Do not implement a path that separates a Pokémon from its stone mid-battle. |
| **The one exception** | **Mega Rayquaza keeps its item slot** (ruling B — no stone). It is the only Mega exempt from this tax, which at 780 BST is a further reason it is T7-only (§8.2). |

---

## 5. Question 4 — Primal Reversion: in or out?

### 5.1 Recommendation — OUT (ruling A, and this document's independent recommendation)

> **OUT.** Primal Groudon and Primal Kyogre do not ship — not in the main game, not in the
> post-game, not behind a flag. **No Red Orb, no Blue Orb, no `-primal` form of any species.**

This matches the owner's ruling A and `DATA_CONTRACT.md` §11.5. The reasoning below is kept
because the build must be able to defend the exclusion, and because a future pass will be tempted
to re-add them for "roster completeness".

### 5.2 Reasoning

| # | Reason | Detail |
|---|---|---|
| 1 | **It is not Mega Evolution — it is a second gimmick.** | It triggers off the **Red/Blue Orb, not the Key Stone**; in canon it does not consume the one-Mega-per-side budget; and it needs its own path through `can_mega_evolve()`. The project's headline constraint is *Mega Evolution is the ONLY battle gimmick*. Every extra branch in that function is a place for the excluded mechanics (§7) to grow back — and ruling B has already spent the one legitimate extra branch on Mega Rayquaza's `stone == null`. |
| 2 | **Desolate Land and Primordial Sea are the worst possible abilities under a level cap.** | They do not weaken a type — they make Water moves and Fire moves **fail outright**. The player's entire edge in a capped game is type coverage and tactics; an ability that deletes a type from the battle removes the category the difficulty lives in. Against Flint, Primal Kyogre is not a fight. Against Crasher Wake, neither is Primal Groudon. |
| 3 | **770 BST with no held-item tax.** | Like Mega Rayquaza, an Orb is not a Mega Stone, so §4.7's automatic offset does not apply. 770 BST *and* Leftovers is outside anything else in the roster. |
| 4 | **Sinnoh has no story slot for them.** | There is no Groudon and no Kyogre in Sinnoh. Importing Hoenn's legendary arc puts it in direct competition with the Creation Trio — Dialga, Palkia, Giratina — which is what the Platinum story actually is. |

### 5.3 What ships instead

| Thing | Disposition |
|---|---|
| `primal-groudon`, `primal-kyogre` | **Absent from `data/megas.json`.** A build test asserts neither id appears (contract §11.5, §7.2 guard 6). |
| `red-orb`, `blue-orb` | **Not emitted to `data/items.json`.** Test-asserted (§7.2 guard 4). |
| `-primal` species forms | **Dropped at import** in `tools/build_species.py` (§7.2 guard 3). |
| Groudon / Kyogre as species | Unaffected — they remain ordinary species rows if the post-game ever wants them. Only the Primal *forms* are excluded. |
| The "big legendary Mega" fantasy | **Already served, three times over**, and all inside the Mega system: Mega Rayquaza 780, Mega Mewtwo X/Y 780, Mega Zygarde 778 (§3.4 T7). Nothing is missing from the roster's ceiling. |

### 5.4 The one legitimate argument for inclusion, and why it still loses

The strongest pro-Primal case is *roster completeness*: ORAS shipped 22 Mega-slot forms and this
game ships 20 of them. But **completeness is satisfied at the level of the mechanic, not the
form**: every ORAS *Mega* ships. Primal Reversion is a second system, and that is the whole
distinction. The count table in §1.2 says "20 of 22, minus 2 Primals" out loud so no later pass
mistakes the gap for an oversight.

---

## 6. Question 5 — the dangerous Megas, and how each is handled

Three failure classes. **The handling is late tier placement in every case; nothing is excluded
outright, and only three forms are pushed past the Hall of Fame for power reasons.**

### 6.1 Class A — the base species is available far too early in Sinnoh

The stone is the *only* gate on these, because the Pokémon is already in the player's box. The cap
cannot help: at matched level, +100 BST is +100 BST.

| Mega | BST | Base species — earliest catch | Natural tier by R2 | **Shipped tier** | Handling |
|---|---|---|---|---|---|
| **Mega Garchomp** | **700** | **Gible, Wayward Cave L17–20 — reachable with the Bicycle before Hearthome** | T6 | **T7** | **The game's number-one hazard.** `game-design.md` §5.1 already names vanilla's own Gible as the biggest early power spike and relies on the cap to contain it — a Mega breaks that containment, because the cap constrains level, not BST. Gated post-game and handed over by **Cynthia**, who used it on you (§3.3). |
| **Mega Garchomp Z** | **700** | Same | T6 | **T7** | Same line; pure Dragon with **Levitate** is a strictly better defensive profile. R5 puts it after `garchompite`. |
| **Mega Staraptor** | 585 | **Starly, Route 201 20% — the first Pokémon most players catch** | T3 | **T6** | **Contrary turns Close Combat from a drawback move into a free setup move.** The widest-reach hazard in the roster: essentially every save file has a Staraptor. Barry uses it in **every fight from R3 on** — five fights — and gifts the stone after (§4.5). |
| **Mega Alakazam** | 600 | Abra, Route 203 10% (pre-badge-1) | T3 | **T5** | 175 SpA at matched level. Pushed to Galactic HQ — **which is also where Saturn uses it on you** (§4.4), twice. |
| **Mega Gardevoir** | 618 | Ralts, Route 203 5% (pre-badge-1) | T4 | **T5** | Pixilate Hyper Voice. Pushed to Sendoff Spring. |
| **Mega Gallade** | 618 | Same Ralts line | T4 | **T5** | |
| **Mega Steelix** | 610 | **Onix, Oreburgh Mine 10% — pre-badge-1** | T3 | **T4** | Handled by *making it Byron's* (§3.3/§4.2) — on a **teammate**; his ace is Bastiodon. The player meets it as a wall before owning it. |
| **Mega Gengar** | 600 | Gastly, Eterna Forest 5% (pre-badge-2) | T3 | **T7** ⚠ | Not a stat problem — §6.3. **But `gengarite` is Fantina's locked gym-3 award (§3.3), which collides head-on with this T7 placement.** The stone the player is *given* at gym 3 is the one this table pushes past the Hall of Fame. Needs the §3.3 ruling. |
| **Mega Aerodactyl** | 615 | **Old Amber, Underground dig — from Eterna (T1)**, revived at Oreburgh | T4 | **T5** ⚠ | Easy to miss: the Underground makes a Gen-1 fossil an *early* item in Sinnoh specifically. **And `aerodactylite` is Roark's locked gym-1 award (§3.3)** — the earliest award in the game against a T5 placement. Needs the §3.3 ruling. |
| **Mega Clefable** | 583 | Clefairy, Mt. Coronet south (pre-Hearthome) | T3 | **T4** | Magic Bounce on a Fairy/Flying body. |
| **Mega Medicham** | 510 | Meditite, Mt. Coronet south (pre-Hearthome) | T1 | **T2** | Lowest BST on this list, but see §6.3 — Pure Power. Priced behind 8,000 Game Corner coins rather than tiered later, so the early game has one *grind for it* option. |
| **Mega Heracross** | 600 | **Heracross, honey trees — from Route 205** | T3 | **T5** | Skill Link; §6.3. **The `skill-link` hook has landed** (`onMultiHitCount`, §1.5), so the old "‡ inert, therefore less dangerous than its tier assumes" caveat is spent: T5 is now its real strength, and **Aaron's Mega Heracross revert is unblocked** — his team already carries the Heracross (§4.3). |
| **Mega Chimecho** | 555 | Chingling, Mt. Coronet south | T1 | **T1** | **Accepted at T1 on purpose** — 555, defensive typing, Levitate. The control case showing the tier system is not just *everything late*. |
| **Mega Lopunny** | 580 | Buneary, Eterna Forest 20% | T1 | **T1** | **Accepted at T1 on purpose.** 580 is the ceiling for the tier. Verified against R4: it is 2× on Maylene's Lucario only, a weaker answer than the Staraptor and Alakazam vanilla hands out before Veilstone anyway. |
| **Mega Sceptile / Meganium / Chesnaught** | 630 / 625 / 630 | Treecko, Chikorita, Chespin — §4.2 places all three in **Eterna Forest / Rt 205 north (T0)** | T4 | **T4 / T4 / T5** | The cross-gen starter programme puts three 625+ bases in the pre-badge-2 window. Their stones are the gate. |
| **Mega Absol / Absol Z** | 565 / 565 | Absol, Route 213 | T1 | **T2 / T5** | R5 splits the pair; Absol Z's Sharpness is the offensive upgrade. **Mars uses `absolite` at Lake Verity** (§4.4), one tier after the player can own it. |

### 6.2 Class B — 700 or above, regardless of where the base lives

Fifteen forms. Handling is uniform and needs no case-by-case argument: **T6 at the earliest, T7 by
default, and every one of their base species is already reserved for Victory Road, Routes 224–230
or the post-game by `game-design.md` §4.4 and §5.3.** R1 and R2 agree on all fifteen, which is the
system working as designed.

| Tier | Megas |
|---|---|
| **T6** (Victory Road / League) | Mega Tyranitar, Mega Salamence, Mega Metagross, Mega Dragonite, Mega Baxcalibur — all **700**, all raised from §4.4's Victory Road / Rts 224–230 pseudo-legendary pool. Under the caps none can realistically be raised to a Mega-capable stage before Cynthia. That is the point. |
| **T7** (post-Hall of Fame) | Mega Garchomp **700**, Mega Garchomp Z **700**, Mega Latias **700**, Mega Latios **700**, Mega Diancie **700**, Mega Heatran **700**, Mega Darkrai **700**, Mega Magearna **700** (×2 rows), Mega Zeraora **700**, **Mega Zygarde 778**, Mega Mewtwo X **780**, Mega Mewtwo Y **780**, **Mega Rayquaza 780** (no stone — §8.2). |

> **Corrected this revision:** Mega Zygarde is **778**, not 700 (§1.4), which makes it the
> third-highest BST in the game. Its T7 placement was already right; the number was wrong.

### 6.3 Class C — the ability is the problem, not the stat line

**This is the class that matters most under a hard level cap.** When neither side can out-level
the other, a stat swing is arithmetic the player can plan around; an ability that changes the
*rules* is not. R3 exists for exactly these, and it overrides BST.

| Mega | BST | Ability | Why it is dangerous *specifically under a level cap* | **Shipped tier** |
|---|---|---|---|---|
| **Mega Gengar** | 600 | **Shadow Tag** ‡ | **The worst one on the list**, and the argument now cuts both ways: it removes switching from a boss fight, turning a 6-vs-5 gauntlet into five sequential 1-vs-1s — and **Fantina brings it at gym 3** (§4.2), where it removes switching from *the player*, against an ability the engine cannot even run yet. Gastly is an Eterna Forest catch, so nothing else gates the player's copy. **Read §4.2's B9 note and §3.3's award conflict together: this is the single most tangled cell in the document.** | **T7** ⚠ |
| **Mega Kangaskhan** | 590 | **Parental Bond** ‡ | Every move hits twice. Roughly doubles output and makes every secondary effect and every multi-hit interaction fire twice, at a BST R2 alone would place at T3. | **T7** |
| **Mega Starmie** | 620 | **Huge Power** | Huge Power on a **115-base-Speed special attacker's body**. Ruling F fixes the Attack figure at **100 → 200 effective**, which is still the highest effective Attack in the roster bar Mega Mewtwo X. The `conf=uncertain` half of its old double gate is retired; the power half is untouched. | **T7** |
| **Mega Mawile** | **480** | **Huge Power** | **The proof that BST is the wrong metric.** 480 BST — 9 points above the weakest Mega in the game — and roughly 210 effective Attack. R2 would put it at T1; R3 puts it at T5. | **T5** |
| **Mega Medicham** | **510** | **Pure Power** | Same mechanism, one tier better base. Kept early **only** because it costs 8,000 Game Corner coins — a real gate that is not a story flag. | **T2 (priced)** |
| **Mega Blaziken** | 630 | **Speed Boost** | Snowballs. Against a level-matched 5- or 6-Pokémon boss team, free Speed every turn converts one favourable matchup into a whole-team sweep. | **T5** |
| **Mega Greninja** | 630 | **Protean** | Perfect STAB on every move; defeats the type-coverage planning the capped game is built on. | **T5** |
| **Mega Scizor** | 600 | **Technician** | Technician **Bullet Punch** is boosted priority. Priority is worth far more when Speed tiers are compressed by matched levels. Now also **Aaron's Mega** (§4.3). | **T5** |
| **Mega Heracross** | 600 | **Skill Link** ‡ | Pin Missile / Rock Blast / Bullet Seed always hit five times; also breaks Focus Sash and Sturdy. Base is a honey-tree mon from Route 205. | **T5** |
| **Mega Pinsir** | 600 | **Aerilate** | Normal moves become Flying with a damage bonus — Return / Frustration become 1.2× STAB Flying. | **T5** |
| **Mega Sableye** | **480** | **Magic Bounce** | Bounces every status a boss throws, on 480 BST of bulk, producing a stall shape the capped AI has no answer to. *(Correction: base Sableye's Prankster is **lost** on Mega Evolution — the ability is replaced. The stall shape is Magic Bounce plus recovery, not priority.)* | **T5** |
| **Mega Malamar** | 582 | **Contrary** | Superpower and Overheat become setup moves. | **T5** |
| **Mega Staraptor** | 585 | **Contrary** | Same, on the most widely-owned Pokémon in Sinnoh. §6.1. **Barry runs it in five fights from R3 on** (§4.5), so the player meets it long before owning the stone. | **T6** |
| **Mega Pidgeot** | 579 | **No Guard** | 100%-accurate **Hurricane** (110 BP + 30% confuse), and it ignores evasion entirely. | **T5** |
| **Mega Hawlucha** | 600 | **No Guard** | 100%-accurate High Jump Kick — a move whose entire balance is its miss penalty. | **T5** |
| **Mega Raichu Y** | 585 | **No Guard** | **Corrected:** Raichu has **no Zap Cannon** in `data/learnsets.json`, so the old "guaranteed 120-BP paralysis" claim is false. What No Guard actually buys is perfect-accuracy **Thunder** (and Focus Blast) off 160 SpA — still a real threat, one class lower. Reserved as Volkner's own (§4.2) and gifted at T6. | **T6** |
| **Mega Banette** | 555 | **Prankster** | Priority Will-O-Wisp / Destiny Bond / Trick Room. R3 moves it from T1 to T4. | **T4** |
| **Mega Froslass / Abomasnow** | 580 / 594 | **Snow Warning** | Permanent weather is a *battlefield* change, not a stat change, and it persists across the boss's whole team. Safe in the player's hands at T4/T5; genuinely threatening in Candice's (§4.2). | **T4 / T5** |
| **Mega Gyarados** | 640 | **Mold Breaker** | Turns off Levitate, Water Absorb, Filter, Sturdy — the exact abilities a capped player builds a wall around. Gifted by Wake, who uses it on you first. | **T3** |
| **Mega Lucario Z** | 625 | **Aura Guard** ‡ | Halving contact damage on a 625 body is a defensive Mega Lucario. Sits at T6 on R5 (after `lucarionite`) and is held out of the build until the hook exists. | **T6** |
| **Mega Excadrill** | 608 | **Piercing Drill** ‡ | Piercing Protect for 1/4 removes the capped player's most reliable stalling tool. Fine at T4 because it is *Bertha's* trick first (§4.3). | **T4** |
| **Mega Scovillain** | 586 | **Spicy Spray** ‡ | Burns any attacker that lands a damaging move — a passive Attack halving the AI cannot play around. | **T5** |

> **Summary of the exclusion question.** Nothing is excluded from the game for being too strong.
> **Three forms are pushed past the Hall of Fame on power grounds alone** — Mega Gengar (Shadow
> Tag), Mega Kangaskhan (Parental Bond), Mega Starmie (Huge Power) — joining the fifteen Class-B
> forms that were always going to be post-game. The only things genuinely **excluded** are Primal
> Groudon and Primal Kyogre (§5), and that is a mechanic decision, not a power one.

### 6.4 Class D — the four Megas that *were* under-powered, and the ruling-G question that replaced it

From ruling G: four forms were to ship with a named but **inert** ability (§1.5).

> ### ⚠ Superseded by data, and the owner has to rule on it.
> `data/abilities.json` now gives **all four a tier-1 hook** — `mega-sol` `onWeatherView`,
> `dragonize` `onModifyMoveType`, `eelevate` `onTypeImmunity`, `fire-mane` `onDamageCalc`. Ruling G
> says these four have **no published mechanic and must not be guessed**, so either the
> implementations are sourced from something neither this document nor `mega-abilities.md` §2 has
> seen, or ruling G has been broken. **Until that is answered, treat the table below as the
> *intended* balance and the four tiers as unpriced** — a form that was tiered on "+100 BST and a
> type change, nothing else" is mistiered the moment the ability does something. §9.

| Mega | BST | Ability | Real in-game power | Handling |
|---|---|---|---|---|
| Mega Meganium | 625 | `mega-sol` — no published effect | 625 stats + Grass/Fairy typing, nothing else | **Ship as-is at T4.** Do not compensate with stats, do not substitute a different ability. |
| Mega Feraligatr | 630 | `dragonize` — no published effect | 630 stats + Water/Dragon typing | Same. |
| Mega Eelektross | 615 | `eelevate` — no published effect | 615 stats + pure Electric | Same. |
| Mega Pyroar | 607 | `fire-mane` — no published effect | 607 stats + Fire/Normal | Same. |

**Why inertness was the right call, and why it still matters.** Guessing a mechanic makes the data
untraceable, which is the one thing contract §11.5 exists to prevent, and it creates a balance
liability the moment TPC publishes the real effect. An inert ability is visibly incomplete,
harmless, and a one-line fix later. **None of the four is assigned to a boss** (B9), so whichever
way the ruling-G question above is settled, no *boss* fight changes — the exposure is entirely on
the player's side, at T4/T5.

### 6.5 Rejected sources — recorded so no later pass reopens them

| Rejected | Why |
|---|---|
| **The "Champions mega abilities leak"** (Chinese forum, claimed localisation insider access: Darkrai = Bad Dreams, Magearna = Soul Heart, Zeraora = Speed Boost) | **Ruling E.** Not a datamine, and **demonstrably wrong where testable** — it claimed Mega Lucario Z has Prankster; the official ability is **Aura Guard**. Never seed data from it, not even as a placeholder. **Note the near-miss:** the owner's picks for Darkrai (`dark-aura`) and Zeraora (`transistor`) both differ from the leak, and the one that matches (Magearna / Soul-Heart) matches *canon*, which is where it came from — so the leak gained no credibility from being half-right. |
| **Serebii's Legends Z-A stat tables** for any form whose Champions ability multiplies | **Ruling F.** Z-A has no abilities, so its stat lines are compensation. Confirmed inflated for Mega Starmie (Atk 140 vs 100). Watchlist in §1.4. |
| **Speed Boost on Mega Zeraora** (even if it were confirmed) | Rejected **on merit** as well as on sourcing: base Zeraora is already 143 Speed, so it is redundant *and* it is §6.3's snowball class. |
| **Shadow Tag** as a *proposed* ability for any pending form | §6.3 — the single worst ability to allow under a hard cap. |
| **Power Construct on Mega Zygarde** | A form-changing ability nested inside a Mega form collides with §11.2's single form-swap path. `mega-abilities.md` §4.3 veto. |
| **Commander on Mega Tatsugiri** | Doubles-only, tier 2 / inert in our engine, and it removes the Mega from the field. |
| Dated third-party Champions articles as a re-check source | The Champions roster grew twice during research; dated write-ups still list Absol Z / Garchomp Z / Lucario Z / Golisopod / Baxcalibur as unknown. Re-check only against the live Serebii and Game8 pages. |

### 6.6 Passive levers already doing work

Before adding any new balance machinery, note that five levers are live and cost nothing:

| Lever | Effect |
|---|---|
| **The held-item slot** (§4.7) | A Mega gives up Leftovers / Life Orb / Focus Sash / berries. The main continuous tax on every Mega, and it applies to both sides. |
| **One per side per battle** (contract §11.1) | Six stones in the bag is still one Mega per fight. The tier tables can be generous from T3 on precisely because of this. |
| **Reverts on faint** | A fainted Mega does not free the budget — the side has still used its Mega (canon). Do not implement a *Mega again after it faints* path. |
| **Boss symmetry** (§4) | **24 of the 31 bosses Mega Evolve** — every fight from Fantina on except Mars at Spear Pillar, whose partner carries the side's Mega. The player's Mega is an answer, not an auto-win. |
| **The cap itself** | **Mega Evolution changes no level, so it never interacts with EXP capping** (contract §11.3). The two systems are orthogonal; the only coupling is access timing, which is what §2 and §3 are. |

---

## 7. Question 6 — excluded gimmicks: explicit confirmation

> ### Confirmed: this design introduces **no Dynamax, no Gigantamax, no Z-Moves and no Terastallization** anywhere.
>
> Not in the roster, not in the stone tables, not on any boss, not in the post-game, not behind a
> flag, not as an "optional mode". **Mega Evolution is the only battle gimmick in this game**, as
> `DATA_CONTRACT.md` §11 requires.

### 7.1 Audit of this document

| Excluded mechanic | Appears in this design? | Where it could have crept in, and did not |
|---|---|---|
| **Dynamax / Gigantamax** | **No** | Boss design (§4) uses Mega Evolution for every leader and E4 member; no boss has a raid phase, a size mechanic, or an HP multiplier. No Power Spots, no Dynamax Band, no Max Raid dens, no G-Max forms in any tier table. |
| **Z-Moves** | **No** | The Key Stone (§2.5) is the only battle key item in the game. No Z-Ring / Z-Power Ring, no Z-Crystals among the 92 stones, no once-per-battle move upgrade of any kind. The *once per battle* budget is spent entirely on `rule: "one-per-battle"` Mega Evolution. |
| **Terastallization** | **No** | Type changes happen **only** as part of a Mega form's `types` field (contract §11.1) and are fixed per form — Mega Charizard X is always Fire/Dragon. No player-chosen type, no Tera Orb, no Tera Shard, no Tera Type on any species row, no Tera Raid content. |
| **Primal Reversion** *(not a listed gimmick, but the same class of risk)* | **No** | §5, ruling A. The only non-stone Mega path in the whole design is Mega Rayquaza's `requiresMove` (ruling B), and that is a contract-sanctioned branch, not a second mechanic. |

### 7.2 Enforcement checklist for the build

Contract §11.4 requires a test asserting absence. Concretely:

| # | Guard | Where |
|---|---|---|
| 1 | At import, **drop** every non-default form whose identifier matches `-gmax`, `-totem`, `-eternamax`; **keep** only `-mega`, `-mega-x`, `-mega-y`. | `tools/build_species.py` |
| 2 | Drop the source fields `max_moves`, `gmax_move`, `can_gigantamax`, `tera_type`, `z_move`, `z_crystal` wherever PokeAPI or Showdown supplies them. | `tools/build_species.py` |
| 3 | **Drop `-primal` forms** — contract §11.5, ruling A. | `tools/build_species.py` |
| 4 | No Z-Crystal, `dynamax-candy`, Max Mushroom / Max Honey, `tera-orb` or `tera-shard` item is emitted; **and no `red-orb` / `blue-orb`** (§5). | `tools/build_gamedata.py` |
| 5 | Test asserting **no key or string value** anywhere under `data/` matches `/dynamax\|gigantamax\|gmax\|g-max\|z-?move\|z-?crystal\|z-?ring\|terastal\|tera-?type\|tera-?orb\|tera-?shard/i`. | `tools/tests/test_no_excluded_gimmicks.py` |
| 6 | Test asserting `data/megas.json` contains no `primal-groudon` / `primal-kyogre` id, and that every `stone` value is either **JSON `null`** (Rayquaza only) or an id present in `data/items.json`. **`""` must fail this test** (§1.1). | same test file |
| 7 | Source grep over `src/` for the same pattern, run in CI. **`can_mega_evolve()` must be the only gimmick entry point in `BattleEngine`, and the Mega button the only gimmick button in the battle UI.** | CI |
| 8 | Test asserting every `abilities` entry resolves in `data/abilities.json`, and that **`len(abilities) == 1`** for every form — `<= 1` as the loose guard, `>= 1` because nothing is pending any more (§1.5). | same test file |
| 9 | **Inverted, now that the owner has decided all nine (§1.5):** test asserting **no** form carries `abilityStatus: "pending-owner"` or an empty `abilities` array; that the nine owner-decided forms carry exactly the abilities in **`data/mega_ability_overrides.json`**; and that every `abilityStatus` is one of `canon` / `champions` / `owner-decided` / `owner-decided-by-recommendation`. Join the two files **by form id, and assert all nine join** — today four ids differ between them (§1.5). | same test file |
| 10 | **Report** (not fail) every form whose ability is `tier: 3 / hook: none`. **The list is empty as of 2026-09-23b** (§1.5), so this report is now a **regression detector**: any row appearing means a hook was lost or a new form was added blind. | build report |
| 11 | **Fail** the build on any **boss** in `data/rom/bosses.json` whose `megaForm` ability is not `tier: 1` (rule B9). Bosses live in `bosses.json`, **not** `trainers.json` (contract §7.1), which is what the previous revision said. **The list is empty as of 2026-09-23b** — Fantina's `shadow-tag` and Bertha's `piercing-drill` were the last two and both hooks landed — so this can be a hard failure rather than a report. | same test file |
| 12 | Test asserting **every boss's `ace.species` is in 387–493** and that **no `megaEvolves` member's level exceeds `ace.level`** (rule B10). The second half is the assertion the previous revision of this document would have failed on Wake, Byron and Bertha. | same test file |

> ### Precision notes — three ways these guards go wrong
>
> **1. Do not ban the `-z` suffix.** Z-Crystals end in `-z` (`firium-z`, `psychium-z`) — **and so
> do three legitimate Mega Stones in this roster: `absolite-z`, `garchompite-z`,
> `lucarionite-z`** (the Legends Z-A alternate forms, §1.3). A suffix rule would silently delete
> three shipped stones and break their forms. Guard Z-Crystals by **explicit id list** or by the
> source data's own item category, never by suffix.
>
> **2. Do not ban the substring `max`.** **Dragon Ascent, Dynamax Cannon and Max Guard are
> ordinary moves** in the move table and must not be swept up — Dragon Ascent is **load-bearing**
> for Mega Rayquaza (§8.2). Guard on field names, item ids and form suffixes; never blanket-ban
> `max` in `data/moves.json`.
>
> **3. Do not let guard 5 catch `mega-sol`.** It is a legitimate Champions ability slug (§1.5) and
> contains none of the banned substrings — but a future over-broad pattern on `sol`/`max`/`z` style
> fragments would. Keep the pattern exactly as written in guard 5.

---

## 8. What the build needs from this document

### 8.1 Data rows to generate

**Most of this section is now *done*, not requested.** `data/megas.json` exists and ships 97 rows;
`data/rom/bosses.json` exists and ships 31 bosses × 6. The rows below are marked accordingly.

| File | Rows | Status |
|---|---|---|
| `data/megas.json` | **97 rows** = **30 XY + 18 ORAS + 49 Z-A** (§1.1/§1.2). Not 95, not 93, not 145. | **SHIPPED** — built by `python tools/build_megas.py`. *(The previous revision said "does not yet exist in the repo; this is a greenfield build", and split Gen 6 as 28 + 20.)* |
| Per-row fields | `id`, `base`, `name`, `stone` (**`null` for Rayquaza only**), `types`, `stats`, **`bst`**, **`abilities` (array, length 1)**, `abilityStatus` (**`canon` \| `champions` \| `owner-decided` \| `owner-decided-by-recommendation`** — on **every** row, not just Z-A), `abilityNote` (owner-decided rows), **`requiresForm`** (9 rows), `requiresMove` (Rayquaza only), `metricsSource`, `height`, `weight`, `introducedIn`, `sprite` | **SHIPPED** — a superset of what contract §11.1 documents; §8.3 asks the contract to catch up. |
| `data/items.json` | **92 Mega Stones + 1 Key Stone = 93 rows.** 92 stones, not 93 — Mega Rayquaza has no stone. | **SHIPPED** — verified this pass: all 92 stone ids referenced by `data/megas.json` are present, plus `key-stone`. Each stone row carries `category: "mega-stone"`, `baseSpecies`, `megaForms`, `holdable`, `introducedIn`. |
| Item flags per stone | **Still missing: `tier`** (T1–T7 → the unlock flag from §3.1) and **`unmovable: true`** (immune to Knock Off / Trick / Thief / Covet / Fling). Neither field exists on any row yet; `price: 0` on every stone also means no shop or Game Corner row is priced (§3.4 T2 assumes both). | requested — §3.1, §3.4, §4.7 |
| Map object / script rows | **48** item balls, **12** hidden items, **21** NPC gifts (**8** gym-leader awards per the locked list + 13 other), 1 shop row, 1 Game Corner prize row, 2 Safari prizes, 2 Underground-style finds, 5 BP shop rows; Mega Rayquaza needs none | requested — §3.4, §3.5. **The gym-award rows are `awardsStone` in `bosses.json` and are already authored;** the §3.3 tier conflict has to be ruled on before the *spawn* rows are placed. |
| `data/rom/bosses.json` | `megaForm` + `megaSlot` on **24 of the 31 bosses**: Fantina, Maylene, Wake, Byron, Candice, Volkner, Aaron, Bertha, Flint, Lucian, Cynthia, Barry R3–R7, Cyrus ×3, Saturn ×2, Mars (Lake Verity), Jupiter (Spear Pillar), Charon | **SHIPPED** — §4.2–§4.5. *(The previous revision asked for 13 rows on `trainers.json`; bosses are a different file, and there are 24 of them.)* |
| Party edits | **None.** The rebalance authors parties outright, so the old list — 5 level permutations, 1 species substitution, 1 moveset edit, 1 send-out note — is **void** (B2/B5). **Zero cap changes**, which was and remains the invariant. | superseded |
| `GameState` | `mega_unlocked_at = "badge:relic"` | requested — §2.5 |
| `data/abilities.json` | **No new rows.** Every roster ability slug resolves, re-verified this pass. **The 14 missing hooks all landed during this pass** — all 97 forms' abilities are now `tier: 1` (§1.5). What is left is a *provenance* question, not an engine one: **four of them (`mega-sol`, `dragonize`, `eelevate`, `fire-mane`) implement mechanics ruling G says are unpublished** — §6.4, §9. | **hooks DONE**, ruling G open |

### 8.2 The three content dependencies — features with no other way to be reached

| Form | Dependency | Consequence if skipped |
|---|---|---|
| **Mega Rayquaza** (780) | A **Dragon Ascent move tutor at Stark Mountain**, gated on `flag:hall-of-fame`. `requiresMove` has no other satisfier (ruling B). Also needs the `delta-stream` hook (‡). | Unreachable content. |
| **Mega Zygarde** (778) | **Zygarde Complete must be obtainable** — the Mega is built on Complete, not the 50% form (§1.3), and Power Construct is vetoed. Recommend a post-game cell-gathering flag that grants Complete directly, or a one-off gift form. | Unreachable content. |
| **Mega Magearna (Original Colour)** · **Mega Tatsugiri ×3** · **Mega Meowstic (F)** | **RESOLVED IN DATA** — the discriminator ships as **`requiresForm`** (not `baseForm`): 9 rows carry it, including `floette-eternal` and `zygarde-complete`. What is still owed is the **contract** (§8.3 proposal 1) and the runtime's use of it. | The runtime resolves the wrong form, or silently only ever produces the first row. |

### 8.3 Contract amendments this design requests

Contract §11 says shape changes are made in the contract first. Proposals 1 and 4 are **required**;
2, 3 and 5 are improvements.

| # | Proposal | Status | Reason |
|---|---|---|---|
| 1 | Document **`"requiresForm"`** (nullable string) on a Mega form row, used when `base` + `stone` do not identify the base Pokémon. **The field is already shipped in `data/megas.json` on 9 rows** — `floette-eternal`, `meowstic-male`, `meowstic-female`, `zygarde-complete`, `magearna`, `magearna-original`, `tatsugiri-curly`, `tatsugiri-droopy`, `tatsugiri-stretchy` — under that name, not the `baseForm` this document originally proposed. | **REQUIRED — contract is behind the data** | Nine rows are unresolvable without it, and the contract's §11.1 example does not mention it, so a runtime coded strictly against §11.1 will ignore it. Also undocumented: `bst`, `abilityStatus` on XY/ORAS rows, `abilityNote`, `metricsSource`. §1.3, §1.4 |
| 2 | Add `"tier": 1..7` to each stone's item row. | Improvement | Makes §3's power curve machine-checkable: a test can assert no stone's tier is below its base species' encounter tier (R1) or its BST band (R2). Today that is prose. |
| 3 | Add `"confidence"` to each form and let `"enabled": false` ship a row that does not appear in game. | Improvement | Lets a ‡ engine-hook-pending form ship as auditable data without being reachable, instead of being held out of the file entirely. |
| 4 | **Correct §11.1's comment.** *"a few Z-A Megas have two (e.g. Mega Heatran)"* is **wrong** — Flash Fire + Flame Body are base Heatran's two mainline abilities, and Mega Heatran ships **`["earth-eater"]`** by owner decision. State that `abilities` has length **exactly 1** in the shipped data (≤ 1 as a guard), and keep the array shape. **Still outstanding** — the comment is unchanged in `DATA_CONTRACT.md` as of this pass, and this document does not edit the contract. | **REQUIRED** | §1.5. Left uncorrected, a build will try to give Mega Heatran two abilities that no source assigns it. |
| 5 | State explicitly that **exp yield, EV yield and catch rate are always read from the BASE species**, never the Mega form. | Improvement, with a correctness consequence | Mega forms carry a different `baseExp` in canon. A Mega'd boss ace must not yield more exp than the same Pokémon unmega'd, or Mega Evolution becomes an *input* to the level-cap system — which contract §11.3 promises it is not. |

### 8.4 Cross-document dependencies

| Document | What this design needs from it |
|---|---|
| `game-design.md` §4 | **20 base-species encounter placements** (§3.6). Each is needed at T2 or later, so none touches §5.2's pre-Relic-Badge window. |
| `level-curve.md` §1.1 / §1.3 | **The cap table and the headroom table.** This design edits **no cap, no ace level and no party's highest level** (B3), and makes **no party edits at all** (B2). Replaces the previous revision's dependency on `game-design.md` §2.5/§2.6. |
| `game-design.md` §3.6 | Two replacement-TM gifts are reassigned to stones: **Jasmine after Volkner → `scizorite`**, and **Riley on Iron Island → `falinksite`** alongside the Riolu Egg he already keeps. |
| `game-design.md` §4.2 | Rowan's aide's seed-stock programme hands out **6 stones** with their matching cross-gen starters (§3.5), giving that NPC a second reason to exist. |
| `mega-abilities.md` | **Authoritative for every Z-A ability** (ruling D). §2 = the 40 Champions rows, **verified row-for-row against `data/megas.json` this pass — zero drift**; §4 = the nine forms, now **decided** and mirrored in `data/mega_ability_overrides.json`; §7.1 = the re-check calendar (**Mega Heatran may resolve ~2026-12-01 with Champions Regulation Set M-D, which would supersede the owner's `earth-eater` pick** — Champions is source (1) and outranks an owner decision made now). |
| `species-data.md` §7 | **Closed.** The Mega sprite gap is filled: `assets/generated/mega/{,back/,icon/}` each hold **97 PNGs**, one per row. (Gitignored, like every other generated asset.) |
| `data/abilities.json` | **14 hooks: written** (§1.5), including the three with public effect text — **Aura Guard** halves contact damage (`onDamageCalc`) · **Piercing Drill** pierces Protect for 1/4 (`onProtectCheck`) · **Spicy Spray** burns an attacker that lands a damaging move (`onHitTaken`). **Outstanding: the provenance of the four with no published mechanic** (§6.4). |

---

## 9. Open questions for the owner

Most of the previous revision's list is closed by shipped data. What actually remains:

| # | Question | Default if unanswered |
|---|---|---|
| 1 | **The §3.3 award-vs-tier conflict — the one new question this pass creates, and the only one that touches balance.** Five locked gym awards land earlier than §3.4 tiers their stone: `aerodactylite` (gym 1 / T5), `victreebelite` (gym 2 / T3), **`gengarite` (gym 3 / T7 — Shadow Tag)**, `raichunite-x` (gym 8 / T5), `raichunite-y` (gym 8 / T6). Both the award list and the tiering are owner decisions. | **Resolution 1 in §3.3:** the award is granted as locked, and the stone's *world spawn* stays at its §3.4 tier. |
| 2 | **`shadow-tag` at gym 3 — now a balance question, not a schedule one.** The hook landed mid-pass, so Fantina *can* run it. Should she? §6.3 calls it the worst ability to allow under a hard cap, and at gym 3 the player has no Mega to answer with. | **Cursed Body for Fantina**, Shadow Tag for the player's own `gengarite`. Removing switching from a player who cannot answer the Mega at all is the one case with no counterplay. |
| 3 | **⚠ Ruling G vs. the four newly-implemented abilities** (§6.4, §1.5). `mega-sol`, `dragonize`, `eelevate` and `fire-mane` now have tier-1 hooks, but ruling G says their mechanics are **unpublished and must not be guessed**. Is there a source, or were they invented? If invented: revert to inert, or amend ruling G and **re-price the four tiers** (Meganium T4, Feraligatr T4, Eelektross T4, Pyroar T4 were all set assuming the ability does nothing). | **Record a source in `mega-abilities.md` §2 or revert them to `tier: 3`.** Data whose provenance cannot be stated is exactly what contract §11.5 forbids. |
| 4 | **Zygarde Complete obtain path** (§8.2) — post-game cell-gathering flag, or a direct gift? Mega Zygarde is **778 BST**, the third-highest in the game, and it is unreachable without one. | Mega Zygarde ships as data and is unreachable content. |
| 5 | **`data/items.json` exists (93 rows) but carries no `tier` or `unmovable` flag, and every stone is `price: 0`** (§8.1). §3.4's 92 placements are gated on the tier flag, and §3.4 T2 assumes a Dept. Store shop row and an 8,000-coin Game Corner row that no price supports. | Stones exist but are ungated: nothing stops an early spawn, and Knock Off can strip one. |
| 6 | **Game Corner coins as a stone gate** (`medichamite`, 8,000) — acceptable, or does the Game Corner get cut? | If cut, `medichamite` moves to T4 on R3 grounds (Pure Power). |
| 7 | **Zygarde and Magearna ×2 are `owner-decided-by-recommendation`**, i.e. taken as recommended and never explicitly confirmed (`thick-fat`, `soul-heart` ×2). Confirm or revisit? | They stand. All three are tier 1 and T7, so the cost of being wrong is cosmetic. |

**Closed since the previous revision:**

* **The nine pending abilities are decided** — `data/mega_ability_overrides.json`, all tier 1, all
  shipped in `data/megas.json` (old q1, §1.5).
* **The `baseForm` amendment** — shipped as **`requiresForm`** on 9 rows; only the contract text is
  outstanding (old q4, §8.3).
* **Mega sprites** — 97 × 3 exist under `assets/generated/mega/` (old q6, §8.4).
* **The four effect-less Champions abilities stay inert** (old q2, §6.4): ruling G, unchanged.
* The roster count (§1.1/§1.2), the Primal ruling (§5, ruling A), Rayquaza's no-stone path
  (ruling B), Z-A ability provenance (ruling D), the rejected leak (ruling E), the Starmie stat
  line (ruling F), and the two-ability question — **dissolved**: `abilities` is length 1 (§1.5).

---

## 10. Correction log — 2026-09-23b

Every change this revision made, and the authority for it. **No data file was modified.**

| # | Where | Was | Is | Authority |
|---|---|---|---|---|
| 1 | **§4.2** | Wake's Gyarados and Byron's Steelix permuted to the **top level**, making them the aces | Wake's ace is **Floatzel 54**, Byron's is **Bastiodon 66**; both Megas ride a **non-ace teammate** one level below (Gyarados 53, Steelix 65) | CLAUDE.md *Bosses* (every ace is Gen 4, dex 387–493); `data/rom/bosses.json`; contract §7.1 |
| 2 | **§4.3** | Bertha's substituted **Excadrill permuted to 55, above Rhyperior 52** | Ace is **Rhyperior 97**; **Mega Excadrill 96** in slot 5, Ground/Steel, consistent with her Ground identity | same |
| 3 | **§1.1, §1.2** | XY **28** / ORAS **20**; Latias and Latios tagged `oras` | **XY 30 forms / 28 species** (Charizard and Mewtwo doubled) · **ORAS 18 new Megas** · **Latias and Latios are XY** | owner ruling (CLAUDE.md *Open items*) |
| 4 | **§1.4, §3.4, §6.2** | "base BST + 100 … **no exceptions**" | **96 of 97.** **Mega Zygarde is the sole exception at 778**, built on Zygarde-Complete (708). Mega Floette's apparent second exception dissolves once `requiresForm` (Floette-Eternal, 551) is resolved | `data/megas.json` |
| 5 | **§4.6** | Re-verified against the **vanilla** cap ladder (14…62) and `game-design.md` §2.6 | **Marked superseded and re-run** against **18/27/36/45/54/66/78/90/96/97/98/99/100**, sourced to `docs/research/level-curve.md` §1.1 and `data/level_caps.json`; per-segment EXP multipliers noted | `data/level_caps.json`; contract §8 |
| 6 | **§4.1 B8, §4.2, §0.1** | "Roark, Gardenia and **Fantina never Mega, in any circumstance**"; Maylene was the debut | **Fantina is the first boss to Mega Evolve** (Mega Gengar, slot 5, L35) — gym leaders Mega from **gym 3 onward** and the Ring follows immediately; Maylene is the first Mega-*vs*-Mega fight | CLAUDE.md *Bosses* / *Mega Ring*; contract §7.1, §12.5; `bosses.json` |
| 7 | **§4.4, §2.4** | "**No Team Galactic boss ever Mega Evolves**" | **Withdrawn.** Seven of nine Galactic fights Mega, plus Charon; Mars at Spear Pillar carries none because Jupiter holds the side's one Mega | `bosses.json`; `rosters-story.md` |
| 8 | **§4.5** | Barry's first Mega is **R5**; R3/R4 hold no Mega-capable member; R4 has +1 headroom | **First Mega is R3**; Staraptor is slot 2 from R3 on, five fights; every Barry ace sits exactly at its cap | `bosses.json`; `level-curve.md` §1.3 |
| 9 | **§1.5, §0.2 D, §7.2, §9** | Nine forms `pending-owner`, `abilities: []`; ◊ marker live | **All nine decided** (`earth-eater`, `dark-aura`, `thick-fat`, `soul-heart` ×2, `transistor`, `storm-drain` ×3), all tier 1; **◊ retired**; `abilityStatus` has four values | `data/mega_ability_overrides.json`; `data/megas.json` |
| 10 | **§4.1 B2/B4/B5, §8.1** | Parties from the ROM tables; 5 permutations, 1 substitution, 1 moveset edit; `megaForm` on 13 `trainers.json` rows | Parties are **`data/rom/bosses.json`**, six members each, **no party edits**; `megaForm` on **24 of 31 bosses** | contract §7.1; `bosses.json` |
| 11 | **§4.2, §6.3** | Mega Raichu Y sold on a "guaranteed **Zap Cannon**" | Raichu has **no Zap Cannon** in `data/learnsets.json`; No Guard buys perfect-accuracy **Thunder / Focus Blast** | `data/learnsets.json`; `rosters-gyms58.md` §8 |
| 12 | **§2.1, §2.4** | Key Stone handed over by **Cynthia**; "the world contains **two** Mega Stones at this point" | Giver is the player's **counterpart (Dawn/Lucas)**; the player also already holds the **three dormant pre-Ring gym awards** | contract §12.5; CLAUDE.md *Gym stone awards* |
| 13 | **§3.3, §6.1, §9 q1** | Spine listed 6 leaders and no conflict | All **8** leaders and the locked award list, with the **award-vs-tier conflict flagged** and three resolutions ranked | CLAUDE.md *Gym stone awards*; `bosses.json` `awardsStone` |
| 14 | **§8.1, §8.2, §8.3, §8.4** | `data/megas.json` "does not yet exist"; sprites a known gap; `baseForm` requested | 97 rows shipped; **97 × 3 sprites** exist; discriminator ships as **`requiresForm`**; contract §11.1 is the thing now behind | repo state |
| 15 | **§4.3, §7.2** | "exactly one boss depends on an unwritten hook" | **Corrected to two, then to ZERO mid-pass** — Fantina/`shadow-tag` and Bertha/`piercing-drill` were the two, and a concurrent ability workflow landed **all 14 outstanding hooks** at 21:30, so every one of the 97 forms is `tier: 1`. Guard 11 is now a hard failure reading `bosses.json`, and a new guard 12 asserts the Gen 4 ace and the "Mega never outranks the ace" rules | `data/abilities.json`; `bosses.json` |
| 16 | **§1.5, §6.4, §9 q3** | Ruling G: `mega-sol`, `dragonize`, `eelevate`, `fire-mane` "stay `tier: 3`, inert — do not guess a mechanic" | **Flagged as an open conflict, not rewritten.** All four now ship tier-1 hooks. Either a source exists and must be recorded, or ruling G was broken and four T4 tiers are mispriced | `data/abilities.json` (2026-09-23 21:30) |

| 17 | **§8.1, §9 q5** | "`data/items.json` … absent from the repo" | **It exists — 93 rows, all 92 stone ids plus `key-stone`, verified this pass.** What is actually missing is narrower: **no `tier` flag, no `unmovable` flag, and `price: 0` on every stone** | `data/items.json` |

**Reported, not fixed** (data changes are out of scope for this pass):

1. `data/megas.json` tags `latias-mega` / `latios-mega` `introducedIn: "oras"`; the ruling is `xy`.
   Provenance metadata only — no stone, tier or stat moves.
2. `data/mega_ability_overrides.json` uses four `form` ids that do not exist in `data/megas.json`
   (`magearna-original-mega`, `tatsugiri-{curly,droopy,stretchy}-mega` vs the shipped
   `magearna-mega-original`, `tatsugiri-mega-{curly,droopy,stretchy}`). The abilities agree; a
   join-by-id test would match only 5 of 9.
3. `data/mega_ability_overrides.json`'s Tatsugiri note says *"T4 (badge:mine, cap 44)"* — under the
   shipped curve `badge:mine` is **cap 78**.
4. `DATA_CONTRACT.md` §11.1's comment (*"a few Z-A Megas have two (e.g. Mega Heatran)"*) and its
   §11.1 field list (no `requiresForm`, `bst`, `abilityStatus` on XY/ORAS rows) are behind the data
   — §8.3 proposals 1 and 4.
5. `data/items.json` ships all 92 stones but **no `tier` and no `unmovable` flag**, and every stone
   is `price: 0` — so §3.1's tier gate and §4.7's Knock Off immunity are documented but unenforced,
   and §3.4's shop / Game Corner rows have no price to sell at.
6. `CLAUDE.md`'s *Level caps* line still states a single global **EXP multiplier ×2.5**;
   `DATA_CONTRACT.md` §8 and `data/level_caps.json` are **per-segment** with the top-level value
   permanently `null`.
