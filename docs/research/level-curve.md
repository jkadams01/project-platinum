# Project Platinum — Level Curve and EXP Economy

**Status:** authoritative level-cap curve. Supersedes the vanilla-scaled cap table in
`docs/research/game-design.md` §2.5 and the current contents of `data/level_caps.json`.
**Scope:** the new 15-row cap table (Task 1) and a computational proof that the EXP economy
can supply it (Task 2).

**What the owner decided, which this document serves**

| # | Requirement | Where |
|---|---|---|
| 4 | Cynthia's team is **all level 100** | §1 |
| 5 | All trainers, bosses and wild Pokémon rescaled so natural progression reaches L100 by Cynthia | §1.4, §2 |
| 3 | **Every** boss fight has six Pokémon | §1.5, §2.3 |
| 7 | Every boss's **ace is Sinnoh-native** (dex 387–493) and is the highest-levelled member | §1.5 |

### Provenance

Every number below is computed, not estimated. Inputs:

* `data/rom/trainers.json` — 928 ROM trainer entries, real parties, species and levels.
* `data/rom/encounters.json` — 183 ROM wild-encounter tables.
* `data/species.json` — veekun `baseExp` and `growthRate` for all 1025 species.
* Progression order and area counts: `docs/research/game-design.md` §1.

Scripts (scratch, in `tools/_work/rebalance/`, reproduced in §5):

| File | Purpose |
|---|---|
| `curve.py` | the curve, the level rescale, and a **party simulation** with hard caps and destroyed surplus |
| `verify.py` | an **independent closed-form model** with a different trainer→segment attribution |
| `optimise.py` | exhaustive search of the legal curve space (4,444 curves) for the shape needing the smallest multiplier |
| `select.py` | final shape selection among the economy-equivalent ties |
| `final.py` | emits every table in this document |

```
python tools/_work/rebalance/optimise.py     # why this curve shape
python tools/_work/rebalance/final.py        # every table below
```

---

## 0. Verdict, up front

**The curve is achievable, but not without a global EXP multiplier. The honest number is ×2.5,
and it only works if party-wide Exp Share is always on.**

| Question | Answer |
|---|---|
| Can the player reach L100 by Cynthia at ×1.00? | **No.** The simulation ends at **level 98**, and the last four cap raises are **structurally locked out** — not slow, impossible (§3.1). |
| Required global multiplier | **×2.42** minimum (realistic mixed-growth team, zero grinding). **×2.5 recommended.** |
| Is a curve shape that avoids the multiplier available? | **No.** Exhaustive search over 4,444 legal curves: the floor is ×1.70, and it is set by the Elite Four gauntlet, which no curve shape can change (§3.1). |
| Multiplier if party-wide Exp Share is *not* adopted | **×6.9–8.0.** Implausible. The sharing rule is not a detail; it is half the answer (§3.2). |
| Does the total EXP budget exist? | Yes — total supply/demand is **1.98** at ×2.5. The problem was never the total; it is the **per-segment** distribution, because a hard cap destroys surplus (49% of all EXP earned is destroyed at ×2.5). |

Demand grows as `n³`; supply grows roughly as `n`. Raising the endpoint from 62 to 100
multiplies demand by **4.20×** while rescaled trainer levels multiply supply by only ~1.6×.
That gap — about 2.6× — is the whole problem, and it is why a multiplier is unavoidable.

---

## 1. Task 1 — the curve

### 1.1 The table

Rule unchanged from `game-design.md` §2.5: **cap = the next checkpoint boss's ace level**, and a
Pokémon at or above the cap gains **zero** EXP. `raisedBy` is the event that *closes* that
window.

| # | checkpoint | location | ace (Gen 4, dex 387–493) | **CAP** | step | vanilla cap | delta | raised by |
|---|---|---|---|---|---|---|---|---|
| 0 | start | Twinleaf Town | — | **18** | — | 14 | +4 | `-` |
| 1 | roark | Oreburgh Gym | Cranidos (#408) 18 | **18** | +0 | 14 | +4 | `badge:coal` |
| 2 | gardenia | Eterna Gym | Roserade (#407) 27 | **27** | +9 | 22 | +5 | `badge:forest` |
| 3 | fantina | Hearthome Gym | Mismagius (#429) 36 | **36** | +9 | 26 | +10 | `badge:relic` |
| 4 | maylene | Veilstone Gym | Lucario (#448) 45 | **45** | +9 | 32 | +13 | `badge:cobble` |
| 5 | crasher_wake | Pastoria Gym | Floatzel (#419) 54 | **54** | +9 | 37 | +17 | `badge:fen` |
| 6 | byron | Canalave Gym | Bastiodon (#411) 66 | **66** | +12 | 41 | +25 | `badge:mine` |
| 7 | candice | Snowpoint Gym | Froslass (#478) 78 | **78** | +12 | 44 | +34 | `badge:icicle` |
| 8 | volkner | Sunyshore Gym | Electivire (#466) 90 | **90** | +12 | 50 | +40 | `badge:beacon` |
| 9 | aaron | Elite Four | Drapion (#452) 96 | **96** | +6 | 53 | +43 | `flag:aaron_defeated` |
| 10 | bertha | Elite Four | Rhyperior (#464) 97 | **97** | +1 | 55 | +42 | `flag:bertha_defeated` |
| 11 | flint | Elite Four | Magmortar (#467) 98 | **98** | +1 | 57 | +41 | `flag:flint_defeated` |
| 12 | lucian | Elite Four | Gallade (#475) 99 | **99** | +1 | 59 | +40 | `flag:lucian_defeated` |
| 13 | **cynthia** | Pokémon League | **Garchomp (#445) 100** | **100** | +1 | 62 | +38 | `flag:hall_of_fame` |
| 14 | post-game | — | — | **100** (uncapped) | +0 | 100 | +0 | `flag:hall_of_fame` |

All thirteen aces are dex 387–493, and each is the highest-levelled member of its party
(requirement 7, verified programmatically — see §1.5).

### 1.2 The shape, and why

Three phases, each with one rule:

```
gyms 1-5   18 -> 27 -> 36 -> 45 -> 54      +9  per gym
gyms 6-8         66 -> 78 -> 90           +12  per gym
Victory Road           -> 96               +6
the gauntlet    97 -> 98 -> 99 -> 100      +1  per member
```

Constraint check:

| Constraint | Status |
|---|---|
| Cynthia exactly 100, whole team 100 | yes |
| Roark in 16–20 | **18** |
| No jump larger than ~12 | max jump **12** |
| Smooth, accelerating | badge phase non-decreasing 9,9,9,9,12,12,12 |
| Four Elite Four caps distinct and rising into 100 | 96, 97, 98, 99 → **100** |
| Post-game uncapped | 100 |

**Why Roark 18 and not higher.** The player starts at 5. A 6-mon party reaching 18 costs
34,242 EXP; segment 1 supplies ~108,000 at ×1.00. Roark could be pushed to 20 and still close,
but gym 1 is where the player has one or two Pokémon, not six, and a cap of 18 already means
Geodude 13 / Onix 14 / Cranidos 18 — a real fight without being a wall.

**Why the jump size steps from +9 to +12 at Byron, and not smoothly.** It tracks the content.
Counting trainer-bearing areas off `game-design.md` §1:

| segment | areas | jump | per-level cost of the step (6 mons) |
|---|---|---|---|
| 1 → roark | 6 | +0 | — |
| 2 → gardenia | 8 | +9 | 9,234 / level |
| 3 → fantina | 7 | +9 | 17,982 |
| 4 → maylene | 5 | +9 | 29,646 |
| 5 → crasher_wake | 4 | +9 | 44,226 |
| 6 → byron | 8 | +12 | 65,016 |
| 7 → candice | 7 | +12 | 93,528 |
| 8 → volkner | 7 | +12 | 127,224 |
| 9 → aaron | 2 | +6 | 155,736 |
| 10–13 gauntlet | **0** | +1 each | ~170,000 |

Segments 6, 7 and 8 hold 22 of the 54 areas — Routes 210N/212/218/219–221, Fuego Ironworks,
Iron Island, the two lake raids, Route 211, Mt. Coronet north, Routes 216/217, Galactic HQ,
Spear Pillar and the Distortion World. That is where the biggest cap raises belong, because
that is where the EXP is. Segment 5 (Routes 213/214, Maniac Tunnel, Valor Lakefront — four
areas) keeps the smaller +9 for the same reason.

**Why the curve decelerates into the League instead of continuing to accelerate.** This is the
one place the brief's "smooth and accelerating" has to yield, and the reason is arithmetic, not
taste. At L96 one party level costs `6 × 3 × 96² ≈ 166,000` EXP. Segments 10–13 contain **zero
routes, zero grass and zero optional trainers** — the only EXP between Aaron and Bertha is
Aaron's six Pokémon, worth 100,039 at ×1.00. A **+2** step there (96→98) costs 338,736 and
would need ×3.39 on its own; sliding the whole gauntlet down so Bertha's cap is 100 and
Aaron's is 91 — a **+9** step — costs 1,478,574 and would need ×14.8. `+1, +1, +1, +1` is the smallest legal rise that still gives the four
members distinct caps, and even that needs the multiplier (§3.1).

**Why Volkner is 90 and not 92 or 95.** Victory Road plus Route 223 is two areas. The +6 it has
to fund is already the second-hardest step in the road phase. Pushing Volkner higher would
shrink that step, but only by making Candice→Volkner exceed the +12 ceiling. Pushing Volkner
*lower* wastes Victory Road: with no cap raise at all there, every Victory Road trainer would
pay zero EXP. +6 is the value that keeps Sinnoh's last dungeon economically alive.

### 1.3 Headroom — no mandatory fight is above the cap in force

The `game-design.md` §2.6 safety check, re-run on the new numbers. Story bosses are rescaled by
**story position**, keeping their headroom as the same fraction of their segment's band.

| fight | segment | vanilla ace | vanilla headroom | new ace | cap in force | new headroom |
|---|---|---|---|---|---|---|
| rival R1 Route 201 | 1 | 5 | +9 | 9 | 18 | +9 |
| rival R2 Route 203 | 1 | 9 | +5 | 13 | 18 | +5 |
| **Roark** | 1 | 14 | +0 | **18** | 18 | **+0** |
| Mars (Windworks) | 2 | 17 | +5 | 21 | 27 | +6 |
| **Gardenia** | 2 | 22 | +0 | **27** | 27 | **+0** |
| Jupiter (Eterna Bldg) | 3 | 23 | +3 | 29 | 36 | +7 |
| **Fantina** | 3 | 26 | +0 | **36** | 36 | **+0** |
| rival R3 Route 209 | 4 | 27 | +5 | 38 | 45 | +7 |
| **Maylene** | 4 | 32 | +0 | **45** | 45 | **+0** |
| rival R4 Pastoria | 5 | 36 | +1 | 52 | 54 | +2 |
| **Crasher Wake** | 5 | 37 | +0 | **54** | 54 | **+0** |
| Cyrus (Celestic) | 6 | 36 | +5 | 51 | 66 | **+15** ⚠ |
| rival R5 Canalave | 6 | 38 | +3 | 57 | 66 | +9 |
| **Byron** | 6 | 41 | +0 | **66** | 66 | **+0** |
| Saturn (Lake Valor) | 7 | 40 | +4 | 62 | 78 | **+16** ⚠ |
| Mars (Lake Verity) | 7 | 40 | +4 | 62 | 78 | **+16** ⚠ |
| **Candice** | 7 | 44 | +0 | **78** | 78 | **+0** |
| Saturn (Galactic HQ) | 8 | 44 | +6 | 78 | 90 | +12 |
| rival R6 Spear Pillar (ally) | 8 | 44 | +6 | 78 | 90 | +12 |
| Cyrus (Galactic HQ) | 8 | 46 | +4 | 82 | 90 | +8 |
| Mars + Jupiter (Spear Pillar) | 8 | 46 | +4 | 82 | 90 | +8 |
| Cyrus (Distortion World) | 8 | 48 | +2 | 86 | 90 | +4 |
| **Volkner** | 8 | 50 | +0 | **90** | 90 | **+0** |
| rival R7 League | 9 | 51 | +2 | 92 | 96 | +4 |
| **Aaron → Cynthia** | 9–13 | 53–62 | +0 | **96 → 100** | 96–100 | **+0 each** |

Every mandatory fight sits at or under the cap: no unwinnable fight, and all thirteen
checkpoints are exactly level-matched, which is the point of the system.

⚠ **Three Galactic fights come out too soft and need a hand fix in the Scale phase.** Cyrus at
Celestic (vanilla 36) is *lower* than Crasher Wake's ace (37) even though he is fought after —
a vanilla lumpiness. Any level-driven rescale inherits it and amplifies it into +15/+16
headroom. Fix: rescale the non-gym story bosses from their **segment**, placing them at
`cap − round(0.35 × band)` — Cyrus Celestic → **62**, Saturn/Mars at the lakes → **74**. This
also slightly increases the EXP supply in segments 6 and 7, which are two of the tighter ones.

**RESOLVED — superseded, and this table is now historical.** The roster-authoring pass
(`tools/_work/rebalance/build_story_rosters.py`) did not use the level-driven rescale at all: it
hand-authors every story boss and **pins each ace to the cap in force**, asserting
`max(level) == cap` and `min(level) >= cap - 3` per team. So the shipped `data/rom/bosses.json`
has Cyrus/Celestic at **66**, Saturn/Lake Valor and Mars/Lake Verity at **78** — headroom **+0**,
not +15/+16. The `cap − round(0.35 × band)` figures above are arithmetically correct (band 12 in
both segments, `round(0.35 × 12) = 4`, giving 62 and 74) but they are now *weaker* than the
shipped data. **Do not apply them** — doing so would lower three bosses by 4 levels and re-open
headroom the authoring pass closed. The ⚠ rows are a projection of an intermediate design that
was replaced, not a description of any shipped file. The `+5/+4` vanilla-headroom and 51/62
"new ace" columns likewise describe that intermediate, not `bosses.json`.

### 1.4 The level rescale the Scale phase implements

One monotone piecewise-linear map from vanilla level to new level, knots at
`(vanilla checkpoint ace, new checkpoint ace)`. Applied to **every** trainer Pokémon and
**every** wild encounter. It needs no knowledge of where a trainer stands in the story — only
the mon's vanilla level — which is why it is safe to apply mechanically.

```
knots (vanilla -> new):
   2 ->   2     14 ->  18     22 ->  27     26 ->  36     32 ->  45     37 ->  54
  41 ->  66     44 ->  78     50 ->  90     53 ->  96     55 ->  97     57 ->  98
  59 ->  99     62 -> 100
```

Because the knots *are* the checkpoint aces, `f(vanilla gym ace) == the new cap` exactly, so
the eight gyms and the League come out level-matched for free with no special-casing.

Worked examples: Route 201 Starly L2–4 → **L2–5**. Wayward Cave Gible L17–20 → **L22–26**.
Victory Road trainers L44–48 → **L80–86**. Vanilla Cynthia's Spiritomb L58 → L98, then
overridden to 100 by requirement 4.

### 1.5 Boss expansion to six (requirement 3) — EXP-model rosters

Levels are `ace−5 … ace`, ace last. These are the rosters the economy was computed against;
**the padded slots are duplicates standing in for baseExp only** — the Boss phase picks the real
species. The ace and the requirement-9 Mega teammate are correct and fixed.

| boss | six-mon roster used in the model | ace |
|---|---|---|
| Roark | Geodude 13, Onix 14, +2 pad, **Cranidos 18** | Cranidos |
| Gardenia | Turtwig 22, Cherrim 23, +3 pad, **Roserade 27** | Roserade |
| Fantina | Duskull 31, Haunter 32, **Gengar 33**, +2 pad, **Mismagius 36** | Mismagius |
| Maylene | Meditite 40, Machoke 41, +3 pad, **Lucario 45** | Lucario |
| Crasher Wake | **Gyarados 49**, Quagsire 50, +3 pad, **Floatzel 54** | Floatzel |
| Byron | Magneton 61, **Steelix 62**, +3 pad, **Bastiodon 66** | Bastiodon |
| Candice | Sneasel 73, Piloswine 74, Abomasnow 75, +2 pad, **Froslass 78** | Froslass |
| Volkner | Jolteon 85, **Raichu 86**, Luxray 87, +2 pad, **Electivire 90** | Electivire |
| Aaron | Yanmega 91, Scizor 92, Vespiquen 93, Heracross 94, +1 pad, **Drapion 96** | Drapion |
| Bertha | Whiscash 92, Gliscor 93, Hippowdon 94, Golem 95, +1 pad, **Rhyperior 97** | Rhyperior |
| Flint | Houndoom 93, Flareon 94, Rapidash 95, Infernape 96, +1 pad, **Magmortar 98** | Magmortar |
| Lucian | Mr. Mime 94, Espeon 95, Bronzong 96, Alakazam 97, +1 pad, **Gallade 99** | Gallade |
| **Cynthia** | Spiritomb 100, Roserade 100, Togekiss 100, Lucario 100, Milotic 100, **Garchomp 100** | Garchomp |

The bolded non-ace members are the requirement-9 Mega teammates (Gengar / Gyarados / Steelix /
Raichu) — present in the model because they change the EXP a boss yields.

---

## 2. Task 2 — the EXP economy

### 2.1 Definitions and the two formulas

Growth (Gen 3+ tables):

```python
def exp_for_level(n, curve='medium-fast'):
    if curve == 'medium-fast': return n**3
    if curve == 'medium-slow': return int(1.2*n**3 - 15*n**2 + 100*n - 140)
    if curve == 'slow':        return int(1.25*n**3)
    if curve == 'fast':        return int(0.8*n**3)
```

Yield, the Gen 5 (Black/White) formula with the scaled-level term:

```python
def gen5_exp(b, L, Lp, trainer=True, share=1.0, s=1, egg=1.0):
    """b  base exp of the fainted mon      L   its level
       Lp level of the mon receiving exp   a   1.5 trainer / 1.0 wild
       share 1.0 participant, 0.5 Exp-All bystander"""
    a = 1.5 if trainer else 1.0
    scaled = ((2.0*L + 10.0)**2.5) / ((L + Lp + 10.0)**2.5)
    return int((b*L)/(5.0*s) * scaled * a * egg * share) + 1
```

The scaled-level term matters enormously here and is usually ignored in romhack balance work.
Under a hard cap the player is *always at or above* the enemy's level, so `Lp ≥ L` always and
the term is always `≤ 1`. It is a standing tax on a level-cap game, worth 10–30% across the
run, and it gets worse the further a fight sits below its cap — which is why the ⚠ rows in
§1.3 cost real EXP as well as difficulty.

**What "supply" means.** One KO delivers one *share unit* to the party. The sharing rule decides
how many units that is:

| sharing rule | units per KO, 6-mon party |
|---|---|
| vanilla Gen 4/5, one participant, no Exp Share | 1.0 |
| Gen 5 Exp Share, one holder | 2.0 |
| **Gen 6+ party-wide Exp Share** (participant 1.0 + five bystanders × 0.5) | **3.5** |
| switch-training — every member tagged into every battle | 6.0 |

### 2.2 (a) EXP required, cap to cap, cumulatively to L100

Six Pokémon, medium-fast (`n³`).

| segment | cap step | per mon | party of 6 | cumulative (6) | vanilla step (6) | × vanilla |
|---|---|---|---|---|---|---|
| roark | 18 → 18 | 0 | 0 | 0 | 0 | — |
| gardenia | 18 → 27 | 13,851 | 83,106 | 83,106 | 47,424 | 1.8× |
| fantina | 27 → 36 | 26,973 | 161,838 | 244,944 | 41,568 | 3.9× |
| maylene | 36 → 45 | 44,469 | 266,814 | 511,758 | 91,152 | 2.9× |
| crasher_wake | 45 → 54 | 66,339 | 398,034 | 909,792 | 107,310 | 3.7× |
| byron | 54 → 66 | 130,032 | 780,192 | 1,689,984 | 109,608 | 7.1× |
| candice | 66 → 78 | 187,056 | 1,122,336 | 2,812,320 | 97,578 | 11.5× |
| volkner | 78 → 90 | 254,448 | 1,526,688 | 4,339,008 | 238,896 | 6.4× |
| aaron | 90 → 96 | 155,736 | 934,416 | 5,273,424 | 143,262 | 6.5× |
| bertha | 96 → 97 | 27,937 | 167,622 | 5,441,046 | 104,988 | 1.6× |
| flint | 97 → 98 | 28,519 | 171,114 | 5,612,160 | 112,908 | 1.5× |
| lucian | 98 → 99 | 29,107 | 174,642 | 5,786,802 | 121,116 | 1.4× |
| cynthia | 99 → 100 | 29,701 | 178,206 | **5,965,008** | 197,694 | 0.9× |

**6 medium-fast mons, L5 → L100 = 5,999,250 EXP. Vanilla L5 → L62 = 1,429,218. Ratio 4.20×.**

The growth curve the party actually uses matters, and a realistic Sinnoh team is *not*
medium-fast:

| growth curve | EXP to L100 | EXP to vanilla L62 | ratio |
|---|---|---|---|
| medium-fast | 1,000,000 | 238,328 | 4.20× |
| medium-slow (all three Sinnoh starters, Lucario, Roserade, Staraptor) | 1,059,860 | 234,393 | 4.52× |
| slow (Garchomp, Gallade, Mamoswine, Abomasnow) | 1,250,000 | 297,910 | 4.20× |
| fast | 800,000 | 190,662 | 4.20× |
| erratic | 600,000 | 209,728 | 2.86× |
| fluctuating (Drifblim, Wailord) | 1,640,000 | 300,293 | 5.46× |

Every scenario below is therefore run twice: once on the brief's `medium-fast × 6`, and once on
a **REAL team** — Infernape, Staraptor, Luxray, Gyarados, Lucario, Roserade — which is five
medium-slow and one slow, and needs **7.0M** rather than 6.0M. The real team is the number to
plan against; medium-fast × 6 is a floor, not a forecast.

### 2.3 (b) EXP available — how supply is modelled

Trainer population, extracted and filtered from the 928 ROM entries:

| step | remaining | dropped |
|---|---|---|
| ROM entries with a real party | 927 | — |
| minus the 30 named story fights (counted separately) | 897 | −30 |
| minus the five Frontier Brain stubs and the `Leader` / `Elite Four` / `Champion` / `Commander` rematch classes | 875 | −22 |
| minus placeholder slots — a lone **Rattata L5** (Rattata is not in the Sinnoh dex; 170 unused table entries use it) | 705 | −170 |
| minus Battle Zone content — ace ≥ 53 (Fight / Survival / Resort Area, Stark Mountain; all post-game) | 536 | −169 |
| minus Vs. Seeker rematch tiers — same class + name, keep the lowest (e.g. *Youngster Tristan* exists at 5 / 24 / 35 / 45) | **392** | −144 |
| **main-story ordinary trainers** | **392 trainers, 736 Pokémon** | |

`curve.py` runs the same filter in a slightly different order and keeps a few more
double-battle partners: **398 trainers, 745 Pokémon**. The two populations differ by 1.2%.

Plus 30 story fights (13 checkpoints expanded to six Pokémon each, 9 Galactic bosses, 7 rival
battles, 1 ally battle), and wild encounters from the 183 ROM tables (mean encounter level 29.1,
mean `baseExp` 108) budgeted at **20 incidental wild KOs per trainer-bearing area** — 1,080
across the run, which is what walking Sinnoh costs you without deliberately grinding.

**Two independent attributions, because this is the weakest link in the model.**
`trainers.json` carries no route association, so which segment a trainer belongs to has to be
inferred. Both inferences are computed and both are reported:

1. `curve.py` — **level bucketing**: a trainer belongs to the vanilla cap window its ace level
   falls in. Faithful to the ROM, but lumpy: vanilla's Byron→Candice window is 3 levels wide yet
   holds seven areas, while Fantina→Maylene is 6 wide and holds five.
2. `verify.py` — **area weighting**: the population is spread over the segments in proportion to
   the trainer-bearing area count from `game-design.md` §1, in vanilla-level order.

If both land on the same multiplier, the verdict does not depend on the attribution. They do.

The simulation enforces the hard cap exactly as the engine must, including the destruction of
surplus:

```python
def grant(self, participant, b, L, cap, trainer=True, exp_all=True, mult=1.0):
    for i in range(len(self.lv)):
        if self.lv[i] >= cap: continue                  # HARD CAP: zero exp
        sh = 1.0 if i == participant else (0.5 if exp_all else 0.0)
        if not sh: continue
        self.exp[i] += gen5_exp(int(b*mult), L, self.lv[i], trainer, sh)
        c = self.curves[i]
        while self.lv[i] < cap and self.exp[i] >= exp_for_level(self.lv[i]+1, c):
            self.lv[i] += 1
        if self.lv[i] >= cap:
            self.exp[i] = exp_for_level(cap, c)         # surplus destroyed
```

The party also ramps 3 → 4 → 5 → 6 members over the first three segments, since nobody has six
Pokémon at Oreburgh.

### 2.4 (c) Supply vs demand — no multiplier

`×1.00`, medium-fast × 6, party-wide Exp Share already assumed:

| segment | cap step | fights | mons KO'd | EXP demand | EXP supply | **ratio** | incidental wilds | forced grind | level reached |
|---|---|---|---|---|---|---|---|---|---|
| roark | 18 → 18 | 55 | 91 | 17,121 | 30,181 | **1.76** | 160 | – | 18 |
| gardenia | 18 → 27 | 64 | 131 | 58,492 | 150,763 | **2.58** | 820 | – | 27 |
| fantina | 27 → 36 | 62 | 123 | 142,381 | 291,036 | **2.04** | 1060 | – | 36 |
| maylene | 36 → 45 | 60 | 122 | 280,702 | 493,765 | **1.76** | 360 | – | 45 |
| crasher_wake | 45 → 54 | 67 | 143 | 398,034 | 813,387 | **2.04** | 340 | – | 54 |
| byron | 54 → 66 | 40 | 90 | 780,192 | 667,108 | **0.86** | 180 | – | 66 |
| candice | 66 → 78 | 17 | 46 | 1,122,336 | 433,099 | **0.39** | 20 | 66 | 78 |
| volkner | 78 → 90 | 37 | 101 | 1,526,688 | 983,065 | **0.64** | 60 | 68 | 90 |
| aaron | 90 → 96 | 22 | 54 | 934,416 | 842,434 | **0.90** | 660 | – | 96 |
| bertha | 96 → 97 | 1 | 6 | 167,622 | 112,963 | **0.67** | 0 | **LOCKED OUT** | 96 |
| flint | 97 → 98 | 1 | 6 | 225,773 | 118,622 | **0.53** | 0 | **LOCKED OUT** | 97 |
| lucian | 98 → 99 | 1 | 6 | 281,793 | 115,148 | **0.41** | 0 | **LOCKED OUT** | 97 |
| cynthia | 99 → 100 | 1 | 6 | 344,851 | 138,808 | **0.40** | 0 | **LOCKED OUT** | 98 |

**TOTAL demand 6,280,401 | supply 5,190,379 | ratio 0.83 | level at Cynthia 98.**

(The League demand figures grow down that table because the party never reaches the previous
cap: `bertha` asks for 96→97, but by `cynthia` the party is still at 98 and owes the whole
99→100 step plus its arrears.)

Same run, REAL mixed-growth team: **level at Cynthia 98**, 243 forced wild battles in the badge
phase (~81 minutes of pure grinding at 20 s/battle), and the same four League segments locked
out.

> Reading the `ratio` column. It is a deliberately pessimistic lower bound: supply is measured
> against an *uncapped shadow party* levelling alongside, which climbs faster and therefore eats
> a larger scaled-level penalty. The authoritative columns are **forced grind** and **level
> reached** — `candice` at ratio 0.91 in §3.3 completes with zero grinding for exactly this
> reason.

Flagged shortfalls at ×1.00: **byron, candice, volkner, aaron, bertha, flint, lucian, cynthia** —
eight of thirteen, i.e. the entire back half of the game.

### 2.5 Per-segment required multiplier

Both models, both growth assumptions, zero grinding allowed:

| segment | sim, medium-fast × 6 | sim, REAL team | closed form, mf × 6 | closed form, REAL |
|---|---|---|---|---|
| roark | 0.30 | 0.25 | 0.32 | 0.37 |
| gardenia | 0.25 | 0.25 | 0.27 | 0.31 |
| fantina | 0.25 | 0.25 | 0.46 | 0.54 |
| maylene | 0.25 | 0.25 | 0.86 | 1.00 |
| crasher_wake | 0.25 | 0.25 | 1.26 | 1.47 |
| byron | 0.51 | 0.63 | 0.99 | 1.15 |
| candice | **1.99** | **2.42** | 1.35 | 1.57 |
| volkner | 1.27 | 1.57 | 1.06 | 1.24 |
| aaron | 0.25 | 0.25 | 1.28 | 1.50 |
| bertha | 1.53 | 1.82 | **1.70** | **1.98** |
| flint | 1.51 | 1.79 | 1.50 | 1.75 |
| lucian | 1.58 | 1.87 | 1.48 | 1.72 |
| cynthia | 1.48 | 1.77 | 1.55 | 1.81 |

The two models disagree about *which* segment binds — `candice` under level bucketing,
`bertha` under area weighting — and that disagreement is exactly the attribution uncertainty,
not a bug. They agree on the number: **the binding requirement is ×1.8–2.4 for a realistic
team.** The first five segments need less than ×1.0 in both models: the early game is
over-supplied no matter what.

---

## 3. The multiplier decision

### 3.1 The Elite Four gauntlet is the floor, and no curve shape moves it

`optimise.py` scores all 4,444 legal curves (Roark 16–20, seven non-decreasing badge-phase jumps
of 4–12, League fixed at 96/97/98/99/100). **The required multiplier bottoms out at ×1.70, and
the binding segment is always inside the gauntlet.** The best shapes differ only in how much
slack they leave on the road; the League floor is a flat ×1.70 for every one of them.

| gauntlet step | demand (6 mons) | the **only** EXP source | its yield ×1.00 | at ×2.5 | ratio at ×2.5 |
|---|---|---|---|---|---|
| → Bertha's cap 97 | 167,622 | Aaron's six Pokémon | 100,039 | 250,097 | 1.49 |
| → Flint's cap 98 | 171,114 | Bertha's six Pokémon | 111,565 | 278,912 | 1.63 |
| → Lucian's cap 99 | 174,642 | Flint's six Pokémon | 116,372 | 290,930 | 1.67 |
| → Cynthia's cap 100 | 178,206 | Lucian's six Pokémon | 112,368 | 280,920 | 1.58 |
| **gauntlet total** | **691,584** | | 440,344 | **1,100,860** | **1.59** |

There is no grass, no water, no optional trainer and no exit inside the Pokémon League. The
gauntlet is **grind-proof**: a player who wants those four levels cannot earn them by playing
better or longer. At ×1.00 the player faces Cynthia at **98**, and requirement 5 fails — not
because the game is stingy but because it is arithmetically impossible.

This is the single strongest argument in the document for a multiplier, and it is also the
strongest argument for the `+1, +1, +1, +1` deceleration in §1.2: any larger rise in the
gauntlet makes the required multiplier grow without bound.

### 3.2 The sharing rule is half the answer

Required global multiplier as a function of the party EXP-sharing rule (closed-form model,
binding segment):

| sharing rule | units/KO | medium-fast × 6 | REAL team |
|---|---|---|---|
| none — vanilla single participant | 1.0 | **×5.94** | **×6.93** |
| Gen 5 Exp Share, one holder | 2.0 | ×2.97 | ×3.46 |
| **Gen 6+ party-wide Exp Share** | 3.5 | **×1.70** | **×1.98** |
| switch-train, all six participate every battle | 6.0 | ×0.99 | ×1.15 |

Simulation agreement, same question asked of the full party sim:

| scenario | zero grinding | ≤30 wild battles | ≤60 wild battles |
|---|---|---|---|
| medium-fast × 6, level-bucket attribution | ×2.38 | ×1.95 | ×1.66 |
| medium-fast × 6, area attribution | ×1.99 | ×1.58 | ×1.58 |
| REAL mixed team, level-bucket | ×2.96 | ×2.43 | ×2.06 |
| **REAL mixed team, area** | **×2.42** | ×1.87 | ×1.87 |
| REAL team, player skips 20% of trainers | ×2.73 | ×1.87 | ×1.87 |
| REAL team, player skips 35% of trainers | ×2.98 | ×1.93 | ×1.87 |
| REAL team, player skips 50% of trainers | ×3.27 | ×2.05 | ×1.87 |
| REAL team, **no** Exp Share (rotate the lead) | ×8.00 (search ceiling) | ×7.43 | ×7.43 |
| REAL team, no Exp Share, switch-train all six | ×1.42 | ×1.12 | ×1.12 |

**`game-design.md` §5.5 currently recommends that party-wide Exp Share be "opt-in or absent".
That recommendation is incompatible with an L100 endpoint and should be reversed.** Without it,
the game needs ×7–8, which would mean a single early trainer filling the cap; or it needs the
player to manually tag all six Pokémon into every battle for ninety hours, which is not a design
so much as a chore. Party-wide Exp Share is the cheapest ×3.5 available and it is standard in
every game since X/Y.

### 3.3 Recommendation: ×2.5, with party-wide Exp Share always on

At `×2.50`, REAL mixed-growth team:

| segment | cap step | fights | mons KO'd | EXP demand | EXP supply | ratio | forced grind | level reached |
|---|---|---|---|---|---|---|---|---|
| roark | 18 → 18 | 55 | 91 | 10,989 | 54,578 | 4.97 | – | 18 |
| gardenia | 18 → 27 | 64 | 131 | 55,511 | 298,794 | 5.38 | – | 27 |
| fantina | 27 → 36 | 62 | 123 | 139,188 | 599,639 | 4.31 | – | 36 |
| maylene | 36 → 45 | 60 | 122 | 285,212 | 1,051,938 | 3.69 | – | 45 |
| crasher_wake | 45 → 54 | 67 | 143 | 418,629 | 1,759,880 | 4.20 | – | 54 |
| byron | 54 → 66 | 40 | 90 | 840,735 | 1,512,777 | 1.80 | – | 66 |
| candice | 66 → 78 | 17 | 46 | 1,232,555 | 1,032,750 | 0.84 | – | 78 |
| volkner | 78 → 90 | 37 | 101 | 1,699,550 | 2,313,241 | 1.36 | – | 90 |
| aaron | 90 → 96 | 22 | 54 | 1,048,385 | 2,026,528 | 1.93 | – | 96 |
| bertha | 96 → 97 | 1 | 6 | 188,566 | 281,254 | 1.49 | – | 97 |
| flint | 97 → 98 | 1 | 6 | 192,639 | 293,305 | 1.52 | – | 98 |
| lucian | 98 → 99 | 1 | 6 | 196,748 | 283,489 | 1.44 | – | 99 |
| cynthia | 99 → 100 | 1 | 6 | 200,912 | 341,251 | 1.70 | – | **100** |

**TOTAL demand 6,509,619 | supply 11,849,424 | ratio 1.82 | 45% of all EXP earned is destroyed
by the caps | level at Cynthia 100, zero forced grinding.**

| multiplier | mf × 6 at Cynthia | REAL team at Cynthia | forced wild battles (REAL) | locked-out segments |
|---|---|---|---|---|
| ×1.00 | 98 | 98 | 243 (~81 min) | bertha, flint, lucian, cynthia |
| ×1.50 | 100 | 99 | 54 (~18 min) | bertha, flint, lucian, cynthia |
| ×2.00 | 100 | 100 | 15 (~5 min) | none |
| **×2.50** | **100** | **100** | **0** | **none** |
| ×3.00 | 100 | 100 | 0 | none |

×2.0 is the minimum that works at all; ×2.5 is the smallest value that works for a realistic
team with **zero** forced grinding and still absorbs a player who skips a fifth of the optional
trainers. Choose ×3.0 instead only if playtesting shows people routinely skipping half the
trainers — at the cost below.

### 3.4 The cost of a flat multiplier, and how to soften it

Over-supply is harmless for *correctness* — the cap clamps it — but it is not free for
*pacing*. How far into each segment the cap starts biting (REAL team):

| mult | roark | gardenia | fantina | maylene | wake | byron | candice | volkner | aaron | bertha | flint | lucian | cynthia |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| ×1.00 | 33% | 43% | 56% | 64% | 62% | never | never | never | never | never | never | never | never |
| ×2.00 | 8% | 22% | 32% | 30% | 34% | 79% | never | 99% | 74% | 100% | 100% | 100% | 100% |
| **×2.50** | **7%** | 18% | 27% | 25% | 28% | 62% | never | 87% | 59% | 83% | 83% | 83% | 83% |
| ×3.00 | 3% | 12% | 22% | 23% | 24% | 51% | never | 77% | 48% | 67% | 67% | 83% | 67% |

At ×2.5 the pre-Roark cap fills after **7%** of segment 1 — roughly four trainers — and the
remaining fifty-odd early-game battles pay nothing. That is the honest cost of a flat
multiplier, and it falls entirely on the first five segments, which need less than ×1.0 (§2.5).

Two ways to keep the number and lose the cost. Either is a small change and neither affects the
proof above, which uses the flat ×2.5 throughout:

1. **Phase it in.** ×1.0 through segments 1–4 (Roark → Maylene, all over-supplied), ×2.5 from
   segment 5 on. The first quarter of the game keeps vanilla pacing; nothing downstream changes.
2. **Scale by distance to cap** — `mult = 1 + 1.5 × (cap − level) / cap`, the Gen 8 catch-up
   idea. Delivers ×2.5 to a party that is behind and ×1.0 to a party at the cap, which is
   exactly where the need is. Slightly more engine work; strictly better feel.

---

## 4. What this requires of the implementation

| # | Rule | Why |
|---|---|---|
| I1 | **Apply the cap raise *before* crediting the defeated boss's EXP.** | The gauntlet's only EXP source is the member you just beat. If the raise lands after, the EXP is clamped by the *old* cap and destroyed, and the four League steps become unreachable at any multiplier. This is the single most important line of code in the system. |
| I2 | **Party-wide Exp Share (Gen 6+ behaviour) is always on**, not an item. | Reverses `game-design.md` §5.5. Worth ×3.5; without it the required multiplier is ×7–8 (§3.2). |
| I3 | Global EXP multiplier **×2.5**, ideally phased or distance-scaled (§3.4). | §3.3. |
| I4 | Zero **EVs** as well as EXP at or above cap. | Already in `game-design.md` §2.7; restated because 45–49% of earned EXP is destroyed and the same must be true of EVs or the cap becomes farmable. |
| I5 | Rescale **non-gym story bosses by segment**, not by vanilla level. | Three Galactic fights otherwise land 15–16 levels under the cap (§1.3 ⚠). |
| I6 | The rescale is the single piecewise-linear map in §1.4, applied to trainers **and** wilds. | Guarantees `f(gym ace) == cap` with no special-casing. |
| I7 | Keep Jupiter's Eterna Building fight behind the Forest Badge. | Unchanged dependency from `game-design.md` §2.6; new ace 29 vs pre-Gardenia cap 27. |

`data/level_caps.json` payload (DATA_CONTRACT §8 shape) is in §6.

---

## 5. The Python

Full sources live in `tools/_work/rebalance/` (scratch, not part of the build):
`curve.py` (395 lines, the simulation), `verify.py` (the independent model), `optimise.py`
(curve search), `select.py`, `final.py` (emits every table here). The load-bearing parts:

**The curve and the rescale**

```python
CAP = [18,18,27,36,45,54,66,78,90,96,97,98,99,100,100]
ACE = [None,18,27,36,45,54,66,78,90,96,97,98,99,100,None]
VANILLA_CAP = [14,14,22,26,32,37,41,44,50,53,55,57,59,62,100]
VANILLA_ACE = [None,14,22,26,32,37,41,44,50,53,55,57,59,62,None]

KNOT_V = [2] + [VANILLA_ACE[i] for i in range(1, 14)]
KNOT_N = [2] + [ACE[i]         for i in range(1, 14)]

def f(L):
    """vanilla level -> new level; monotone piecewise-linear through the knots."""
    if L <= KNOT_V[0]:  return KNOT_V[0]
    if L >= KNOT_V[-1]: return min(100, int(round(KNOT_N[-1] + (L - KNOT_V[-1]))))
    i = bisect.bisect_right(KNOT_V, L) - 1
    v0, v1 = KNOT_V[i], KNOT_V[i+1]
    n0, n1 = KNOT_N[i], KNOT_N[i+1]
    return int(round(n0 + (L - v0) * (n1 - n0) / float(v1 - v0)))
```

**Growth and yield** — as printed in §2.1.

**Six-mon boss rosters, ace last, Gen-4 ace enforced**

```python
def boss_roster(alias):
    t = TR[alias]
    ace_lv = f(max(p['level'] for p in t['party']))
    if alias == 'cynthia': levels = [100]*6
    else: levels = [max(2, ace_lv+o) for o in (-5,-4,-3,-2,-1,0)]
    MEGA_TEAMMATE = {'fantina':94, 'crasher_wake':130, 'byron':208, 'volkner':26}
    ace  = ACE_SPECIES[alias][0]
    rest = [p['species'] for p in t['party'] if p['species'] != ace]
    if alias in MEGA_TEAMMATE and MEGA_TEAMMATE[alias] not in rest:
        rest.append(MEGA_TEAMMATE[alias])
    while len(rest) < 5: rest.append(rest[len(rest) % max(1, len(rest))])
    return list(zip(rest[:5] + [ace], levels))        # ace last == highest level
```

**The hard cap** — `Party.grant`, as printed in §2.3. Surplus is written back down to
`exp_for_level(cap)` so it cannot be banked.

**One segment of the economy**

```python
for i in range(1, 14):
    prev, cap = caps[i-1], caps[i]
    while len(party.lv) < size.get(i, 6):      # party ramps 3 -> 6
        party.add(max(5, prev-4), curves[len(party.lv)])
    demand = party.demand_to(cap)

    st       = stream(i, ordinary, bosses)     # (baseExp, level) of every mon defeated
    absorbed = 0
    for n, (b, L) in enumerate(st):
        absorbed += party.grant(n % len(party.lv), b, L, cap, True, exp_all, mult)

    used = 0                                   # incidental wilds, 20 per area
    while used < free and not party.at(cap):
        party.grant(used % len(party.lv), wbe, wlv, cap, False, exp_all, mult)
        used += 1
    grind = 0                                  # forced grinding beyond that
    while i < 10 and not party.at(cap) and grind < grind_limit:
        party.grant(grind % len(party.lv), wbe, wlv, cap, False, exp_all, mult)
        grind += 1
    # i >= 10: no wild encounters exist inside the Pokemon League -> stuck
```

**Solving for the multiplier**

```python
def required_mult(caps=None, curves=None, exp_all=True, skip=0.0, max_grind=60, **kw):
    """Smallest global multiplier clearing every checkpoint with <= max_grind forced
       wild battles per segment, and zero inside the League."""
    lo, hi = 0.5, 8.0
    for _ in range(40):
        mid  = (lo+hi)/2.0
        rows = simulate(caps, mid, curves, exp_all, skip, **kw)
        ok   = all((not r['stuck']) and r['grind'] <= max_grind for r in rows)
        if ok: hi = mid
        else:  lo = mid
    return hi
```

**The curve search** (`optimise.py`) enumerates Roark 16–20 × seven non-decreasing jumps of
4–12 with Volkner ≤ 95, scores each on `max(required multiplier per segment)`, and reports the
frontier. 4,444 curves are legal; the minimum is ×1.70 and it is set by the gauntlet.

---

## 6. `data/level_caps.json` payload

```json
{ "caps": [
  {"index":0,"checkpoint":"start","location":"Twinleaf Town","ace":null,"cap":18,"raisedBy":null},
  {"index":1,"checkpoint":"roark","location":"Oreburgh Gym","ace":"Cranidos 18","cap":18,"raisedBy":"badge:coal"},
  {"index":2,"checkpoint":"gardenia","location":"Eterna Gym","ace":"Roserade 27","cap":27,"raisedBy":"badge:forest"},
  {"index":3,"checkpoint":"fantina","location":"Hearthome Gym","ace":"Mismagius 36","cap":36,"raisedBy":"badge:relic"},
  {"index":4,"checkpoint":"maylene","location":"Veilstone Gym","ace":"Lucario 45","cap":45,"raisedBy":"badge:cobble"},
  {"index":5,"checkpoint":"crasher_wake","location":"Pastoria Gym","ace":"Floatzel 54","cap":54,"raisedBy":"badge:fen"},
  {"index":6,"checkpoint":"byron","location":"Canalave Gym","ace":"Bastiodon 66","cap":66,"raisedBy":"badge:mine"},
  {"index":7,"checkpoint":"candice","location":"Snowpoint Gym","ace":"Froslass 78","cap":78,"raisedBy":"badge:icicle"},
  {"index":8,"checkpoint":"volkner","location":"Sunyshore Gym","ace":"Electivire 90","cap":90,"raisedBy":"badge:beacon"},
  {"index":9,"checkpoint":"aaron","location":"Elite Four","ace":"Drapion 96","cap":96,"raisedBy":"flag:aaron_defeated"},
  {"index":10,"checkpoint":"bertha","location":"Elite Four","ace":"Rhyperior 97","cap":97,"raisedBy":"flag:bertha_defeated"},
  {"index":11,"checkpoint":"flint","location":"Elite Four","ace":"Magmortar 98","cap":98,"raisedBy":"flag:flint_defeated"},
  {"index":12,"checkpoint":"lucian","location":"Elite Four","ace":"Gallade 99","cap":99,"raisedBy":"flag:lucian_defeated"},
  {"index":13,"checkpoint":"cynthia","location":"Pokemon League","ace":"Garchomp 100","cap":100,"raisedBy":"flag:hall_of_fame"},
  {"index":14,"checkpoint":"post-game","location":null,"ace":null,"cap":100,"raisedBy":"flag:hall_of_fame"}
 ],
 "postGameCap": 100,
 "rule": "hard-xp-stop",
 "expMultiplier": 2.5,
 "expShare": "party-wide"
}
```

`expMultiplier` and `expShare` are **proposed additions** to the DATA_CONTRACT §8 shape. They
belong next to the caps because they are not tuning knobs — at the wrong value the cap table is
unreachable. If the contract owner prefers, they can live in a separate `data/exp_rules.json`;
what matters is that they are data, versioned beside the curve they make possible.

---

## 7. Risks and open items

1. **Trainer→segment attribution is the weakest input.** `trainers.json` has no route mapping;
   both models infer it, and they disagree about which segment binds (§2.5). Once
   `data/maps/*.json` carries `objects[].script` for trainer NPCs, re-run `final.py` with a real
   mapping — the headline multiplier should move by less than ±0.3, but the *shape* recommendation
   for segments 5–9 could tighten.
2. **The 20-wilds-per-area budget is an assumption, not a measurement.** At 0 incidental wilds
   the required multiplier rises to roughly ×3.2; at 40 it falls to ~×2.1. Worth a playtest count.
3. **`mega-design.md` §4.2–4.3 conflicts with owner requirements 7 and 9.** It permutes Crasher
   Wake's Gyarados and Byron's Steelix *to the top level* (making a non-Gen-4 species the ace)
   and substitutes Excadrill onto Bertha. Requirement 7 says the ace is the highest-levelled
   member and must be dex 387–493; requirement 9 says Wake's ace is Floatzel and Byron's is
   Bastiodon with the Mega on a non-ace teammate. The cap table here follows the owner. That
   document also states it "changes no cap" and reasons against the vanilla numbers throughout —
   its §4.6 symmetry table needs re-running against this curve.
4. **The padded boss slots in §1.5 are baseExp placeholders.** The Boss phase must choose real
   sixth/fifth members; if it picks high-`baseExp` species the economy improves slightly, and if
   it picks low-`baseExp` ones the gauntlet floor (§3.1) tightens. Re-run `final.py` once the
   real rosters exist.
5. **Cynthia's flat L100 team costs the player nothing in EXP terms** — her fight is the last,
   and post-game is uncapped. But it makes her six Pokémon the highest-`baseExp` yield in the
   game at 100; if a post-game rematch exists, it will be the best EXP source by a wide margin.
6. **Erratic and fluctuating growth curves are outliers.** Bastiodon is *erratic* (600,000 to
   L100, only 2.86× its vanilla L62 cost) and Drifblim is *fluctuating* (1,640,000, 5.46×).
   A party built from fluctuating-curve species needs about ×3.0, not ×2.5. This is a per-species
   fairness wrinkle the flat multiplier cannot fix; it is inherent to the vanilla growth tables.
7. **Level 100 removes the level-up learnset tail.** Nothing learns a move above ~L80 in most
   lines, so the last 20 levels are pure stats. If the Move phase wants late-game moves to feel
   earned, `learnsets.json` needs hand additions in the 85–100 band — otherwise the back third of
   the curve is numerically large and mechanically silent.
