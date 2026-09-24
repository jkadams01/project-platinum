"""Rescale Barry's first two fights to the player's plausible team, not the cap ceiling.

The global rescale pins every boss ace to the cap in force. That is right for a boss the
player reaches after a stretch of play, and wrong for the opening fights, which happen
before the player has had any chance to build a team:

  Route 201 (first crossing) : 1 Pokemon, level 5, and NO Poke Balls yet (they come from
                               Sandgem, which is after this fight). Any six-Pokemon team is
                               unwinnable here by arithmetic, at any level.
  Route 203                  : starter ~L10-12 plus 2-4 caught mons at L4-8, since routes
                               201/202/203 only spawn levels 2-7.

Rule applied: early fights scale to PLAYER TEAM STATE, not to the active cap.
Re-runnable and idempotent.
"""
import json, io, shutil, sys

PATH = 'data/rom/bosses.json'
shutil.copy(PATH, PATH + '.bak')
doc = json.load(io.open(PATH, encoding='utf-8'))
bosses = doc.get('bosses', doc)
get = (lambda k: bosses[k]) if isinstance(bosses, dict) else \
      (lambda k: next(b for b in bosses if b.get('key') == k))

sp = json.load(io.open('data/species.json', encoding='utf-8'))
spl = sp if isinstance(sp, list) else sp.get('species', [])
nm = {s['id']: s['name'] for s in spl}

# --- Route 201: the opening scuffle -------------------------------------------------
# Vanilla exactly: ONE Pokemon, his starter, level 5. The level curve is higher across
# this game, but the STARTING POINT is unchanged - the player still walks in with a
# single level-5 starter, so this fight scales to that and nothing else.
r1 = get('barry_r1_route_201')
before1 = [(nm.get(p['species']), p['level']) for p in r1['party']]
starter = max(r1['party'], key=lambda p: p.get('level', 0))
# de-evolve to the first stage if the rescale had evolved it
starter['species'] = {391: 390, 392: 390, 388: 387, 389: 387, 394: 393, 395: 393}.get(
    starter['species'], starter['species'])
starter['level'] = 5
r1['party'] = [starter]
r1['partySizeException'] = (
    'One Pokemon, not six - vanilla parity. This is the first battle in the game and the '
    'player has exactly one level-5 starter and no Poke Balls yet (Sandgem comes after). '
    'The raised level curve does not move the starting point, so this fight does not move '
    'either.')
r1['scalingNote'] = 'Fixed at the vanilla opening: 1 starter, level 5. Not cap-scaled.'
r1['dynamicStarter'] = (
    "Barry carries the starter with a type advantage over the player's choice: player "
    'Turtwig -> Barry Chimchar, player Chimchar -> Barry Piplup, player Piplup -> Barry '
    'Turtwig. The stored species is a placeholder; the engine should substitute at battle '
    'start. Applies to every Barry fight, not just this one.')

# --- Route 203 --------------------------------------------------------------------
# Player has starter ~L10-12 + 2-4 caught mons at L4-8. Six at L10-13 is a real wall
# but a fair one.
r2 = get('barry_r2_route_203')
before2 = [(nm.get(p['species']), p['level']) for p in r2['party']]
r2['party'].sort(key=lambda p: p.get('level', 0))
for lvl, p in zip([10, 10, 11, 11, 12, 13], r2['party']):
    p['level'] = lvl
# his starter stays the ace
ace = next(p for p in r2['party'] if p['species'] in (390, 391, 392, 393, 394, 395))
if ace['level'] != 13:
    top = max(r2['party'], key=lambda p: p['level'])
    ace['level'], top['level'] = top['level'], ace['level']
r2['scalingNote'] = (
    'Scaled to player team state (starter ~L10-12 plus 2-4 caught mons at L4-8; routes '
    '201/202/203 only spawn levels 2-7), not to the active cap of 18.')

json.dump(doc, io.open(PATH, 'w', encoding='utf-8'), indent=2, ensure_ascii=False)

print('Route 201  BEFORE:', before1)
print('Route 201  AFTER :', [(nm.get(p['species']), p['level']) for p in r1['party']])
print()
print('Route 203  BEFORE:', before2)
print('Route 203  AFTER :', sorted([(nm.get(p['species']), p['level']) for p in r2['party']], key=lambda x: x[1]))
