# -*- coding: utf-8 -*-
"""tools.rom - production ROM-reading library for project-platinum.

Read-only. Nothing in here writes to a ROM, and nothing it produces may be
committed: ROM-derived output belongs in ``assets/generated/`` or ``data/rom/``,
both gitignored.

    from tools.rom import open_rom, NARC, NCGR, NCLR, TEX0
    pt = open_rom('platinum')
    enc = pt.narc('encounters')

Modules:
    ndsfs      NDS header / FAT / FNT -> a named file tree
    narc       NARC (BTAF / BTNF / GMIF) sub-file archive
    lz         LZ10 / LZ11 / RLE / difference filter
    nitrogfx   NCLR / NCGR / NSCR / NCER / NANR -> RGBA, plus the Gen 4/5 sprite XOR
    nsbtx      TEX0 texture banks -> RGBA, with NAME-BASED palette binding
    rom        the facade above

See tools/rom/README.md, and docs/research/nds-formats.md for the verified
byte-level reference this library implements.
"""

from .lz import (CompressionError, decompress, decompress_lz10, decompress_lz11,
                 decompress_rle, decompress_diff, maybe_decompress, looks_compressed)
from .narc import NARC, NARCError, magic_of
from .ndsfs import NDS, NDSError, NDSHeader, Overlay
from .nitrogfx import (NCLR, NCGR, NSCR, NCER, NANR, NitroError, auto_decrypt,
                       bgr555_to_rgb, compose_cell, decode_oam, gen5_assemble,
                       indices_to_rgba, nibble_entropy, render_screen, save_png,
                       sections, unpack_indices, unpack_screen_entry, untile,
                       xor_lcg)
from .nsbtx import TEX0, TEX0Error, resolve_palettes
from .rom import PATHS, ROMS, Rom, RomNotFound, available, open_rom, roms_dir

__version__ = '1.0.0'

__all__ = [
    'NDS', 'NDSError', 'NDSHeader', 'Overlay',
    'NARC', 'NARCError', 'magic_of',
    'CompressionError', 'decompress', 'decompress_lz10', 'decompress_lz11',
    'decompress_rle', 'decompress_diff', 'maybe_decompress', 'looks_compressed',
    'NCLR', 'NCGR', 'NSCR', 'NCER', 'NANR', 'NitroError', 'sections',
    'bgr555_to_rgb', 'unpack_indices', 'untile', 'gen5_assemble',
    'unpack_screen_entry', 'decode_oam', 'xor_lcg', 'nibble_entropy',
    'auto_decrypt', 'render_screen', 'compose_cell', 'indices_to_rgba', 'save_png',
    'TEX0', 'TEX0Error', 'resolve_palettes',
    'Rom', 'RomNotFound', 'open_rom', 'roms_dir', 'available', 'ROMS', 'PATHS',
]
