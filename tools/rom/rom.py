# -*- coding: utf-8 -*-
"""Thin facade: open one of the project's ROMs by nickname and pull files out.

    from tools.rom import open_rom
    pt = open_rom('platinum')
    enc = pt.narc('/fielddata/encountdata/pl_enc_data.narc')   # cached NARC
    raw = pt.read('/poketool/personal/pl_personal.narc')       # raw bytes

The ROMs are the owner's own dumps under ``References/Roms/`` and are never
committed; neither is anything extracted from them. Set
``PROJECT_PLATINUM_ROMS`` to point the loader at a different directory.

Nicknames: ``platinum`` (CPUE), ``heartgold`` (IPKE), ``black`` (IRBO),
``white2`` (IRDO). ``diamond``/``pearl`` are not separate ROMs - Platinum ships
the Diamond/Pearl sprite archive at ``/poketool/pokegra/pokegra.narc``.
"""

import os

from .narc import NARC
from .ndsfs import NDS

__all__ = ['RomNotFound', 'Rom', 'open_rom', 'roms_dir', 'repo_root',
           'available', 'ROMS', 'PATHS']

#: nickname -> (path under the ROM directory, expected game code)
ROMS = {
    'platinum':  ('Platinum/3541 - Pokemon Platinum Version (US)(XenoPhobia).nds', 'CPUE'),
    'heartgold': ('Heartgold/4780 - Pokemon HeartGold (U)(Xenophobia).nds', 'IPKE'),
    'black':     ('Black/5585 - Pokemon - Black Version (DSi Enhanced)(USA) (E)(SweeTnDs).nds', 'IRBO'),
    'white2':    ('White 2/Pokemon White 2 (Experience + Trade Evolution Patched).nds', 'IRDO'),
}

#: Frequently used in-ROM paths, so callers stop retyping them.
#: See docs/research/platinum-data.md and gen5-assets.md for the full tables.
PATHS = {
    'platinum': {
        'encounters':    '/fielddata/encountdata/pl_enc_data.narc',
        'encounters_ex': '/arc/encdata_ex.narc',
        'trainer_data':  '/poketool/trainer/trdata.narc',
        'trainer_party': '/poketool/trainer/trpoke.narc',
        'personal':      '/poketool/personal/pl_personal.narc',
        'learnsets':     '/poketool/personal/wotbl.narc',
        'evolutions':    '/poketool/personal/evo.narc',
        'moves':         '/poketool/waza/pl_waza_tbl.narc',
        'items':         '/itemtool/itemdata/pl_item_data.narc',
        'text':          '/msgdata/pl_msg.narc',
        'pokegra':       '/poketool/pokegra/pl_pokegra.narc',
        'pokegra_dp':    '/poketool/pokegra/pokegra.narc',
        'otherpoke':     '/poketool/pokegra/pl_otherpoke.narc',
        'icons':         '/poketool/icongra/pl_poke_icon.narc',
        'trainer_gfx':   '/poketool/trgra/trfgra.narc',
        'map_textures':  '/fielddata/areadata/area_map_tex/map_tex_set.narc',
        'prop_textures': '/fielddata/areadata/area_build_model/areabm_texset.narc',
        'area_data':     '/fielddata/areadata/area_data.narc',
        'land_data':     '/fielddata/land_data/land_data.narc',
        'map_matrix':    '/fielddata/mapmatrix/map_matrix.narc',
        'zone_event':    '/fielddata/eventdata/zone_event.narc',
        'scripts':       '/fielddata/script/scr_seq.narc',
    },
    'heartgold': {
        'pokegra':       '/a/0/0/4',
        'pokegra_named': '/pbr/pokegra.narc',
        'map_textures':  '/a/0/4/4',
    },
    'white2': {
        'pokegra':       '/a/0/0/4',       # 15065 sub-files, 20 per form
        'pokegra_bw':    '/a/0/5/1',
        'icons':         '/a/0/0/7',
        'map_textures':  '/a/0/1/4',       # the main tileset source
        'exterior_tex':  '/a/1/7/4',
        'interior_tex':  '/a/1/7/5',
        'object_tex':    '/a/0/4/8',
    },
    'black': {
        'pokegra':       '/a/0/0/4',       # 14285 sub-files
        'icons':         '/a/0/0/7',
        'map_textures':  '/a/0/1/4',
    },
}


class RomNotFound(IOError):
    """Raised when a ROM nickname cannot be resolved to a readable file."""


def repo_root(start=None):
    """Walk up from this file (or ``start``) to the project root."""
    p = os.path.abspath(start or __file__)
    if os.path.isfile(p):
        p = os.path.dirname(p)
    while True:
        if os.path.isfile(os.path.join(p, 'project.godot')):
            return p
        parent = os.path.dirname(p)
        if parent == p:
            # Fall back to tools/rom/../.. so the library still works if moved.
            return os.path.abspath(os.path.join(os.path.dirname(__file__), '..', '..'))
        p = parent


def roms_dir():
    """Directory holding the ROM sub-folders. ``PROJECT_PLATINUM_ROMS`` overrides."""
    env = os.environ.get('PROJECT_PLATINUM_ROMS')
    if env:
        return env
    return os.path.join(repo_root(), 'References', 'Roms')


def rom_path(nickname):
    """Absolute path to the ROM file for ``nickname``."""
    key = nickname.lower().replace(' ', '').replace('_', '')
    if key not in ROMS:
        raise RomNotFound('unknown ROM nickname %r (known: %s)'
                          % (nickname, ', '.join(sorted(ROMS))))
    rel, _code = ROMS[key]
    path = os.path.join(roms_dir(), rel.replace('/', os.sep))
    if not os.path.isfile(path):
        raise RomNotFound('%s: no such file.\nExpected the owner\'s own dump at this '
                          'path, or set PROJECT_PLATINUM_ROMS.' % path)
    return path


def available():
    """Nicknames whose ROM file is actually present, sorted."""
    out = []
    for k in sorted(ROMS):
        try:
            rom_path(k)
        except RomNotFound:
            continue
        out.append(k)
    return out


class Rom(object):
    """An open ROM: file tree plus a NARC cache.

    Attributes:
        name    the nickname it was opened with
        fs      the underlying :class:`tools.rom.ndsfs.NDS`
    """

    def __init__(self, nickname, path=None, preload=False, check_gamecode=True):
        key = nickname.lower().replace(' ', '').replace('_', '')
        self.name = key
        self.path = path or rom_path(key)
        self.fs = NDS(self.path, preload=preload)
        expected = ROMS.get(key, (None, None))[1]
        if check_gamecode and expected and self.fs.header.gamecode != expected:
            got = self.fs.header.gamecode
            self.close()
            raise RomNotFound('%s is game code %r, expected %r for %r'
                              % (self.path, got, expected, key))
        self._narcs = {}

    # -- lifecycle ---------------------------------------------------------
    def close(self):
        self._narcs = {}
        fs = getattr(self, 'fs', None)
        if fs is not None:
            fs.close()

    def __enter__(self):
        return self

    def __exit__(self, *exc):
        self.close()
        return False

    def __repr__(self):
        h = self.fs.header
        return ('<Rom %s %s %d files (%d named)>'
                % (self.name, h.gamecode, len(self.fs.fat), len(self.fs.paths)))

    # -- access ------------------------------------------------------------
    @property
    def header(self):
        return self.fs.header

    @property
    def gamecode(self):
        return self.fs.header.gamecode

    def resolve(self, path_or_key):
        """Map a PATHS nickname ('encounters') to its in-ROM path; pass '/...' through."""
        if path_or_key.startswith('/'):
            return path_or_key
        table = PATHS.get(self.name, {})
        if path_or_key not in table:
            raise KeyError('%r is not a known key for %s (known: %s)'
                           % (path_or_key, self.name, ', '.join(sorted(table))))
        return table[path_or_key]

    def read(self, path_or_key):
        """Raw bytes of a file, by in-ROM path or PATHS nickname."""
        return self.fs.read(self.resolve(path_or_key))

    def narc(self, path_or_key):
        """Open (and cache) the NARC at a path or PATHS nickname."""
        path = self.resolve(path_or_key)
        n = self._narcs.get(path)
        if n is None:
            n = NARC(self.fs.read(path))
            self._narcs[path] = n
        return n

    def find(self, substring):
        return self.fs.find(substring)

    def listdir(self, prefix=''):
        return self.fs.listdir(prefix)

    def check(self):
        return self.fs.check()


_OPEN = {}


def open_rom(nickname, preload=False, cache=True):
    """Open a ROM by nickname, reusing an already-open handle by default."""
    key = nickname.lower().replace(' ', '').replace('_', '')
    if cache and key in _OPEN:
        return _OPEN[key]
    r = Rom(key, preload=preload)
    if cache:
        _OPEN[key] = r
    return r
