"""Nintendo DS container + 2D graphics readers.

Pure format knowledge (no ROM data): NDS filesystem, NARC archives, LZ10/LZ11,
NCLR palettes, NCGR character banks, NCER cell banks, NANR cell animations and
NMCR multicell rigs.

Everything here was verified against the owner's own ROM dumps; see
docs/research/nds-formats.md and docs/research/gen5-assets.md.
"""

import struct


# --------------------------------------------------------------------- NDS ROM
class NDS(object):
    """Read-only view of an .nds ROM: header + FNT/FAT filesystem."""

    def __init__(self, path):
        with open(path, 'rb') as f:
            self.d = f.read()
        d = self.d
        self.path = path
        self.title = d[0:12].decode('ascii', 'replace').rstrip('\x00')
        self.gamecode = d[0x0C:0x10].decode('ascii', 'replace')
        (self.fnt_off, self.fnt_size,
         self.fat_off, self.fat_size) = struct.unpack_from('<4I', d, 0x40)
        n = self.fat_size // 8
        self.fat = [struct.unpack_from('<II', d, self.fat_off + i * 8) for i in range(n)]
        self.paths = {}
        self._walk(0xF000, '')

    def _walk(self, did, prefix):
        off = self.fnt_off + (did & 0xFFF) * 8
        sub, fid, _parent = struct.unpack_from('<IHH', self.d, off)
        p = self.fnt_off + sub
        while True:
            t = self.d[p]
            p += 1
            if t == 0:
                break
            ln = t & 0x7F
            name = self.d[p:p + ln].decode('ascii', 'replace')
            p += ln
            full = prefix + '/' + name
            if t & 0x80:
                sd = struct.unpack_from('<H', self.d, p)[0]
                p += 2
                self._walk(sd, full)
            else:
                self.paths[full] = fid
                fid += 1

    def read(self, path):
        s, e = self.fat[self.paths[path]]
        return self.d[s:e]


def _blocks(blob, hdrsize, nblocks):
    p = hdrsize
    out = []
    for _ in range(nblocks):
        if p + 8 > len(blob):
            break
        magic = blob[p:p + 4]
        size = struct.unpack_from('<I', blob, p + 4)[0]
        if size == 0:
            break
        out.append((magic, p, size))
        p += size
    return out


class NARC(object):
    """Nitro archive. Accepts both BTAF/BTNF/GMIF and FATB/FNTB/FIMG spellings."""

    def __init__(self, blob):
        if blob[:4] != b'NARC':
            raise ValueError('not a NARC: %r' % blob[:4])
        self.blob = blob
        hdrsize, nblocks = struct.unpack_from('<HH', blob, 12)
        self.ents = []
        self.base = None
        for magic, p, _size in _blocks(blob, hdrsize, nblocks):
            m = magic[::-1] if magic in (b'FATB', b'FNTB', b'FIMG') else magic
            if m == b'BTAF':
                n = struct.unpack_from('<H', blob, p + 8)[0]
                for i in range(n):
                    self.ents.append(struct.unpack_from('<II', blob, p + 12 + i * 8))
            elif m == b'GMIF':
                self.base = p + 8
        if self.base is None:
            raise ValueError('NARC has no image block')

    def __len__(self):
        return len(self.ents)

    def __getitem__(self, i):
        s, e = self.ents[i]
        return self.blob[self.base + s:self.base + e]


# ------------------------------------------------------------------ compression
def lz10(data):
    out = bytearray()
    size = data[1] | (data[2] << 8) | (data[3] << 16)
    p = 4
    while len(out) < size and p < len(data):
        flags = data[p]
        p += 1
        for b in range(8):
            if len(out) >= size:
                break
            if flags & (0x80 >> b):
                if p + 1 >= len(data):
                    return bytes(out)
                v = (data[p] << 8) | data[p + 1]
                p += 2
                n = (v >> 12) + 3
                disp = (v & 0xFFF) + 1
                for _ in range(n):
                    out.append(out[-disp])
            else:
                if p >= len(data):
                    return bytes(out)
                out.append(data[p])
                p += 1
    return bytes(out)


def lz11(data):
    size = data[1] | (data[2] << 8) | (data[3] << 16)
    p = 4
    if size == 0:
        size = struct.unpack_from('<I', data, 4)[0]
        p = 8
    out = bytearray()
    while len(out) < size and p < len(data):
        flags = data[p]
        p += 1
        for b in range(8):
            if len(out) >= size or p >= len(data):
                break
            if flags & (0x80 >> b):
                a = data[p]
                p += 1
                ind = a >> 4
                if ind == 0:
                    c, d = data[p], data[p + 1]
                    p += 2
                    n = (((a & 0xF) << 4) | (c >> 4)) + 0x11
                    disp = (((c & 0xF) << 8) | d) + 1
                elif ind == 1:
                    c, d, e = data[p], data[p + 1], data[p + 2]
                    p += 3
                    n = (((a & 0xF) << 12) | (c << 4) | (d >> 4)) + 0x111
                    disp = (((d & 0xF) << 8) | e) + 1
                else:
                    c = data[p]
                    p += 1
                    n = ind + 1
                    disp = (((a & 0xF) << 8) | c) + 1
                for _ in range(n):
                    out.append(out[-disp])
            else:
                out.append(data[p])
                p += 1
    return bytes(out)


def decomp(data):
    """Transparently LZ-decompress if the blob carries an LZ10/LZ11 header."""
    if len(data) > 4:
        try:
            if data[0] == 0x10:
                return lz10(data)
            if data[0] == 0x11:
                return lz11(data)
        except Exception:
            return data
    return data


def sections(blob):
    """-> {b'TTLP': (offset, size), ...} for a Nitro container (magics are reversed)."""
    hdrsize, nblocks = struct.unpack_from('<HH', blob, 12)
    out = {}
    for magic, p, size in _blocks(blob, hdrsize, nblocks):
        out[magic] = (p, size)
    return out


# ---------------------------------------------------------------------- NCLR
def read_nclr(blob):
    """-> (list of palettes, each a list of (r, g, b)).

    Gotcha: Gen 5 pokegra NCLRs report bitDepth 4 (256-colour) while actually
    holding 16-colour palettes. `colorsPerPalette` is the field to trust.
    """
    blob = decomp(blob)
    p, size = sections(blob)[b'TTLP']
    bitdepth = struct.unpack_from('<I', blob, p + 8)[0]
    _datasize, colorsperpal = struct.unpack_from('<II', blob, p + 16)
    raw = blob[p + 24: p + size]
    cols = []
    for i in range(len(raw) // 2):
        v = struct.unpack_from('<H', raw, i * 2)[0]
        cols.append((((v) & 31) * 255 // 31,
                     ((v >> 5) & 31) * 255 // 31,
                     ((v >> 10) & 31) * 255 // 31))
    per = 256 if bitdepth == 4 else 16
    if colorsperpal in (16, 256):
        per = colorsperpal
    return [cols[i:i + per] for i in range(0, len(cols), per)] or [cols]


# ---------------------------------------------------------------------- NCGR
def read_ncgr(blob):
    """-> dict(idx, ntiles, tiles_x, tiles_y, bpp, mapmode, linear).

    `idx` is one palette index per pixel, still in the file's own order
    (8x8 tile-major when linear == 0, raster when linear == 1).

    Gotcha: the linear flag is at CHAR+0x14. CHAR+0x10 is the OBJ VRAM
    mapping/partition field and means something else entirely.
    """
    blob = decomp(blob)
    p, _size = sections(blob)[b'RAHC']
    tiles_y, tiles_x = struct.unpack_from('<HH', blob, p + 8)
    fmt = struct.unpack_from('<I', blob, p + 12)[0]
    mapmode = struct.unpack_from('<I', blob, p + 16)[0]
    linear = struct.unpack_from('<I', blob, p + 20)[0]
    datasize, dataoff = struct.unpack_from('<II', blob, p + 24)
    raw = blob[p + 8 + dataoff: p + 8 + dataoff + datasize]
    if fmt == 3:
        idx = bytearray(len(raw) * 2)
        for i, byte in enumerate(raw):
            idx[i * 2] = byte & 0xF
            idx[i * 2 + 1] = byte >> 4
        bpp = 4
    else:
        idx = bytearray(raw)
        bpp = 8
    if tiles_x in (0, 0xFFFF) or tiles_y in (0, 0xFFFF):
        tiles_x = tiles_y = None
    return dict(idx=idx, ntiles=len(idx) // 64, tiles_x=tiles_x, tiles_y=tiles_y,
                bpp=bpp, mapmode=mapmode, linear=linear)


def tiles_to_image(idx, ntiles, tiles_wide):
    """8x8-tiled index data -> (w, h, raster index bytes)."""
    th = (ntiles + tiles_wide - 1) // tiles_wide
    w, h = tiles_wide * 8, th * 8
    out = bytearray(w * h)
    for t in range(ntiles):
        tx, ty = t % tiles_wide, t // tiles_wide
        for y in range(8):
            s = t * 64 + y * 8
            d = (ty * 8 + y) * w + tx * 8
            out[d:d + 8] = idx[s:s + 8]
    return w, h, out


def ncgr_raster(c, default_tiles_wide=16):
    """NCGR dict -> (w, h, raster index bytes), honouring the linear flag."""
    if c['linear'] and c['tiles_x'] and c['tiles_y']:
        w, h = c['tiles_x'] * 8, c['tiles_y'] * 8
        buf = bytearray(w * h)
        n = min(len(c['idx']), w * h)
        buf[:n] = c['idx'][:n]
        return w, h, buf
    return tiles_to_image(c['idx'], c['ntiles'], c['tiles_x'] or default_tiles_wide)


def to_rgba(w, h, indexed, palette, transparent_index=0):
    """(w, h, index bytes, palette) -> PIL RGBA image."""
    from PIL import Image
    import numpy as np
    pal = np.zeros((256, 4), dtype=np.uint8)
    for i, c in enumerate(palette[:256]):
        pal[i] = (c[0], c[1], c[2], 255)
    if transparent_index is not None and transparent_index < 256:
        pal[transparent_index][3] = 0
    a = np.frombuffer(bytes(indexed), dtype=np.uint8)[:w * h]
    if a.size < w * h:
        a = np.concatenate([a, np.zeros(w * h - a.size, dtype=np.uint8)])
    return Image.fromarray(pal[a].reshape(h, w, 4), 'RGBA')


# ---------------------------------------------------------------------- NCER
_OAM_SIZE = {
    (0, 0): (8, 8),  (0, 1): (16, 16), (0, 2): (32, 32), (0, 3): (64, 64),
    (1, 0): (16, 8), (1, 1): (32, 8),  (1, 2): (32, 16), (1, 3): (64, 32),
    (2, 0): (8, 16), (2, 1): (8, 32),  (2, 2): (16, 32), (2, 3): (32, 64),
}


def parse_oam(a0, a1, a2):
    y = a0 & 0xFF
    if y >= 128:
        y -= 256
    rot = (a0 >> 8) & 1
    # bit 9 is "double size" when rot is set, "disable" when it is not.
    bit9 = (a0 >> 9) & 1
    shape = (a0 >> 14) & 3
    depth = (a0 >> 13) & 1
    x = a1 & 0x1FF
    if x >= 256:
        x -= 512
    size = (a1 >> 14) & 3
    w, h = _OAM_SIZE.get((shape, size), (8, 8))
    return dict(x=x, y=y, w=w, h=h,
                tile=a2 & 0x3FF, prio=(a2 >> 10) & 3, pal=(a2 >> 12) & 0xF,
                flipx=(a1 >> 12) & 1, flipy=(a1 >> 13) & 1,
                rot=rot, double=(rot and bit9), disabled=((not rot) and bit9),
                depth=depth)


def read_ncer(blob):
    """-> list of cells, each dict(oams=[...], bounds).

    Gotcha: the section magic is KBEC (CEBK reversed), not RBEC.
    """
    blob = decomp(blob)
    p, _size = sections(blob)[b'KBEC']
    ncells, cellattr = struct.unpack_from('<HH', blob, p + 8)
    cellptr, mapmode = struct.unpack_from('<II', blob, p + 12)
    base = p + 8 + cellptr
    stride = 16 if (cellattr & 1) else 8
    cells = []
    for i in range(ncells):
        o = base + i * stride
        noam, _cattr, oamptr = struct.unpack_from('<HHI', blob, o)
        bounds = None
        if stride == 16:
            xmax, ymax, xmin, ymin = struct.unpack_from('<4h', blob, o + 8)
            bounds = (xmin, ymin, xmax, ymax)
        oo = base + ncells * stride + oamptr
        oams = [parse_oam(*struct.unpack_from('<3H', blob, oo + j * 6)) for j in range(noam)]
        cells.append(dict(oams=oams, bounds=bounds))
    cells_mapmode = mapmode
    for c in cells:
        c['mapmode'] = cells_mapmode
    return cells


# ---------------------------------------------------------------------- NANR
def read_nanr(blob):
    """-> list of sequences, each dict(frames=[(cell, duration, dx, dy)], ...).

    Gotcha: a sequence entry is 16 bytes and the pointer into the frame array
    is the LAST u32 (a byte offset), not the startFrame u16.
    """
    d = decomp(blob)
    p, _size = sections(d)[b'KNBA']
    nseq, _nframe = struct.unpack_from('<HH', d, p + 8)
    seqoff, frameoff, dataoff = struct.unpack_from('<III', d, p + 12)
    base = p + 8
    seqs = []
    for i in range(nseq):
        o = base + seqoff + i * 16
        nfr, _loop, etype, atype = struct.unpack_from('<4H', d, o)
        mode, fbyteoff = struct.unpack_from('<II', d, o + 8)
        frames = []
        for j in range(nfr):
            fo = base + frameoff + fbyteoff + j * 8
            if fo + 8 > len(d):
                break
            dptr, dur = struct.unpack_from('<IH', d, fo)
            e = base + dataoff + dptr
            cell = struct.unpack_from('<H', d, e)[0]
            dx = dy = 0
            if etype == 1:                       # index + scale/rotate/translate
                dx, dy = struct.unpack_from('<hh', d, e + 12)
            elif etype == 2:                     # index + translate
                dx, dy = struct.unpack_from('<hh', d, e + 4)
            frames.append((cell, dur, dx, dy))
        seqs.append(dict(frames=frames, etype=etype, atype=atype, mode=mode))
    return seqs


# ---------------------------------------------------------------------- NMCR
def read_nmcr(blob):
    """-> list of multicells; each is a list of nodes.

    A node is 8 bytes and its field order is
    ``(u16 animSequenceIndex, s16 x, s16 y, u16 drawOrderAndFlags)``.
    Reading the priority first and the sequence index last -- which looks
    plausible because the last byte of the flag word counts 0,1,2,... -- makes
    every node draw the wrong body part. Nodes are composited in ascending
    ``order``.
    """
    d = decomp(blob)
    p, _size = sections(d)[b'KBCM']
    nmc = struct.unpack_from('<H', d, p + 8)[0]
    mcoff, nodeoff = struct.unpack_from('<II', d, p + 12)
    base = p + 8
    mcs = []
    for i in range(nmc):
        o = base + mcoff + i * 8
        nnodes, _a, dofs = struct.unpack_from('<HHI', d, o)
        nodes = []
        for j in range(nnodes):
            anim, x, y, order = struct.unpack_from('<HhhH', d, base + nodeoff + dofs + j * 8)
            nodes.append(dict(anim=anim, x=x, y=y, order=order & 0xFF, flags=order >> 8))
        mcs.append(nodes)
    return mcs
