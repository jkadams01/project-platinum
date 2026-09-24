#!/usr/bin/env python
# -*- coding: utf-8 -*-
"""Rescale every ORDINARY (non-boss) Sinnoh trainer onto the new level curve.

    python tools/scale_trainers.py                  # scale in place + report
    python tools/scale_trainers.py --dry-run        # report only, write nothing
    python tools/scale_trainers.py --analyse        # + EXP supply / multiplier impact
    python tools/scale_trainers.py --selftest       # prove the transform on
                                                    # documented vanilla values only
                                                    # (no ROM dump needed)

WHAT THIS DOES
--------------
The new curve (docs/research/level-curve.md 1.1, data/level_caps.json) makes the
cap at every checkpoint equal to that boss's ace level:

    18 27 36 45 54 66 78 90 | 96 97 98 99 100

`level-curve.md` 1.4 rescales *everything* with one global monotone piecewise-linear
map whose knots are (vanilla ace -> new ace).  That map is right for bosses and
wilds, but for ordinary trainers it inherits vanilla's scatter and amplifies it.
Measured, as a fraction of the cap in force:

    segment 1   f(3..14)  =  3..18  ->   17% .. 100% of cap
    segment 5   f(33..37) = 47..54  ->   87% .. 100% of cap
    post-game   f(53..65) = 96..100 ->   96% .. 100% of cap

Two things are wrong with that.  The first fights of a segment are 5-8 levels under
the player and pay almost nothing under a hard cap; the last ones land *exactly on
the cap*, which is the gym leader's own ace level -- so a Route 207 Youngster fields
the same level as Roark and the checkpoint stops being a wall.

So ordinary trainers are instead scaled by the **cap in force where they stand**,
into a band just under it:

    band(segment) = [ max(prev_cap, 0.85 * cap) , 0.95 * cap ]

placed inside that band by their position within their own segment, so route order
survives.  Every ordinary trainer then sits at 85-95% of the cap: level-matched to
slightly above the player (real EXP, a real threat), and strictly below the
checkpoint, which stays the wall.

EXP CONSEQUENCE -- coordinated with level-curve.md 2.4 / 3.3
-----------------------------------------------------------
Raising the floor and lowering the spikes roughly cancel: total ordinary-trainer
EXP moves by a few per cent (see `--analyse`), and the required global multiplier
does not move.  **The x2.5 multiplier the curve document calls for is NOT avoidable
by re-levelling route trainers** -- the gap is set by the Elite Four gauntlet, and
this transform does not touch it.  What it does move is *where* the supply sits: the
two binding segments (Volkner, Aaron) gain ~7%, and the over-supplied mid segments
lose ~5-10%, which is the harmless direction.  x2.5 still clears every checkpoint
with the scaled trainers in place (`--analyse` re-solves and checks it).

AREA -> CAP MAPPING
-------------------
`trainers.json` carries no map id (the ROM stores parties in a NARC and the
placements in map scripts), so the segment is derived from the trainer's own
vanilla ace level against the *vanilla* cap table.  That is exactly the
attribution `level-curve.md` 2.3 used to build the EXP supply model, and it is
sound because vanilla Platinum is itself level-gated: a party whose ace is 23-26
is on the road between Gardenia and Fantina, and nowhere else.  Same function,
same buckets, so the two documents cannot disagree.

WHAT IS *NOT* TOUCHED
---------------------
  * the 30 boss aliases (gyms, E4, Champion, rivals, Galactic commanders) -- the
    Boss phase owns those and expands them to six;
  * gym-leader / E4 / Champion *rematch* entries (Battleground, ace 65-78) --
    boss content, and re-levelling them as route trainers would be wrong;
  * the Battle Tower / Frontier opponent pool (fixed facility levels) and the
    unused lone-Rattata-L5 placeholder slots.

Party SIZE and SPECIES are never changed.  Only levels move.  The transform is
idempotent: every mon keeps its `vanillaLevel`, and a re-run rescales from that.
"""
from __future__ import division

import argparse
import collections
import json
import os
import re
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
TRAINERS = os.path.join(ROOT, 'data', 'rom', 'trainers.json')
LEVEL_CAPS = os.path.join(ROOT, 'data', 'level_caps.json')
SPECIES = os.path.join(ROOT, 'data', 'species.json')

# ---------------------------------------------------------------------------
# 1. The two cap tables
# ---------------------------------------------------------------------------
# index 0 = start, 1..8 = the eight gyms in PLATINUM order (Fantina is 3rd),
# 9..12 = Elite Four, 13 = Cynthia, 14 = post-game.
CHECKPOINTS = ['start', 'roark', 'gardenia', 'fantina', 'maylene', 'crasher_wake',
               'byron', 'candice', 'volkner', 'aaron', 'bertha', 'flint', 'lucian',
               'cynthia', 'post-game']

# ROM-verified vanilla aces / caps (docs/research/game-design.md).
VANILLA_CAP = [14, 14, 22, 26, 32, 37, 41, 44, 50, 53, 55, 57, 59, 62, 100]

# The new curve.  Loaded from data/level_caps.json when present; this literal is
# the fallback and the assertion target.
NEW_CAP = [18, 18, 27, 36, 45, 54, 66, 78, 90, 96, 97, 98, 99, 100, 100]

# level-curve.md 1.4 -- the global rescale, kept here so this script can report
# what the ordinary-trainer band buys over the plain map.
KNOT_V = [2, 14, 22, 26, 32, 37, 41, 44, 50, 53, 55, 57, 59, 62]
KNOT_N = [2, 18, 27, 36, 45, 54, 66, 78, 90, 96, 97, 98, 99, 100]

# The band, as a fraction of the cap in force.
BAND_LO_FRAC = 0.85
BAND_HI_FRAC = 0.95
# Post-game (Battle Zone) is the one place the player is already AT the terminal
# cap, so the band there is pure difficulty, not EXP headroom: it runs from the
# top of Victory Road up to just under 100, and is never softer than segment 9.
POSTGAME_HI_FRAC = 0.98
START_LEVEL = 5          # the starter's level: the floor of segment 1's ramp
MIN_LEVEL = 2


def load_caps(path=LEVEL_CAPS):
    """The approved curve, cross-checked against the committed design table.

    `data/level_caps.json` is regenerated by the Curve phase.  Until that lands it
    still holds the VANILLA table, so the literal above -- the owner-approved new
    curve -- wins, and the mismatch is reported rather than silently obeyed.
    """
    try:
        with open(path) as fh:
            doc = json.load(fh)
    except (IOError, ValueError):
        return NEW_CAP, 'built-in approved curve (data/level_caps.json unreadable)'
    got = [None] * 15
    for row in doc.get('caps') or []:
        i = row.get('index')
        if isinstance(i, int) and 0 <= i < 15:
            got[i] = row['cap']
    if got == NEW_CAP:
        return NEW_CAP, 'data/level_caps.json (agrees with the approved curve)'
    if got == VANILLA_CAP:
        return NEW_CAP, ('built-in approved curve -- data/level_caps.json is still '
                         'the VANILLA table (the Curve phase has not rewritten it)')
    return NEW_CAP, ('built-in approved curve -- data/level_caps.json disagrees: %s'
                     % (got,))


def f_global(level):
    """level-curve.md 1.4: the global monotone piecewise-linear rescale."""
    if level <= KNOT_V[0]:
        return KNOT_V[0]
    if level >= KNOT_V[-1]:
        return min(100, int(round(KNOT_N[-1] + (level - KNOT_V[-1]))))
    i = 0
    while KNOT_V[i + 1] <= level:
        i += 1
    v0, v1 = KNOT_V[i], KNOT_V[i + 1]
    n0, n1 = KNOT_N[i], KNOT_N[i + 1]
    return int(round(n0 + (level - v0) * (n1 - n0) / float(v1 - v0)))


# ---------------------------------------------------------------------------
# 2. Which segment of the road a trainer stands on
# ---------------------------------------------------------------------------
POSTGAME = 'postgame'


def bucket(ace):
    """Vanilla ace level -> segment index (the checkpoint being walked toward).

    Identical to the attribution in docs/research/level-curve.md 2.3, so the
    supply model and this rescale agree by construction.
    """
    if ace >= 53:
        return POSTGAME              # Battle Zone: Routes 224-230, Stark Mountain
    if ace >= 46:
        return 9                     # Victory Road + Route 223 + League front
    for i in range(1, 14):
        if ace <= VANILLA_CAP[i]:
            return i
    return 13


def band(segment):
    """(lo, hi) levels an ordinary trainer's ACE may occupy in this segment."""
    if segment == POSTGAME:
        cap = NEW_CAP[14]
        lo = max(band(9)[1], int(round(BAND_LO_FRAC * cap)))
        return lo, int(round(POSTGAME_HI_FRAC * cap))
    cap = NEW_CAP[segment]
    hi = int(round(BAND_HI_FRAC * cap))
    if segment == 1:
        # The ONE exception.  Everywhere else the player enters a segment sitting
        # at the previous cap; in segment 1 they leave Twinleaf with a single L5
        # starter, so an 85%-of-18 floor (L15) on Route 201 is unwinnable.  The
        # band therefore opens at the starter's level and ramps up INTO it, so
        # the last fights before Roark (Oreburgh Gate) still land at 17/18.
        return START_LEVEL + 1, hi
    lo = max(NEW_CAP[segment - 1], int(round(BAND_LO_FRAC * cap)))
    return lo, max(lo, hi)


def spread_scale(segment):
    """How much a party's internal level spread widens.

    The whole segment inflated by cap_new/cap_vanilla, so a vanilla 2-level gap
    inside a party grows by the same factor instead of collapsing to nothing.
    """
    if segment == POSTGAME:
        return NEW_CAP[14] / float(VANILLA_CAP[14])
    return NEW_CAP[segment] / float(VANILLA_CAP[segment])


# ---------------------------------------------------------------------------
# 3. Classifying the ROM population
# ---------------------------------------------------------------------------
NUMBERED = re.compile(r'^trainer_\d+$')

# Battle Tower / Frontier opponent pool.  These five names cover 205 entries,
# 175 of which are the unused lone-Rattata-L5 placeholder slots.
FACILITY_NAMES = set(['Mickey', 'Angelica', 'Tara & Tim', 'Cedric', 'Arturo'])
FRONTIER_CLASSES = set(['Tower Tycoon', 'Hall Matron', 'Factory Head',
                        'Arcade Star', 'Castle Valet'])
# Boss classes.  The 30 story bosses are keyed by alias, so anything left in
# these classes is a post-game Battleground rematch -- still boss content.
BOSS_CLASSES = set(['Leader', 'Elite Four', 'Champion', 'Galactic Boss', 'Commander'])


def classify(key, trainer):
    """None if this trainer is ours to scale, else the reason it is skipped."""
    if not NUMBERED.match(key):
        return 'boss-alias'
    if not trainer.get('party'):
        return 'empty-party'
    if trainer.get('name') in FACILITY_NAMES:
        return 'facility-pool'
    if trainer.get('trainerClassName') in FRONTIER_CLASSES:
        return 'frontier'
    if trainer.get('trainerClassName') in BOSS_CLASSES:
        return 'boss-rematch'
    return None


def vanilla_levels(trainer):
    """Party levels as the ROM has them, surviving re-runs of this script."""
    out = []
    for mon in trainer['party']:
        out.append(mon.get('vanillaLevel', mon['level']))
    return out


# ---------------------------------------------------------------------------
# 4. The transform
# ---------------------------------------------------------------------------
def place_ace(vanilla_ace, segment, seg_lo, seg_hi):
    """Put a trainer inside its segment's band by position within the segment.

    `seg_lo`/`seg_hi` are the min/max vanilla ace actually present in the
    segment, so the whole segment stretches across the whole band and route
    order survives (Route 202's L5 stays below Oreburgh Gate's L14).
    """
    lo, hi = band(segment)
    if seg_hi <= seg_lo:                       # degenerate segment: one level only
        return int(round((lo + hi) / 2.0))
    t = (vanilla_ace - seg_lo) / float(seg_hi - seg_lo)
    return int(round(lo + t * (hi - lo)))


def scale_party(vlevels, new_ace, segment):
    """New levels for one party: ace at `new_ace`, spread preserved and widened."""
    vace = max(vlevels)
    scale = spread_scale(segment)
    out = []
    for v in vlevels:
        gap = vace - v
        if gap:
            gap = max(1, int(round(gap * scale)))
        out.append(max(MIN_LEVEL, new_ace - gap))
    return out


def scale_all(trainers):
    """Rescale in place.  Returns (per-trainer records, skip counts)."""
    # pass 1 -- segment membership, and each segment's vanilla ace range
    members = collections.defaultdict(list)
    skipped = collections.Counter()
    for key in sorted(trainers):
        reason = classify(key, trainers[key])
        if reason:
            skipped[reason] += 1
            trainers[key]['levelScale'] = {'scaled': False, 'reason': reason}
            continue
        vl = vanilla_levels(trainers[key])
        members[bucket(max(vl))].append(key)

    span = {}
    for seg, keys in members.items():
        aces = [max(vanilla_levels(trainers[k])) for k in keys]
        span[seg] = (min(aces), max(aces))

    # pass 2 -- place every trainer in its band
    records = []
    for seg in sorted(members, key=lambda s: 99 if s == POSTGAME else s):
        seg_lo, seg_hi = span[seg]
        lo, hi = band(seg)
        cap = NEW_CAP[14] if seg == POSTGAME else NEW_CAP[seg]
        checkpoint = 'post-game' if seg == POSTGAME else CHECKPOINTS[seg]
        for key in sorted(members[seg], key=lambda k: (max(vanilla_levels(trainers[k])), k)):
            t = trainers[key]
            vl = vanilla_levels(t)
            vace = max(vl)
            new_ace = place_ace(vace, seg, seg_lo, seg_hi)
            new = scale_party(vl, new_ace, seg)
            for mon, v, n in zip(t['party'], vl, new):
                mon['vanillaLevel'] = v
                mon['level'] = n
            t['levelScale'] = {
                'scaled': True,
                'segment': (14 if seg == POSTGAME else seg),
                'checkpoint': checkpoint,
                'capInForce': cap,
                'band': [lo, hi],
                'vanillaAce': vace,
                'ace': max(new),
            }
            records.append({
                'key': key, 'name': t.get('name'), 'class': t.get('trainerClassName'),
                'segment': seg, 'checkpoint': checkpoint, 'cap': cap,
                'vanilla': vl, 'new': new, 'ace': max(new), 'vace': vace,
                'plain_map': [f_global(v) for v in vl],
            })
    return records, skipped


# ---------------------------------------------------------------------------
# 5. Verification
# ---------------------------------------------------------------------------
def verify(records):
    """Every invariant this transform claims.  Raises AssertionError on a breach."""
    problems = []
    for r in records:
        seg, cap = r['segment'], r['cap']
        lo, hi = band(seg)
        if len(r['new']) != len(r['vanilla']):
            problems.append('%s: party size changed' % r['key'])
        if max(r['new']) >= cap:
            problems.append('%s: ace %d at/over the cap in force %d'
                            % (r['key'], max(r['new']), cap))
        if not (lo <= max(r['new']) <= hi):
            problems.append('%s: ace %d outside band %d-%d' % (r['key'], max(r['new']), lo, hi))
        if min(r['new']) < MIN_LEVEL:
            problems.append('%s: level below %d' % (r['key'], MIN_LEVEL))
        # party order preserved: mon i above mon j in vanilla stays above
        vl, nl = r['vanilla'], r['new']
        for i in range(len(vl)):
            for j in range(len(vl)):
                if vl[i] > vl[j] and nl[i] <= nl[j]:
                    problems.append('%s: party order inverted' % r['key'])
        if max(r['new']) < max(r['vanilla']):
            problems.append('%s: ace went DOWN' % r['key'])
    # monotone across the road: a later segment's floor is not below an
    # earlier segment's floor
    by_seg = collections.defaultdict(list)
    for r in records:
        by_seg[r['segment']].append(max(r['new']))
    order = sorted(by_seg, key=lambda s: 99 if s == POSTGAME else s)
    for a, b in zip(order, order[1:]):
        if min(by_seg[b]) < min(by_seg[a]):
            problems.append('segment %s floor below segment %s' % (b, a))
    if problems:
        raise AssertionError('verification failed:\n  ' + '\n  '.join(problems[:20]))
    return len(records)


# ---------------------------------------------------------------------------
# 6. EXP interaction with docs/research/level-curve.md
# ---------------------------------------------------------------------------
def gen5_exp(base, level, player_level, trainer=True, share=1.0):
    """level-curve.md 2.1: Gen 5 formula with the scaled-level term."""
    a = 1.5 if trainer else 1.0
    core = (a * base * level) / 5.0
    scaled = ((2.0 * level + 10) / (level + player_level + 10)) ** 2.5
    return int(core * scaled * share)


def exp_supply(records, species):
    """Ordinary-trainer EXP per segment, before (plain map) and after (band).

    Evaluated against a player sitting AT the cap in force -- the honest case
    under a hard cap, and the case level-curve.md 2.4 found short.
    """
    out = {}
    for r in records:
        seg = r['segment']
        cap = r['cap']
        row = out.setdefault(seg, {'before': 0, 'after': 0, 'n': 0, 'mons': 0})
        row['n'] += 1
        for i, mon_species in enumerate(r.get('species', [])):
            base = species.get(mon_species, 150)
            row['mons'] += 1
            row['before'] += gen5_exp(base, r['plain_map'][i], cap)
            row['after'] += gen5_exp(base, r['new'][i], cap)
    return out


def load_species():
    try:
        with open(SPECIES) as fh:
            return dict((s['id'], s.get('baseExp') or 150) for s in json.load(fh))
    except (IOError, ValueError):
        return {}


# per-segment demand for six medium-fast Pokemon, from level-curve.md 2.2
DEMAND = {1: 0, 2: 83106, 3: 161838, 4: 266814, 5: 398034, 6: 780192, 7: 1122336,
          8: 1526688, 9: 934416, 10: 167622, 11: 171114, 12: 174642, 13: 178206}


def report_exp(records, species):
    supply = exp_supply(records, species)
    print('')
    print('EXP FROM ORDINARY TRAINERS -- plain global map (level-curve.md 1.4)')
    print('vs the cap-in-force band, player AT the cap, party-wide Exp Share off')
    print('(one participant, full share), x1.00 multiplier:')
    print('')
    print('  seg  checkpoint      cap   trainers  mons     before      after   gain')
    total_b = total_a = 0
    for seg in sorted(supply, key=lambda s: 99 if s == POSTGAME else s):
        row = supply[seg]
        cap = NEW_CAP[14] if seg == POSTGAME else NEW_CAP[seg]
        name = 'post-game' if seg == POSTGAME else CHECKPOINTS[seg]
        total_b += row['before']
        total_a += row['after']
        gain = (row['after'] / float(row['before'])) if row['before'] else 0.0
        print('  %3s  %-14s %4d   %6d  %5d  %9d  %9d  x%.2f'
              % (seg if seg != POSTGAME else 'pg', name, cap, row['n'], row['mons'],
                 row['before'], row['after'], gain))
    print('  %-25s %6s  %5s  %9d  %9d  x%.2f'
          % ('TOTAL', '', '', total_b, total_a,
             (total_a / float(total_b)) if total_b else 0))
    print('')
    print('Story-relevant subtotal (segments 1-9, excludes post-game Battle Zone):')
    sb = sum(supply[s]['before'] for s in supply if s != POSTGAME)
    sa = sum(supply[s]['after'] for s in supply if s != POSTGAME)
    print('  before %d   after %d   x%.2f' % (sb, sa, sa / float(sb) if sb else 0))
    return supply


def analyse_multiplier(trainers):
    """Re-run the level-curve.md economy model with the scaled trainer levels.

    Imports the design script from tools/_work/rebalance/ when it is there; that
    directory is scratch and gitignored, so this is optional by design.
    """
    work = os.path.join(ROOT, 'tools', '_work', 'rebalance')
    if not os.path.exists(os.path.join(work, 'curve.py')):
        print('\n[--analyse] tools/_work/rebalance/curve.py not present; '
              'skipping the multiplier re-solve.')
        return None
    sys.path.insert(0, work)
    try:
        import curve as C
    except Exception as exc:                                  # pragma: no cover
        print('\n[--analyse] could not import curve.py (%s); skipping.' % exc)
        return None

    scaled_levels = {}
    for key, t in trainers.items():
        if t.get('levelScale', {}).get('scaled'):
            scaled_levels[t['id']] = [m['level'] for m in t['party']]

    def stream(seg, ordinary, bosses):
        out = []
        for t in ordinary.get(seg, []):
            lv = scaled_levels.get(t['id'])
            for i, p in enumerate(t['party']):
                out.append((C.base_exp(p['species']),
                            lv[i] if lv and i < len(lv) else C.f(p['level'])))
        for alias in bosses.get(seg, []):
            for sid, l in C.boss_roster(alias):
                out.append((C.base_exp(sid), l))
        return out

    before = C.required_mult(curves=C.REAL_CURVES)
    C.stream = stream
    after = C.required_mult(curves=C.REAL_CURVES)
    print('')
    print('REQUIRED GLOBAL EXP MULTIPLIER (realistic mixed-growth team, '
          'party-wide Exp Share, <=60 forced wilds/segment)')
    print('  plain global map, same harness:                  x%.2f' % before)
    print('  with ordinary trainers on the cap-in-force band: x%.2f' % after)

    rows = C.simulate(mult=2.5, curves=C.REAL_CURVES)
    stuck = [r['name'] for r in rows if r['stuck']]
    grind = max(r['grind'] for r in rows)
    print('')
    print('  at the recommended x2.50, scaled trainers in place: %s'
          % ('ALL 13 CHECKPOINTS CLEAR' if not stuck else 'STUCK AT ' + ', '.join(stuck)))
    print('  worst forced wild grind in any segment: %d battles' % grind)
    for r in rows:
        print('    %-13s cap %3d  reached %3d  segment supply/demand x%.2f  %s'
              % (r['name'], r['cap'], r['reached'], min(r['ratio'], 99.0),
                 'grind %d' % r['grind'] if r['grind'] else ''))
    return before, after


# ---------------------------------------------------------------------------
# 7. Self-test on documented vanilla values -- no ROM dump required
# ---------------------------------------------------------------------------
SELFTEST = [
    # (label, vanilla party, expected segment, expected cap in force)
    ('Route 202 Youngster Tristan', [5], 1, 18),
    ('Route 203 Youngster Michael', [7, 6], 1, 18),
    ('Oreburgh Gate Roughneck', [12, 12], 1, 18),
    ('Eterna Forest Bug Catcher', [15], 2, 27),
    ('Route 205 Fisherman', [19, 19, 19], 2, 27),
    ('Hearthome Rich Boy', [25], 3, 36),
    ('Route 210 Ace Trainer', [31, 31], 4, 45),
    ('Pastoria Tuber', [35], 5, 54),
    ('Iron Island Worker', [39, 40], 6, 66),
    ('Mt Coronet Psychic', [43, 43], 7, 78),
    ('Galactic HQ Grunt', [45, 45], 8, 90),
    ('Victory Road Ace Trainer', [48, 49, 50], 9, 96),
    ('Route 228 Ace Trainer', [58, 58, 59], POSTGAME, 100),
]


def selftest():
    load_caps()
    assert NEW_CAP == [18, 18, 27, 36, 45, 54, 66, 78, 90, 96, 97, 98, 99, 100, 100], \
        'cap table does not match the approved curve: %r' % (NEW_CAP,)
    # the global map must reproduce level-curve.md 1.4 exactly
    for v, n in zip(KNOT_V, KNOT_N):
        assert f_global(v) == n, 'global map broken at knot %d' % v
    assert f_global(2) == 2 and f_global(4) == 5, 'Route 201 Starly L2-4 -> L2-5'
    assert all(f_global(i) <= f_global(i + 1) for i in range(2, 100)), 'map not monotone'

    # fake a population so segment spans are the documented vanilla ranges
    spans = {1: (3, 14), 2: (15, 22), 3: (23, 26), 4: (27, 32), 5: (33, 37),
             6: (38, 41), 7: (42, 44), 8: (45, 45), 9: (46, 52), POSTGAME: (53, 65)}
    print('SELF-TEST -- the transform on documented vanilla parties')
    print('')
    print('  %-28s %-9s %4s %7s  %-14s %-14s' %
          ('trainer', 'segment', 'cap', 'band', 'vanilla', 'scaled'))
    ok = True
    for label, party, seg, cap in SELFTEST:
        assert bucket(max(party)) == seg, '%s bucketed wrong' % label
        got_cap = NEW_CAP[14] if seg == POSTGAME else NEW_CAP[seg]
        assert got_cap == cap, '%s cap wrong' % label
        lo, hi = band(seg)
        s_lo, s_hi = spans[seg]
        ace = place_ace(max(party), seg, s_lo, s_hi)
        new = scale_party(party, ace, seg)
        assert len(new) == len(party)
        assert max(new) < cap, '%s: ace %d not below cap %d' % (label, max(new), cap)
        assert lo <= max(new) <= hi, '%s: ace %d outside band' % (label, max(new))
        assert max(new) >= max(party), '%s: went down' % label
        print('  %-28s %-9s %4d %3d-%-3d  %-14s %-14s' %
              (label, seg, cap, lo, hi,
               '/'.join(str(x) for x in party), '/'.join(str(x) for x in new)))
    print('')
    print('  all assertions passed' if ok else '  FAILED')
    return 0


# ---------------------------------------------------------------------------
# 8. CLI
# ---------------------------------------------------------------------------
def sample_line(r):
    return ('  %-11s %-13s %-16s seg %-9s cap %3d  band %3d-%-3d  %-18s -> %-18s'
            % (r['key'], (r['name'] or '')[:12], (r['class'] or '')[:15],
               r['segment'], r['cap'], band(r['segment'])[0], band(r['segment'])[1],
               '/'.join(str(x) for x in r['vanilla']),
               '/'.join(str(x) for x in r['new'])))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--in', dest='src', default=TRAINERS)
    ap.add_argument('--out', dest='dst', default=TRAINERS)
    ap.add_argument('--dry-run', action='store_true')
    ap.add_argument('--analyse', action='store_true',
                    help='EXP supply before/after and the multiplier re-solve')
    ap.add_argument('--selftest', action='store_true')
    args = ap.parse_args(argv)

    if args.selftest:
        return selftest()

    caps, src_of_caps = load_caps()
    print('cap table from %s' % src_of_caps)
    print('  new: %s' % ' '.join(str(c) for c in caps))
    print('  van: %s' % ' '.join(str(c) for c in VANILLA_CAP))

    if not os.path.exists(args.src):
        print('\n%s not present (the ROM build has not run).' % args.src)
        print('Running --selftest instead: the transform proved on documented values.\n')
        return selftest()

    with open(args.src) as fh:
        trainers = json.load(fh)
    print('\n%d trainer entries read from %s' % (len(trainers), args.src))

    records, skipped = scale_all(trainers)
    verify(records)

    print('\nscaled %d ordinary trainers (%d Pokemon); skipped:'
          % (len(records), sum(len(r['new']) for r in records)))
    for reason, n in sorted(skipped.items(), key=lambda kv: -kv[1]):
        print('  %-14s %4d' % (reason, n))

    print('\nPER SEGMENT')
    print('  seg  checkpoint      cap   band      trainers  vanilla aces  new aces'
          '   mean % of cap')
    by_seg = collections.defaultdict(list)
    for r in records:
        by_seg[r['segment']].append(r)
    for seg in sorted(by_seg, key=lambda s: 99 if s == POSTGAME else s):
        rs = by_seg[seg]
        lo, hi = band(seg)
        cap = rs[0]['cap']
        vac = [r['vace'] for r in rs]
        nac = [r['ace'] for r in rs]
        pct = 100.0 * sum(nac) / float(len(nac)) / cap
        print('  %3s  %-14s %4d   %3d-%-4d  %6d    %3d-%-3d       %3d-%-3d    %5.1f%%'
              % (seg if seg != POSTGAME else 'pg',
                 'post-game' if seg == POSTGAME else CHECKPOINTS[seg],
                 cap, lo, hi, len(rs), min(vac), max(vac), min(nac), max(nac), pct))

    if args.analyse:
        species = load_species()
        for r in records:
            r['species'] = [m['species'] for m in trainers[r['key']]['party']]
        report_exp(records, species)
        analyse_multiplier(trainers)

    if args.dry_run:
        print('\n--dry-run: nothing written.')
        return 0

    tmp = args.dst + '.tmp'
    with open(tmp, 'w') as fh:
        json.dump(trainers, fh, indent=1, sort_keys=False)
    if os.path.exists(args.dst):
        os.remove(args.dst)
    os.rename(tmp, args.dst)
    print('\nwrote %s (%d bytes)' % (args.dst, os.path.getsize(args.dst)))
    return 0


if __name__ == '__main__':
    sys.exit(main())
