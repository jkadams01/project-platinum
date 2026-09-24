# Project Platinum — Game Design Reference

**Status:** authoritative content & rules reference for the Sinnoh remake.
**Scope:** progression order, boss ladder, level caps, HM removal, cross-gen encounter placement, early-game balance.

**Headline features this document serves**

| # | Feature | Where covered |
|---|---|---|
| A | Gen 5 visual style | out of scope here (see art docs) — but drives §4 tonal rules |
| B | Hard level caps at boss fights; at/above cap = **zero exp** | §2 |
| C | HMs removed entirely; badge-gated automatic traversal | §3 |
| D | Pokémon from all 9 generations available | §4, §5 |

### Provenance of the numbers

Every boss level, party, and wild encounter table in this document was **extracted from the owner's own US Platinum cartridge dump** (`CPUE`, 462 files) rather than transcribed from a wiki. Wiki sources were used only to confirm *story order* and *HM gate locations*.

* Trainers: `/poketool/trainer/trdata.narc` + `/poketool/trainer/trpoke.narc` (928 entries).
* Species names: `/msgdata/pl_msg.narc` file **412** (496 entries).
* Wild encounters: `/fielddata/encountdata/pl_enc_data.narc` (183 entries, 424 bytes each).
* Extractor: `tools/_work/ndsfs.py` + `dump5.py` (scratch, gitignored). **Nothing ROM-derived is ever committed.**

One correction to the commonly-cited wiki data was found and is reflected below: **Bertha's ace in Platinum is Rhyperior L55, not Hippowdon L55** (ROM: Whiscash 50, Gliscor 53, Hippowdon 52, Golem 52, Rhyperior 55). The cap number is unchanged at 55.

---

## 1. Sinnoh progression order — the map build order

This is the intended visit order, with the gate that opens each step. Build the maps in this order; anything marked *(optional)* can be deferred to a later milestone without blocking the critical path.

| # | Location | Type | Gate to enter | Notable content |
|---|---|---|---|---|
| 1 | Twinleaf Town | Town | — | Start, rival's house |
| 2 | Route 201 | Route | Leave house | **Rival battle 1** (starter only, L5) |
| 3 | Lake Verity | Dungeon-lite | Follow Rowan | Starter obtained; Mesprit cutscene |
| 4 | Sandgem Town | Town | — | Pokédex, Rowan's lab |
| 5 | Route 202 | Route | Pokédex | Catching tutorial |
| 6 | Jubilife City | City | — | Pokétch, Trainers' School, Galactic intro |
| 7 | Route 203 | Route | — | **Rival battle 2** (Starly 7 / starter 9) |
| 8 | Oreburgh Gate 1F / B1F | Cave | — (through-path is clear) | Rock Smash HM in vanilla; water side-rooms |
| 9 | Oreburgh City | City | — | Mining museum |
| 10 | Oreburgh Mine | Cave | — | Find Roark |
| 11 | **Oreburgh Gym — Roark** | Gym | — | **Coal Badge → SMASH** |
| 12 | Jubilife City (return) | City | Coal Badge | Galactic grunts cleared, Route 204 opens |
| 13 | Route 204 (south) | Route | — | |
| 14 | **Ravaged Path** | Cave | **SMASH** (rocks block the only through-route) | Hard gate — see §3 |
| 15 | Route 204 (north) | Route | Ravaged Path | |
| 16 | Floaroma Town | Town | — | |
| 17 | Floaroma Meadow | Route | Galactic grunts | **Works Key** |
| 18 | Route 205 (south) | Route | — | |
| 19 | Valley Windworks | Dungeon | Works Key | **Boss: Mars** (Purugly 17) |
| 20 | Route 205 (north) | Route | Windworks cleared | |
| 21 | Eterna Forest | Dungeon | — | Cheryl partner escort |
| 22 | Eterna City | City | — | |
| 23 | **Eterna Gym — Gardenia** | Gym | — | **Forest Badge → CUT** |
| 24 | Team Galactic Eterna Building | Dungeon | **CUT** (trees block the door) | **Boss: Jupiter** (Skuntank 23); Rad Rickshaw → **Bicycle** |
| 25 | Old Chateau *(optional)* | Dungeon | CUT | Rotom |
| 26 | Route 206 (Cycling Road) | Route | Bicycle | |
| 27 | Wayward Cave *(optional)* | Cave | Bicycle (hidden entrance) | **Gible** L17–20 |
| 28 | Route 207 | Route | — | |
| 29 | Mt. Coronet (south) | Cave | — (through-path clear) | |
| 30 | Route 208 | Route | — | |
| 31 | Hearthome City | City | — | Contest Hall, Amity Square, Eevee gift |
| 32 | **Hearthome Gym — Fantina** | Gym | — | **Relic Badge → (fog deleted; see §3.4)** |
| 33 | Route 209 | Route | — | **Rival battle 3** (starter 27) |
| 34 | Lost Tower *(optional)* | Dungeon | — | |
| 35 | Solaceon Town / Solaceon Ruins | Town / Dungeon | — | Defog HM in vanilla; Unown |
| 36 | Route 210 (south) | Route | — | |
| 37 | Route 215 | Route | — | |
| 38 | Veilstone City | City | — | Galactic Warehouse (Fly HM in vanilla), Game Corner |
| 39 | **Veilstone Gym — Maylene** | Gym | — | **Cobble Badge → FLY** |
| 40 | Route 214 / Maniac Tunnel | Route / Cave | — | |
| 41 | Valor Lakefront | Route | — | Hotel Grand Lake |
| 42 | Route 213 | Route | — | |
| 43 | Pastoria City | City | — | **Rival battle 4** (starter 36) |
| 44 | **Pastoria Gym — Crasher Wake** | Gym | — | **Fen Badge → SURF** |
| 45 | Great Marsh *(optional)* | Safari | — | |
| 46 | Route 212 (south) | Route | — | Loops back to Hearthome |
| 47 | Valor Lakefront (return) | Route | — | Galactic blockade event |
| 48 | Route 210 (north) | Route | **Secret Potion** (Psyduck blockade); fog is cosmetic and deleted | Café Cabin |
| 49 | Celestic Town | Town | — | **Boss: Cyrus** (Murkrow 36); Surf HM in vanilla |
| 50 | Fuego Ironworks *(optional)* | Dungeon | **SURF** | |
| 51 | Routes 219 / 220 / 221 *(optional)* | Sea routes | **SURF** | |
| 52 | Route 218 | Sea route | **SURF** (mandatory to reach Canalave) | |
| 53 | Canalave City | City | — | Library, Sailor |
| 54 | Iron Island | Dungeon | Sailor | Riley partner escort; Strength HM in vanilla; Riolu egg |
| 55 | **Canalave Gym — Byron** | Gym | — | **Mine Badge → STRENGTH** |
| 56 | Lake Valor | Dungeon | Story flag | **Boss: Saturn** (Toxicroak 40) |
| 57 | Lake Verity (return) | Dungeon | Story flag | **Boss: Mars** (Purugly 40) |
| 58 | Route 211 | Route | — | |
| 59 | Mt. Coronet (north) | Cave | **SMASH + STRENGTH** | |
| 60 | Route 216 | Snow route | — | |
| 61 | Route 217 | Blizzard route | — | Rock Climb HM in vanilla |
| 62 | Acuity Lakefront | Route | — | |
| 63 | Snowpoint City | City | — | |
| 64 | **Snowpoint Gym — Candice** | Gym | — | **Icicle Badge → CLIMB** |
| 65 | Lake Acuity | Dungeon | — | Jupiter (scripted, no battle); rival defeated |
| 66 | Veilstone — Team Galactic HQ | Dungeon | Galactic Key | **Bosses: Saturn** (Toxicroak 44), **Cyrus** (Honchkrow 46); lake trio freed |
| 67 | Mt. Coronet (south → summit) | Dungeon | **SURF + STRENGTH + CLIMB** | Long interior climb |
| 68 | Spear Pillar | Dungeon | — | **Bosses: Mars + Jupiter** (double, Barry as partner, aces 46); **Cyrus**; Giratina abduction |
| 69 | Distortion World | Dungeon | — | **Boss: Cyrus** (Weavile 48); Giratina |
| 70 | Sendoff Spring *(optional)* | Dungeon | — | |
| 71 | Route 222 | Route | — | |
| 72 | Sunyshore City | City | — | Jasmine |
| 73 | **Sunyshore Gym — Volkner** | Gym | — | **Beacon Badge → WATERFALL** |
| 74 | Route 223 | Sea route | **SURF** | |
| 75 | Pokémon League (south) | Hub | 8 Badges | **Rival battle 5** (starter 51) |
| 76 | Victory Road | Dungeon | **none** — the through-route is walkable (see the §3 correction note); the optional loops want SURF / SMASH / STRENGTH / CLIMB / WATERFALL | |
| 77 | Pokémon League (north) | Gauntlet | Clear Victory Road | **Elite Four → Cynthia** |

Post-game (Fight / Survival / Resort Areas, Stark Mountain, Turnback Cave, Snowpoint Temple, Pal Park) sits behind the Hall of Fame and is a later milestone.

---

## 2. Boss ladder and the level cap table

### 2.1 Gym Leaders (ROM-verified, full teams)

> **§2.1–§2.4 are the VANILLA teams, kept as ROM provenance only.** They are not what
> ships. The shipped rosters are six Pokemon each, on the raised curve, in
> `data/rom/bosses.json` and `docs/research/rosters-gyms14.md`, `rosters-gyms58.md`,
> `rosters-e4.md`, `rosters-story.md`. The live cap table is §2.5.

Send-out order is party order; the **ace is the last / highest** member.

| Badge | # | Leader | City | Type | Full team (ROM) | **Ace level** | Trainer ID |
|---|---|---|---|---|---|---|---|
| Coal | 1 | Roark | Oreburgh | Rock | Geodude 12, Onix 12, **Cranidos 14** | **14** | 246 |
| Forest | 2 | Gardenia | Eterna | Grass | Turtwig 20, Cherrim 20, **Roserade 22** | **22** | 315 |
| Relic | 3 | Fantina | Hearthome | Ghost | Duskull 24, Haunter 24, **Mismagius 26** | **26** | 318 |
| Cobble | 4 | Maylene | Veilstone | Fighting | Meditite 28, Machoke 29, **Lucario 32** | **32** | 317 |
| Fen | 5 | Crasher Wake | Pastoria | Water | Gyarados 33, Quagsire 34, **Floatzel 37** | **37** | 316 |
| Mine | 6 | Byron | Canalave | Steel | Magneton 37, Steelix 38, **Bastiodon 41** | **41** | 250 |
| Icicle | 7 | Candice | Snowpoint | Ice | Sneasel 40, Piloswine 40, Abomasnow 42, **Froslass 44** | **44** | 319 |
| Beacon | 8 | Volkner | Sunyshore | Electric | Jolteon 46, Raichu 46, Luxray 48, **Electivire 50** | **50** | 320 |

> Platinum-specific ordering: **Fantina is gym 3**, Maylene gym 4. (In Diamond/Pearl they are 5th and 3rd.) Getting this wrong is the single most common mistake when porting Sinnoh data.

### 2.2 Elite Four and Champion (ROM-verified)

| # | Member | Type | Full team (ROM) | **Ace level** | Trainer ID |
|---|---|---|---|---|---|
| E1 | Aaron | Bug | Yanmega 49, Scizor 49, Vespiquen 50, Heracross 51, **Drapion 53** | **53** | 261 |
| E2 | Bertha | Ground | Whiscash 50, Gliscor 53, Hippowdon 52, Golem 52, **Rhyperior 55** | **55** | 262 |
| E3 | Flint | Fire | Houndoom 52, Flareon 55, Rapidash 53, Infernape 55, **Magmortar 57** | **57** | 263 |
| E4 | Lucian | Psychic | Mr. Mime 53, Espeon 55, Bronzong 54, Alakazam 56, **Gallade 59** | **59** | 264 |
| CH | **Cynthia** | Mixed | Spiritomb 58, Roserade 58, Togekiss 60, Lucario 60, Milotic 58, **Garchomp 62** | **62** | 267 |

### 2.3 Team Galactic bosses (ROM-verified)

| Order | Boss | Location | Team | Ace | Trainer ID |
|---|---|---|---|---|---|
| G1 | Mars | Valley Windworks | Zubat 15, **Purugly 17** | 17 | 295 |
| G2 | Jupiter | Galactic Eterna Building | Zubat 21, **Skuntank 23** | 23 | 406 |
| G3 | Cyrus | Celestic Town | Sneasel 34, Golbat 34, **Murkrow 36** | 36 | 913 |
| G4 | Saturn | Lake Valor | Golbat 38, Bronzor 38, **Toxicroak 40** | 40 | 408 |
| G5 | Mars | Lake Verity | Golbat 38, Bronzor 38, **Purugly 40** | 40 | 405 |
| G6 | Saturn | Galactic HQ, Veilstone | Golbat 42, Bronzor 42, **Toxicroak 44** | 44 | 409 |
| G7 | Cyrus | Galactic HQ, Veilstone | Sneasel 44, Crobat 44, **Honchkrow 46** | 46 | 403 |
| G8 | Mars + Jupiter | Spear Pillar (double) | Bronzor 44, Golbat 44, **Purugly 46** / Bronzor 44, Golbat 44, **Skuntank 46** | 46 | 528 + 407 |
| G9 | **Cyrus** | Distortion World | Houndoom 45, Honchkrow 47, Crobat 46, Gyarados 46, **Weavile 48** | 48 | 404 |

### 2.4 Rival (Barry) — story battles (ROM-verified)

Teams shown for the **Turtwig** player (Barry takes Chimchar); the other two branches are identical in level, swapping the starter line and the Roselia / Ponyta slot.

| # | Location | Team | Ace | Trainer ID |
|---|---|---|---|---|
| R1 | Route 201 | **Chimchar 5** | 5 | 851 |
| R2 | Route 203 | Starly 7, **Monferno 9** | 9 | 248 |
| R3 | Route 209 | Staravia 25, Buizel 23, Roselia 23, **Monferno 27** | 27 | 471 |
| R4 | Pastoria City | Staravia 34, Buizel 32, Roselia 32, **Monferno 36** | 36 | 474 |
| R5 | Canalave City | Staraptor 36, Floatzel 35, Heracross 37, Roserade 35, **Infernape 38** | 38 | 477 |
| R6 | Spear Pillar *(ally, not opponent)* | Munchlax 40, Staraptor 42, Floatzel 40, Heracross 42, Roserade 40, **Infernape 44** | 44 | 619 |
| R7 | Pokémon League | Staraptor 48, Floatzel 47, Heracross 48, Roserade 47, Snorlax 49, **Infernape 51** | 51 | 480 |

### 2.5 THE LEVEL CAP TABLE  <!-- raised-curve -->

> **THIS TABLE IS THE RAISED CURVE. The curve terminates at level 100.**
> Cynthia's team is **all level 100**, and every trainer and wild encounter in Sinnoh is
> scaled so that natural progression brings the player to 100 by the time they face her.
> Exp awards are multiplied by **2.5** before the cap is tested (`expMultiplier` in
> `data/level_caps.json`) — that multiplier is what makes the curve reachable without
> grinding. The derivation, the exp-supply model and the per-area scaling live in
> **`docs/research/level-curve.md`**; the boss teams behind each ace live in
> `data/rom/bosses.json` and `docs/research/rosters-*.md`.
>
> The vanilla-scaled table this replaces (Roark 14 … Cynthia 62) is kept only as
> provenance in §2.1–§2.4, which are verbatim ROM dumps of the *original* teams.

**Rule:** a Pokémon whose current level is **greater than or equal to the active cap gains
zero experience** from every source. A Pokémon at `cap − 1` still gains exp and may level
*into* the cap, then stops. **Maximum reachable level = the cap.** Cap equals the next
checkpoint boss's ace level — the standard level-cap-hack convention, which means you may
always meet a boss exactly level-matched, never above.

| # | Checkpoint (the fight the cap is set for) | Location | Ace | **CAP** | Raised by |
|---|---|---|---|---|---|
| 0 | *(game start)* | Twinleaf | — | **18** | — |
| 1 | **Roark** | Oreburgh Gym | Cranidos 18 | **18** | **Coal Badge** |
| 2 | **Gardenia** | Eterna Gym | Roserade 27 | **27** | **Forest Badge** |
| 3 | **Fantina** | Hearthome Gym | Mismagius 36 | **36** | **Relic Badge** |
| 4 | **Maylene** | Veilstone Gym | Lucario 45 | **45** | **Cobble Badge** |
| 5 | **Crasher Wake** | Pastoria Gym | Floatzel 54 | **54** | **Fen Badge** |
| 6 | **Byron** | Canalave Gym | Bastiodon 66 | **66** | **Mine Badge** |
| 7 | **Candice** | Snowpoint Gym | Froslass 78 | **78** | **Icicle Badge** |
| 8 | **Volkner** | Sunyshore Gym | Electivire 90 | **90** | **Beacon Badge** |
| 9 | **Aaron** | Elite Four | Drapion 96 | **96** | flag: aaron defeated |
| 10 | **Bertha** | Elite Four | Rhyperior 97 | **97** | flag: bertha defeated |
| 11 | **Flint** | Elite Four | Magmortar 98 | **98** | flag: flint defeated |
| 12 | **Lucian** | Elite Four | Gallade 99 | **99** | flag: lucian defeated |
| 13 | **Cynthia** | Pokemon League | Garchomp 100 | **100** | flag: hall of fame |
| 14 | *(post-game)* | — | — | **100** (terminal) | flag: hall of fame |

**Every ace is a Sinnoh-native Gen 4 species** (national dex 387–493) and **every boss fields
six Pokémon**. From Fantina (gym 3) onward every gym leader and Elite Four member Mega
Evolves, and each gym leader awards a fixed Mega Stone on defeat — see §2.8.

**Why per-member caps inside the Elite Four work.** You gain exp *during* the gauntlet, so each
cap raise is live and meaningful — you enter the League at ≤96 and climb to 100 by the time you
reach Cynthia, but only by actually winning the four fights. A single flat "100 for the whole
League" cap would let you grind to 100 before Aaron and trivialise E1–E3.

### 2.6 Cap verification — every mandatory fight sits at or under the cap in force

Regenerated from `data/rom/bosses.json` against the raised cap table. The safety check that
"cap = next checkpoint ace" never produces an unwinnable fight. Headroom 0 means the fight is
exactly level-matched, which is the intent for every checkpoint boss.

| Fight | Ace | Cap in force | Headroom | OK? |
|---|---|---|---|---|
| Barry (Route 201) | 18 | 18 | +0 | yes — level-matched |
| Barry (Route 203) | 18 | 18 | +0 | yes — level-matched |
| **Roark** | 18 | 18 | +0 | yes — level-matched |
| Mars (Valley Windworks) | 27 | 27 | +0 | yes — level-matched |
| **Gardenia** | 27 | 27 | +0 | yes — level-matched |
| Jupiter (Galactic Eterna Building) | 36 | 36 | +0 | yes — level-matched |
| **Fantina** | 36 | 36 | +0 | yes — level-matched |
| Barry (Route 209) | 45 | 45 | +0 | yes — level-matched |
| **Maylene** | 45 | 45 | +0 | yes — level-matched |
| Barry (Pastoria City) | 54 | 54 | +0 | yes — level-matched |
| **Crasher Wake** | 54 | 54 | +0 | yes — level-matched |
| Cyrus (Celestic Town) | 66 | 66 | +0 | yes — level-matched |
| Barry (Canalave City) | 66 | 66 | +0 | yes — level-matched |
| **Byron** | 66 | 66 | +0 | yes — level-matched |
| Saturn (Lake Valor) | 78 | 78 | +0 | yes — level-matched |
| Mars (Lake Verity) | 78 | 78 | +0 | yes — level-matched |
| **Candice** | 78 | 78 | +0 | yes — level-matched |
| Saturn (Galactic HQ, Veilstone) | 90 | 90 | +0 | yes — level-matched |
| Cyrus (Galactic HQ, Veilstone) | 90 | 90 | +0 | yes — level-matched |
| Mars (Spear Pillar) | 90 | 90 | +0 | yes — level-matched |
| Jupiter (Spear Pillar) | 90 | 90 | +0 | yes — level-matched |
| Cyrus (Distortion World) | 90 | 90 | +0 | yes — level-matched |
| Barry (Spear Pillar) | 90 | 90 | +0 | yes — level-matched |
| **Volkner** | 90 | 90 | +0 | yes — level-matched |
| Barry (Pokemon League gate) | 96 | 96 | +0 | yes — level-matched |
| **Aaron** | 96 | 96 | +0 | yes — level-matched |
| **Bertha** | 97 | 97 | +0 | yes — level-matched |
| **Flint** | 98 | 98 | +0 | yes — level-matched |
| **Lucian** | 99 | 99 | +0 | yes — level-matched |
| **Cynthia** | 100 | 100 | +0 | yes — level-matched |
| Charon (Stark Mountain) | 100 | 100 | +0 | yes — level-matched |

**The one dependency to enforce in script order:** Jupiter's Eterna Building fight (ace 36)
must remain **after** Gardenia, because the pre-Gardenia cap is 27. In vanilla Platinum it
already is — the Galactic building's door is behind Cut trees, and Cut is the Forest Badge
reward. Keep that dependency intact and this table holds for free.

**Barry R1 and R2 are the known exception.** Both sit at the cap (18) while the player is
still on their starter, so as vanilla-placed they are not winnable at parity — see the W1/W2
balance warnings in `docs/research/rosters-story.md`.

### 2.7 Cap implementation notes

* Zero the **EV** gain as well as the exp gain at/above cap, or the cap becomes a soft cap you can farm around.
* Rare Candy / Exp. Candy: refuse to apply at or above cap.
* Trading in an over-cap Pokémon: clamp its exp gain to zero. Obedience stays a separate, badge-gated system (§3.6).
* Surface the cap in the UI: party and summary screens read `Lv.14 (CAP)` in a distinct colour; the battle exp bar must visibly not move.
* **Evolution is not capped.** A Pokémon that evolves at the cap level still evolves; only exp is zeroed.
* Day-care exp is zeroed at/above cap too.

---

### 2.8 Mega Evolution on the boss ladder — DECIDED

Mega Evolution is the **only** gimmick in the game (DATA_CONTRACT §11). The Mega Ring is given
by the player's NPC counterpart (**Dawn/Lucas**) in Hearthome City after **Fantina, gym 3** —
authored as `data/events/mega_ring.json`, documented in DATA_CONTRACT §12. Nothing before gym 3
Mega Evolves, on either side.

Every boss's **ace stays Gen 4**. Only 9 Gen 4 species have a Mega form, so where the ace has
no Mega the Mega rides a **non-ace teammate** — and that teammate is the species whose stone the
leader awards.

| # | Leader | Ace (Gen 4) | Mega carrier | Form | Awards |
|---|---|---|---|---|---|
| 3 | **Roark** | Cranidos 18 | — | — | `aerodactylite` |
| 5 | **Gardenia** | Roserade 27 | — | — | `victreebelite` |
| 7 | **Fantina** | Mismagius 36 | Gengar | gengar-mega | `gengarite` |
| 9 | **Maylene** | Lucario 45 | Lucario | lucario-mega | `lucarionite` |
| 11 | **Crasher Wake** | Floatzel 54 | Gyarados | gyarados-mega | `gyaradosite` |
| 14 | **Byron** | Bastiodon 66 | Steelix | steelix-mega | `steelixite` |
| 17 | **Candice** | Froslass 78 | Froslass | froslass-mega | `froslassite` |
| 24 | **Volkner** | Electivire 90 | Raichu | raichu-mega-y | `raichunite-y`, `raichunite-x` |

Cynthia uses **Mega Garchomp (X/Y, `garchompite`, Dragon/Ground)** — not Mega Garchomp Z.


## 3. HM removal design

**Principle:** no HM items exist, no move slots are consumed, no HM slave exists. Each *badge* grants a **traversal verb** that the player character performs automatically on walking into the matching obstacle. The obstacle is a property of the map, not of the party. Badge order is unchanged from vanilla, so **route order is preserved exactly**.

> ### ⚠ CORRECTION (adversarial verification pass, 2026-09-23) — Victory Road gates nothing
>
> This section originally repeated Bulbapedia's line that **Victory Road requires Surf,
> Strength, Rock Smash, Waterfall and Rock Climb**. **That is wrong**, and it was proven
> wrong against Platinum's own collision and event data: a BFS over `land_data` terrain
> attributes + `zone_event` warps/obstacles, brute-forced over all 32 subsets of the five
> HMs.
>
> **Measured result — the mandatory traversal needs NO HM at all.** League-plaza south
> entrance (map 244, tile 15,78) → north exit to the League building (map 244, tile 34,5)
> has a **139-step walking path entirely on Victory Road 1F**. It really is mandatory —
> the League building door is reachable from the north exit tile but **not** from the south
> entrance tile even holding all five HMs — you just don't need a verb to cross it.
>
> * Victory Road **1F (map 244) contains zero Strength boulders, zero Rock Smash rocks and
>   no water.** Every HM obstacle lives on the optional side maps: 245 (16 boulders,
>   7 rocks), 246 (479 water, 6 waterfall tiles), 247 (891 water, 10 boulders), plus
>   20 Rock Climb tiles on 244 itself.
> * Removing any single HM from a full set **loses zero maps**. Marginal value is items and
>   side rooms only: Surf +1,747 reachable tiles, Strength +776, Rock Smash +117,
>   Waterfall +33, Rock Climb +20.
> * The only branch that needs anything is the **back exit to Route 224 (map 249)**, which
>   needs **Surf OR Strength — either alone suffices.**
> * Robustness: the "(none)" result is unchanged with ledges made completely impassable,
>   and unchanged with every overworld object (NPC, trainer, item ball) treated as a hard
>   blocker.
>
> Bulbapedia's list is the set of HMs *usable* in the area, not the set of gates on the
> route.
>
> **Mt. Coronet, by contrast, is confirmed exactly as written below:**
>
> | Traversal | Minimal sufficient HM set | Status |
> |---|---|---|
> | Route 211A entrance → Route 216 exit ("Coronet north") | **Strength + Rock Smash** | CONFIRMED |
> | Route 211A entrance → Route 211B entrance | Strength + Rock Smash | CONFIRMED |
> | Route 207/208 entrance (1F) → Spear Pillar stairs | **Surf + Strength + Rock Climb** | CONFIRMED exactly |
> | Route 211A entrance → Spear Pillar | Strength + Rock Smash + Rock Climb (no Surf) | new |
>
> So Surf on the summit route is **entrance-specific**, not a property of the route: every
> path to the summit needs Strength + Rock Climb, plus Surf (south entrance) **or** Rock
> Smash (Route 211 entrance). Inside Mt. Coronet from the south, dropping Surf, Strength or
> Rock Climb each strands you on 1F; dropping Rock Smash costs 122 tiles and Waterfall
> 88 tiles — both optional side pockets.
>
> **Gating graph for the remake:** gate Mt. Coronet north on SMASH + STRENGTH, the summit
> on STRENGTH + CLIMB (+ SURF via the south entrance), and **gate Victory Road on nothing** —
> only its optional loops and the Route 224 back exit (SURF or STRENGTH).
>
> **This does not change the soft-lock proof or the cap table.** Victory Road sits after
> badge 8, so every verb is already held; removing a gate can only make the path safer.
> The Beacon Badge / WATERFALL pairing survives on flavour and on the optional Victory Road
> and Sendoff Spring loops, but **WATERFALL now gates nothing mandatory in the whole game**
> — worth knowing before you spend art budget on it.

### 3.1 The badge → traversal ladder

| Badge | # | Leader | Vanilla HM | **Remake traversal verb** | Granted at |
|---|---|---|---|---|---|
| Coal | 1 | Roark | Rock Smash | **SMASH** | Oreburgh Gym |
| Forest | 2 | Gardenia | Cut | **CUT** | Eterna Gym |
| Relic | 3 | Fantina | Defog | *(fog deleted globally — §3.4)* | Hearthome Gym |
| Cobble | 4 | Maylene | Fly | **FLY** (map menu) | Veilstone Gym |
| Fen | 5 | Crasher Wake | Surf | **SURF** | Pastoria Gym |
| Mine | 6 | Byron | Strength | **STRENGTH** | Canalave Gym |
| Icicle | 7 | Candice | Rock Climb | **CLIMB** | Snowpoint Gym |
| Beacon | 8 | Volkner | Waterfall | **WATERFALL** | Sunyshore Gym |

This is a **1:1 preservation of the vanilla Platinum badge→HM bindings** (note the Platinum-specific swap: Relic = Defog and Fen = Surf, the reverse of Diamond/Pearl). That 1:1 preservation is exactly why route order cannot break: every obstacle in Sinnoh becomes passable precisely when a vanilla player could have passed it, and never earlier.

### 3.2 Obstacle → unlock condition → player-facing behaviour

| Obstacle (map object) | Where it gates progress in Sinnoh | Unlock condition | Player-facing behaviour |
|---|---|---|---|
| **Cracked rock** | **Ravaged Path (MANDATORY, Route 204 S→N)**; Oreburgh Gate side-rooms; Route 207; **Mt. Coronet north (MANDATORY,** Route 211 halves → Route 216); Wayward Cave; Iron Island; Victory Road *(side rooms only — **not** the through-route; see the ⚠ correction above)* | **Coal Badge** | Walk into it. Short shatter animation and screen shake; the rock breaks and the player steps through on the same input. Respawns on map reload, as in vanilla. No prompt, no menu, no party check. |
| **Cuttable tree** | **Team Galactic Eterna Building door (MANDATORY)**; Old Chateau approach; Routes 204 / 205 / 209 / 210 / 212 / 213 / 214 / 215; Floaroma Meadow; Eterna Forest shortcuts | **Forest Badge** | Walk into it. Slash animation, tree falls away, player continues. Respawns on map reload. |
| **Fog overlay** | Route 210 north; Mt. Coronet B1F; Great Marsh | **n/a — deleted** | There is no fog in this build. See §3.4. |
| **Deep water edge** | **Route 218 (MANDATORY → Canalave → Byron)**; **Route 223 (MANDATORY → League)**; Victory Road *(optional loops + the Route 224 back exit, which takes SURF **or** STRENGTH)*; Routes 219 / 220 / 221; Fuego Ironworks; Mt. Coronet interior; the three lakes; Pastoria / Great Marsh water | **Fen Badge** | Walk into the shoreline tile. The player mounts a Gen-5-style water mount and slides onto the water; dismount by walking into land. Wild encounters use the map's surf table. |
| **Push-boulder** | **Mt. Coronet north (MANDATORY)**; Victory Road *(optional side maps 245/247 only)*; Iron Island; Solaceon Ruins; Lake Verity / Valor caves; Galactic HQ | **Mine Badge** | Walk into it. The boulder slides one tile with a heavy shove animation. Puzzle logic unchanged from vanilla; only the "does someone know Strength" check is removed. |
| **Climbable rock face (chevron tiles)** | **Mt. Coronet summit route to Spear Pillar (MANDATORY)**; Victory Road *(20 optional tiles on map 244)*; Routes 210 / 211 / 216 / 217 | **Icicle Badge** | Walk into the chevron tile; the player grips and ascends or descends at climb speed. Can be interrupted by wild encounters exactly like vanilla Rock Climb. |
| **Waterfall (while on water)** | Victory Road *(optional, 6 tiles on map 246)*; Mt. Coronet interior *(optional, 88 tiles)*; Sendoff Spring — **gates nothing mandatory game-wide** | **Beacon Badge** | Swim into the base of a waterfall and ascend automatically; descend from the top ledge. |
| **Fly destinations** | Never gates progress — pure fast travel | **Cobble Badge** | See §3.3. |

### 3.3 Fly — a map menu, not a move

* **Cobble Badge** adds a **MAP** entry to the main menu (and a Pokétch shortcut).
* Opens the Sinnoh town map. Any location whose Pokémon Center the player has entered at least once is selectable; the landing point is that Center's door.
* Blocked inside dungeons, buildings and scripted sequences — **except** a dedicated `ESCAPE` option that returns you to the current dungeon's entrance, folding Escape Rope into the same UI.
* The unlock flag is "Center visited", not "map tile exists", so Fly can never reach content the story has not yet opened.
* Because Fly never gates progress in vanilla Sinnoh, granting it at badge 4 is provably incapable of breaking route order: every destination is a town the player already walked to on foot.

### 3.4 Defog — delete the fog

Per the brief: **the fog is simply removed from the game.** No fog weather state, no dimmed-visibility overlay, no accuracy modifier, no DEFOG verb, no Defog obstacle type.

This is safe because **fog never gated progress in vanilla Diamond/Pearl/Platinum.** It reduced overworld draw distance and lowered accuracy, but every fogged tile was walkable. The real gate on Route 210 north is the **Psyduck blockade**, cleared with the **Secret Potion** story item from Cynthia at the Café Cabin. That stays exactly as it is.

**Consequence: the Relic Badge is the one badge with no movement unlock.** That is correct and honest — its vanilla HM gated nothing either. What Relic Badge does grant:

* the cap raise 26 → 32,
* the obedience tier bump (§3.6),
* the story flag that opens the Route 209 / Solaceon leg.

> **Option B — if you want all 8 badges to grant movement.**
> Move **FLY to the Relic Badge (3)** and give the **Cobble Badge (4)** a new **WADE** verb: cross *shallow* water (single-tile streams, fords, shallows) while deep water still requires SURF at badge 5.
> Moving Fly one badge earlier is provably safe (it only fast-travels to towns already visited). WADE is safe **only if** shallow-water tiles are authored exclusively on decorative streams that vanilla never gated — **never** on Route 218, Route 223, Fuego Ironworks, Victory Road, or any lake interior.
> If you take Option B, nothing in §2.6 changes, because neither verb opens a new boss. Cost: extra map-authoring discipline. Recommendation: ship Option A (vanilla bindings) first; revisit Option B only if playtesters report badge 3 feeling hollow.

### 3.5 Soft-lock proof — walking the progression

The claim to verify was *"Surf is needed before certain badges in vanilla."* **In Platinum it is not.** Here is the walk, gate by gate, showing every mandatory obstacle is reached only after the badge that opens it.

| Step | Mandatory obstacle on the critical path | Verb needed | Badges held | Safe? |
|---|---|---|---|---|
| Twinleaf → Oreburgh Gym | none — Oreburgh Gate's through-path and Oreburgh Mine are both open | — | 0 | yes |
| Oreburgh → Floaroma | **Ravaged Path cracked rocks** | SMASH | **Coal (1)** | yes |
| Floaroma → Valley Windworks → Eterna Gym | none — Works Key is a story item; Route 205 and Eterna Forest are open | — | Coal | yes |
| Eterna Gym → Galactic Eterna Building | **Cut trees at the door** | CUT | **Coal, Forest (2)** | yes |
| Eterna → Hearthome Gym | Bicycle for Cycling Road (story item from Rad Rickshaw); Mt. Coronet south through-path is clear | — | Coal, Forest | yes |
| Hearthome → Solaceon → Veilstone Gym | none | — | + Relic (3) | yes |
| Veilstone → Pastoria Gym | none | — | + Cobble (4) | yes |
| Pastoria → Celestic Town | **Secret Potion** for the Psyduck (story item); fog is cosmetic and deleted | — | **+ Fen (5)** | yes |
| Celestic → **Route 218** → Canalave | **deep water** | SURF | Fen already held | **yes — this is the key check** |
| Canalave → Iron Island → Byron | none — the escorted path needs no boulders | — | Fen | yes |
| Byron → Lake Valor / Lake Verity | none | — | **+ Mine (6)** | yes |
| Route 211 → **Mt. Coronet north** → Routes 216/217 → Snowpoint | **cracked rocks + push-boulders** | SMASH + STRENGTH | Coal, Mine | yes |
| Snowpoint → Galactic HQ → **Mt. Coronet summit** | **deep water + boulders + climb faces** | SURF + STRENGTH + CLIMB | **+ Icicle (7)** | yes |
| Spear Pillar → Distortion World → Sunyshore Gym | none | — | Icicle | yes |
| Sunyshore → **Route 223** → Victory Road → League | **deep water on Route 223 only** — Victory Road's through-route is a 139-step walk needing no verb (⚠ correction, §3) | SURF | **+ Beacon (8)** | yes — and safer than previously believed |

**Result: zero soft-locks.** Vanilla Platinum's badge order is already a topological sort of the obstacle graph; binding traversal to badges 1:1 preserves that sort. Two facts make it work and must not be changed:

1. **SURF arrives at badge 5 (Fen); the first mandatory deep water is Route 218, on the way to badge 6.** Celestic Town — where vanilla *gives* HM Surf — is reachable on foot via Route 210 north. In this build the HM item is gone entirely, so that dependency disappears and the badge alone is the key.
2. **STRENGTH arrives at badge 6 (Mine); the first mandatory boulder is Mt. Coronet north, on the way to badge 7.** Iron Island is visited *before* Byron's gym, but its escorted critical path needs no boulders — exactly as in vanilla, where Riley hands you an HM you cannot yet legally use.

A third, quieter check: **SMASH at badge 1 vs. Ravaged Path.** Ravaged Path is the first mandatory HM gate in the whole game and it sits immediately after Roark. If you ever move a Rock Smash rock earlier than Oreburgh Gym, that is the one place a soft-lock can appear.

### 3.6 Knock-on changes

* **Delete HM01–HM08** from all item tables, marts, NPC gifts, and the Bag's HM pocket. Replace the vanilla HM gifts with something worth the trip: Oreburgh Gate Hiker → a TM; Cynthia in Eterna → a TM; Solaceon Ruins deepest room → a TM plus Odd Keystone lore; **Riley on Iron Island keeps the Riolu Egg** (that was always the real prize); Jasmine after Volkner → a TM.
* **HM moves become ordinary TM moves** — deletable and replaceable — so Surf, Waterfall and Strength remain usable *in battle* without the Move Deleter dance.
* **Obedience stays badge-gated** (traded Pokémon obey to L20/30/40/50/70/100 by badge count). With a hard level cap this rarely binds, but keep it so a trade-in cannot bypass the cap.
* **HM-shaped map puzzles still work** (Solaceon Ruins boulder mazes, Victory Road's strength puzzles, Mt. Coronet's climb chains). Only the party check is removed; the puzzle geometry is untouched.

---

## 4. Curated Gen 1–9 encounter placement

### 4.1 Design philosophy

The goal is *"Sinnoh, but the whole history of the world lives here"* — not a randomiser. Six rules:

1. **Sinnoh keeps the commons.** Vanilla Platinum species hold the high-rate slots (20% / 10%). Cross-gen guests take the **10% / 5% / 4%** tail. A route still *reads* as Route 201; the guests are what you find when you keep looking.
2. **Tone before nostalgia.** Sinnoh is temperate, rural, alpine, industrial in the north. Guests must match the biome: farm-and-hedgerow mons on 201–204, cave and mineral mons in Oreburgh, wetland mons on 205, deep-forest and fungal mons in Eterna Forest. Tropical Alola picks (Pikipek, Yungoos, Wimpod) are held for the southern sea routes and the Resort Area; desert picks are held for Route 228.
3. **One or two guests per generation per area; every generation represented by the end of Eterna Forest.** This is the promise of feature (D): by badge 2 the player has *seen* all nine generations without any single area reading as a grab-bag.
4. **Early-game feel is a stat-and-evolution test, not a nostalgia test.** A guest qualifies for the first 8 areas only if base-stage BST ≤ ~340, first evolution at L14 or later, no pseudo-legendary line, and no signature-ability blowout.
5. **The level cap is the balance tool.** Because exp is hard-capped at the next boss's ace, a strong early catch cannot be out-levelled into a wrecking ball. This lets us be generous with *variety* and strict only about *type coverage* (§5).
6. **Encounter levels are inherited from the vanilla slot.** A guest placed in Route 204's 5% slot appears at the level the vanilla occupant did. No new level bands are invented — which keeps §2.6 intact for free.

Slot rate ladder (Gen 4 land table, preserved): `20, 20, 10, 10, 10, 10, 10, 10, 5, 5, 4, 4`.

### 4.2 Starters — the decision

**Keep Turtwig / Chimchar / Piplup as the briefcase choice.** Reasons:

* The rival's entire script is a counter-pick off the player's choice — the ROM carries three symmetric branches for every one of Barry's seven battles (§2.4). Widening to 27 starters means 27 branches or abandoning the counter-pick, which is a real loss of character.
* Gyms 1–3 are tuned against three known lines. A Gen 5 Oshawott or a Gen 9 Fuecoco materially changes Roark and Gardenia.
* Art budget: 3 lines × 3 stages in Gen 5 style is 9 sprite sets; 27 lines is 81 — before a single route is drawn.

**Widen the roster, not the opening.** Every other generation's starters are obtainable mid-to-late game as rare wild encounters or one-off NPC gifts in biome-matched locations, so the "all 9 generations" promise is kept without touching the first hour:

| Biome | Starters placed there |
|---|---|
| Eterna Forest / Route 205 north (deep wood) | Chikorita, Treecko, Snivy, Chespin, Rowlet, Grookey, Sprigatito |
| Fuego Ironworks / Stark Mountain (fire) | Charmander, Cyndaquil, Torchic, Tepig, Fennekin, Litten, Scorbunny, Fuecoco |
| Great Marsh / Routes 219–221 (water) | Squirtle, Totodile, Mudkip, Oshawott, Froakie, Popplio, Sobble, Quaxly |
| Route 212 south / Pastoria wetlands | Bulbasaur, plus wild Turtwig cameo populations |

If wild rarity feels punishing, gift them through a repeatable NPC — Professor Rowan's aide running a "seed stock" programme — which also gives Rowan a reason to exist after the prologue.

### 4.3 Worked placement tables — the first 8 areas

Vanilla columns are **ROM-extracted and exact**. "Gen" marks the generation of each cross-gen guest.

---

#### Route 201 — cap 14, levels 2–4

**Vanilla (ROM, enc #140):** Starly L2–3, Bidoof L2–3, Kricketot L3. Morning: Starly / Bidoof. Night: Kricketot / Bidoof. Poké Radar: Nidoran♂ / Nidoran♀.

| Slot | Species | Gen | Lv | Note |
|---|---|---|---|---|
| 20% | **Starly** | 4 | 2–4 | vanilla |
| 20% | **Bidoof** | 4 | 2–4 | vanilla |
| 10% | **Kricketot** | 4 | 3 | vanilla, night-weighted |
| 10% | **Lechonk** | **9** | 3 | rural forager; evolves L18, well past this band |
| 10% | **Bunnelby** | **6** | 3 | hedgerow digger; evolves L20 |
| 5% | **Nidoran♀ / Nidoran♂** | **1** | 4 | promoted from vanilla's Poké Radar slot — ROM precedent |
| 5% | **Skwovet** | **8** | 4 | berry thief; pairs with the route's berry patches |
| 4% | **Hoothoot** | **2** | 4 | **night only**; evolves L20 |
| 4% | **Wooloo** | **8** | 4 | day pasture; cut this if Gen 8 feels over-represented |

Generations present: 1, 2, 4, 6, 8, 9.

---

#### Route 202 — cap 14, levels 3–5

**Vanilla (ROM, enc #141):** Shinx L3–4, Bidoof L3–4, Starly L2–4, Kricketot L3. Swarm: Zigzagoon. Poké Radar: Sentret.

| Slot | Species | Gen | Lv | Note |
|---|---|---|---|---|
| 20% | **Shinx** | 4 | 3–4 | vanilla |
| 20% | **Bidoof** | 4 | 3–4 | vanilla |
| 10% | **Starly** | 4 | 4 | vanilla |
| 10% | **Kricketot** | 4 | 3 | vanilla |
| 10% | **Zigzagoon** | **3** | 4 | promoted from vanilla's swarm slot — ROM precedent |
| 10% | **Sentret** | **2** | 4 | promoted from vanilla's Poké Radar slot — ROM precedent |
| 5% | **Lillipup** | **5** | 4 | farm dog; evolves L16 |
| 5% | **Pawmi** | **9** | 4 | the route's second electric option beside Shinx; evolves L18 |
| 4% | **Fletchling** | **6** | 5 | evolves L17 |
| 4% | **Grubbin** | **7** | 5 | Gen 7's temperate-forest entry |

Generations present: 2, 3, 4, 5, 6, 7, 9. **All nine generations are visible by Route 203.**

---

#### Route 203 — cap 14, levels 4–7 *(pre-Roark: type discipline applies, §5.2)*

**Vanilla (ROM, enc #142):** Starly L4–7, Shinx L4–5, Kricketot L4, Bidoof L5–7, **Abra L4–5**. Swarm: Cubone. Night: Kricketot / Zubat.

| Slot | Species | Gen | Lv | Note |
|---|---|---|---|---|
| 20% | **Starly** | 4 | 4–5 | vanilla |
| 20% | **Shinx** | 4 | 4–5 | vanilla |
| 10% | **Abra** | **1** | 4–5 | vanilla; the route's "rare prize" identity — keep it |
| 10% | **Kricketot** | 4 | 4 | vanilla |
| 10% | **Bidoof** | 4 | 5 | vanilla |
| 10% | **Blitzle** | **5** | 5 | pasture electric; evolves L27 |
| 5% | **Ralts** | **3** | 5 | slow bloomer (evolves L20); no early dominance |
| 5% | **Hoppip** | **2** | 5 | evolves L18 |
| 4% | **Nymble** | **9** | 6 | evolves L24 |
| 4% | **Skwovet** | **8** | 6 | safe filler — see the Cubone ruling below |

**Ruling on Cubone.** Vanilla's swarm slot here is Cubone, and Ground is super-effective on Roark's Rock. Route 203 is pre-badge-1, and vanilla exposes this route to nothing that beats Roark. **Hold Cubone until Route 206/207 (post-Gardenia)** and leave the 4% slot to Skwovet or Nymble. If you want the swarm flavour back, re-enable the Cubone swarm *after* the Coal Badge flag.

---

#### Oreburgh Gate 1F / B1F — cap 14, levels 3–8

**Vanilla (ROM, enc #53 = 1F, #54 = B1F):**
*1F:* Zubat L3–6, Psyduck L4–6. **Surf:** Psyduck / Zubat L20–30, Golduck / Golbat L20–40. **Old Rod:** Magikarp L3–15. **Good Rod:** Magikarp / Barboach L10–25. **Super Rod:** Gyarados L30–55, Whiscash L30–55.
*B1F:* Zubat L5–8, Psyduck L5–7, Geodude L5–7.

| Slot | Species | Gen | Lv | Note |
|---|---|---|---|---|
| 20% | **Zubat** | 1 | 3–6 | vanilla |
| 20% | **Psyduck** | 1 | 4–6 | vanilla |
| 10% | **Geodude** | 1 | 5–7 | vanilla (B1F) |
| 10% | **Roggenrola** | **5** | 5 | pure Rock — no advantage over Roark; evolves L25 |
| 10% | **Rolycoly** | **8** | 5 | **coal** — perfect for Oreburgh; pure Rock until Carkol at L18 |
| 5% | **Rockruff** | **7** | 6 | pure Rock; evolves L25 |
| 5% | **Nacli** | **9** | 6 | pure Rock; evolves L24 |
| 4% | **Woobat** | **5** | 6 | cave-bat variety against Zubat monotony |
| 4% | **Noibat** | **6** | 6 | pure cave flavour; evolves L48 — a deliberate long-term project |
| Surf | vanilla + **Chewtle (8)**, **Tympole (5)** | | 20–40 | Fen Badge required, so effectively a return visit |
| Fish | vanilla + **Poliwag (1)**, **Tadbulb (9)** on the Good Rod | | | |

**Every cross-gen guest here is pure Rock or a bat.** None is super-effective against Roark. That is deliberate — §5.2.

---

#### Oreburgh Mine 1F / B1F — cap 14, levels 4–9

**Vanilla (ROM, enc #5 = 1F, #6 = B1F):** Geodude L4–9, Zubat L5–8, Onix L6–9.

| Slot | Species | Gen | Lv | Note |
|---|---|---|---|---|
| 20% | **Geodude** | 1 | 4–9 | vanilla |
| 20% | **Zubat** | 1 | 5–8 | vanilla |
| 10% | **Onix** | 1 | 6–9 | vanilla |
| 10% | **Rolycoly** | **8** | 6 | coal seam |
| 10% | **Roggenrola** | **5** | 6 | |
| 10% | **Nacli** | **9** | 7 | salt vein |
| 5% | **Nosepass** | **3** | 7 | pure Rock; magnetic-ore flavour |
| 5% | **Rockruff** | **7** | 7 | |
| 4% | **Shuckle** | **2** | 8 | Bug/Rock; harmless, memorable, a genuine deep-mine find |
| 4% | **Carbink** | **6** | 8 | Rock/Fairy; the mine's treasure — keep at 4% or lower |

**Deliberately excluded pre-Roark:** Aron, Cufant, Tinkatink, Magnemite, Beldum (**Steel**); Drilbur, Mudbray, Sandshrew, Phanpy, Cubone (**Ground**); Timburr, Machop, Makuhita, Riolu (**Fighting**). All of these move to Mt. Coronet south, Route 207, or Iron Island.

---

#### Route 204 (south L4–6 / north L8–11) — cap 22

**Vanilla (ROM, enc #143 south / #144 north):** Starly, Bidoof, Wurmple, Kricketot, Budew, Shinx. Morning: Wurmple / Budew. Night: Kricketot / Zubat. Poké Radar (north): Sunkern.

| Slot | Species | Gen | Lv (S / N) | Note |
|---|---|---|---|---|
| 20% | **Starly** | 4 | 4 / 9 | vanilla |
| 20% | **Bidoof** | 4 | 4 / 9 | vanilla |
| 10% | **Budew** | 4 | 4–5 / 9–10 | vanilla |
| 10% | **Wurmple** | 3 | 4 / 9 | vanilla |
| 10% | **Kricketot** | 4 | 3 / 8 | vanilla |
| 10% | **Shinx** | 4 | 4–5 / 9–10 | vanilla |
| 5% | **Cutiefly** | **7** | 5 / 10 | meadow verge; evolves L25 |
| 5% | **Sewaddle** | **5** | 5 / 10 | leaf-wrapped larva; evolves L20 |
| 4% | **Blipbug** | **8** | 6 / 11 | evolves L10 into Dottler — defensive and harmless |
| 4% | **Sunkern** | **2** | 6 / 11 | promoted from vanilla's Poké Radar slot — ROM precedent |
| *(north, swaps Kricketot)* | **Scatterbug** | **6** | 10 | |
| *(north, swaps Wurmple)* | **Oddish** | **1** | 10 | |

---

#### Ravaged Path — cap 22, levels 6–10 *(the first SMASH gate)*

**Vanilla (ROM, enc #55):** Zubat L6–9, Psyduck L8–10, Geodude L6–8, Golbat L10. **Surf:** Psyduck / Zubat L20–30, Golduck / Golbat L20–40. Fishing as Oreburgh Gate.

| Slot | Species | Gen | Lv | Note |
|---|---|---|---|---|
| 20% | **Zubat** | 1 | 6–9 | vanilla |
| 20% | **Psyduck** | 1 | 8–10 | vanilla |
| 10% | **Geodude** | 1 | 6–8 | vanilla |
| 10% | **Wooper** | **2** | 8 | cave pool; evolves L20 |
| 10% | **Tympole** | **5** | 8 | evolves L25 |
| 10% | **Dewpider** | **7** | 9 | bubble spider on the cave water; evolves L22 |
| 5% | **Lotad** | **3** | 9 | evolves L14 — right at the cap band, which is fine |
| 5% | **Golbat** | 1 | 10 | vanilla |
| 4% | **Chewtle** | **8** | 10 | evolves L22 |
| 4% | **Tadbulb** | **9** | 10 | a glowing bulb in a dark cave — strong flavour; stone evolution |
| Surf / Fish | vanilla + **Poliwag (1)** on the Good Rod | | | post-Fen return visit |

---

#### Route 205 (south, L9–12, riverside) — cap 22

**Vanilla (ROM, enc #145):** Shellos L9–12, Buizel L10–11, Pachirisu L9–11, Bidoof L10.

| Slot | Species | Gen | Lv | Note |
|---|---|---|---|---|
| 20% | **Shellos** | 4 | 9–12 | vanilla |
| 20% | **Buizel** | 4 | 10–11 | vanilla |
| 10% | **Pachirisu** | 4 | 9–11 | vanilla |
| 10% | **Bidoof** | 4 | 10 | vanilla |
| 10% | **Marill** | **2** | 10 | riverbank; evolves L18 |
| 10% | **Surskit** | **3** | 10 | evolves L22 |
| 5% | **Ducklett** | **5** | 11 | evolves L35 |
| 5% | **Flabébé** | **6** | 11 | riverside flowers; Fairy, stone evolution |
| 4% | **Dewpider** | **7** | 12 | |
| 4% | **Tadbulb** | **9** | 12 | |

#### Route 205 (north, L12–15, forest verge) — cap 22

**Vanilla (ROM, enc #146):** Bidoof L12–14, Budew L12–14, Wurmple L13, Kricketot L12, Silcoon / Cascoon L14, Beautifly / Dustox L15.

| Slot | Species | Gen | Lv | Note |
|---|---|---|---|---|
| 20% | **Bidoof** | 4 | 12–14 | vanilla |
| 20% | **Budew** | 4 | 12–14 | vanilla |
| 10% | **Wurmple** | 3 | 13 | vanilla |
| 10% | **Kricketot** | 4 | 12 | vanilla |
| 10% | **Silcoon** | 3 | 14 | vanilla |
| 10% | **Cascoon** | 3 | 14 | vanilla |
| 5% | **Applin** | **8** | 13 | orchard verge; item evolution |
| 5% | **Tarountula** | **9** | 13 | evolves L15 |
| 4% | **Beautifly / Dustox** | 3 | 15 | vanilla |
| 4% | **Ledyba / Spinarak** | **2** | 14 | **day / night split** |

---

#### Eterna Forest — cap 22, levels 10–14 *(the all-nine-generations showcase)*

**Vanilla (ROM, enc #8):** Buneary L11–13, Budew L10–11, Wurmple L10, Kricketot L12, Bidoof L12, Silcoon L12, Cascoon L12, Gastly L13, Beautifly L14, Dustox L14.

| Slot | Species | Gen | Lv | Note |
|---|---|---|---|---|
| 20% | **Budew** | 4 | 10–11 | vanilla |
| 20% | **Buneary** | 4 | 11–13 | vanilla |
| 10% | **Wurmple** | 3 | 10 | vanilla |
| 10% | **Kricketot** | 4 | 12 | vanilla |
| 10% | **Silcoon / Cascoon** | 3 | 12 | vanilla |
| 10% | **Venipede** | **5** | 12 | evolves L22 |
| 10% | **Paras** | **1** | 12 | mushroom forest; evolves L24 |
| 5% | **Gastly** | 1 | 13 | vanilla — **the Fantina answer, kept exactly where vanilla put it** |
| 5% | **Morelull** | **7** | 13 | **night only**; glowing caps under the canopy — the best tonal fit in the game |
| 4% | **Phantump** | **6** | 14 | **night only**; pairs with Gastly. Trade evolution — give it a level/item alternative (§5.5) |
| 4% | **Shroomish** | **3** | 14 | evolves L23 |
| *swarm* | **Toedscool** | **9** | 13 | Ground/Grass fungal drifter — a memorable Gen 9 forest signature |
| *swarm alt* | **Stufful** | **7** | 13 | use if Toedscool reads too strange for the opening act |
| *radar* | **Grubbin** | **7** | 12 | |
| *radar* | **Blipbug** | **8** | 12 | |

**Generation coverage by the end of Eterna Forest:** 1, 2, 3, 4, 5, 6, 7, 8, 9 — all nine. Feature (D) is delivered before badge 2.

### 4.4 Placement rules for the rest of Sinnoh (carry these forward)

| Biome | Reserved for | Examples |
|---|---|---|
| Mt. Coronet south / Route 207 | Steel, Ground, Fighting (post-Gardenia only) | Aron, Cufant, Drilbur, Timburr, Mudbray, Cubone |
| Routes 210 / 214 / 215 (scrub, former fog belt) | Dark, Poison, Psychic | Nickit, Purrloin, Maschiff, Espurr, Stunky |
| Great Marsh / Route 212 | Water-Ground, wetland | Paldean Wooper, Croagunk, Palpitoad, Sobble |
| Routes 218–221, open sea | Coastal Alola / Galar | Wimpod, Pyukumuku, Arrokuda, Wiglett, Finizen |
| Routes 216 / 217, Acuity, Snowpoint | Ice | Snom, Cetoddle, Cubchoo, Vanillite, Bergmite, **Frigibax (L45+ only)** |
| Fuego Ironworks / Stark Mountain | Fire, Steel | Litwick, Charcadet, Heatmor, Magmar, Carkol |
| Distortion World / Turnback / Old Chateau | Ghost, Dark | Sinistea, Greavard, Duskull, Sableye, Mimikyu |
| Victory Road / Routes 224–230 | Dragon, pseudo-legendaries | Deino, Goomy, Jangmo-o, Dreepy, Bagon, Larvitar, Beldum |

---

## 5. Balance sanity — is the early game broken?

**Verdict: no, and the level cap is the reason.** Three independent guards.

### 5.1 Guard 1 — the level cap neutralises power spikes

In an ordinary romhack, "all nine generations on Route 201" breaks the game because a strong catch can be over-levelled. Here exp is **hard-zeroed** at the cap.

The benchmark: vanilla Platinum already places **Gible at Wayward Cave, L17–20** (ROM enc #113), reachable with the Bicycle before Hearthome. Under the cap that Gible can reach at most **L26** before Fantina and **L32** before Maylene. Gabite evolves at 24, Garchomp at 48 — so vanilla's own Gible stays the single biggest early power spike in the game, and the cap contains it.

**Nothing proposed in §4.3 is stronger than a Gible the vanilla game already gives away.** That is the bar used throughout.

### 5.2 Guard 2 — type discipline against gyms 1–3

The real risk is not stats, it is **coverage**. The rule: *no cross-gen addition may be a harder counter to gym N than something vanilla already offered before gym N.*

| Gym | Type | Counters | What vanilla already gives before it | Ruling for cross-gen additions |
|---|---|---|---|---|
| **1 Roark** | Rock | Water, Grass, Fighting, Ground, Steel | Psyduck (Oreburgh Gate), Budew (Route 204), Piplup / Turtwig starters | **Ban before Coal Badge:** all Fighting (Machop, Timburr, Makuhita, Tyrogue, Riolu), all Ground (Drilbur, Mudbray, Sandshrew, Phanpy, Cubone), all Steel (Aron, Magnemite, Cufant, Tinkatink, Beldum). Water / Grass guests only at ≤10% and only lines matching vanilla's own pre-Roark pool. **Every Oreburgh guest in §4.3 is pure Rock or a bat.** |
| **2 Gardenia** | Grass | Fire, Flying, Ice, Bug, Poison, Steel | Starly (Flying, everywhere), Chimchar starter, Zubat (Poison), Wurmple / Kricketot (Bug), Budew (Poison) | Gardenia is already soft in vanilla. **Ban before Forest Badge:** Steel (walls her outright) and Ice. No Fire beyond the starter before Eterna. Flying / Bug / Poison guests are fine — they only match what Starly and Zubat already do. |
| **3 Fantina** | Ghost | Dark, Ghost | Gastly (Eterna Forest, 5%) | **Ban before Relic Badge:** all early Dark lines (Nickit, Purrloin, Maschiff, Poochyena, Zorua, Impidimp) and all Ghost lines except vanilla's Gastly and the night-only **Phantump** at 4%. Phantump is Ghost/**Grass**, which Mismagius does not fear, and at 4% night-only it is a find rather than a strategy. |

### 5.3 Guard 3 — the hard exclusion list for the first 8 areas

Not placeable anywhere before Eterna City, at any rarity:

* **Pseudo-legendaries and near-pseudos:** Larvitar, Bagon, Beldum, Deino, Goomy, Jangmo-o, Dreepy, Frigibax. **Gible keeps its vanilla Wayward Cave slot only (L17–20) and appears nowhere else.**
* **Signature-ability blowouts:** Nincada (Shedinja), Wynaut / Wobbuffet (**Wobbuffet keeps its vanilla Route 201 Poké Radar slot only**), Ditto, Chansey. Shuckle is permitted — it blows nothing up.
* **Fast-snowball lines:** Scyther, Pinsir, Skarmory, Sneasel, Dratini; **Eevee keeps the vanilla Hearthome gift**, **Riolu keeps the vanilla Iron Island egg**, **Munchlax keeps vanilla honey trees**, Magikarp keeps its vanilla fishing slots.
* **Tonal misfits held for later:** Pikipek, Yungoos, Wimpod, Smoliv, Capsakid, Sandile, Trapinch, Alolan Vulpix, Alolan Sandshrew.

### 5.4 The specific fears named in the brief, answered

| Fear | Status |
|---|---|
| "Pseudo-legendaries on Route 201" | **Impossible.** §5.3 bans all nine lines from the first 8 areas. The only pseudo in the pre-badge-3 window is vanilla's own Gible at Wayward Cave, and the cap holds it at L26. |
| "Early access to something that invalidates the first three gyms" | **Guarded.** §5.2 bans Fighting / Ground / Steel before Roark, Steel / Ice / Fire before Gardenia, Dark / Ghost before Fantina. The Oreburgh Gate and Mine tables are *deliberately* all-Rock, so the mine and the gate cannot arm you against the Rock gym. |
| "Early game trivially broken by Gen 5–9 additions" | **Contained.** Every guest in §4.3 has base-stage BST ≤ 340, first evolution at L14+, inherits the vanilla slot's level band, and sits in the 10 / 5 / 4% tail. The 20% slots remain Sinnoh's own. |
| "Level cap makes a boss unwinnable" | **Verified.** §2.6 walks all mandatory fights; each sits at or under the cap in force, with the eight gyms and the League exactly level-matched. Tightest margins: Rival at Pastoria (+1) and Cyrus in the Distortion World (+2). |
| "HM removal creates a soft-lock" | **Proven.** §3.5 walks the whole critical path. Vanilla's badge order is already a topological sort of the obstacle graph and we preserve the bindings 1:1. SURF (badge 5) precedes the first mandatory deep water (Route 218, en route to badge 6); STRENGTH (badge 6) precedes the first mandatory boulder (Mt. Coronet north, en route to badge 7); SMASH (badge 1) precedes the first mandatory gate of any kind (Ravaged Path). |

### 5.5 Two further levers, if the early game still plays soft

1. **Party-wide Exp. Share should be opt-in or absent.** Under a hard cap it mostly accelerates *hitting* the cap, which flattens team-building decisions rather than deepening them.
2. **Trade evolutions need level or item alternatives** — Phantump, Haunter, Machoke, Graveler, Kadabra, Boldore, Gurdurr, Karrablast / Shelmet. The References folder holds "no impossible evos" patched builds of Platinum, HeartGold, Black and White 2; lift those patches' evolution tables as the substitution scheme rather than inventing one.

   **VERIFIED (2026-09-23).** Diffing `/poketool/personal/evo.narc` between
   `Platinum/3541 - ... (XenoPhobia).nds` and `Platinum/Platinum no impossible evos.nds`
   (both `CPUE`, both 508 entries) gives **exactly 16 differing species** — a
   ready-made, ROM-authored substitution table. The patch uses two rules and nothing else:

   | Vanilla method | Patched method | Applied to |
   |---|---|---|
   | `5` trade (no item) → | `4` level-up at **L37** | Kadabra (64), Machoke (67), Graveler (75), Haunter (93) |
   | `6` trade holding item → | `18` + `19` level-up holding that item, **day and night** | Poliwhirl→Politoed (King's Rock), Onix→Steelix, Scyther→Scizor, Seadra→Kingdra, Porygon→Porygon2, Porygon2→Porygon-Z, Rhydon→Rhyperior, Electabuzz→Electivire, Magmar→Magmortar, Dusclops→Dusknoir, Clamperl→Huntail **and** Gorebyss |

   One hand-tuned exception: **Slowpoke→Slowking** becomes `7` use-item **Water Stone**
   rather than a held-item level-up, because Slowpoke already evolves into Slowbro at L37
   and a level trigger would collide. Adopt that exception — it is the only genuinely
   ambiguous case in the set.

   Emitting the same two rules over the veekun evolution data covers the Gen 5–9 lines the
   Gen 4 table cannot know about (Boldore, Gurdurr, Karrablast/Shelmet, Phantump, Pumpkaboo,
   Spritzee/Swirlix, Gimmighoul). Extraction command lives in
   `tools/extract_platinum.py --evo-diff`; scratch proof in `tools/_work/arch/evodiff.py`.

---

## Appendix A — regenerating the source data

All figures above are reproducible from the owner's local cartridge dumps. Nothing ROM-derived is committed.

```
tools/_work/ndsfs.py     # NDS FNT/FAT filesystem reader + NARC unpacker
tools/_work/dump5.py     # trainer parties  -> all_trainers.txt
                         # encounter tables -> encounters.txt
```

Key file indices inside Platinum (US, `CPUE`):

| Data | Path | Index |
|---|---|---|
| Trainer properties | `/poketool/trainer/trdata.narc` | 928 entries |
| Trainer parties | `/poketool/trainer/trpoke.narc` | 928 entries |
| Species names | `/msgdata/pl_msg.narc` | file **412** (496 entries) |
| Trainer names | `/msgdata/pl_msg.narc` | file **618** (928 entries; many are 9-bit packed behind marker `0xF100`) |
| Wild encounters | `/fielddata/encountdata/pl_enc_data.narc` | 183 entries × 424 bytes |

**Trainer-party record (DPPt):** `u8 ivs, u8 ability/gender, u16 level, u16 species (&0x3FF), [u16 item if flags&2], [u16 moves[4] if flags&1], u16 ballseal`. In `trdata`: byte 0 = flags, byte 1 = trainer class, byte 3 = party size.

**Encounter table (Platinum):** `u32 walkRate`, then 12 × `{u32 level, u32 species}` on the fixed rate ladder `20,20,10,10,10,10,10,10,5,5,4,4`, then swarm[2], morning[2], night[2], Poké Radar[4], 6 unused, dual-slot[10], then rate-prefixed 5-slot blocks for surf, (unused), Old Rod, Good Rod, Super Rod.

**Encounter indices used in §4.3:** Route 201 = **140**, Route 202 = **141**, Route 203 = **142**, Route 204 S/N = **143 / 144**, Route 205 S/N = **145 / 146**, Oreburgh Gate 1F/B1F = **53 / 54**, Oreburgh Mine 1F/B1F = **5 / 6**, Ravaged Path = **55**, Eterna Forest = **8**, Wayward Cave (Gible) = **113**. Area↔index identification is by encounter composition matched against the known vanilla tables; the levels and species themselves are read straight from the ROM.

## Appendix B — external sources, used only for story order and gate locations

* Bulbapedia — [Walkthrough:Pokémon Platinum](https://bulbapedia.bulbagarden.net/wiki/Walkthrough:Pok%C3%A9mon_Platinum) — the 20-part order underlying §1
* Bulbapedia — [Badge](https://bulbapedia.bulbagarden.net/wiki/Badge) — Platinum badge→HM bindings, including the Platinum-specific Relic = Defog / Fen = Surf swap
* Bulbapedia — [Ravaged Path](https://bulbapedia.bulbagarden.net/wiki/Ravaged_Path) — "can only be crossed using Rock Smash"
* Bulbapedia — [Mt. Coronet](https://bulbapedia.bulbagarden.net/wiki/Mt._Coronet) — Rock Smash + Strength for the northern passage; Surf, Strength and Rock Climb for the summit — **both CONFIRMED byte-exact against the ROM**
* Bulbapedia — [Victory Road (Sinnoh)](https://bulbapedia.bulbagarden.net/wiki/Victory_Road_(Sinnoh)) — ~~"Surf, Strength, Rock Smash, Waterfall, and Rock Climb are required"~~ **REFUTED against the ROM's own collision data — the through-route needs no HM. See the ⚠ correction in §3. This is the second proven error in a widely-cited source (cf. Bertha).**
* Bulbapedia — [Barry (game)/Platinum](https://bulbapedia.bulbagarden.net/wiki/Barry_(game)/Platinum) — rival battle locations
* Pokémon Database — [Platinum Gym Leaders & Elite Four](https://pokemondb.net/platinum/gymleaders-elitefour) — cross-check only; **superseded by the ROM where they disagree (see Bertha)**
* Pokémon Database — [DPPt HM locations](https://pokemondb.net/diamond-pearl/hms) — where each HM item sits in vanilla
