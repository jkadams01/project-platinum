# -*- coding: utf-8 -*-
"""Build the outdoor_sinnoh game tileset from the owner's own ROM dumps.

Composition (decided in tools/_work/tilecmp/COMPARISON.md):

    BASE TERRAIN  -> PLATINUM   /fielddata/areadata/area_map_tex/map_tex_set.narc
                                grass, sand, snow, water, the dun_* dungeon kit
    PROPS + EDGES -> WHITE 2    /a/0/1/4  (+ /a/1/7/4 for the doors)
                                gake1_* cliff edge strips, ki02ax/ki03ax trees,
                                fence_01, door_n_*, door_pc, gates, kawa_* river
                                kit, sea_gake01/02 shore pieces
    ROADS         -> HEARTGOLD  /a/0/4/4
                                road01/road05/droad01 + _r/_r2/_sub variants

White 2 is measurably ~12% darker than Platinum (COMPARISON.md section 4: mean
HSV value 0.663 vs 0.750, saturation 0.338 vs 0.378).  Every White 2 tile
therefore gets a fixed +8% value / +4% saturation HSV lift at import - see
HSV_LIFT below - and nothing else does.  The transform lives here so it is
reproducible, every tile records its `source` and `hsvLift` in the manifest so
it stays auditable, and each build prints the before/after means it achieved.

Outputs (all gitignored - ROM-derived):
    assets/generated/tilesets/outdoor_sinnoh.png   packed 16px-cell atlas, 32 cols, PoT
    assets/generated/tilesets/_preview.png         labelled atlas contact sheet
    assets/generated/tilesets/_scene.png           composed scene, final tiles
    data/tilesets/outdoor_sinnoh.json              manifest, DATA_CONTRACT.md section 10
    resources/outdoor_sinnoh.tres                  Godot TileSet (built by tools/build_tileset_res.gd)

Run:  source tools/_work/gen5/env.sh && python tools/build_tilesets.py
"""
from __future__ import print_function

import collections
import json
import os
import subprocess
import sys

import numpy as np
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
sys.path.insert(0, ROOT)

from tools.rom import TEX0, open_rom                 # noqa: E402
from tools.nsbmd_matpair import texpal_from_narcs    # noqa: E402

# --------------------------------------------------------------------------- config
# ROM access goes through tools/rom (the production reader): nicknames resolve
# to the owner's own dumps under References/Roms/, and the NARC keys below are
# that library's named paths - see tools/rom/rom.py PATHS.
SOURCES = {
    'platinum': dict(
        rom='platinum',
        narcs=['map_textures'],          # /fielddata/areadata/area_map_tex/map_tex_set.narc
        # Platinum's NSBMD field models name, per material, the texture AND the
        # palette the game actually pairs. That is ground truth and it beats the
        # name heuristic on 6 of our 51 picks (nsand and nectgr decode to garbage
        # under pure name binding - verified by eye). Consulted first; the name
        # resolver still handles everything the models do not mention.
        models=['land_data', '/fielddata/build_model/build_model.narc'],
        lift=False),
    'white2': dict(
        rom='white2',
        # map_textures (/a/0/1/4) is the field archive: terrain, cliffs, trees,
        # river. The door/gate building textures are NOT in it - they live in
        # exterior_tex (/a/1/7/4); verified, 70/70 entries there carry door_n_0*.
        narcs=['map_textures', 'exterior_tex'],
        lift=True),
    'heartgold': dict(
        rom='heartgold',
        narcs=['map_textures'],          # /a/0/4/4
        lift=False),
}

TILE = 16
COLUMNS = 32

# White 2 -> Platinum tonal correction: a fixed +8% value / +4% saturation lift,
# applied to White 2 pixels ONLY, at import, so it stays reproducible.
#
# MULTIPLICATIVE (v *= 1.08, s *= 1.04) rather than additive, chosen by
# measurement on the tiles that actually ship (printed by every build, and
# recorded under "tonal" in the manifest):
#     platinum target value 0.712
#     white2 raw          0.668
#     white2 x1.08        0.721   <- delta 0.009 from target
#     white2 +0.08        0.744   <- delta 0.032, overshoots into "washed out"
# It is also the literal reading of "+8%". Override with --lift-mode=add to
# reproduce the additive variant.
HSV_LIFT = dict(mode='multiply', value=1.08, saturation=1.04)
HSV_LIFT_ADD = dict(mode='add', value=0.08, saturation=0.04)

# Collision / traversal roles.  Collision codes are DATA_CONTRACT.md section 9:
#   0 walk  1 block  2 ledge  3 deep water  4 tall grass  5 shallow water
#   6 stairs/climb  7 waterfall
ROLES = {
    'ground':        dict(collision=0, encounter=False, traversal=''),
    'tallgrass':     dict(collision=4, encounter=True,  traversal=''),
    'water_deep':    dict(collision=3, encounter=True,  traversal='surf'),
    'water_shallow': dict(collision=5, encounter=False, traversal=''),
    'waterfall':     dict(collision=7, encounter=False, traversal='waterfall'),
    'block':         dict(collision=1, encounter=False, traversal=''),
    'tree':          dict(collision=1, encounter=False, traversal='cut'),
    'rock':          dict(collision=1, encounter=False, traversal='smash'),
    'climb':         dict(collision=6, encounter=False, traversal='climb'),
}

# ------------------------------------------------------------------ the pick list
# (source, texture name, category, role).  Order here is the atlas grouping order.
PICKS = [
    # ---- PLATINUM: base terrain -----------------------------------------
    ('platinum', 'lgreen',      'grass', 'ground'),
    ('platinum', 'lgreenp',     'grass', 'ground'),
    ('platinum', 'ngrass',      'grass', 'ground'),
    ('platinum', 'ngrass02',    'grass', 'ground'),
    ('platinum', 'fenter',      'grass', 'ground'),
    ('platinum', 'hage',        'grass', 'ground'),
    ('platinum', 'nectgr',      'grass', 'tallgrass'),
    ('platinum', 'l_grass_u',   'grass', 'tallgrass'),
    ('platinum', 'l_grass_m',   'grass', 'tallgrass'),
    ('platinum', 'l_grass_d',   'grass', 'tallgrass'),

    ('platinum', 'nsand',       'sand',  'ground'),
    ('platinum', 'nsandp',      'sand',  'ground'),
    ('platinum', 'beach',       'sand',  'ground'),
    ('platinum', 'beachp',      'sand',  'ground'),
    ('platinum', 'hamabe',      'sand',  'ground'),
    ('platinum', 'asahamabe',   'sand',  'ground'),

    ('platinum', 's_snow',      'snow',  'ground'),
    ('platinum', 's_snow02',    'snow',  'ground'),
    ('platinum', 's_snow04',    'snow',  'ground'),

    ('platinum', 'sea',         'water', 'water_deep'),
    ('platinum', 'asasea',      'water', 'water_shallow'),
    ('platinum', 'seaside3',    'water', 'water_shallow'),
    ('platinum', 'seaside2',    'water', 'water_shallow'),
    ('platinum', 'searock',     'water', 'block'),
    ('platinum', 'puddlep',     'water', 'water_shallow'),
    ('platinum', 'blueglay',    'water', 'water_deep'),
    ('platinum', 'blueglayp',   'water', 'water_deep'),
    ('platinum', 'taki',        'water', 'waterfall'),

    # ---- PLATINUM: the dun_* dungeon kit (all names with occurrence >= 2) -
    ('platinum', 'dun_floor',   'cave',  'ground'),
    ('platinum', 'dun_floor2',  'cave',  'ground'),
    ('platinum', 'dun_level',   'cave',  'ground'),
    ('platinum', 'dun_light',   'cave',  'ground'),
    ('platinum', 'dun_sside',   'cave',  'ground'),
    ('platinum', 'dun_imped',   'cave',  'block'),
    ('platinum', 'dun_wall_n',  'cave',  'block'),
    ('platinum', 'dun_wall_s',  'cave',  'block'),
    ('platinum', 'dun_wall_e',  'cave',  'block'),
    ('platinum', 'dun_wall_w',  'cave',  'block'),
    ('platinum', 'dun_wall_c',  'cave',  'block'),
    ('platinum', 'dun_dansou',  'cave',  'block'),
    ('platinum', 'dun_hanger',  'cave',  'block'),
    ('platinum', 'dun_dhole',   'cave',  'block'),
    ('platinum', 'dun_dhole2',  'cave',  'block'),
    ('platinum', 'dun_ent',     'cave',  'ground'),
    ('platinum', 'dun_ent2',    'cave',  'ground'),
    ('platinum', 'dun_down',    'cave',  'climb'),
    ('platinum', 'dun_slope',   'cave',  'climb'),
    ('platinum', 'dun_step',    'cave',  'climb'),
    ('platinum', 'dun_jump',    'cave',  'ground'),
    ('platinum', 'dun_allpeak', 'cliff', 'block'),
    ('platinum', 'dun_sea',     'water', 'water_deep'),

    # ---- WHITE 2: cliff edge strips --------------------------------------
    ('white2', 'gake1_0',   'cliff', 'block'),
    ('white2', 'gake1_1',   'cliff', 'block'),
    ('white2', 'gake1_2',   'cliff', 'block'),
    ('white2', 'gake1_3',   'cliff', 'block'),
    ('white2', 'gake1_s0',  'cliff', 'block'),
    ('white2', 'gake1_b',   'cliff', 'block'),
    ('white2', 'gake01a',   'cliff', 'block'),
    ('white2', 'dansa01a',  'cliff', 'climb'),

    # ---- WHITE 2: trees (32x64, with trunks - stamp-ready) ---------------
    ('white2', 'ki02ax',    'tree',  'tree'),
    ('white2', 'ki03ax',    'tree',  'tree'),

    # ---- WHITE 2: props --------------------------------------------------
    ('white2', 'fence_01',  'building', 'block'),
    ('white2', 'door_n_01', 'building', 'block'),
    ('white2', 'door_n_02', 'building', 'block'),
    ('white2', 'door_n_03', 'building', 'block'),
    ('white2', 'door_pc',   'building', 'block'),
    ('white2', 'gate_1',    'building', 'block'),
    ('white2', 'gate_4',    'building', 'block'),

    # ---- WHITE 2: river kit + shore --------------------------------------
    ('white2', 'kawa01a',      'water', 'water_shallow'),
    ('white2', 'kawa01b',      'water', 'water_shallow'),
    ('white2', 'kawa_fuchi.1', 'water', 'water_shallow'),
    ('white2', 'kawa_kage',    'water', 'water_shallow'),
    ('white2', 'kawa_nose.1',  'water', 'water_shallow'),
    ('white2', 'kawa_soko',    'water', 'water_deep'),
    ('white2', 'kawasoko_isi', 'water', 'water_deep'),
    ('white2', 'sea_gake01',   'water', 'block'),
    ('white2', 'sea_gake02',   'water', 'block'),

    # ---- HEARTGOLD: roads ------------------------------------------------
    ('heartgold', 'road01',        'path', 'ground'),
    ('heartgold', 'road01_r',      'path', 'ground'),
    ('heartgold', 'road01_sub',    'path', 'ground'),
    ('heartgold', 'road05',        'path', 'ground'),
    ('heartgold', 'road05_r',      'path', 'ground'),
    ('heartgold', 'road05_sub',    'path', 'ground'),
    ('heartgold', 'droad01',       'path', 'ground'),
    ('heartgold', 'droad01_y',     'path', 'ground'),
    ('heartgold', 'droad01_r',     'path', 'ground'),
    ('heartgold', 'droad01_r2',    'path', 'ground'),
    ('heartgold', 'droad01_sub',   'path', 'ground'),
    ('heartgold', 'droad01_sub2',  'path', 'ground'),
]

SOURCE_COLOUR = {'platinum': (255, 190, 70), 'white2': (120, 200, 255),
                 'heartgold': (255, 120, 190)}


# ------------------------------------------------------------------- HSV lift
def rgb_to_hsv(rgb):
    """rgb float32 (...,3) in 0..1 -> h 0..1, s 0..1, v 0..1."""
    mx = rgb.max(-1)
    mn = rgb.min(-1)
    d = mx - mn
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    dd = np.maximum(d, 1e-12)
    h = np.where(d < 1e-12, 0.0,
                 np.where(mx == r, ((g - b) / dd) % 6.0,
                          np.where(mx == g, (b - r) / dd + 2.0, (r - g) / dd + 4.0))) / 6.0
    s = np.where(mx > 1e-12, d / np.maximum(mx, 1e-12), 0.0)
    return h, s, mx


def hsv_to_rgb(h, s, v):
    i = np.floor(h * 6.0)
    f = h * 6.0 - i
    p = v * (1.0 - s)
    q = v * (1.0 - f * s)
    t = v * (1.0 - (1.0 - f) * s)
    i = (i.astype(np.int32) % 6)
    r = np.choose(i, [v, q, p, p, t, v])
    g = np.choose(i, [t, v, v, q, p, p])
    b = np.choose(i, [p, p, t, v, v, q])
    return np.stack([r, g, b], -1)


def hsv_lift(arr, lift):
    """Lift an RGBA uint8 array's value/saturation. Alpha untouched.

    `lift` is HSV_LIFT / HSV_LIFT_ADD: mode 'multiply' scales, mode 'add'
    offsets.  Only pixels with alpha > 0 are touched, so fully transparent
    padding does not pick up a colour.
    """
    out = arr.copy()
    mask = arr[..., 3] > 0
    if not mask.any():
        return out
    rgb = arr[..., :3].astype(np.float32)[mask] / 255.0
    h, s, v = rgb_to_hsv(rgb)
    if lift['mode'] == 'multiply':
        s = np.clip(s * lift['saturation'], 0.0, 1.0)
        v = np.clip(v * lift['value'], 0.0, 1.0)
    else:
        s = np.clip(s + lift['saturation'], 0.0, 1.0)
        v = np.clip(v + lift['value'], 0.0, 1.0)
    lifted = np.clip(hsv_to_rgb(h, s, v) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    rgb_plane = out[..., :3]
    rgb_plane[mask] = lifted
    out[..., :3] = rgb_plane
    return out


def mean_hsv(arrays):
    """Mean saturation / value over the opaque pixels of a list of RGBA arrays."""
    ss, vv, n = 0.0, 0.0, 0
    for a in arrays:
        m = a[..., 3] > 0
        if not m.any():
            continue
        rgb = a[..., :3].astype(np.float32)[m] / 255.0
        _, s, v = rgb_to_hsv(rgb)
        ss += float(s.sum())
        vv += float(v.sum())
        n += int(m.sum())
    if n == 0:
        return 0.0, 0.0
    return ss / n, vv / n


# ---------------------------------------------------------------- extraction
def bind_palettes(t, texpal, stats):
    """Palette index per texture slot.  Model-material pairing first (ground
    truth), then TEX0.pal_index - which tools/rom binds BY NAME via
    resolve_palettes() - for whatever the models never mention.  Index binding
    is never used as a first-class strategy."""
    byname = list(t.pal_index)
    for k, v in t.pal_stats.items():
        stats[k] += v
    if not texpal:
        return byname
    pidx = {}
    for k, pn in enumerate(t.pal_names):
        pidx.setdefault(pn, k)
    out = list(byname)
    for j, tn in enumerate(t.tex_names):
        for pn, _n in texpal.get(tn, collections.Counter()).most_common():
            if pn in pidx:
                out[j] = pidx[pn]
                # pal_by_model supersedes whatever the name resolver said for
                # this slot; the name counters are left alone so they keep
                # reporting how far the name heuristic reached on its own.
                stats['pal_by_model'] += 1
                break
    return out


def extract(source_key, wanted):
    """-> {name: {arr, narc, occurrences}}.  Picks, per name, the pixel variant
    that occurs most often across the archive - that is the canonical
    seasonal/area variant.  Palettes are bound by MODEL MATERIAL where the
    models say, otherwise BY NAME.  Never by index."""
    cfg = SOURCES[source_key]
    rom = open_rom(cfg['rom'])
    variants = collections.defaultdict(collections.Counter)   # name -> Counter(key)
    blobs = {}                                                # key -> (array, narcpath)
    stats = collections.Counter()
    fails = collections.Counter()
    texpal = texpal_from_narcs(rom, cfg.get('models', []))
    for narckey in cfg['narcs']:
        narcpath = rom.resolve(narckey)
        narc = rom.narc(narckey)
        for ei in range(len(narc)):
            eb = narc[ei]
            if len(eb) < 16:
                continue
            try:
                t = TEX0(eb)
            except Exception:
                fails['entry_no_tex0'] += 1
                continue
            if not (wanted & set(t.tex_names)):
                continue
            palidx = bind_palettes(t, texpal, stats)
            for i, tn in enumerate(t.tex_names):
                if tn not in wanted:
                    continue
                try:
                    a = t.decode(i, palidx[i])
                except Exception:
                    fails['decode_error'] += 1
                    continue
                key = (tn, a.shape, a.tobytes())
                variants[tn][key] += 1
                blobs[key] = (a, narcpath)
    out = {}
    for name, counter in variants.items():
        key, occ = counter.most_common(1)[0]
        arr, narcpath = blobs[key]
        out[name] = dict(arr=arr, narc=narcpath, occurrences=occ)
    print('  %-10s %d/%d names, palette binding %s, fails %s'
          % (source_key, len(out), len(wanted), dict(stats), dict(fails) or '{}'))
    return out


# ------------------------------------------------------------------- packing
class ShelfPacker(object):
    def __init__(self, columns):
        self.columns = columns
        self.shelves = []       # [x_cursor, y, height]
        self.rows = 0

    def place(self, w, h):
        # First-fit on any shelf at least this tall. Measured against exact-height
        # matching on this pick list: 10 rows vs 12, so first-fit wins here.
        for sh in self.shelves:
            if sh[2] >= h and sh[0] + w <= self.columns:
                x, y = sh[0], sh[1]
                sh[0] += w
                return x, y
        if w > self.columns:
            raise ValueError('block wider than the atlas: %d cells' % w)
        y = self.rows
        self.shelves.append([w, y, h])
        self.rows += h
        return 0, y


# ---------------------------------------------------------------------- build
def build(lift):
    wanted = collections.defaultdict(set)
    for src, name, _cat, _role in PICKS:
        wanted[src].add(name)

    print('extracting from ROMs (palette binding by name):')
    tex = {}
    for src in ('platinum', 'white2', 'heartgold'):
        tex[src] = extract(src, wanted[src])

    missing = [(s, n) for s, n, _c, _r in PICKS if n not in tex[s]]
    if missing:
        print('  MISSING: %s' % missing)

    # tonal measurement before / after, on the pixels that actually ship
    def arrays(src):
        return [tex[src][n]['arr'] for s, n, _c, _r in PICKS
                if s == src and n in tex[src]]

    ps, pv = mean_hsv(arrays('platinum'))
    ws, wv = mean_hsv(arrays('white2'))
    hs, hv = mean_hsv(arrays('heartgold'))

    # apply the lift to White 2 only
    for n in list(tex['white2']):
        tex['white2'][n]['arr'] = hsv_lift(tex['white2'][n]['arr'], lift)
    ls, lv = mean_hsv(arrays('white2'))

    tonal = dict(
        platinum=dict(saturation=round(ps, 3), value=round(pv, 3)),
        heartgold=dict(saturation=round(hs, 3), value=round(hv, 3)),
        white2_raw=dict(saturation=round(ws, 3), value=round(wv, 3)),
        white2_lifted=dict(saturation=round(ls, 3), value=round(lv, 3)),
        lift=lift)
    print('')
    print('tonal check (mean HSV over the shipped pixels):')
    print('  platinum       sat %.3f  val %.3f   <- target' % (ps, pv))
    print('  heartgold      sat %.3f  val %.3f' % (hs, hv))
    print('  white2 raw     sat %.3f  val %.3f' % (ws, wv))
    print('  white2 lifted  sat %.3f  val %.3f   (%s V %.2f / S %.2f)'
          % (ls, lv, lift['mode'], lift['value'], lift['saturation']))

    # ---- pack -----------------------------------------------------------
    blocks = []
    for src, name, cat, role in PICKS:
        rec = tex[src].get(name)
        if rec is None:
            continue
        a = rec['arr']
        h, w = a.shape[0], a.shape[1]
        cw = max(1, (w + TILE - 1) // TILE)
        ch = max(1, (h + TILE - 1) // TILE)
        blocks.append(dict(src=src, name=name, cat=cat, role=role, arr=a,
                           narc=rec['narc'], occurrences=rec['occurrences'],
                           w=w, h=h, cw=cw, ch=ch))
    order = sorted(range(len(blocks)), key=lambda i: (-blocks[i]['ch'], -blocks[i]['cw'], i))
    packer = ShelfPacker(COLUMNS)
    for i in order:
        b = blocks[i]
        b['cx'], b['cy'] = packer.place(b['cw'], b['ch'])

    rows = packer.rows
    width = COLUMNS * TILE
    height = 1
    while height < rows * TILE:
        height *= 2
    print('')
    print('packed %d textures into %d cells over %d rows -> atlas %dx%d (PoT)'
          % (len(blocks), sum(b['cw'] * b['ch'] for b in blocks), rows, width, height))

    atlas = np.zeros((height, width, 4), np.uint8)
    tiles = []
    for b in sorted(blocks, key=lambda b: (b['cy'], b['cx'])):
        px, py = b['cx'] * TILE, b['cy'] * TILE
        atlas[py:py + b['h'], px:px + b['w']] = b['arr']
        role = ROLES[b['role']]
        for sy in range(b['ch']):
            for sx in range(b['cw']):
                cx, cy = b['cx'] + sx, b['cy'] + sy
                cell = b['arr'][sy * TILE:(sy + 1) * TILE, sx * TILE:(sx + 1) * TILE]
                if cell.size == 0 or not (cell[..., 3] > 0).any():
                    continue            # padding cell of a non-multiple-of-16 texture
                tiles.append(dict(
                    index=cy * COLUMNS + cx, atlasX=cx, atlasY=cy,
                    source=b['src'], texture=b['name'], category=b['cat'],
                    role=b['role'], collision=role['collision'],
                    encounter=role['encounter'], traversal=role['traversal'],
                    srcNarc=b['narc'], srcW=b['w'], srcH=b['h'],
                    cellsW=b['cw'], cellsH=b['ch'], subX=sx, subY=sy,
                    hsvLift=(b['src'] == 'white2')))

    outdir = os.path.join(ROOT, 'assets', 'generated', 'tilesets')
    if not os.path.isdir(outdir):
        os.makedirs(outdir)
    atlas_path = os.path.join(outdir, 'outdoor_sinnoh.png')
    Image.fromarray(atlas, 'RGBA').save(atlas_path)

    datadir = os.path.join(ROOT, 'data', 'tilesets')
    if not os.path.isdir(datadir):
        os.makedirs(datadir)
    manifest = dict(
        name='outdoor_sinnoh', tileSize=TILE,
        atlas='assets/generated/tilesets/outdoor_sinnoh.png',
        columns=COLUMNS, rows=height // TILE, tileCount=len(tiles),
        sources=dict((k, dict(rom=SOURCES[k]['rom'],
                              narcs=[open_rom(SOURCES[k]['rom']).resolve(n)
                                     for n in SOURCES[k]['narcs']],
                              hsvLift=SOURCES[k]['lift'])) for k in SOURCES),
        hsvLift=lift, tonal=tonal,
        customDataLayers=[dict(name='collision', type='int'),
                          dict(name='encounter', type='bool'),
                          dict(name='traversal', type='String')],
        tiles=tiles)
    mpath = os.path.join(datadir, 'outdoor_sinnoh.json')
    with open(mpath, 'w') as f:
        json.dump(manifest, f, indent=1)

    by_src = collections.Counter(t['source'] for t in tiles)
    print('wrote %s  (%d tiles: %s)' % (atlas_path, len(tiles), dict(by_src)))
    print('wrote %s' % mpath)
    return blocks, atlas, tiles, manifest


# ----------------------------------------------------------------- previews
def render_preview(atlas, blocks, path, scale=3):
    ah, aw = atlas.shape[0], atlas.shape[1]
    pad, legend = 8, 54
    img = Image.new('RGBA', (aw * scale + pad * 2, ah * scale + pad * 2 + legend),
                    (26, 28, 32, 255))
    d = ImageDraw.Draw(img)
    # checkerboard behind the atlas so transparent padding is obvious
    for y in range(0, ah * scale, 16):
        for x in range(0, aw * scale, 16):
            if ((x // 16) + (y // 16)) % 2:
                d.rectangle([pad + x, pad + y, pad + x + 15, pad + y + 15],
                            fill=(44, 46, 52, 255))
    up = Image.fromarray(atlas, 'RGBA').resize((aw * scale, ah * scale), Image.NEAREST)
    img.alpha_composite(up, (pad, pad))
    # grid
    for cx in range(0, aw // TILE + 1):
        x = pad + cx * TILE * scale
        d.line([x, pad, x, pad + ah * scale], fill=(70, 74, 82, 160))
    for cy in range(0, ah // TILE + 1):
        y = pad + cy * TILE * scale
        d.line([pad, y, pad + aw * scale, y], fill=(70, 74, 82, 160))
    # per-texture outline in its source colour + name
    for b in blocks:
        c = SOURCE_COLOUR[b['src']]
        x0 = pad + b['cx'] * TILE * scale
        y0 = pad + b['cy'] * TILE * scale
        x1 = x0 + b['cw'] * TILE * scale - 1
        y1 = y0 + b['ch'] * TILE * scale - 1
        d.rectangle([x0, y0, x1, y1], outline=c + (255,))
        d.text((x0 + 2, y0 + 1), b['name'][:12], fill=(0, 0, 0, 255))
        d.text((x0 + 1, y0), b['name'][:12], fill=c + (255,))
    y = pad + ah * scale + 10
    d.text((pad, y), 'outdoor_sinnoh atlas  %dx%d px  %d cols x %d rows @ %dpx  (3x, nearest)'
           % (aw, ah, aw // TILE, ah // TILE, TILE), fill=(220, 220, 225, 255))
    x = pad
    for k in ('platinum', 'white2', 'heartgold'):
        d.rectangle([x, y + 18, x + 12, y + 30], fill=SOURCE_COLOUR[k] + (255,))
        lbl = k + (' (HSV lift)' if SOURCES[k]['lift'] else '')
        d.text((x + 18, y + 19), lbl, fill=(220, 220, 225, 255))
        x += 22 + 8 * len(lbl)
    img.convert('RGB').save(path)
    print('wrote %s' % path)


SCENE_W, SCENE_H = 26, 18


def render_scene(blocks, path, lift, scale=4):
    """A small composed scene from the FINAL post-lift tiles:
    Platinum grass + sand, HeartGold road, White 2 cliff edge, trees, river."""
    by = {}
    for b in blocks:
        by[b['name']] = b

    def cell(name, sx=0, sy=0):
        b = by.get(name)
        if b is None:
            raise KeyError('scene asks for a texture that is not in the atlas: %r' % name)
        if sx >= b['cw'] or sy >= b['ch']:
            raise IndexError('%s is %dx%d cells; asked for sub-cell (%d,%d)'
                             % (name, b['cw'], b['ch'], sx, sy))
        a = b['arr'][sy * TILE:(sy + 1) * TILE, sx * TILE:(sx + 1) * TILE]
        if a.shape[0] != TILE or a.shape[1] != TILE:
            padded = np.zeros((TILE, TILE, 4), np.uint8)
            padded[:a.shape[0], :a.shape[1]] = a
            a = padded
        return a

    scene = np.zeros((SCENE_H * TILE, SCENE_W * TILE, 4), np.uint8)

    def blit(a, cx, cy):
        if a is None:
            return
        x, y = cx * TILE, cy * TILE
        if x < 0 or y < 0 or x + TILE > scene.shape[1] or y + TILE > scene.shape[0]:
            return
        dst = scene[y:y + TILE, x:x + TILE]
        al = a[..., 3:4].astype(np.float32) / 255.0
        dst[..., :3] = (a[..., :3] * al + dst[..., :3] * (1 - al)).astype(np.uint8)
        dst[..., 3] = np.maximum(dst[..., 3], a[..., 3])

    # 1. ground: Platinum grass everywhere (lgreenp is 32x32 -> 2x2 cells)
    for cy in range(SCENE_H):
        for cx in range(SCENE_W):
            blit(cell('lgreenp', cx % 2, cy % 2), cx, cy)

    # 2. a cliff bank across the top, entirely from the White 2 edge kit:
    #    gake1_2 top lip -> gake01a face -> gake1_0 bottom lip.
    #    gake1_* are 16x8 strips: they occupy the TOP half of their cell, which
    #    is how the 3D games use them (a lip drawn over the tile below).
    for cx in range(SCENE_W):
        blit(cell('gake1_2'), cx, 2)
        blit(cell('gake01a'), cx, 3)
        blit(cell('gake01a'), cx, 4)
        blit(cell('gake1_0'), cx, 5)

    # 3. a HeartGold road running left-to-right (road01 is 32x32 -> 2x2)
    road_y = 9
    for cx in range(SCENE_W):
        for k in range(2):
            blit(cell('road01', cx % 2, k), cx, road_y + k)
        blit(cell('road01_sub'), cx, road_y - 1)     # HG shoulder strips
        blit(cell('road01_sub'), cx, road_y + 2)

    # 4. Platinum water: a pond bottom-left with a Platinum beach sand shore
    for cy in range(13, SCENE_H):
        for cx in range(0, 7):
            blit(cell('sea'), cx, cy)
    for cx in range(0, 8):
        blit(cell('seaside3'), cx, 12)
    for cy in range(12, SCENE_H):
        blit(cell('seaside3'), 7, cy)
    for cy in range(12, SCENE_H):
        for cx in range(8, 11):
            blit(cell('beachp', cx % 2, cy % 2), cx, cy)

    # 5. White 2 river kit: a short stream running down from the cliff
    for cy in range(6, 9):
        blit(cell('kawa_soko'), 23, cy)
        blit(cell('kawa_soko'), 24, cy)
        blit(cell('kawa01b'), 22, cy)
        blit(cell('kawa01b'), 25, cy)
    blit(cell('kawa_fuchi.1'), 23, 6)
    blit(cell('kawa_fuchi.1'), 24, 6)

    # 6. White 2 trees (32x64 -> 2x4 cells) standing on the Platinum grass
    for tx, ty, nm in ((3, 6, 'ki02ax'), (9, 5, 'ki03ax'), (15, 6, 'ki02ax')):
        for sy in range(4):
            for sx in range(2):
                blit(cell(nm, sx, sy), tx + sx, ty + sy)

    # 7. Platinum tall grass patch (nectgr) - the encounter tile
    for cy in (12, 13):
        for cx in range(12, 17):
            blit(cell('nectgr'), cx, cy)

    # 8. White 2 props: a fence run and a door
    for cx in range(18, 23):
        blit(cell('fence_01', 0, 0), cx, 13)
        blit(cell('fence_01', 0, 1), cx, 14)
    for sy in range(2):
        for sx in range(2):
            blit(cell('door_n_01', sx, sy), 19 + sx, 6 + sy)

    img = Image.fromarray(scene, 'RGBA').convert('RGB')
    img = img.resize((SCENE_W * TILE * scale, SCENE_H * TILE * scale), Image.NEAREST)
    d = ImageDraw.Draw(img)
    d.text((6, 6), 'FINAL tiles: Platinum ground/grass/sand + HeartGold road + '
                   'White 2 cliff/tree/fence/river/door  (W2 post %s lift V %.2f S %.2f)'
           % (lift['mode'], lift['value'], lift['saturation']), fill=(255, 255, 255))
    img.save(path)
    print('wrote %s' % path)


# ------------------------------------------------------------------- godot
GODOT = 'C:/Users/James/Documents/GitHub/Godot_v4.7.2-stable_win64_console.exe'


def _run(cmd, timeout=600):
    """subprocess.call with a timeout. Returns the exit code, or None on timeout."""
    p = subprocess.Popen(cmd)
    try:
        return p.wait(timeout=timeout)
    except subprocess.TimeoutExpired:
        p.kill()
        p.wait()
        return None


def build_godot_resource():
    script = 'res://tools/build_tileset_res.gd'
    print('')
    print('--- godot --import ---')
    rc = _run([GODOT, '--headless', '--path', ROOT, '--import'], timeout=900)
    print('import rc=%s' % rc)
    if rc is None:
        print('    (--import did not return in time. It scans the whole project and'
              ' contends with any other Godot instance open on it; the codegen below'
              ' only needs assets/generated/tilesets/outdoor_sinnoh.png to have been'
              ' imported at least once.)')
    print('--- godot tileset codegen ---')
    rc = _run([GODOT, '--headless', '--path', ROOT, '--script', script])
    print('codegen rc=%d' % rc)
    return rc


def main():
    lift = HSV_LIFT
    suffix = ''
    for a in sys.argv[1:]:
        if a == '--lift-mode=add':
            lift, suffix = HSV_LIFT_ADD, '_add'
        elif a == '--lift-mode=none':
            lift = dict(mode='multiply', value=1.0, saturation=1.0)
            suffix = '_nolift'
    blocks, atlas, tiles, manifest = build(lift)
    outdir = os.path.join(ROOT, 'assets', 'generated', 'tilesets')
    render_preview(atlas, blocks, os.path.join(outdir, '_preview%s.png' % suffix))
    render_scene(blocks, os.path.join(outdir, '_scene%s.png' % suffix), lift)
    if '--no-godot' not in sys.argv:
        rc = build_godot_resource()
        if rc != 0:
            return rc
    return 0


if __name__ == '__main__':
    sys.exit(main())
