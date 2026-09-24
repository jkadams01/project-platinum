# -*- coding: utf-8 -*-
"""Texture-name -> palette-name pairings harvested from NSBMD MDL0 materials.

An NSBTX/TEX0 bank stores textures and palettes in two SEPARATELY name-sorted
dictionaries and records no mapping between them, so `tools.rom.resolve_palettes`
binds them by name (`<tex>_pl`, then exact, then affix). That is right almost
always - but the model's material section says which palette the game actually
pairs with which texture, and that is ground truth.

On the Platinum map-texture library it changes 6 of the 51 tiles this project
ships, two of them badly: `nsand` decodes to pure white and `nectgr` (the tall
grass) to a grey/orange smear under pure name binding. So `tools/build_tilesets.py`
consults this first and falls back to the name resolver.

Materials block layout (Nitro MDL0):
    +0x00 u16 texToMatDictOff   (relative to the materials block base)
    +0x02 u16 palToMatDictOff
    +0x04 material dictionary
each tex/pal dict entry being {u16 offset_to_matidx_list, u8 count, u8 flag},
the offset again relative to the materials block base.

This belongs in `tools/rom/` once that package settles; it is kept out here for
now so two streams are not editing the same package.
"""
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from tools.rom.nsbtx import read_dict   # noqa: E402

__all__ = ['pairs_from_bmd', 'pairs_from_model', 'model_blocks', 'texpal_from_narcs']


def model_blocks(blob, base):
    """MDL0 at ``base`` -> (names, [absolute model data offsets])."""
    names, data, _unit = read_dict(blob, base + 8)
    offs = []
    for raw in data:
        o = struct.unpack_from('<I', raw, 0)[0]
        offs.append(base + o)
    return names, offs


def pairs_from_model(blob, mbase):
    """-> list of (texname, palname) for one model."""
    matoff = struct.unpack_from('<I', blob, mbase + 0x08)[0]
    mb = mbase + matoff
    tdoff, pdoff = struct.unpack_from('<HH', blob, mb)
    tnames, tdata, _ = read_dict(blob, mb + tdoff)
    pnames, pdata, _ = read_dict(blob, mb + pdoff)
    mat2tex, mat2pal = {}, {}
    for nm, raw in zip(tnames, tdata):
        off, cnt = struct.unpack_from('<HB', raw, 0)
        for k in range(cnt):
            mat2tex[blob[mb + off + k]] = nm
    for nm, raw in zip(pnames, pdata):
        off, cnt = struct.unpack_from('<HB', raw, 0)
        for k in range(cnt):
            mat2pal[blob[mb + off + k]] = nm
    out = []
    for mi, tn in mat2tex.items():
        pn = mat2pal.get(mi)
        if pn is not None:
            out.append((tn, pn))
    return out


def pairs_from_bmd(blob, base=0):
    """BMD0 blob (``base`` = offset of the b'BMD0' magic) -> [(tex, pal), ...]."""
    if blob[base:base + 4] != b'BMD0':
        return []
    nblocks = struct.unpack_from('<H', blob, base + 14)[0]
    out = []
    for i in range(nblocks):
        o = base + struct.unpack_from('<I', blob, base + 16 + 4 * i)[0]
        if blob[o:o + 4] != b'MDL0':
            continue
        try:
            _names, offs = model_blocks(blob, o)
        except Exception:
            continue
        for mo in offs:
            try:
                out.extend(pairs_from_model(blob, mo))
            except Exception:
                pass
    return out


def texpal_from_narcs(rom, narc_keys):
    """Walk model NARCs on an open `tools.rom.Rom` -> {texname: Counter(palname)}."""
    import collections
    m = collections.defaultdict(collections.Counter)
    for key in narc_keys:
        try:
            archive = rom.narc(key)
        except Exception:
            continue
        for i in range(len(archive)):
            e = archive[i]
            k = e.find(b'BMD0')
            if k < 0:
                continue
            for t, p in pairs_from_bmd(e, k):
                m[t][p] += 1
    return m
