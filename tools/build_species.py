#!/usr/bin/env python3
"""Build the committed species/move/learnset/ability/type data files.

Source: the PokeAPI veekun CSV dump (BSD-3-Clause data, NOT ROM-derived -> safe to commit).
Output shapes are defined by docs/DATA_CONTRACT.md sections 1-5, and nothing else.

    python tools/build_species.py            # offline if tools/.cache/veekun is populated
    python tools/build_species.py --refresh  # re-download every CSV

Downloads are cached under tools/.cache/veekun/ (gitignored) via curl, which uses the
Windows Schannel TLS backend and therefore sidesteps the anaconda _ssl DLL quirk
documented in docs/research/species-data.md section 0.
"""
import csv
import json
import os
import re
import subprocess
import sys
from collections import defaultdict

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
CACHE = os.path.join(ROOT, 'tools', '.cache', 'veekun')
OUT = os.path.join(ROOT, 'data')
BASE = 'https://raw.githubusercontent.com/PokeAPI/pokeapi/master/data/v2/csv'
REFRESH = '--refresh' in sys.argv
ENGLISH = 9  # local_language_id

MAX_DEX = 1025
VALID_TYPES = [
    'normal', 'fighting', 'flying', 'poison', 'ground', 'rock', 'bug', 'ghost', 'steel',
    'fire', 'water', 'grass', 'electric', 'psychic', 'ice', 'dragon', 'dark', 'fairy',
]
VALID_GROWTH = ['erratic', 'fast', 'medium-fast', 'medium-slow', 'slow', 'fluctuating']

CSVS = [
    'pokemon_species', 'pokemon_species_names', 'pokemon', 'pokemon_stats', 'stats',
    'pokemon_types', 'types', 'type_efficacy', 'pokemon_abilities', 'abilities',
    'ability_names', 'ability_prose', 'pokemon_egg_groups', 'egg_groups', 'growth_rates',
    'pokemon_evolution', 'evolution_triggers', 'moves', 'move_names',
    'move_damage_classes', 'move_targets', 'move_flags', 'move_flag_map',
    'move_effect_prose', 'pokemon_moves', 'pokemon_move_methods', 'version_groups',
    'items', 'locations',
]

# veekun names growth rates after how the RATE behaves, which is the opposite of the
# series' own names for two of them. Disambiguated from the `formula` column, not guessed:
#   slow-then-very-fast -> x^3(160-x)/100 at L100 = 600,000 total EXP  = Erratic
#   fast-then-very-slow -> x^3(32+x/2)/50 at L100 = 1,640,000 total EXP = Fluctuating
GROWTH_RENAME = {
    'slow': 'slow', 'medium': 'medium-fast', 'fast': 'fast', 'medium-slow': 'medium-slow',
    'slow-then-very-fast': 'erratic', 'fast-then-very-slow': 'fluctuating',
}

# veekun ships legacy internal egg-group names; the contract wants the modern display
# slugs (Pikachu is ["field","fairy"], not ["ground","fairy"]).
EGG_RENAME = {
    'ground': 'field', 'plant': 'grass', 'humanshape': 'human-like',
    'indeterminate': 'amorphous', 'no-eggs': 'undiscovered',
}

# Post-generator corrections to abilities.json, applied HERE so that rerunning this
# script is idempotent. Without this table a rebuild silently reverts them and the
# committed data file loses information -- which is exactly what happened once.
#
# `hook` is documentation: no code reads it (docs/research/ability-implementation.md
# section 4). `tier` is the one that means something -- it records what the engine
# actually implements. The 14 below are the Mega-critical abilities now written in
# src/battle/abilities/, so they are no longer tier 3 / hook `none`.
ABILITY_HOOK_OVERRIDES = {
    'shadow-tag':      ('onSwitchAttempt', 1),
    'steadfast':       ('onFlinch', 1),
    'skill-link':      ('onMultiHitCount', 1),
    'parental-bond':   ('onMultiHitCount', 1),
    'delta-stream':    ('onFieldEnter', 1),
    'stalwart':        ('onRedirect', 2),
    'unseen-fist':     ('onProtectCheck', 1),
    'piercing-drill':  ('onProtectCheck', 1),
    'dragonize':       ('onModifyMoveType', 1),
    'mega-sol':        ('onWeatherView', 1),
    'spicy-spray':     ('onHitTaken', 1),
    'eelevate':        ('onTypeImmunity', 1),
    'fire-mane':       ('onDamageCalc', 1),
    'aura-guard':      ('onDamageCalc', 1),
}

# veekun's `ability_prose` is outdated or truncated for these three.
ABILITY_TEXT_OVERRIDES = {
    # veekun still carries Gen 6's "half power"; it is a quarter from Gen 7 on
    'parental-bond':
        "Lets the bearer hit twice with damaging moves.  The second hit deals a quarter of the damage.",
    # veekun's row stops mid-sentence
    'piercing-drill':
        "When the Pok\u00e9mon uses contact moves, it can hit even targets that are protecting themselves, dealing 1/4 of the damage it would otherwise deal.",
    # veekun paraphrases; this states the actual multiplier
    'fire-mane':
        "When the Pok\u00e9mon uses a Fire-type move, its Attack or Sp. Atk is multiplied by 1.5.",
}

# Ability -> engine hook, grouped by the hook the turn pipeline actually needs
# (docs/research/species-data.md section 9). Order matters: first group wins for the
# handful of abilities that appear twice.
HOOKS = [
    ('onSwitchIn', 1, [
        'intimidate', 'drought', 'drizzle', 'sand-stream', 'snow-warning', 'electric-surge',
        'psychic-surge', 'grassy-surge', 'misty-surge', 'trace', 'download', 'imposter',
        'intrepid-sword', 'dauntless-shield', 'protosynthesis', 'quark-drive',
        'supreme-overlord', 'as-one-glastrier', 'orichalcum-pulse', 'hadron-engine',
        'embody-aspect', 'zero-to-hero', 'tera-shift']),
    ('onTypeImmunity', 1, [
        'levitate', 'volt-absorb', 'water-absorb', 'flash-fire', 'lightning-rod',
        'storm-drain', 'motor-drive', 'sap-sipper', 'dry-skin', 'earth-eater',
        'well-baked-body', 'wind-rider', 'bulletproof', 'soundproof', 'good-as-gold',
        'purifying-salt']),
    ('onDamageCalc', 1, [
        'huge-power', 'pure-power', 'adaptability', 'technician', 'sheer-force',
        'tinted-lens', 'solid-rock', 'filter', 'prism-armor', 'thick-fat', 'heatproof',
        'multiscale', 'shadow-shield', 'ice-scales', 'fur-coat', 'guts', 'hustle',
        'overgrow', 'blaze', 'torrent', 'swarm', 'flower-gift', 'solar-power', 'iron-fist',
        'strong-jaw', 'mega-launcher', 'tough-claws', 'sharpness', 'punk-rock',
        'rocky-payload', 'transistor', 'dragons-maw', 'steelworker', 'water-bubble',
        'neuroforce', 'stakeout', 'analytic', 'reckless', 'sand-force', 'steely-spirit',
        'toxic-boost', 'flare-boost', 'fairy-aura', 'dark-aura', 'aura-break']),
    ('onTurnOrder', 1, [
        'swift-swim', 'chlorophyll', 'sand-rush', 'slush-rush', 'surge-surfer',
        'quick-feet', 'unburden', 'prankster', 'gale-wings', 'triage', 'stall',
        'mycelium-might', 'quick-draw']),
    ('onModifyMoveType', 1, [
        'pixilate', 'refrigerate', 'aerilate', 'galvanize', 'normalize', 'liquid-voice',
        'protean', 'libero', 'color-change', 'rks-system', 'multitype']),
    ('onAccuracyCheck', 1, [
        'no-guard', 'compound-eyes', 'sand-veil', 'snow-cloak', 'tangled-feet',
        'wonder-skin', 'keen-eye', 'unaware', 'mold-breaker', 'teravolt', 'turboblaze',
        'scrappy', 'infiltrator']),
    ('onTurnEnd', 1, [
        'speed-boost', 'moody', 'poison-heal', 'rain-dish', 'ice-body', 'shed-skin',
        'hydration', 'healer', 'bad-dreams', 'harvest', 'slow-start', 'truant',
        'zen-mode', 'schooling', 'power-construct', 'hunger-switch']),
    ('onContactHit', 1, [
        'static', 'flame-body', 'poison-point', 'effect-spore', 'rough-skin', 'iron-barbs',
        'cute-charm', 'mummy', 'lingering-aroma', 'gooey', 'tangling-hair',
        'wandering-spirit', 'perish-body', 'aftermath', 'innards-out', 'cursed-body',
        'pickpocket', 'rattled', 'justified', 'weak-armor', 'anger-point', 'berserk',
        'water-compaction', 'steam-engine', 'thermal-exchange', 'seed-sower',
        'toxic-debris', 'electromorphosis', 'wind-power']),
    ('onStatusApply', 1, [
        'immunity', 'limber', 'water-veil', 'magma-armor', 'insomnia', 'vital-spirit',
        'own-tempo', 'oblivious', 'inner-focus', 'shield-dust', 'overcoat', 'sweet-veil',
        'flower-veil', 'leaf-guard', 'comatose', 'magic-guard', 'magic-bounce',
        'natural-cure', 'regenerator', 'clear-body', 'white-smoke', 'full-metal-body',
        'hyper-cutter', 'big-pecks', 'defiant', 'competitive', 'contrary', 'simple',
        'mirror-armor']),
    ('onHpCross', 1, [
        'sturdy', 'shell-armor', 'battle-armor', 'disguise', 'ice-face', 'shields-down',
        'moxie', 'chilling-neigh', 'grim-neigh', 'beast-boost', 'soul-heart',
        'battle-bond', 'gulp-missile', 'emergency-exit', 'wimp-out']),
    ('onFieldMisc', 2, [
        'air-lock', 'cloud-nine', 'unnerve', 'klutz', 'pressure', 'forewarn', 'frisk',
        'anticipation', 'gluttony', 'ripen', 'cheek-pouch', 'sticky-hold', 'suction-cups',
        'damp', 'friend-guard', 'telepathy', 'symbiosis', 'power-spot', 'battery',
        'neutralizing-gas', 'costar', 'commander', 'opportunist', 'sword-of-ruin',
        'beads-of-ruin', 'tablets-of-ruin', 'vessel-of-ruin']),
    ('none', 3, [
        'run-away', 'pickup', 'honey-gather', 'illuminate', 'stench', 'synchronize',
        'rivalry', 'early-bird', 'ball-fetch', 'magician', 'super-luck', 'sniper',
        'serene-grace']),
]

# Learnset version-group fallback, newest usable first. Excluded on purpose:
# 21,22,26,27,30,31 carry zero rows; 32 (`champions`) has 19,810 rows but ZERO level-up
# rows and would silently hand 44 species an empty movepool.
VG_ORDER = [25, 20, 23, 24, 18, 17, 19, 16, 15, 14, 11, 10, 9, 8,
            7, 6, 5, 13, 12, 4, 3, 2, 1]


# --------------------------------------------------------------------------- io
def fetch():
    os.makedirs(CACHE, exist_ok=True)
    gd = os.path.join(os.path.dirname(CACHE), '.gdignore')
    if not os.path.exists(gd):
        open(gd, 'w').close()  # keep Godot's importer out of the download cache
    missing = [f for f in CSVS
               if REFRESH or not os.path.exists(os.path.join(CACHE, f + '.csv'))]
    if not missing:
        print('cache: all %d CSVs present (offline build)' % len(CSVS))
        return
    print('cache: downloading %d CSV(s) from PokeAPI ...' % len(missing))
    failed = []
    for f in missing:
        dest = os.path.join(CACHE, f + '.csv')
        rc = subprocess.call(['curl', '-sSL', '--fail', '--retry', '3', '--max-time',
                              '300', '-o', dest, '%s/%s.csv' % (BASE, f)])
        if rc != 0 or not os.path.exists(dest) or os.path.getsize(dest) == 0:
            failed.append(f)
            if os.path.exists(dest):
                os.remove(dest)
    if failed:
        sys.exit('\nNETWORK FAILURE: could not download %d CSV(s): %s\n'
                 'Refusing to emit partial data. Fix the network and re-run.'
                 % (len(failed), ', '.join(failed)))
    print('cache: downloaded %d CSV(s)' % len(missing))


def load(name):
    path = os.path.join(CACHE, name + '.csv')
    if not os.path.exists(path):
        sys.exit('missing cached CSV: %s (run with --refresh)' % path)
    with open(path, encoding='utf-8') as fh:
        return list(csv.DictReader(fh))


def num(v, default=None):
    v = (v or '').strip()
    return int(v) if v else default


def slugify(text):
    t = (text or '').strip().lower().rstrip('.')
    t = t.replace('$effect_chance%', '').replace('$effect_chance', '')
    t = re.sub(r'^has an? chance to ', 'chance-to ', t)
    t = re.sub(r'\bthe (target|user)$', '', t)
    t = re.sub(r'[^a-z0-9]+', '-', t).strip('-')
    return t or None


# ------------------------------------------------------------------- lookups
fetch()

TYPE = {int(r['id']): r['identifier'] for r in load('types')}
STAT = {int(r['id']): r['identifier'] for r in load('stats')}
GROWTH = {int(r['id']): GROWTH_RENAME[r['identifier']] for r in load('growth_rates')}
EGG = {int(r['id']): EGG_RENAME.get(r['identifier'], r['identifier'])
       for r in load('egg_groups')}
ABIL = {int(r['id']): r['identifier'] for r in load('abilities')}
MOVE = {int(r['id']): r['identifier'] for r in load('moves')}
DCLASS = {int(r['id']): r['identifier'] for r in load('move_damage_classes')}
TARGET = {int(r['id']): r['identifier'] for r in load('move_targets')}
FLAG = {int(r['id']): r['identifier'] for r in load('move_flags')}
METHOD = {int(r['id']): r['identifier'] for r in load('pokemon_move_methods')}
TRIGGER = {int(r['id']): r['identifier'] for r in load('evolution_triggers')}
ITEM = {int(r['id']): r['identifier'] for r in load('items')}
LOCATION = {int(r['id']): r['identifier'] for r in load('locations')}
VG_NAME = {int(r['id']): r['identifier'] for r in load('version_groups')}

SPECIES_NAME = {int(r['pokemon_species_id']): r['name'] for r in load('pokemon_species_names')
                if num(r['local_language_id']) == ENGLISH}
MOVE_NAME = {int(r['move_id']): r['name'] for r in load('move_names')
             if num(r['local_language_id']) == ENGLISH}
ABILITY_NAME = {int(r['ability_id']): r['name'] for r in load('ability_names')
                if num(r['local_language_id']) == ENGLISH}
EFFECT_TEXT = {int(r['move_effect_id']): r['short_effect'] for r in load('move_effect_prose')
               if num(r['local_language_id']) == ENGLISH}
ABILITY_TEXT = {int(r['ability_id']): r['short_effect'] for r in load('ability_prose')
                if num(r['local_language_id']) == ENGLISH}

STAT_KEY = {'hp': 'hp', 'attack': 'atk', 'defense': 'def',
            'special-attack': 'spa', 'special-defense': 'spd', 'speed': 'spe'}

# ------------------------------------------------------------------- species
species = {}
for r in load('pokemon_species'):
    sid = num(r['id'])
    if sid > MAX_DEX:
        continue
    species[sid] = {
        'id': sid,
        'name': SPECIES_NAME.get(sid, r['identifier']),
        'types': [],
        'stats': {},
        'abilities': [],
        'hiddenAbility': None,
        'growthRate': GROWTH[num(r['growth_rate_id'])],
        'baseExp': None,
        'catchRate': num(r['capture_rate']),
        'genderRate': num(r['gender_rate'], -1),
        'eggGroups': [],
        'hatchCounter': num(r['hatch_counter']),
        'height': None,
        'weight': None,
        'evolvesFrom': num(r['evolves_from_species_id']),
        'evolutions': [],
        'generation': num(r['generation_id']),
        'sprite': {'front': 'pkmn/%03d.png' % sid,
                   'back': 'pkmn/back/%03d.png' % sid,
                   'icon': 'icon/%03d.png' % sid},
        '_types': [],
        '_abilities': [],
    }

# Stats/types/abilities key on pokemon_id (1351 rows incl. megas & regional forms);
# only is_default=1 rows map back to a national-dex species.
pk2sp = {}
for r in load('pokemon'):
    sid = num(r['species_id'])
    if r['is_default'] == '1' and sid in species:
        pk2sp[num(r['id'])] = sid
        species[sid]['baseExp'] = num(r['base_experience'])
        species[sid]['height'] = num(r['height'])
        species[sid]['weight'] = num(r['weight'])

for r in load('pokemon_types'):
    sid = pk2sp.get(num(r['pokemon_id']))
    if sid:
        species[sid]['_types'].append((num(r['slot']), TYPE[num(r['type_id'])]))

for r in load('pokemon_stats'):
    sid = pk2sp.get(num(r['pokemon_id']))
    if sid:
        species[sid]['stats'][STAT_KEY[STAT[num(r['stat_id'])]]] = num(r['base_stat'])

for r in load('pokemon_abilities'):
    sid = pk2sp.get(num(r['pokemon_id']))
    if not sid:
        continue
    name = ABIL[num(r['ability_id'])]
    if r['is_hidden'] == '1':
        species[sid]['hiddenAbility'] = name
    else:
        species[sid]['_abilities'].append((num(r['slot']), name))

for r in load('pokemon_egg_groups'):
    sid = num(r['species_id'])
    if sid in species:
        species[sid]['eggGroups'].append(EGG[num(r['egg_group_id'])])

for s in species.values():
    s['types'] = [t for _, t in sorted(s.pop('_types'))]
    s['abilities'] = [a for _, a in sorted(s.pop('_abilities'))]

# --------------------------------------------------------------- evolutions
# One row PER VERSION GROUP, so branches duplicate (Eevee: 19 rows, 8 real targets).
# Dedupe on (target, trigger) keeping the newest version group.
EVO_COND = [
    ('level', 'minimum_level', int),
    ('happiness', 'minimum_happiness', int),
    ('beauty', 'minimum_beauty', int),
    ('affection', 'minimum_affection', int),
    ('timeOfDay', 'time_of_day', str),
    ('gender', 'gender_id', int),
    ('relativePhysicalStats', 'relative_physical_stats', int),
    ('knownMove', 'known_move_id', lambda v: MOVE.get(int(v), int(v))),
    ('knownMoveType', 'known_move_type_id', lambda v: TYPE.get(int(v), int(v))),
    ('partySpecies', 'party_species_id', int),
    ('partyType', 'party_type_id', lambda v: TYPE.get(int(v), int(v))),
    ('tradeSpecies', 'trade_species_id', int),
    ('item', 'trigger_item_id', lambda v: ITEM.get(int(v), int(v))),
    ('heldItem', 'held_item_id', lambda v: ITEM.get(int(v), int(v))),
    ('location', 'location_id', lambda v: LOCATION.get(int(v), int(v))),
]
raw_edges = 0
for r in load('pokemon_evolution'):
    to = num(r['evolved_species_id'])
    if to not in species:
        continue
    frm = species[to]['evolvesFrom']
    if frm not in species:
        continue
    evo = {'to': to, 'method': TRIGGER.get(num(r['evolution_trigger_id']), 'unknown')}
    for key, col, conv in EVO_COND:
        v = (r.get(col) or '').strip()
        if v:
            evo[key] = conv(v)
    for flag in ('needs_overworld_rain', 'turn_upside_down'):
        if r.get(flag) == '1':
            evo[{'needs_overworld_rain': 'needsRain',
                 'turn_upside_down': 'upsideDown'}[flag]] = True
    evo['_vg'] = num(r['version_group_id'], 0)
    species[frm]['evolutions'].append(evo)
    raw_edges += 1

evo_edges = 0
for s in species.values():
    best = {}
    for e in s['evolutions']:
        k = (e['to'], e['method'])
        if k not in best or e['_vg'] > best[k]['_vg']:
            best[k] = e
    s['evolutions'] = sorted(
        ({k: v for k, v in e.items() if k != '_vg'} for e in best.values()),
        key=lambda e: (e['to'], e['method']))
    evo_edges += len(s['evolutions'])

# ---------------------------------------------------------------- learnsets
by_species = defaultdict(lambda: defaultdict(list))
for r in load('pokemon_moves'):
    sid = pk2sp.get(num(r['pokemon_id']))
    if sid:
        by_species[sid][num(r['version_group_id'])].append(r)

learnsets = {}
vg_spread = defaultdict(int)
no_learnset = []
for sid in sorted(species):
    groups = by_species.get(sid, {})
    pick = next((v for v in VG_ORDER if v in groups), None)
    if pick is None:
        no_learnset.append(sid)
        learnsets[str(sid)] = {'levelUp': [], 'machine': [], 'egg': [], 'tutor': []}
        continue
    vg_spread[VG_NAME[pick]] += 1
    level_up, buckets = [], {'machine': set(), 'egg': set(), 'tutor': set()}
    for r in groups[pick]:
        move = MOVE[num(r['move_id'])]
        method = METHOD[num(r['pokemon_move_method_id'])]
        if method == 'level-up':
            level_up.append([num(r['level'], 0), move])
        elif method in buckets:
            buckets[method].add(move)
    level_up.sort(key=lambda p: (p[0], p[1]))
    learnsets[str(sid)] = {
        'levelUp': level_up,
        'machine': sorted(buckets['machine']),
        'egg': sorted(buckets['egg']),
        'tutor': sorted(buckets['tutor']),
    }

# -------------------------------------------------------------------- moves
flags_by_move = defaultdict(list)
for r in load('move_flag_map'):
    flags_by_move[num(r['move_id'])].append(FLAG[num(r['move_flag_id'])])

# The Gen 9 effect-id gap. 93 moves in the veekun snapshot carry an EMPTY
# `effect_id`, and the engine branches on `effectId` and never on the effect
# string (multi_hit.gd, skill-link.gd), so those moves read as ordinary
# single-hit damage. This table fills in the ones whose behaviour the engine
# actually implements; the rest stay null on purpose.
#
# Ids start at 20001, deliberately clear of veekun's own space -- the highest
# real effect_id is 10006 (the Colosseum/XD shadow effects), so nothing upstream
# can ever collide with these.
#
#   20001  population-bomb -- hits up to 10 times, accuracy rolled per hit and
#          the move stops at the first miss. Skill Link takes it to a guaranteed
#          10. https://bulbapedia.bulbagarden.net/wiki/Population_Bomb_(move)
LOCAL_EFFECT_IDS = {
    'population-bomb': 20001,
}

# Effect prose for the ids above. veekun has none, and `slugify` runs on the
# upstream text, so these are written already in the emitted slug form.
LOCAL_EFFECT_TEXT = {
    20001: 'hits-up-to-10-times-in-one-turn-checking-accuracy-each-hit',
}

moves = []
for r in load('moves'):
    mid = num(r['id'])
    if mid > 10000:  # Colosseum/XD shadow moves
        continue
    eid = num(r['effect_id'])
    if eid is None:
        eid = LOCAL_EFFECT_IDS.get(r['identifier'])
    moves.append({
        'id': mid,
        'name': MOVE_NAME.get(mid, r['identifier']),
        # contract key `name` is the display name; learnsets reference the veekun slug,
        # so carry the slug too or the runtime cannot join the two files.
        'slug': r['identifier'],
        'type': TYPE[num(r['type_id'])],
        'category': DCLASS[num(r['damage_class_id'])],
        'power': num(r['power']),
        # veekun encodes "no accuracy check" as "" (288 moves) AND as "0" for three
        # gen-9 moves. Both must become null or those three always miss.
        'accuracy': (num(r['accuracy']) or None),
        'pp': num(r['pp']),
        'priority': num(r['priority'], 0),
        'target': TARGET[num(r['target_id'])],
        'effect': slugify(EFFECT_TEXT.get(eid)) or LOCAL_EFFECT_TEXT.get(eid),
        'effectId': eid,
        'effectChance': num(r['effect_chance']),
        'flags': sorted(flags_by_move.get(mid, [])),
        'generation': num(r['generation_id']),
    })
moves.sort(key=lambda m: m['id'])
move_slugs = {MOVE[m['id']] for m in moves}

# ---------------------------------------------------------------- abilities
hook_of, tier_of = {}, {}
for hook, tier, names in HOOKS:
    for n in names:
        hook_of.setdefault(n, hook)
        tier_of.setdefault(n, tier)

abilities = []
for r in load('abilities'):
    if r['is_main_series'] != '1':
        continue
    aid = num(r['id'])
    slug = r['identifier']
    hook, tier = ABILITY_HOOK_OVERRIDES.get(
        slug, (hook_of.get(slug, 'none'), tier_of.get(slug, 3)))
    abilities.append({
        'id': aid,
        'name': ABILITY_NAME.get(aid, slug),
        'slug': slug,  # species.abilities / hiddenAbility reference this, not `name`
        'hook': hook,
        'text': ABILITY_TEXT_OVERRIDES.get(slug, ABILITY_TEXT.get(aid, '')),
        'tier': tier,
    })
abilities.sort(key=lambda a: a['id'])
ability_slugs = {r['identifier'] for r in load('abilities') if r['is_main_series'] == '1'}

# ---------------------------------------------------------------- typechart
typechart = {a: {d: 1.0 for d in VALID_TYPES} for a in VALID_TYPES}
for r in load('type_efficacy'):
    a, d = TYPE[num(r['damage_type_id'])], TYPE[num(r['target_type_id'])]
    if a in typechart and d in typechart[a]:
        typechart[a][d] = num(r['damage_factor']) / 100.0

# ------------------------------------------------------------------- output
species_list = [species[i] for i in sorted(species)]

os.makedirs(OUT, exist_ok=True)


def write(name, obj):
    path = os.path.join(OUT, name)
    with open(path, 'w', encoding='utf-8') as fh:
        json.dump(obj, fh, separators=(',', ':'), sort_keys=True)
        fh.write('\n')
    return path, os.path.getsize(path)


written = [
    write('species.json', species_list),
    write('moves.json', moves),
    write('learnsets.json', learnsets),
    write('abilities.json', abilities),
    write('typechart.json', typechart),
]

# --------------------------------------------------------------- assertions
FAILURES = []
CHECKS = []


def check(label, ok, detail=''):
    CHECKS.append((label, bool(ok), detail))
    if not ok:
        FAILURES.append('%s -- %s' % (label, detail))


ids = [s['id'] for s in species_list]
check('species count == 1025', len(species_list) == 1025, 'got %d' % len(species_list))
check('ids 1..1025 contiguous, no gaps', ids == list(range(1, 1026)),
      'first gap at %s' % next((i for i, v in enumerate(ids, 1) if v != i), 'none'))

bad_types = [s['name'] for s in species_list
             if not (1 <= len(s['types']) <= 2)
             or any(t not in VALID_TYPES for t in s['types'])]
check('every species has 1-2 valid types', not bad_types,
      '%d bad: %s' % (len(bad_types), bad_types[:5]))

no_abil = [s['name'] for s in species_list if len(s['abilities']) < 1]
check('every species has >=1 ability', not no_abil,
      '%d bad: %s' % (len(no_abil), no_abil[:5]))

bad_growth = sorted({s['growthRate'] for s in species_list} - set(VALID_GROWTH))
check('every growthRate in the 6 allowed values', not bad_growth, str(bad_growth))

unknown_ab = sorted({a for s in species_list for a in s['abilities']} |
                    {s['hiddenAbility'] for s in species_list if s['hiddenAbility']}
                    - ability_slugs)
unknown_ab = [a for a in unknown_ab if a not in ability_slugs]
check('every species ability resolves to abilities.json', not unknown_ab, str(unknown_ab[:5]))

# A typo in either override table would otherwise be invisible: the entry simply
# never applies and the rebuild quietly reverts the correction.
bad_ovr = sorted((set(ABILITY_HOOK_OVERRIDES) | set(ABILITY_TEXT_OVERRIDES)) - ability_slugs)
check('every ability override slug is a real ability', not bad_ovr, str(bad_ovr))

# The local move-effect ids must land on real moves, for the same reason.
bad_eff = sorted(set(LOCAL_EFFECT_IDS) - move_slugs)
check('every local move-effect slug is a real move', not bad_eff, str(bad_eff))

check('typechart is 18x18',
      len(typechart) == 18 and all(len(v) == 18 for v in typechart.values()),
      '%d rows' % len(typechart))
check('Fairy exists in typechart',
      'fairy' in typechart and 'fairy' in typechart['normal'], '')
check('dragon -> fairy == 0.0 (gen6)', typechart['dragon']['fairy'] == 0.0,
      str(typechart['dragon']['fairy']))
check('steel -> ghost == 1.0 (gen6 resist removed)', typechart['steel']['ghost'] == 1.0,
      str(typechart['steel']['ghost']))
check('dark -> steel == 1.0 (gen6 resist removed)', typechart['dark']['steel'] == 1.0,
      str(typechart['dark']['steel']))

unresolved = set()
for sid, ls in learnsets.items():
    for lvl, mv in ls['levelUp']:
        if mv not in move_slugs:
            unresolved.add(mv)
    for key in ('machine', 'egg', 'tutor'):
        for mv in ls[key]:
            if mv not in move_slugs:
                unresolved.add(mv)
check('every learnset move resolves to a real move', not unresolved,
      '%d unresolved: %s' % (len(unresolved), sorted(unresolved)[:5]))
check('every species has a non-empty level-up learnset', not no_learnset,
      '%d empty: %s' % (len(no_learnset), no_learnset[:5]))

SPOT = {25: 'Pikachu', 448: 'Lucario', 493: 'Arceus', 649: 'Genesect', 1025: 'Pecharunt'}
for sid, want in SPOT.items():
    got = species_list[sid - 1]['name']
    check('spot-check #%d == %s' % (sid, want),
          species_list[sid - 1]['id'] == sid and got == want, 'got %r' % got)

# ----------------------------------------------------------------- report
print()
print('=' * 72)
print('BUILD: %d species | %d moves | %d abilities | %d learnsets | %d types'
      % (len(species_list), len(moves), len(abilities), len(learnsets), len(typechart)))
print('evolution edges: %d raw -> %d after per-version-group dedupe' % (raw_edges, evo_edges))
print('learnset sources: %s'
      % dict(sorted(vg_spread.items(), key=lambda kv: -kv[1])))
for path, size in written:
    print('  %-24s %8.2f KB' % (os.path.relpath(path, ROOT).replace('\\', '/'),
                                size / 1024.0))
print('-' * 72)
print('ASSERTIONS')
for label, ok, detail in CHECKS:
    print('  [%s] %-46s %s' % ('PASS' if ok else 'FAIL', label, '' if ok else detail))
print('-' * 72)
if FAILURES:
    print('%d ASSERTION(S) FAILED' % len(FAILURES))
    sys.exit(1)
print('ALL %d ASSERTIONS PASSED' % len(CHECKS))
