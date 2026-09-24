#!/usr/bin/env python
"""Build front / back / icon images for every Mega Evolution form.

Why a separate script from ``build_sprites.py``
-----------------------------------------------
The species pipeline is keyed by *national dex number* 1..1025 and half of it is
driven by the owner's Pokemon White 2 cartridge.  Megas are keyed by a *form id*
string (``charizard-mega-x``) and none of them exist in a Gen 5 ROM -- Mega
Evolution is a Gen 6 mechanic.  So this is a second, purely web-sourced pass
that reuses ``build_sprites``'s fetch/cache/frame-fitting helpers and writes to
its own output tree.  It never touches ``assets/generated/pkmn``.

Sources
-------
front/back  PokeAPI/sprites ``versions/generation-v/black-white/{form}.png`` --
            the same Smogon Sprite Project aggregation the Gen 6-9 species
            sprites come from (docs/research/species-data.md section 7).
            PokeAPI numbers alternate forms above 10000: ``venusaur-mega`` is
            10033, ``clefable-mega`` 10278.  That number is the only join key
            between the roster and the sprite repo, so it is carried in ROSTER.
icon        PokeAPI/sprites ``versions/generation-viii/icons/{form}.png``, then
            ``generation-vii/icons``.  Neither covers the Legends Z-A Megas, so
            those downscale the Mega's own front sprite -- the same convention
            ``build_sprites.py`` already uses for the Gen 9 species.

Legends Z-A Megas are recent enough that upstream art may not exist for all of
them.  A form with no front sprite is NOT skipped and does NOT fail the build:
it ships a loudly-marked placeholder derived from the base species sprite
(violet tint + border + Mega-stone badge) and is listed under ``placeholders``
in the manifest so it can be swapped for real art later.

Output (gitignored, like the rest of assets/generated)
------------------------------------------------------
  assets/generated/mega/<form-id>.png        96x96 front   (contract 11.1)
  assets/generated/mega/back/<form-id>.png   96x96 back
  assets/generated/mega/icon/<form-id>.png   32x32 party icon
  assets/generated/mega/_manifest.json       sidecar copy of the mega manifest
  assets/generated/_mega_check.png           24-form visual contact sheet
  data/rom/sprites.json                      merged in under the "megas" key

``data/rom/sprites.json`` is rewritten wholesale by ``build_sprites.py``, so
this script read-modify-writes only the ``megas`` key, keeps the sidecar copy
next to the images, and can re-merge that copy without refetching anything.

Usage
-----
  source tools/_work/gen5/env.sh      # PIL needs the anaconda DLL path here
  python tools/build_mega_sprites.py
  python tools/build_mega_sprites.py --no-download    # cache only
  python tools/build_mega_sprites.py --check-only     # rebuild contact sheet
  python tools/build_mega_sprites.py --manifest-only  # re-merge into sprites.json

Excluded by the owner (contract 11.5): Primal Reversion, Dynamax/Gigantamax,
Z-Moves, Terastallization.  ``assert_exclusions`` fails the build if a Primal
form or a Kyogre/Groudon "Mega" ever reaches the roster.
"""

import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from PIL import Image, ImageDraw

# Fetching, caching and frame fitting are shared with the species pipeline so
# Megas land on the same 96x96 ground line and in the same cache store.
from build_sprites import (ROOT, CACHE, PKAPI, BW, G8_ICON, FRAME, ICON,
                           cached, fetch_many, fit_frame, fit_icon, log)

G7_ICON = PKAPI + '/versions/generation-vii/icons'

OUT_MEGA = os.path.join(ROOT, 'assets', 'generated', 'mega')
OUT_BACK = os.path.join(OUT_MEGA, 'back')
OUT_ICON = os.path.join(OUT_MEGA, 'icon')
SIDECAR = os.path.join(OUT_MEGA, '_manifest.json')
MANIFEST = os.path.join(ROOT, 'data', 'rom', 'sprites.json')
MEGAS_JSON = os.path.join(ROOT, 'data', 'megas.json')
BASE_FRONT = os.path.join(ROOT, 'assets', 'generated', 'pkmn')
BASE_BACK = os.path.join(BASE_FRONT, 'back')
CHECK_SHEET = os.path.join(ROOT, 'assets', 'generated', '_mega_check.png')

# Placeholder styling -- deliberately garish.  A placeholder must never be
# mistaken for finished art in a screenshot.
TINT = (168, 60, 214)            # mega violet
BADGE_A = (255, 210, 60)         # stone highlight
BADGE_B = (120, 30, 160)         # stone body
TINT_STRENGTH = 0.45

# The verified roster: form id, PokeAPI form id (what the sprite files are named
# after), base national dex id, Mega Stone item id, introducing game.
# Mega Rayquaza carries stone=None -- it Mega Evolves off the move Dragon Ascent
# instead of a held stone (contract 11.5).
ROSTER = [
    ('venusaur-mega',               10033,    3, 'venusaurite',        'xy'),
    ('charizard-mega-x',            10034,    6, 'charizardite-x',     'xy'),
    ('charizard-mega-y',            10035,    6, 'charizardite-y',     'xy'),
    ('blastoise-mega',              10036,    9, 'blastoisinite',      'xy'),
    ('alakazam-mega',               10037,   65, 'alakazite',          'xy'),
    ('gengar-mega',                 10038,   94, 'gengarite',          'xy'),
    ('kangaskhan-mega',             10039,  115, 'kangaskhanite',      'xy'),
    ('pinsir-mega',                 10040,  127, 'pinsirite',          'xy'),
    ('gyarados-mega',               10041,  130, 'gyaradosite',        'xy'),
    ('aerodactyl-mega',             10042,  142, 'aerodactylite',      'xy'),
    ('mewtwo-mega-x',               10043,  150, 'mewtwonite-x',       'xy'),
    ('mewtwo-mega-y',               10044,  150, 'mewtwonite-y',       'xy'),
    ('ampharos-mega',               10045,  181, 'ampharosite',        'xy'),
    ('scizor-mega',                 10046,  212, 'scizorite',          'xy'),
    ('heracross-mega',              10047,  214, 'heracronite',        'xy'),
    ('houndoom-mega',               10048,  229, 'houndoominite',      'xy'),
    ('tyranitar-mega',              10049,  248, 'tyranitarite',       'xy'),
    ('blaziken-mega',               10050,  257, 'blazikenite',        'xy'),
    ('gardevoir-mega',              10051,  282, 'gardevoirite',       'xy'),
    ('mawile-mega',                 10052,  303, 'mawilite',           'xy'),
    ('aggron-mega',                 10053,  306, 'aggronite',          'xy'),
    ('medicham-mega',               10054,  308, 'medichamite',        'xy'),
    ('manectric-mega',              10055,  310, 'manectite',          'xy'),
    ('banette-mega',                10056,  354, 'banettite',          'xy'),
    ('absol-mega',                  10057,  359, 'absolite',           'xy'),
    ('garchomp-mega',               10058,  445, 'garchompite',        'xy'),
    ('lucario-mega',                10059,  448, 'lucarionite',        'xy'),
    ('abomasnow-mega',              10060,  460, 'abomasite',          'xy'),
    ('beedrill-mega',               10090,   15, 'beedrillite',        'oras'),
    ('pidgeot-mega',                10073,   18, 'pidgeotite',         'oras'),
    ('slowbro-mega',                10071,   80, 'slowbronite',        'oras'),
    ('steelix-mega',                10072,  208, 'steelixite',         'oras'),
    ('sceptile-mega',               10065,  254, 'sceptilite',         'oras'),
    ('swampert-mega',               10064,  260, 'swampertite',        'oras'),
    ('sableye-mega',                10066,  302, 'sablenite',          'oras'),
    ('sharpedo-mega',               10070,  319, 'sharpedonite',       'oras'),
    ('camerupt-mega',               10087,  323, 'cameruptite',        'oras'),
    ('altaria-mega',                10067,  334, 'altarianite',        'oras'),
    ('glalie-mega',                 10074,  362, 'glalitite',          'oras'),
    ('salamence-mega',              10089,  373, 'salamencite',        'oras'),
    ('metagross-mega',              10076,  376, 'metagrossite',       'oras'),
    ('latias-mega',                 10062,  380, 'latiasite',          'oras'),
    ('latios-mega',                 10063,  381, 'latiosite',          'oras'),
    ('rayquaza-mega',               10079,  384, None,                 'oras'),
    ('lopunny-mega',                10088,  428, 'lopunnite',          'oras'),
    ('gallade-mega',                10068,  475, 'galladite',          'oras'),
    ('audino-mega',                 10069,  531, 'audinite',           'oras'),
    ('diancie-mega',                10075,  719, 'diancite',           'oras'),
    ('raichu-mega-x',               10304,   26, 'raichunite-x',       'za'),
    ('raichu-mega-y',               10305,   26, 'raichunite-y',       'za'),
    ('clefable-mega',               10278,   36, 'clefablite',         'za'),
    ('victreebel-mega',             10279,   71, 'victreebelite',      'za'),
    ('starmie-mega',                10280,  121, 'starminite',         'za'),
    ('dragonite-mega',              10281,  149, 'dragoninite',        'za'),
    ('meganium-mega',               10282,  154, 'meganiumite',        'za'),
    ('feraligatr-mega',             10283,  160, 'feraligite',         'za'),
    ('skarmory-mega',               10284,  227, 'skarmorite',         'za'),
    ('chimecho-mega',               10306,  358, 'chimechite',         'za'),
    ('absol-mega-z',                10307,  359, 'absolite-z',         'za'),
    ('staraptor-mega',              10308,  398, 'staraptite',         'za'),
    ('garchomp-mega-z',             10309,  445, 'garchompite-z',      'za'),
    ('lucario-mega-z',              10310,  448, 'lucarionite-z',      'za'),
    ('froslass-mega',               10285,  478, 'froslassite',        'za'),
    ('heatran-mega',                10311,  485, 'heatranite',         'za'),
    ('darkrai-mega',                10312,  491, 'darkranite',         'za'),
    ('emboar-mega',                 10286,  500, 'emboarite',          'za'),
    ('excadrill-mega',              10287,  530, 'excadrite',          'za'),
    ('scolipede-mega',              10288,  545, 'scolipite',          'za'),
    ('scrafty-mega',                10289,  560, 'scraftinite',        'za'),
    ('eelektross-mega',             10290,  604, 'eelektrossite',      'za'),
    ('chandelure-mega',             10291,  609, 'chandelurite',       'za'),
    ('golurk-mega',                 10313,  623, 'golurkite',          'za'),
    ('chesnaught-mega',             10292,  652, 'chesnaughtite',      'za'),
    ('delphox-mega',                10293,  655, 'delphoxite',         'za'),
    ('greninja-mega',               10294,  658, 'greninjite',         'za'),
    ('pyroar-mega',                 10295,  668, 'pyroarite',          'za'),
    ('floette-mega',                10296,  670, 'floettite',          'za'),
    ('meowstic-male-mega',          10314,  678, 'meowsticite',        'za'),
    ('meowstic-female-mega',        10326,  678, 'meowsticite',        'za'),
    ('malamar-mega',                10297,  687, 'malamarite',         'za'),
    ('barbaracle-mega',             10298,  689, 'barbaracite',        'za'),
    ('dragalge-mega',               10299,  691, 'dragalgite',         'za'),
    ('hawlucha-mega',               10300,  701, 'hawluchanite',       'za'),
    ('zygarde-mega',                10301,  718, 'zygardite',          'za'),
    ('crabominable-mega',           10315,  740, 'crabominite',        'za'),
    ('golisopod-mega',              10316,  768, 'golisopite',         'za'),
    ('drampa-mega',                 10302,  780, 'drampanite',         'za'),
    ('magearna-mega',               10317,  801, 'magearnite',         'za'),
    ('magearna-original-mega',      10318,  801, 'magearnite',         'za'),
    ('zeraora-mega',                10319,  807, 'zeraorite',          'za'),
    ('falinks-mega',                10303,  870, 'falinksite',         'za'),
    ('scovillain-mega',             10320,  952, 'scovillainite',      'za'),
    ('glimmora-mega',               10321,  970, 'glimmoranite',       'za'),
    ('tatsugiri-curly-mega',        10322,  978, 'tatsugirinite',      'za'),
    ('tatsugiri-droopy-mega',       10323,  978, 'tatsugirinite',      'za'),
    ('tatsugiri-stretchy-mega',     10324,  978, 'tatsugirinite',      'za'),
    ('baxcalibur-mega',             10325,  998, 'baxcalibrite',       'za'),
]

# A placeholder normally derives from the base species' default sprite.  Where
# the Mega is documented as coming from a non-default form, derive it from that
# form instead so the stand-in is at least the right silhouette: Mega Zygarde is
# reached from Complete Forme (PokeAPI form 10120), not the 50% Forme of #718.
PLACEHOLDER_BASE = {'zygarde-mega': 10120}

# Tokens that must never appear in a form id, kept as data so the assertion can
# name what it caught.
FORBIDDEN = ('primal', 'dynamax', 'gigantamax', 'gmax', 'tera', 'z-move')


def assert_exclusions(forms):
    """Contract 11.5: Primal Reversion (and the other gimmicks) must be absent."""
    bad = [f['id'] for f in forms
           if any(tok in f['id'].lower() for tok in FORBIDDEN)]
    if bad:
        raise SystemExit('EXCLUDED FORMS PRESENT IN ROSTER: %s' % bad)
    bases = set(f['base'] for f in forms)
    for dex, name in ((382, 'Kyogre'), (383, 'Groudon')):
        if dex in bases:
            raise SystemExit('%s (#%d) has no Mega -- only Primal, which is OUT'
                             % (name, dex))
    stones = set(f['stone'] for f in forms)
    for orb in ('red-orb', 'blue-orb'):
        if orb in stones:
            raise SystemExit('%s is a Primal Reversion item, which is OUT' % orb)

    # The roster above is ours; assert the same over the data build's output, so
    # a Primal sneaking into megas.json fails this build too rather than merely
    # going un-spritted.
    if os.path.exists(MEGAS_JSON):
        with open(MEGAS_JSON) as f:
            entries = json.load(f).get('forms', [])
        bad = [e.get('id') for e in entries
               if any(tok in (e.get('id') or '').lower() for tok in FORBIDDEN)
               or e.get('stone') in ('red-orb', 'blue-orb')
               or e.get('base') in (382, 383)]
        if bad:
            raise SystemExit('data/megas.json contains excluded forms: %s' % bad)


# ------------------------------------------------------------------- roster
def load_roster():
    """-> [form dict].  ``data/megas.json`` wins on form ids when it exists.

    The Mega *data* build runs concurrently with this one, so megas.json may be
    absent (first run) or newer than the table above.  Reconcile by PokeAPI form
    id where the data build records one, else by (base dex, stone), else by id,
    and report whatever only one side knows about.
    """
    forms = [dict(id=i, pokeapi=p, base=b, stone=s, introducedIn=g,
                  front=None, back=None, icon=None, placeholder=False, notes=[])
             for i, p, b, s, g in ROSTER]
    if not os.path.exists(MEGAS_JSON):
        log('data/megas.json not written yet -- using the built-in roster '
            '(%d forms)' % len(forms))
        return forms

    with open(MEGAS_JSON) as f:
        entries = json.load(f).get('forms', [])

    def tokens(form_id):
        # 'magearna-original-mega' and 'magearna-mega-original' name the same
        # form; word order is the only thing the two conventions disagree on.
        return frozenset((form_id or '').split('-'))

    # Every index must be one-to-one or it cannot safely rename anything: three
    # Tatsugiri Megas share a base dex AND a stone, so a (base, stone) hit is
    # only trustworthy when it is unique on both sides.
    def unique_index(pairs):
        idx = {}
        for k, v in pairs:
            idx[k] = None if k in idx else v
        return dict((k, v) for k, v in idx.items() if v is not None)

    by_pokeapi = unique_index((e['pokeapiId'], e) for e in entries if e.get('pokeapiId'))
    by_id = unique_index((e.get('id'), e) for e in entries)
    by_tokens = unique_index((tokens(e.get('id')), e) for e in entries)
    by_key = unique_index(((e.get('base'), e.get('stone')), e) for e in entries)
    mine_by_key = unique_index(((f['base'], f['stone']), f) for f in forms)

    claimed = {}
    for f in forms:
        e = (by_pokeapi.get(f['pokeapi']) or by_id.get(f['id'])
             or by_tokens.get(tokens(f['id'])))
        if e is None and (f['base'], f['stone']) in mine_by_key:
            e = by_key.get((f['base'], f['stone']))
        if e is None:
            f['notes'].append('not found in data/megas.json')
            continue
        if id(e) in claimed:
            # Two roster rows resolving to one entry would silently overwrite
            # one form's sprites with the other's.  Refuse instead.
            raise SystemExit('megas.json entry %r matches both %s and %s'
                             % (e.get('id'), claimed[id(e)], f['id']))
        claimed[id(e)] = f['id']
        if e.get('id') and e['id'] != f['id']:
            f['notes'].append('id taken from megas.json (was %s)' % f['id'])
            f['id'] = e['id']

    out_ids = [f['id'] for f in forms]
    if len(set(out_ids)) != len(out_ids):
        raise SystemExit('duplicate form ids after reconciling with megas.json')
    extra = [e.get('id') for e in entries if id(e) not in claimed]
    log('data/megas.json: %d forms, %d matched here%s'
        % (len(entries), len(claimed),
           (', %d only there: %s' % (len(extra), extra)) if extra else ''))
    return forms


# -------------------------------------------------------------- placeholders
def mark_placeholder(img, size=FRAME):
    """Tint, frame and badge an image so it reads as 'not the real art'.

    The blend has to run on RGB only: ``Image.blend`` over RGBA would drag the
    alpha channel toward 45% opaque as well and turn the transparent background
    into a violet rectangle.
    """
    img = img.convert('RGBA')
    alpha = img.getchannel('A')
    rgb = Image.blend(img.convert('RGB'), Image.new('RGB', img.size, TINT),
                      TINT_STRENGTH).convert('RGBA')
    rgb.putalpha(alpha)

    out = Image.new('RGBA', img.size, (0, 0, 0, 0))
    out.alpha_composite(rgb)
    d = ImageDraw.Draw(out)
    edge = max(1, size // 48)
    d.rectangle([0, 0, img.size[0] - 1, img.size[1] - 1],
                outline=TINT + (255,), width=edge)

    # Mega-stone badge: a two-tone diamond in the top-right corner.
    r = max(4, size // 8)
    cx, cy = img.size[0] - r - edge - 1, r + edge + 1
    d.polygon([(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)],
              fill=BADGE_B + (255,), outline=(255, 255, 255, 255))
    d.polygon([(cx, cy - r + 2), (cx + max(2, r // 2), cy), (cx, cy)],
              fill=BADGE_A + (255,))
    return out


def base_image(form, back=False, offline=False):
    """The base sprite a placeholder for `form` is derived from.

    Prefers the already-built species asset (ROM-extracted for 1..649) and falls
    back to fetching the PokeAPI BW sprite, which is also the only route for a
    PLACEHOLDER_BASE override since those alternate forms have no dex-numbered
    asset of their own.
    """
    alt = PLACEHOLDER_BASE.get(form['id'])
    if not alt:
        path = os.path.join(BASE_BACK if back else BASE_FRONT,
                            '%03d.png' % form['base'])
        if os.path.exists(path):
            return Image.open(path).convert('RGBA')
    num = alt or form['base']
    url = ('%s/back/%d.png' if back else '%s/%d.png') % (BW, num)
    name = 'bw_%s_%d.png' % ('back' if back else 'front', num)
    if offline:
        p = os.path.join(CACHE, name)
        p = p if os.path.exists(p) else None
    else:
        p = cached(url, name)
    if not p:
        return None
    return fit_frame(Image.open(p).convert('RGBA'))


def placeholder_src(form):
    """Human-readable provenance for a placeholder, for the manifest."""
    alt = PLACEHOLDER_BASE.get(form['id'])
    return ('pokeapi form %d' % alt) if alt else ('base #%d' % form['base'])


# ------------------------------------------------------------------- output
def ensure_dirs():
    for d in (OUT_MEGA, OUT_BACK, OUT_ICON, os.path.dirname(MANIFEST)):
        if not os.path.isdir(d):
            os.makedirs(d)


def save(img, folder, form_id):
    path = os.path.join(folder, '%s.png' % form_id)
    img.save(path)
    return os.path.relpath(path, ROOT).replace('\\', '/')


def build(forms, download=True):
    jobs = []
    for f in forms:
        p = f['pokeapi']
        jobs += [('%s/%d.png' % (BW, p), 'mega_front_%d.png' % p),
                 ('%s/back/%d.png' % (BW, p), 'mega_back_%d.png' % p),
                 ('%s/%d.png' % (G8_ICON, p), 'mega_icon8_%d.png' % p),
                 ('%s/%d.png' % (G7_ICON, p), 'mega_icon7_%d.png' % p)]
    if download:
        log('fetching %d files for %d Mega forms' % (len(jobs), len(forms)))
        t0 = time.time()
        got = fetch_many(jobs)
        log('  fetch done in %.0fs' % (time.time() - t0))
    else:
        # Cache-only: look the files up on disk rather than calling cached(),
        # which would go to the network on a miss.
        got = {}
        for _, name in jobs:
            p = os.path.join(CACHE, name)
            got[name] = p if os.path.exists(p) else None
        log('offline: %d/%d files already cached'
            % (sum(1 for v in got.values() if v), len(jobs)))

    for f in forms:
        p = f['pokeapi']

        # --- front -------------------------------------------------------
        src = got.get('mega_front_%d.png' % p)
        img = fit_frame(Image.open(src).convert('RGBA')) if src else None
        if img is not None:
            f['front'] = save(img, OUT_MEGA, f['id'])
            f['source_front'] = 'pokeapi:generation-v/black-white/%d' % p
        else:
            base = base_image(f, offline=not download)
            if base is None:
                f['notes'].append('front: no Mega art and no base sprite to derive from')
            else:
                f['front'] = save(mark_placeholder(base), OUT_MEGA, f['id'])
                f['source_front'] = 'placeholder:%s tinted' % placeholder_src(f)
                f['placeholder'] = True

        # --- back --------------------------------------------------------
        src = got.get('mega_back_%d.png' % p)
        img = fit_frame(Image.open(src).convert('RGBA')) if src else None
        if img is not None:
            f['back'] = save(img, OUT_BACK, f['id'])
            f['source_back'] = 'pokeapi:generation-v/black-white/back/%d' % p
        else:
            base = base_image(f, back=True, offline=not download)
            if base is None:
                f['notes'].append('back: no Mega art and no base sprite to derive from')
            else:
                f['back'] = save(mark_placeholder(base), OUT_BACK, f['id'])
                f['source_back'] = 'placeholder:%s back tinted' % placeholder_src(f)
                f['placeholder'] = True

        # --- icon --------------------------------------------------------
        for cname, label in (('mega_icon8_%d.png' % p, 'pokeapi:generation-viii/icons'),
                             ('mega_icon7_%d.png' % p, 'pokeapi:generation-vii/icons')):
            q = got.get(cname)
            if not q:
                continue
            ic = fit_icon(Image.open(q).convert('RGBA'))
            if ic is not None:
                f['icon'] = save(ic, OUT_ICON, f['id'])
                f['source_icon'] = label
                break
        if not f['icon'] and f['front']:
            # No box icon is published anywhere for the Z-A Megas.  Derive one
            # from whatever front art this form ended up with -- if that was a
            # placeholder the icon inherits the tint, which is what we want.
            ic = fit_icon(Image.open(os.path.join(ROOT, f['front'])).convert('RGBA'))
            if ic is not None:
                f['icon'] = save(ic, OUT_ICON, f['id'])
                f['source_icon'] = ('placeholder:downscaled front' if f['placeholder']
                                    else 'derived:downscaled front sprite')
        if not f['icon']:
            f['notes'].append('icon: no source')

    note_shared_art(forms)


def note_shared_art(forms):
    """Flag forms whose front art is byte-identical to another form's.

    Upstream ships one image for some form pairs (Mega Meowstic M/F).  That is
    not an error -- the two really do look the same -- but it should be visible
    in the manifest rather than discovered later in a battle scene.
    """
    import hashlib
    seen = {}
    for f in forms:
        if not f['front']:
            continue
        h = hashlib.md5(open(os.path.join(ROOT, f['front']), 'rb').read()).hexdigest()
        seen.setdefault(h, []).append(f)
    for group in seen.values():
        if len(group) < 2:
            continue
        ids = [g['id'] for g in group]
        for g in group:
            g['shared_art_with'] = [i for i in ids if i != g['id']]
            g['notes'].append('upstream ships identical front art for %s'
                              % ', '.join(g['shared_art_with']))


# --------------------------------------------------------------- verification
def pick_check(forms, n=24):
    """Placeholders first -- they are what actually needs eyeballing -- then an
    even spread across the rest of the roster."""
    ph = [f for f in forms if f['placeholder']]
    real = [f for f in forms if not f['placeholder']]
    out = ph[:n]
    if len(out) < n and real:
        step = max(1, len(real) // (n - len(out)))
        out += real[::step][:n - len(out)]
    return out[:n]


def build_check_sheet(forms):
    picks = pick_check(forms)
    cols, rows = 6, 4
    cw, ch = 96 + 52, 96 + 26
    sheet = Image.new('RGBA', (cols * cw + 8, rows * ch + 28), (250, 250, 252, 255))
    d = ImageDraw.Draw(sheet)
    nph = sum(1 for f in forms if f['placeholder'])
    d.text((6, 5), 'project-platinum MEGA sprite check - front / back / icon   '
                   '(%d real art, %d placeholder, of %d forms)'
           % (len(forms) - nph, nph, len(forms)), fill=(20, 20, 30, 255))
    holes = []
    for i, f in enumerate(picks):
        ox, oy = 4 + (i % cols) * cw, 24 + (i // cols) * ch
        if f['front']:
            sheet.alpha_composite(
                Image.open(os.path.join(ROOT, f['front'])).convert('RGBA'), (ox, oy))
        else:
            holes.append(f['id'])
        if f['back']:
            b = Image.open(os.path.join(ROOT, f['back'])).convert('RGBA').resize((48, 48))
            sheet.alpha_composite(b, (ox + 96, oy))
        if f['icon']:
            sheet.alpha_composite(
                Image.open(os.path.join(ROOT, f['icon'])).convert('RGBA'), (ox + 104, oy + 56))
        d.text((ox + 2, oy + 98), f['id'][:26], fill=(30, 30, 40, 255))
        ph = f['placeholder']
        d.text((ox + 2, oy + 108), 'PLACEHOLDER' if ph else f['introducedIn'].upper(),
               fill=(190, 40, 40, 255) if ph else (120, 120, 130, 255))
    sheet.convert('RGB').save(CHECK_SHEET)
    return holes


# ------------------------------------------------------------------ manifest
def mega_manifest(forms):
    real = [f['id'] for f in forms if f['front'] and not f['placeholder']]
    ph = [f['id'] for f in forms if f['placeholder']]
    derived_icons = [f['id'] for f in forms
                     if (f.get('source_icon') or '').startswith(('derived:', 'placeholder:'))]
    return dict(
        generated_by='tools/build_mega_sprites.py',
        frame=FRAME, icon=ICON,
        convention='content trimmed, centred horizontally, stood on the bottom edge',
        source='PokeAPI/sprites generation-v/black-white, keyed by PokeAPI form id',
        placeholder_style='base species sprite, violet tint + border + Mega-stone badge',
        counts=dict(total=len(forms), real_art=len(real), placeholder=len(ph),
                    missing_front=sum(1 for f in forms if not f['front']),
                    missing_back=sum(1 for f in forms if not f['back']),
                    missing_icon=sum(1 for f in forms if not f['icon']),
                    icon_derived_from_front=len(derived_icons)),
        placeholders=ph,
        forms=forms,
    )


def merge_manifest(mega):
    """Add/replace only the "megas" key of data/rom/sprites.json.

    build_sprites.py rewrites that file wholesale, so this is a read-modify-write
    of whatever is on disk right now, published through a temp file so a reader
    never sees a half-written manifest.
    """
    doc = {}
    if os.path.exists(MANIFEST):
        with open(MANIFEST) as f:
            doc = json.load(f)
    doc['megas'] = mega
    tmp = MANIFEST + '.tmp'
    with open(tmp, 'w') as f:
        json.dump(doc, f, indent=1)
    os.replace(tmp, MANIFEST)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--no-download', action='store_true',
                    help='use only what is already in tools/.cache/sprites')
    ap.add_argument('--check-only', action='store_true',
                    help='rebuild the contact sheet from the sidecar manifest')
    ap.add_argument('--manifest-only', action='store_true',
                    help='re-merge the sidecar manifest into data/rom/sprites.json')
    args = ap.parse_args()
    ensure_dirs()

    if args.check_only or args.manifest_only:
        with open(SIDECAR) as f:
            mega = json.load(f)
        if args.check_only:
            holes = build_check_sheet(mega['forms'])
            log('sheet -> %s%s' % (os.path.relpath(CHECK_SHEET, ROOT),
                                   ('  HOLES: %s' % holes) if holes else ''))
        if args.manifest_only:
            merge_manifest(mega)
            log('re-merged into %s' % os.path.relpath(MANIFEST, ROOT))
        return 0

    forms = load_roster()
    assert_exclusions(forms)
    build(forms, download=not args.no_download)

    mega = mega_manifest(forms)
    with open(SIDECAR, 'w') as f:
        json.dump(mega, f, indent=1)
    merge_manifest(mega)
    holes = build_check_sheet(forms)

    c = mega['counts']
    log('')
    log('Mega forms: %d   real art: %d   placeholder: %d'
        % (c['total'], c['real_art'], c['placeholder']))
    log('missing front: %d  back: %d  icon: %d   (icons downscaled from front: %d)'
        % (c['missing_front'], c['missing_back'], c['missing_icon'],
           c['icon_derived_from_front']))
    if mega['placeholders']:
        log('placeholders: %s' % ', '.join(mega['placeholders']))
    for f in forms:
        if f['notes']:
            log('  %-26s %s' % (f['id'], '; '.join(f['notes'])))
    if holes:
        log('CONTACT SHEET HAS HOLES: %s' % holes)
    log('sheet    -> %s' % os.path.relpath(CHECK_SHEET, ROOT))
    log('manifest -> %s (key "megas") + %s'
        % (os.path.relpath(MANIFEST, ROOT), os.path.relpath(SIDECAR, ROOT)))
    return 1 if c['missing_front'] or c['missing_back'] else 0


if __name__ == '__main__':
    sys.exit(main())
