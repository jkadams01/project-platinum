# Custom Battle mode

Build both teams from any of the 1025 species, set their levels, natures, abilities, held
stones and moves, do the same for the opponent, and fight. Separate from the campaign and
sharing none of its state.

It exists to answer **"do battles feel right?"** without playing to Oreburgh first. It is
also the fastest way to exercise the engine by hand: the payload it produces is the same
`EventBus.battle_started` shape a gym fight produces (DATA_CONTRACT 13), so anything that
works here works there.

---

## Getting in

`scenes/Title.tscn` is the main scene. **CAMPAIGN** loads `scenes/Boot.tscn` unchanged;
**CUSTOM BATTLE** loads `scenes/CustomBattle.tscn`.

```bash
tools/run_game.sh                    # title screen
tools/run_game.sh --custom           # skip the title, straight into the builder
```

From inside the Godot editor, **F5** runs the main scene, which is the title.
Launching the Godot binary on its own opens the Project Manager and then the
*editor*, not the game -- that is the usual reason it seems not to run.

---

## Controls

Two schemes, and the difference is deliberate. The builder uses WASD like the rest of the
game; the pickers filter as you type, so W and S have to mean "W" and "S" there. Both are
printed on screen.

| Screen | Keys |
|---|---|
| **Teams** (the overview) | `WASD` move the cursor · `A`/`D` swap sides · `Enter` edit the slot · `Tab` options · `R` start · `Esc` title |
| **Slot editor** | `W`/`S` field · `A`/`D` level ±1 (`Shift` ±10) · `Enter` change · `Esc` back |
| **Any picker** | `↑`/`↓`, `PgUp`/`PgDn`, `Home`/`End` move · **type to filter** · `Enter` pick · `Esc` back |
| **Result panel** | `A` rematch · `X` back to the builder · `Esc` title |

A species picker filters on name *or* dex number, so `445` and `garchomp` both find
Garchomp.

---

## The options menu (`Tab`)

| | |
|---|---|
| **Format** | single / double / triple / rotation — **only single is playable**, see below |
| **Watch mode** | both sides play themselves from `ai.gd`; the log still pages one line at a time |
| **Seed** | pin the RNG, or leave it on `auto` for a fresh one each battle |
| **Award EXP** | off by default — a mid-battle level-up makes a rematch not a rematch |
| **Foe AI** | 0-10 (`trainer.ai`). Below 3 it just picks its best damaging move; at 3+ it switches out of bad matchups |
| **Key Stones** | per side, on by default. Mega Evolution **without** granting the save a Key Stone |
| **Fill a team** | a boss roster · six random Pokémon · your campaign party · clear |
| **Save / load / delete** | matchups stored as JSON in `user://custom_battles/` |

### Pre-filling from a boss

Every roster in `data/rom/bosses.json` — all 31, gyms and rivals and the Elite Four — can be
dropped into either side and then edited. The rows are read straight out of the table, so
what you get is the authored fight, not a rebuild of it.

`data/rom/bosses.json` is ROM-derived and gitignored. On a checkout without it the option
says so instead of offering an empty list; run `python tools/build_gamedata.py`.

A rival slot tagged `dynamicSlot` (Barry's starter, normally chosen to counter yours) keeps
its **placeholder** species here — there is no starter choice in a sandbox, and a visible
placeholder you can edit beats a silent guess.

---

## What is legal, and what merely bends

Two tiers, because they are genuinely different problems (`src/custom/battle_spec.gd`).

**Blocking** — `R` refuses and the status line goes red: an empty team, a species the data
does not have, a level outside 1-100, a move slug with no row in `data/moves.json` (it would
be silently dropped from the Pokémon), a format the engine cannot play.

**Advisory** — the status line goes amber and `R` still works: a move outside the species'
learnset, an ability it cannot have, someone else's Mega Stone.

You cannot *build* an advisory by hand — the pickers only ever offer legal choices. They
exist for imported rosters and hand-edited presets, and they are shown rather than silently
corrected, because sanitising an authored roster on import is the kind of quiet data loss
this project has already been bitten by.

### Held items are Mega Stones or nothing

The engine reads a held item in exactly two places: `mega.gd` matches it against an eligible
form's stone, and `exp.gd` looks for `lucky-egg`. There is no Life Orb, no Leftovers, no
Choice Band. So the picker offers the stones a species can actually use and nothing else,
while an item that arrived with a roster (Roark's Roggenrola holds an Oran Berry) is kept
and marked **`(inert)`** in the slot editor.

---

## Doubles, triples and rotations are not implemented

The format selector is built and the choice is remembered, but only **single** can be
played. `battle_engine.gd` keeps one active Pokémon per side — `sides[side]["active"]` is an
int, `damage.gd` targets `active(1 - side)`, `turn_order.gd` sorts exactly two actions, and
`ai.gd` chooses one move for one Pokémon. Multi-slot formats need target selection in the
action payload, spread damage and redirection, adjacency for triples, rotation as a free
action, and every ability field hook re-checked against more than one foe.

Choosing one anyway is *refused*, out loud, with the reason. A format that silently
downgrades to singles would be worse than one that is greyed out.

---

## It never touches the campaign save

Not by omission — by construction, and `tests/test_custom_battle.gd` asserts it:

* teams are built fresh from the spec every battle, so no Dictionary out of
  `GameState.party` is ever in the fight (damage and EXP would persist);
* the payload carries **no `prizeMoney`**, because the engine pays a trainer prize straight
  into `GameState.add_money()`;
* `awardExp` is false by default, so nothing levels up;
* `playerKeyStone` rides in the payload instead of granting the save a Key Stone;
* `SaveSystem` is never called.

---

## The preset format

`user://custom_battles/<name>.json`. Loading normalises whatever it finds, so a preset
written by an older build still opens.

```jsonc
{
  "version": 1,
  "format": "single",
  "seed": 4242,                     // 0 = a new seed each battle
  "awardExp": false,
  "watch": false,
  "player": {
    "name": "You",
    "keyStone": true,
    "ai": 7,                        // only the foe side is read
    "slots": [                      // always 6; species 0 is an empty slot
      {"species": 445, "level": 62, "nature": "jolly",
       "ability": "rough-skin", "item": "garchompite",
       "moves": ["dragon-claw", "earthquake", "stone-edge", "swords-dance"]}
    ]
  },
  "foe": { }
}
```

`moves: []` means "roll the level-up moveset", which is what an untouched slot fights with.

**Every number must come back an int.** `JSON.parse_string` returns floats, and `445.0` does
not resolve to a species in any Dictionary lookup — `BattleSpec.normalize()` is what fixes
that, and the round trip is a test.
