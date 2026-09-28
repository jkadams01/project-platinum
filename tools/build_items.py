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

IT ALSO BUILDS THE HELD BATTLE ITEMS (category `held-item`). Those are NOT derived
from anything -- there is no data file that says the game wants a Leftovers -- so
the HELD table below is authored, the same status as the DESIGN table. What
justifies each row is that the rosters already reference it: 23 boss slots hold a
Sitrus Berry, 22 hold Leftovers, 21 a Life Orb, and 56 ordinary trainers hold a
Sitrus Berry, all of which did nothing at all before this family existed.

`tier` mirrors DATA_CONTRACT 4 for abilities: 1 = src/battle/items.gd implements
it, 3 = the row exists so a roster can reference it but nothing reads it yet. The
builder UI shows the tier, so an item that does nothing says so before it is
chosen rather than after the battle.

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
OURS = ('evolution-stone', 'evolution-item', 'held-item')

# ---------------------------------------------------------------------------
# HELD BATTLE ITEMS -- id: (name, tier, hook, consumable, description)
#
# `hook` names the seam src/battle/items.gd uses, the way abilities.json names
# the seam an ability uses. It is documentation, not dispatch: items.gd keys on
# the id. Keep the two in step -- a row claiming tier 1 that items.gd does not
# implement is a lie the builder UI will repeat.
# ---------------------------------------------------------------------------
HELD = {
    'leftovers': (
        'Leftovers', 1, 'onTurnEnd', False,
        'Restores a little of the holder HP at the end of every turn.'),
    'black-sludge': (
        'Black Sludge', 1, 'onTurnEnd', False,
        'Restores HP to a Poison-type holder each turn, and hurts any other holder.'),
    'flame-orb': (
        'Flame Orb', 1, 'onTurnEnd', False,
        'Burns the holder at the end of the turn.'),
    'life-orb': (
        'Life Orb', 1, 'onDamageCalc', False,
        'Boosts the power of moves, at the cost of some HP each time one lands.'),
    'expert-belt': (
        'Expert Belt', 1, 'onDamageCalc', False,
        'Boosts the power of super effective moves.'),
    'muscle-band': (
        'Muscle Band', 1, 'onDamageCalc', False,
        'Slightly boosts the power of physical moves.'),
    'wise-glasses': (
        'Wise Glasses', 1, 'onDamageCalc', False,
        'Slightly boosts the power of special moves.'),
    'choice-band': (
        'Choice Band', 1, 'onDamageCalc', False,
        'Boosts Attack, but allows only the first move chosen.'),
    'choice-specs': (
        'Choice Specs', 1, 'onDamageCalc', False,
        'Boosts Sp. Atk, but allows only the first move chosen.'),
    'choice-scarf': (
        'Choice Scarf', 1, 'onSpeed', False,
        'Boosts Speed, but allows only the first move chosen.'),
    'assault-vest': (
        'Assault Vest', 1, 'onDamageCalc', False,
        'Boosts Sp. Def, but forbids status moves.'),
    'rocky-helmet': (
        'Rocky Helmet', 1, 'onContactHit', False,
        'Hurts attackers that make contact.'),
    'focus-sash': (
        'Focus Sash', 1, 'onFatalHit', True,
        'Holds on with 1 HP against a hit that would knock the holder out from full '
        'health. Used up.'),
    'sitrus-berry': (
        'Sitrus Berry', 1, 'onLowHp', True,
        'Restores a quarter of the holder HP when it falls to half. Eaten.'),
    'oran-berry': (
        'Oran Berry', 1, 'onLowHp', True,
        'Restores 10 HP when the holder HP falls to half. Eaten.'),
    'shuca-berry': (
        'Shuca Berry', 1, 'onEffectiveness', True,
        'Weakens a super effective Ground-type hit. Eaten.'),
    'black-belt': (
        'Black Belt', 1, 'onDamageCalc', False,
        'Boosts Fighting-type moves.'),
    'charcoal': (
        'Charcoal', 1, 'onDamageCalc', False,
        'Boosts Fire-type moves.'),
    'magnet': (
        'Magnet', 1, 'onDamageCalc', False,
        'Boosts Electric-type moves.'),
    'mystic-water': (
        'Mystic Water', 1, 'onDamageCalc', False,
        'Boosts Water-type moves.'),
    'sharp-beak': (
        'Sharp Beak', 1, 'onDamageCalc', False,
        'Boosts Flying-type moves.'),
    'silk-scarf': (
        'Silk Scarf', 1, 'onDamageCalc', False,
        'Boosts Normal-type moves.'),
    'lucky-egg': (
        'Lucky Egg', 1, 'onExp', False,
        'The holder earns more EXP. Points from a battle.'),
    'booster-energy': (
        'Booster Energy', 1, 'onFieldEnter', True,
        'Rouses a Pokemon with Protosynthesis or Quark Drive, raising its best stat '
        'until it leaves the field. Used up.'),
}

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


def build_held(costs):
    """The held battle items as contract rows. Authored, not derived; see HELD."""
    rows = []
    for item_id in sorted(HELD):
        name, tier, hook, consumable, description = HELD[item_id]
        price = costs.get(item_id, 0)
        rows.append({
            'id': item_id,
            'name': name,
            'category': 'held-item',
            'pocket': 'items',
            'price': price,
            'sellable': price > 0,
            'holdable': True,
            'consumable': consumable,
            'description': description,
            'hook': hook,
            'tier': tier,
            'sprite': 'items/%s.png' % item_id,
        })
    return rows


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
    held = build_held(veekun_costs())
    rows = rows + held

    print('=' * 74)
    print('ITEMS THIS TOOL OWNS')
    print('=' * 74)
    by_cat = {}
    for r in rows:
        by_cat.setdefault(r['category'], []).append(r)
    for cat in sorted(by_cat):
        print('  %-18s %d' % (cat, len(by_cat[cat])))
    holds = [r for r in rows if not r['consumable'] and r['category'] != 'held-item']
    print('  %-18s %d (hold-and-level; not consumed)' % ('of which held', len(holds)))
    print()
    print('=' * 74)
    print('HELD BATTLE ITEMS')
    print('=' * 74)
    inert = [r for r in held if r['tier'] != 1]
    print('  %-18s %d' % ('implemented', len(held) - len(inert)))
    for r in inert:
        print('  %-18s %s (tier %d -- nothing reads it yet)'
              % ('data only', r['id'], r['tier']))
    print()

    if problems:
        print('PROBLEMS -- refusing to write:')
        for p in problems:
            print('  ! ' + p)
        return 1

    payload, merged, replaced = merge(rows)
    print('merged: %d rows total (%d written by this tool, %d preserved, %d replaced)'
          % (len(merged), len(rows), len(merged) - len(rows), replaced))

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
