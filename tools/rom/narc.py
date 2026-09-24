# -*- coding: utf-8 -*-
"""NARC - Nitro ARChive.

Every ``.narc`` in Gen 4 and nearly every ``/a/x/y/z`` in Gen 5 is a NARC:
a 16-byte container header followed by exactly three chunks, always in this
order:

    BTAF   sub-file allocation table
    BTNF   sub-file name table  (null in every NARC in all four ROMs)
    GMIF   file image; BTAF offsets are relative to GMIF's payload

Some tools write the chunk magics reversed (FATB/FNTB/FIMG); both spellings are
accepted here.

See docs/research/nds-formats.md section 2.

Traps:

* **The BTAF sub-file count is at +0x08, not +0x06.** Reading +0x06 silently
  yields 0 sub-files for pl_pokegra and 1 for White 2's /a/0/0/4.
* **Sub-file names do not exist.** 0 of Platinum's 340 NARCs carry a name
  table. Address sub-files by index.
* **Empty sub-files are normal** (``start == end``) - Gen 4 female sprite slots
  and Gen 5 slots +1/+3 are routinely empty. Guard before parsing.
"""

import struct

from .lz import maybe_decompress

__all__ = ['NARCError', 'NARC', 'magic_of']

_ALIAS = {b'FATB': b'BTAF', b'FNTB': b'BTNF', b'FIMG': b'GMIF'}


class NARCError(ValueError):
    """Raised when a blob is not a usable NARC."""


class NARC(object):
    """A Nitro archive. Indexable and iterable; yields raw sub-file bytes.

    Attributes:
        chunks   dict magic -> (offset, size)
        entries  list of (start, end) offsets relative to the GMIF payload
    """

    def __init__(self, data):
        data = bytes(data)
        if len(data) < 16:
            raise NARCError('blob is %d bytes - too short for a NARC header' % len(data))
        if data[:4] != b'NARC':
            raise NARCError('not a NARC: magic %r' % data[:4])
        self.data = data
        self.filesize = struct.unpack_from('<I', data, 8)[0]
        hdrsize, nchunks = struct.unpack_from('<HH', data, 12)
        self.chunks = {}
        p = hdrsize
        for _ in range(nchunks):
            if p + 8 > len(data):
                break
            magic, csize = struct.unpack_from('<4sI', data, p)
            magic = _ALIAS.get(magic, magic)
            self.chunks.setdefault(magic, (p, csize))
            if csize <= 0:
                break
            p += csize
        if b'BTAF' not in self.chunks:
            raise NARCError('NARC has no BTAF chunk (chunks: %s)'
                            % sorted(m.decode('latin-1') for m in self.chunks))
        if b'GMIF' not in self.chunks:
            raise NARCError('NARC has no GMIF chunk (chunks: %s)'
                            % sorted(m.decode('latin-1') for m in self.chunks))
        bo = self.chunks[b'BTAF'][0]
        n = struct.unpack_from('<H', data, bo + 8)[0]   # count is at +0x08
        self.entries = [struct.unpack_from('<II', data, bo + 12 + i * 8)
                        for i in range(n)]
        self.image = self.chunks[b'GMIF'][0] + 8

    # -- container ---------------------------------------------------------
    def __len__(self):
        return len(self.entries)

    def __getitem__(self, i):
        if isinstance(i, slice):
            return [self[k] for k in range(*i.indices(len(self)))]
        if i < 0:
            i += len(self.entries)
        s, e = self.entries[i]
        return self.data[self.image + s:self.image + e]

    def __iter__(self):
        for i in range(len(self.entries)):
            yield self[i]

    def __repr__(self):
        return '<NARC %d sub-files, %d bytes>' % (len(self.entries), len(self.data))

    # -- helpers -----------------------------------------------------------
    def size(self, i):
        s, e = self.entries[i]
        return e - s

    def sizes(self):
        return [e - s for s, e in self.entries]

    def is_empty(self, i):
        """True for a legal zero-length sub-file (``start == end``)."""
        s, e = self.entries[i]
        return s == e

    def get(self, i, decompress=True):
        """Sub-file ``i``, transparently LZ10/LZ11-decompressed when it really is.

        Uses the validating sniff from :func:`tools.rom.lz.maybe_decompress`,
        so an uncompressed file whose first byte happens to be 0x10/0x11 comes
        back untouched.
        """
        raw = self[i]
        if not decompress:
            return raw
        return maybe_decompress(raw)

    def magics(self):
        """Per-sub-file 4-byte magic (after decompression), for surveying."""
        return [magic_of(self.get(i)) for i in range(len(self.entries))]

    @classmethod
    def from_nds(cls, nds, path):
        """Open the NARC at ``path`` inside an open :class:`tools.rom.ndsfs.NDS`."""
        return cls(nds.read(path))


def magic_of(b):
    """Printable 4-byte magic, or a size marker for a too-short blob."""
    if len(b) < 4:
        return '<%d bytes>' % len(b)
    m = b[:4]
    if all(32 <= c < 127 for c in m):
        return m.decode('ascii')
    return repr(m)
