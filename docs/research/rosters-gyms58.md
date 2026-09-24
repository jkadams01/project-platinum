# Boss rosters — Gyms 5–8 (Wake · Byron · Candice · Volkner)

**Status:** authored against the NEW cap table (Wake 54 / Byron 66 / Candice 78 / Volkner 90).
**Codes against:** `docs/DATA_CONTRACT.md` §7 (`data/rom/trainers.json` party shape), §8 (cap table),
§11 (Mega Evolution).
**Verified against:** `data/species.json` (types, abilities) and `data/learnsets.json` (every move,
every mon, at the listed level) via `tools/_work/rebalance/val58.py`. No illegal move, no illegal
ability, no move whose only source is a level-up entry above the holder's level.
**Mega forms used:** `gyaradosite`, `steelixite`, `froslassite`, `raichunite-y` — all four are
XY/ORAS or confirmed in `docs/research/mega-design.md` §4.2, which assigns exactly these four Megas
to exactly these four leaders.

---

## Rules applied

| Rule | How it lands here |
|---|---|
| Exactly 6 per boss | 6 / 6 / 6 / 6. Vanilla had 3 / 3 / 4 / 4. |
| Ace AT the cap, rest within ~3 below | Wake 51–54 · Byron 63–66 · Candice 75–78 · Volkner 87–90 |
| Ace must be Sinnoh-native (387–493) | Floatzel 419 · Bastiodon 411 · Froslass 478 · Electivire 466 |
| One Mega per boss | Wake → Gyarados (teammate) · Byron → Steelix (teammate) · **Candice → Froslass (ACE)** · Volkner → Raichu (teammate) |
| Type identity preserved | Wake all-Water · Byron all-Steel · Candice all-Ice · Volkner all-Electric |
| Cross-gen is the selling point | 12 of the 24 slots are non-Gen-4, spanning Gens 1, 2, 6, 7, 8 and 9 |

---

## 5. Crasher Wake — Pastoria Gym · Water · cap **54** · awards Fen Badge + **Gyaradosite**

Send-out order is party order; ace last.

| # | Pokémon | Dex | Gen | Types | Lv | Ability | Item | Moves |
|---|---|---|---|---|---|---|---|---|
| 1 | Quagsire | 195 | 4 | Water/Ground | 51 | Unaware | Leftovers | Earthquake · Waterfall · Yawn · Rest |
| 2 | Clawitzer | 693 | 6 | Water | 51 | Mega Launcher | Assault Vest | Water Pulse · Dark Pulse · Dragon Pulse · Aura Sphere |
| 3 | Barraskewda | 847 | 8 | Water | 52 | Swift Swim | Mystic Water | Liquidation · Close Combat · Psychic Fangs · Aqua Jet |
| 4 | Basculegion | 902 | 8 | Water/Ghost | 52 | Adaptability | Expert Belt | Wave Crash · Phantom Force · Crunch · Aqua Jet |
| 5 | **Gyarados** | 130 | 1 | Water/Flying | 53 | Intimidate | **Gyaradosite** → **MEGA** | Waterfall · Crunch · Earthquake · Ice Fang |
| 6 | **Floatzel — ACE** | 419 | 4 | Water | **54** | Swift Swim | Life Orb | Liquidation · Ice Punch · Crunch · Aqua Jet |

**Mega Gyarados** — Water/**Dark**, 640 BST, **Mold Breaker**. Mold Breaker is the point: it turns
off the exact abilities a level-capped player builds a Water answer around (Water Absorb, Storm
Drain, Levitate, Sturdy, Filter). Deliberately **no Dragon Dance** — a Mold Breaker Mega at
level-matched parity with a setup move is a snowball, so the threat stays tactical, not exponential.

**Deliberate omission: no rain.** No Pelipper, no Politoed, no Rain Dance anywhere on the team. Two
Swift Swimmers (Barraskewda, Floatzel) under auto-rain at level 52–54 would outspeed every legal
player team simultaneously. Wake keeps his Swift Swimmers and loses his weather.

---

## 6. Byron — Canalave Gym · Steel · cap **66** · awards Mine Badge + **Steelixite**

| # | Pokémon | Dex | Gen | Types | Lv | Ability | Item | Moves |
|---|---|---|---|---|---|---|---|---|
| 1 | Magnezone | 462 | 4 | Electric/Steel | 63 | Analytic | Assault Vest | Thunderbolt · Flash Cannon · Body Press · Volt Switch |
| 2 | Tinkaton | 959 | 9 | Fairy/Steel | 64 | Mold Breaker | Leftovers | Gigaton Hammer · Play Rough · Thunder Wave · Stealth Rock |
| 3 | Corviknight | 823 | 8 | Flying/Steel | 64 | Mirror Armor | Rocky Helmet | Brave Bird · Iron Head · Bulk Up · Roost |
| 4 | Aegislash | 681 | 6 | Steel/Ghost | 65 | Stance Change | Leftovers | King's Shield · Sacred Sword · Shadow Ball · Iron Head |
| 5 | **Steelix** | 208 | 2 | Steel/Ground | 65 | Sturdy | **Steelixite** → **MEGA** | Earthquake · Heavy Slam · Stone Edge · Iron Defense |
| 6 | **Bastiodon — ACE** | 411 | 4 | Rock/Steel | **66** | Sturdy | Leftovers | Metal Burst · Iron Head · Stone Edge · Body Press |

**Mega Steelix** — Steel/Ground, 610 BST, **Sand Force**. Per `mega-design.md` §3.3 this converts the
*Onix is a pre-badge-1 catch* hazard into the fight's reward: the player meets the wall before owning
the stone. **Sand Force is intentionally dry** — Byron runs no sand setter, so the ability
contributes nothing and Mega Steelix is pure 230-base-Defense wall. That is the fight.

**Bastiodon is a passive ace and that is the design.** Metal Burst punishes the biggest hit the
player throws, Body Press converts 168 base Defense into offence, and Sturdy guarantees it acts
once. The fight is a wall-breaking puzzle, not a damage race — which is why it is the one gym here
whose ace has no Mega and does not need one.

**Deliberate omission: no Excadrill.** `mega-design.md` §4.3 substitutes Mega Excadrill onto Bertha
(E2). A non-Mega Excadrill on Byron, three fights earlier, muddies that reveal.

---

## 7. Candice — Snowpoint Gym · Ice · cap **78** · awards Icicle Badge + **Froslassite**

**The one gym in 5–8 where the ACE Mega Evolves** — Froslass is Gen 4 *and* has a Mega, so
requirement 9's first branch applies.

| # | Pokémon | Dex | Gen | Types | Lv | Ability | Item | Moves |
|---|---|---|---|---|---|---|---|---|
| 1 | Abomasnow | 460 | 4 | Grass/Ice | 75 | Snow Warning | Life Orb | Blizzard · Wood Hammer · Ice Shard · Earthquake |
| 2 | Frosmoth | 873 | 8 | Ice/Bug | 76 | Ice Scales | Leftovers | Blizzard · Bug Buzz · Giga Drain · Quiver Dance |
| 3 | Weavile | 461 | 4 | Dark/Ice | 76 | Pressure | Life Orb | Triple Axel · Knock Off · Ice Shard · Low Kick |
| 4 | Cetitan | 975 | 9 | Ice | 77 | Slush Rush | Assault Vest | Ice Spinner · Earthquake · Liquidation · Heavy Slam |
| 5 | Baxcalibur | 998 | 9 | Dragon/Ice | 77 | Thermal Exchange | Expert Belt | Glaive Rush · Icicle Crash · Earthquake · Dragon Claw |
| 6 | **Froslass — ACE** | 478 | 4 | Ice/Ghost | **78** | Cursed Body → **MEGA** | **Froslassite** | Blizzard · Shadow Ball · Will-O-Wisp · Destiny Bond |

**Mega Froslass** — Ice/Ghost, 580 BST, **Snow Warning**. Note the ability swap: base Froslass has
Snow Cloak / Cursed Body, so the *party* entry carries **Cursed Body** and the Mega form supplies
Snow Warning on transform (contract §11.2: "swap types, base stats, ability").

**The snow engine, stated plainly.** Abomasnow opens with Snow Warning; Cetitan doubles its Speed
under it (Slush Rush); Blizzard is 100% accurate in snow on three members; snow gives every Ice-type
on the field +50% Defense. Froslass re-establishes snow in the last slot if it has lapsed. This is
the most *systemic* gym team in the game — it wins with a battlefield, not a stat line, exactly as
`mega-design.md` §4.2 argues (580 is the lowest boss Mega in the game and still the scariest of the
Ice options).

---

## 8. Volkner — Sunyshore Gym · Electric · cap **90** · awards Beacon Badge + **Raichunite Y AND Raichunite X**

| # | Pokémon | Dex | Gen | Types | Lv | Ability | Item | Moves |
|---|---|---|---|---|---|---|---|---|
| 1 | Jolteon | 135 | 1 | Electric | 87 | Volt Absorb | Choice Specs | Thunderbolt · Shadow Ball · Volt Switch · Hyper Voice |
| 2 | Luxray | 405 | 4 | Electric | 87 | Intimidate | Expert Belt | Wild Charge · Crunch · Ice Fang · Play Rough |
| 3 | Vikavolt | 738 | 7 | Bug/Electric | 88 | Levitate | Assault Vest | Thunderbolt · Bug Buzz · Energy Ball · Air Slash |
| 4 | Toxtricity | 849 | 8 | Electric/Poison | 88 | Punk Rock | Throat Spray | Overdrive · Boomburst · Sludge Bomb · Volt Switch |
| 5 | **Raichu** | 26 | 1 | Electric | 89 | Static | **Raichunite Y** → **MEGA** | Thunder · Focus Blast · Grass Knot · Volt Switch |
| 6 | **Electivire — ACE** | 466 | 4 | Electric | **90** | Motor Drive | Life Orb | Wild Charge · Ice Punch · Earthquake · Cross Chop |

**Mega Raichu Y** — Electric, 585 BST, **No Guard**. Sent **5th, immediately before Electivire**, per
`mega-design.md` §4.2 rule **B4**: Electivire is Volkner's identity and must stay the closer, so the
Mega goes in the slot before it rather than displacing the ace.

**Two changes from `mega-design.md` §4.2, both forced by data:**

1. §4.2 sells Mega Raichu Y on *"Zap Cannon guaranteed"*. **`data/learnsets.json` gives Raichu no
   Zap Cannon** — not level-up, not TM, not tutor, not egg. The set instead uses **Thunder (100%
   under No Guard) + Focus Blast (100% under No Guard)**, which is the same idea, legally.
2. **No Nasty Plot**, though Raichu learns it at level 1. No Guard + Nasty Plot + 110 SpA at level 89
   against a level-90-capped team is a one-mon sweep. The Mega stays a perfect-accuracy nuke, not a
   setup snowball.

**Stone award conflict, flagged.** Requirement 8 has Volkner award **both** Raichunite Y and
Raichunite X. `mega-design.md` §3.4 currently places `raichunite-x` as a **T5 overworld item ball on
the Sunyshore solar panels**. Requirement 8 is the owner's decision and wins: both stones come from
Volkner, and the Sunyshore solar-panel ball needs a new occupant (or deletion) in the §3.4 stone
table. Follow-up for whoever regenerates that table.

---

## Cross-generation coverage (the selling point, audited)

| Gen | Slots | Members |
|---|---|---|
| 1 | 3 | Gyarados, Jolteon, Raichu |
| 2 | 1 | Steelix |
| 4 | 9 | Quagsire, Floatzel, Magnezone, Bastiodon, Abomasnow, Weavile, Froslass, Luxray, Electivire |
| 6 | 2 | Clawitzer, Aegislash |
| 7 | 1 | Vikavolt |
| 8 | 5 | Barraskewda, Basculegion, Corviknight, Frosmoth, Toxtricity |
| 9 | 3 | Tinkaton, Cetitan, Baxcalibur |

All four **aces** are Gen 4 / Sinnoh-native (419, 411, 478, 466). Requirement 7 holds.

---

## Balance flags

Ranked by how likely each is to be the thing that stops a player.

| # | Risk | Where | Judgement |
|---|---|---|---|
| 1 | **Candice is the hardest gym in the ladder.** Permanent snow + Slush Rush Cetitan + Ice Scales Frosmoth + Baxcalibur + a Mega ace. Six Ice-types sharing weaknesses is normally a flaw, but snow converts the shared type into a shared +50% Defense buff. | §7 | **Ship it, but it is the tuning candidate.** If playtesting breaks here, the cut is Baxcalibur → Mamoswine (Gen 4, Thick Fat) — removes a second Dragon-tier attacker without touching the snow engine. |
| 2 | **Frosmoth's Quiver Dance.** Ice Scales already halves special damage; +1 SpA/SpD/Speed on top, in snow, at level 76, is the scariest non-ace set here. | §7 slot 2 | **Watch, do not cut.** Frosmoth's 4× Rock and 4× Fire weaknesses and 60/65 physical bulk are the intended out. |
| 3 | **Destiny Bond on a Mega ace.** Mega Froslass dying and taking the player's answer with it, at the end of a six-mon gym, is legal, canon and extremely annoying. | §7 slot 6 | **Keep.** It costs her a turn and only pays off if she is already dying. Substitute is the swap if it tests badly. |
| 4 | **Punk Rock Boomburst at level 88.** Throat Spray means the first Boomburst boosts SpA for the second. | §8 slot 4 | **Keep.** Toxtricity is slow (75 Speed) and any Ghost-type is flatly immune to Boomburst — a real, findable answer. |
| 5 | **Mold Breaker Mega Gyarados** disabling Water Absorb / Levitate / Sturdy is a *category* removal, not a stat check — the player may not understand why their wall stopped working. | §5 slot 5 | **Keep, but telegraph it.** A pre-battle Wake line about "nothing to hide behind" earns its keep. |
| 6 | **Byron's fight is long, not hard.** Five of six members are defensive; Mega Steelix has no recovery and Bastiodon's Iron Defense / Body Press shape can stall. | §6 | **Acceptable.** A capped player at 66 with any Fire / Fighting / Ground move clears it. The risk is boredom, not loss. If it drags, drop Steelix's Iron Defense for Dig. |
| 7 | **Nothing here is unfair by level.** Every ace sits exactly at its cap and every teammate 1–3 below, so a capped player meets each gym level-matched or ahead — the §2.6 guarantee holds unchanged. | all | **Clear.** |

---

## Emission notes for `data/rom/trainers.json` (§7)

* `ability` in §7 is an **index** (`"ability": 0`). These rosters name abilities by slug because
  several use the **hidden** slot — Quagsire (Unaware), Magnezone (Analytic), Corviknight (Mirror
  Armor), Frosmoth (Ice Scales), Froslass (Cursed Body). The writer must map slug → slot index
  against `data/species.json`, not assume 0.
* The Mega member carries the stone in `item` and needs the `megaForm` field (`mega-design.md` §9):
  `gyarados-mega`, `steelix-mega`, `froslass-mega`, `raichu-mega-y`.
* Volkner's Raichu must be **party index 4** (5th send-out). Order matters for rule B4.
* `prizeMoney` scales with the new ace levels and is not set here.
