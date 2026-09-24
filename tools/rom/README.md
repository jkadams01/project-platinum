# `tools/rom` — the production ROM-reading library

Read-only access to the owner's own NDS dumps. Everything here implements the
byte-level reference in [`docs/research/nds-formats.md`](../../docs/research/nds-formats.md),
which was verified against real ROM bytes; this library is the promoted,
hardened version of the throwaway code in `tools/_work/`.

**Nothing this library produces may be committed.** ROM-derived output goes to
`assets/generated/` or `data/rom/`, both gitignored. Check with
`git check-ignore -v <path>` before writing a new output directory.

```python
from tools.rom import open_rom, NCGR, NCLR, TEX0, auto_decrypt, gen5_assemble

pt  = open_rom('platinum')          # 'platinum' | 'heartgold' | 'black' | 'white2'
enc = pt.narc('encounters')         # cached NARC, 183 sub-files
raw = pt.read('/poketool/personal/pl_personal.narc')
```

Requires `numpy` for NSBTX decoding and `PIL` for image output. **PIL fails
under Git Bash here unless you first run**
`source tools/_work/gen5/env.sh` (it puts the Anaconda DLL directories on
`PATH`).

Tests: `python -m pytest tests/test_rom.py -v`, or `python tests/test_rom.py`
with no pytest. They assert on content — exact FAT counts, exact sub-file
counts, exact pixel dimensions, the XOR self-check halfword, the palette
binding — not on "it didn't throw".

---

## `rom.py` — the facade

`open_rom(nickname)` resolves a ROM under `References/Roms/` (override with
`PROJECT_PLATINUM_ROMS`), checks its game code, and returns a `Rom`:

| | |
|---|---|
| `rom.fs` | the underlying `NDS` |
| `rom.read(path_or_key)` | raw bytes |
| `rom.narc(path_or_key)` | opened and **cached** `NARC` |
| `rom.find(substr)`, `rom.listdir(prefix)` | spelunking |
| `rom.check()` | structural invariants, returns the counts |

`path_or_key` accepts either an in-ROM path (`/fielddata/...`) or a nickname
from `PATHS[game]` (`'encounters'`, `'pokegra'`, `'map_textures'`, …), so the
long Gen 5 `/a/x/y/z` paths only have to be right in one place.

`ROMS` maps nickname → (file, expected game code): `platinum` CPUE,
`heartgold` IPKE, `black` IRBO, `white2` IRDO. Diamond/Pearl is not a separate
ROM — Platinum ships the DP sprite archive at
`/poketool/pokegra/pokegra.narc`.

## `ndsfs.py` — NDS cartridge

A `.nds` image is a 0x200-byte header, then ARM binaries, an overlay table, a
**FAT** (flat array of `(start, end)` ROM offsets, 8 bytes per file ID) and an
**FNT** (a directory table plus one name sub-table per directory). Walking the
FNT assigns the *named* file IDs and their paths.

`NDS(path)` memory-maps the image (`preload=True` reads it instead) and exposes
`header`, `fat`, `paths`, `by_id`, `overlays()` and `check()`.

Invariant, asserted by `check()`: `n_overlays + len(named files) == len(fat)`.
Platinum `122 + 340 == 462`; White 2 `344 + 318 == 662`. Overlays occupy file
IDs `0 .. n_overlays-1`, so the first *named* file ID equals the overlay count.

Traps handled: directory IDs are `0xF000 | index`; directory 0's "parent" field
is really the directory count; an empty file is legal (`start == end`); and the
file on disk is longer than the ROM — header `+0x80` (`used_size`) is the
length, never `os.path.getsize`.

## `narc.py` — Nitro ARChive

Every Gen 4 `.narc` and nearly every Gen 5 `/a/x/y/z` is a NARC: a 16-byte
header then exactly three chunks — `BTAF` (sub-file allocation), `BTNF` (names)
and `GMIF` (the image; BTAF offsets are relative to its payload). The reversed
spellings `FATB`/`FNTB`/`FIMG` are accepted too.

`NARC(bytes)` is indexable and iterable. `narc[i]` is raw; `narc.get(i)` is
transparently LZ-decompressed; `is_empty(i)`, `sizes()` and `magics()` round it
out.

Traps handled: **the sub-file count is at +0x08, not +0x06** (reading +0x06
silently yields 0 for `pl_pokegra`); **sub-file names do not exist** — 0 of
Platinum's 340 NARCs ship a name table, so address by index; and **empty
sub-files are normal** (Gen 4 female sprite slots, Gen 5 slots +1/+3).

## `lz.py` — BIOS compression

Header: type byte, then a 24-bit little-endian decompressed size (0 ⇒ an
extended 32-bit size follows and the payload starts at +8).

| | |
|---|---|
| `0x10` | LZ10 — implemented |
| `0x11` | LZ11 (extended lengths) — implemented |
| `0x30` | RLE — implemented, **UNVERIFIED**: no real asset in these ROMs uses it |
| `0x80/0x81` | difference filter — implemented |
| `0x20/24/28` | Huffman — **not implemented**, nothing needs it |
| overlay flag bit 0 | BLZ (backwards LZ) — **not implemented**, code only, no asset uses it |

`decompress(d)` dispatches and raises `CompressionError` on a bad stream.
`maybe_decompress(d)` is the one to use on an archive sub-file: it validates the
decoded length against the declared length, which is what rejects the ~5% of
sub-files whose leading byte merely coincides with `0x10`/`0x11`.

Trap handled: LZ back-references deliberately overlap the output written so
far, so the copy is byte-at-a-time. A slice copy silently corrupts runs.

## `nitrogfx.py` — NCLR / NCGR / NSCR / NCER / NANR

All share a 16-byte container header plus sections. **Magics are byte-reversed
on disk** — an NCLR starts with the ASCII `RLCN`.

| Class | Magic | Section | Holds |
|---|---|---|---|
| `NCLR` | `RLCN` | `TTLP` | palette; `colors` is flat `(r,g,b)`, `palettes()` splits it |
| `NCGR` | `RGCN` | `RAHC` | char/tile data; `data`, `bpp`, `linear`, `tiles_x/y`, `indices()` |
| `NSCR` | `RCSN` | `NRCS` | tilemap; `width`, `height`, `entries` |
| `NCER` | `RECN` | `KBEC` | OAM cells; `cells`, `mapping_mode`, `char_boundary` |
| `NANR` | `RNAN` | `KNBA` | animation; `sequences` with decoded frames |

Helpers: `unpack_indices`, `untile`, `gen5_assemble`, `unpack_screen_entry`,
`decode_oam`, `render_screen` (NSCR ⨉ NCGR ⨉ NCLR → RGBA), `compose_cell`
(NCER cell → RGBA), `indices_to_rgba` / `save_png`.

Traps handled:

* **Gen 5 sprite NCGRs lie about their file and section size.** `sections()`
  clamps to the real buffer and pixel decoding is driven by `CHAR.dataSize`.
* **4bpp: the low nibble is the LEFT pixel.**
* **`CHAR flags & 1` means *linear* — do NOT untile.** Gen 4 battle sprites are
  linear; almost everything else is tiled.
* **NCLR's depth field can disagree with reality.** `pl_pokegra` palettes
  declare 8bpp and hold 16 colours, so the count comes from `dataSize / 2` and
  the depth comes from the NCGR.
* **BGR555 → RGB uses `(x*255 + 15)//31`,** not `x << 3`, which would leave
  white at 248.
* **OAM attr0 bit 9 is *disable* only when bit 8 (rot) is clear**; with rot set
  it is *double size*, and attr1 bits 12/13 stop being flip flags.

### Sprite obfuscation (`xor_lcg`, `auto_decrypt`)

Gen 4 Pokémon and trainer battle sprites XOR their **pixel data only** with the
Pokémon LCG keystream (`seed = seed*0x41C64E6D + 0x6073`, mask = low 16 bits).
The direction is **per authoring game, not per generation** — Platinum and
HeartGold are `forward`, Diamond/Pearl (`pokegra.narc`, shipped inside
Platinum) is `backward` — so `auto_decrypt` detects by nibble entropy instead of
assuming. **Gen 5 sprites are not obfuscated**; XORing them destroys the image,
which is why the detector is entropy-gated (< 3.6 bits ⇒ already plaintext).

Because the seed *is* the halfword it first masks, the first (forward) or last
(backward) decoded halfword is always `0x0000` — a free self-check the tests
assert on.

> **Correction to `docs/research/nds-formats.md` §5.1.1.** The doc says
> encryption is "the *same function*", an involution. It is not, when the seed
> is derived from the buffer: decryption zeroes the seeding halfword, so a
> second derived-seed pass runs a keystream from seed 0 and yields different
> bytes. `xor_lcg(data, backward, seed=...)` takes the original seed explicitly
> for re-encryption. Proven both ways by
> `test_xor_lcg_round_trips_with_an_explicit_seed`.

### The Gen 5 96×96 layout (`gen5_assemble`)

`/a/0/0/4` slots `+0` / `+9` declare 12×12 tiles and `flags = 0` (tiled), but a
plain 96-wide `untile` produces scrambled stripes. The chars are stored as
**four 1D-mapped OAM objects** covering the canvas in 64×64 super-blocks,
row-major, clipped at the edges:

| Object | Position | Size | Chars |
|---|---|---|---|
| 1 | (0, 0) | 64×64 | 64 |
| 2 | (64, 0) | 32×64 | 32 |
| 3 | (0, 64) | 64×32 | 32 |
| 4 | (64, 64) | 32×32 | 16 |
| | | | **144** |

Use `gen5_assemble`, never `untile`, for these. A sprite that decodes without
an exception is not proof of success — the tests check that the assembled and
naively-untiled results differ, that the canvas border is transparent and that
the mid-row is not.

## `nsbtx.py` — TEX0 texture banks

A `BTX0` file (or the `TEX0` block inside a `BMD0` model) holds two Nitro 3D
info dictionaries: one of textures, one of palettes.

> **The two dictionaries are sorted by name independently, so palette index ≠
> texture index.** This is the most expensive bug in the format, because
> binding by index still *decodes* — it just tints the texture with a
> neighbour's palette.

Concretely, White 2 `/a/0/1/4` entry 0 has 76 textures and 76 palettes.
Texture 3 is `gake01a`; palette 3 is `gake01a2_pl`. The palette `gake01a`
actually wants is index **4**, `gake01a_pl`. Measured over the first 60 entries
of that archive: **471 of 5,646 texture slots (8.3%) get a different palette by
index than by name, and 329 of them (5.8% of all slots) render different
pixels.**

`resolve_palettes(tex_names, pal_names)` binds by name in four passes, and
`TEX0.decode()` uses the result by default:

1. exact `<tex>_pl`
2. exact `<tex>`
3. longest affix match against an unclaimed palette's stem — covers the real
   exceptions (`h04_stair` → `stair`, `warp01/02/03` → `gtswarp_r/b/g`)
4. leftovers handed out in order; only then fall back to the index

`TEX0.pal_stats` records which pass fired, so a pipeline can assert that
`pal_by_index_guess` is 0.

| API | |
|---|---|
| `TEX0(blob)` | accepts `BTX0` or `BMD0` |
| `tex_names`, `pal_names`, `pal_index` | the dictionaries and the name binding |
| `index_of(name)`, `palette_index_for(tex)`, `palette_name_for(tex)` | lookup |
| `tex_param(i)` | `w`, `h`, `fmt`, `fmtname`, `col0`, `vram` |
| `decode(tex, pal_index=None)` | `(h, w, 4)` uint8 ndarray; pass `pal_index` only to *demonstrate* the wrong answer |
| `to_image(tex)` | PIL RGBA |

Formats: `0` none, `1` A3I5, `2` PAL4, `3` PAL16, `4` PAL256, `5` CMP4×4,
`6` A5I3, `7` DIRECT — all implemented. PAL16 is ~78% of the map-texture
libraries.

---

## Known limitations

* **Gen 4 party icon colours are wrong.** `pl_poke_icon[0]` holds 16 shared
  16-colour palettes and the per-species palette index lives in a table outside
  the NARC (ARM9 or an overlay). `compose_cell` produces correct silhouettes
  and wrong hues until that table is located. **UNVERIFIED** where it lives.
* **Huffman (`0x20/24/28`) and BLZ overlay compression are not implemented.**
  No graphics asset needs either.
* **RLE is implemented but UNVERIFIED** — no genuine RLE asset was found.
* **`NMCR` (`RCMN`) and `NMAR` (`RAMN`)** multi-cell resources are not parsed;
  static sprites do not need them.
* **The Gen 5 dex-number → form-index table is not here.** `/a/0/0/4` has 751
  form blocks in White 2 for 649 species plus alternates; for the forms spot-
  checked the index happens to equal the dex number. The mapping table lives
  outside the archive. **UNVERIFIED.**
* **NCLR `PCMP`** (palette index remap) is not parsed; it appears in no
  Platinum NCLR scanned.
