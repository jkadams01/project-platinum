# -*- coding: utf-8 -*-
"""Content tests for tools/rom against the owner's own ROM dumps.

These are not smoke tests. Every assertion checks a value that would change if
the parser were wrong: exact FAT entry counts, exact sub-file counts, exact
pixel dimensions, the XOR self-check halfword, and the NSBTX name-vs-index
palette binding.

Run with pytest::

    source tools/_work/gen5/env.sh        # PIL needs the Anaconda DLLs on PATH
    python -m pytest tests/test_rom.py -v

or standalone (no pytest needed)::

    python tests/test_rom.py

If the ROMs are missing the ROM-backed tests skip rather than fail; the pure
algorithm tests always run.
"""

import os
import sys

_ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
if _ROOT not in sys.path:
    sys.path.insert(0, _ROOT)

from tools.rom import (NARC, NCGR, NCLR, NCER, NANR, NSCR, TEX0, auto_decrypt,
                       bgr555_to_rgb, decompress_lz10, decompress_lz11,
                       gen5_assemble, magic_of, maybe_decompress, nibble_entropy,
                       open_rom, resolve_palettes, unpack_indices, untile,
                       xor_lcg)
from tools.rom.rom import RomNotFound

# --------------------------------------------------------------------------
# ROM fixtures. Opened lazily and cached; skip cleanly when a dump is absent.
# --------------------------------------------------------------------------
_MISSING = {}


def _rom(name):
    try:
        return open_rom(name)
    except RomNotFound as e:
        _MISSING[name] = str(e)
        try:
            import pytest
            pytest.skip('%s ROM not available: %s' % (name, e))
        except ImportError:
            raise SystemExit('%s ROM not available: %s' % (name, e))


PL_ENC = '/fielddata/encountdata/pl_enc_data.narc'


# --------------------------------------------------------------------------
# 1. NDS filesystem
# --------------------------------------------------------------------------
def test_platinum_fnt_walk_yields_462_fat_entries():
    pt = _rom('platinum')
    assert pt.gamecode == 'CPUE'
    info = pt.check()                       # asserts overlays + named == FAT
    assert info['fat_entries'] == 462, info
    assert info['named_files'] == 340, info
    assert info['overlays'] == 122, info
    assert info['dirs'] == 89, info
    assert len(pt.fs.fat) == 462
    # The walk must produce this exact path, not merely 462 anonymous entries.
    assert PL_ENC in pt.fs, 'FNT walk did not produce %s' % PL_ENC
    assert min(pt.fs.paths.values()) == 122, 'first named file id must equal overlay count'


def test_platinum_header_fields():
    pt = _rom('platinum')
    h = pt.header
    assert h.title == 'POKEMON PL', repr(h.title)
    assert h.gamecode == 'CPUE'
    assert h.fnt_off == 0x431000 and h.fat_off == 0x432C00, (hex(h.fnt_off), hex(h.fat_off))
    assert h.n_overlays == 122
    # The file on disk is larger than the ROM: never use the file length.
    assert h.used_size == 104607804, h.used_size
    assert h.capacity == 134217728, h.capacity
    assert h.used_size < os.path.getsize(pt.path)


def test_white2_fnt_walk():
    w2 = _rom('white2')
    info = w2.check()
    assert info['gamecode'] == 'IRDO', info
    assert info['fat_entries'] == 662, info
    assert info['named_files'] == 318, info
    assert info['overlays'] == 344, info
    assert '/a/0/0/4' in w2.fs and '/a/0/1/4' in w2.fs


def test_overlay_table_ids_match_indices():
    pt = _rom('platinum')
    ovs = pt.fs.overlays()
    assert len(ovs) == 122
    for i, o in enumerate(ovs):
        assert o.id == i and o.file_id == i, (i, o.id, o.file_id)
    assert not any(o.is_compressed for o in ovs), 'Platinum ships overlays uncompressed'


# --------------------------------------------------------------------------
# 2. NARC
# --------------------------------------------------------------------------
def test_pl_enc_data_narc_opens_with_a_plausible_subfile_count():
    pt = _rom('platinum')
    n = pt.narc(PL_ENC)
    assert isinstance(n, NARC)
    assert len(n) == 183, 'expected 183 Platinum encounter tables, got %d' % len(n)
    # Every entry is the documented fixed 424-byte record.
    sizes = set(n.sizes())
    assert sizes == {424}, sorted(sizes)
    assert n.chunks[b'BTAF'][0] == 16, n.chunks
    assert set(n.chunks) == {b'BTAF', b'BTNF', b'GMIF'}, sorted(n.chunks)


def test_narc_subfile_count_is_read_at_plus_8_not_plus_6():
    """The +0x06 misreading yields 0 for pl_pokegra and 1 for White 2 /a/0/0/4."""
    import struct
    pt = _rom('platinum')
    pg = pt.narc('pokegra')
    assert len(pg) == 2964, len(pg)
    bo = pg.chunks[b'BTAF'][0]
    wrong = struct.unpack_from('<H', pg.data, bo + 6)[0]
    assert wrong != len(pg), 'the +0x06 trap no longer reproduces - check the test'
    w2 = _rom('white2')
    assert len(w2.narc('/a/0/0/4')) == 15065


def test_narc_empty_subfiles_are_legal():
    pt = _rom('platinum')
    pg = pt.narc('pokegra')
    # Genderless species leave the female slots (+0, +2) empty.
    empties = [i for i in range(0, 600) if pg.is_empty(i)]
    assert empties, 'expected empty sub-files in pl_pokegra'
    for i in empties:
        assert pg[i] == b''


def test_narc_magics_and_transparent_decompression():
    pt = _rom('platinum')
    cb = pt.narc('/application/custom_ball/data/cb_data.narc')
    raw = cb[0]
    assert raw[0] == 0x10, 'cb_data[0] should be LZ10-compressed'
    out = cb.get(0)
    assert len(raw) == 92 and len(out) == 111, (len(raw), len(out))
    assert magic_of(out) == 'RNAN', magic_of(out)


# --------------------------------------------------------------------------
# 3. Compression
# --------------------------------------------------------------------------
def test_lz11_decodes_every_compressed_subfile_in_a_gen5_sprite_block():
    w2 = _rom('white2')
    g5 = w2.narc('/a/0/0/4')
    checked = 0
    for i in (0, 2, 5, 20, 22, 25):
        raw = g5[i]
        if not raw or raw[0] != 0x11:
            continue
        declared = raw[1] | (raw[2] << 8) | (raw[3] << 16)
        out = decompress_lz11(raw)
        assert len(out) == declared, (i, len(out), declared)
        assert magic_of(out) in ('RGCN', 'RLCN', 'RNAN', 'RECN', 'RCMN', 'RAMN'), \
            (i, magic_of(out))
        checked += 1
    assert checked >= 3, 'expected several LZ11 sub-files in /a/0/0/4'


def test_maybe_decompress_rejects_first_byte_false_positives():
    """A blob starting 0x10 whose declared length does not check out is left alone."""
    fake = b'\x10\x40\x00\x00' + b'\xFF' * 8      # claims 64 bytes, cannot produce them
    assert maybe_decompress(fake) == fake
    assert maybe_decompress(b'RGCN\xff\xfe') == b'RGCN\xff\xfe'
    assert maybe_decompress(b'') == b''


def test_lz10_back_references_overlap():
    """A run encoded as a self-overlapping copy must expand byte-at-a-time."""
    # header: LZ10, 8 bytes out. flags 0x40 -> literal 'A', then a copy of
    # length 7 at displacement 1, which reads bytes it is still writing.
    blob = bytes([0x10, 8, 0, 0, 0x40, ord('A'), 0x40, 0x00])
    assert decompress_lz10(blob) == b'A' * 8


# --------------------------------------------------------------------------
# 4. Nitro graphics
# --------------------------------------------------------------------------
def test_known_nclr_decodes_to_16_colours():
    pt = _rom('platinum')
    pg = pt.narc('pokegra')
    nclr = NCLR(pg[10])                     # Bulbasaur normal palette, 72 bytes
    assert len(pg[10]) == 72, len(pg[10])
    assert len(nclr.colors) == 16, len(nclr.colors)
    assert len(set(nclr.colors)) > 1, 'a 16-colour palette of one colour is a parse failure'
    # The depth field LIES here: it declares 8bpp (4) yet holds 16 colours.
    assert nclr.depth == 4, nclr.depth
    assert nclr.datasize == 32, nclr.datasize
    for c in nclr.colors:
        assert len(c) == 3 and all(0 <= v <= 255 for v in c), c
    # Exact first colour, byte-for-byte: raw u16 0x5B59 -> BGR555.
    assert nclr.colors[0] == bgr555_to_rgb(0x5B59), nclr.colors[0]
    assert nclr.colors[1] == (255, 255, 255), nclr.colors[1]   # 0x7FFF, not (248,248,248)


def test_bgr555_rounding_keeps_white_at_255():
    assert bgr555_to_rgb(0x7FFF) == (255, 255, 255)
    assert bgr555_to_rgb(0x0000) == (0, 0, 0)


def test_gen4_battle_sprite_is_160x80_linear_and_forward_encrypted():
    pt = _rom('platinum')
    pg = pt.narc('pokegra')
    for species in (1, 4, 25, 448):
        g = NCGR(pg[species * 6 + 3])       # front, male
        assert (g.tiles_x, g.tiles_y) == (20, 10), (species, g.tiles_x, g.tiles_y)
        assert g.bpp == 4 and g.linear, (species, g.bpp, g.linear)
        assert g.declared_size == 0x1900 and len(g.data) == 0x1900, g.declared_size
        data, mode = auto_decrypt(g.data)
        assert mode == 'forward', (species, mode)
        # The seed IS the first halfword, so it always decodes to 0x0000.
        assert data[0] == 0 and data[1] == 0, (species, data[:2])
        assert nibble_entropy(data) < 3.6, nibble_entropy(data)
        w, h = g.dimensions()
        assert (w, h) == (160, 80), (w, h)
        px = unpack_indices(data, g.bpp)
        assert len(px) == w * h, (len(px), w * h)
        assert len(set(px)) > 4, 'a real sprite uses more than 4 palette indices'


def test_dp_sprite_archive_uses_the_backward_xor_direction():
    """Platinum ships pl_pokegra (forward) and pokegra (backward) side by side."""
    pt = _rom('platinum')
    dp = pt.narc('pokegra_dp')
    g = NCGR(dp[1 * 6 + 3])
    data, mode = auto_decrypt(g.data)
    assert mode == 'backward', mode
    assert data[-2] == 0 and data[-1] == 0, data[-2:]


def test_xor_lcg_round_trips_with_an_explicit_seed():
    """The XOR is NOT self-inverse with a derived seed - see nitrogfx.xor_lcg.

    docs/research/nds-formats.md 5.1.1 says "encryption is the *same function*
    ... because the seeding halfword decrypts to 0 and re-encrypts to itself".
    That is wrong: decryption zeroes the seeding halfword, so a second
    derived-seed pass runs a keystream from seed 0. Re-encrypting needs the
    original seed passed in.
    """
    import struct
    pt = _rom('platinum')
    cipher = bytes(NCGR(pt.narc('pokegra')[1 * 6 + 3]).data)
    seed = struct.unpack_from('<H', cipher, 0)[0]
    plain = xor_lcg(cipher, False)
    assert plain[:2] == b'\x00\x00'
    assert bytes(xor_lcg(plain, False)) != cipher, 'the doc claim would make this equal'
    assert bytes(xor_lcg(plain, False, seed=seed)) == cipher


def test_gen5_sprite_is_a_144_char_12x12_block_and_assembles_via_four_oam_objects():
    w2 = _rom('white2')
    g5 = w2.narc('/a/0/0/4')
    for form in (1, 4, 25, 448, 643):
        base = form * 20
        g = NCGR(g5.get(base))
        assert (g.tiles_x, g.tiles_y) == (12, 12), (form, g.tiles_x, g.tiles_y)
        assert g.bpp == 4 and not g.linear, (form, g.bpp, g.linear)
        assert g.n_tiles == 144, (form, g.n_tiles)
        # Gen 5 sprites are NOT obfuscated - the XOR would destroy them.
        assert nibble_entropy(g.data) < 3.6, nibble_entropy(g.data)
        _d, mode = auto_decrypt(g.data)
        assert mode == 'plain', (form, mode)
        px = unpack_indices(g.data, g.bpp)
        assert len(px) == 96 * 96, len(px)
        good = gen5_assemble(px)
        bad = untile(list(px), 96, 96)
        assert len(good) == 96 * 96
        assert good != bad, 'gen5_assemble must not equal a plain 96-wide untile'
        # Content check: the sprite is centred art on a transparent field, so
        # the canvas border is index 0 while the middle is not.
        border = [good[x] for x in range(96)] + [good[95 * 96 + x] for x in range(96)]
        assert set(border) == {0}, (form, 'top/bottom rows should be transparent')
        mid = good[48 * 96 + 24: 48 * 96 + 72]
        assert any(v != 0 for v in mid), (form, 'mid-row should contain the sprite')
        pal = NCLR(g5.get(base + 18))
        assert len(pal.colors) == 16, (form, len(pal.colors))


def test_gen5_assemble_places_the_four_objects_where_the_layout_says():
    """Synthetic check of the object order: 64x64, 32x64, 0/64 64x32, 64/64 32x32."""
    # Give every char a distinct value per object so we can see where it landed.
    px = []
    for obj, nchars in enumerate((64, 32, 32, 16)):
        px += [obj + 1] * (nchars * 64)
    out = gen5_assemble(px)
    assert out[0 * 96 + 0] == 1           # object 1 at (0,0)
    assert out[0 * 96 + 64] == 2          # object 2 at (64,0)
    assert out[64 * 96 + 0] == 3          # object 3 at (0,64)
    assert out[64 * 96 + 64] == 4         # object 4 at (64,64)
    assert out[63 * 96 + 63] == 1
    assert out[95 * 96 + 95] == 4


def test_nscr_and_ncgr_compose_the_poketch_background():
    pt = _rom('platinum')
    pk = pt.narc('/graphic/poketch.narc')
    s = NSCR(pk.get(11))
    g = NCGR(pk.get(10))
    assert (s.width, s.height) == (256, 192), (s.width, s.height)
    assert len(s.entries) == (256 // 8) * (192 // 8) == 768, len(s.entries)
    assert g.bpp == 4
    from tools.rom import render_screen
    img = render_screen(s, g, NCLR(pk.get(9)))
    assert img.size == (256, 192)
    assert len(img.getcolors(maxcolors=4096)) > 1, 'a blank background is a parse failure'


def test_ncer_and_nanr_parse_with_the_documented_values():
    pt = _rom('platinum')
    ic = pt.narc('icons')
    cer = NCER(ic[2])
    assert cer.n_cells == 2, cer.n_cells
    assert cer.extended, 'pl_poke_icon[2] uses 16-byte extended cells'
    assert cer.mapping_mode == 0, cer.mapping_mode
    assert cer.cells[0]['bounds'] == (-16, -16, 15, 15), cer.cells[0]['bounds']
    assert len(cer.cells[0]['oam']) == 1
    anr = NANR(ic[1])
    assert len(anr.sequences) == 2, len(anr.sequences)
    seq = anr.sequences[0]
    assert seq['elem_type'] == 0, seq['elem_type']
    assert seq['frames'][0]['raw'] == (0, 0xCCCC), seq['frames'][0]['raw']


def test_ncgr_section_clamping_survives_a_lying_header():
    """Gen 5 sprite NCGRs declare a filesize larger than the bytes they ship."""
    import struct
    w2 = _rom('white2')
    blob = w2.narc('/a/0/0/4').get(20)
    declared_file = struct.unpack_from('<I', blob, 8)[0]
    assert declared_file > len(blob), (declared_file, len(blob))
    g = NCGR(blob)
    assert len(g.data) == g.declared_size == 0x1200, (len(g.data), g.declared_size)
    assert 0x30 + 0x1200 == len(blob) == 4656, len(blob)


# --------------------------------------------------------------------------
# 5. NSBTX - the palette binding bug
# --------------------------------------------------------------------------
def test_nsbtx_binds_gake01a_by_name_not_by_index():
    """THE regression test for the NSBTX palette bug.

    TEX0 stores textures and palettes in two separately name-sorted
    dictionaries. In White 2 /a/0/1/4 entry 0, texture 3 is 'gake01a' but
    palette 3 is 'gake01a2_pl'. The palette it wants is index 4, 'gake01a_pl'.
    """
    w2 = _rom('white2')
    t = TEX0(w2.narc('/a/0/1/4')[0])
    assert len(t.tex_names) == 76 and len(t.pal_names) == 76, (len(t.tex_names),
                                                               len(t.pal_names))
    i = t.index_of('gake01a')
    assert i == 3, 'texture gake01a should be at index 3, got %d' % i
    # The trap: the palette at the SAME index is a different texture's palette.
    assert t.pal_names[3] == 'gake01a2_pl', t.pal_names[3]
    # The fix: bound by name.
    assert t.palette_name_for('gake01a') == 'gake01a_pl', t.palette_name_for('gake01a')
    assert t.palette_index_for('gake01a') == 4, t.palette_index_for('gake01a')
    assert t.palette_index_for('gake01a') != i
    # And decode() must use it without being asked.
    p = t.tex_param(i)
    assert (p['w'], p['h'], p['fmtname']) == (16, 16, 'PAL16'), p
    img = t.decode('gake01a')
    assert img.shape == (16, 16, 4), img.shape
    assert img[:, :, 3].max() > 0, 'fully transparent decode is a failure'


def test_nsbtx_name_binding_differs_from_index_binding_on_real_data():
    """Index-binding is wrong for ~8% of texture slots and visibly so for ~6%."""
    w2 = _rom('white2')
    narc = w2.narc('/a/0/1/4')
    slots = differ = pixels_differ = 0
    for e in range(20):
        try:
            t = TEX0(narc[e])
        except Exception:
            continue
        for i in range(len(t)):
            slots += 1
            by_index = min(i, len(t.pal_names) - 1)
            if t.pal_index[i] == by_index:
                continue
            differ += 1
            try:
                a = t.decode(i)
                b = t.decode(i, pal_index=by_index)
            except Exception:
                continue
            if a.tobytes() != b.tobytes():
                pixels_differ += 1
    assert slots > 1000, slots
    assert differ > 50, 'expected many index/name disagreements, got %d/%d' % (differ, slots)
    assert pixels_differ > 20, ('expected index-binding to change pixels, got %d'
                                % pixels_differ)


def test_nsbtx_every_texture_in_entry_0_binds_by_exact_name():
    w2 = _rom('white2')
    t = TEX0(w2.narc('/a/0/1/4')[0])
    assert t.pal_stats.get('pal_by_name') == 76, t.pal_stats
    assert 'pal_by_index_guess' not in t.pal_stats, t.pal_stats
    for i, name in enumerate(t.tex_names):
        assert t.pal_names[t.pal_index[i]] in (name + '_pl', name), (name,
                                                                     t.pal_names[t.pal_index[i]])


def test_resolve_palettes_fallback_chain():
    """Pure-function check of the four passes, no ROM needed."""
    # 1. '<tex>_pl'  2. exact  3. affix  4. leftover
    tex = ['a', 'b', 'h04_stair', 'zzz']
    pal = ['b', 'stair', 'a_pl', 'leftover_pl']
    out = resolve_palettes(tex, pal)
    assert pal[out[0]] == 'a_pl', out
    assert pal[out[1]] == 'b', out
    assert pal[out[2]] == 'stair', out          # affix match, not index 2
    assert pal[out[3]] == 'leftover_pl', out
    assert resolve_palettes(['x'], []) == [None]


def test_nsbtx_decodes_a_whole_texture_bank_without_falling_back_to_index():
    w2 = _rom('white2')
    narc = w2.narc('/a/0/1/4')
    decoded = guesses = 0
    for e in range(10):
        try:
            t = TEX0(narc[e])
        except Exception:
            continue
        guesses += t.pal_stats.get('pal_by_index_guess', 0)
        for i in range(len(t)):
            t.decode(i)
            decoded += 1
    assert decoded > 500, decoded
    assert guesses == 0, 'name binding fell through to an index guess %d times' % guesses


# --------------------------------------------------------------------------
# 6. The facade
# --------------------------------------------------------------------------
def test_facade_resolves_nicknames_and_caches_narcs():
    pt = _rom('platinum')
    assert pt.resolve('encounters') == PL_ENC
    assert pt.resolve('/arc/encdata_ex.narc') == '/arc/encdata_ex.narc'
    assert pt.narc('encounters') is pt.narc(PL_ENC), 'NARC cache should hand back one object'
    assert len(pt.find('pokegra')) >= 3, pt.find('pokegra')
    try:
        pt.resolve('no_such_key')
    except KeyError:
        pass
    else:
        raise AssertionError('resolve() should raise on an unknown key')


def test_unknown_rom_nickname_raises():
    try:
        open_rom('emerald')
    except RomNotFound:
        pass
    else:
        raise AssertionError('open_rom should reject an unknown nickname')


# --------------------------------------------------------------------------
def _main():
    fns = [(n, o) for n, o in sorted(globals().items())
           if n.startswith('test_') and callable(o)]
    failed = []
    for name, fn in fns:
        try:
            fn()
        except SystemExit as e:
            print('SKIP %-64s %s' % (name, e))
            continue
        except Exception as e:
            failed.append((name, e))
            print('FAIL %-64s %s: %s' % (name, type(e).__name__, e))
            continue
        print('ok   %s' % name)
    print('\n%d/%d passed' % (len(fns) - len(failed), len(fns)))
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(_main())
