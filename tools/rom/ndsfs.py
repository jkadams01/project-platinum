# -*- coding: utf-8 -*-
"""Nintendo DS cartridge: header, FAT, FNT -> a named file tree.

An .nds image is a 0x200-byte header followed by ARM binaries, an overlay table,
a File Allocation Table (FAT) and a File Name Table (FNT).

* FAT  - flat array of (start, end) ROM offsets, 8 bytes per file ID.
* FNT  - a directory table plus one name sub-table per directory; walking it
         assigns the *named* file IDs and their full paths.
* Overlays occupy file IDs ``0 .. n_overlays-1``; the first named file ID is
  ``n_overlays``.

The invariant ``n_overlays + len(named files) == len(fat)`` holds for all four
ROMs in this project and is asserted by :meth:`NDS.check`.

See docs/research/nds-formats.md section 1.

Traps:

* Never use the file length on disk as the ROM length - the tail is 0xFF
  padding. Header +0x80 (``used_size``) is authoritative.
* Directory IDs are ``0xF000 | index``; mask with 0x0FFF.
* Directory 0's "parent" field is really the total directory count.
* An empty file is legal and appears as ``start == end``.
"""

import mmap
import os
import struct

__all__ = ['NDSError', 'NDSHeader', 'Overlay', 'NDS']


class NDSError(ValueError):
    """Raised when a file is not a usable NDS image."""


class NDSHeader(object):
    """The fields of the 0x200-byte cartridge header that we actually use."""

    __slots__ = ('title', 'gamecode', 'makercode', 'unitcode', 'capacity',
                 'region', 'version', 'arm9_off', 'arm9_entry', 'arm9_ram',
                 'arm9_size', 'arm7_off', 'arm7_entry', 'arm7_ram', 'arm7_size',
                 'fnt_off', 'fnt_size', 'fat_off', 'fat_size', 'ov9_off',
                 'ov9_size', 'ov7_off', 'ov7_size', 'banner_off', 'used_size',
                 'n_overlays')

    def __init__(self, d):
        if len(d) < 0x200:
            raise NDSError('file is shorter than an NDS header (0x200 bytes)')
        self.title = d[0x00:0x0C].rstrip(b'\x00').decode('ascii', 'replace')
        self.gamecode = d[0x0C:0x10].decode('ascii', 'replace')
        self.makercode = d[0x10:0x12].decode('ascii', 'replace')
        self.unitcode = d[0x12]
        self.capacity = 128 * 1024 << d[0x14]
        self.region = d[0x1D]
        self.version = d[0x1E]
        (self.arm9_off, self.arm9_entry, self.arm9_ram, self.arm9_size,
         self.arm7_off, self.arm7_entry, self.arm7_ram, self.arm7_size,
         self.fnt_off, self.fnt_size, self.fat_off, self.fat_size,
         self.ov9_off, self.ov9_size, self.ov7_off,
         self.ov7_size) = struct.unpack_from('<16I', d, 0x20)
        self.banner_off = struct.unpack_from('<I', d, 0x68)[0]
        self.used_size = struct.unpack_from('<I', d, 0x80)[0]
        self.n_overlays = self.ov9_size // 32

    def __repr__(self):
        return ('<NDSHeader %s %r fat=%d entries overlays=%d>'
                % (self.gamecode, self.title, self.fat_size // 8, self.n_overlays))


class Overlay(object):
    """One 32-byte ARM9 overlay table entry."""

    __slots__ = ('id', 'ram_addr', 'ram_size', 'bss_size', 'sinit_start',
                 'sinit_end', 'file_id', 'compressed_size', 'flags')

    def __init__(self, raw):
        (self.id, self.ram_addr, self.ram_size, self.bss_size,
         self.sinit_start, self.sinit_end, self.file_id,
         packed) = struct.unpack_from('<8I', raw, 0)
        self.compressed_size = packed & 0x00FFFFFF
        self.flags = packed >> 24

    @property
    def is_compressed(self):
        """True when the overlay is BLZ-compressed. BLZ is not implemented."""
        return bool(self.flags & 1)

    def __repr__(self):
        return ('<Overlay %d file_id=%d ram=0x%08X size=0x%X flags=0x%02X>'
                % (self.id, self.file_id, self.ram_addr, self.ram_size, self.flags))


class NDS(object):
    """A read-only view of an NDS ROM image with a named file tree.

    ``NDS(path)`` memory-maps the image. ``NDS(path, preload=True)`` reads it
    into memory instead (faster for many small random reads, ~130-290 MB).

    Attributes:
        header     NDSHeader
        fat        list of (start, end) ROM offsets, indexed by file ID
        paths      dict '/full/path' -> file id   (named files only)
        by_id      dict file id -> '/full/path'
        dir_count  number of directories in the FNT
    """

    def __init__(self, path, preload=False):
        self.path = os.fspath(path)
        self._fh = open(self.path, 'rb')
        if preload:
            self.d = self._fh.read()
            self._mm = None
        else:
            self._mm = mmap.mmap(self._fh.fileno(), 0, access=mmap.ACCESS_READ)
            self.d = self._mm
        try:
            self.header = NDSHeader(self.d[:0x200])
        except Exception:
            self.close()
            raise
        h = self.header
        if h.fat_size == 0 or h.fat_off == 0:
            self.close()
            raise NDSError('%s has no FAT - not an NDS ROM?' % self.path)
        self.fat = [struct.unpack_from('<II', self.d, h.fat_off + i * 8)
                    for i in range(h.fat_size // 8)]
        self.paths = {}
        self.by_id = {}
        self.dir_count = 0
        self._walk_fnt()

    # -- lifecycle ---------------------------------------------------------
    def close(self):
        mm = getattr(self, '_mm', None)
        if mm is not None:
            mm.close()
            self._mm = None
        fh = getattr(self, '_fh', None)
        if fh is not None:
            fh.close()
            self._fh = None
        self.d = b''

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
        return False

    def __repr__(self):
        return ('<NDS %s %r %d files (%d named, %d overlays)>'
                % (self.header.gamecode, self.header.title, len(self.fat),
                   len(self.paths), self.header.n_overlays))

    # -- FNT ---------------------------------------------------------------
    def _walk_fnt(self):
        d, base = self.d, self.header.fnt_off
        # Directory 0's "parent" field is the total directory count.
        self.dir_count = struct.unpack_from('<H', d, base + 6)[0]
        dirs = [struct.unpack_from('<IHH', d, base + i * 8)
                for i in range(self.dir_count)]

        def walk(index, prefix, seen):
            if index in seen:                       # malformed/cyclic FNT guard
                return
            seen.add(index)
            sub, fid, _parent = dirs[index]
            p = base + sub
            while True:
                t = d[p]
                p += 1
                if t == 0x00 or t == 0x80:          # end of sub-table
                    break
                ln = t & 0x7F
                name = d[p:p + ln].decode('shift_jis', 'replace')
                p += ln
                full = prefix + '/' + name
                if t < 0x80:
                    self.paths[full] = fid
                    self.by_id[fid] = full
                    fid += 1
                else:
                    sid = struct.unpack_from('<H', d, p)[0]
                    p += 2
                    walk(sid & 0x0FFF, full, seen)

        walk(0, '', set())

    # -- reading -----------------------------------------------------------
    def __contains__(self, path):
        return path in self.paths

    def __len__(self):
        return len(self.fat)

    def size_of(self, path):
        s, e = self.fat[self.paths[path]]
        return e - s

    def size_of_id(self, fid):
        s, e = self.fat[fid]
        return e - s

    def read_id(self, fid):
        """Raw bytes of file ID ``fid``. Empty files return b''."""
        if fid < 0 or fid >= len(self.fat):
            raise KeyError('file id %d out of range (0..%d)' % (fid, len(self.fat) - 1))
        s, e = self.fat[fid]
        return bytes(self.d[s:e])

    def read(self, path):
        """Raw bytes of the named file at ``path`` (e.g. '/data/weather_sys.narc')."""
        try:
            fid = self.paths[path]
        except KeyError:
            raise KeyError('%s: no such file in %s' % (path, self.header.gamecode))
        return self.read_id(fid)

    def listdir(self, prefix=''):
        """Sorted paths under ``prefix`` ('' = every named file)."""
        if prefix and not prefix.endswith('/'):
            prefix += '/'
        return sorted(p for p in self.paths if p.startswith(prefix))

    def find(self, substring):
        """Sorted paths containing ``substring`` - for interactive spelunking."""
        return sorted(p for p in self.paths if substring in p)

    # -- overlays ----------------------------------------------------------
    def overlays(self):
        """Parsed ARM9 overlay table entries."""
        h = self.header
        raw = self.d[h.ov9_off:h.ov9_off + h.ov9_size]
        return [Overlay(raw[i * 32:i * 32 + 32]) for i in range(h.n_overlays)]

    # -- sanity ------------------------------------------------------------
    def check(self):
        """Assert the structural invariants. Returns a dict of the counts."""
        h = self.header
        n_named, n_fat = len(self.paths), len(self.fat)
        if h.n_overlays + n_named != n_fat:
            raise NDSError('FNT/FAT mismatch: %d overlays + %d named != %d FAT entries'
                           % (h.n_overlays, n_named, n_fat))
        if self.paths:
            lowest = min(self.paths.values())
            if lowest != h.n_overlays:
                raise NDSError('lowest named file id %d != overlay count %d'
                               % (lowest, h.n_overlays))
        return dict(gamecode=h.gamecode, fat_entries=n_fat, named_files=n_named,
                    overlays=h.n_overlays, dirs=self.dir_count,
                    used_size=h.used_size, capacity=h.capacity)
