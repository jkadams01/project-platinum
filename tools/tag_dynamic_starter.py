"""Mark Barry's starter slot in every one of his fights as dynamic.

In vanilla Platinum the rival picks the starter with a TYPE ADVANTAGE over the player's
choice. Our ROM-extracted data hardcodes whichever line the dump happened to contain, so
every Barry fight would field the same starter regardless of what the player picked.

This tags the slot instead of fixing the species: the engine substitutes at battle start,
keeping the EVOLUTION STAGE the data recorded. Idempotent.
"""
import json, io, shutil

# Gen 4 starter lines, in evolution order. All are dex 387-395, so any substitution
# keeps Barry's ace a Gen 4 species and the ace rule holds automatically.
LINES = {
    'turtwig':  (387, 388, 389),   # Turtwig  -> Grotle   -> Torterra   (Grass)
    'chimchar': (390, 391, 392),   # Chimchar -> Monferno -> Infernape  (Fire)
    'piplup':   (393, 394, 395),   # Piplup   -> Prinplup -> Empoleon   (Water)
}
# Rival takes the line that beats the player's: Grass < Fire < Water < Grass
COUNTER = {'turtwig': 'chimchar', 'chimchar': 'piplup', 'piplup': 'turtwig'}

STAGE_OF = {s: (line, i) for line, ev in LINES.items() for i, s in enumerate(ev)}

PATH = 'data/rom/bosses.json'
shutil.copy(PATH, PATH + '.bak')
doc = json.load(io.open(PATH, encoding='utf-8'))
bl = doc.get('bosses', doc)
items = list(bl.items()) if isinstance(bl, dict) else [(b.get('key'), b) for b in bl]

doc['starterLines'] = LINES
doc['starterCounter'] = COUNTER
doc['dynamicStarterRule'] = (
    "Barry's starter is chosen to counter the player's: player picks turtwig -> Barry gets "
    "chimchar, chimchar -> piplup, piplup -> turtwig. A party slot tagged "
    "dynamicSlot='rival-starter' keeps its starterStage and has its species substituted at "
    "battle start from starterLines[COUNTER[player_choice]][starterStage]. The stored "
    "species is only a placeholder.")

tagged = []
for key, boss in items:
    if boss.get('name') != 'Barry':
        continue
    for p in boss.get('party', []):
        hit = STAGE_OF.get(p.get('species'))
        if not hit:
            continue
        line, stage = hit
        p['dynamicSlot'] = 'rival-starter'
        p['starterStage'] = stage
        p['placeholderSpecies'] = p['species']
        tagged.append((key, line, stage, p['level']))

json.dump(doc, io.open(PATH, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)

print('tagged %d slots across %d Barry fights\n' % (len(tagged), len(set(t[0] for t in tagged))))
print('%-28s %-9s %-5s %s' % ('fight', 'line', 'stage', 'lv'))
for k, line, stage, lv in tagged:
    print('%-28s %-9s %-5s %s' % (k, line, stage, lv))
print('\nresolution examples (stage 2, the final evolution):')
for choice in LINES:
    line = COUNTER[choice]
    print('  player %-9s -> Barry %-9s stage2 = dex %s' % (choice, line, LINES[line][2]))
