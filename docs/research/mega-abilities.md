# Mega Ability Assignments

The provenance record for every Mega form's ability, as required by
`docs/DATA_CONTRACT.md` §11.5. **This file is the authority for `abilities` and
`abilityStatus` in `data/megas.json`.** Nothing may ship an ability that is not traceable
to a row in this file.

| | |
|---|---|
| **Date of this pass** | 2026-09-23 · **verified against shipped data 2026-09-23b** |
| **Rule applied** | DATA_CONTRACT §11.5 — (1) Pokémon Champions, else (2) owner-approved assignment |
| **Z-A Mega forms resolved from Champions** | **40** (39 published rows; Meowstic M/F counted separately). **§2 was checked row-for-row against `data/megas.json` this pass: zero drift.** |
| **Forms resolved by owner decision** | **9 — no longer pending.** The owner has decided all nine; **`data/mega_ability_overrides.json` is the authoritative machine-readable record** and `data/megas.json` matches it. `abilityStatus` is `owner-decided` (6) or `owner-decided-by-recommendation` (3). §4 |
| **Forms still `pending-owner`** | **None.** No row in `data/megas.json` ships `abilities: []`. |
| **XY / ORAS Megas** | Not listed here. Their abilities are mainline canon and were never in doubt. They ship `abilityStatus: "canon"` (48 rows). |

---

## 1. Why this file exists

Pokémon Legends: Z-A **has no Ability system at all**, so its ~47 Mega forms have no
ability defined in that game. **Pokémon Champions** does have a full Ability system and
does support Mega Evolution, and The Pokémon Company has published abilities for Z-A Mega
forms as they enter the competitive roster. Champions is therefore source (1).

Champions has not shipped every Z-A Mega. Regulation Set M-A banned all
Legendary/Restricted Pokémon and M-B/M-C did not lift that, so the legendary and mythical
Z-A Megas are simply absent — their ability is not secret, it **does not exist yet**. Those
fall through to source (2): an owner decision, recorded in §4 below.

---

## 2. Section A — RESOLVED FROM POKÉMON CHAMPIONS

`abilityStatus: "champions"`. These are not proposals. Do not relitigate them and do not
substitute a "better" ability for any row here — the point of §11.5 is that the shipped
ability is traceable, not that it is optimal.

**Provenance.** Cross-checked 2026-09-23 against two independent live sources that agree
row-for-row on all 39 published rows: Serebii's dedicated Champions *Mega Evolution
Abilities* page and Game8's independent Champions ability list. Champions is on v1.1.0+ and
running Regulation Set M-C (live since 2026-09-09).

> **Do not re-check this table against dated articles.** The roster grew twice during
> research: v1.1.0 added 11 forms, and the 2026-09-09 update added Absol Z, Garchomp Z,
> Lucario Z, Golisopod and Baxcalibur. Older write-ups (e.g. Kotaku's guide) still list
> those five as unaccounted for. Any future re-check uses the live Serebii/Game8 pages.

`engine` = the `tier` and `hook` carried in `data/abilities.json`. **tier 1 = implemented behind a
real hook; tier 3 = the row exists but `hook` is `none`, i.e. data only.**

> **Updated 2026-09-23b: the nine tier-3 rows in this table are now tier 1.** An
> ability-implementation workflow wrote all nine hooks (plus five canon ones — `delta-stream`,
> `shadow-tag`, `parental-bond`, `skill-link`, `steadfast`), so **no Mega form in the roster is
> blocked on engine work any more**. Two caveats: this is another workflow's live output, so
> re-read `data/abilities.json` before relying on it; and **four of the nine —`mega-sol`,
> `dragonize`, `eelevate`, `fire-mane` — have no published mechanic**, so what their hooks *do*
> needs a source or ruling G is broken (`mega-design.md` §6.4, §9 q3).

| Mega form | Ability | slug | engine | hook |
|---|---|---|---|---|
| Mega Raichu X | Electric Surge | `electric-surge` | 1 | onSwitchIn |
| Mega Raichu Y | No Guard | `no-guard` | 1 | onAccuracyCheck |
| Mega Clefable | Magic Bounce | `magic-bounce` | 1 | onStatusApply |
| Mega Victreebel | Innards Out | `innards-out` | 1 | onContactHit |
| Mega Starmie | **Huge Power** | `huge-power` | 1 | onDamageCalc |
| Mega Dragonite | Multiscale | `multiscale` | 1 | onDamageCalc |
| Mega Meganium | Mega Sol | `mega-sol` | **1** | onWeatherView |
| Mega Feraligatr | Dragonize | `dragonize` | **1** | onModifyMoveType |
| Mega Skarmory | Stalwart | `stalwart` | **1** | onRedirect |
| Mega Chimecho | Levitate | `levitate` | 1 | onTypeImmunity |
| Mega Absol Z | Sharpness | `sharpness` | 1 | onDamageCalc |
| Mega Staraptor | Contrary | `contrary` | 1 | onStatusApply |
| Mega Garchomp Z | Levitate | `levitate` | 1 | onTypeImmunity |
| Mega Lucario Z | Aura Guard | `aura-guard` | **1** | onDamageCalc |
| Mega Froslass | Snow Warning | `snow-warning` | 1 | onSwitchIn |
| Mega Emboar | Mold Breaker | `mold-breaker` | 1 | onAccuracyCheck |
| Mega Excadrill | Piercing Drill | `piercing-drill` | **1** | onProtectCheck |
| Mega Scolipede | Shell Armor | `shell-armor` | 1 | onHpCross |
| Mega Scrafty | Intimidate | `intimidate` | 1 | onSwitchIn |
| Mega Eelektross | Eelevate | `eelevate` | **1** | onTypeImmunity |
| Mega Chandelure | Infiltrator | `infiltrator` | 1 | onAccuracyCheck |
| Mega Golurk | Unseen Fist | `unseen-fist` | **1** | onProtectCheck |
| Mega Chesnaught | Bulletproof | `bulletproof` | 1 | onTypeImmunity |
| Mega Delphox | Levitate | `levitate` | 1 | onTypeImmunity |
| Mega Greninja | Protean | `protean` | 1 | onModifyMoveType |
| Mega Pyroar | Fire Mane | `fire-mane` | **1** | onDamageCalc |
| Mega Floette | Fairy Aura | `fairy-aura` | 1 | onDamageCalc |
| Mega Meowstic (Male) | Trace | `trace` | 1 | onSwitchIn |
| Mega Meowstic (Female) | Trace | `trace` | 1 | onSwitchIn |
| Mega Malamar | Contrary | `contrary` | 1 | onStatusApply |
| Mega Barbaracle | Tough Claws | `tough-claws` | 1 | onDamageCalc |
| Mega Dragalge | Regenerator | `regenerator` | 1 | onStatusApply |
| Mega Hawlucha | No Guard | `no-guard` | 1 | onAccuracyCheck |
| Mega Crabominable | Iron Fist | `iron-fist` | 1 | onDamageCalc |
| Mega Golisopod | Tough Claws | `tough-claws` | 1 | onDamageCalc |
| Mega Drampa | Berserk | `berserk` | 1 | onContactHit |
| Mega Falinks | Defiant | `defiant` | 1 | onStatusApply |
| Mega Scovillain | Spicy Spray | `spicy-spray` | **1** | onHitTaken |
| Mega Glimmora | Adaptability | `adaptability` | 1 | onDamageCalc |
| Mega Baxcalibur | Thermal Exchange | `thermal-exchange` | 1 | onContactHit |

### 2.1 Three things this table settles

1. **All 40 slugs already exist in `data/abilities.json`** — verified, zero typos, zero
   additions needed to the ability list itself.
2. **Nine of them *were* tier 3 with `hook: none`** — `mega-sol`, `dragonize`, `stalwart`,
   `aura-guard`, `piercing-drill`, `eelevate`, `unseen-fist`, `fire-mane`, `spicy-spray` — the
   ability sourced but not implemented. **All nine now carry a tier-1 hook** (2026-09-23b; see the
   note above the table), so the separate engine gate is closed and `mega-design.md`'s `‡` marker
   has no members. The `◊` provenance marker is retired too, for a different reason: the owner
   decided the nine §4 forms. **What is still open is the provenance of four of these nine
   mechanics**, which TPC has never published (`mega-design.md` §6.4).
3. **Mega Starmie's ability is no longer uncertain — Huge Power is confirmed.** That
   removes the `conf=uncertain` half of its double gate. The power half stands: Huge Power
   on a 115-base-Speed special attacker's body is still `mega-design.md` §6.3's problem, so
   **Mega Starmie stays T7**. The data flag may be dropped; the tier may not.

### 2.2 Two Champions design patterns worth copying

Both are load-bearing for the proposals in §4.

- **Champions is bold, not conservative.** It hands out weather setters (Snow Warning on
  Froslass), terrain setters (Electric Surge on Raichu X), Huge Power (Starmie), and
  **a legendary's signature ability to a non-legendary** (Xerneas's Fairy Aura on Floette).
  Roughly half its picks are the base species' own ability; the other half are new and
  aggressive. "Keep the base ability" and "transplant a signature ability" are *both*
  in-language.
- **Cosmetic variants get the SAME ability.** Meowstic Male and Female have different
  ability sets in the mainline games, and Champions gave **both** Trace. This is the
  governing precedent for Mega Magearna (Original Colour) and for the three Mega Tatsugiri
  forms in §4.

---

## 3. Standing facts that apply to all nine open forms

Established from `mega-design.md` §3.4, §4.2 and §4.3; they change what "risky" means here,
so read this before the per-form blocks.

1. **No boss Mega Evolves into any of these nine — still true, re-checked against
   `data/rom/bosses.json`.** The 24 boss Megas are Gengar, Lucario, Gyarados (×3), Steelix,
   Froslass, Raichu Y, Staraptor (×5), Houndoom (×2), Alakazam (×2), Absol, Dragalge, Scizor,
   Excadrill, Gallade, Garchomp and Metagross. *(Corrected from the previous list: Heracross is
   **not** a boss Mega — Aaron runs Mega Scizor — and Gengar, Staraptor, Alakazam, Absol, Dragalge
   and Metagross are.)* Every one of the nine forms below is **player-side only**, so no choice
   here can be turned against the player by a level-matched AI.
2. **Eight of the nine are post-Hall-of-Fame (T7), where `postGameCap` is 100 — i.e. the
   hard cap is gone.** Heatran, Darkrai, Zygarde, Magearna (both colours) and Zeraora all
   sit in T7. The hard-cap argument that dominates `mega-design.md` §6.3 therefore does
   **not** constrain them, which is why these can take interesting abilities. *(This is why the
   owner's picks needed no balance re-run: eight of them cannot reach a capped fight.)*
3. **Mega Tatsugiri is the one exception and the only genuinely balance-sensitive form
   here.** `tatsugirinite` is T4 (`badge:mine` / STRENGTH, **cap 78** — `data/level_caps.json`;
   the *44* in earlier text and in the override file's note is the dead vanilla ladder) —
   mid-game, fully capped content. It is the only one of the nine where an ability can be
   oppressive. Treat it conservatively; the other eight can be treated on merit.
4. **Every ability recommended below — and every one the owner actually chose, including the
   write-in `earth-eater` (tier 1, `onTypeImmunity`) — is `tier: 1` in `data/abilities.json`**: an
   existing hook, zero new engine work. Re-verified this pass, not assumed. That is deliberate: §2.1
   already leaves nine Champions-confirmed forms blocked on new hooks, and the pending set
   should not add a tenth.
5. **Stats are no longer unsourced — all nine ship spreads in `data/megas.json`**, listed in
   `mega-design.md` §1.4. The per-form blocks below still show the *assumed* base + 100 shape they
   reasoned from; where the shipped spread differs the block says so. The one structural
   difference: **Mega Zygarde is 778, not 700** — it is built on Zygarde-**Complete** (708), and it
   is the roster's sole exception to base + 100 (§4.3).

---

## 4. Section B — RESOLVED BY OWNER DECISION

> ### RESOLVED — the owner has decided all nine (2026-09-23).
>
> This section was the decision sheet. It is now the **record of the decision plus the reasoning
> that produced it**, kept because the reasoning is what a later pass needs when Champions
> eventually publishes one of these upstream (§7.1).
>
> **The authoritative record is `data/mega_ability_overrides.json`**, and `data/megas.json` ships
> exactly what it says. `abilityStatus` is **`owner-decided`** where the owner chose explicitly and
> **`owner-decided-by-recommendation`** where the recommendation was taken without an explicit
> confirmation — the second group is flagged for review, not settled forever.

### 4.0 The decision, as shipped

| # | Form | **Decided** | Status | Was recommended here | Engine |
|---|---|---|---|---|---|
| 1 | Mega Heatran | **Earth Eater** | `owner-decided` — **a write-in**, none of the three options below | Levitate | tier 1, `onTypeImmunity` |
| 2 | Mega Darkrai | **Dark Aura** | `owner-decided` | Dark Aura ✓ | tier 1, `onDamageCalc` |
| 3 | Mega Zygarde | **Thick Fat** | `owner-decided-by-recommendation` | Thick Fat ✓ | tier 1, `onDamageCalc` |
| 4 | Mega Magearna | **Soul-Heart** | `owner-decided-by-recommendation` | Soul-Heart ✓ | tier 1, `onHpCross` |
| 5 | Mega Magearna (Original Colour) | **Soul-Heart** | `owner-decided-by-recommendation` | Soul-Heart ✓ *(mirrors #4, as required)* | tier 1, `onHpCross` |
| 6 | Mega Zeraora | **Transistor** | `owner-decided` | Transistor ✓ | tier 1, `onDamageCalc` |
| 7 | Mega Tatsugiri (Curly) | **Storm Drain** | `owner-decided` | Storm Drain ✓ | tier 1, `onTypeImmunity` |
| 8 | Mega Tatsugiri (Droopy) | **Storm Drain** | `owner-decided` | Storm Drain ✓ *(mirrors #7)* | tier 1, `onTypeImmunity` |
| 9 | Mega Tatsugiri (Stretchy) | **Storm Drain** | `owner-decided` | Storm Drain ✓ *(mirrors #7)* | tier 1, `onTypeImmunity` |

**Eight of nine went to the recommendation; the ninth (Heatran) went to a write-in that is
strictly better than the recommendation** — see §4.1. The mirror rules held: rows 4/5 match and
rows 7/8/9 match, so the Meowstic precedent (§2.2) was respected.

> **Reported, not fixed — a data-side id mismatch.** `data/mega_ability_overrides.json` names four
> of the nine with a different word order from the shipped form ids:
> `magearna-original-mega` / `tatsugiri-curly-mega` / `tatsugiri-droopy-mega` /
> `tatsugiri-stretchy-mega` in the override file, against `magearna-mega-original` /
> `tatsugiri-mega-curly` / `tatsugiri-mega-droopy` / `tatsugiri-mega-stretchy` in
> `data/megas.json`. **The abilities agree, so no shipped ability is wrong**, but any test that
> joins the two files on `form` will match only 5 of 9 and silently pass. Fix in the data.

---

### 4.1 Mega Heatran — Fire/Steel · BST 700 · T7

| | |
|---|---|
| Base species | Heatran #485 · Fire/Steel · 91/90/106/130/106/77 (600) |
| Base abilities | **Flash Fire** (normal) · **Flame Body** (hidden) |
| Mega typing | Fire/Steel (unchanged) |
| Assumed Mega stats | base + 100 → BST 700; bulky special attacker, low Speed |
| Champions | **Not shipped.** Announced as Champions' first Legendary Mega, expected at the start of Regulation M-D around **2026-12-01**. TPC said "stay tuned for more details" and has published **no ability**. |

> **Corrects the prior pass.** `mega-design.md` records Mega Heatran as having **two
> abilities**, `flash-fire` + `flame-body`. That is a **misread**: those are base Heatran's
> normal and hidden abilities in every mainline game, not a Mega ability pair. No source
> assigns Mega Heatran two abilities. See §5.1 — this dissolves `mega-design.md` §9 open
> question 5 entirely.

> ### DECIDED: **Earth Eater** *(`earth-eater`, tier 1, `onTypeImmunity`)*
>
> **An owner write-in, not one of the three options below, and it dominates all of them.** Where
> Levitate makes Heatran's 4× Ground weakness *nothing*, **Earth Eater makes it healing** — a
> Ground move restores 1/4 max HP. Same immunity, plus recovery, on the same hook and the same
> tier, with no new engine work: Earth Eater is a Gen 9 ability (Orthworm) and already exists in
> `data/abilities.json`. And because Mega Heatran is **T7 post-Hall-of-Fame at cap 100**, the
> power level is balance-insensitive.
>
> Shipped spread: **91/120/106/175/141/67 (700)**, Fire/Steel, stone `heatranite`.
>
> The Levitate case below is kept as the reasoning that led here — it is also the argument a future
> pass needs if Champions publishes something different in Regulation M-D (§7.1).

**Superseded recommendation — Levitate** *(`levitate`, tier 1, onTypeImmunity)*

Heatran is the game's canonical "why does this thing not have Levitate" Pokémon: the flavour
is a magma beast that clings to cave walls and ceilings, and the mechanical reality is a
Fire/Steel body with a **4× Ground weakness** and 77 Speed. Levitate is the one ability that
speaks to both at once — it is the Mega resolving the base form's signature flaw, which is
the core Gen 6 Mega design move (Mega Venusaur's Thick Fat, Mega Aggron's Filter).

It is also squarely in Champions' demonstrated language: Levitate is its single most-used
pick, on **three** of the 39 published rows (Chimecho, Delphox, **Garchomp Z**) — and
Garchomp Z shows Champions is willing to hand Levitate to a 700-BST pseudo-legendary. Zero
engine cost: `onTypeImmunity` is already required for Flash Fire and Bulletproof.

**RISK — flagged, and judged acceptable.** Fire/Steel + Levitate is a very hard defensive
profile: immune to Poison and Ground, resists nine types, weak to only Water and Fighting.
It deletes Earthquake, the standard player-side answer to a Fire/Steel wall. Two things
contain it: Mega Heatran is **T7 post-Hall-of-Fame** (uncapped) and, per §3.1, **no boss
ever holds it** — Flint's Mega is Houndoom. The oppressive version of this pick — a
level-matched boss whose 4× weakness you cannot exploit — never occurs in this game.

**Alternative A — Flash Fire** *(conservative)*. Continuity: it is Heatran's ability in
every mainline game, so it needs no invention at all, and it is a real answer to Flint. The
cost is that Mega Heatran's entire identity becomes "+100 stats" — a dull Mega, on the one
form the owner is most likely to care about.

**Alternative B — Drought** *(strong)*. The direct Gen 6 precedent: the high-SpA Fire-type
Mega that got a weather setter is **Mega Charizard Y**. 1.5× Fire STAB off ~150 SpA, and it
softens the Water weakness. Two reasons it is not the recommendation: this game **already
ships Mega Charizard Y**, so a second sun-setting Fire Mega is redundant design; and
permanent weather is a *battlefield* change, the class `mega-design.md` §6.3 singles out as
worth more than a stat line. Fine in the player's hands at T7 — just less interesting and
less Heatran-specific than Levitate.

**Rejected:** Flame Body (contact-burn on a 700-BST mon that does not want to be touched —
strictly worse flavour than either option above); Magma Armor (near-inert).

---

### 4.2 Mega Darkrai — Dark · BST 700 · T7

| | |
|---|---|
| Base species | Darkrai #491 · Dark · 70/90/90/135/90/125 (600) |
| Base abilities | **Bad Dreams** (only ability, no hidden) |
| Mega typing | Dark (unchanged) |
| Datamined Champions stats | **70/120/130/165/130/85** (700) — present in the Champions files |
| Champions | **Not shipped.** Form data is datamined and present, but the Abilities field reads *"No abilities listed"* — the form exists in the files with no ability assigned. Banned from M-A through M-C as a Restricted/Mythical. |

> **The datamined spread is a real design signal, and it is not base + 100 spread evenly.**
> Speed **drops** 125 → 85 while SpA goes 135 → 165 and both defences go 90 → 130. Mega
> Darkrai is not a faster Darkrai; it is a **bulky special wallbreaker**. Pick the ability
> for that body, not for the base form's sleep-and-sweep pattern. Treat the numbers as
> datamined, not official — but they are the best evidence available, and this is the only
> one of the nine whose stat shape is known at all. (Magearna's and Zeraora's blocks exist
> in the same source and should be pulled in a stats pass.)

> ### DECIDED: **Dark Aura** *(`dark-aura`, tier 1, `onDamageCalc`)* — as recommended
> Shipped spread: **70/120/130/165/130/85 (700)** — the datamined block, confirmed in
> `data/megas.json` — Dark, stone `darkranite`. `abilityStatus: owner-decided`.

**Recommended: Dark Aura** *(`dark-aura`, tier 1, onDamageCalc)*

Champions has already done this exact thing once: it gave **Xerneas's Fairy Aura to Mega
Floette**. Transplanting an aura onto a Mega is a confirmed, in-language Champions move, and
Darkrai — the Dark-type mythical, the literal embodiment of nightmare — is the most natural
Dark Aura holder in the franchise. Mechanically it is a pure damage multiplier on an
existing hook, and it suits the new body: a 165-SpA wallbreaker wants a flat multiplier, not
a Speed or snowball ability it can no longer use at 85 Speed.

The pick **self-balances in a way the alternatives do not**: Dark Aura boosts Dark moves for
*both* sides. Every Dark attacker the player faces gets 1.33× too. That is a real cost, it
is legible to the player, and it is the kind of two-edged ability a mythical should have.

Bonus interaction, and a reason to read this row together with §4.3: Champions confirmed
**Fairy Aura on Mega Floette**, so **Aura Break already has one live target in this game.**
Dark Aura on Mega Darkrai would give it a second.

**Alternative A — Bad Dreams** *(conservative)*. Its own signature, and the only ability it
has ever had. Zero invention, zero risk. The problem is that Bad Dreams is **conditional on
the foe being asleep**, and with Dark Void at 50% accuracy in modern gens — and questionable
whether it ships here at all — the condition rarely fires in single-player. A Mega whose
ability does nothing most turns is a bad Mega. The unreliable forum rumour of an "enhanced
Bad Dreams" is not a source and is not implementable as a tier-1 ability — **do not ship
it** (see §6).

**Alternative B — Unaware** *(strong)*. Ignores the target's stat boosts. On a 130/130
defensive body this is superb and it fits "nightmare" flavour — your buffs do not matter.
**RISK:** it hard-counters setup, which is the boss AI's main comeback line, and Unaware
plus 130/130 bulk is a stall shape. T7 and player-only contains it, but it is the most
oppressive of the three if the owner ever moves Darkrai earlier.

**Rejected:** Shadow Tag (§6 — `mega-design.md` §6.3 calls it the single worst ability to
allow under a level cap, and it is `tier: 3` in our data anyway); Insomnia (a thematically
cute inversion that does nothing on this body).

---

### 4.3 Mega Zygarde — Dragon/Ground · BST **778** · T7 *(flag-gated)*

| | |
|---|---|
| Base species | Zygarde #718 (50% Forme) · Dragon/Ground · 108/100/121/81/95/95 (600) |
| Base abilities | **Aura Break** (50% Forme) · **Power Construct** (10%/50% Power Construct formes) |
| Mega typing | Dragon/Ground (unchanged) |
| **Shipped Mega stats** | **216/70/91/216/85/100 = BST 778** — built on **Zygarde-Complete (708)**, not the 50% Forme, so base + 100 does *not* apply. **This is the only form in the 97-row roster that breaks the +100 rule** (`mega-design.md` §1.4), and `data/megas.json` declares its base with `requiresForm: "zygarde-complete"`. The old *"BST 700, a wall with a real Attack stat"* line was wrong twice: the total and the shape — it is a 216/216 HP-and-SpA monster with 70 Attack. |
| Champions | **Not shipped**, no ability announced. Banned as a Restricted Legendary through M-C. |

> ### DECIDED: **Thick Fat** *(`thick-fat`, tier 1, `onDamageCalc`)* — taken as recommended
> `abilityStatus: **owner-decided-by-recommendation**` — **not explicitly confirmed by the owner.**
> Flag for review if he wants to revisit. Halves Ice and Fire, so the 4× Ice weakness becomes 2×.
> Stone `zygardite`; **still gated on a Zygarde-Complete obtain path** (`mega-design.md` §8.2).

**Recommended: Thick Fat** *(`thick-fat`, tier 1, onDamageCalc)*

Zygarde's one structural flaw is a **4× Ice weakness** — the biggest liability on any
Dragon/Ground, and the reason Garchomp is answered by Ice Shard in this game. Thick Fat
halves Ice (and Fire) damage, turning 4× into 2×. **The precedent is exact and is Gen 6's
own:** Mega Venusaur got Thick Fat for precisely this reason. Thematically it reads as the
cell-mass armour of a swarm made solid, and it costs nothing to implement.

It is also the *right shape* for the body: base + 100 on 108/100/121/81/95/95 is a bulky
physical attacker, not a special threat. A defensive multiplier does more for it than any
offensive ability, and it does not create a stall lock the way Multiscale does.

**Alternative A — Aura Break** *(conservative)*. Continuity — the 50% Forme's own ability.
It used to be near-inert in a Sinnoh game, but that has changed: **Champions confirmed Fairy
Aura on Mega Floette**, and if the owner also takes Dark Aura for Mega Darkrai (§4.2), Aura
Break would have **two live targets in this game** and become a genuine, if narrow, anti-Mega
tech. Honest assessment: still narrow. Picking it makes Mega Zygarde a pure stat boost in
~99% of battles.

**Alternative B — Multiscale** *(strong)*. Halves all damage at full HP. **RISK:** on
108 HP / 121 Def / 95 SpD plus +100, Multiscale produces something the player essentially
cannot be punished for bringing in, and it duplicates Champions' Mega Dragonite pick. The
most powerful of the three.

**Rejected — and this one is a hard rule, not a preference:**

> **Power Construct must NOT be assigned to Mega Zygarde.** It is a **form-changing**
> ability (50% → Complete at ≤50% HP) and it would fire *inside* a Mega form, colliding
> head-on with the single form-swap path in the engine contract (§11.2: swap types, stats
> and ability; recompute keeping the HP fraction; revert on faint or battle end). Two nested
> form changes with two different revert rules is a bug factory for the sake of one Mega. It
> is `tier: 1 / onTurnEnd` in our data, so the engine *could* run it — which makes this an
> explicit design veto, not an implementation gap.

Also rejected: Levitate (contradicts a Ground-type serpent of the earth, and fixes none of
its actual weaknesses — Ice, Fairy, Dragon).

---

### 4.4 Mega Magearna — Steel/Fairy · BST 700 · T7

| | |
|---|---|
| Base species | Magearna #801 · Steel/Fairy · 80/95/115/130/115/65 (600) |
| Base abilities | **Soul-Heart** (only ability, no hidden) |
| Mega typing | Steel/Fairy (unchanged) |
| Assumed Mega stats | base + 100 → BST 700; slow bulky special attacker |
| Champions | **Not shipped.** Form data exists in the Champions database; the Abilities field reads *"No abilities listed"*. |
| Rumour | "Soul-Heart" — unverified, but it matches mainline canon exactly, so the rumour is uninformative rather than wrong. |

> ### DECIDED: **Soul-Heart** *(`soul-heart`, tier 1, `onHpCross`)* — taken as recommended
> `abilityStatus: **owner-decided-by-recommendation**` — not explicitly confirmed. Shipped spread
> **80/125/115/170/115/95 (700)**, Steel/Fairy, stone `magearnite`. Rationale as recorded in the
> override file: `magearnite` is a Battle Park BP purchase, so the player has owned Soul-Heart on
> the base form for a long time before the Mega exists.

**Recommended: Soul-Heart** *(`soul-heart`, tier 1, onHpCross)*

This is the rare case where continuity is also the *correct* call, because of an access
argument that is easy to miss: **the player already owns Soul-Heart on the base form.**
`magearnite` is a Battle Park BP purchase, so by the time the Mega exists, base Magearna and
its Soul-Heart have been in the party for a while. Assigning it to the Mega adds **no new
capability to the game at all** — the Mega becomes purely the stat block. Assigning anything
else *creates* a new choice (Soul-Heart on base vs. the new ability on Mega), which is more
interesting but strictly more power.

**RISK — named, then dismissed on structure.** Soul-Heart is a snowball ability (+1 SpA on
every faint, either side), and `mega-design.md` §6.3 flags snowballing as the danger class
under a hard cap, with Mega Blaziken's Speed Boost as the cited example. Against a
six-Pokémon boss team it can reach +5 SpA. **This does not bite here:** Magearna is T7
post-Hall-of-Fame where `postGameCap` is 100 and the hard cap no longer exists, and per §3.1
no boss holds it. If the owner ever moves `magearnite` into capped content, this row must be
revisited and one of the alternatives taken instead.

**Alternative A — Full Metal Body** *(conservative, and the best pick if the snowball is
unwanted)*. Solgaleo's ability: immune to stat reduction, and cannot be bypassed by Mold
Breaker. Thematically perfect for a sealed artificial golem, mechanically clean, and it
removes the snowball entirely — the safest of the three by a distance. `tier: 1`,
onStatusApply.

**Alternative B — Filter** *(strong)*. Cuts super-effective damage by 25%. Steel/Fairy is
weak to only Fire and Ground, and Filter on ten resistances makes it nearly unbreakable.
Precedent exists (Mega Aggron). **RISK:** the most defensively oppressive of the three.

**Rejected:** Levitate (would leave Fire as the *only* weakness on a 700-BST body — too
much, and it duplicates the §4.1 pick); Steelworker (clean but flavourless); Pixilate (its
best moves are already Fairy).

---

### 4.5 Mega Magearna (Original Colour) — Steel/Fairy · BST 700 · T7

| | |
|---|---|
| Base species | Magearna #801, Original Colour — identical typing, stats and ability to the standard colour |
| Base abilities | **Soul-Heart** |
| Champions | **Not shipped**, and no separate ability data exists for the colour variant. |

> ### DECIDED: **Soul-Heart** — identical to §4.4, as the rule below requires
> `abilityStatus: **owner-decided-by-recommendation**`. Shipped spread is byte-identical to the
> standard colour: **80/125/115/170/115/95 (700)**, Steel/Fairy, same stone `magearnite`. **If
> §4.4 ever changes, change this with it.**

**Recommended: Soul-Heart — and the real recommendation is a rule, not an ability.**

> **Original Colour must carry whatever standard Mega Magearna carries. Decide §4.4, then
> copy it here.** Do not differentiate the two colours.

Three reasons. **(1) Champions precedent, directly on point:** Meowstic Male and Female have
*different* ability sets in the mainline games and Champions gave **both** Trace — when
Champions meets a variant pair, it collapses them to one ability. **(2) Mainline canon:**
Original Colour Magearna shares Soul-Heart with the standard colour; there has never been an
ability difference between them. **(3) Player-facing sanity:** the colour is a cosmetic
trophy from Side Mission 195. Making it mechanically distinct turns a skin into a
competitive decision and forces the player to keep two Magearna.

The alternatives are listed only as the mirror of §4.4 — if the owner takes Full Metal Body
there, take Full Metal Body here. **This row should never be ticked independently.**

---

### 4.6 Mega Zeraora — Electric · BST 700 · T7

| | |
|---|---|
| Base species | Zeraora #807 · Electric · 88/112/75/102/80/143 (600) |
| Base abilities | **Volt Absorb** (only ability, no hidden) |
| Mega typing | Electric (unchanged) |
| Assumed Mega stats | base + 100 → BST 700; the fastest thing the player can own |
| Champions | **Not shipped.** Form data exists in the Champions database; Abilities reads *"No abilities listed"*. |
| Rumour | "Speed Boost" — unverified, and rejected on merit below. |

> ### DECIDED: **Transistor** *(`transistor`, tier 1, `onDamageCalc`)* — as recommended
> Shipped spread: **88/157/75/147/80/153 (700)**, Electric, stone `zeraorite`. `abilityStatus:
> owner-decided`.

**Recommended: Transistor** *(`transistor`, tier 1, onDamageCalc)*

Zeraora is the Thunderclap Pokémon — it generates its own current and discharges it through
its paws. Transistor (1.3× Electric moves) is the cleanest possible expression of that, it is
a pure damage multiplier on an existing hook, and transplanting a legendary's signature
ability onto a Mega is confirmed Champions practice (**Fairy Aura → Mega Floette**, §2.2).

The balance property that makes it the right pick is **what it does not fix**: Electric has
the worst offensive coverage of any type — Ground is flatly immune, Grass and Dragon resist.
A 1.3× multiplier on Electric leaves the player still needing a real second answer for every
Ground type in Sinnoh. The ability makes Zeraora *better at what it already does* without
removing a single planning problem.

**Alternative A — Volt Absorb** *(conservative)*. Continuity — its only mainline ability, an
Electric immunity with healing, `tier: 1`, already implemented. Completely safe, and a
genuine answer to Volkner. The cost is the §4.1 problem again: the Mega becomes +100 stats.

**Alternative B — Tough Claws** *(strong — and counter-intuitively the riskiest of the
three)*. 1.3× on contact moves, thematic for a clawed striker, and Champions used it twice
(Barbaracle, Golisopod). **RISK: Tough Claws is more dangerous than Transistor despite the
identical multiplier**, because it boosts Close Combat, Play Rough and every other contact
move — it is **not** walled by the Ground immunity that keeps Transistor honest. If the owner
wants the safer of the two offensive options, that is Transistor.

**Rejected:**

> **Speed Boost is rejected even though it is the circulating rumour.** Two independent
> reasons. **(1) It is redundant:** base Zeraora is already 143 Speed, the fastest Pokémon
> the player can realistically field; +1 Speed a turn buys nothing it does not already have.
> **(2) It is the flagged class:** `mega-design.md` §6.3 lists Mega Blaziken's Speed Boost as
> a snowball that "converts one favourable matchup into a whole-team sweep." Spending
> Zeraora's ability slot on its best stat is the worst of both worlds — mechanically
> pointless *and* in the most-flagged category.

Also rejected: Electric Surge (Champions already gave it to **Mega Raichu X** — duplicate
design, and terrain is a field change); Motor Drive (+1 Speed is wasted for the same reason
as Speed Boost).

---

### 4.7 Mega Tatsugiri (Curly · Droopy · Stretchy) — Dragon/Water · BST 575 · T4

**One decision covering three form rows.** Same treatment as §4.5, same Meowstic precedent:
Curly, Droopy and Stretchy are **purely cosmetic** in the mainline games — identical types,
identical stats, identical abilities. Assign one ability to all three.

| | |
|---|---|
| Base species | Tatsugiri #978 · Dragon/Water · 68/50/60/120/95/82 (475) |
| Base abilities | **Commander** (normal) · **Storm Drain** (hidden) |
| Mega typing | Dragon/Water (unchanged) |
| **Shipped Mega stats** | **68/65/90/135/125/92 = BST 575** (base + 100, as assumed), identical across all three forms |
| Champions | **Not shipped at all** — no database entry; the form returns *"Pokémon not found"*. No ability announced for any Tatsugiri form. |

> ### DECIDED: **Storm Drain** *(`storm-drain`, tier 1, `onTypeImmunity`)* — as recommended, one decision for all three rows
> `abilityStatus: owner-decided`. Storm Drain is **base Tatsugiri's own hidden ability**, so
> nothing new enters the game at a capped checkpoint — which is exactly why it was the
> conservative pick. **Dragon's Maw and Adaptability were both rejected as too strong here.**

> ### This is the only balance-sensitive form of the nine. Read §3.3.
> `tatsugirinite` is **T4** — `badge:mine` / STRENGTH, **cap 78** (`data/level_caps.json`; *44* was
> the vanilla ladder). Unlike the other eight,
> this is mid-game content inside the hard cap, where `mega-design.md` §6.3's argument
> applies at full force: *an ability that changes the rules is worth more than a stat line
> when neither side can out-level the other.* Be conservative here even though the owner can
> afford to be generous everywhere else on this page. **The old §1.5 penalty tier no longer
> applies:** while the form was `pending-owner` it was to ship one tier late (T5); the decision
> below returns it to **T4**.

**Recommended: Storm Drain** *(`storm-drain`, tier 1, onTypeImmunity)*

The best available answer on every axis at once. It is **canon-traceable** — Tatsugiri's own
hidden ability, so nothing is invented. It gives the Mega a **real, legible identity** (a
Water immunity that also pumps SpA when baited) rather than a stat bump. It is **already
implemented** for Gastrodon's line. And it is **safe at T4's cap of 78**: a defensive immunity
plus a conditional boost is a tool the player must set up, not a damage engine, and Water immunity
is a *sideways* answer to Sinnoh's water-heavy mid-game (Wake at cap **54**, the surf encounters)
rather than a way to skip past it.

**Alternative A — Dragon's Maw** *(`dragons-maw`, tier 1, onDamageCalc; the middle option)*.
1.5× Dragon moves — a bigger multiplier than Adaptability's 2× STAB, but on one type only,
and **self-limiting in exactly the right place**: Dragon is resisted by Steel, so it does
nothing to shortcut Byron (cap **66**, Steel), the gym whose badge unlocks this very stone.
**Not taken** — the owner chose Storm Drain.

**Alternative B — Adaptability** *(strong — and it would need a tier bump)*. 2× STAB instead
of 1.5× on Dragon **and** Water, off ~150 SpA. Champions used it for Mega Glimmora, so it is
in-language. **RISK: this was the one proposal on this page I would not ship at its stated
tier.** Double-STAB Draco Meteor and Surf at cap **78**, on a form handed out with Byron's badge,
outclasses anything else available at that point. **Rejected** — and if it is ever revisited,
`tatsugirinite` moves to **T6** (`badge:beacon`) with it; do not take Adaptability *and* keep T4.

**Rejected — and Commander must be rejected on three independent grounds:**

> **Commander cannot be Mega Tatsugiri's ability.**
> **(1) It is inert in this game.** Commander requires an allied **Dondozo** on the field —
> a Doubles-only mechanic — and this is a single-player Platinum remake fought overwhelmingly
> in singles. The ability would do nothing in almost every battle.
> **(2) Our engine cannot run it.** `commander` is **`tier: 2`, `hook: onFieldMisc`** in
> `data/abilities.json` — declared but inert. It needs a bespoke ally-pairing system that
> would exist for exactly one species.
> **(3) It is self-defeating on a Mega.** Commander *removes Tatsugiri from the field* (into
> Dondozo's mouth) and buffs the ally. Spending the battle's one Mega Evolution on a Pokémon
> that then leaves the field is nonsense.
> `mega-design.md` records Mega Tatsugiri as `commander + storm-drain`; as with Heatran
> (§5.1) that is the **base species' normal + hidden ability**, not a Mega ability pair.

Also rejected: Levitate (Dragon/Water has no Ground weakness — it would do literally
nothing); Drizzle / Swift Swim (permanent weather inside a capped tier, the flagged field-change
class); Multiscale (would fix its 68 HP frailty, but duplicates Mega Dragonite and is too strong at
T4).

---

## 5. Section C — findings that amend `mega-design.md`

### 5.1 No Mega in this roster has two abilities — §9 open question 5 dissolves

`mega-design.md` §8.1 and §9 q5 ask whether two-ability Megas need a slot choice or take
both at once, citing **Mega Heatran** (`flash-fire` + `flame-body`) and **Mega Tatsugiri**
(`commander` + `storm-drain`). **Both citations are the same misread:** in each case those
are the *base species'* normal and hidden abilities as they appear in every mainline game,
not a published Mega ability pair. No source anywhere assigns either Mega two abilities, and
none of the 40 Champions rows in §2 has two either.

**Therefore: `abilities` in `data/megas.json` always has length exactly 1** — it was *0 or 1*
while the nine were pending, and all 97 rows now carry one ability. Open question 5 needs no owner
answer and no engine work, and the contract comment in §11.1 (*"a few Z-A Megas have two (e.g.
Mega Heatran)"*) **is still uncorrected as of this pass** — Mega Heatran ships
`["earth-eater"]`. See §7.

### 5.2 Mega Starmie — half of its double gate is released

`conf=uncertain` is resolved: **Huge Power, multi-source-confirmed.** Drop the data flag.
**Keep T7** — §6.3's power objection (Huge Power on a 115-Speed special attacker's body) is
untouched by having confirmed the ability.

### 5.3 The `◊` marker is now retired, and `‡` is the only one left

This section originally split one overloaded marker in two. **The owner's decisions have since
emptied the first half**, and `mega-design.md` §1.5 has been updated to match:

- `◊` **provenance-pending** — **retired. Zero members.** Every one of the 97 rows has a sourced
  ability: canon (48), Champions (40) or owner-decided (9). The *tier placements* R7 produced on
  provenance grounds stay where they are — eight of the nine are T7 on power grounds anyway — but
  **`mega-design.md` R7 is no longer a live rule** and must not be cited for a new stone.
- `‡` **engine-hook-pending** — **also empty now.** It covered the nine tier-3 abilities in §2.1
  plus five canon ones (`delta-stream` `onFieldEnter`, `shadow-tag` `onSwitchAttempt`,
  `parental-bond` / `skill-link` `onMultiHitCount`, `steadfast` `onFlinch`) =
  **14 forms**, of which two were on bosses (`shadow-tag` on Fantina at gym 3, `piercing-drill` on
  Bertha at E2). **All 14 hooks landed on 2026-09-23b**, so rule B9 is satisfied and nothing is
  held out of the build for engine reasons. Keep the marks in `mega-design.md` as a regression
  watchlist, and keep the rule for the next unimplemented ability.

---

## 6. Section D — rejected sources and abilities, recorded

| Rejected | Where it came from | Why it is rejected |
|---|---|---|
| "Enhanced Bad Dreams" (Mega Darkrai) | A single unreliable forum rumour | Not a source under §11.5. Also not implementable — no such ability exists in `data/abilities.json`, and "enhanced" has no defined numbers. |
| **Speed Boost** (Mega Zeraora) | Unverified rumour | **Rejected on merit even if it were confirmed** — §4.6. Base Zeraora is already 143 Speed, so it is redundant *and* it is §6.3's flagged snowball class. |
| **Soul Heart** as a *rumour* (Mega Magearna) | Unverified rumour | The *ability* is what shipped (§4.4) — but on mainline-continuity grounds, not on the rumour's authority. A rumour that merely restates canon adds no evidence, and the leak's other two guesses (Darkrai = Bad Dreams, Zeraora = Speed Boost) are **both** different from what the owner chose. |
| **Power Construct** (Mega Zygarde) | Base species' second ability | Form-changing ability nested inside a Mega form — collides with the §11.2 single form-swap path. Explicit design veto (§4.3). |
| **Commander** (Mega Tatsugiri) | `mega-design.md`, from base Tatsugiri | Doubles-only, `tier: 2` inert in our engine, and it removes the Mega from the field (§4.7). |
| **Shadow Tag** (considered for Mega Darkrai) | Thematic fit only | §6.3: the single worst ability to allow under a hard level cap. `tier: 3` in our data. |
| Any Champions ability for these nine | — | **Champions resolves none of the nine** — which is why all nine fell through to an owner decision (§4). The datamined entries for Darkrai, Magearna and Zeraora all read *"No abilities listed"*; Tatsugiri returns *"not found"*; Heatran's is explicitly unrevealed. A verified gap in Champions, not a research failure. |
| Dated third-party articles as a re-check source | Kotaku's Champions guide et al. | The roster grew twice mid-research; dated articles still list Absol Z / Garchomp Z / Lucario Z / Golisopod / Baxcalibur as unknown. Use the live Serebii/Game8 pages (§2). |

### 6.1 Owner decisions carried in from `DATA_CONTRACT.md` §11.5 — recorded, not open

- **Primal Reversion is OUT.** Primal Groudon and Primal Kyogre are excluded entirely and no
  Red Orb / Blue Orb item is emitted. Not an ability question; recorded here so this file is
  a complete statement of the Mega roster's decided boundaries.
- **Mega Rayquaza is IN, and is the one Mega with no stone.** It Mega Evolves by knowing
  **Dragon Ascent** (`stone: null`, `requiresMove: "dragon-ascent"`). Its ability is mainline
  canon (**Delta Stream**) and it is not a Z-A form, so it needs no entry in §2 or §4.

---

## 7. Section E — what the build must do with this file

| # | Action | Owner |
|---|---|---|
| 1 | Write the 40 §2 rows into `data/megas.json` with `abilityStatus: "champions"`. | **DONE** — verified row-for-row this pass, zero drift. |
| 2 | Write the nine §4 forms from **`data/mega_ability_overrides.json`** with `abilityStatus: "owner-decided"` (6) / `"owner-decided-by-recommendation"` (3). **Assert no form ships `abilities: []` and none carries `pending-owner`** — the old instruction, to ship them empty until §4.0 was ticked, is spent. **Join the override file to `data/megas.json` by form id and assert all nine join** (four ids currently differ — §4.0). | **DONE** (build) / **TODO** (the join test) |
| 3 | Assert every `abilities` entry has length **exactly 1** (§5.1) — `<= 1` as the loose guard. No two-ability Mega exists. | tests |
| 4 | Correct `DATA_CONTRACT.md` §11.1's comment — *"a few Z-A Megas have two (e.g. Mega Heatran)"* is wrong (§5.1). | contract edit |
| 5 | Close `mega-design.md` §9 open question 5 as **dissolved — no answer needed** (§5.1). | doc edit |
| 6 | **DONE (2026-09-23b)** — all nine hooks written: `mega-sol` `onWeatherView`, `dragonize` `onModifyMoveType`, `stalwart` `onRedirect`, `aura-guard` `onDamageCalc`, `piercing-drill` `onProtectCheck`, `eelevate` `onTypeImmunity`, `unseen-fist` `onProtectCheck`, `fire-mane` `onDamageCalc`, `spicy-spray` `onHitTaken`. **Follow-up: four of them (`mega-sol`, `dragonize`, `eelevate`, `fire-mane`) implement mechanics TPC has never published — record the source here or revert them to `tier: 3`** (`mega-design.md` §6.4, ruling G). | engine |
| 7 | Drop Mega Starmie's `conf=uncertain` data flag; **keep it at T7** (§5.2). | build + `mega-design.md` |
| 8 | **Retire `◊` entirely and keep only `‡`** (§5.3) — no form is provenance-pending now. **DONE** in `mega-design.md` §1.5/§3.2 (rule R7 marked retired). | `mega-design.md` |
| 9 | **Confirmed after the fact: none of the nine decisions needed new engine work.** All nine — including the `earth-eater` write-in that was not on this page — are `tier: 1` on an existing hook. Re-verified against `data/abilities.json`. | **DONE** |
| 10 | **Stats for all nine are shipped** in `data/megas.json` and listed in `mega-design.md` §1.4. Mega Darkrai's datamined block (**70/120/130/165/130/85**) is confirmed as shipped; **Mega Zygarde ships 778, not 700** (§4.3). | **DONE** |
| 11 | **Fix the four override-file form ids** so they match `data/megas.json` (§4.0). Data edit, not a doc edit. | build + data |

### 7.1 Re-check calendar

| Date | What changes |
|---|---|
| **2026-12-01** | **Regulation Set M-D** — Mega Heatran becomes Champions' first Legendary Mega. If TPC publishes its ability, §4.1 is **superseded**: Champions is source (1) and outranks any owner decision made now. Re-check Serebii/Game8 then. |
| After M-D | The M-A Legendary/Restricted ban is what keeps Darkrai, Zygarde, Magearna and Zeraora out of Champions. If M-D or a later set lifts it, re-check all four before shipping. |
| No date | Mega Tatsugiri has no Champions entry at all and no announced plan. It is the least likely of the nine to resolve upstream, so treat the §4.7 decision as durable. |

> **Precedence rule.** If Champions later publishes an ability for any of the nine, it
> **overrides** the owner decision recorded here, per §11.5's ordering — including the
> `earth-eater` write-in for Mega Heatran, which M-D is most likely to overturn (§7.1). Update the
> row, move it into §2, change `abilityStatus` from `owner-decided` /
> `owner-decided-by-recommendation` to `champions`, **and update
> `data/mega_ability_overrides.json` in the same commit** so the two never disagree.
