#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Which of the 1025 species can the player actually get, and why not?

This is the check that proves the evolution rework worked. Fixing 73 impossible
edges is only meaningful if it made species reachable, and "unreachable" on its
own is not a bug report -- most of the dex is unreachable today simply because
the game is a nine-map vertical slice. So this walks the whole obtainability
graph and separates the reasons:

    WILD          in data/rom/encounters.json somewhere
    GIFT          a starter
    EVOLUTION     reachable from something reachable, by a performable edge
  --------------------------------------------------------------------------
    BROKEN_EVO    a reachable parent, but the edge CANNOT BE PERFORMED at all.
                  This is the bug the evolution rework exists to drive to zero.
    NEEDS_ITEM    a reachable parent and a fine edge, but the item it requires
                  does not exist in data/items.json. A real blocker, a DIFFERENT
                  owner (evolution-audit.md 6.1) -- reported, never conflated.
    NEEDS_FRIEND  a reachable parent, but the edge needs another species in the
                  party that is not itself reachable.
    NOT_IN_GAME   nothing in its line is obtainable. EXPECTED for a slice.

Exit status is 0 only when BROKEN_EVO is empty: that bucket is the regression
this file guards. NEEDS_ITEM and NEEDS_FRIEND are reported and do not fail, so
this can be wired into CI now and stay useful while items.json is unfinished.

    python tools/check_reachability.py
    python tools/check_reachability.py --list        # name every species, bucket by bucket
    python tools/check_reachability.py --strict      # also fail on NEEDS_ITEM

Performability rules are imported from fix_evolutions, not restated, so the two
files cannot drift.
"""

from __future__ import print_function

import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, HERE)

import fix_evolutions as fx                                  # noqa: E402

SPECIES = os.path.join(ROOT, 'data', 'species.json')
ITEMS = os.path.join(ROOT, 'data', 'items.json')
LEARNSETS = os.path.join(ROOT, 'data', 'learnsets.json')
# Gitignored: regenerated from the owner's ROM. Absent on a fresh checkout.
ENCOUNTERS = os.path.join(ROOT, 'data', 'rom', 'encounters.json')

## The three Sinnoh starters. One is handed over; all three are listed because
## which one is a player choice and the dex does not care.
STARTERS = (387, 390, 393)

## Encounter method keys in data/rom/encounters.json whose lists hold species.
ENCOUNTER_SLOTS = ('grass', 'surf', 'oldRod', 'goodRod', 'superRod',
                   'rockSmash', 'headbutt', 'honey', 'swarm', 'radar',
                   'morning', 'day', 'night', 'dual', 'feebasTiles')

WILD, GIFT, EVOLUTION = 'WILD', 'GIFT', 'EVOLUTION'
BROKEN_EVO, NEEDS_ITEM, NEEDS_FRIEND, NOT_IN_GAME = (
    'BROKEN_EVO', 'NEEDS_ITEM', 'NEEDS_FRIEND', 'NOT_IN_GAME')

ORDER = [WILD, GIFT, EVOLUTION, BROKEN_EVO, NEEDS_ITEM, NEEDS_FRIEND, NOT_IN_GAME]


def load(path):
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def wild_species():
    """Every species reachable in the wild, and whether the table was found."""
    if not os.path.exists(ENCOUNTERS):
        return set(), False
    out = set()
    for area in load(ENCOUNTERS).values():
        if not isinstance(area, dict):
            continue
        for slot in ENCOUNTER_SLOTS:
            for row in area.get(slot, []) or []:
                if isinstance(row, dict) and row.get('species'):
                    out.add(int(row['species']))
    return out, True


def blocker(edge, have_items, learnable, reachable):
    """Why this edge cannot be taken right now, or None when it can.

    Returns one of BROKEN_EVO / NEEDS_ITEM / NEEDS_FRIEND. The first two rules
    come straight from fix_evolutions so that "impossible" means exactly what the
    rework's own audit means by it.
    """
    if edge.get('method') in fx.DEAD_METHODS:
        return BROKEN_EVO
    if fx.DEAD_KEYS.intersection(edge.keys()):
        return BROKEN_EVO
    if edge.get('knownMove') in fx.DEAD_KNOWN_MOVES:
        return BROKEN_EVO
    # A bare level-up with no level and no condition can never fire.
    if (edge.get('method') == 'level-up'
            and not set(edge.keys()) - set(['to', 'method'])):
        return BROKEN_EVO
    if edge.get('knownMove') and edge['knownMove'] not in learnable:
        return BROKEN_EVO

    for key in ('item', 'heldItem'):
        if edge.get(key) and edge[key] not in have_items:
            return NEEDS_ITEM

    # Needs a companion in the party. Mantyke wants a Remoraid; Pancham wants any
    # Dark type. Performable only once that companion is itself obtainable.
    if edge.get('partySpecies') and int(edge['partySpecies']) not in reachable:
        return NEEDS_FRIEND
    if edge.get('partyType'):
        if not any(edge['partyType'] in TYPES_OF.get(s, ()) for s in reachable):
            return NEEDS_FRIEND
    return None


TYPES_OF = {}


def classify():
    species = load(SPECIES)
    by_id = dict((s['id'], s) for s in species)
    for s in species:
        TYPES_OF[s['id']] = tuple(s.get('types', []))

    have_items = set(i['id'] for i in load(ITEMS))
    learn = load(LEARNSETS) if os.path.exists(LEARNSETS) else {}

    def learnable_by(dex):
        row = learn.get(str(dex), {})
        out = set()
        for pair in row.get('levelUp', []):
            if isinstance(pair, list) and len(pair) >= 2:
                out.add(pair[1])
        for bucket in ('machine', 'egg', 'tutor'):
            out.update(row.get(bucket, []) or [])
        return out

    wild, had_encounters = wild_species()
    source = {}
    for dex in sorted(wild):
        source[dex] = WILD
    for dex in STARTERS:
        source.setdefault(dex, GIFT)

    # Closure: keep walking edges out of reachable species until nothing new
    # appears. partySpecies/partyType depend on what is reachable, so this has to
    # be a fixed point rather than one pass.
    reachable = set(source)
    while True:
        grew = False
        for dex in sorted(reachable):
            for edge in by_id.get(dex, {}).get('evolutions', []):
                target = int(edge.get('to', 0))
                if target in reachable or target not in by_id:
                    continue
                if blocker(edge, have_items, learnable_by(dex), reachable) is None:
                    reachable.add(target)
                    source[target] = EVOLUTION
                    grew = True
        if not grew:
            break

    # Everything still unreachable: say why, preferring the most actionable
    # reason across all of its parents.
    parents = {}
    for s in species:
        for edge in s.get('evolutions', []):
            parents.setdefault(int(edge['to']), []).append((s['id'], edge))

    RANK = [BROKEN_EVO, NEEDS_ITEM, NEEDS_FRIEND]
    for s in species:
        dex = s['id']
        if dex in source:
            continue
        reasons = set()
        for frm, edge in parents.get(dex, []):
            if frm not in reachable:
                continue
            why = blocker(edge, have_items, learnable_by(frm), reachable)
            if why:
                reasons.add(why)
        if not reasons:
            source[dex] = NOT_IN_GAME
            continue
        for candidate in RANK:
            if candidate in reasons:
                source[dex] = candidate
                break
    return species, source, had_encounters


def main(argv):
    species, source, had_encounters = classify()
    names = dict((s['id'], s['name']) for s in species)

    buckets = dict((k, []) for k in ORDER)
    for dex in sorted(source):
        buckets[source[dex]].append(dex)

    print('=' * 74)
    print('REACHABILITY -- %d species' % len(species))
    print('=' * 74)
    if not had_encounters:
        print('WARNING: data/rom/encounters.json is absent (it is gitignored).')
        print('         Only the starters seed the walk, so NOT_IN_GAME is')
        print('         meaningless in this run. BROKEN_EVO is still valid.')
        print()

    obtainable = sum(len(buckets[k]) for k in (WILD, GIFT, EVOLUTION))
    for key in ORDER:
        print('  %-13s %4d' % (key, len(buckets[key])))
    print('  %-13s %4d of %d' % ('obtainable', obtainable, len(species)))
    print()

    if buckets[BROKEN_EVO]:
        print('BROKEN_EVO -- a reachable parent and an unperformable edge.')
        print('This is the regression bucket and it must be empty:')
        for dex in buckets[BROKEN_EVO]:
            print('  #%-4d %s' % (dex, names[dex]))
        print()
    else:
        print('BROKEN_EVO is empty: no species is locked out by an evolution')
        print('that cannot be performed.')
        print()

    if buckets[NEEDS_ITEM]:
        print('NEEDS_ITEM -- %d species blocked ONLY by data/items.json having no'
              % len(buckets[NEEDS_ITEM]))
        print('evolution items (evolution-audit.md 6.1). Not an evolution bug:')
        head = buckets[NEEDS_ITEM][:12]
        print('  ' + ', '.join('%s (#%d)' % (names[d], d) for d in head)
              + (', ...' if len(buckets[NEEDS_ITEM]) > len(head) else ''))
        print()
    if buckets[NEEDS_FRIEND]:
        print('NEEDS_FRIEND -- %d species need a companion that is not obtainable:'
              % len(buckets[NEEDS_FRIEND]))
        print('  ' + ', '.join('%s (#%d)' % (names[d], d)
                               for d in buckets[NEEDS_FRIEND]))
        print()

    if '--list' in argv:
        for key in ORDER:
            print('-- %s (%d)' % (key, len(buckets[key])))
            for dex in buckets[key]:
                print('   #%-4d %s' % (dex, names[dex]))
            print()

    failed = bool(buckets[BROKEN_EVO])
    if '--strict' in argv and buckets[NEEDS_ITEM]:
        failed = True
        print('--strict: NEEDS_ITEM is not empty.')
    print('RESULT: %s' % ('FAIL' if failed else 'PASS'))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
