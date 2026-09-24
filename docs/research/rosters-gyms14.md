# Rebalanced rosters - Gyms 1-4 (Roark, Gardenia, Fantina, Maylene)

**Scope:** the first four boss fights of the raised level curve. Six Pokemon each, ace at the
checkpoint cap, non-aces within 3 levels below it. Every species, ability, item and move was
legality-checked against `data/species.json`, `data/learnsets.json` and `data/moves.json` by
`tools/_work/rebalance/build_gyms14.py` - all assertions pass.

| Gym | Leader | Type | Cap / ace level | Ace (Gen 4) | Mega | Stone awarded |
|---|---|---|---|---|---|---|
| 1 | **Roark** | Rock | **18** | Cranidos 18 | - (no Ring yet) | `aerodactylite` |
| 2 | **Gardenia** | Grass | **27** | Roserade 27 | - (no Ring yet) | `victreebelite` |
| 3 | **Fantina** | Ghost | **36** | Mismagius 36 | **Mega Gengar** (L35, non-ace) | `gengarite` |
| 4 | **Maylene** | Fighting | **45** | Lucario 45 | **Mega Lucario** (the ace) | `lucarionite` |

The Mega Ring is handed over by Dawn/Lucas **immediately after Fantina**, so Fantina is the first
boss the player watches Mega Evolve while unable to answer it, and Maylene is the first
Mega-vs-Mega fight. That is the intended step change.

---

## Roark - Rock gym, cap 18

| # | Pokemon | Dex | Gen | Types | Lv | Ability | Item | Moves |
|---|---|---|---|---|---|---|---|---|
| 1 | Roggenrola | 524 | 5 | Rock | **16** | Sturdy | `oran-berry` | Stealth Rock, Smack Down, Rock Blast, Sand Attack |
| 2 | Geodude | 74 | 1 | Rock/Ground | **15** | Sturdy | `oran-berry` | Defense Curl, Rollout, Rock Tomb, Bulldoze |
| 3 | Onix | 95 | 1 | Rock/Ground | **16** | Sturdy | `oran-berry` | Rock Tomb, Smack Down, Screech, Dragon Breath |
| 4 | Tyrunt | 696 | 6 | Rock/Dragon | **17** | Strong Jaw | `oran-berry` | Bite, Ancient Power, Rock Tomb, Charm |
| 5 | Klawf | 950 | 9 | Rock | **17** | Anger Shell | `oran-berry` | Rock Tomb, Metal Claw, Rock Smash, Smack Down |
| 6 | **Cranidos** (ACE) | 408 | 4 | Rock | **18** | Mold Breaker | `sitrus-berry` | Rock Slide, Take Down, Headbutt, Scary Face |

**Design.** Send-out order is party order. Roggenrola leads to set **Stealth Rock** - a six-Pokemon Rock gym with hazards is the game's first real lesson in switching cost. Cranidos closes: 125 base Attack, **Mold Breaker** (so Sturdy leads do not save you) and Rock Slide. Tyrunt (Gen 6) and Klawf (Gen 9) are the cross-gen guests; Klawf's 450 BST makes it the wall of the fight, and **Anger Shell** turns a failed 2HKO into a +1/+1 attacker. There is no Fire coverage anywhere on the team - deliberate, so a Turtwig player is not punished for taking the canonical easy pick.

## Gardenia - Grass gym, cap 27

| # | Pokemon | Dex | Gen | Types | Lv | Ability | Item | Moves |
|---|---|---|---|---|---|---|---|---|
| 1 | Grotle | 388 | 4 | Grass | **25** | Overgrow | `oran-berry` | Sunny Day, Seed Bomb, Bite, Reflect |
| 2 | Cherrim | 421 | 4 | Grass | **25** | Flower Gift | `sitrus-berry` | Solar Beam, Weather Ball, Magical Leaf, Morning Sun |
| 3 | Eldegoss | 830 | 8 | Grass | **25** | Regenerator | `sitrus-berry` | Energy Ball, Cotton Spore, Leaf Tornado, Light Screen |
| 4 | Lilligant | 549 | 5 | Grass | **26** | Chlorophyll | `sitrus-berry` | Energy Ball, Stun Spore, Growth, Synthesis |
| 5 | Brambleghast | 947 | 9 | Grass/Ghost | **26** | Wind Rider | `oran-berry` | Seed Bomb, Shadow Sneak, Rapid Spin, Leech Seed |
| 6 | **Roserade** (ACE) | 407 | 4 | Grass/Poison | **27** | Natural Cure | `sitrus-berry` | Giga Drain, Sludge Bomb, Dazzling Gleam, Synthesis |

**Design.** Built around **sun**, which vanilla Gardenia already gestures at (her ROM Turtwig carries Sunny Day). Grotle leads and sets it; Cherrim then gets **Flower Gift** (+50% Atk and SpD to the whole team) with instant Solar Beam and a Fire-type 100 BP Weather Ball, and Lilligant doubles its Speed with **Chlorophyll**. Eldegoss is the **Regenerator** pivot, Brambleghast (Gen 9) is a Grass/Ghost that ignores Normal and Fighting answers, and Roserade closes with 125 SpA plus Poison STAB for the Fairy and Grass switch-ins. Lilligant runs **Stun Spore, not Sleep Powder** - Sleep Powder was deliberately withheld at gym 2.

## Fantina - Ghost gym, cap 36

| # | Pokemon | Dex | Gen | Types | Lv | Ability | Item | Moves |
|---|---|---|---|---|---|---|---|---|
| 1 | Drifblim | 426 | 4 | Ghost/Flying | **34** | Aftermath | `sitrus-berry` | Will-O-Wisp, Shadow Ball, Air Slash, Strength Sap |
| 2 | Cofagrigus | 563 | 5 | Ghost | **34** | Mummy | `sitrus-berry` | Will-O-Wisp, Hex, Body Press, Nasty Plot |
| 3 | Houndstone | 972 | 9 | Ghost | **34** | Fluffy | `sitrus-berry` | Poltergeist, Crunch, Play Rough, Will-O-Wisp |
| 4 | Mimikyu | 778 | 7 | Ghost/Fairy | **34** | Disguise | `sitrus-berry` | Swords Dance, Shadow Claw, Play Rough, Drain Punch |
| 5 | **MEGA GENGAR** | 94 | 1 | Ghost/Poison | **35** | Cursed Body | `gengarite` | Shadow Ball, Sludge Bomb, Thunderbolt, Dazzling Gleam |
| 6 | **Mismagius** (ACE) | 429 | 4 | Ghost | **36** | Levitate | `sitrus-berry` | Nasty Plot, Shadow Ball, Mystical Fire, Dazzling Gleam |

**Design.** The debut Mega fight. Fantina keeps **Mismagius** as her Gen 4 ace (105/105/105 with Nasty Plot) and Mega Evolves **Gengar** in the 5th slot, one level below the ace, so the Mega arrives before the closer rather than as the closer. Duskull and Haunter are retired: Dusclops needs L37, above this cap, and Haunter's slot is upgraded into the Gengar that carries the Gengarite. Drifblim (150 HP, Strength Sap), Cofagrigus (145 Def, Will-O-Wisp into Hex), Houndstone (Gen 9) and Mimikyu (Gen 7, **Disguise** plus Swords Dance) fill out a team with two burn spreaders and one free turn built in. **Last Respects is explicitly excluded** from Houndstone's set.

## Maylene - Fighting gym, cap 45

| # | Pokemon | Dex | Gen | Types | Lv | Ability | Item | Moves |
|---|---|---|---|---|---|---|---|---|
| 1 | Medicham | 308 | 3 | Fighting/Psychic | **42** | Pure Power | `sitrus-berry` | High Jump Kick, Zen Headbutt, Ice Punch, Thunder Punch |
| 2 | Machamp | 68 | 1 | Fighting | **43** | Guts | `black-belt` | Close Combat, Knock Off, Rock Slide, Bulk Up |
| 3 | Scrafty | 560 | 5 | Dark/Fighting | **43** | Intimidate | `sitrus-berry` | Drain Punch, Crunch, Poison Jab, Bulk Up |
| 4 | Hawlucha | 701 | 6 | Fighting/Flying | **44** | Limber | `sitrus-berry` | Flying Press, Throat Chop, Swords Dance, Roost |
| 5 | Annihilape | 979 | 9 | Fighting/Ghost | **44** | Vital Spirit | `sitrus-berry` | Close Combat, Shadow Claw, Drain Punch, Bulk Up |
| 6 | **MEGA LUCARIO** (ACE) | 448 | 4 | Fighting/Steel | **45** | Steadfast | `lucarionite` | Close Combat, Crunch, Ice Punch, Flash Cannon |

**Design.** The first Mega-vs-Mega fight and the hardest of the four. Her ace **Lucario** Mega Evolves for **Adaptability** - Close Combat at exactly your level is the biggest single hit in the first half of the game - and it runs **no setup move**: Swords Dance was withheld on purpose. Medicham brings **Pure Power** and the elemental punches, Machamp is **Guts** (No Guard plus Dynamic Punch was also withheld), Scrafty has **Intimidate** and 115/115 defences, Hawlucha is the speed control at 118, and Annihilape (Gen 9) is her tech answer to the Psychic-types a player brings to beat a Fighting gym. **Rage Fist is excluded** from Annihilape's set.

---

## Balance notes and flags

- **Roark is a long fight, not a hard one.** Six Pokemon at L15-18 against an L18-capped player is roughly triple vanilla's HP pool, and Roggenrola (280 BST) and Geodude (300 BST) are deliberately thin so the attrition stays survivable. Budget Potions, not a wipe.

- **Cranidos with Mold Breaker and Rock Slide** at level-matched 18 will 2HKO most things and OHKO frail Flying-types. That is the intended ace spike, and Sturdy will not stop it.

- **Gardenia's sun stacks three abilities at once** (Flower Gift, Chlorophyll, and Solar Beam / Weather Ball). If it swings too hard in playtest the single lever is Grotle's Sunny Day - drop it and the whole engine idles.

- **Fantina's Mega Gengar has Shadow Tag**, which stops the player switching at all. This is the one genuinely questionable item on these four teams: `mega-design.md` section 6.3 calls Shadow Tag *the single worst ability to allow under a level cap*, and its ruling **B9** forbids giving a boss an ability whose engine hook is not written. Two acceptable resolutions: (a) implement `shadow-tag` before gym 3 ships, or (b) run Fantina's Mega Gengar on **Cursed Body**, its base ability, and reserve Shadow Tag for the player's own Gengarite. Either one keeps the owner's requirement that Fantina Mega Evolves Gengar and awards Gengarite.

- **Direct conflict with `mega-design.md` ruling B8**, which reads *no boss Mega Evolves before `badge:relic` is set - Roark, Gardenia and Fantina never Mega, in any circumstance.* The owner's decision (gym leaders Mega Evolve from gym 3 onward, and Fantina is gym 3) overrides it. `mega-design.md` section 4.1 ruling B8 and the Fantina row of section 4.2 both need editing to match, and the Mega Ring gift moves to **immediately after Fantina**.

- **Maylene is the difficulty peak of the first four.** Pure Power Medicham, Guts Machamp, a Fighting/Ghost, and an Adaptability Mega Lucario, all at 42-45 against a cap of 45. She is beatable with Psychic/Flying/Fairy coverage plus one physically bulky answer, but a player who brings six Fighting-weak Pokemon loses. Recommend the pre-gym NPC in Veilstone flag *bring something that can take a punch*.

- **Medicham's High Jump Kick** is the single biggest damage roll on any of the four teams (Pure Power, 130 BP, level-matched). Its 50%-HP crash on a miss is what keeps it fair - do not swap it for Drain Punch and then buff something else to compensate.

- **Two hidden abilities are used**: Houndstone `fluffy` and Scrafty `intimidate`. `DATA_CONTRACT.md` section 7 types trainer `ability` as a slot integer (`0` / `1`), which cannot express either. Either widen section 7 to accept an ability slug (or `2` for hidden), or fall back to Houndstone `sand-rush` (inert - Fantina has no sand) and Scrafty `shed-skin`. Every other ability across these 24 Pokemon is slot 0 or slot 1.

- **Items are all consumable or low-impact** (`oran-berry`, `sitrus-berry`, `black-belt`) except the two Mega Stones. No Leftovers, no Choice items and no Focus Sash anywhere in the first four gyms - those are held back for later, when the player has more tools.

- **Stone awards are unchanged from the owner's fixed list**: Roark gives `aerodactylite`, Gardenia `victreebelite`, Fantina `gengarite`, Maylene `lucarionite`. Roark and Gardenia hand over stones for Megas they do not use themselves, because the player has no Ring until after Fantina - both are dormant rewards at the moment they are given, which is worth a line of NPC dialogue foreshadowing the Ring.

- **No excluded gimmick appears anywhere**: no Dynamax, Gigantamax, Z-Move or Terastal data, and exactly one Mega per Mega-capable boss.
