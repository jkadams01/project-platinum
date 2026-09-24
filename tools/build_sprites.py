#!/usr/bin/env python
"""Build every Pokemon image the game needs: front, back and party icon for
national dex 1..1025.

Sources
-------
1..649    the owner's own Pokemon White 2 cartridge dump.
          Front/back come from NARC ``/a/0/0/4``, which does NOT hold a flat
          sprite -- see `compose_bw_sprite` for the multicell rig that has to be
          run to get one.  Icons come from NARC ``/a/0/0/7``.
650..1025 Gen-5-style sprites from the PokeAPI/sprites mirror of the Smogon
          Sprite Project (official BW art does not exist for these species).
          Cached under ``tools/.cache/``.

Output (all gitignored -- nothing ROM-derived is ever committed)
---------------------------------------------------------------
  assets/generated/pkmn/<id>.png        96x96 front
  assets/generated/pkmn/back/<id>.png   96x96 back
  assets/generated/icon/<id>.png        32x32 party icon
  assets/generated/_sprite_check.png    24-species visual contact sheet
  data/rom/sprites.json                 per-species manifest + miss list

Usage
-----
  source tools/_work/gen5/env.sh      # PIL needs the anaconda DLL path here
  python tools/build_sprites.py
  python tools/build_sprites.py --no-download     # ROM half only
  python tools/build_sprites.py --check-only      # rebuild the contact sheet
"""

import argparse
import json
import os
import sys
import time

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from lib.nitro import (NDS, NARC, read_nclr, read_ncgr, read_ncer, read_nanr,
                       read_nmcr, ncgr_raster, tiles_to_image, to_rgba)

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROM_DIR = os.path.join(ROOT, 'References', 'Roms')
CACHE = os.path.join(ROOT, 'tools', '.cache', 'sprites')
OUT_PKMN = os.path.join(ROOT, 'assets', 'generated', 'pkmn')
OUT_BACK = os.path.join(OUT_PKMN, 'back')
OUT_ICON = os.path.join(ROOT, 'assets', 'generated', 'icon')
MANIFEST = os.path.join(ROOT, 'data', 'rom', 'sprites.json')
CHECK_SHEET = os.path.join(ROOT, 'assets', 'generated', '_sprite_check.png')

MAX_DEX = 1025
ROM_MAX = 649            # highest dex the White 2 pokegra covers as a base form
FRAME = 96               # battle sprite frame, px
ICON = 32                # party icon frame, px

PKAPI = ('https://raw.githubusercontent.com/PokeAPI/sprites/master/sprites/pokemon')
BW = PKAPI + '/versions/generation-v/black-white'
G8_ICON = PKAPI + '/versions/generation-viii/icons'
GV_ICON = PKAPI + '/versions/generation-v/icons'

# /a/0/0/4 is 20 entries per national-dex group.
G_FRONT = 0              # +0 NCGR 96x96 tiled   +2 NCGR 256x128 linear part atlas
G_BACK = 9               # +9 .. +17: the same 9-slot block for the back sprite
SLOT_ATLAS = 2           # the linear 256x128 part atlas the cells index into
SLOT_CELLS = 4           # NCER
SLOT_ANIM = 5            # NANR
SLOT_RIG = 6             # NMCR
PAL_NORMAL = 18          # NCLR
ATLAS_TILES_WIDE = 32    # 256 px / 8 -- the char bank is addressed in 2D


def log(msg):
    sys.stdout.write(msg + '\n')
    sys.stdout.flush()


# --------------------------------------------------------------- BW composer
def compose_bw_sprite(narc, dex, block, palette_slot=PAL_NORMAL, canvas=256):
    """Assemble one static BW battle sprite and return it as an RGBA image.

    There is no pre-composed flat sprite anywhere in a Gen 5 ROM.  Slot +0 of a
    group looks like one (it is exactly 96x96 = 12x12 tiles) but de-tiling it
    raster-wise yields a scattered pile of ears, jaws and feet: it is a part
    atlas, not a picture.  The real sprite only exists once the NNS multicell
    rig has been run.  Four things have to be right at once:

      1. the character bank is slot +2 (a 256x128 *linear* bitmap), not slot +0;
      2. the cell OAMs address it in **2D mapping** -- tile *t* is the 8x8 block
         at (t % 32 * 8, t // 32 * 8) of that bitmap, NOT the t-th tile of a
         1D run;
      3. an NMCR node is (u16 animSequenceIndex, s16 x, s16 y, u16 order) --
         reading the order word first makes every node draw the wrong part;
      4. almost every OAM here sets both the rot/scale bit and bit 9, i.e.
         **double-size**, which offsets the drawn sprite by (w/2, h/2) inside
         its box.  Skipping that scatters the feet and limbs by half a part.

    Verified by extracting all 649 x 2 sprites and diffing the content bounding
    box against the PokeAPI BW rip: 11 of 14 spot-checked species match to the
    pixel, the rest to within a few px of animation-frame choice.
    """
    base = dex * 20
    palettes = read_nclr(narc[base + palette_slot])
    pal = palettes[0]

    gfx = read_ncgr(narc[base + block + SLOT_ATLAS])
    aw, ah, raster = ncgr_raster(gfx)
    atlas = to_rgba(aw, ah, raster, pal, 0)

    cells = read_ncer(narc[base + block + SLOT_CELLS])
    seqs = read_nanr(narc[base + block + SLOT_ANIM])
    rigs = read_nmcr(narc[base + block + SLOT_RIG])
    if not rigs:
        raise ValueError('dex %d block %d: empty multicell rig' % (dex, block))

    img = Image.new('RGBA', (canvas, canvas), (0, 0, 0, 0))
    cx = cy = canvas // 2
    for node in sorted(rigs[0], key=lambda n: n['order']):
        if node['anim'] >= len(seqs):
            continue
        frames = seqs[node['anim']]['frames']
        if not frames:
            continue
        cell_index = frames[0][0]
        if cell_index >= len(cells):
            continue
        for oam in cells[cell_index]['oams']:
            if oam['disabled']:
                continue
            w, h, t = oam['w'], oam['h'], oam['tile']
            sx, sy = (t % ATLAS_TILES_WIDE) * 8, (t // ATLAS_TILES_WIDE) * 8
            if sx + w > aw or sy + h > ah:
                continue
            part = atlas.crop((sx, sy, sx + w, sy + h))
            if not oam['rot']:
                if oam['flipx']:
                    part = part.transpose(Image.FLIP_LEFT_RIGHT)
                if oam['flipy']:
                    part = part.transpose(Image.FLIP_TOP_BOTTOM)
            dx, dy = (w // 2, h // 2) if oam['double'] else (0, 0)
            layer = Image.new('RGBA', img.size, (0, 0, 0, 0))
            layer.paste(part, (oam['x'] + dx + cx + node['x'],
                               oam['y'] + dy + cy + node['y']))
            img.alpha_composite(layer)
    return img


def fit_frame(img, size=FRAME):
    """Trim to content, then centre horizontally and stand it on the floor.

    The ROM does not bake the on-screen vertical offset into the rig (that
    lives in a separate placement table), so we adopt one explicit convention
    for every species: a single ground line at the bottom of the frame.  A
    battle scene then lines every Pokemon up on the same floor and can add its
    own hover/bob.
    """
    bbox = img.getbbox()
    if bbox is None:
        return None
    crop = img.crop(bbox)
    if crop.width > size or crop.height > size:
        scale = min(size / float(crop.width), size / float(crop.height))
        crop = crop.resize((max(1, int(crop.width * scale)),
                            max(1, int(crop.height * scale))), Image.NEAREST)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.alpha_composite(crop, ((size - crop.width) // 2, size - crop.height))
    return out


# ------------------------------------------------------------------- icons
def icon_palettes(narc):
    """The three shared 16-colour party-icon palettes (NARC entry 0)."""
    return read_nclr(narc[0])[:3]


def read_icon_tiles(narc, dex):
    """-> (w, h, raster indices) for the two-frame 32x64 icon of `dex`."""
    entry = 8 + 2 * dex          # White 2: 8-entry header, then NCGR/void pairs
    gfx = read_ncgr(narc[entry])
    return tiles_to_image(gfx['idx'], gfx['ntiles'], 4)


def shared_indices(palettes):
    """Palette slots that hold the same colour in every candidate palette.

    White and the two greys are identical across all three icon palettes, so
    they match everything and only add noise to any scoring.
    """
    n = min(len(p) for p in palettes)
    return set(i for i in range(1, n) if len({tuple(p[i]) for p in palettes}) == 1)


def palette_from_reference(ref_image, palettes):
    """Exact palette resolution from a known-good rip of the same icon.

    A Gen 5 party icon paints one of three shared 16-colour palettes, and the
    per-species index lives in a BLZ-compressed ARM9 table this project has not
    unpacked (a raw-ROM, packed-bitfield and per-NARC-field scan for it all came
    back empty).  Given any correctly-palettised rip of the icon, though, the
    index is not a guess at all: the rip's set of opaque colours is a subset of
    exactly one palette.  We still paint the pixels out of the owner's own
    cartridge -- only the 3-way index comes from the reference.

    -> (palette index, number of reference colours that palette cannot explain)
    """
    cols = set((r, g, b) for r, g, b, a in ref_image.convert('RGBA').getdata() if a > 0)
    scores = [len(cols - set(tuple(c) for c in pal[1:])) for pal in palettes]
    best = min(range(len(scores)), key=lambda i: scores[i])
    return best, scores[best]


def pick_icon_palette(indices, palettes, sprite_hist):
    """Offline fallback: score each palette against the battle sprite's colours.

    Only the slots that actually differ between palettes carry information, and
    a match against a colour that covers a lot of the battle sprite is worth
    more than a match against a stray highlight.  Measured at 82.5% agreement
    with `palette_from_reference` over a random 120-species sample -- good
    enough to keep the pipeline running offline, not good enough to prefer.
    """
    shared = shared_indices(palettes)
    used = {}
    for v in indices:
        if v and v not in shared:
            used[v] = used.get(v, 0) + 1
    if not used or not sprite_hist:
        return 0
    total = float(sum(used.values()))
    best, best_score = 0, None
    for pi, pal in enumerate(palettes):
        score = 0.0
        for v, n in used.items():
            if v >= len(pal):
                continue
            r, g, b = pal[v]
            d = min(((r - c[0]) ** 2 + (g - c[1]) ** 2 + (b - c[2]) ** 2) / (w + 0.02)
                    for c, w in sprite_hist)
            score += (n / total) * d
        if best_score is None or score < best_score:
            best, best_score = pi, score
    return best


def sprite_histogram(img, top=24):
    """-> [((r, g, b), area fraction)] for the most-used opaque colours."""
    from collections import Counter
    import numpy as np
    a = np.asarray(img)
    px = a[:, :, :3][a[:, :, 3] > 0]
    if px.size == 0:
        return []
    c = Counter(map(tuple, px.tolist()))
    total = float(sum(c.values()))
    return [(k, v / total) for k, v in c.most_common(top)]


def fit_icon(img, size=ICON):
    bbox = img.getbbox()
    if bbox is None:
        return None
    crop = img.crop(bbox)
    if crop.width > size or crop.height > size:
        scale = min(size / float(crop.width), size / float(crop.height))
        crop = crop.resize((max(1, int(crop.width * scale)),
                            max(1, int(crop.height * scale))), Image.LANCZOS)
    out = Image.new('RGBA', (size, size), (0, 0, 0, 0))
    out.alpha_composite(crop, ((size - crop.width) // 2, size - crop.height))
    return out


# ---------------------------------------------------------------- downloads
def http_get(url, timeout=30):
    """-> bytes, or None on 404. Falls back to curl when python has no SSL."""
    try:
        import urllib.request
        import urllib.error
        try:
            with urllib.request.urlopen(url, timeout=timeout) as r:
                return r.read()
        except urllib.error.HTTPError as e:
            if e.code == 404:
                return None
            raise
    except ImportError:
        pass
    except Exception as e:
        if 'SSL' not in repr(e) and 'ssl' not in repr(e):
            raise
    import subprocess
    p = subprocess.Popen(['curl', '-sSL', '--retry', '2', '--max-time', str(timeout),
                          '-w', '%{http_code}', url], stdout=subprocess.PIPE)
    body, _ = p.communicate()
    code = body[-3:].decode('ascii', 'replace')
    body = body[:-3]
    if code == '404':
        return None
    if code != '200':
        raise IOError('%s -> HTTP %s' % (url, code))
    return body


def cached(url, name):
    """Fetch `url` once into tools/.cache/sprites/<name>. -> path or None."""
    path = os.path.join(CACHE, name)
    miss = path + '.404'
    if os.path.exists(path):
        return path
    if os.path.exists(miss):
        return None
    body = http_get(url)
    if body is None:
        open(miss, 'wb').close()
        return None
    with open(path, 'wb') as f:
        f.write(body)
    return path


def fetch_many(jobs, workers=8):
    """jobs: [(url, cache_name)] -> {cache_name: path or None}"""
    from concurrent.futures import ThreadPoolExecutor
    out = {}
    with ThreadPoolExecutor(max_workers=workers) as ex:
        futs = {ex.submit(cached, u, n): n for u, n in jobs}
        done = 0
        for f, n in list(futs.items()):
            try:
                out[n] = f.result()
            except Exception as e:
                log('  download failed %s: %r' % (n, e))
                out[n] = None
            done += 1
            if done % 200 == 0:
                log('  ... %d/%d fetched' % (done, len(futs)))
    return out


# ------------------------------------------------------------------- driver
def find_white2():
    d = os.path.join(ROM_DIR, 'White 2')
    if not os.path.isdir(d):
        raise IOError('no White 2 ROM directory at %s' % d)
    for name in sorted(os.listdir(d)):
        if not name.lower().endswith('.nds'):
            continue
        path = os.path.join(d, name)
        rom = NDS(path)
        if rom.title.startswith('POKEMON W2'):
            return rom
    raise IOError('no POKEMON W2 cartridge found in %s' % d)


def ensure_dirs():
    for d in (CACHE, OUT_PKMN, OUT_BACK, OUT_ICON, os.path.dirname(MANIFEST)):
        if not os.path.isdir(d):
            os.makedirs(d)


def save(img, folder, dex):
    path = os.path.join(folder, '%03d.png' % dex)
    img.save(path)
    return os.path.relpath(path, ROOT).replace('\\', '/')


def build_from_rom(entries, stats, allow_reference=True):
    rom = find_white2()
    log('ROM: %s  [%s]  %s' % (rom.title, rom.gamecode, os.path.basename(rom.path)))
    pokegra = NARC(rom.read('/a/0/0/4'))
    icons = NARC(rom.read('/a/0/0/7'))
    ipals = icon_palettes(icons)
    log('  /a/0/0/4: %d entries (%d dex groups)' % (len(pokegra), len(pokegra) // 20))
    log('  /a/0/0/7: %d entries, %d shared icon palettes' % (len(icons), len(ipals)))

    refs = {}
    if allow_reference:
        jobs = [('%s/%d.png' % (GV_ICON, d), 'gv_icon_%d.png' % d)
                for d in range(1, ROM_MAX + 1)]
        log('  fetching %d icon-palette references' % len(jobs))
        try:
            refs = fetch_many(jobs)
        except Exception as ex:
            log('  reference fetch unavailable (%r) - using the offline heuristic' % ex)

    t0 = time.time()
    for dex in range(1, ROM_MAX + 1):
        e = entries[dex]
        front_img = None
        for block, folder, key in ((G_FRONT, OUT_PKMN, 'front'),
                                   (G_BACK, OUT_BACK, 'back')):
            try:
                img = fit_frame(compose_bw_sprite(pokegra, dex, block))
                if img is None:
                    e['errors'].append('%s: composed blank' % key)
                    continue
                if key == 'front':
                    front_img = img
                e[key] = save(img, folder, dex)
                e['source_' + key] = 'white2:/a/0/0/4'
            except Exception as ex:
                e['errors'].append('%s: %r' % (key, ex))
        try:
            w, h, idx = read_icon_tiles(icons, dex)
            refpath = refs.get('gv_icon_%d.png' % dex)
            if refpath:
                pi, unexplained = palette_from_reference(Image.open(refpath), ipals)
                method = 'exact'
                if unexplained:
                    stats['icon_palette_inexact'] += 1
            else:
                pi = pick_icon_palette(idx, ipals,
                                       sprite_histogram(front_img) if front_img else [])
                method = 'heuristic'
            stats['icon_palette_method'][method] = stats['icon_palette_method'].get(method, 0) + 1
            full = to_rgba(w, h, idx, ipals[pi], 0)
            img = fit_icon(full.crop((0, 0, ICON, ICON)))
            if img is None:
                e['errors'].append('icon: blank')
            else:
                e['icon'] = save(img, OUT_ICON, dex)
                e['source_icon'] = 'white2:/a/0/0/7 pal%d (%s)' % (pi, method)
        except Exception as ex:
            e['errors'].append('icon: %r' % ex)
        if dex % 100 == 0:
            log('  rom %d/%d (%.0fs)' % (dex, ROM_MAX, time.time() - t0))
    log('  ROM extraction done in %.0fs' % (time.time() - t0))


def build_from_web(entries):
    jobs = []
    for dex in range(ROM_MAX + 1, MAX_DEX + 1):
        jobs.append(('%s/%d.png' % (BW, dex), 'bw_front_%d.png' % dex))
        jobs.append(('%s/back/%d.png' % (BW, dex), 'bw_back_%d.png' % dex))
        jobs.append(('%s/%d.png' % (G8_ICON, dex), 'g8_icon_%d.png' % dex))
    log('fetching %d files (cached in %s)' % (len(jobs), CACHE))
    got = fetch_many(jobs)

    for dex in range(ROM_MAX + 1, MAX_DEX + 1):
        e = entries[dex]
        for key, folder, cname, src in (
                ('front', OUT_PKMN, 'bw_front_%d.png' % dex, 'pokeapi:generation-v/black-white'),
                ('back', OUT_BACK, 'bw_back_%d.png' % dex, 'pokeapi:generation-v/black-white/back')):
            p = got.get(cname)
            if not p:
                e['errors'].append('%s: not published upstream' % key)
                continue
            img = fit_frame(Image.open(p).convert('RGBA'))
            if img is None:
                e['errors'].append('%s: downloaded image is blank' % key)
                continue
            e[key] = save(img, folder, dex)
            e['source_' + key] = src

        p = got.get('g8_icon_%d.png' % dex)
        if p:
            img = fit_icon(Image.open(p).convert('RGBA'))
            if img is not None:
                e['icon'] = save(img, OUT_ICON, dex)
                e['source_icon'] = 'pokeapi:generation-viii/icons'
                continue
        # No box icon exists anywhere for these (gen 9 and a few gen 8).
        # Derive one from the front sprite rather than shipping a hole.
        if e['front']:
            src = Image.open(os.path.join(ROOT, e['front'])).convert('RGBA')
            img = fit_icon(src)
            if img is not None:
                e['icon'] = save(img, OUT_ICON, dex)
                e['source_icon'] = 'derived:downscaled front sprite'
                continue
        e['errors'].append('icon: no source')


# --------------------------------------------------------------- verification
CHECK_SPECIES = [1, 6, 25, 94, 130, 150,
                 157, 196, 248, 282, 384, 445,
                 448, 483, 493, 555, 609, 649,
                 700, 724, 887, 892, 1000, 1025]


def species_names():
    path = os.path.join(ROOT, 'data', 'species.json')
    names = {}
    if os.path.exists(path):
        with open(path) as f:
            for s in json.load(f):
                names[s['id']] = s['name']
    return names


def build_check_sheet(entries):
    """24 species spanning all nine generations, front + back + icon + label."""
    from PIL import ImageDraw
    names = species_names()
    cols, rows = 6, 4
    cw, ch = 96 + 52, 96 + 24
    sheet = Image.new('RGBA', (cols * cw + 8, rows * ch + 26), (250, 250, 252, 255))
    d = ImageDraw.Draw(sheet)
    d.text((6, 5), 'project-platinum sprite check - front / back / icon', fill=(20, 20, 30, 255))
    missing = []
    for i, dex in enumerate(CHECK_SPECIES):
        e = entries[dex]
        ox, oy = 4 + (i % cols) * cw, 22 + (i // cols) * ch
        if e['front']:
            sheet.alpha_composite(Image.open(os.path.join(ROOT, e['front'])).convert('RGBA'),
                                  (ox, oy))
        else:
            missing.append(dex)
        if e['back']:
            b = Image.open(os.path.join(ROOT, e['back'])).convert('RGBA').resize((48, 48))
            sheet.alpha_composite(b, (ox + 96, oy))
        if e['icon']:
            sheet.alpha_composite(Image.open(os.path.join(ROOT, e['icon'])).convert('RGBA'),
                                  (ox + 104, oy + 56))
        label = '%d %s' % (dex, names.get(dex, '?'))
        d.text((ox + 4, oy + 96 + 2), label, fill=(30, 30, 40, 255))
        d.text((ox + 4, oy + 96 + 11), 'gen %d' % gen_of(dex), fill=(120, 120, 130, 255))
    sheet.convert('RGB').save(CHECK_SHEET)
    return missing


GEN_BOUNDS = [(1, 151, 1), (152, 251, 2), (252, 386, 3), (387, 493, 4), (494, 649, 5),
              (650, 721, 6), (722, 809, 7), (810, 905, 8), (906, 1025, 9)]


def gen_of(dex):
    for lo, hi, g in GEN_BOUNDS:
        if lo <= dex <= hi:
            return g
    return 0


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('--no-rom', action='store_true', help='skip the White 2 extraction')
    ap.add_argument('--no-download', action='store_true', help='skip the gen 6-9 fetch')
    ap.add_argument('--check-only', action='store_true',
                    help='rebuild the contact sheet from the existing manifest')
    args = ap.parse_args()
    ensure_dirs()

    entries = {}
    for dex in range(1, MAX_DEX + 1):
        entries[dex] = dict(id=dex, generation=gen_of(dex), front=None, back=None,
                            icon=None, errors=[])

    if args.check_only:
        with open(MANIFEST) as f:
            old = json.load(f)
        for s in old['species']:
            entries[s['id']].update(s)
    else:
        stats = dict(icon_palette_method={}, icon_palette_inexact=0)
        if not args.no_rom:
            build_from_rom(entries, stats, allow_reference=not args.no_download)
        if not args.no_download:
            build_from_web(entries)

    have = [d for d in range(1, MAX_DEX + 1)
            if entries[d]['front'] and entries[d]['back'] and entries[d]['icon']]
    miss_front = [d for d in range(1, MAX_DEX + 1) if not entries[d]['front']]
    miss_back = [d for d in range(1, MAX_DEX + 1) if not entries[d]['back']]
    miss_icon = [d for d in range(1, MAX_DEX + 1) if not entries[d]['icon']]

    missing_on_sheet = build_check_sheet(entries)

    manifest = dict(
        generated_by='tools/build_sprites.py',
        frame=FRAME, icon=ICON, max_dex=MAX_DEX,
        convention='content trimmed, centred horizontally, stood on the bottom edge',
        counts=dict(complete=len(have),
                    missing_front=len(miss_front),
                    missing_back=len(miss_back),
                    missing_icon=len(miss_icon)),
        missing=dict(front=miss_front, back=miss_back, icon=miss_icon),
        species=[entries[d] for d in range(1, MAX_DEX + 1)],
    )
    with open(MANIFEST, 'w') as f:
        json.dump(manifest, f, indent=1)

    log('')
    log('complete (front+back+icon): %d / %d' % (len(have), MAX_DEX))
    log('MISSING front: %d  back: %d  icon: %d' % (len(miss_front), len(miss_back), len(miss_icon)))
    for label, lst in (('front', miss_front), ('back', miss_back), ('icon', miss_icon)):
        if lst:
            log('  missing %s: %s%s' % (label, lst[:25], ' ...' if len(lst) > 25 else ''))
    if missing_on_sheet:
        log('CONTACT SHEET HAS HOLES: %s' % missing_on_sheet)
    log('manifest -> %s' % os.path.relpath(MANIFEST, ROOT))
    log('sheet    -> %s' % os.path.relpath(CHECK_SHEET, ROOT))
    return 0 if not miss_front and not miss_back else 1


if __name__ == '__main__':
    sys.exit(main())
