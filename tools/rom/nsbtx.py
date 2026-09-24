# -*- coding: utf-8 -*-
"""NSBTX / BMD0 ``TEX0`` texture banks -> RGBA, with NAME-BASED palette binding.

A ``BTX0`` file (or the ``TEX0`` block inside a ``BMD0`` model) holds two Nitro
3D info dictionaries: one of textures and one of palettes. Each dictionary is
sorted by name **independently**, so:

    **palette index != texture index.** Binding by index is the single most
    expensive bug in this format.

Concretely, White 2 ``/a/0/1/4`` entry 0 has 76 textures and 76 palettes.
Texture 3 is ``gake01a``; palette 3 is ``gake01a2_pl``. The palette ``gake01a``
actually wants is index 4, ``gake01a_pl``. Binding by index tints the cliff with
the neighbouring cliff variant's colours - it *decodes*, it just looks subtly
wrong, which is why it survives a "the script exited 0" check.

:func:`resolve_palettes` binds by name with a four-pass fallback chain, and
:meth:`TEX0.decode` uses it by default. Passing an explicit ``pal_index`` is
still allowed, for tooling that wants to demonstrate the wrong answer.

Texture formats (texImageParam bits 26-28):

    0 none   1 A3I5    2 PAL4    3 PAL16
    4 PAL256 5 CMP4x4  6 A5I3    7 DIRECT (RGB555 + 1-bit alpha)
"""

import struct

__all__ = ['TEX0Error', 'TEX0', 'read_dict', 'resolve_palettes', 'FMT_NAME']

FMT_NAME = {0: 'none', 1: 'A3I5', 2: 'PAL4', 3: 'PAL16', 4: 'PAL256',
            5: 'CMP4x4', 6: 'A5I3', 7: 'DIRECT'}

_NCOLORS = {2: 4, 3: 16, 4: 256}
_BITS = {2: 2, 3: 4, 4: 8}


class TEX0Error(ValueError):
    """Raised when a blob holds no usable TEX0 block."""


def read_dict(d, off):
    """Nitro 3D info dictionary -> (names, [raw entry bytes], size_unit).

    Layout::

        u8  dummy;  u8 numObjs;  u16 sectionSize
        u16 unkSize; u16 unkSectionSize; u32 constant; numObjs * u32 unknown
        u16 sizeUnit; u16 offsetToNames
        numObjs * sizeUnit  entry data
        numObjs * 16        NUL-padded ASCII names
    """
    n = d[off + 1]
    p = off + 4
    p += 2                       # unknown block size
    p += 2                       # unknown section size
    p += 4 * (n + 1)             # constant + one u32 per entry
    sizeunit, _offname = struct.unpack_from('<HH', d, p)
    p += 4
    datap = p
    data = [bytes(d[datap + i * sizeunit: datap + (i + 1) * sizeunit]) for i in range(n)]
    namep = datap + n * sizeunit
    names = []
    for i in range(n):
        raw = bytes(d[namep + i * 16: namep + i * 16 + 16])
        names.append(raw.split(b'\x00')[0].decode('ascii', 'replace').strip())
    return names, data, sizeunit


def resolve_palettes(tex_names, pal_names, stats=None):
    """Texture index -> palette index, bound by NAME.

    The convention is ``<tex>_pl``, but there are real exceptions in these
    archives (``h04_stair`` -> ``stair``; ``warp01/02/03`` -> ``gtswarp_r/b/g``),
    so resolve in four passes:

      1. exact ``<tex>_pl``
      2. exact ``<tex>``
      3. longest affix match against an unclaimed palette's stem
      4. leftovers handed out in order; only then fall back to the index

    ``stats`` may be a ``collections.Counter`` to record which pass fired.
    Returns a list of palette indices, one per texture (``None`` only when
    there are no palettes at all).
    """
    if stats is None:
        stats = {}

    def bump(k):
        stats[k] = stats.get(k, 0) + 1

    pal_by_name = {}
    for k, pn in enumerate(pal_names):
        pal_by_name.setdefault(pn, k)
    npal = len(pal_names)
    out = [None] * len(tex_names)
    if npal == 0:
        return out
    taken = set()
    for i, tn in enumerate(tex_names):                     # 1. '<tex>_pl'  2. '<tex>'
        k = pal_by_name.get(tn + '_pl')
        if k is None:
            k = pal_by_name.get(tn)
        if k is not None:
            out[i] = k
            taken.add(k)
            bump('pal_by_name')
    free = [k for k in range(npal) if k not in taken]
    for i, tn in enumerate(tex_names):                     # 3. longest affix match
        if out[i] is not None:
            continue
        best, bl = None, 0
        for k in free:
            pn = pal_names[k]
            stem = pn[:-3] if pn.endswith('_pl') else pn
            if stem and (tn.endswith(stem) or tn.startswith(stem)) and len(stem) > bl:
                best, bl = k, len(stem)
        if best is not None:
            out[i] = best
            free.remove(best)
            bump('pal_by_affix')
    rest = [i for i in range(len(out)) if out[i] is None]   # 4. leftovers, in order
    for n, i in enumerate(rest):
        if n < len(free):
            out[i] = free[n]
            bump('pal_by_leftover')
        else:
            out[i] = min(i, npal - 1)
            bump('pal_by_index_guess')
    return out


class TEX0(object):
    """A TEX0 texture bank.

    Attributes:
        tex_names, pal_names   parallel to the two info dictionaries
        pal_index              texture index -> palette index, bound BY NAME
    """

    def __init__(self, blob):
        blob = bytes(blob)
        if len(blob) < 20:
            raise TEX0Error('blob is %d bytes - too short for a Nitro 3D container'
                            % len(blob))
        magic = blob[:4]
        if magic == b'BTX0':
            _hdrsize, _nblocks = struct.unpack_from('<HH', blob, 12)
            off = struct.unpack_from('<I', blob, 16)[0]
            if blob[off:off + 4] != b'TEX0':
                raise TEX0Error('BTX0 block 0 is %r, not TEX0' % blob[off:off + 4])
        elif magic == b'BMD0':
            _hdrsize, nblocks = struct.unpack_from('<HH', blob, 12)
            off = None
            for i in range(nblocks):
                o = struct.unpack_from('<I', blob, 16 + 4 * i)[0]
                if 0 < o < len(blob) - 4 and blob[o:o + 4] == b'TEX0':
                    off = o
                    break
            if off is None:
                raise TEX0Error('no TEX0 block in this BMD0')
        else:
            raise TEX0Error('not BTX0/BMD0: magic %r' % magic)

        self.d = blob
        self.base = b = off
        d = blob
        self.texdatasize = struct.unpack_from('<H', d, b + 0x0C)[0] << 3
        self.texinfo_off = struct.unpack_from('<H', d, b + 0x0E)[0]
        self.texdata_off = struct.unpack_from('<I', d, b + 0x14)[0]
        self.cmpdatasize = struct.unpack_from('<H', d, b + 0x1C)[0] << 3
        self.cmpinfo_off = struct.unpack_from('<H', d, b + 0x1E)[0]
        self.cmpdata_off = struct.unpack_from('<I', d, b + 0x24)[0]
        self.cmpinfodata_off = struct.unpack_from('<I', d, b + 0x28)[0]
        self.paldatasize = struct.unpack_from('<I', d, b + 0x30)[0] << 3
        self.palinfo_off = struct.unpack_from('<I', d, b + 0x34)[0]
        self.paldata_off = struct.unpack_from('<I', d, b + 0x38)[0]
        self.tex_names, self.tex_data, _ = read_dict(d, b + self.texinfo_off)
        self.pal_names, self.pal_data, _ = read_dict(d, b + self.palinfo_off)
        self.pal_stats = {}
        self.pal_index = resolve_palettes(self.tex_names, self.pal_names, self.pal_stats)
        self._pal_cache = {}

    def __len__(self):
        return len(self.tex_names)

    def __repr__(self):
        return '<TEX0 %d textures, %d palettes>' % (len(self.tex_names), len(self.pal_names))

    # -- lookup ------------------------------------------------------------
    def index_of(self, name):
        try:
            return self.tex_names.index(name)
        except ValueError:
            raise KeyError('no texture named %r in this TEX0' % name)

    def palette_index_for(self, tex):
        """Palette index bound to texture ``tex`` (index or name), BY NAME."""
        i = tex if isinstance(tex, int) else self.index_of(tex)
        return self.pal_index[i]

    def palette_name_for(self, tex):
        k = self.palette_index_for(tex)
        return None if k is None else self.pal_names[k]

    # -- raw fields --------------------------------------------------------
    def tex_param(self, i):
        """-> dict(vram, w, h, fmt, fmtname, col0) from texImageParam."""
        raw = self.tex_data[i]
        off, param = struct.unpack_from('<HH', raw, 0)
        p = (param << 16) | off
        return dict(vram=(p & 0xFFFF) << 3,
                    w=8 << ((p >> 20) & 7),
                    h=8 << ((p >> 23) & 7),
                    fmt=(p >> 26) & 7,
                    fmtname=FMT_NAME[(p >> 26) & 7],
                    col0=(p >> 29) & 1)

    def pal_offset(self, i):
        off, _flag = struct.unpack_from('<HH', self.pal_data[i], 0)
        return off << 3

    def palette(self, i, ncolors=None):
        """Palette ``i`` as a list of (r, g, b). ``ncolors=None`` reads to the end."""
        key = (i, ncolors)
        if key in self._pal_cache:
            return self._pal_cache[key]
        o = self.base + self.paldata_off + self.pal_offset(i)
        end = min(self.base + self.paldata_off + self.paldatasize, len(self.d))
        if ncolors is not None:
            end = min(end, o + ncolors * 2)
        raw = self.d[o:end]
        n = len(raw) // 2
        cols = [((v & 31) * 255 // 31, ((v >> 5) & 31) * 255 // 31,
                 ((v >> 10) & 31) * 255 // 31)
                for v in struct.unpack_from('<%dH' % n, raw, 0)] if n else []
        self._pal_cache[key] = cols
        return cols

    # -- decoding ----------------------------------------------------------
    def decode(self, tex, pal_index=None):
        """Decode texture ``tex`` (index or name) to an (h, w, 4) uint8 ndarray.

        ``pal_index`` defaults to the NAME-bound palette. Only pass it
        explicitly when you deliberately want a different palette.
        """
        import numpy as np
        i = tex if isinstance(tex, int) else self.index_of(tex)
        if pal_index is None:
            pal_index = self.pal_index[i]
        p = self.tex_param(i)
        w, h, fmt = p['w'], p['h'], p['fmt']
        if w == 0 or h == 0:
            raise TEX0Error('texture %r has a zero dimension' % self.tex_names[i])
        if fmt == 0:
            raise TEX0Error('texture %r has format "none"' % self.tex_names[i])
        if pal_index is None and fmt != 7:
            raise TEX0Error('texture %r needs a palette and this TEX0 has none'
                            % self.tex_names[i])
        n = w * h

        if fmt == 5:
            return self._decode_cmp(i, p, self.palette(pal_index))

        if fmt == 7:                                    # DIRECT: RGB555 + alpha bit
            base = self.base + self.texdata_off + p['vram']
            raw = self.d[base:base + n * 2]
            if len(raw) < n * 2:
                raise TEX0Error('texture %r: texdata truncated' % self.tex_names[i])
            v = np.frombuffer(raw, '<u2')
            out = np.stack([(v & 31) * 255 // 31, ((v >> 5) & 31) * 255 // 31,
                            ((v >> 10) & 31) * 255 // 31,
                            np.where((v >> 15) & 1, 255, 0)], 1).astype(np.uint8)
            return out.reshape(h, w, 4)

        base = self.base + self.texdata_off + p['vram']

        if fmt in (2, 3, 4):                            # PAL4 / PAL16 / PAL256
            bits = _BITS[fmt]
            nbytes = n * bits // 8
            raw = self.d[base:base + nbytes]
            if len(raw) < nbytes:
                raise TEX0Error('texture %r: texdata truncated (%d < %d)'
                                % (self.tex_names[i], len(raw), nbytes))
            arr = np.frombuffer(raw, np.uint8)
            if bits == 8:
                idx = arr.copy()
            elif bits == 4:
                idx = np.empty(n, np.uint8)
                idx[0::2] = arr & 0xF
                idx[1::2] = arr >> 4
            else:
                idx = np.empty(n, np.uint8)
                for k in range(4):
                    idx[k::4] = (arr >> (2 * k)) & 3
            cols = self.palette(pal_index, _NCOLORS[fmt])
            pl = np.zeros((256, 4), np.uint8)
            m = min(len(cols), 256)
            if m:
                pl[:m, :3] = np.array(cols[:m], np.uint8)
                pl[:m, 3] = 255
            if p['col0']:
                pl[0, 3] = 0
            return pl[idx].reshape(h, w, 4)

        if fmt in (1, 6):                               # A3I5 / A5I3
            raw = self.d[base:base + n]
            if len(raw) < n:
                raise TEX0Error('texture %r: texdata truncated' % self.tex_names[i])
            arr = np.frombuffer(raw, np.uint8)
            if fmt == 1:        # A3I5: 5 index bits, 3 alpha bits
                ai, ash, amax = arr & 0x1F, arr >> 5, 7
            else:               # A5I3: 3 index bits, 5 alpha bits
                ai, ash, amax = arr & 0x07, arr >> 3, 31
            cols = self.palette(pal_index, 256)
            pl = np.zeros((256, 3), np.uint8)
            m = min(len(cols), 256)
            if m:
                pl[:m] = np.array(cols[:m], np.uint8)
            alpha = (ash.astype(np.uint16) * 255 // amax).astype(np.uint8)
            return np.concatenate([pl[ai], alpha[:, None]], 1).reshape(h, w, 4)

        raise TEX0Error('unhandled texture format %d' % fmt)

    def _decode_cmp(self, i, p, pal):
        """4x4 block-compressed (CMP4x4) texture -> (h, w, 4) uint8 ndarray."""
        import numpy as np
        w, h = p['w'], p['h']
        base = self.base + self.cmpdata_off + p['vram']
        ibase = self.base + self.cmpinfodata_off + (p['vram'] >> 1)
        out = np.zeros((h, w, 4), np.uint8)
        bw, bh = w // 4, h // 4
        for by in range(bh):
            for bx in range(bw):
                bi = by * bw + bx
                blk = struct.unpack_from('<I', self.d, base + bi * 4)[0]
                info = struct.unpack_from('<H', self.d, ibase + bi * 2)[0]
                paloff = (info & 0x3FFF) * 4
                mode = (info >> 14) & 3
                cols = []
                for k in range(4):
                    if paloff + k < len(pal):
                        cols.append(list(pal[paloff + k]) + [255])
                    else:
                        cols.append([0, 0, 0, 0])
                if mode == 0:
                    cols[3] = [0, 0, 0, 0]
                elif mode == 1:
                    cols[2] = [(cols[0][j] + cols[1][j]) // 2 for j in range(3)] + [255]
                    cols[3] = [0, 0, 0, 0]
                elif mode == 3:
                    cols[2] = [(cols[0][j] * 5 + cols[1][j] * 3) // 8 for j in range(3)] + [255]
                    cols[3] = [(cols[0][j] * 3 + cols[1][j] * 5) // 8 for j in range(3)] + [255]
                for py in range(4):
                    for px in range(4):
                        sel = (blk >> (2 * (py * 4 + px))) & 3
                        out[by * 4 + py, bx * 4 + px] = cols[sel]
        return out

    def to_image(self, tex, pal_index=None):
        """Decode to a PIL RGBA Image."""
        from PIL import Image
        return Image.fromarray(self.decode(tex, pal_index), 'RGBA')
