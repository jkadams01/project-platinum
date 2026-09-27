#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Build the evolution items into data/items.json.

WHY THIS EXISTS. data/items.json held 93 entries -- 92 Mega Stones and the Key
Stone -- while the evolution data referenced 40 distinct items and NONE of them
existed. Every one of the 67 `use-item` evolutions was therefore as dead as the
trade evolutions were before the rework, and 23 species that the rework unblocked
were still unobtainable. See docs/research/evolution-audit.md 6.1.

THE LIST IS DERIVED, NOT TYPED. The set of items to build is read out of
data/species.json's evolution edges, so it cannot drift from the evolution data:
add an evolution that needs a new item and this script fails until the item is
described. `python tools/check_reachability.py` is the end-to-end proof.

What comes from where:
  * which items are needed  -- data/species.json (evolution edges)
  * price                   -- tools/.cache/veekun/items.csv `cost`, authoritative
  * name, description, role -- the DESIGN table below; this is authored data, the
                               same status as the Mega Stone descriptions that
                               tools/build_megas.py writes
  * evolves                 -- derived from data/species.json, so the file says
                               what each item is actually for

MERGE, NOT OVERWRITE. Mega Stone and Key Stone rows are preserved untouched, and
tools/build_megas.py preserves these rows in turn. Both tools sort the file with
`sort_rows()` so the result is byte-identical whichever ran last.

    python tools/build_items.py              # dry run, prints what would change
    python tools/build_items.py --apply      # write data/items.json
"""

from __future__ import print_function

import csv
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SPECIES = os.path.join(ROOT, 'data', 'species.json')
ITEMS = os.path.join(ROOT, 'data', 'items.json')
VEEKUN_ITEMS = os.path.join(HERE, '.cache', 'veekun', 'items.csv')

## Categories this script owns. Rows in any other category are left alone.
OURS = ('evolution-stone', 'evolution-item')

## Roles, which decide category/consumable:
##   stone  a classic evolution stone, used on the Pokemon and consumed
##   use    a bespoke Gen 7-9 use-item, used on the Pokemon and consumed
##   hold   held while levelling up; NOT consumed (this is what the 16 trade-item
##          evolutions became under owner rule 2)
HOLD_SUFFIX = ' Certain Pokemon evolve when they level up holding it.'
USE_SUFFIX = ' Use it on the right Pokemon and it will evolve.'
STONE_SUFFIX = ' It makes certain species of Pokemon evolve.'

# id -> (display name, role, flavour). The mechanic sentence is appended by role,
# so the three families cannot describe themselves inconsistently.
DESIGN = {
    # ---- the ten classic stones ------------------------------------------
    'fire-stone': ('Fire Stone', 'stone',
                   'A peculiar stone, colored orange, with fire seeming to burn inside it.'),
    'water-stone': ('Water Stone', 'stone',
                    'A peculiar stone, a clear light blue, the color of a deep pool.'),
    'thunder-stone': ('Thunder Stone', 'stone',
                      'A peculiar stone with a thunderbolt pattern printed on it.'),
    'leaf-stone': ('Leaf Stone', 'stone',
                   'A peculiar stone with an unmistakable leaf pattern.'),
    'moon-stone': ('Moon Stone', 'stone',
                   'A peculiar stone, as black as the night sky.'),
    'sun-stone': ('Sun Stone', 'stone',
                  'A peculiar stone that burns as red as the evening sun.'),
    'shiny-stone': ('Shiny Stone', 'stone',
                    'A peculiar stone that shines with a dazzling light.'),
    'dusk-stone': ('Dusk Stone', 'stone',
                   'A peculiar stone that holds shadows as dark as can be.'),
    'dawn-stone': ('Dawn Stone', 'stone',
                   'A peculiar stone that sparkles like a pair of eyes.'),
    'ice-stone': ('Ice Stone', 'stone',
                  'A peculiar stone, as cold to the touch as ice.'),

    # ---- the seventeen hold-and-level items -------------------------------
    'kings-rock': ("King's Rock", 'hold', 'A rock that looks like a crown.'),
    'metal-coat': ('Metal Coat', 'hold',
                   'A special metallic film that boosts the power of Steel-type moves.'),
    'dragon-scale': ('Dragon Scale', 'hold',
                     'A thick, tough scale, shed by a Dragon-type Pokemon.'),
    'up-grade': ('Up-Grade', 'hold',
                 'A transparent device packed with all sorts of data, made by Silph Co.'),
    'dubious-disc': ('Dubious Disc', 'hold',
                     'A transparent device overflowing with dubious data.'),
    'protector': ('Protector', 'hold',
                  'A protective item of some sort. It is extremely stiff and heavy.'),
    'electirizer': ('Electirizer', 'hold',
                    'A box packed with a tremendous amount of electric energy.'),
    'magmarizer': ('Magmarizer', 'hold',
                   'A box packed with a tremendous amount of magma energy.'),
    'reaper-cloth': ('Reaper Cloth', 'hold',
                     'A cloth soaked with the spirits of the departed.'),
    'deep-sea-tooth': ('Deep Sea Tooth', 'hold',
                       'A fang that gleams a sharp silver. It is as sharp as a blade.'),
    'deep-sea-scale': ('Deep Sea Scale', 'hold',
                       'A scale that shines a faint pink.'),
    'prism-scale': ('Prism Scale', 'hold',
                    'A mysterious scale that shines in rainbow colors.'),
    'sachet': ('Sachet', 'hold',
               'A sachet filled with a perfume so sweet its scent lingers.'),
    'whipped-dream': ('Whipped Dream', 'hold',
                      'A soft, sweet treat made of whipped cream.'),
    'razor-claw': ('Razor Claw', 'hold', 'A curved claw, wickedly sharp.'),
    'razor-fang': ('Razor Fang', 'hold', 'A fang that gleams with a keen edge.'),
    'oval-stone': ('Oval Stone', 'hold', 'A round stone, pure white, like an egg.'),

    # ---- the thirteen bespoke Gen 7-9 use-items ---------------------------
    'black-augurite': ('Black Augurite', 'use',
                       'A dark stone with a rough, gritty surface.'),
    'peat-block': ('Peat Block', 'use', 'A block of peat, rich and dark.'),
    'tart-apple': ('Tart Apple', 'use', 'A sour apple.'),
    'sweet-apple': ('Sweet Apple', 'use', 'A sweet apple.'),
    'syrupy-apple': ('Syrupy Apple', 'use', 'An apple heavy with sweet syrup.'),
    'cracked-pot': ('Cracked Pot', 'use', 'A chipped teapot.'),
    'unremarkable-teacup': ('Unremarkable Teacup', 'use', 'A plain, ordinary teacup.'),
    'metal-alloy': ('Metal Alloy', 'use', 'A peculiar alloy of several metals.'),
    'auspicious-armor': ('Auspicious Armor', 'use',
                         'Armor said to bring good fortune to the one who wears it.'),
    'malicious-armor': ('Malicious Armor', 'use', 'Armor steeped in ill will.'),
    'scroll-of-darkness': ('Scroll of Darkness', 'use',
                           'A scroll recording the secrets of a dark technique.'),
    'galarica-cuff': ('Galarica Cuff', 'use', 'A cuff woven from Galarica twigs.'),
    'galarica-wreath': ('Galarica Wreath', 'use', 'A wreath woven from Galarica twigs.'),
}

SUFFIX = {'stone': STONE_SUFFIX, 'use': USE_SUFFIX, 'hold': HOLD_SUFFIX}
CATEGORY = {'stone': 'evolution-stone', 'use': 'evolution-item',
            'hold': 'evolution-item'}


def sort_rows(rows):
    """The canonical row order for data/items.json: by category, then by id.

    Both this script and tools/build_megas.py sort with this, so the committed
    file is byte-identical no matter which of the two ran last. Without it the
    file flip-flops between "evolution items first" and "Mega Stones first" and
    neither tool is idempotent in the presence of the other.
    """
    return sorted(rows, key=lambda r: (str(r.get('category', '')), str(r.get('id', ''))))


def load(path):
    with open(path, encoding='utf-8') as fh:
        return json.load(fh)


def needed_items(species):
    """item id -> {'use': [dex...], 'hold': [dex...]} from the evolution edges."""
    out = {}
    for sp in species:
        for edge in sp.get('evolutions', []):
            for key, role in (('item', 'use'), ('heldItem', 'hold')):
                if edge.get(key):
                    out.setdefault(edge[key], {'use': [], 'hold': []})
                    out[edge[key]][role].append(int(edge['to']))
    return out


def veekun_costs():
    if not os.path.exists(VEEKUN_ITEMS):
        return {}
    with open(VEEKUN_ITEMS, encoding='utf-8') as fh:
        rows = list(csv.DictReader(fh))
    out = {}
    for r in rows:
        cost = (r.get('cost') or '').strip()
        out[r['identifier']] = int(cost) if cost.isdigit() else 0
    return out


def build(species):
    need = needed_items(species)
    costs = veekun_costs()
    rows, problems = [], []

    for item_id in sorted(need):
        if item_id not in DESIGN:
            problems.append('%s is referenced by an evolution but has no DESIGN row'
                            % item_id)
            continue
        name, role, flavour = DESIGN[item_id]
        uses = need[item_id]
        # An item used BOTH ways would need two mechanics in one description.
        # None currently is; fail loudly rather than describe it wrongly.
        if uses['use'] and uses['hold']:
            problems.append('%s is used as both `item` and `heldItem`; the DESIGN '
                            'table describes one mechanic only' % item_id)
            continue
        actual = 'hold' if uses['hold'] else 'use'
        if actual == 'hold' and role != 'hold':
            problems.append('%s is held in the data but the DESIGN row calls it %r'
                            % (item_id, role))
            continue
        if actual == 'use' and role == 'hold':
            problems.append('%s is used in the data but the DESIGN row calls it hold'
                            % item_id)
            continue

        price = costs.get(item_id, 0)
        rows.append({
            'id': item_id,
            'name': name,
            'category': CATEGORY[role],
            'pocket': 'items',
            'price': price,
            'sellable': price > 0,
            # Every one of these is holdable: the `hold` family requires it, and
            # the stones are holdable in the mainline games too.
            'holdable': True,
            'consumable': role != 'hold',
            'description': flavour + SUFFIX[role],
            # Derived, so the file records what the item is actually for and a
            # stale row cannot hide.
            'evolves': sorted(set(uses['use'] + uses['hold'])),
            'sprite': 'items/%s.png' % item_id,
        })

    for item_id in sorted(set(DESIGN) - set(need)):
        problems.append('%s has a DESIGN row but no evolution references it' % item_id)
    return rows, problems


def merge(new_rows):
    """New rows plus every row this script does not own, in canonical order."""
    container, existing = None, []
    if os.path.isfile(ITEMS):
        doc = load(ITEMS)
        if isinstance(doc, dict):
            container, existing = doc, doc.get('items', [])
        else:
            existing = doc
    ours = set(r['id'] for r in new_rows)
    kept = [r for r in existing
            if r.get('id') not in ours and r.get('category') not in OURS]
    merged = sort_rows(kept + new_rows)
    payload = merged
    if container is not None:
        container['items'] = merged
        payload = container
    return payload, merged, len(existing) - len(kept)


def main(argv):
    species = load(SPECIES)
    rows, problems = build(species)

    print('=' * 74)
    print('EVOLUTION ITEMS')
    print('=' * 74)
    by_cat = {}
    for r in rows:
        by_cat.setdefault(r['category'], []).append(r)
    for cat in sorted(by_cat):
        print('  %-18s %d' % (cat, len(by_cat[cat])))
    holds = [r for r in rows if not r['consumable']]
    print('  %-18s %d (hold-and-level; not consumed)' % ('of which held', len(holds)))
    print()

    if problems:
        print('PROBLEMS -- refusing to write:')
        for p in problems:
            print('  ! ' + p)
        return 1

    payload, merged, replaced = merge(rows)
    print('merged: %d rows total (%d new/replaced, %d preserved)'
          % (len(merged), replaced or len(rows), len(merged) - len(rows)))

    if '--apply' not in argv:
        print('dry run: data/items.json untouched (pass --apply to write)')
        return 0

    with open(ITEMS, 'w', encoding='utf-8') as fh:
        json.dump(payload, fh, indent=2, sort_keys=True)
        fh.write('\n')

    # Assert on content: re-read from disk and check every referenced item exists.
    check = load(ITEMS)
    have = set(r['id'] for r in (check['items'] if isinstance(check, dict) else check))
    missing = sorted(set(needed_items(species)) - have)
    print('re-read from disk: %d items, %d referenced items missing'
          % (len(have), len(missing)))
    if missing:
        print('FAILED: %s' % missing)
        return 1
    print('wrote %s' % ITEMS)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
