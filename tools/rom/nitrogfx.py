# -*- coding: utf-8 -*-
"""Nitro 2D graphics resources: NCLR, NCGR, NSCR, NCER, NANR -> RGBA.

Every ``N***`` resource shares a 16-byte container header followed by sections.
**The magic is stored byte-reversed on disk** - an NCLR file starts with the
ASCII ``RLCN``. Match the on-disk spelling.

    NCLR  RLCN   palette              section TTLP (+ optional PCMP)
    NCGR  RGCN   character / tiles    section RAHC (+ optional SOPC)
    NSCR  RCSN   screen / tilemap     section NRCS
    NCER  RECN   cell / OAM assembly  section KBEC (+ LBAL, TXEU)
    NANR  RNAN   animation            section KNBA

See docs/research/nds-formats.md sections 4 and 5.

Traps this module handles for you:

* **Gen 5 sprite NCGRs lie about their file and section size.** The
  ``dataSize`` field inside CHAR is the truth; every section read is clamped to
  the real buffer length.
* **4bpp: the low nibble is the LEFT pixel.**
* **CHAR flags bit 0 means *linear* (do NOT untile).** Gen 4 battle sprites are
  linear; almost everything else is tiled.
* **NCLR's depth field can disagree with reality.** Colour count comes from
  ``dataSize / 2``; pixel depth comes from the NCGR.
* **Gen 4 sprite pixels are XOR-obfuscated with an LCG keystream**, and the
  direction is per-authoring-game (Platinum forward, Diamond/Pearl backward),
  so :func:`auto_decrypt` detects rather than assumes. **Gen 5 sprites are not
  obfuscated** - running the XOR on them destroys the image, so the detector is
  entropy-gated.
* **The Gen 5 96x96 canvas is not a plain 12x12 tile grid.** It is four
  1D-mapped OAM objects; use :func:`gen5_assemble`, never :func:`untile`.
"""

import collections
import math
import struct

from .lz import maybe_decompress

__all__ = [
    'NitroError', 'sections', 'bgr555_to_rgb', 'NCLR', 'NCGR', 'NSCR', 'NCER',
    'NANR', 'unpack_indices', 'untile', 'gen5_assemble', 'GEN5_OBJS',
    'unpack_screen_entry', 'decode_oam', 'OAM_SIZE', 'xor_lcg', 'nibble_entropy',
    'auto_decrypt', 'render_screen', 'compose_cell', 'indices_to_rgba', 'save_png',
]


class NitroError(ValueError):
    """Raised when a blob is not the Nitro resource we asked for."""


# --------------------------------------------------------------- container
def sections(d):
    """-> {section_magic: (offset, size)} for a Nitro container.

    Clamps to the real buffer: Gen 5 sprite NCGRs declare sizes larger than the
    data they ship.
    """
    if len(d) < 16:
        raise NitroError('blob is %d bytes - too short for a Nitro header' % len(d))
    hdrsize, nsec = struct.unpack_from('<HH', d, 12)
    out = {}
    p = hdrsize if hdrsize else 16
    for _ in range(nsec):
        if p + 8 > len(d):
            break
        cid, csz = struct.unpack_from('<4sI', d, p)
        if csz == 0 or p + csz > len(d):         # header lies - clamp and stop
            out.setdefault(cid, (p, len(d) - p))
            break
        out.setdefault(cid, (p, csz))
        p += csz
    return out


def _section(d, magic, what):
    s = sections(d)
    if magic not in s:
        raise NitroError('no %s section in this %s (magic %r, sections %s)'
                         % (magic.decode('latin-1'), what, d[:4],
                            sorted(k.decode('latin-1') for k in s)))
    return s[magic]


def bgr555_to_rgb(v):
    """DS 15-bit BGR -> 8-bit RGB. The rounding matters: ``x << 3`` leaves whites at 248."""
    r, g, b = v & 0x1F, (v >> 5) & 0x1F, (v >> 10) & 0x1F
    return ((r * 255 + 15) // 31, (g * 255 + 15) // 31, (b * 255 + 15) // 31)


# -------------------------------------------------------------------- NCLR
class NCLR(object):
    """Palette. ``colors`` is a flat list of (r, g, b); ``palettes()`` splits it.

    Attributes:
        depth       raw depth field (3 = 4bpp, 4 = 8bpp) - NOT reliable, see below
        colors      flat list of (r,g,b), length = dataSize / 2
        per_palette colours-per-palette field (0x10 in every ROM here)
    """

    MAGIC = b'RLCN'

    def __init__(self, data, decompress=True):
        d = maybe_decompress(data) if decompress else bytes(data)
        if d[:4] != self.MAGIC:
            raise NitroError('not an NCLR: magic %r (expected %r)' % (d[:4], self.MAGIC))
        self.data = d
        o, _size = _section(d, b'TTLP', 'NCLR')
        self.depth = struct.unpack_from('<H', d, o + 0x08)[0]
        self.datasize = struct.unpack_from('<I', d, o + 0x10)[0]
        self.per_palette = struct.unpack_from('<I', d, o + 0x14)[0]
        # dataSize / 2 is the authoritative colour count; clamp to the buffer.
        n = min(self.datasize // 2, max(0, (len(d) - (o + 0x18)) // 2))
        raw = struct.unpack_from('<%dH' % n, d, o + 0x18) if n else ()
        self.colors = [bgr555_to_rgb(c) for c in raw]

    def __len__(self):
        return len(self.colors)

    def __repr__(self):
        return ('<NCLR %d colours, depth field %d, %d per palette>'
                % (len(self.colors), self.depth, self.per_palette))

    @property
    def bpp(self):
        """Depth implied by the header field. Prefer the NCGR's own bpp."""
        return 8 if self.depth == 4 else 4

    def palettes(self, per=None):
        """Split the flat colour list into sub-palettes of ``per`` colours."""
        if per is None:
            per = self.per_palette if self.per_palette in (16, 256) else 16
        return [self.colors[i:i + per] for i in range(0, len(self.colors), per)] \
            or [self.colors]

    def palette(self, index, per=16):
        """Sub-palette ``index``, falling back to the whole list when there is only one."""
        chunk = self.colors[index * per: index * per + per]
        return chunk if chunk else self.colors


# -------------------------------------------------------------------- NCGR
class NCGR(object):
    """Character (tile) data.

    Attributes:
        tiles_x, tiles_y  width/height in 8x8 tiles (0xFFFF = unspecified)
        bpp               4 or 8, from the CHAR depth field
        linear            True when CHAR flags bit 0 is set: do NOT untile
        data              raw char bytes, clamped to CHAR.dataSize
        n_tiles           len(data) // (32 at 4bpp, 64 at 8bpp)
    """

    MAGIC = b'RGCN'

    def __init__(self, data, decompress=True):
        d = maybe_decompress(data) if decompress else bytes(data)
        if d[:4] != self.MAGIC:
            raise NitroError('not an NCGR: magic %r (expected %r)' % (d[:4], self.MAGIC))
        self.data_blob = d
        o, _size = _section(d, b'RAHC', 'NCGR')
        # NOTE: height comes first, then width.
        self.tiles_y, self.tiles_x = struct.unpack_from('<HH', d, o + 0x08)
        depth = struct.unpack_from('<I', d, o + 0x0C)[0]
        self.bpp = 4 if depth == 3 else 8
        self.map_param = struct.unpack_from('<I', d, o + 0x10)[0]
        self.flags = struct.unpack_from('<I', d, o + 0x14)[0]
        self.linear = bool(self.flags & 1)
        dsz = struct.unpack_from('<I', d, o + 0x18)[0]
        doff = struct.unpack_from('<I', d, o + 0x1C)[0]      # always 0x18
        start = o + 0x08 + doff
        self.data = bytes(d[start:start + dsz])              # clamps if the header lies
        self.declared_size = dsz
        # SOPC is the fallback when CHAR says 0xFFFF.
        s = sections(d)
        self.sopc = None
        if b'SOPC' in s:
            so = s[b'SOPC'][0]
            if so + 0x10 <= len(d):
                self.sopc = struct.unpack_from('<HH', d, so + 0x0C)   # (tilesX, tilesY)

    @property
    def n_tiles(self):
        return len(self.data) // (32 if self.bpp == 4 else 64)

    def dimensions(self, default_tiles_x=None):
        """-> (width, height) in pixels, using CHAR then SOPC then a fallback.

        ``default_tiles_x`` lays the tiles out in a strip that many tiles wide
        when neither header gives a size.
        """
        tx, ty = self.tiles_x, self.tiles_y
        if tx in (0, 0xFFFF) or ty in (0, 0xFFFF):
            if self.sopc and 0 not in self.sopc and 0xFFFF not in self.sopc:
                tx, ty = self.sopc
            elif default_tiles_x:
                tx = default_tiles_x
                ty = (self.n_tiles + tx - 1) // tx
            else:
                raise NitroError('NCGR has no usable dimensions '
                                 '(CHAR %r, SOPC %r); pass default_tiles_x'
                                 % ((self.tiles_x, self.tiles_y), self.sopc))
        return tx * 8, ty * 8

    def indices(self, width=None, height=None, default_tiles_x=None):
        """-> flat list of palette indices in raster order, ``width*height`` long."""
        if width is None or height is None:
            width, height = self.dimensions(default_tiles_x)
        px = unpack_indices(self.data, self.bpp)
        need = width * height
        if len(px) < need:
            px = px + [0] * (need - len(px))
        px = px[:need]
        if not self.linear:
            px = untile(px, width, height)
        return px

    def __repr__(self):
        return ('<NCGR %sx%s tiles, %dbpp, %s, %d chars>'
                % (self.tiles_x, self.tiles_y, self.bpp,
                   'linear' if self.linear else 'tiled', self.n_tiles))


# -------------------------------------------------------------------- NSCR
class NSCR(object):
    """Screen / tilemap. ``entries`` is a list of u16 screen entries."""

    MAGIC = b'RCSN'

    def __init__(self, data, decompress=True):
        d = maybe_decompress(data) if decompress else bytes(data)
        if d[:4] != self.MAGIC:
            raise NitroError('not an NSCR: magic %r (expected %r)' % (d[:4], self.MAGIC))
        o, _size = _section(d, b'NRCS', 'NSCR')
        self.width, self.height = struct.unpack_from('<HH', d, o + 0x08)
        self.color_mode, self.screen_format = struct.unpack_from('<HH', d, o + 0x0C)
        dsz = struct.unpack_from('<I', d, o + 0x10)[0]
        dsz = min(dsz, max(0, len(d) - (o + 0x14)))
        n = dsz // 2
        self.entries = list(struct.unpack_from('<%dH' % n, d, o + 0x14)) if n else []

    def __repr__(self):
        return '<NSCR %dx%d px, %d entries>' % (self.width, self.height, len(self.entries))


def unpack_screen_entry(v):
    """-> (tile_index, hflip, vflip, palette_number)."""
    return (v & 0x03FF, bool(v & 0x0400), bool(v & 0x0800), (v >> 12) & 0xF)


# -------------------------------------------------------------------- NCER
OAM_SIZE = {   # (shape, size) -> (w, h) in pixels
    (0, 0): (8, 8),   (0, 1): (16, 16), (0, 2): (32, 32), (0, 3): (64, 64),
    (1, 0): (16, 8),  (1, 1): (32, 8),  (1, 2): (32, 16), (1, 3): (64, 32),
    (2, 0): (8, 16),  (2, 1): (8, 32),  (2, 2): (16, 32), (2, 3): (32, 64),
}


def decode_oam(a0, a1, a2):
    """Decode one hardware OAM entry (attr0, attr1, attr2) -> dict.

    Trap: when ``rot`` is set, bit 9 of attr0 means *double size*, not
    *disable*, and attr1 bits 12/13 are affine-matrix selector bits, not flips.
    Gen 5 Pokemon cells set ``rot`` on every entry.
    """
    y = a0 & 0xFF
    if y >= 128:
        y -= 256
    rot = bool(a0 & 0x0100)
    dsize = rot and bool(a0 & 0x0200)
    disable = (not rot) and bool(a0 & 0x0200)
    mode = (a0 >> 10) & 3
    mosaic = bool(a0 & 0x1000)
    depth8 = bool(a0 & 0x2000)
    shape = (a0 >> 14) & 3
    x = a1 & 0x01FF
    if x >= 256:
        x -= 512
    hflip = (not rot) and bool(a1 & 0x1000)
    vflip = (not rot) and bool(a1 & 0x2000)
    size = (a1 >> 14) & 3
    tile = a2 & 0x03FF
    prio = (a2 >> 10) & 3
    pal = (a2 >> 12) & 0xF
    w, h = OAM_SIZE[(shape, size)]
    box = (w * 2, h * 2) if dsize else (w, h)    # drawn box; SOURCE stays w x h
    return dict(x=x, y=y, w=w, h=h, box=box, tile=tile, pal=pal,
                hflip=hflip, vflip=vflip, depth8=depth8, rot=rot,
                disable=disable, prio=prio, mosaic=mosaic, mode=mode)


class NCER(object):
    """Cell bank. ``cells`` is a list of dicts with 'oam' (raw triples) and bounds."""

    MAGIC = b'RECN'

    def __init__(self, data, decompress=True):
        d = maybe_decompress(data) if decompress else bytes(data)
        if d[:4] != self.MAGIC:
            raise NitroError('not an NCER: magic %r (expected %r)' % (d[:4], self.MAGIC))
        o, _size = _section(d, b'KBEC', 'NCER')
        self.n_cells, cellattr = struct.unpack_from('<HH', d, o + 0x08)
        cellptr = struct.unpack_from('<I', d, o + 0x0C)[0]
        self.mapping_mode = struct.unpack_from('<I', d, o + 0x10)[0]
        self.extended = bool(cellattr & 1)
        stride = 16 if self.extended else 8
        base = o + 0x08 + cellptr
        oam_pool = base + self.n_cells * stride
        self.cells = []
        for i in range(self.n_cells):
            co = base + i * stride
            n_oam, attr, oamoff = struct.unpack_from('<HHI', d, co)
            bounds = None
            if self.extended:
                maxx, maxy, minx, miny = struct.unpack_from('<4h', d, co + 0x08)
                bounds = (minx, miny, maxx, maxy)   # order on disk is max before min
            oams = []
            for j in range(n_oam):
                po = oam_pool + oamoff + j * 6
                if po + 6 > len(d):
                    break
                oams.append(struct.unpack_from('<3H', d, po))
            self.cells.append(dict(oam=oams, attr=attr, bounds=bounds))

    @property
    def char_boundary(self):
        """Bytes per unit of an OAM tile index: 32 for 2D mapping, 32<<(mode-1) for 1D."""
        m = self.mapping_mode
        return 32 if m == 0 else (32 << (m - 1))

    def __len__(self):
        return self.n_cells

    def __repr__(self):
        return ('<NCER %d cells, mapping %d, %s>'
                % (self.n_cells, self.mapping_mode,
                   'extended' if self.extended else 'basic'))


# -------------------------------------------------------------------- NANR
class NANR(object):
    """Animation bank. ``sequences`` is a list of dicts with decoded frames."""

    MAGIC = b'RNAN'
    _ELEM_SIZE = {0: 4, 1: 16, 2: 8}

    def __init__(self, data, decompress=True):
        d = maybe_decompress(data) if decompress else bytes(data)
        if d[:4] != self.MAGIC:
            raise NitroError('not an NANR: magic %r (expected %r)' % (d[:4], self.MAGIC))
        o, _size = _section(d, b'KNBA', 'NANR')
        n_seq, n_frame = struct.unpack_from('<HH', d, o + 0x08)
        seqptr, frameptr, valptr = struct.unpack_from('<III', d, o + 0x0C)
        base = o + 0x08
        self.n_frames_total = n_frame
        self.sequences = []
        for i in range(n_seq):
            so = base + seqptr + i * 16
            (nfr, loop_start, etype, atype, mode,
             foff) = struct.unpack_from('<HHHHII', d, so)
            esize = self._ELEM_SIZE.get(etype, 4)
            frames = []
            for j in range(nfr):
                fo = base + frameptr + foff + j * 8
                if fo + 8 > len(d):
                    break
                voff, duration, _pad = struct.unpack_from('<IHH', d, fo)
                vo = base + valptr + voff
                if vo + esize > len(d):
                    break
                cell = struct.unpack_from('<H', d, vo)[0]
                raw = struct.unpack_from('<%dH' % (esize // 2), d, vo)
                frames.append(dict(cell=cell, duration=duration, raw=raw))
            self.sequences.append(dict(frames=frames, loop_start=loop_start,
                                       elem_type=etype, anim_type=atype, mode=mode))

    def __len__(self):
        return len(self.sequences)

    def __repr__(self):
        return ('<NANR %d sequences, %d frames>'
                % (len(self.sequences), self.n_frames_total))


# ---------------------------------------------------------------- pixel ops
def unpack_indices(data, bpp):
    """Char bytes -> one palette index per pixel. 4bpp: LOW nibble is the LEFT pixel."""
    if bpp == 8:
        return list(data)
    out = []
    for byte in data:
        out.append(byte & 0x0F)   # left
        out.append(byte >> 4)     # right
    return out


def untile(idx, width, height):
    """8x8-tiled char order -> raster order. Do NOT call this when CHAR flags bit 0 is set."""
    out = [0] * (width * height)
    p = 0
    for ty in range(height // 8):
        for tx in range(width // 8):
            for y in range(8):
                row = (ty * 8 + y) * width + tx * 8
                out[row:row + 8] = idx[p:p + 8]
                p += 8
    return out


# Gen 5 96x96 battle sprites: four 1D-mapped OAM objects, row-major, clipped.
GEN5_OBJS = [(0, 0, 64, 64), (64, 0, 32, 64), (0, 64, 64, 32), (64, 64, 32, 32)]


def gen5_assemble(px, width=96, height=96, objs=None):
    """Assemble a Gen 5 battle sprite's chars into a raster image.

    The +0/+9 NCGR declares 12x12 tiles and flags = 0 (tiled), but a plain
    96-wide :func:`untile` produces garbage: the chars are stored as four
    1D-mapped OAM objects covering the canvas in 64x64 super-blocks, row-major,
    clipped at the edges (64 + 32 + 32 + 16 = 144 chars). Inside each object the
    chars are row-major 8x8 tiles.

    ``px`` is the output of :func:`unpack_indices` on the NCGR char data.
    """
    if objs is None:
        objs = GEN5_OBJS
    out = [0] * (width * height)
    c = 0
    for ox, oy, ow, oh in objs:
        for ty in range(oh // 8):
            for tx in range(ow // 8):
                base = c * 64
                c += 1
                for y in range(8):
                    r = (oy + ty * 8 + y) * width + ox + tx * 8
                    out[r:r + 8] = px[base + y * 8: base + y * 8 + 8]
    return out


# ---------------------------------------------- Gen 4/5 sprite XOR de-obfuscation
MUL, ADD, U32 = 0x41C64E6D, 0x6073, 0xFFFFFFFF
ENTROPY_THRESHOLD = 3.6


def xor_lcg(data, backward, seed=None):
    """XOR the char payload with the Pokemon LCG keystream.

    When ``seed`` is None (the decryption case) the seed IS the first (forward)
    or last (backward) u16 of the buffer, so that halfword always decodes to
    0x0000 - a free self-check.

    **This is NOT self-inverse with a derived seed**, contrary to
    docs/research/nds-formats.md section 5.1.1: decryption leaves the seeding
    halfword at 0x0000, so a second derived-seed pass runs a keystream from
    seed 0 and produces different bytes. To re-encrypt, pass the original
    ciphertext's seeding halfword explicitly::

        seed = struct.unpack_from('<H', cipher, 0)[0]
        plain  = xor_lcg(cipher, False)
        cipher2 = xor_lcg(plain, False, seed=seed)     # == cipher

    Verified by tests/test_rom.py::test_xor_lcg_round_trips_with_an_explicit_seed.
    """
    n = len(data) // 2
    if n == 0:
        return bytearray(data)
    w = list(struct.unpack_from('<%dH' % n, bytes(data)))
    if seed is None:
        seed = w[n - 1] if backward else w[0]
    for i in (range(n - 1, -1, -1) if backward else range(n)):
        w[i] ^= seed & 0xFFFF
        seed = (seed * MUL + ADD) & U32
    return bytearray(struct.pack('<%dH' % n, *w))


def nibble_entropy(buf):
    """Shannon entropy over 4-bit nibbles. Encrypted data sits at ~4.000 bits."""
    c = collections.Counter()
    for x in buf:
        c[x & 0xF] += 1
        c[x >> 4] += 1
    t = float(sum(c.values()))
    if not t:
        return 0.0
    return -sum((v / t) * math.log(v / t, 2) for v in c.values() if v)


def auto_decrypt(buf, threshold=ENTROPY_THRESHOLD):
    """-> (plaintext_bytes, mode) where mode is 'plain' | 'forward' | 'backward'.

    Entropy-gated, because the XOR direction is per-authoring-game (Platinum
    forward, Diamond/Pearl backward) and Gen 5 sprites are not obfuscated at
    all - XORing them would destroy the image.
    """
    if nibble_entropy(buf) < threshold:
        return bytearray(buf), 'plain'
    f, b = xor_lcg(buf, False), xor_lcg(buf, True)
    hf, hb = nibble_entropy(f), nibble_entropy(b)
    if hf < hb and hf < threshold:
        return f, 'forward'
    if hb < threshold:
        return b, 'backward'
    return bytearray(buf), 'plain'


# ------------------------------------------------------------- compositing
def render_screen(nscr, ncgr, nclr):
    """Compose an NSCR tilemap over an NCGR char stream -> PIL RGBA Image.

    Index 0 is OPAQUE for backgrounds, unlike sprites. A tile is 8x8 pixels at
    both depths; only the byte cost differs.
    """
    from PIL import Image
    chars = unpack_indices(ncgr.data, ncgr.bpp)
    tw, th = nscr.width // 8, nscr.height // 8
    img = Image.new('RGBA', (nscr.width, nscr.height), (0, 0, 0, 255))
    px = img.load()
    psize = 16 if ncgr.bpp == 4 else 256
    for ty in range(th):
        for tx in range(tw):
            k = ty * tw + tx
            if k >= len(nscr.entries):
                break
            tile, hf, vf, pn = unpack_screen_entry(nscr.entries[k])
            pal = nclr.colors[pn * psize: pn * psize + psize] or nclr.colors
            base = tile * 64
            if base + 64 > len(chars):
                continue
            for yy in range(8):
                for xx in range(8):
                    i = chars[base + yy * 8 + xx]
                    sx = 7 - xx if hf else xx
                    sy = 7 - yy if vf else yy
                    px[tx * 8 + sx, ty * 8 + sy] = (tuple(pal[i]) + (255,)
                                                    if i < len(pal) else (0, 0, 0, 255))
    return img


def compose_cell(ncer, cell_index, ncgr, nclr, canvas=(128, 128), origin=None,
                 boundary=None):
    """Compose one NCER cell from an NCGR char stream -> PIL RGBA Image.

    ``boundary`` is the byte granularity of an OAM tile index; it defaults to
    ``ncer.char_boundary`` (32 for 2D mapping, 32<<(mode-1) for 1D). Index 0 is
    transparent.
    """
    from PIL import Image
    idx = unpack_indices(ncgr.data, ncgr.bpp)
    W, H = canvas
    ox, oy = origin if origin else (W // 2, H // 2)
    if boundary is None:
        boundary = ncer.char_boundary
    mult = max(1, boundary // 32)          # chars per unit of the tile index
    img = Image.new('RGBA', (W, H), (0, 0, 0, 0))
    px = img.load()
    psize = 16 if ncgr.bpp == 4 else 256
    for a in ncer.cells[cell_index]['oam']:
        o = decode_oam(*a)
        if o['disable']:
            continue
        pal = nclr.colors[o['pal'] * psize: o['pal'] * psize + psize] or nclr.colors
        base = o['tile'] * mult * 64                    # in PIXELS
        tw, th = o['w'] // 8, o['h'] // 8
        for ty in range(th):
            for tx in range(tw):
                cb = base + (ty * tw + tx) * 64         # 1D object char order
                if cb + 64 > len(idx):
                    continue
                for yy in range(8):
                    for xx in range(8):
                        v = idx[cb + yy * 8 + xx]
                        if v == 0 or v >= len(pal):
                            continue
                        sx, sy = tx * 8 + xx, ty * 8 + yy
                        if o['hflip']:
                            sx = o['w'] - 1 - sx
                        if o['vflip']:
                            sy = o['h'] - 1 - sy
                        X = ox + o['x'] + sx + (o['box'][0] - o['w']) // 2
                        Y = oy + o['y'] + sy + (o['box'][1] - o['h']) // 2
                        if 0 <= X < W and 0 <= Y < H:
                            px[X, Y] = tuple(pal[v]) + (255,)
    return img


# ------------------------------------------------------------------- output
def indices_to_rgba(idx, width, height, palette, transparent_index=0):
    """-> a PIL RGBA Image. Palette index 0 is transparent for sprites and cells.

    Pass ``transparent_index=None`` for NSCR backgrounds, where index 0 is
    opaque.
    """
    from PIL import Image
    im = Image.new('RGBA', (width, height))
    px = im.load()
    n = len(palette)
    for y in range(height):
        b = y * width
        for x in range(width):
            i = idx[b + x]
            if i == transparent_index:
                px[x, y] = (0, 0, 0, 0)
            elif i < n:
                px[x, y] = tuple(palette[i]) + (255,)
            else:
                px[x, y] = (0, 0, 0, 0)
    return im


def save_png(path, idx, width, height, palette, transparent_index=0):
    """Write an indexed image to ``path`` as RGBA PNG. Returns the PIL Image."""
    im = indices_to_rgba(idx, width, height, palette, transparent_index)
    im.save(path)
    return im
