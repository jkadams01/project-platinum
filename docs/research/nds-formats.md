# Nintendo DS / Pokémon ROM formats — verified reference

**Status:** every struct layout, offset and algorithm below was verified by running Python
against the owner's own ROMs on 2026-09-23. Nothing here is quoted from memory without a
byte dump or a rendered image backing it. Where a claim could not be verified it is marked
**UNVERIFIED** explicitly.

**Audience:** implementers of `tools/extract_*.py`. Read §1→§5 in order; §6 is a complete,
runnable extractor you can lift wholesale.

## 0. Environment and ground truth

| ROM | Path (under `References/Roms/`) | Game code | FAT entries | Overlays | Named files | Dirs |
|---|---|---|---|---|---|---|
| Platinum (US) | `Platinum/3541 - Pokemon Platinum Version (US)(XenoPhobia).nds` | `CPUE` | 462 | 122 | 340 | 89 |
| HeartGold (US) | `Heartgold/4780 - Pokemon HeartGold (U)(Xenophobia).nds` | `IPKE` | 513 | — | 384 | — |
| Black (US) | `Black/5585 - Pokemon - Black Version (DSi Enhanced)(USA) (E)(SweeTnDs).nds` | `IRBO` | 484 | — | 247 | — |
| White 2 (US) | `White 2/Pokemon White 2 (Experience + Trade Evolution Patched).nds` | `IRDO` | 662 | 344 | 318 | 39 |

`References/Roms/Explorers of Sky/` also holds a Mystery Dungeon ROM; it is a different
engine and out of scope here.

Python 3.8.3, Pillow 7.2.0, NumPy 1.24.4. Pillow lives in Anaconda and its DLLs are **not**
on `PATH` by default — `from PIL import Image` fails with
`ImportError: DLL load failed while importing _imaging`. Fix before running anything that
imports PIL:

```bash
export PATH="/c/Users/James/anaconda3:/c/Users/James/anaconda3/Library/bin:/c/Users/James/anaconda3/Library/mingw-w64/bin:/c/Users/James/anaconda3/Scripts:$PATH"
```

All scratch scripts referenced here live in `tools/_work/` (gitignored). Nothing
ROM-derived is ever committed.

---

## 1. The NDS ROM container

### 1.1 Cartridge header (first 0x200 bytes)

Little-endian throughout. Fields we actually use:

| Off | Size | Field | Platinum | White 2 |
|---|---|---|---|---|
| 0x000 | 12 | Game title (ASCII, NUL-padded) | `POKEMON PL` | `POKEMON W2` |
| 0x00C | 4  | Game code | `CPUE` | `IRDO` |
| 0x010 | 2  | Maker code | `01` | `01` |
| 0x012 | 1  | Unit code (0=NDS, 2=NDS+DSi, 3=DSi) | 0 | 2 |
| 0x013 | 1  | Encryption seed select | | |
| 0x014 | 1  | Device capacity — bytes = `128*1024 << value` | 10 → 128 MiB | 12 → 512 MiB |
| 0x015 | 7  | Reserved (zero) | | |
| 0x01D | 1  | Region | 0 | 64 |
| 0x01E | 1  | ROM version | 0 | 0 |
| 0x01F | 1  | Autostart flags | | |
| 0x020 | 4  | ARM9 ROM offset | 0x4000 | 0x4000 |
| 0x024 | 4  | ARM9 entry address | 0x02000800 | 0x02004800 |
| 0x028 | 4  | ARM9 RAM address | 0x02000000 | 0x02004000 |
| 0x02C | 4  | ARM9 size | 0x1023F8 | 0x736CC |
| 0x030 | 4  | ARM7 ROM offset | 0x409800 | 0x7A200 |
| 0x034 | 4  | ARM7 entry address | 0x02380000 | 0x02380000 |
| 0x038 | 4  | ARM7 RAM address | 0x02380000 | 0x02380000 |
| 0x03C | 4  | ARM7 size | 0x277FC | 0x28F84 |
| **0x040** | 4 | **FNT offset** | 0x431000 | 0xA3C00 |
| **0x044** | 4 | **FNT size** | 0x1BB4 | 0x4F0 |
| **0x048** | 4 | **FAT offset** | 0x432C00 | 0xA4200 |
| **0x04C** | 4 | **FAT size** | 0xE70 | 0x14B0 |
| 0x050 | 4  | ARM9 overlay table (OVT) offset | 0x106600 | 0x776CC |
| 0x054 | 4  | ARM9 OVT size (bytes; `/32` = overlay count) | 0xF40 → 122 | 0x2B00 → 344 |
| 0x058 | 4  | ARM7 OVT offset | 0 | 0xA3184 |
| 0x05C | 4  | ARM7 OVT size | 0 | 0 |
| 0x060 | 4  | Normal card control register | | |
| 0x064 | 4  | Secure card control register | | |
| 0x068 | 4  | Icon/title (banner) offset | 0x433C00 | 0xA3200 |
| 0x06C | 2  | Secure-area CRC16 | 0xF8B8 | 0x0F68 |
| 0x06E | 2  | Secure transfer timeout | | |
| 0x070 | 4  | ARM9 autoload | | |
| 0x074 | 4  | ARM7 autoload | | |
| 0x078 | 8  | Secure-area disable | | |
| 0x080 | 4  | Total used ROM size | 0x63C303C | 0x1125283C |
| 0x084 | 4  | ROM header size | 0x4000 | 0x4000 |
| 0x15C | 2  | Header CRC16 (over 0x000..0x15D) | 0xCF56 | 0xCF56 |

Note the *file on disk is larger than `used_size`* — Platinum's file is 128 MiB of which
0x63C303C (≈104 MB) is used; the tail is 0xFF padding. Never trust the file length as the
ROM length.

```python
import struct

def read_header(rom_path):
    d = open(rom_path, 'rb').read()
    h = {}
    h['data']      = d
    h['title']     = d[0x00:0x0C].rstrip(b'\x00').decode('ascii', 'replace')
    h['gamecode']  = d[0x0C:0x10].decode('ascii')
    h['unitcode']  = d[0x12]
    h['capacity']  = 128 * 1024 << d[0x14]
    (h['arm9_off'], h['arm9_entry'], h['arm9_ram'], h['arm9_size'],
     h['arm7_off'], h['arm7_entry'], h['arm7_ram'], h['arm7_size'],
     h['fnt_off'],  h['fnt_size'],   h['fat_off'],  h['fat_size'],
     h['ov9_off'],  h['ov9_size'],   h['ov7_off'],  h['ov7_size']) =         struct.unpack_from('<16I', d, 0x20)
    h['banner_off'] = struct.unpack_from('<I', d, 0x68)[0]
    h['used_size']  = struct.unpack_from('<I', d, 0x80)[0]
    h['n_overlays'] = h['ov9_size'] // 32
    return h
```

### 1.2 Overlay table (OVT) — 32 bytes per entry

`ov9_size // 32` entries. Verified for both ROMs: `overlay_id == index` and
`file_id == index` for **every** entry.

| Off | Size | Field |
|---|---|---|
| 0x00 | 4 | Overlay ID |
| 0x04 | 4 | RAM load address |
| 0x08 | 4 | RAM size |
| 0x0C | 4 | BSS size |
| 0x10 | 4 | static-initialiser start address |
| 0x14 | 4 | static-initialiser end address |
| 0x18 | 4 | **File ID** (index into the FAT) |
| 0x1C | 4 | low 24 bits = compressed size, high 8 bits = flags |

Flags: bit 0 = compressed (**BLZ**, "backwards LZ" — *not* LZ10/LZ11, see §3.5), bit 1 = signed/authenticated.

Real entries:

```
Platinum ov0   id=0   ram=0x021D0D80 size=0x20  bss=0x0  fileID=0   compSize=0x0   flag=0x00
Platinum ov121 id=121 ram=0x021D0D80 size=0x640 bss=0x0  fileID=121 compSize=0x0   flag=0x00
White2   ov0   id=0   ram=0x0214F540 size=0x420 bss=0x0  fileID=0   compSize=0x404 flag=0x03
White2   ov343 id=343 ram=0x021FB8C0 size=0x20  bss=0x0  fileID=343 compSize=0x14  flag=0x03
```

Platinum ships its overlays uncompressed; White 2 compresses and signs all of them.

**Consequence for the file walker:** overlays occupy file IDs `0 .. overlay_count-1`.
The first *named* file in the FNT is file ID `overlay_count`. Verified:
Platinum's lowest named file ID is 122 (`/application/balloon/graphic/balloon_gra.narc`)
and White 2's is 344 (`/skb.narc`).

### 1.3 FAT — File Allocation Table

Flat array at `fat_off`, `fat_size // 8` entries, 8 bytes each:

| Off | Size | Field |
|---|---|---|
| 0x00 | 4 | start offset in the ROM image (absolute) |
| 0x04 | 4 | end offset (exclusive) |

```python
def read_fat(d, fat_off, fat_size):
    return [struct.unpack_from('<II', d, fat_off + i*8) for i in range(fat_size // 8)]

def file_bytes(d, fat, fid):
    s, e = fat[fid]
    return d[s:e]
```

File size is `end - start`. An **empty file is legal** and appears as `start == end`
(the NARC sub-file equivalent is very common — see §5.2).

### 1.4 FNT — File Name Table

The FNT is two regions inside one blob starting at `fnt_off`:

1. a **directory table**: 8 bytes per directory, directory 0 first;
2. **name sub-tables**, one per directory, pointed at by the directory table.

Directory entry (8 bytes):

| Off | Size | Field |
|---|---|---|
| 0x00 | 4 | offset of this directory's sub-table, **relative to `fnt_off`** |
| 0x04 | 2 | first file ID in this directory |
| 0x06 | 2 | parent directory ID — **for directory 0 this is instead the total directory count** |

Directory IDs are `0xF000 | index`; mask with `0x0FFF` to get the index. Directory 0 is
the root. Platinum has 89 directories, White 2 has 39.

Sub-table entries, read sequentially until a terminator:

| Type byte | Meaning |
|---|---|
| `0x00` | end of this sub-table |
| `0x01..0x7F` | **file**; low 7 bits = name length; name follows; consumes the next sequential file ID |
| `0x80` | reserved, treat as terminator (never observed in these ROMs) |
| `0x81..0xFF` | **sub-directory**; `type & 0x7F` = name length; name follows; then a `u16` directory ID |

File IDs are assigned by walking each directory's sub-table in order starting from that
directory's `first file ID`. Names are Shift-JIS in principle; every name in these four
ROMs is pure ASCII.

```python
def read_fnt(d, fnt_off):
    ndirs = struct.unpack_from('<H', d, fnt_off + 6)[0]   # dir 0's "parent" == dir count
    dirs  = [struct.unpack_from('<IHH', d, fnt_off + i*8) for i in range(ndirs)]
    files = {}                                            # file id -> '/full/path'

    def walk(i, prefix):
        sub, fid, _parent = dirs[i]
        p = fnt_off + sub
        while True:
            t = d[p]; p += 1
            if t == 0x00 or t == 0x80:
                break
            ln = t & 0x7F
            name = d[p:p+ln].decode('shift_jis', 'replace'); p += ln
            if t < 0x80:
                files[fid] = prefix + '/' + name
                fid += 1
            else:
                sid = struct.unpack_from('<H', d, p)[0]; p += 2
                walk(sid & 0x0FFF, prefix + '/' + name)

    walk(0, '')
    return files, ndirs
```

Sanity check that must hold: `overlay_count + len(files) == len(fat)`.
Platinum `122 + 340 == 462` ✓. White 2 `344 + 318 == 662` ✓.

Complete file listings are in **Appendix A (Platinum, 340 files)** and
**Appendix B (White 2, 318 files)**.

### 1.5 Gen 4 vs Gen 5 naming

Gen 4 (DPPt/HGSS) ships a real directory tree with meaningful names
(`/poketool/pokegra/pl_pokegra.narc`). Gen 5 (BW/B2W2) moved nearly everything into
opaque numbered paths `/a/<x>/<y>/<z>`; only a handful of root files keep names
(`/skb.narc`, `/soundstatus.narc`, `/swan_sound_data.sdat`, …). White 2's entire game
content is 318 files, 315 of which are `/a/x/y/z`.

Empirically identified White 2 archives (from a survey of every NARC's sub-file magics —
`tools/_work/survey_w2.py`):

| Path | Sub-files | Contents |
|---|---|---|
| `/a/0/0/4` | 15065 | **Pokémon battle sprites (B2W2 "pokegra")** — 20 files/form |
| `/a/0/5/1` | 14285 | BW-era Pokémon sprites, same 20-file layout (legacy copy; Black's `/a/0/0/4` has 14285 too) |
| `/a/0/6/3`, `/a/0/7/1`, `/a/0/7/2` | 248 / 1504 / 248 | trainer sprites (80×80 tiled NCGR + 256×128 linear atlas) |
| `/a/0/4/0` | 33 | 80×80 **8bpp** NCGR + NCLR pairs |
| `/a/0/9/4` | 267 | 256×256 4bpp NCGR + NSCR + NCLR triples (backgrounds) |
| `/a/1/1/7` | 95 | 168×160 4bpp NCGRs (24 of them) + palettes |

---

## 2. NARC — Nitro ARChive

Every `.narc` in Gen 4, and nearly every `/a/x/y/z` in Gen 5, is a NARC.

### 2.1 Container header (16 bytes)

| Off | Size | Field | Observed |
|---|---|---|---|
| 0x00 | 4 | magic `"NARC"` (stored in reading order, *not* reversed) | `4E 41 52 43` |
| 0x04 | 2 | BOM | `0xFFFE` |
| 0x08* | 2 | version | `0x0100` |
| 0x08 | 4 | total file size | |
| 0x0C | 2 | header size | `0x0010` |
| 0x0E | 2 | number of chunks | `0x0003` |

(Exact order: `<4s H H I H H>` = magic, bom, version, filesize, headersize, nchunks.)

Then `nchunks` chunks laid end to end, each `u32 magic; u32 size;` followed by payload.
Always three, always in this order: `BTAF`, `BTNF`, `GMIF`.

### 2.2 BTAF — sub-file allocation table

Real bytes from `pl_pokegra.narc`:

```
42 54 41 46  AC 5C 00 00  94 0B 00 00   ('BTAF', size=0x5CAC, count=0x0B94=2964)
00 00 00 00  30 19 00 00                 entry[0] = start 0,      end 0x1930
30 19 00 00  60 32 00 00                 entry[1] = start 0x1930, end 0x3260
```

| Off (from chunk start) | Size | Field |
|---|---|---|
| 0x00 | 4 | magic `"BTAF"` |
| 0x04 | 4 | chunk size (includes this header) |
| 0x08 | 2 | **number of sub-files** |
| 0x0A | 2 | reserved (0) |
| 0x0C | 8×N | entries: `u32 start; u32 end;` **relative to the start of GMIF's payload** |

> **Gotcha that cost an hour:** the count is at **+0x08**, not +0x06. Reading it at +0x06
> yields 0 for `pl_pokegra` and 1 for White 2's `/a/0/0/4`. Some references describe the
> field as a `u32` at +0x08 (count then acts as a 32-bit value); both readings agree
> because no observed NARC exceeds 65535 sub-files. Chunk-size arithmetic confirms it:
> `(0x5CAC - 12) / 8 == 2964`.

### 2.3 BTNF — sub-file name table

Same structure as the ROM FNT (§1.4), but **every NARC in all four ROMs ships a null
name table**: 16 bytes total, i.e. the 8-byte chunk header plus one root directory entry
and nothing else.

```
42 54 4E 46  10 00 00 00  04 00 00 00  00 00 01 00
'BTNF'       size=0x10    subOff=4     firstID=0  parent/dircount=1
```

Verified: **0 of Platinum's 340 files** carry sub-file names. Do not build a name-based
API for NARC contents — address sub-files by index.

### 2.4 GMIF — file image

```
47 4D 49 46  A8 5D B3 00      ('GMIF', size=0x00B35DA8)
```

| Off | Size | Field |
|---|---|---|
| 0x00 | 4 | magic `"GMIF"` |
| 0x04 | 4 | chunk size |
| 0x08 | … | raw sub-file bytes; BTAF offsets are relative to **here** |

### 2.5 Reader

```python
import struct

class NARC(object):
    def __init__(self, data):
        assert data[:4] == b'NARC'
        hdrsize, nchunks = struct.unpack_from('<HH', data, 12)
        self.data, self.chunks, p = data, {}, hdrsize
        for _ in range(nchunks):
            cid, csize = struct.unpack_from('<4sI', data, p)
            self.chunks[cid] = (p, csize)
            p += csize
        bo, _ = self.chunks[b'BTAF']
        self.n = struct.unpack_from('<H', data, bo + 8)[0]
        self.ent = [struct.unpack_from('<II', data, bo + 12 + i*8) for i in range(self.n)]
        self.img = self.chunks[b'GMIF'][0] + 8

    def __len__(self):  return self.n
    def __getitem__(self, i):
        s, e = self.ent[i]
        return self.data[self.img + s : self.img + e]
```

Verified output:

```
/poketool/pokegra/pl_pokegra.narc  bom=0xFFFE ver=0x0100 size=11778676 hdr=16 chunks=3 files=2964
      BTAF at 0x10   size=23724
      BTNF at 0x5CBC size=16
      GMIF at 0x5CCC size=11754920
      [0] size=6448 magic=b'RGCN'   [4] size=72 magic=b'RLCN'
W2 /a/0/0/4                        files=15065
      [0] size=443  magic=b'\x110\x12\x00'  (LZ11, 4656 bytes out)
      [1] size=0    (empty sub-file — legal and common)
```

---

## 3. Compression

### 3.1 The BIOS header byte

Every BIOS-compressed blob starts with a 4-byte header:

```
byte 0 : type   (high nibble = algorithm, low nibble = variant)
byte 1-3: uncompressed size, 24-bit little-endian
```

If the 24-bit size is **0**, an extended 32-bit size follows at bytes 4..7 and the payload
starts at byte 8 instead of byte 4.

| Type | Algorithm |
|---|---|
| `0x10` | LZ77 / LZ10 |
| `0x11` | LZ77 / LZ11 (extended lengths) |
| `0x20`, `0x24`, `0x28` | Huffman (bit depth = low nibble) |
| `0x30` | Run-length |
| `0x80`, `0x81` | Difference filter (8-bit / 16-bit) |

```python
def read_comp_header(d):
    t = d[0]
    size = d[1] | (d[2] << 8) | (d[3] << 16)
    p = 4
    if size == 0:                     # 24-bit size of 0 -> extended 32-bit size follows
        size = struct.unpack_from('<I', d, 4)[0]
        p = 8
    return t, size, p
```

### 3.2 LZ10 (`0x10`)

Payload is a sequence of *blocks*. Each block starts with one **flag byte**, consumed
**MSB first** (`0x80, 0x40, … 0x01`). For each of the 8 flags:

* flag = 0 → copy one literal byte from the stream;
* flag = 1 → read two bytes `b0, b1`:
  * `length      = (b0 >> 4) + 3`             (3..18)
  * `displacement= (((b0 & 0x0F) << 8) | b1) + 1`  (1..4096)
  * copy `length` bytes from `out[len(out) - displacement]`.

The copy **must be byte-at-a-time**: source and destination overlap deliberately (that is
how runs are encoded). A `memcpy`-style slice copy produces corrupt output.

```python
def decompress_lz10(data):
    t, size, p = read_comp_header(data)
    assert t == 0x10
    out = bytearray()
    while len(out) < size:
        flags = data[p]; p += 1
        for bit in range(8):
            if len(out) >= size: break
            if flags & (0x80 >> bit):
                b0, b1 = data[p], data[p+1]; p += 2
                ln   = (b0 >> 4) + 3
                disp = (((b0 & 0x0F) << 8) | b1) + 1
                start = len(out) - disp
                for i in range(ln):
                    out.append(out[start + i])
            else:
                out.append(data[p]); p += 1
    return bytes(out[:size])
```

Verified: `/application/custom_ball/data/cb_data.narc[0]`, 92 bytes in → 111 bytes out,
declared size matches, output begins `RNAN`.

### 3.3 LZ11 (`0x11`)

Same flag-byte framing. On a set flag, read `b0` and branch on `b0 >> 4`:

| `b0 >> 4` | Bytes consumed | length | displacement |
|---|---|---|---|
| `0` | 3 (`b0 b1 b2`) | `(((b0 & 0xF) << 4) \| (b1 >> 4)) + 0x11` (17..272) | `(((b1 & 0xF) << 8) \| b2) + 1` |
| `1` | 4 (`b0 b1 b2 b3`) | `(((b0 & 0xF) << 12) \| (b1 << 4) \| (b2 >> 4)) + 0x111` (273..65808) | `(((b2 & 0xF) << 8) \| b3) + 1` |
| `2..15` | 2 (`b0 b1`) | `(b0 >> 4) + 1` (3..16) | `(((b0 & 0xF) << 8) \| b1) + 1` |

```python
def decompress_lz11(data):
    t, size, p = read_comp_header(data)
    assert t == 0x11
    out = bytearray()
    while len(out) < size:
        flags = data[p]; p += 1
        for bit in range(8):
            if len(out) >= size: break
            if not (flags & (0x80 >> bit)):
                out.append(data[p]); p += 1
                continue
            b0 = data[p]; ind = b0 >> 4
            if ind == 0:
                b1, b2 = data[p+1], data[p+2]; p += 3
                ln   = (((b0 & 0x0F) << 4) | (b1 >> 4)) + 0x11
                disp = (((b1 & 0x0F) << 8) | b2) + 1
            elif ind == 1:
                b1, b2, b3 = data[p+1], data[p+2], data[p+3]; p += 4
                ln   = (((b0 & 0x0F) << 12) | (b1 << 4) | (b2 >> 4)) + 0x111
                disp = (((b2 & 0x0F) << 8) | b3) + 1
            else:
                b1 = data[p+1]; p += 2
                ln   = ind + 1
                disp = (((b0 & 0x0F) << 8) | b1) + 1
            start = len(out) - disp
            for i in range(ln):
                out.append(out[start + i])
    return bytes(out[:size])
```

Verified on White 2 `/a/0/0/4`: 4937 of 15065 sub-files are LZ11; every one decodes to
exactly its declared size and lands on a valid Nitro magic. Examples:

```
[ 0] LZ11 in=443 declared=4656  actual=4656  -> RGCN
[ 2] LZ11 in=435 declared=16448 actual=16448 -> RGCN
[ 5] LZ11 in=89  declared=111   actual=111   -> RNAN
[20] LZ11 in=565 declared=4656  actual=4656  -> RGCN
```

### 3.4 RLE (`0x30`)

Payload is a sequence of runs, each introduced by one flag byte:

* `flag & 0x80` set → **compressed run**: `length = (flag & 0x7F) + 3`, next byte repeated
  `length` times.
* `flag & 0x80` clear → **literal run**: `length = (flag & 0x7F) + 1`, copy `length` bytes.

```python
def decompress_rle(data):
    t, size, p = read_comp_header(data)
    assert t & 0xF0 == 0x30
    out = bytearray()
    while len(out) < size:
        flag = data[p]; p += 1
        if flag & 0x80:
            ln = (flag & 0x7F) + 3
            out += bytes([data[p]]) * ln; p += 1
        else:
            ln = (flag & 0x7F) + 1
            out += data[p:p+ln]; p += ln
    return bytes(out[:size])
```

**UNVERIFIED against a genuine RLE asset.** A scan of Platinum, White 2 and HeartGold
found no sub-file that both begins `0x3*` and decodes to a recognisable Nitro resource —
every `0x3*` hit was an uncompressed file whose first byte happened to be in range (see
§3.6). These games do not appear to use BIOS RLE for graphics. Keep the routine for
completeness; do not build a pipeline that depends on it without first finding a real case.

### 3.5 Difference filter (`0x80`/`0x81`) and BLZ

The difference filter is a post-pass, not a compressor: each output element is the running
sum of the stored deltas (8-bit for `0x80`, 16-bit little-endian for `0x81`).

Overlay compression (OVT flag bit 0, used by White 2) is **BLZ**, Nintendo's
"backwards LZ" variant used only for ARM9/overlay code: the stream is decoded from the end
of the buffer towards the start and the footer, not a header, carries the sizes. It is
**out of scope for asset extraction** — no graphics asset uses it. **UNVERIFIED**; we never
needed to decode an overlay.

### 3.6 Detecting compression — do not sniff on the first byte alone

Counting first-byte hits across every NARC sub-file:

```
Platinum : 0x10:2405  0x11:35  0x24:20  0x28:61  0x30:26  0x40:24  0x80:23  0x81:3
White2   : 0x11:1298  0x10:981 0x24:49  0x28:63  0x30:30  0x40:58  0x80:14
verified to decode to a Nitro magic:
Platinum : 0x10:2365   (everything else = false positive)
White2   : 0x11:719  0x10:845
```

Roughly 5 % of "hits" are uncompressed files whose leading byte coincides. The safe test:

```python
def maybe_decompress(d):
    if not d or d[0] not in (0x10, 0x11):
        return d
    size = d[1] | (d[2] << 8) | (d[3] << 16)
    if size == 0 or size > 8 * 1024 * 1024:
        return d
    try:
        out = decompress_lz10(d) if d[0] == 0x10 else decompress_lz11(d)
    except (IndexError, AssertionError):
        return d
    if len(out) != size:
        return d
    return out
```

Better still: know the archive. `/a/0/0/4` slots +0/+2/+5 are always LZ11; Gen 4
`pl_pokegra` is never compressed.

---

## 4. Nitro graphics resources

### 4.1 The shared 16-byte container header

Every `N***` resource uses it. **The magic is stored byte-reversed** — an NCLR file starts
with the ASCII `RLCN`. Both spellings appear in tooling; match on the on-disk form.

| Off | Size | Field | Typical |
|---|---|---|---|
| 0x00 | 4 | magic, reversed (`RLCN`, `RGCN`, `RCSN`, `RECN`, `RNAN`, `RCMN`, `RAMN`) | |
| 0x04 | 2 | BOM | `0xFEFF` |
| 0x06 | 2 | version | `0x0100` (Gen 4) / `0x0101` (Gen 5 sprite NCGRs) |
| 0x08 | 4 | total file size | |
| 0x0C | 2 | header size | `0x0010` |
| 0x0E | 2 | number of sections | 1..3 |

Sections follow immediately, each `u32 magic; u32 size;` then payload; `size` **includes**
the 8-byte section header.

```python
def sections(d):
    hdrsize, nsec = struct.unpack_from('<HH', d, 12)
    out, p = {}, hdrsize
    for _ in range(nsec):
        cid, csz = struct.unpack_from('<4sI', d, p)
        if csz == 0 or p + csz > len(d):      # header lies — see the warning below
            out.setdefault(cid, (p, len(d) - p)); break
        out.setdefault(cid, (p, csz)); p += csz
    return out
```

> **Warning — Gen 5 sprite NCGRs lie about their size.** White 2 `/a/0/0/4[20]`
> decompresses to 4656 bytes but its header claims `filesize = 0x2030 (8240)` and
> `CHAR size = 0x2020`. The **`dataSize` field inside CHAR is correct** (`0x1200` = 4608)
> and `0x30 + 0x1200 = 0x1230 = 4656` = the real length. Always clamp section reads to the
> actual buffer and drive pixel decoding from `dataSize`, never from `filesize`.

### 4.2 NCLR (`RLCN`) — palette

Section `TTLP` (= `PLTT` reversed). Optional section `PCMP` (= `PMCP`).

`TTLP`, offsets relative to the section start:

| Off | Size | Field |
|---|---|---|
| 0x00 | 4 | `"TTLP"` |
| 0x04 | 4 | section size |
| 0x08 | 2 | bit depth: `3` = 4bpp/16-colour, `4` = 8bpp/256-colour |
| 0x0A | 2 | unused/garbage — **`0x000A` in DPPt pokegra palettes**, 0 elsewhere |
| 0x0C | 4 | "compressed"/padding flag (always 0 here) |
| 0x10 | 4 | **palette data size in bytes** (colours = `/2`) |
| 0x14 | 4 | colours per palette (always `0x10` in these ROMs, even for 8bpp files) |
| 0x18 | … | colour data, `u16` BGR555 each |

Real bytes, `pl_pokegra[10]` (Bulbasaur normal palette, 72 bytes):

```
0000  52 4C 43 4E FF FE 00 01  48 00 00 00 10 00 01 00   RLCN, ver 0x0100, size 0x48, 1 section
0010  54 54 4C 50 38 00 00 00  04 00 0A 00 00 00 00 00   TTLP size 0x38, depth=4, unk=0x000A
0020  20 00 00 00 10 00 00 00  59 5B FF 7F B0 63 4C 5B   dataSize=0x20 (16 colours), cpp=0x10
0030  47 4A 23 25 BF 31 3B 21  B7 10 39 67 42 08 F7 3B
```

> **Do not trust the depth field for colour count.** This palette declares depth 4 (8bpp)
> yet contains 16 colours, and the matching NCGR is 4bpp. Derive the colour count from
> `dataSize / 2` and the pixel depth from the **NCGR**.

Colour conversion (BGR555 → RGB888):

```python
def bgr555_to_rgb(v):
    r, g, b = v & 0x1F, (v >> 5) & 0x1F, (v >> 10) & 0x1F
    return ((r*255 + 15)//31, (g*255 + 15)//31, (b*255 + 15)//31)
```

The `(x*255 + 15)//31` rounding matters: `x << 3` leaves whites at 248 instead of 255.

```python
def read_nclr(d):
    o = sections(d)[b'TTLP'][0]
    n = struct.unpack_from('<I', d, o + 0x10)[0] // 2     # dataSize / 2 = colour count
    cols = struct.unpack_from('<%dH' % n, d, o + 0x18)
    return [bgr555_to_rgb(c) for c in cols]
```

Palette index `0` is the transparent colour for sprites and OAM cells (it is *opaque* for
NSCR backgrounds).

Census across Platinum (`depth, unk@0x0A, colours, colours-per-palette`):
`(3,0,256,16)` ×164, `(3,0,240,16)` ×62, `(3,0,192,16)` ×13, `(4,0,256,16)` ×6,
`(3,0,32,16)` ×6 …

Optional `PCMP` section (palette-index remap; **not present in any Platinum NCLR** we
scanned): `u32 "PCMP"; u32 size; u16 count; u16 0xBEEF; u32 offset;` then `count` × `u16`
palette IDs. **UNVERIFIED.**

### 4.3 NCGR (`RGCN`) — character / tile data

Section `RAHC` (= `CHAR`). Optional section `SOPC` (= `CPOS`).

`RAHC`, offsets relative to the section start:

| Off | Size | Field |
|---|---|---|
| 0x00 | 4 | `"RAHC"` |
| 0x04 | 4 | section size |
| 0x08 | 2 | **height in tiles** (`0xFFFF` = unspecified) |
| 0x0A | 2 | **width in tiles** (`0xFFFF` = unspecified) |
| 0x0C | 4 | bit depth: `3` = 4bpp, `4` = 8bpp |
| 0x10 | 4 | OBJ mapping / attribute word (see below) |
| 0x14 | 4 | **flags**: bit 0 = *not tiled* (scanline/linear), bit 1 = VRAM transfer |
| 0x18 | 4 | **char data size in bytes** — the authoritative length |
| 0x1C | 4 | offset of the char data relative to section+0x08; **always `0x18`** |
| 0x20 | … | char data (i.e. always at section + 0x20, = file + 0x30 for a 1-section NCGR) |

Real bytes, `pl_pokegra[6]` (Bulbasaur back sprite, 6448 bytes):

```
0000  52 47 43 4E FF FE 00 01  30 19 00 00 10 00 01 00   RGCN, size 0x1930, 1 section
0010  52 41 48 43 20 19 00 00  0A 00 14 00 03 00 00 00   RAHC size 0x1920, H=10 tiles, W=20 tiles, 4bpp
0020  00 00 00 00 01 00 00 00  00 19 00 00 18 00 00 00   map=0, flags=1 (LINEAR), dataSize=0x1900, +0x18
0030  77 A0 1E F5 39 E2 B8 10  CB 8E E2 06 AD 2A 1C 42   <- encrypted pixels, see §5.1
```

`10 tiles × 20 tiles = 200 tiles × 32 bytes (4bpp) = 6400 = 0x1900` ✓.

**Observed values of the field at +0x10** (Platinum census, as `u32`): `0x00000000` ×234,
`0x00000010` ×61, `0x00200010` ×20, `0x00100010` ×13. The low half is `0x10` whenever set;
the high half is `0x10` or `0x20`. It is not needed to decode pixels — ignore it.

**Observed values of the flags at +0x14**: `0` ×328 (tiled), `1` ×25 (linear), `0x100` ×1
(`/data/slot.narc[24]`, purpose unknown, **UNVERIFIED**). Only bit 0 matters in practice.

`SOPC` (present when `nsections == 2`, 202 of 354 Platinum NCGRs), always 16 bytes:

```
53 4F 50 43  10 00 00 00  00 00 00 00  10 00 10 00
'SOPC'       size=0x10    pad          tilesX=0x10  tilesY=0x10
```

| Off | Size | Field |
|---|---|---|
| 0x00 | 4 | `"SOPC"` |
| 0x04 | 4 | size (`0x10`) |
| 0x08 | 4 | padding (0) |
| 0x0C | 2 | width in tiles |
| 0x0E | 2 | height in tiles |

Verified to agree with the CHAR header where both are present
(`balloon_gra[0]` CHAR (16,16) / SOPC (0x10,0x10); `area_win_gra[0]` CHAR (32,3) /
SOPC (0x20,0x03)). Use SOPC as the fallback when CHAR says `0xFFFF`.

```python
def read_ncgr(d):
    o = sections(d)[b'RAHC'][0]
    ty, tx  = struct.unpack_from('<HH', d, o + 0x08)      # NOTE: height first, then width
    bpp     = 4 if struct.unpack_from('<I', d, o + 0x0C)[0] == 3 else 8
    linear  = bool(struct.unpack_from('<I', d, o + 0x14)[0] & 1)
    dsz     = struct.unpack_from('<I', d, o + 0x18)[0]
    doff    = struct.unpack_from('<I', d, o + 0x1C)[0]    # always 0x18
    start   = o + 0x08 + doff
    data    = bytearray(d[start : start + dsz])           # clamps if the header lies
    return dict(tx=tx, ty=ty, bpp=bpp, linear=linear, data=data,
                ntiles=len(data) // (32 if bpp == 4 else 64))
```

#### Pixel unpacking

**4bpp: the LOW nibble is the LEFT pixel.**

```python
def unpack_indices(data, bpp):
    if bpp == 8:
        return list(data)
    out = []
    for byte in data:
        out.append(byte & 0x0F)   # left
        out.append(byte >> 4)     # right
    return out
```

#### Tiled vs linear

* `flags & 1 == 0` (**tiled**, the default): the char stream is a sequence of 8×8 tiles,
  row-major within each tile, tiles row-major across the image. Use `untile()` below.
* `flags & 1 == 1` (**linear / "not tiled" / BMP mode**): the stream is already raster
  scanlines; use it as-is. Gen 4 Pokémon and trainer battle sprites are all linear.

```python
def untile(idx, width, height):
    out = [0] * (width * height); p = 0
    for ty in range(height // 8):
        for tx in range(width // 8):
            for y in range(8):
                row = (ty*8 + y) * width + tx*8
                out[row:row+8] = idx[p:p+8]; p += 8
    return out
```

Proof that the flag matters: decrypting `pl_pokegra[6]` correctly but then untiling it
anyway produces scrambled stripes; taking it as linear produces a clean Bulbasaur
(`tools/_work/out/cmp_gen4_decrypt.png`, columns 3 and 4).

### 4.4 NSCR (`RCSN`) — screen / tilemap

Section `NRCS` (= `SCRN`).

| Off | Size | Field |
|---|---|---|
| 0x00 | 4 | `"NRCS"` |
| 0x04 | 4 | section size |
| 0x08 | 2 | **width in pixels** |
| 0x0A | 2 | **height in pixels** |
| 0x0C | 2 | colour/palette mode |
| 0x0E | 2 | screen format |
| 0x10 | 4 | data size in bytes (`= (w/8)*(h/8)*2`) |
| 0x14 | … | screen entries, `u16` each |

Real bytes, `/graphic/poketch.narc[11]` (after LZ10):

```
0000  52 43 53 4E FF FE 00 01  24 06 00 00 10 00 01 00   RCSN size 0x624
0010  4E 52 43 53 14 06 00 00  00 01 C0 00 00 00 00 00   NRCS size 0x614, w=0x100(256), h=0xC0(192), mode 0, fmt 0
0020  00 06 00 00 01 08 01 08  01 08 01 08 01 08 01 08   dataSize=0x600 (1536 = 768 entries = 32x24)
```

Screen entry bit layout (`u16`):

| Bits | Field |
|---|---|
| 0–9 | tile index into the NCGR char stream |
| 10 | horizontal flip |
| 11 | vertical flip |
| 12–15 | palette number (×16 colours) |

```python
def unpack_screen_entry(v):
    return (v & 0x03FF, bool(v & 0x0400), bool(v & 0x0800), (v >> 12) & 0xF)
```

Census of `(colour_mode, screen_format)` across Platinum: `(0,0)` ×458, `(1,1)` ×16,
`(2,2)` ×12, `(1,0)` ×10, `(2,0)` ×2. The values do not correlate cleanly with the paired
NCGR's bit depth — e.g. `(1,0)` appears on a 512×256, 4bpp battle background. **Ignore both
fields**; derive tile count from `width/8 × height/8` and pixel depth from the NCGR.
**UNVERIFIED** what they actually select.

Composer (verified — renders the Poketch screen correctly, `tools/_work/out/bg_poketch.png`):

```python
def render_screen(nscr, ncgr, nclr):
    chars = unpack_indices(ncgr.data, ncgr.bpp)
    tw, th = nscr.width // 8, nscr.height // 8
    img = Image.new('RGBA', (nscr.width, nscr.height), (0, 0, 0, 255))
    px = img.load()
    psize = 16 if ncgr.bpp == 4 else 256
    for ty in range(th):
        for tx in range(tw):
            tile, hf, vf, pn = unpack_screen_entry(nscr.entries[ty*tw + tx])
            pal = nclr.colors[pn*psize : pn*psize + psize] or nclr.colors
            base = tile * 64
            for yy in range(8):
                for xx in range(8):
                    i  = chars[base + yy*8 + xx]
                    sx = 7 - xx if hf else xx
                    sy = 7 - yy if vf else yy
                    px[tx*8 + sx, ty*8 + sy] = tuple(pal[i]) + (255,)
    return img
```

Note NSCR uses 64 pixels per tile for **both** depths (a tile is 8×8 pixels regardless;
only the byte cost differs).

### 4.5 NCER (`RECN`) — cell / OAM assembly

Section `KBEC` (= `CEBK`). Optional `LBAL` (labels) and `TXEU` (extended) sections.

| Off | Size | Field |
|---|---|---|
| 0x00 | 4 | `"KBEC"` |
| 0x04 | 4 | section size |
| 0x08 | 2 | **number of cells** |
| 0x0A | 2 | cell attributes — **bit 0 set ⇒ 16-byte extended cell entries**, else 8-byte |
| 0x0C | 4 | offset to the cell array, relative to **section + 0x08** (always `0x18`) |
| 0x10 | 4 | OBJ mapping mode (see below) |
| 0x14 | 4 | VRAM-transfer data offset (0 = none) |
| 0x18 | 8 | unused (zero) |
| 0x20 | … | cell array, then the OAM pool |

Cell entry — 8 bytes (basic) or 16 bytes (extended):

| Off | Size | Field |
|---|---|---|
| 0x00 | 2 | number of OAM entries in this cell |
| 0x02 | 2 | cell attribute word |
| 0x04 | 4 | offset of this cell's OAM entries, relative to the **end of the cell array** |
| 0x08 | 2 | `s16 maxX` (extended only) |
| 0x0A | 2 | `s16 maxY` |
| 0x0C | 2 | `s16 minX` |
| 0x0E | 2 | `s16 minY` |

Real extended cell, `pl_poke_icon[2]`:

```
0010  4B 42 45 43 4C 00 00 00  02 00 01 00 18 00 00 00   KBEC size 0x4C, 2 cells, attr=1 (extended), cellOff=0x18
0020  00 00 00 00 00 00 00 00  00 00 00 00 00 00 00 00   mapping=0 (2D), no VRAM transfer
0030  01 00 06 08 00 00 00 00  0F 00 0F 00 F0 FF F0 FF   cell 0: 1 OAM, attr 0x0806, oamOff 0,
                                                          maxX=15 maxY=15 minX=-16 minY=-16
```

The bounding box `(-16,-16)..(15,15)` is exactly a centred 32×32 icon ✓, which also
confirms the field **order is max before min**.

Each OAM entry is 3 × `u16` (`attr0, attr1, attr2`), identical to hardware OAM:

```python
OAM_SIZE = {  # (shape, size) -> (w, h) in pixels
 (0,0):(8,8),   (0,1):(16,16), (0,2):(32,32), (0,3):(64,64),
 (1,0):(16,8),  (1,1):(32,8),  (1,2):(32,16), (1,3):(64,32),
 (2,0):(8,16),  (2,1):(8,32),  (2,2):(16,32), (2,3):(32,64),
}

def decode_oam(a0, a1, a2):
    y       = a0 & 0xFF
    if y >= 128: y -= 256
    rot     = bool(a0 & 0x0100)
    dsize   = rot and bool(a0 & 0x0200)          # double-size affine box
    disable = (not rot) and bool(a0 & 0x0200)
    mode    = (a0 >> 10) & 3                     # 0 normal, 1 blend, 2 window, 3 bitmap
    mosaic  = bool(a0 & 0x1000)
    depth8  = bool(a0 & 0x2000)                  # 1 = 256-colour OBJ
    shape   = (a0 >> 14) & 3
    x       = a1 & 0x01FF
    if x >= 256: x -= 512
    hflip   = (not rot) and bool(a1 & 0x1000)
    vflip   = (not rot) and bool(a1 & 0x2000)
    size    = (a1 >> 14) & 3
    tile    = a2 & 0x03FF
    prio    = (a2 >> 10) & 3
    pal     = (a2 >> 12) & 0xF
    w, h    = OAM_SIZE[(shape, size)]
    box     = (w*2, h*2) if dsize else (w, h)    # drawn box; SOURCE stays w x h
    return dict(x=x, y=y, w=w, h=h, box=box, tile=tile, pal=pal,
                hflip=hflip, vflip=vflip, depth8=depth8, rot=rot,
                disable=disable, prio=prio, mosaic=mosaic, mode=mode)
```

**Trap:** when `rot` is set, bit 9 means *double size*, not *disable*, and bits 12/13 of
attr1 are affine-matrix selector bits, **not** flip flags. Gen 5 Pokémon cells set `rot`
on every OAM entry. Extracting a static frame means using the `w×h` **source** size and
centring it in the `box`.

**Mapping mode** (`+0x10`): `0` = 2D (tile index is a flat char index), `1..4` = 1D with a
32/64/128/256-byte boundary. Observed: `0` for Gen 4 icon cells, `4` for Gen 5 Pokémon
cells. The byte offset of an OAM's first char is `tile_index × boundary`.

Verified composer (renders Gen 4 Pokémon icons with correct silhouettes —
`tools/_work/out/icons_gen4.png`):

```python
def compose_cell(ncer, ci, ncgr, nclr, mult, W=128, H=128, ox=64, oy=64):
    """mult = chars consumed per unit of the OAM tile index (boundary/32 at 4bpp)."""
    idx = unpack_indices(ncgr.data, ncgr.bpp)
    img = Image.new('RGBA', (W, H), (0,0,0,0)); px = img.load()
    for a in ncer.cells[ci]['oam']:
        o = decode_oam(*a)
        if o['disable']: continue
        psize = 16 if ncgr.bpp == 4 else 256
        pal = nclr.colors[o['pal']*psize : o['pal']*psize + psize] or nclr.colors
        base = o['tile'] * mult * 64                       # in PIXELS
        tw, th = o['w'] // 8, o['h'] // 8
        for ty in range(th):
            for tx in range(tw):
                cb = base + (ty*tw + tx) * 64              # 1D object char order
                for yy in range(8):
                    for xx in range(8):
                        v = idx[cb + yy*8 + xx]
                        if v == 0: continue
                        sx, sy = tx*8 + xx, ty*8 + yy
                        if o['hflip']: sx = o['w'] - 1 - sx
                        if o['vflip']: sy = o['h'] - 1 - sy
                        X = ox + o['x'] + sx + (o['box'][0] - o['w']) // 2
                        Y = oy + o['y'] + sy + (o['box'][1] - o['h']) // 2
                        if 0 <= X < W and 0 <= Y < H:
                            px[X, Y] = tuple(pal[v]) + (255,)
    return img
```

> Gen 4 icons come out with the **wrong colours** using `o['pal']` alone: the shared
> `pl_poke_icon[0]` NCLR holds 16 palettes of 16 colours and the per-species palette index
> lives in a table outside the NARC (ARM9/overlay). Shapes are correct, hues are not, until
> that table is located. **UNVERIFIED** where it lives.

### 4.6 NANR (`RNAN`) — animation

Section `KNBA` (= `ABNK`).

| Off | Size | Field |
|---|---|---|
| 0x00 | 4 | `"KNBA"` |
| 0x04 | 4 | section size |
| 0x08 | 2 | number of sequences |
| 0x0A | 2 | total number of frames |
| 0x0C | 4 | offset to sequence array, relative to **section + 0x08** |
| 0x10 | 4 | offset to frame array, same base |
| 0x14 | 4 | offset to element-value array, same base |
| 0x18 | 8 | unused (zero) |

Sequence entry, 16 bytes:

| Off | Size | Field |
|---|---|---|
| 0x00 | 2 | frame count |
| 0x02 | 2 | loop start frame |
| 0x04 | 2 | **element type**: `0` = index, `1` = index+SRT, `2` = index+T |
| 0x06 | 2 | animation type: 0 forward, 1 forward-loop, 2 reverse, 3 reverse-loop |
| 0x08 | 4 | playback mode |
| 0x0C | 4 | offset of this sequence's frames, relative to the frame array base |

Frame entry, 8 bytes: `u32 valueOffset; u16 duration (in 1/60 s); u16 0xBEEF;`

Element value, sized by the sequence's element type:

| Type | Size | Layout |
|---|---|---|
| 0 (index) | 4 | `u16 cellIndex; u16 padding (0xCCCC)` |
| 1 (SRT) | 16 | `u16 cellIndex; u16 rotZ; s32 scaleX; s32 scaleY; s16 px; s16 py` — scales are 20.12 fixed point (`0x1000` = 1.0) |
| 2 (T) | 8 | `u16 cellIndex; u16 padding (0xBEEF); s16 px; s16 py` |

Real bytes, `pl_poke_icon[1]`:

```
0010  4B 4E 42 41 58 00 00 00  02 00 02 00 18 00 00 00   KNBA size 0x58, 2 seqs, 2 frames, seqOff=0x18
0020  38 00 00 00 48 00 00 00  00 00 00 00 00 00 00 00   frameOff=0x38, valueOff=0x48
0030  01 00 00 00 00 00 01 00  01 00 00 00 00 00 00 00   seq0: 1 frame, loop 0, etype 0, atype 1, mode 1, off 0
```

Decoded sequences confirm the value layouts exactly:

```
pl_poke_icon[1]  seq nframes=1 etype=0 -> value (0, -13108)        # -13108 = 0xCCCC padding
W2 a/0/0/4[25]   seq0 nframes=12 etype=2 -> (0, -16657, 0, 0)      # -16657 = 0xBEEF padding, px=0 py=0
W2 a/0/0/4[25]   seq1 nframes=6  etype=1 -> (5, 0, 4096, 0, 4096, 0, 0, 0)
                                            index=5, rot=0, scaleX=0x1000=1.0, scaleY=0x1000=1.0, px=0, py=0
                                 next frame  (5, 0, 4096, 0, 3686, 0, 0, 0)   scaleY=3686/4096=0.90 (squash)
```

`NMCR` (`RCMN`, multi-cell) and `NMAR` (`RAMN`, multi-cell animation) chain several cells
into one composite. Both appear in Gen 5 Pokémon blocks. **Their internal layouts are
UNVERIFIED** — we did not need them to produce static sprites (see §5.2).

---

## 5. Pokémon battle sprites

### 5.1 Gen 4 — Platinum / HeartGold

**Archive:** `/poketool/pokegra/pl_pokegra.narc` — 2964 sub-files = **494 blocks of 6**,
indexed by national dex number (`block = species * 6`; block 0 is a dummy).

HeartGold uses the identical layout at **`/a/0/0/4`** (2964 sub-files, 11778676 bytes —
byte-for-byte the same size as Platinum's `pl_pokegra.narc`), and also ships a named copy at
`/pbr/pokegra.narc`. Everything in this section applies unchanged to HGSS.

| Slot | Content | Verified |
|---|---|---|
| +0 | back sprite, female | NCGR ×428, empty ×66 |
| +1 | back sprite, male | NCGR ×478, empty ×16 |
| +2 | front sprite, female | NCGR ×428, empty ×66 |
| +3 | front sprite, male | NCGR ×478, empty ×16 |
| +4 | normal palette | NCLR ×494 |
| +5 | shiny palette | NCLR ×494 |

Back/front assignment confirmed visually (`tools/_work/out/g4_slots.png`: slots 0–1 show
Bulbasaur from behind, slots 2–3 from the front). Genderless and gender-identical species
leave the female slots empty (`start == end` in BTAF) — **fall back to the male slot**.

Each sprite NCGR is **6448 bytes**: 16-byte container + 32-byte CHAR header + 6400 bytes
of pixels; `tiles = (H=10, W=20)` → **160 × 80 pixels, 4bpp, flags = 1 (linear)**. The
160×80 canvas is **two 80×80 animation frames side by side** — frame 1 at x 0..79, frame 2
at x 80..159. Confirmed for Bulbasaur, Charmander, Pikachu, Mewtwo and Lucario.

Companion archives:

* `/poketool/pokegra/pokegra.narc` — the **Diamond/Pearl** sprite set, still shipped inside
  Platinum. Same 2964/6 layout. **Different obfuscation direction** (see below).
* `/poketool/pokegra/pl_otherpoke.narc` — 253 files of alternate forms: indices 0..153 are
  6448-byte sprite NCGRs, 154..247 are 72-byte NCLRs, then `G G L G L`. Non-uniform;
  a hand-built index table is required. **UNVERIFIED** which form each index is.
* `/poketool/trgra/trfgra.narc` — trainer front sprites, **525 files = 105 blocks of 5**:
  `+0` OAM char strip NCGR (3248 B, tiles `0xFFFF`), `+1` NCLR, `+2` NCER, `+3` NANR,
  `+4` the **160×80 linear battle sprite** (6448 B, obfuscated, same as Pokémon).
* `/poketool/trgra/trbgra.narc` — trainer back sprites, 55 files, same 5-file shape.
* `/poketool/icongra/pl_poke_icon.narc` — 547 files: `[0]` shared 256-colour NCLR,
  `[1..6]` NANR/NCER pairs, `[7 + species]` a 1072-byte NCGR (32 chars = two 32×32 frames).

#### 5.1.1 The XOR obfuscation

Gen 4 Pokémon and trainer battle sprites store their **pixel data** (the CHAR payload only —
headers and palettes are plaintext) XOR-masked with a 32-bit LCG keystream.

The LCG is the standard Pokémon PRNG:

```
seed = (seed * 0x41C64E6D + 0x6073) & 0xFFFFFFFF
```

and the mask applied to each `u16` of pixel data is the **low 16 bits of the current seed**.
There are two directions, and *which one a file uses depends on the game that authored it*:

| Variant | Seed | Iteration | Used by |
|---|---|---|---|
| **forward** | the **first** `u16` of the pixel buffer | index `0 → n-1` | **Platinum**, **HeartGold** (`pl_pokegra`, `pl_otherpoke`, `trfgra`, `trbgra`, HGSS `/a/0/0/4`) |
| **backward** | the **last** `u16` of the pixel buffer | index `n-1 → 0` | **Diamond/Pearl** (`pokegra.narc` as shipped inside Platinum) |

Because the seed *is* the halfword it first masks, the first (forward) or last (backward)
decoded halfword is always **0x0000** — a free self-check.

```python
MUL, ADD, U32 = 0x41C64E6D, 0x6073, 0xFFFFFFFF

def xor_lcg(data, backward):
    n = len(data) // 2
    w = list(struct.unpack_from('<%dH' % n, bytes(data)))
    seed = w[n-1] if backward else w[0]
    for i in (range(n-1, -1, -1) if backward else range(n)):
        w[i] ^= seed & 0xFFFF
        seed = (seed * MUL + ADD) & U32
    return bytearray(struct.pack('<%dH' % n, *w))
```

Encryption is the *same function* — it is an involution given the ciphertext/plaintext
seed relationship, because the seeding halfword decrypts to 0 and re-encrypts to itself.

**Detection.** Encrypted pixel data is statistically indistinguishable from random: the
nibble entropy is ≈4.000 bits. Real 4bpp art is far from uniform. Measured on
`pl_pokegra[6]`:

```
raw          H = 3.999   first 16 bytes: 77 A0 1E F5 39 E2 B8 10 CB 8E E2 06 AD 2A 1C 42
forward      H = 1.777   first 16 bytes: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
backward     H = 3.948   first 16 bytes: 72 76 84 9D 5A E6 08 ED DA 86 B4 2D 22 46 10 39
```

```python
def nibble_entropy(buf):
    import math, collections
    c = collections.Counter()
    for x in buf:
        c[x & 0xF] += 1; c[x >> 4] += 1
    t = float(sum(c.values()))
    return -sum((v/t) * math.log(v/t, 2) for v in c.values() if v)

def auto_decrypt(buf):
    if nibble_entropy(buf) < 3.6:
        return buf, 'plain'
    f, b = xor_lcg(buf, False), xor_lcg(buf, True)
    hf, hb = nibble_entropy(f), nibble_entropy(b)
    if hf < hb and hf < 3.6: return f, 'forward'
    if hb < 3.6:             return b, 'backward'
    return buf, 'plain'
```

Classification over whole archives (threshold 3.6 bits):

| Archive | NCGRs | plain | forward | backward |
|---|---|---|---|---|
| Platinum `pl_pokegra.narc` | 1812 | 4 | **1808** | 0 |
| Platinum `pokegra.narc` (DP) | 1812 | 4 | 0 | **1808** |
| Platinum `pl_otherpoke.narc` | 157 | 0 | **157** | 0 |
| Platinum `trfgra.narc` | 210 | 105 | **105** | 0 |
| Platinum `trbgra.narc` | 22 | 11 | **11** | 0 |
| Platinum `pl_poke_icon.narc` | 540 | **540** | 0 | 0 |
| HeartGold `/a/0/0/4` (first 400) | 256 | 4 | **252** | 0 |
| White 2 `/a/0/0/4` | sampled | **all** | 0 | 0 |
| Black `/a/0/0/4` | sampled | **all** | 0 | 0 |

The 4 "plain" hits in each pokegra are tiny placeholder entries. Note that **Pokémon icons
are never obfuscated**, and in trainer archives only the 160×80 battle sprite is — the OAM
char strip at `+0` is plaintext.

#### 5.1.2 Gen 4 pipeline

```python
def gen4_sprite(narc, species, slot, shiny=False):
    b   = species * 6
    raw = narc[b + slot]
    if not raw:                                  # empty -> no such gender variant
        return None
    g   = read_ncgr(maybe_decompress(raw))       # pl_pokegra is never compressed
    pal = read_nclr(maybe_decompress(narc[b + (5 if shiny else 4)]))[:16]
    data, mode = auto_decrypt(g['data'])
    W, H = g['tx'] * 8, g['ty'] * 8              # 160 x 80
    px = unpack_indices(data, g['bpp'])[:W*H]
    if not g['linear']:
        px = untile(px, W, H)
    return px, W, H, pal, mode
```

Verified end to end for species 1, 4, 25, 448 in both `pl_pokegra` (reports `forward`) and
`pokegra` (reports `backward`), producing clean Bulbasaur/Charmander/Pikachu/Lucario front
and back sprites plus correct shiny palettes.

### 5.2 Gen 5 — Black / White 2

**Archive:** `/a/0/0/4` — 15065 sub-files in White 2, 14285 in Black (and `/a/0/5/1` in
White 2 is the 14285-entry BW-era copy). **20 sub-files per form.**

**How many blocks, exactly.** `len(narc) // 20` over-counts: the archive ends in a tail of
loose resources, not more form blocks. Scanning until slot `+0`/`+9` stops being a
144-char 12×12 4bpp NCGR:

| Archive | sub-files | conforming form blocks | covered indices | tail |
|---|---|---|---|---|
| White 2 `/a/0/0/4` | 15065 | **751** (0–750) | 0–15019 | 45 entries |
| Black `/a/0/0/4` | 14285 | **712** (0–711) | 0–14239 | 45 entries |
| White 2 `/a/0/5/1` | 14285 | **712** (0–711) | 0–14239 | 45 entries |

Block 751 in White 2 breaks the pattern immediately (`+0` is a 32×16 linear 512-char NCGR,
`+9` is an `RCMN`) and the last five entries are loose 72-byte NCLRs. **Stop the block loop
when slot `+0` fails the 12×12/144-char check**, not at `len(narc) // 20`.

Across White 2's 751 blocks, **1502 of 1506** front/back NCGRs are exactly
`(12×12 tiles, 4bpp, tiled, 144 chars)` and **all 1506 palettes hold exactly 16 colours** —
the layout below is not a special case, it is the rule. (`/a/0/5/1`, the BW-era copy, is the
exception: 717 of its palette slots hold 256 colours.)

| Slot | Content | White 2, form 1 |
|---|---|---|
| +0 | **front sprite** NCGR | LZ11 → 4656 B, 12×12 tiles, 4bpp, tiled, 144 chars |
| +1 | (empty) | |
| +2 | front animation part-atlas NCGR | LZ11 → 16448 B, 32×16 tiles, 4bpp, **linear**, 512 chars |
| +3 | (empty) | |
| +4 | front NCER | 11 cells, mapping 4, basic (8-byte) cells |
| +5 | front NANR | LZ11 → 20 sequences, 216 frames |
| +6 | front NMCR (`RCMN`) | multi-cell |
| +7 | front NMAR (`RAMN`) | multi-cell animation |
| +8 | front per-cell table | `u32 count` + 12 pad + `count × 48` bytes; `count == NCER.ncells` |
| +9 … +17 | identical nine slots for the **back sprite** | |
| +18 | **normal palette** NCLR | 72 B, 16 colours |
| +19 | **shiny palette** NCLR | 72 B, 16 colours |

`+8` layout verified by size arithmetic: form 0 has `count=1, size=64`; form 1 has
`count=11, size=544`; `(544-64)/(11-1) = 48` and `16 + 11*48 = 544` ✓. Its contents are
**UNVERIFIED**.

**Gen 5 sprites in these ROMs are NOT obfuscated.** They are LZ11-compressed instead.
Measured nibble entropy of White 2 `/a/0/0/4[20]` char data: **0.750** raw (already real
art). Applying either XOR direction *raises* entropy to 3.999 — i.e. it destroys the image.
The same holds for Black. Compression replaced encryption in Gen 5.

#### 5.2.1 The 96×96 char layout — the one non-obvious step

The `+0`/`+9` NCGR declares `12 × 12` tiles (96 × 96 px) and `flags = 0` (tiled), but a
plain 96-wide untile produces garbage. The chars are stored as **four 1D-mapped OAM
objects** covering the 96×96 canvas in 64×64 super-blocks, row-major, clipped at the edges:

| Object | Position | Size | Chars |
|---|---|---|---|
| 1 | (0, 0) | 64 × 64 | 64 |
| 2 | (64, 0) | 32 × 64 | 32 |
| 3 | (0, 64) | 64 × 32 | 32 |
| 4 | (64, 64) | 32 × 32 | 16 |
| | | | **144** ✓ |

Inside each object the chars are row-major 8×8 tiles. Equivalent phrasing: tile the canvas
into 64×64 super-blocks scanned row-major, clip each to the canvas, and lay chars out
row-major within each clipped block.

```python
GEN5_OBJS = [(0, 0, 64, 64), (64, 0, 32, 64), (0, 64, 64, 32), (64, 64, 32, 32)]

def gen5_assemble(px):
    out = [0] * (96 * 96); c = 0
    for ox, oy, ow, oh in GEN5_OBJS:
        for ty in range(oh // 8):
            for tx in range(ow // 8):
                base = c * 64; c += 1
                for y in range(8):
                    r = (oy + ty*8 + y) * 96 + ox + tx*8
                    out[r:r+8] = px[base + y*8 : base + y*8 + 8]
    return out
```

Verified to produce pixel-perfect 96×96 sprites for Bulbasaur, Charmander, Squirtle,
Pikachu, Mewtwo, Lucario, Arceus and Reshiram, in front, back and shiny variants
(`tools/_work/out/g5_quad.png`).

Slots `+2`/`+11` (the 256×128 linear atlas) hold **animation parts only** — detached heads,
limbs and bulbs. Rendering that atlas as a flat linear image shows the parts; rendering it
as tiled shows scrambled noise, which confirms the `flags & 1` reading
(`tools/_work/out/cmp_gen5.png`). You do **not** need it for a static sprite.

#### 5.2.2 Gen 5 pipeline

```python
def gen5_sprite(narc, form, back=False, shiny=False):
    base = form * 20
    g    = read_ncgr(maybe_decompress(narc[base + (9 if back else 0)]))
    pal  = read_nclr(maybe_decompress(narc[base + (19 if shiny else 18)]))[:16]
    return gen5_assemble(unpack_indices(g['data'], g['bpp'])), 96, 96, pal
```

`form` here is a **form index, not a dex number** — 751 blocks in White 2 for 649 species
plus alternate forms. The dex-number → form-index table lives outside the archive.
**UNVERIFIED** where; for forms 1, 4, 25, 448 and 643 the index happens to equal the dex
number, which is consistent with "base forms first, alternates appended".

### 5.3 Writing the PNG

Palette index 0 is transparent for sprites:

```python
def write_png(path, idx, W, H, pal):
    im = Image.new('RGBA', (W, H)); p = im.load()
    for y in range(H):
        b = y * W
        for x in range(W):
            i = idx[b + x]
            p[x, y] = (0, 0, 0, 0) if i == 0 else tuple(pal[i]) + (255,)
    im.save(path)
```

---

## 6. Complete reference extractor

`tools/_work/reference_extractor.py` is a single self-contained file implementing
everything above — NDS walk, NARC, LZ10/LZ11, NCLR/NCGR readers, the XOR layer, both
sprite pipelines and PNG output. Verified run:

```
Platinum CPUE : 462 FAT entries, 340 named files, 122 overlays
  species   1  Pt 160x80 crypt=forward  | DP crypt=backward
  species   4  Pt 160x80 crypt=forward  | DP crypt=backward
  species  25  Pt 160x80 crypt=forward  | DP crypt=backward
  species 448  Pt 160x80 crypt=forward  | DP crypt=backward
White2 IRDO : 662 FAT entries, 318 named files, 344 overlays
  form   1  96x96 crypt=plain
  form   4  96x96 crypt=plain
  form  25  96x96 crypt=plain
  form 448  96x96 crypt=plain
  form 643  96x96 crypt=plain
```

27 PNGs were produced and visually confirmed correct (front, back and shiny for each).

### 6.1 The doc is self-testing

`tools/_work/doc_selftest.py` extracts **every `python` fence in this file**, `exec`s them
into one namespace, and then drives both ROMs using nothing but the functions defined here.
Last run:

```
exec'd 25/25 doc blocks
symbols defined by the doc: 28/28   missing: none
Platinum CPUE: 462 FAT, 340 named, 122 overlays, 89 dirs  (sum ok: True)  capacity=134217728 used=104607804
  doc-code Pt species   1 -> 160x80 crypt=forward  | DP crypt=backward
  doc-code Pt species  25 -> 160x80 crypt=forward  | DP crypt=backward
  doc-code Pt species 448 -> 160x80 crypt=forward  | DP crypt=backward
White2 IRDO:   662 FAT, 318 named, 344 overlays, 39 dirs  (sum ok: True)  capacity=536870912 used=287647804
  doc-code W2 form   1 -> 96x96, 16 colours
  doc-code W2 form  25 -> 96x96, 16 colours
  doc-code W2 form 643 -> 96x96, 16 colours
```

If you change a snippet above, re-run that script. A green run means the code in this
document is literally the code that works.

### 6.2 Supporting scratch scripts (all in `tools/_work/`, gitignored)

| Script | What it proves |
|---|---|
| `nds.py` | header + FNT + FAT walker; prints the summary table in §0 |
| `dump_listing.py` | writes `listing_<rom>.txt` (Appendices A and B) |
| `narc.py` | NARC reader; dumps chunk offsets and sub-file magics |
| `lzss.py` / `test_lzss.py` | LZ10/LZ11/RLE/diff; verifies every LZ11 blob in `/a/0/0/4` |
| `nitro.py` | NCLR/NCGR/NSCR/NCER/NANR classes |
| `hexprobe*.py`, `final_facts.py` | the raw hex dumps and field censuses quoted above |
| `crypt_probe.py` / `crypt_scan.py` | the entropy tables in §5.1.1 |
| `brute.py`, `g5_zoom.py`, `g5_final.py`, `g5_quad.py` | how the Gen 5 96x96 layout was found |
| `nscr_test.py` | renders the Poketch background |
| `cell_test*.py` | NCER composition |
| `reference_extractor.py` | the self-contained extractor in §6 |
| `doc_selftest.py` | runs this document's own code |

Rendered proof images land in `tools/_work/out/`: `sheet_gen4_front.png`,
`cmp_gen4_decrypt.png`, `cmp_gen5.png`, `g5_quad.png`, `bg_poketch.png`,
`icons_gen4.png`, `doc_selftest.png`.

---

## 7. Traps, in the order they will bite you

1. **BTAF sub-file count is at +0x08**, not +0x06. Wrong offset silently yields 0 files.
2. **Gen 5 sprite NCGRs lie about `filesize` and section size.** Trust `CHAR.dataSize` and
   clamp every section read to the actual buffer length.
3. **Nitro magics are byte-reversed on disk.** Match `RLCN`, not `NCLR`.
4. **4bpp low nibble is the left pixel.** Reversing this mirrors every 2-pixel pair.
5. **`flags & 1` on CHAR means *linear*, i.e. do NOT untile.** Gen 4 battle sprites are
   linear; almost everything else is tiled.
6. **LZ back-references overlap.** Copy byte-at-a-time, never with a slice.
7. **First-byte compression sniffing has a ~5 % false-positive rate.** Validate the decoded
   length and magic, or hard-code what each archive holds.
8. **Empty NARC sub-files are normal** (`start == end`). Gen 4 female sprite slots and Gen 5
   slots +1/+3 are routinely empty; guard before parsing.
9. **The XOR direction is per-authoring-game, not per-generation.** Platinum ships both
   `pl_pokegra` (forward) and `pokegra` (backward) side by side. Detect, don't assume.
10. **Gen 5 sprites are not obfuscated** — running the XOR on them destroys the image.
    Entropy-gate before decrypting.
11. **The Gen 5 96×96 canvas is not a plain 12×12 tile grid** — it is four 1D-mapped OAM
    objects (§5.2.1).
12. **OAM bit 9 of attr0 is *disable* only when bit 8 (rot) is clear**; with rot set it is
    *double size*, and attr1 bits 12/13 stop being flip flags.
13. **NCLR's depth field can disagree with reality** (DPPt pokegra palettes declare 8bpp but
    hold 16 colours). Derive the count from `dataSize / 2`.
14. **Pillow needs the Anaconda DLL directories on `PATH`** in this environment (§0).
15. **Don't use `file_length` as the ROM length** — use header `+0x80` (`used_size`).

---

## Appendix A — Platinum complete file listing

Format: `file-ID  path  ROM-offset  size`. 340 named files (file IDs 122–461; IDs 0–121 are
the ARM9 overlays).

```
 122  /application/balloon/graphic/balloon_gra.narc         off=0x05F32000  size=   303008
 123  /application/bucket/ballslow_data.narc                off=0x05F9B800  size=      420
 124  /application/custom_ball/data/cb_data.narc            off=0x05C9F000  size=    60812
 125  /application/custom_ball/edit/pl_cb_data.narc         off=0x05F16E00  size=     3132
 126  /application/wifi_earth/wifi_earth.narc               off=0x05C78E00  size=   152180
 127  /application/wifi_earth/wifi_earth_place.narc         off=0x05C9E200  size=     3272
 128  /application/wifi_lobby/map_conv/wflby_map.narc       off=0x05F7C000  size=    17040
 129  /application/zukanlist/zkn_data/zukan_data.narc       off=0x05C6DA00  size=    22664
 130  /application/zukanlist/zkn_data/zukan_data_gira.narc  off=0x05C73400  size=    22668
 131  /application/zukanlist/zkn_data/zukan_enc_diamond.narc  off=0x05ED4C00  size=    71456
 132  /application/zukanlist/zkn_data/zukan_enc_pearl.narc  off=0x05EE6400  size=    71432
 133  /application/zukanlist/zkn_data/zukan_enc_platinum.narc  off=0x05EF7C00  size=    71460
 134  /arc/area_win_gra.narc                                off=0x05CCAE00  size=    33388
 135  /arc/balance_ball_gra.narc                            off=0x05CD3200  size=   141356
 136  /arc/bm_anime.narc                                    off=0x05CF5C00  size=    73040
 137  /arc/bm_anime_list.narc                               off=0x05D07A00  size=    16572
 138  /arc/codein_gra.narc                                  off=0x05D0BC00  size=    93268
 139  /arc/demo_tengan_gra.narc                             off=0x05D22A00  size=   953056
 140  /arc/email_gra.narc                                   off=0x05E0B600  size=    26124
 141  /arc/encdata_ex.narc                                  off=0x05E11E00  size=     1828
 142  /arc/manene.narc                                      off=0x05E12600  size=   257844
 143  /arc/plgym_ghost.narc                                 off=0x05E51600  size=     4936
 144  /arc/ppark.narc                                       off=0x05E52A00  size=     3020
 145  /arc/ship_demo.narc                                   off=0x05E53600  size=    95064
 146  /arc/ship_demo_pl.narc                                off=0x05E6AA00  size=    62036
 147  /arc/tv.narc                                          off=0x05E79E00  size=     1160
 148  /battle/b_pl_stage/pl_bsdpm.narc                      off=0x05F89E00  size=    11524
 149  /battle/b_pl_tower/pl_btdpm.narc                      off=0x05F8CC00  size=    22876
 150  /battle/b_pl_tower/pl_btdtr.narc                      off=0x05F92600  size=    37160
 151  /battle/b_tower/btdpm.narc                            off=0x05EC6E00  size=    22876
 152  /battle/b_tower/btdtr.narc                            off=0x05ECC800  size=    33728
 153  /battle/graphic/b_bag_gra.narc                        off=0x0372E600  size=    20228
 154  /battle/graphic/b_plist_gra.narc                      off=0x03733600  size=    74408
 155  /battle/graphic/batt_bg.narc                          off=0x03745A00  size=   640124
 156  /battle/graphic/batt_obj.narc                         off=0x037E2000  size=   131676
 157  /battle/graphic/pl_b_plist_gra.narc                   off=0x03802400  size=    74408
 158  /battle/graphic/pl_batt_bg.narc                       off=0x03814800  size=   852772
 159  /battle/graphic/pl_batt_obj.narc                      off=0x038E4C00  size=   169112
 160  /battle/graphic/vs_demo_gra.narc                      off=0x0390E200  size=    44416
 161  /battle/skill/be_seq.narc                             off=0x0395AA00  size=    16940
 162  /battle/skill/sub_seq.narc                            off=0x0395EE00  size=    53196
 163  /battle/skill/waza_seq.narc                           off=0x0396BE00  size=     6416
 164  /battle/tr_ai/tr_ai_seq.narc                          off=0x05CC0800  size=    42448
 165  /contest/data/contest_data.narc                       off=0x05C5F000  size=    14140
 166  /contest/graphic/contest_bg.narc                      off=0x05FA1000  size=    81248
 167  /contest/graphic/contest_obj.narc                     off=0x05FB4E00  size=    25108
 168  /data/arealight.narc                                  off=0x00434800  size=     8376
 169  /data/battle_win.NSCR                                 off=0x00436A00  size=     2084
 170  /data/btower_canm.resdat                              off=0x00437400  size=       52
 171  /data/btower_celact.cldat                             off=0x00437600  size=       64
 172  /data/btower_cell.resdat                              off=0x00437800  size=       52
 173  /data/btower_chr.resdat                               off=0x00437A00  size=       52
 174  /data/btower_pal.resdat                               off=0x00437C00  size=       52
 175  /data/cell0.NCGR                                      off=0x00437E00  size=     8240
 176  /data/cell0.NCLR                                      off=0x0043A000  size=      552
 177  /data/clact_default.NANR                              off=0x0043A400  size=      111
 178  /data/crystal.nsbmd                                   off=0x0043A600  size=     3332
 179  /data/demo_climax.narc                                off=0x0043B400  size=   472620
 180  /data/dp_areawindow.NCGR                              off=0x004AEC00  size=      368
 181  /data/dp_areawindow.NCLR                              off=0x004AEE00  size=      552
 182  /data/dt_test_celact.txt                              off=0x004AF200  size=       54
 183  /data/dt_test_res_cell.txt                            off=0x004AF400  size=       38
 184  /data/dt_test_res_cellanm.txt                         off=0x004AF600  size=       38
 185  /data/dt_test_res_char.txt                            off=0x004AF800  size=       43
 186  /data/dt_test_res_multi.txt                           off=0x004AFA00  size=       16
 187  /data/dt_test_res_multianm.txt                        off=0x004AFC00  size=       16
 188  /data/dt_test_res_pltt.txt                            off=0x004AFE00  size=       45
 189  /data/dun_sea.nsbtx                                   off=0x004B0000  size=     1400
 190  /data/eoo.dat                                         off=0x004B0600  size=   277504
 191  /data/exdata.dat                                      off=0x004F4200  size=      292
 192  /data/field_cutin.narc                                off=0x004F4400  size=    23072
 193  /data/fld_anime0.bin                                  off=0x004FA000  size=       72
 194  /data/fld_anime1.bin                                  off=0x004FA200  size=       72
 195  /data/fld_anime10.bin                                 off=0x004FA400  size=       72
 196  /data/fld_anime2.bin                                  off=0x004FA600  size=       72
 197  /data/fld_anime3.bin                                  off=0x004FA800  size=       72
 198  /data/fld_anime4.bin                                  off=0x004FAA00  size=       72
 199  /data/fld_anime5.bin                                  off=0x004FAC00  size=       72
 200  /data/fld_anime6.bin                                  off=0x004FAE00  size=       72
 201  /data/fld_anime7.bin                                  off=0x004FB000  size=       72
 202  /data/fld_anime8.bin                                  off=0x004FB200  size=       72
 203  /data/fld_anime9.bin                                  off=0x004FB400  size=       72
 204  /data/fldtanime.narc                                  off=0x004FB600  size=   154640
 205  /data/fs_kanban.nsbca                                 off=0x00521400  size=     2036
 206  /data/ground0.NCGR                                    off=0x00521C00  size=    32816
 207  /data/ground0.NCLR                                    off=0x00529E00  size=      552
 208  /data/ground0.NSCR                                    off=0x0052A200  size=     2084
 209  /data/guru2.narc                                      off=0x0052AC00  size=   191724
 210  /data/kemu_itpconv.dat                                off=0x00559A00  size=       20
 211  /data/lake_anim.nsbtx                                 off=0x00559C00  size=     4432
 212  /data/miniasahamabe.nsbtx                             off=0x0055AE00  size=     4488
 213  /data/miniasasea.nsbtx                                off=0x0055C000  size=     1400
 214  /data/minihamabe.nsbtx                                off=0x0055C600  size=     4488
 215  /data/minimum.nsbtx                                   off=0x0055D800  size=     1400
 216  /data/minirhana.nsbtx                                 off=0x0055DE00  size=      712
 217  /data/namein.narc                                     off=0x0055E200  size=    16292
 218  /data/nfont.NCGR                                      off=0x00562200  size=    32816
 219  /data/nfont.NCLR                                      off=0x0056A400  size=      552
 220  /data/pc.nsbca                                        off=0x0056A800  size=      396
 221  /data/pl_wifi.ncgr                                    off=0x0056AA00  size=      576
 222  /data/pl_wm.ncgr                                      off=0x0056AE00  size=      576
 223  /data/pl_wm.nclr                                      off=0x0056B200  size=      552
 224  /data/plbr.dat                                        off=0x0056B600  size=   420928
 225  /data/plist_canm.resdat                               off=0x005D2400  size=      196
 226  /data/plist_cell.resdat                               off=0x005D2600  size=      196
 227  /data/plist_chr.resdat                                off=0x005D2800  size=      316
 228  /data/plist_h.cldat                                   off=0x005D2A00  size=      416
 229  /data/plist_pal.resdat                                off=0x005D2C00  size=      148
 230  /data/porucase_canm.resdat                            off=0x005D2E00  size=       76
 231  /data/porucase_celact.cldat                           off=0x005D3000  size=       96
 232  /data/porucase_cell.resdat                            off=0x005D3200  size=       76
 233  /data/porucase_chr.resdat                             off=0x005D3400  size=       76
 234  /data/porucase_pal.resdat                             off=0x005D3600  size=       52
 235  /data/pst_canm.resdat                                 off=0x005D3800  size=      436
 236  /data/pst_cell.resdat                                 off=0x005D3A00  size=      436
 237  /data/pst_chr.resdat                                  off=0x005D3C00  size=     1060
 238  /data/pst_h.cldat                                     off=0x005D4200  size=     1408
 239  /data/pst_pal.resdat                                  off=0x005D4800  size=      172
 240  /data/shop_canm.resdat                                off=0x005D4A00  size=      100
 241  /data/shop_cell.resdat                                off=0x005D4C00  size=      100
 242  /data/shop_chr.resdat                                 off=0x005D4E00  size=      100
 243  /data/shop_h.cldat                                    off=0x005D5000  size=      128
 244  /data/shop_pal.resdat                                 off=0x005D5200  size=       76
 245  /data/slot.narc                                       off=0x005D5400  size=    88388
 246  /data/smptm_koori.NANR                                off=0x005EAE00  size=      163
 247  /data/smptm_koori.NCER                                off=0x005EB000  size=      215
 248  /data/smptm_koori.NCGR                                off=0x005EB200  size=     3248
 249  /data/smptm_koori.NCLR                                off=0x005EC000  size=      552
 250  /data/smptm_nemuri.NANR                               off=0x005EC400  size=      111
 251  /data/smptm_nemuri.NCER                               off=0x005EC600  size=       99
 252  /data/smptm_nemuri.NCGR                               off=0x005EC800  size=      560
 253  /data/smptm_nemuri.NCLR                               off=0x005ECC00  size=      552
 254  /data/str2uni.bin                                     off=0x005ED000  size=     4832
 255  /data/t3_fl_b.nsbtx                                   off=0x005EE400  size=      592
 256  /data/t3_fl_p.nsbtx                                   off=0x005EE800  size=      592
 257  /data/t3_fl_r.nsbtx                                   off=0x005EEC00  size=      592
 258  /data/t3_fl_y.nsbtx                                   off=0x005EF000  size=      592
 259  /data/test.atr                                        off=0x005EF400  size=     2048
 260  /data/tmap_block.dat                                  off=0x005EFC00  size=     4372
 261  /data/tmap_flags.dat                                  off=0x005F0E00  size=      732
 262  /data/tmapn_canm.resdat                               off=0x005F1200  size=      148
 263  /data/tmapn_celact.cldat                              off=0x005F1400  size=      192
 264  /data/tmapn_celact.txt                                off=0x005F1600  size=      268
 265  /data/tmapn_cell.resdat                               off=0x005F1800  size=      148
 266  /data/tmapn_chr.resdat                                off=0x005F1A00  size=      148
 267  /data/tmapn_pal.resdat                                off=0x005F1C00  size=       76
 268  /data/tmapn_res_canm.txt                              off=0x005F1E00  size=      170
 269  /data/tmapn_res_cell.txt                              off=0x005F2000  size=      186
 270  /data/tmapn_res_chr.txt                               off=0x005F2200  size=      220
 271  /data/tmapn_res_pal.txt                               off=0x005F2400  size=      149
 272  /data/tradelist.narc                                  off=0x005F2600  size=    10868
 273  /data/trapmark.narc                                   off=0x005F5200  size=      612
 274  /data/tw_arc_etc.naix                                 off=0x005F5600  size=     1485
 275  /data/tw_arc_etc.narc                                 off=0x005F5C00  size=    22488
 276  /data/ug_anim.narc                                    off=0x005FB400  size=    23680
 277  /data/ug_base_cur.nsbmd                               off=0x00601200  size=     1684
 278  /data/ug_boygirl.NCGR                                 off=0x00601A00  size=     4656
 279  /data/ug_boygirl.NCLR                                 off=0x00602E00  size=      552
 280  /data/ug_fossil.narc                                  off=0x00603200  size=    16088
 281  /data/ug_hero.NANR                                    off=0x00607200  size=      249
 282  /data/ug_hero.NCER                                    off=0x00607400  size=      265
 283  /data/ug_hole.NANR                                    off=0x00607600  size=      214
 284  /data/ug_hole.NCER                                    off=0x00607800  size=      162
 285  /data/ug_hole.NCGR                                    off=0x00607A00  size=     1328
 286  /data/ug_parts.narc                                   off=0x00608000  size=   133020
 287  /data/ug_radar.narc                                   off=0x00628800  size=    14440
 288  /data/ug_trap.narc                                    off=0x0062C200  size=   121772
 289  /data/ugeffect_obj_graphic.narc                       off=0x00649E00  size=    19816
 290  /data/uground_cell.resdat                             off=0x0064EC00  size=       76
 291  /data/uground_cellanm.resdat                          off=0x0064EE00  size=       76
 292  /data/uground_char.resdat                             off=0x0064F000  size=       76
 293  /data/uground_char2.resdat                            off=0x0064F200  size=       76
 294  /data/uground_clact.cldat                             off=0x0064F400  size=       96
 295  /data/uground_pltt.resdat                             off=0x0064F600  size=       52
 296  /data/uground_pltt2.resdat                            off=0x0064F800  size=       52
 297  /data/ugroundeffect.naix                              off=0x0064FA00  size=      765
 298  /data/ugroundeffect.narc                              off=0x0064FE00  size=      612
 299  /data/underg_radar.narc                               off=0x00650200  size=    41524
 300  /data/UTF16.dat                                       off=0x00434600  size=      490
 301  /data/utility.bin                                     off=0x0065A600  size=   929852
 302  /data/weather_sys.narc                                off=0x0073D800  size=    78320
 303  /data/wifi.ncgr                                       off=0x00750A00  size=      576
 304  /data/wifip2pmatch.narc                               off=0x00750E00  size=   150628
 305  /data/wm.ncgr                                         off=0x00775C00  size=      576
 306  /data/wm.nclr                                         off=0x00776000  size=      552
 307  /data/mmodel/fldeff.narc                              off=0x04434400  size=   320780
 308  /data/mmodel/mmodel.narc                              off=0x042CE400  size=  1465988
 309  /data/sound/pl_sound_data.sdat                        off=0x00E99A00  size=  7947008
 310  /data/sound/sound_data.sdat                           off=0x00776400  size=  7484768
 311  /debug/cb_edit/d_test.narc                            off=0x05F14000  size=    11744
 312  /demo/egg/data/egg_data.narc                          off=0x05CADE00  size=    11004
 313  /demo/egg/data/particle/egg_demo_particle.narc        off=0x05CB0A00  size=     9708
 314  /demo/intro/intro.narc                                off=0x05E86E00  size=   112620
 315  /demo/intro/intro_tv.narc                             off=0x05EA2600  size=   109188
 316  /demo/shinka/data/particle/shinka_demo_particle.narc  off=0x05E84800  size=     9364
 317  /demo/syoujyou/syoujyou.narc                          off=0x05EBD200  size=    39748
 318  /demo/title/op_demo.narc                              off=0x05FBB200  size=  1257224
 319  /demo/title/titledemo.narc                            off=0x060EE200  size=   219192
 320  /dwc/utility.bin                                      off=0x062E0000  size=   929852
 321  /fielddata/areadata/area_data.narc                    off=0x049A7600  size=     1252
 322  /fielddata/areadata/area_build_model/area_build.narc  off=0x049A7C00  size=     6468
 323  /fielddata/areadata/area_build_model/areabm_texset.narc  off=0x049A9600  size=  1617848
 324  /fielddata/areadata/area_map_tex/map_tex_set.narc     off=0x04B34600  size=  1872684
 325  /fielddata/areadata/area_move_model/move_model_list.narc  off=0x04CFDA00  size=     1432
 326  /fielddata/build_model/build_model.narc               off=0x0477BE00  size=  2254892
 327  /fielddata/build_model/build_model_matshp.dat         off=0x049A2800  size=     6400
 328  /fielddata/encountdata/d_enc_data.narc                off=0x04741C00  size=    79108
 329  /fielddata/encountdata/p_enc_data.narc                off=0x04755200  size=    79108
 330  /fielddata/encountdata/pl_enc_data.narc               off=0x04768800  size=    79108
 331  /fielddata/eventdata/zone_event.narc                  off=0x0471B200  size=   157800
 332  /fielddata/land_data/land_data.narc                   off=0x04CFE000  size= 16125840
 333  /fielddata/mapmatrix/map_matrix.narc                  off=0x049A4200  size=    13052
 334  /fielddata/maptable/mapname.bin                       off=0x05E7A400  size=     9488
 335  /fielddata/mm_list/move_model_list.narc               off=0x05CB3000  size=      608
 336  /fielddata/pokemon_trade/fld_trade.narc               off=0x06123C00  size=      404
 337  /fielddata/script/scr_seq.narc                        off=0x0397F200  size=   304476
 338  /fielddata/tornworld/tw_arc.narc                      off=0x05F80400  size=     7696
 339  /fielddata/tornworld/tw_arc_attr.narc                 off=0x05F82400  size=    24724
 340  /frontier/script/fr_script.narc                       off=0x05F17C00  size=    42716
 341  /graphic/bag_gra.narc                                 off=0x039C9800  size=   105588
 342  /graphic/box.narc                                     off=0x039E3600  size=   149956
 343  /graphic/btower.narc                                  off=0x03A08000  size=    16888
 344  /graphic/bucket.narc                                  off=0x03A0C200  size=   259696
 345  /graphic/config_gra.narc                              off=0x03A4BA00  size=      684
 346  /graphic/demo_trade.narc                              off=0x03A4BE00  size=    31512
 347  /graphic/dendou_demo.narc                             off=0x03A53A00  size=     1564
 348  /graphic/dendou_pc.narc                               off=0x03A54200  size=      668
 349  /graphic/ending.narc                                  off=0x03A54600  size=  1854944
 350  /graphic/ev_pokeselect.narc                           off=0x03C19400  size=   140580
 351  /graphic/f_note_gra.narc                              off=0x03C3BA00  size=    10620
 352  /graphic/field_board.narc                             off=0x03C3E400  size=    43260
 353  /graphic/field_encounteffect.narc                     off=0x03C48E00  size=   264900
 354  /graphic/fld_comact.narc                              off=0x03C89A00  size=      868
 355  /graphic/font.narc                                    off=0x03C89E00  size=   134744
 356  /graphic/fontoam.narc                                 off=0x03CAAE00  size=     1444
 357  /graphic/footprint_board.narc                         off=0x03CAB400  size=    36308
 358  /graphic/hiden_effect.narc                            off=0x03CB4200  size=    32276
 359  /graphic/imageclip.narc                               off=0x03CBC200  size=   255536
 360  /graphic/library_tv.narc                              off=0x03CFAA00  size=   253272
 361  /graphic/lobby_news.narc                              off=0x03D38800  size=    64420
 362  /graphic/mail_gra.narc                                off=0x03D48400  size=   106800
 363  /graphic/menu_gra.narc                                off=0x03D62600  size=    19312
 364  /graphic/mysign.narc                                  off=0x03D67200  size=     4280
 365  /graphic/mystery.narc                                 off=0x03D68400  size=    32720
 366  /graphic/ntag_gra.narc                                off=0x03D70400  size=   183920
 367  /graphic/nutmixer.narc                                off=0x03D9D400  size=   180980
 368  /graphic/oekaki.narc                                  off=0x03DC9800  size=     5412
 369  /graphic/opening.narc                                 off=0x03DCAE00  size=    27580
 370  /graphic/pl_bag_gra.narc                              off=0x03DD1A00  size=   105588
 371  /graphic/pl_font.narc                                 off=0x03DEB800  size=   135204
 372  /graphic/pl_plist_gra.narc                            off=0x03E0CA00  size=    40108
 373  /graphic/pl_pst_gra.narc                              off=0x03E16800  size=   127152
 374  /graphic/pl_wifinote.narc                             off=0x03E35A00  size=    45340
 375  /graphic/pl_winframe.narc                             off=0x03E40C00  size=    35044
 376  /graphic/plist_gra.narc                               off=0x03E49600  size=    40108
 377  /graphic/pmsi.narc                                    off=0x03E53400  size=    12644
 378  /graphic/poketch.narc                                 off=0x03E56600  size=    59468
 379  /graphic/poru_gra.narc                                off=0x03E65000  size=    27108
 380  /graphic/poruact.narc                                 off=0x03E6BA00  size=     5292
 381  /graphic/porudemo.narc                                off=0x03E6D000  size=     8812
 382  /graphic/pst_gra.narc                                 off=0x03E6F400  size=   127152
 383  /graphic/ranking.narc                                 off=0x03E8E600  size=     5320
 384  /graphic/record.narc                                  off=0x03E8FC00  size=    22976
 385  /graphic/shop_gra.narc                                off=0x03E95600  size=    10608
 386  /graphic/tmap_gra.narc                                off=0x03E98000  size=    85776
 387  /graphic/touch_subwindow.narc                         off=0x03EAD000  size=     2456
 388  /graphic/trainer_case.narc                            off=0x03EADA00  size=   240960
 389  /graphic/unionobj2d_onlyfront.narc                    off=0x03EE8800  size=    15948
 390  /graphic/unionroom.narc                               off=0x03EEC800  size=     4624
 391  /graphic/waza_oshie_gra.narc                          off=0x03EEDC00  size=    12084
 392  /graphic/wifi2dchar.narc                              off=0x03EF0C00  size=   821528
 393  /graphic/wifi_lobby.narc                              off=0x03FB9600  size=   812032
 394  /graphic/wifi_lobby_other.narc                        off=0x0407FA00  size=   363436
 395  /graphic/wifi_unionobj.narc                           off=0x040D8600  size=    91236
 396  /graphic/winframe.narc                                off=0x040EEC00  size=    35044
 397  /graphic/worldtimer.narc                              off=0x040F7600  size=   216612
 398  /graphic/worldtrade.narc                              off=0x0412C600  size=    46804
 399  /itemtool/itemdata/item_data.narc                     off=0x04137E00  size=    19500
 400  /itemtool/itemdata/item_icon.narc                     off=0x0413CC00  size=   399952
 401  /itemtool/itemdata/nuts_data.narc                     off=0x0419E800  size=     1332
 402  /itemtool/itemdata/pl_item_data.narc                  off=0x0419EE00  size=    19676
 403  /msgdata/msg.narc                                     off=0x01A54400  size=  2695184
 404  /msgdata/pl_msg.narc                                  off=0x0162DE00  size=  4351320
 405  /msgdata/scenario/scr_msg.narc                        off=0x01CE6600  size=     6748
 406  /particledata/particledata.narc                       off=0x05C62800  size=    45240
 407  /particledata/pl_etc/pl_etc_particle.narc             off=0x05F9BA00  size=    21592
 408  /particledata/pl_frontier/frontier_particle.narc      off=0x05F22400  size=    64024
 409  /particledata/pl_pokelist/pokelist_particle.narc      off=0x05F88600  size=     5708
 410  /pokeanime/pl_poke_anm.narc                           off=0x05CB9800  size=    28500
 411  /pokeanime/poke_anm.narc                              off=0x05CB3400  size=    25412
 412  /poketool/pl_pokezukan.narc                           off=0x05E7D000  size=     1048
 413  /poketool/pokezukan.narc                              off=0x05E7CA00  size=     1048
 414  /poketool/shinzukan.narc                              off=0x05E7D600  size=      484
 415  /poketool/icongra/pl_poke_icon.narc                   off=0x041A3C00  size=   585336
 416  /poketool/icongra/poke_icon.narc                      off=0x04232C00  size=   577776
 417  /poketool/personal/evo.narc                           off=0x03710C00  size=    26468
 418  /poketool/personal/growtbl.narc                       off=0x03717400  size=     3348
 419  /poketool/personal/personal.narc                      off=0x03703E00  size=    26104
 420  /poketool/personal/pl_growtbl.narc                    off=0x03718200  size=     3348
 421  /poketool/personal/pl_personal.narc                   off=0x0370A400  size=    26468
 422  /poketool/personal/pms.narc                           off=0x03719000  size=     1016
 423  /poketool/personal/wotbl.narc                         off=0x03719400  size=    19168
 424  /poketool/poke_edit/pl_poke_data.narc                 off=0x05F09400  size=    44028
 425  /poketool/pokeanm/pl_pokeanm.narc                     off=0x05E81000  size=    13892
 426  /poketool/pokeanm/pokeanm.narc                        off=0x05E7D800  size=    13892
 427  /poketool/pokefoot/pokefoot.narc                      off=0x042BFE00  size=    58604
 428  /poketool/pokegra/dp_height.narc                      off=0x01CE8200  size=    23108
 429  /poketool/pokegra/dp_height_o.narc                    off=0x01CEDE00  size=     1684
 430  /poketool/pokegra/height.narc                         off=0x01CEE600  size=    23108
 431  /poketool/pokegra/height_o.narc                       off=0x01CF4200  size=     1924
 432  /poketool/pokegra/otherpoke.narc                      off=0x01CF4A00  size=   890604
 433  /poketool/pokegra/pl_otherpoke.narc                   off=0x01DCE200  size=  1021324
 434  /poketool/pokegra/pl_pokegra.narc                     off=0x01EC7800  size= 11778676
 435  /poketool/pokegra/poke_shadow.narc                    off=0x02A03400  size=      556
 436  /poketool/pokegra/poke_shadow_ofx.narc                off=0x02A03800  size=      556
 437  /poketool/pokegra/poke_yofs.narc                      off=0x02A03C00  size=      556
 438  /poketool/pokegra/pokegra.narc                        off=0x02A04000  size= 11778676
 439  /poketool/trainer/trdata.narc                         off=0x0371E000  size=    26036
 440  /poketool/trainer/trpoke.narc                         off=0x03724600  size=    28600
 441  /poketool/trgra/trbgra.narc                           off=0x0353FC00  size=   321628
 442  /poketool/trgra/trfgra.narc                           off=0x0358E600  size=  1529600
 443  /poketool/trmsg/trtbl.narc                            off=0x0372B600  size=    10048
 444  /poketool/trmsg/trtblofs.narc                         off=0x0372DE00  size=     1916
 445  /poketool/waza/pl_waza_tbl.narc                       off=0x03979600  size=    11356
 446  /poketool/waza/waza_tbl.narc                          off=0x0397C400  size=    11356
 447  /resource/eng/batt_rec/batt_rec_gra.narc              off=0x06136000  size=   596912
 448  /resource/eng/frontier_graphic/frontier_bg.narc       off=0x061E2C00  size=   829908
 449  /resource/eng/frontier_graphic/frontier_obj.narc      off=0x062AD600  size=    42912
 450  /resource/eng/pms_aikotoba/pms_aikotoba.narc          off=0x062DFA00  size=     1464
 451  /resource/eng/scratch/scratch.narc                    off=0x062B7E00  size=   162668
 452  /resource/eng/wifi_lobby_minigame/wlmngm_tool.narc    off=0x061C7C00  size=   110260
 453  /resource/eng/zukan/zukan.narc                        off=0x06123E00  size=    73968
 454  /wazaeffect/we.arc                                    off=0x03919000  size=   255820
 455  /wazaeffect/we_sub.narc                               off=0x03957800  size=    12324
 456  /wazaeffect/effectclact/wecell.narc                   off=0x0396D800  size=     5372
 457  /wazaeffect/effectclact/wecellanm.narc                off=0x0396EE00  size=     4688
 458  /wazaeffect/effectclact/wechar.narc                   off=0x03970200  size=    33076
 459  /wazaeffect/effectclact/wepltt.narc                   off=0x03978400  size=     4480
 460  /wazaeffect/effectdata/ball_particle.narc             off=0x04482A00  size=   302380
 461  /wazaeffect/effectdata/waza_particle.narc             off=0x044CC800  size=  2419092
```

## Appendix B — White 2 complete file listing

318 named files (file IDs 344–661; IDs 0–343 are the ARM9 overlays).

```
 344  /skb.narc                                             off=0x00365800  size=    60336
 345  /soundstatus.narc                                     off=0x00374400  size=    12164
 346  /swan_sound_data.sdat                                 off=0x00377400  size= 89373024
 347  /a/0/0/0                                              off=0x058B2E00  size=     2924
 348  /a/0/0/1                                              off=0x058B3A00  size=    54228
 349  /a/0/0/2                                              off=0x058C0E00  size=  5349632
 350  /a/0/0/3                                              off=0x05DDB000  size=  2444780
 351  /a/0/0/4                                              off=0x0602FE00  size=  8261160
 352  /a/0/0/5                                              off=0x06810E00  size=     6652
 353  /a/0/0/6                                              off=0x06812800  size=  7730420
 354  /a/0/0/7                                              off=0x06F71E00  size=   843988
 355  /a/0/0/8                                              off=0x07040000  size= 31530592
 356  /a/0/0/9                                              off=0x08E52000  size=    22360
 357  /a/0/1/0                                              off=0x08E57800  size=     1244
 358  /a/0/1/1                                              off=0x08E57E00  size=  6332576
 359  /a/0/1/2                                              off=0x09462000  size=    29580
 360  /a/0/1/3                                              off=0x09469400  size=     4090
 361  /a/0/1/4                                              off=0x0946A400  size= 19905564
 362  /a/0/1/5                                              off=0x0A766200  size=      244
 363  /a/0/1/6                                              off=0x0A766400  size=    60988
 364  /a/0/1/7                                              off=0x0A775400  size=     3348
 365  /a/0/1/8                                              off=0x0A776200  size=    48532
 366  /a/0/1/9                                              off=0x0A782000  size=    36920
 367  /a/0/2/0                                              off=0x0A78B200  size=     8272
 368  /a/0/2/1                                              off=0x0A78D400  size=    24692
 369  /a/0/2/2                                              off=0x0A793600  size=     3800
 370  /a/0/2/3                                              off=0x0A794600  size=   650120
 371  /a/0/2/4                                              off=0x0A833200  size=    28168
 372  /a/0/2/5                                              off=0x0A83A200  size=   576856
 373  /a/0/2/6                                              off=0x0A8C7000  size=    23860
 374  /a/0/2/7                                              off=0x0A8CCE00  size=    85108
 375  /a/0/2/8                                              off=0x0A8E1C00  size=    68224
 376  /a/0/2/9                                              off=0x0A8F2800  size=    79620
 377  /a/0/3/0                                              off=0x0A906000  size=    51012
 378  /a/0/3/1                                              off=0x0A912800  size=    60324
 379  /a/0/3/2                                              off=0x0A921400  size=    97944
 380  /a/0/3/3                                              off=0x0A939400  size=   192004
 381  /a/0/3/4                                              off=0x0A968400  size=     9472
 382  /a/0/3/5                                              off=0x0A96AA00  size=    28256
 383  /a/0/3/6                                              off=0x0A971A00  size=     5436
 384  /a/0/3/7                                              off=0x0A973000  size=      828
 385  /a/0/3/8                                              off=0x0A973400  size=    17016
 386  /a/0/3/9                                              off=0x0A977800  size=   314216
 387  /a/0/4/0                                              off=0x0A9C4400  size=   114144
 388  /a/0/4/1                                              off=0x0A9E0200  size=     1500
 389  /a/0/4/2                                              off=0x0A9E0800  size=   175336
 390  /a/0/4/3                                              off=0x0AA0B600  size=    55112
 391  /a/0/4/4                                              off=0x0AA18E00  size=    91248
 392  /a/0/4/5                                              off=0x0AA2F400  size=    92312
 393  /a/0/4/6                                              off=0x0AA45E00  size=   624424
 394  /a/0/4/7                                              off=0x0AADE600  size=    28288
 395  /a/0/4/8                                              off=0x0AAE5600  size=  4886968
 396  /a/0/4/9                                              off=0x0AF8E800  size=     4780
 397  /a/0/5/0                                              off=0x0AF8FC00  size=     1672
 398  /a/0/5/1                                              off=0x0AF90400  size=  8914092
 399  /a/0/5/2                                              off=0x0B810A00  size=     3296
 400  /a/0/5/3                                              off=0x0B811800  size=    13412
 401  /a/0/5/4                                              off=0x0B814E00  size=     8960
 402  /a/0/5/5                                              off=0x0B817200  size=    72308
 403  /a/0/5/6                                              off=0x0B828E00  size=   621080
 404  /a/0/5/7                                              off=0x0B8C0A00  size=    12348
 405  /a/0/5/8                                              off=0x0B8C3C00  size=    89292
 406  /a/0/5/9                                              off=0x0B8D9A00  size=     2040
 407  /a/0/6/0                                              off=0x0B8DA200  size=   157652
 408  /a/0/6/1                                              off=0x0B900A00  size=     7932
 409  /a/0/6/2                                              off=0x0B902A00  size=    44504
 410  /a/0/6/3                                              off=0x0B90D800  size=   157388
 411  /a/0/6/4                                              off=0x0B934000  size=    33436
 412  /a/0/6/5                                              off=0x0B93C400  size=   438100
 413  /a/0/6/6                                              off=0x0B9A7400  size=    53280
 414  /a/0/6/7                                              off=0x0B9B4600  size=    10968
 415  /a/0/6/8                                              off=0x0B9B7200  size=   284088
 416  /a/0/6/9                                              off=0x0B9FC800  size=    28712
 417  /a/0/7/0                                              off=0x0BA03A00  size=    41252
 418  /a/0/7/1                                              off=0x0BA0DC00  size=  1170896
 419  /a/0/7/2                                              off=0x0BB2BA00  size=   157388
 420  /a/0/7/3                                              off=0x0BB52200  size=      956
 421  /a/0/7/4                                              off=0x0BB52600  size=   507396
 422  /a/0/7/5                                              off=0x0BBCE600  size=   133936
 423  /a/0/7/6                                              off=0x0BBEF200  size=    75500
 424  /a/0/7/7                                              off=0x0BC01A00  size=   171616
 425  /a/0/7/8                                              off=0x0BC2BA00  size=   129828
 426  /a/0/7/9                                              off=0x0BC4B600  size=      132
 427  /a/0/8/0                                              off=0x0BC4B800  size=      932
 428  /a/0/8/1                                              off=0x0BC4BC00  size=      848
 429  /a/0/8/2                                              off=0x0BC4C000  size=    76952
 430  /a/0/8/3                                              off=0x0BC5EE00  size=    66720
 431  /a/0/8/4                                              off=0x0BC6F400  size=   207232
 432  /a/0/8/5                                              off=0x0BCA1E00  size=     4652
 433  /a/0/8/6                                              off=0x0BCA3200  size=      196
 434  /a/0/8/7                                              off=0x0BCA3400  size=   198840
 435  /a/0/8/8                                              off=0x0BCD3E00  size=    42088
 436  /a/0/8/9                                              off=0x0BCDE400  size=     9364
 437  /a/0/9/0                                              off=0x0BCE0A00  size=     1688
 438  /a/0/9/1                                              off=0x0BCE1200  size=    22840
 439  /a/0/9/2                                              off=0x0BCE6C00  size=    26764
 440  /a/0/9/3                                              off=0x0BCED600  size=   312980
 441  /a/0/9/4                                              off=0x0BD39E00  size=  3319756
 442  /a/0/9/5                                              off=0x0C064600  size=    52720
 443  /a/0/9/6                                              off=0x0C071400  size=     8952
 444  /a/0/9/7                                              off=0x0C073800  size=    12744
 445  /a/0/9/8                                              off=0x0C076A00  size=    15220
 446  /a/0/9/9                                              off=0x0C07A600  size=    19408
 447  /a/1/0/0                                              off=0x0C07F200  size=   447420
 448  /a/1/0/1                                              off=0x0C0EC600  size=    58428
 449  /a/1/0/2                                              off=0x0C0FAC00  size=      860
 450  /a/1/0/3                                              off=0x0C0FB000  size=    75408
 451  /a/1/0/4                                              off=0x0C10D800  size=  1883984
 452  /a/1/0/5                                              off=0x0C2D9800  size=   257708
 453  /a/1/0/6                                              off=0x0C318800  size=     7500
 454  /a/1/0/7                                              off=0x0C31A600  size=    22864
 455  /a/1/0/8                                              off=0x0C320000  size=   212188
 456  /a/1/0/9                                              off=0x0C353E00  size=    16060
 457  /a/1/1/0                                              off=0x0C357E00  size=      352
 458  /a/1/1/1                                              off=0x0C358000  size=    33440
 459  /a/1/1/2                                              off=0x0C360400  size=    25144
 460  /a/1/1/3                                              off=0x0C366800  size=    23876
 461  /a/1/1/4                                              off=0x0C36C600  size=    24000
 462  /a/1/1/5                                              off=0x0C372400  size=    23876
 463  /a/1/1/6                                              off=0x0C378200  size=  4643324
 464  /a/1/1/7                                              off=0x0C7E5C00  size=   132780
 465  /a/1/1/8                                              off=0x0C806400  size=     5200
 466  /a/1/1/9                                              off=0x0C807A00  size=    24264
 467  /a/1/2/0                                              off=0x0C80DA00  size=      832
 468  /a/1/2/1                                              off=0x0C80DE00  size=    50508
 469  /a/1/2/2                                              off=0x0C81A400  size=    45064
 470  /a/1/2/3                                              off=0x0C825600  size=    31264
 471  /a/1/2/4                                              off=0x0C82D200  size=    13140
 472  /a/1/2/5                                              off=0x0C830600  size=    56196
 473  /a/1/2/6                                              off=0x0C83E200  size=   222284
 474  /a/1/2/7                                              off=0x0C874800  size=    41500
 475  /a/1/2/8                                              off=0x0C87EC00  size=    27736
 476  /a/1/2/9                                              off=0x0C885A00  size=    56992
 477  /a/1/3/0                                              off=0x0C893A00  size=   465644
 478  /a/1/3/1                                              off=0x0C905600  size=   124528
 479  /a/1/3/2                                              off=0x0C923E00  size=  1220108
 480  /a/1/3/3                                              off=0x0CA4DE00  size=      244
 481  /a/1/3/4                                              off=0x0CA4E000  size=    52652
 482  /a/1/3/5                                              off=0x0CA5AE00  size=    39164
 483  /a/1/3/6                                              off=0x0CA64800  size=      548
 484  /a/1/3/7                                              off=0x0CA64C00  size=   160984
 485  /a/1/3/8                                              off=0x0CA8C200  size=    41008
 486  /a/1/3/9                                              off=0x0CA96400  size=    52420
 487  /a/1/4/0                                              off=0x0CAA3200  size=    93668
 488  /a/1/4/1                                              off=0x0CABA000  size=    22192
 489  /a/1/4/2                                              off=0x0CABF800  size=   342860
 490  /a/1/4/3                                              off=0x0CB13400  size=   157032
 491  /a/1/4/4                                              off=0x0CB39A00  size=   134516
 492  /a/1/4/5                                              off=0x0CB5A800  size=    43456
 493  /a/1/4/6                                              off=0x0CB65200  size=      412
 494  /a/1/4/7                                              off=0x0CB65400  size=      268
 495  /a/1/4/8                                              off=0x0CB65600  size=   110800
 496  /a/1/4/9                                              off=0x0CB80800  size=      100
 497  /a/1/5/0                                              off=0x0CB80A00  size=   109252
 498  /a/1/5/1                                              off=0x0CB9B600  size=     6320
 499  /a/1/5/2                                              off=0x0CB9D000  size=    60708
 500  /a/1/5/3                                              off=0x0CBABE00  size=    46844
 501  /a/1/5/4                                              off=0x0CBB7600  size=    50932
 502  /a/1/5/5                                              off=0x0CBC3E00  size=    51428
 503  /a/1/5/6                                              off=0x0CBD0800  size=     1772
 504  /a/1/5/7                                              off=0x0CBD1000  size=   606972
 505  /a/1/5/8                                              off=0x0CC65400  size= 22716352
 506  /a/1/5/9                                              off=0x0E20F400  size=     3908
 507  /a/1/6/0                                              off=0x0E210400  size=   672584
 508  /a/1/6/1                                              off=0x0E2B4800  size=      416
 509  /a/1/6/2                                              off=0x0E2B4A00  size=    81460
 510  /a/1/6/3                                              off=0x0E2C8A00  size=     3648
 511  /a/1/6/4                                              off=0x0E2C9A00  size=      404
 512  /a/1/6/5                                              off=0x0E2C9C00  size=    76604
 513  /a/1/6/6                                              off=0x0E2DC800  size=    37160
 514  /a/1/6/7                                              off=0x0E2E5A00  size=    22876
 515  /a/1/6/8                                              off=0x0E2EB400  size=   337416
 516  /a/1/6/9                                              off=0x0E33DC00  size=    44400
 517  /a/1/7/0                                              off=0x0E348A00  size=   249008
 518  /a/1/7/1                                              off=0x0E385800  size=    35440
 519  /a/1/7/2                                              off=0x0E38E400  size=     3352
 520  /a/1/7/3                                              off=0x0E38F200  size=      140
 521  /a/1/7/4                                              off=0x0E38F400  size=  2533172
 522  /a/1/7/5                                              off=0x0E5F9C00  size=  1879716
 523  /a/1/7/6                                              off=0x0E7C4C00  size=   243556
 524  /a/1/7/7                                              off=0x0E800400  size=     4372
 525  /a/1/7/8                                              off=0x0E801600  size=   138256
 526  /a/1/7/9                                              off=0x0E823400  size=    39072
 527  /a/1/8/0                                              off=0x0E82CE00  size=   186876
 528  /a/1/8/1                                              off=0x0E85A800  size=    69508
 529  /a/1/8/2                                              off=0x0E86B800  size=       84
 530  /a/1/8/3                                              off=0x0E86BA00  size=      468
 531  /a/1/8/4                                              off=0x0E86BC00  size=   109764
 532  /a/1/8/5                                              off=0x0E886A00  size=    11056
 533  /a/1/8/6                                              off=0x0E889600  size=    35084
 534  /a/1/8/7                                              off=0x0E892000  size=    69356
 535  /a/1/8/8                                              off=0x0E8A3000  size=    20024
 536  /a/1/8/9                                              off=0x0E8A8000  size=   105128
 537  /a/1/9/0                                              off=0x0E8C1C00  size=    20892
 538  /a/1/9/1                                              off=0x0E8C6E00  size=     8272
 539  /a/1/9/2                                              off=0x0E8C9000  size=    14408
 540  /a/1/9/3                                              off=0x0E8CCA00  size=     3648
 541  /a/1/9/4                                              off=0x0E8CDA00  size=   152180
 542  /a/1/9/5                                              off=0x0E8F2E00  size=      316
 543  /a/1/9/6                                              off=0x0E8F3000  size=     5448
 544  /a/1/9/7                                              off=0x0E8F4600  size=     4312
 545  /a/1/9/8                                              off=0x0E8F5800  size=    39764
 546  /a/1/9/9                                              off=0x0E8FF400  size=   109020
 547  /a/2/0/0                                              off=0x0E919E00  size=    13468
 548  /a/2/0/1                                              off=0x0E91D400  size=    29092
 549  /a/2/0/2                                              off=0x0E924600  size=   388564
 550  /a/2/0/3                                              off=0x0E983400  size=    20228
 551  /a/2/0/4                                              off=0x0E988400  size=    30084
 552  /a/2/0/5                                              off=0x0E98FA00  size=     1276
 553  /a/2/0/6                                              off=0x0E990000  size=     1116
 554  /a/2/0/7                                              off=0x0E990600  size=    23436
 555  /a/2/0/8                                              off=0x0E996200  size=     5020
 556  /a/2/0/9                                              off=0x0E997600  size=    51076
 557  /a/2/1/0                                              off=0x0E9A3E00  size=     3500
 558  /a/2/1/1                                              off=0x0E9A4C00  size=    24052
 559  /a/2/1/2                                              off=0x0E9AAA00  size=    41780
 560  /a/2/1/3                                              off=0x0E9B4E00  size=  1353872
 561  /a/2/1/4                                              off=0x0EAFF800  size=     9516
 562  /a/2/1/5                                              off=0x0EB01E00  size=  2678516
 563  /a/2/1/6                                              off=0x0ED8FE00  size=    23788
 564  /a/2/1/7                                              off=0x0ED95C00  size=    27956
 565  /a/2/1/8                                              off=0x0ED9CA00  size=    12564
 566  /a/2/1/9                                              off=0x0ED9FC00  size=      228
 567  /a/2/2/0                                              off=0x0ED9FE00  size=  1898452
 568  /a/2/2/1                                              off=0x0EF6F600  size=        4
 569  /a/2/2/2                                              off=0x0EF6F800  size= 11784864
 570  /a/2/2/3                                              off=0x0FAACC00  size=      712
 571  /a/2/2/4                                              off=0x0FAAD000  size=    56140
 572  /a/2/2/5                                              off=0x0FABAC00  size=  6727468
 573  /a/2/2/6                                              off=0x10125400  size=  6989780
 574  /a/2/2/7                                              off=0x107CFC00  size=  1425672
 575  /a/2/2/8                                              off=0x1092BE00  size=      720
 576  /a/2/2/9                                              off=0x1092C200  size=     1076
 577  /a/2/3/0                                              off=0x1092C800  size=     5848
 578  /a/2/3/1                                              off=0x1092E000  size=    14908
 579  /a/2/3/2                                              off=0x10931C00  size=    67996
 580  /a/2/3/3                                              off=0x10942600  size=   483696
 581  /a/2/3/4                                              off=0x109B8800  size=      324
 582  /a/2/3/5                                              off=0x109B8A00  size=     5152
 583  /a/2/3/6                                              off=0x109BA000  size=    67064
 584  /a/2/3/7                                              off=0x109CA600  size=    19336
 585  /a/2/3/8                                              off=0x109CF200  size=    17136
 586  /a/2/3/9                                              off=0x109D3600  size=     2468
 587  /a/2/4/0                                              off=0x109D4000  size=     2900
 588  /a/2/4/1                                              off=0x109D4C00  size=     1936
 589  /a/2/4/2                                              off=0x109D5400  size=   117676
 590  /a/2/4/3                                              off=0x109F2000  size=     4776
 591  /a/2/4/4                                              off=0x109F3400  size=    43840
 592  /a/2/4/5                                              off=0x109FE000  size=    77300
 593  /a/2/4/6                                              off=0x10A10E00  size=    27352
 594  /a/2/4/7                                              off=0x10A17A00  size=     2108
 595  /a/2/4/8                                              off=0x10A18400  size=     1972
 596  /a/2/4/9                                              off=0x10A18C00  size=     2544
 597  /a/2/5/0                                              off=0x10A19600  size=    24052
 598  /a/2/5/1                                              off=0x10A1F400  size=     1972
 599  /a/2/5/2                                              off=0x10A1FC00  size=     2640
 600  /a/2/5/3                                              off=0x10A20800  size=    24052
 601  /a/2/5/4                                              off=0x10A26600  size=     1156
 602  /a/2/5/5                                              off=0x10A26C00  size=     1700
 603  /a/2/5/6                                              off=0x10A27400  size=    24052
 604  /a/2/5/7                                              off=0x10A2D200  size=    24052
 605  /a/2/5/8                                              off=0x10A33000  size=    55020
 606  /a/2/5/9                                              off=0x10A40800  size=    11080
 607  /a/2/6/0                                              off=0x10A43400  size=    40828
 608  /a/2/6/1                                              off=0x10A4D400  size=    24052
 609  /a/2/6/2                                              off=0x10A53200  size=    23748
 610  /a/2/6/3                                              off=0x10A59000  size=   854956
 611  /a/2/6/4                                              off=0x10B29C00  size=     7700
 612  /a/2/6/5                                              off=0x10B2BC00  size=    79828
 613  /a/2/6/6                                              off=0x10B3F400  size=    89944
 614  /a/2/6/7                                              off=0x10B55400  size=   112596
 615  /a/2/6/8                                              off=0x10B70C00  size=     3712
 616  /a/2/6/9                                              off=0x10B71C00  size=    71132
 617  /a/2/7/0                                              off=0x10B83200  size=    15752
 618  /a/2/7/1                                              off=0x10B87000  size=   516772
 619  /a/2/7/2                                              off=0x10C05400  size=     6784
 620  /a/2/7/3                                              off=0x10C07000  size=     4612
 621  /a/2/7/4                                              off=0x10C08400  size=  1175396
 622  /a/2/7/5                                              off=0x10D27400  size=   113956
 623  /a/2/7/6                                              off=0x10D43200  size=    18464
 624  /a/2/7/7                                              off=0x10D47C00  size=    54584
 625  /a/2/7/8                                              off=0x10D55200  size=    69984
 626  /a/2/7/9                                              off=0x10D66400  size=   147300
 627  /a/2/8/0                                              off=0x10D8A400  size=   168040
 628  /a/2/8/1                                              off=0x10DB3600  size=   118976
 629  /a/2/8/2                                              off=0x10DD0800  size=     1300
 630  /a/2/8/3                                              off=0x10DD0E00  size=      140
 631  /a/2/8/4                                              off=0x10DD1000  size=   282860
 632  /a/2/8/5                                              off=0x10E16200  size=    31856
 633  /a/2/8/6                                              off=0x10E1E000  size=    15520
 634  /a/2/8/7                                              off=0x10E21E00  size=    58668
 635  /a/2/8/8                                              off=0x10E30400  size=     2628
 636  /a/2/8/9                                              off=0x10E31000  size=     6460
 637  /a/2/9/0                                              off=0x10E32A00  size=   340348
 638  /a/2/9/1                                              off=0x10E85C00  size=   352828
 639  /a/2/9/2                                              off=0x10EDC000  size=   155952
 640  /a/2/9/3                                              off=0x10F02200  size=    14496
 641  /a/2/9/4                                              off=0x10F05C00  size=    21908
 642  /a/2/9/5                                              off=0x10F0B200  size=   213240
 643  /a/2/9/6                                              off=0x10F3F400  size=    19776
 644  /a/2/9/7                                              off=0x10F44200  size=   103804
 645  /a/2/9/8                                              off=0x10F5D800  size=    21372
 646  /a/2/9/9                                              off=0x10F62C00  size=   402048
 647  /a/3/0/0                                              off=0x10FC5000  size=    37940
 648  /a/3/0/1                                              off=0x10FCE600  size=    25552
 649  /a/3/0/2                                              off=0x10FD4A00  size=    46780
 650  /a/3/0/3                                              off=0x10FE0200  size=   108188
 651  /a/3/0/4                                              off=0x10FFAA00  size=    51236
 652  /a/3/0/5                                              off=0x11007400  size=    19172
 653  /a/3/0/6                                              off=0x1100C000  size=    66120
 654  /a/3/0/7                                              off=0x1101C400  size=     3644
 655  /dl_rom/child2_r_eng.srl                              off=0x1101D400  size=   656584
 656  /dl_rom/child_r_eng.srl                               off=0x110BDA00  size=   726216
 657  /dl_rom/icon_b.char                                   off=0x1116F000  size=      512
 658  /dl_rom/icon_b.plt                                    off=0x1116F200  size=       32
 659  /dl_rom/icon_w.char                                   off=0x1116F400  size=      512
 660  /dl_rom/icon_w.plt                                    off=0x1116F600  size=       32
 661  /dwc/utility.bin                                      off=0x1116F800  size=   929852
```
