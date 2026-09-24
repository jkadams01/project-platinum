# Generation 5 asset extraction (Black / White 2)

Status: **verified by running code against the owner's ROMs.** Every claim below that is
marked *verified* was produced by decoding the actual bytes and looking at the resulting
PNG. Claims marked *inferred* are structural deductions I did not visually confirm.

Nothing ROM-derived is committed. Probe scripts live in `tools/_work/gen5/` (gitignored).

---

## 0. ROM identities (verified)

| Game | Title | Code | ROM bytes | FAT files | Named FS files | `/a/` NARCs |
|---|---|---|---|---|---|---|
| Black | `POKEMON B` | `IRBO` | 268,435,456 | 484 | 247 | 234 |
| White 2 | `POKEMON W2` | `IRDO` | 287,647,804 | 662 | 318 | 307 |
| HeartGold | `POKEMON HG` | `IPKE` | 134,217,728 | 513 | 384 | — |
| Platinum | `POKEMON PL` | `CPUE` | 134,217,728 | 462 | 340 | — |

The "662 files" figure for White 2 is the FAT entry count (includes ARM9 overlays).
Gen 5 anonymises the filesystem: every asset is a NARC at a numbered path `/a/X/Y/Z`.
Gen 4 keeps real names (`/poketool/pokegra/pl_pokegra.narc`), which makes Gen 4 far
easier to navigate.

**Important: Black and White 2 do not share NARC numbering.** B2W2 inserted archives, so
paths shift. 102 of Black's 234 `/a/` archives are byte-identical to a White 2 archive but
at a *different path* (e.g. Black `/a/0/5/2` ≡ W2 `/a/0/5/1`, md5 `645cf61b3307`, both
8,914,092 bytes). Never assume a path carries over — match by content or by structure.

---

## 1. Pokémon battle sprites

### Where

| Game | NARC | Entries | Groups |
|---|---|---|---|
| Black | `/a/0/0/4` | 14,285 | 714 × 20 + 5 trailing NCLRs |
| White 2 | `/a/0/0/4` | 15,065 | 753 × 20 + 5 trailing NCLRs |

Black also carries `/a/0/5/2` (14,285 entries, same 20-slot shape, 8,914,092 B) which is
byte-identical to White 2 `/a/0/5/1` — a legacy duplicate of the BW-era set. Use
`/a/0/0/4`; it is the one that grows in B2W2 to cover the new formes.

### Entry ordering — verified

Group index = **National Dex number**. Confirmed by decoding and eyeballing:
1 Bulbasaur, 6 Charizard, 25 Pikachu, 143 Snorlax, 150 Mewtwo, 493 Arceus,
494 Victini, 643 Reshiram, 644 Zekrom. Groups above 649 are alternate formes
(714 groups in BW = 649 species + 65 formes; 753 in B2W2).

Each group is exactly 20 entries at `base = dex * 20`:

```
+0   NCGR  FRONT male   part atlas   96x96,  144 tiles, 4bpp, 8x8-tiled
+1   NCGR  FRONT female (zero-length when the species has no gender difference)
+2   NCGR  FRONT male   part atlas  256x128, 512 tiles, 4bpp, LINEAR bitmap
+3   NCGR  FRONT female
+4   NCER  FRONT cells      (one cell per body part)
+5   NANR  FRONT per-part animation sequences
+6   NMCR  FRONT multicell  (the node graph that assembles the whole Pokemon)
+7   NMAR  FRONT multicell animation
+8   raw   u32-prefixed table, 60-880 B (animation script; not decoded)
+9 ..+17   identical 9-slot block for the BACK sprite
+18  NCLR  normal palette, 16 colours, 4bpp
+19  NCLR  shiny palette,  16 colours, 4bpp
```

* Front/back split verified: group 1 block `+0..+8` renders Bulbasaur's **face**;
  block `+9..+17` renders its bulb **from behind**. Charmander likewise.
* Male/female verified: Pikachu (25) is one of the few species with `+1` and `+3`
  populated; most species have them zero-length.
* Shiny verified: Charizard with palette `+19` is black; Pikachu `+19` is orange-tinted.
* The 5 trailing entries of the NARC are extra NCLRs, not a 21st group.

### The animation data — and the honest verdict

**There is no pre-composed flat battle sprite anywhere in the Gen 5 ROM.** Both NCGRs in
a block are sliced part atlases. Rendering `+0` or `+2` directly gives you a scattered
pile of jaws, wings, ears and feet — verified for Voltorb, Jigglypuff, Bulbasaur, Eevee,
Snorlax, Charizard. This is not a bug in the decoder; it is how BW stores sprites.

BW battle sprites are **NNS multi-cell skeletal animations**:

* `+2` NCGR is the character bank. Its CHAR header has the *linear* flag set
  (u32 at `CHAR+0x14` == 1), so the data is a 256×128 bitmap and must be **re-tiled into
  8×8 tiles in reading order** before OAM tile indices mean anything. Skipping this step
  produces striped garbage — this was the single biggest trap.
* `+4` NCER holds 4–51 cells; each cell is one body part (verified: Charizard's 18 cells
  decode to recognisable jaw, head, wings, tail flames, feet). Cell bank attr = 0
  (8-byte cell entries), mapping mode = 4.
* `+5` NANR holds one sequence per part. The `LBAL` label section spells the parts out in
  romaji: `atama` (head), `ago` (jaw), `kubi` (neck), … — verified for Charizard, which
  has 17 sequences of 72 frames each. Each frame carries a 1–4 px translation: this is
  the idle breathing wobble.
* `+6` NMCR is the rig. Two multicells, each 16 nodes; node = `{u16 priority, s16 x,
  s16 y, u8 flags(0x21), u8 nanrSequenceIndex}`.
* `+7` NMAR animates the whole multicell; its labels are `stay` and `stop`.

**Verdict: static frame extraction is the pragmatic path, but it is not free.** You cannot
"just dump a PNG" — you must implement the multicell composer once:

```
retile(NCGR +2) -> tile buffer
for each NMCR node, ordered by priority descending:
    seq  = NANR[node.anim]
    cell = NCER[ seq.frames[0].cellIndex ]
    draw cell's OAMs into the canvas using the cell's own OAM x/y
```

My composer (`tools/_work/gen5/multicell.py`) gets Bulbasaur, Charmander, Pikachu,
Mewtwo, Reshiram, Zekrom and Arceus to the point where they are unmistakably the right
Pokémon in the right colours with parts in roughly the right places — but individual
parts are still a few pixels out. The residual bug is in how the per-node `(x, y)` and the
per-frame translation combine: empirically, **ignoring both and using the cell's own OAM
offsets is closest**, which suggests the node offset is an animation pivot rather than a
placement offset. Budget a focused half-day to finish this.

> ### ✅ SOLVED (sprite stream, 2026-09-23) — the composer works; here is the exact recipe
>
> The "individual parts are still a few pixels out" residual above is fixed, and the cause
> was **not** the node offset being an animation pivot. Working implementation:
> `tools/build_sprites.py :: compose_bw_sprite`, format readers in `tools/lib/nitro.py`.
> All **649 x 2 = 1,298** front/back sprites now compose with **zero failures and zero
> blanks**. Four things have to be right simultaneously:
>
> 1. **Character bank is slot `+2`, not `+0`.** Slot `+0` is 12x12 tiles = exactly 96x96
>    and therefore looks like the finished sprite, which is a trap: de-tiled raster-wise it
>    is a scattered pile of ears, jaws and feet. It is a part atlas too.
> 2. **The cell OAMs address the bank in 2D mapping** (NCER `mapmode` = 4, bank is 32 tiles
>    wide). OAM tile *t* is the 8x8 block at **`(t % 32 * 8, t // 32 * 8)`** of the 256x128
>    bitmap — *not* the t-th tile of a 1D run. In practice you do not need to re-tile the
>    linear bitmap at all: crop the object straight out of it as a `w x h` rectangle.
> 3. **The NMCR node field order is `(u16 animSequenceIndex, s16 x, s16 y, u16 order)`.**
>    Reading priority first and the sequence index last is the natural-looking mistake,
>    because the last byte of the trailing word counts 0,1,2,... and reads exactly like a
>    sequence index. It is the draw order; the high byte is a flag (0x20/0x21). Composite
>    nodes in **ascending** `order`.
> 4. **Almost every OAM sets both the rot/scale bit and bit 9 — i.e. DOUBLE-SIZE.**
>    (Census over all 649 groups: 31,506 OAMs are `(rot=1, bit9=1)`, 191 are `(1,0)`,
>    458 are `(0,0)`, and **none** is `(0,1)`, so nothing is ever hidden.) A double-size
>    object is drawn centred in a box twice its size, so it must be offset by
>    **`(+w/2, +h/2)`** — but **only when `rot` is also set**. Applying the offset
>    unconditionally is what scatters Venusaur's and Wailmer's parts; skipping it entirely
>    scatters everyone's feet by half a part.
>
> Frame 0 of each node's NANR sequence is the neutral pose. Objective check, not eyeballing:
> the content bounding box was diffed against the PokeAPI BW rip — **11 of 14 spot-checked
> species match to the pixel** (1, 3, 25, 143, 150, 249, 250, 320, 343, 384, 609), and the
> three that differ do so by 1-5 px (6, 146, 493) from a different animation frame being
> picked upstream.
>
> **The ROM still does not carry the on-screen vertical placement** — the rig origin is the
> mon's own anchor, and BW applies a separate per-species Y offset that this project has not
> located. `tools/build_sprites.py` therefore adopts one explicit convention: trim to
> content, centre horizontally, stand on the bottom edge of the 96x96 frame.
>
> **Trainer sprites (`/a/0/7/1`) use the identical rig** — reuse `compose_bw_sprite` with
> the period-8 slot offsets and this same four-point recipe.

### If that is too much: use Gen 4 sprites instead (verified, and much cheaper)

Platinum `/poketool/pokegra/pl_pokegra.narc` — 2,964 entries = **494 groups × 6**:

```
+0 back male   +1 back female   +2 front male   +3 front female
+4 normal palette (16 colours)  +5 shiny palette
```

Each NCGR is a **flat 160×80 linear bitmap = two 80×80 frames side by side** (Gen 4's
2-frame idle wobble). No cells, no rig, no assembly.

The pixel data is XOR-obfuscated. The de-obfuscation is a 16-bit LCG, **forward from the
first halfword, XOR-then-advance** (I brute-forced the six plausible variants and scored
by value-histogram flatness; this one wins at 36% identical values vs 0.2% for the rest):

```python
def gen4_decrypt(raw):                     # raw = CHAR pixel bytes
    n = len(raw) // 2
    v = list(struct.unpack('<%dH' % n, raw))
    seed = v[0]
    for i in range(n):
        v[i] ^= seed & 0xFFFF
        seed = (seed * 0x4E6D + 0x6073) & 0xFFFF
    return struct.pack('<%dH' % n, *v)
```

Verified: Charizard, Pikachu and Mew all decode to clean, correct, full-colour 80×80
sprites in one pass. **If sprite throughput matters more than BW's exact art, Gen 4 gives
you 493 species front+back+shiny for an afternoon's work.**

---

## 2. Overworld character sprites

| Game | NARC | Entries | Sets |
|---|---|---|---|
| Black | `/a/0/3/2` | 97 | 32 |
| White 2 | `/a/0/3/1` | 97 | 32 (byte-identical to Black's) |

Layout: entry 0 is a shared NCLR (16 palettes × 16 colours); entries 1–16 are NCGRs;
from 17 onward NCER/NANR pairs interleave with the remaining NCGRs.

Each set is **NCGR 32×128 = four 32×32 frames**, plus an NCER with **4 cells** and an
NANR with **5 sequences**: four single-frame sequences (one per facing, mapping to cells
1, 0, 2, 3) and one 4-frame cycle `[(0,8),(2,8),(1,8),(3,8)]`. Verified by rendering —
the sheets are unmistakable BW NPCs (lass, youngster, hiker, parasol lady…).

**Honest caveat:** 32 sets is far fewer than the overworld cast BW actually shows, and
these four frames are facing poses, not a full walk/run cycle.

> ### ⚠ CORRECTION (adversarial verification pass, 2026-09-23)
>
> **This section previously claimed White 2 `/a/2/9/1` was "almost certainly" the larger
> overworld-NPC archive — 236 NCGR/NCLR pairs rendering as horizontal part strips
> (hair/hat, face, torso, legs). That identification is WRONG, and four structural
> details were wrong with it. Do not chase `/a/2/9/1` for overworld characters.**
>
> `/a/2/9/1` is **trainer-class battle-sprite art**, not overworld art. Decisive test:
> hashing every non-blank 4bpp tile (3,575 unique) and intersecting against other archives
> gives **2,297 byte-identical tiles shared with `/a/0/7/1` (64.3%)** — the trainer
> battle-sprite rig — against 17 shared with `/a/0/3/1` (0.5%), the actual overworld
> archive. Best-tile-overlap maps set *N* → `/a/0/7/1` group *N* exactly for sets 0–46.
> Set 0 renders as Nate and set 1 as Rosa; the full contact sheet is the BW2 trainer-class
> roster (Plasma Grunts, Sages, Hikers, Nurses, Black Belts, Gym Leaders).
>
> Also corrected:
> * **Not 236 usable sets** — only **171** of the 236 NCGRs contain any non-zero pixel;
>   65 are 4,096 bytes of zeros.
> * **Not plain NCGRs** — the even entries are **LZ10-compressed** (`10 40 10 00`,
>   4,160 B out). `RGCN` only appears after decompression. Odd entries are plain NCLR.
> * **Not 64/128 px wide** — every one of the 236 CHAR headers is identical and
>   self-describing: `ty=4, tx=32` → **256×32 px**, 4bpp, tiled, 4,096 B (128 tiles).
>   Five candidate layouts were rendered; only raster 256×32 produces coherent limbs. The
>   shearing at 64/128 px is exactly what produced the illusion of four part-strip bands.
> * **Not four bands** — per-tile-column occupancy over the 171 live sets shows content in
>   columns 0–10 and 27–31 and **zero in columns 11–26 in every set**: two clusters (lower
>   body, head+upper torso), not four.
> * **Not per-entry 16-colour NCLRs** — each NCLR is 552 B with **256 colour slots**, of
>   which only sub-palette 0 is populated.
> * **There is no missing NCER to find.** The column pattern is a fixed DS OBJ 2D-mapping
>   VRAM arrangement — three hardcoded OAM objects (64×32 @ tile 0, 32×32 @ tile 8,
>   64×32 @ tile 24 = 80 of 128 tiles) — so placement lives in ARM9/overlay code, not in a
>   cell bank. All 306 White 2 `/a/` NARCs were scanned: none holds 236, 171 or 472 NCER
>   entries.
> * **B2W2-exclusive.** Scanning every `/a/` NARC in Black for the same signature returns
>   zero matches, and the `/a/2/9/x` block is B2W2-added facility assets
>   (`/a/2/9/3` = `pokewood_poster`, Pokéstar Studios; `/a/2/9/8` = `ja_ps*` Join Avenue
>   and `wbt_e_win1` Black Tower/White Treehollow). `/a/2/9/1` is most likely a compact
>   trainer-figure set for one of those side facilities, reusing 50–64% of each trainer's
>   battle-sprite tiles.
>
> **Practical upshot:** for animated *trainer* battle sprites use **`/a/0/7/1`** (188
> groups of 8 with the full NCER/NANR/NMCR/NMAR rig — the same composer `/a/0/0/4` needs).
> For *overworld* characters **`/a/0/3/1` (32 sets) remains the only located candidate**,
> and `/a/2/9/1` does not extend it. The walk/run cycle must be hand-authored from those
> four facing poses, or drawn.

For a Godot 2D remake the standard frame set you want (idle + 2 walk + run, × 4
directions) is **not sitting in the ROM as a ready sheet** for Gen 5. `/a/0/3/2` (Black) /
`/a/0/3/1` (White 2) gives you four clean facing poses per character, and that is the
ceiling of what the ROM will hand you.

---

## 3. Map tilesets — read this section before planning the tile pipeline

### The uncomfortable truth, stated plainly

**Neither Gen 5 nor HeartGold is a 2D tilemap game.** Both render the overworld as **3D
geometry (NSBMD models) textured with NSBTX texture banks**. The brief's premise that
HeartGold is "a true 2D Gen4 DS game" is not correct — HGSS uses exactly the same
3D-model-plus-texture architecture as BW. What makes HGSS *look* 2D is a fixed
near-top-down camera over flat ground quads, not a different data format.

So there is **no tileset image and no tilemap** to extract from either game. What you can
extract is the texture library, and it is excellent.

### What IS directly extractable (verified)

NSBTX `TEX0` banks decode cleanly to RGBA, complete with **readable texture names**:

| Game | NARC | Entries | Texture slots | Distinct names |
|---|---|---|---|---|
| White 2 | `/a/0/1/4` | 409 | 35,076 | 3,998 |
| Black | `/a/0/1/4` | 282 | — | — |
| HeartGold | `/a/0/4/4` | 106 | 3,659 | 1,958 |

Each NARC entry is a **per-area texture set** — a map area gets one NSBTX containing only
the textures it uses, so the same tile recurs across hundreds of entries. Deduplicate by
name plus decoded pixels; the true unique library is in the low thousands.

Size and format distribution — this is the decisive fact for a 2D pipeline:

| | White 2 `/a/0/1/4` | HeartGold `/a/0/4/4` |
|---|---|---|
| dominant size | **16×16 (12,080 slots)** | **32×32 (1,711 slots)** |
| next | 32×32 (7,055) | 16×16 (1,307) |
| then | 32×16, 16×32, 64×64, 16×8, 8×8 | 64×64, 8×8 |
| formats | PAL16 76%, PAL4 11%, A3I5 6%, A5I3 5%, PAL256 1% | PAL16 73%, PAL4 24% |

Texture names are romaji and self-documenting: BW2 has `gake01a`/`gake_michi` (cliff,
cliff path), `dansa01a` (step), `grass01ax`, `hana01.1` (flower), `doukutu01` (cave),
`fence_01`, `chip_yuka`/`chip_kabe` (floor/wall chips). HGSS has `fieldkk01`, `roadkk_01`,
`cliffkn`, `treekn`, `sea_on`/`sea_un`, `wallkn_d`.

Both sets render correctly and look exactly like the reference screenshots — verified
visually against `References/overworld example 1.png` (BW2 route) and
`References/Overworld example 2.webp` (HGSS Johto).

Other Gen 5 texture archives worth knowing (White 2 paths):

| NARC | Entries | Texture slots | Content |
|---|---|---|---|
| `/a/0/1/4` | 409 | 35,076 | outdoor/dungeon terrain — **the main tileset source** |
| `/a/1/7/4` | 70 | 3,772 | building exteriors (`pc_kabe02`, `gate_1`) |
| `/a/1/7/5` | 93 | 4,886 | interiors/furniture (`idr_pc01`, `idr_tv01`, `idr_mat01`) |
| `/a/0/4/8` | 975 | 7,528 | map objects + character shadow (`h_kage` 8×8) |

Map geometry lives in `/a/0/1/1` (building models, BMD0/BCA0 — Black 222 entries, W2 572)
and `/a/1/5/8` in White 2 (479 entries, 22.7 MB of NSBMD/NSBCA/NSBTA — area models).
Black's area-model archive is `/a/1/6/0` (252 entries, 11.7 MB). Area/map metadata is
`/a/0/0/8` (Black 649 entries, W2 1,065, magic `WB\x03\x00`).

### Recommendation

**Use White 2 `/a/0/1/4` as the tileset source, not HeartGold.**

1. It matches the stated visual target (the brief says BW-style; reference screenshot 1
   is BW2).
2. Its dominant texture size is **16×16**, which drops straight into a Godot `TileSet`
   with a 16 px tile size. HGSS is dominated by 32×32 textures because its world grid is
   32 units — you would be resampling or working at a different tile scale.
3. It is the larger library (3,998 distinct names vs 1,958) and B2W2 is a superset of BW.
4. Formats are overwhelmingly PAL16 (4bpp + 16-colour palette), the simplest case.

Keep HeartGold `/a/0/4/4` as a **supplementary library** — its rock, tree, flower and
snow textures are genuinely good and reference screenshot 2 is HGSS, so James clearly
likes that look too. Mixing is fine; they are the same technical format.

**The 2D pipeline should therefore be:** extract and deduplicate the NSBTX textures into a
flat PNG tile library keyed by name, build Godot `TileSet` resources from them, and
**author the maps yourself** in Godot. Do not try to reconstruct BW maps automatically —
that would require parsing NSBMD geometry and per-quad UVs to work out which texture sits
on which ground cell, which is a large project of its own and produces 3D-shaped data
(ramps, varying heights, rotated camera) that will not map cleanly onto a 2D grid anyway.

---

## 4. Pokémon party / box icons — the easiest win

| Game | NARC | Entries | NCGR count |
|---|---|---|---|
| Black | `/a/0/0/7` | 1,431 | 715 |
| White 2 | `/a/0/0/7` | 1,510 | 774 |

Layout (Black): entry 0 = NCLR with **3 shared 16-colour palettes**; entries 1–6 =
three NANR/NCER pairs; from entry 7 onward, NCGR entries alternate with zero-length
entries. White 2 has an 8-entry header (2 NCLR + 3 NANR + 3 NCER).

Each icon NCGR is **32 tiles = 32×64 px = two 32×32 frames** (the bob animation), 4bpp.

**Ordering verified**: taking the NCGRs in archive order, index = National Dex number.
Confirmed by sight: 0 = `?` placeholder, 1 Bulbasaur, 4 Charmander, 6 Charizard,
7 Squirtle, 25 Pikachu, 39 Jigglypuff, 133 Eevee, 143 Snorlax, 150 Mewtwo, 493 Arceus,
494 Victini, 643 Reshiram.

Decode is trivial: no compression, no obfuscation, no cell assembly — arrange the 32 tiles
4 tiles wide and apply a palette.

> **Update (sprite stream, 2026-09-23) — the palette index was hunted and NOT found.**
> Searched for it and came up empty: a raw byte scan of the whole 287 MB ROM at stride 1/2/4,
> 2-bit and 4-bit packed variants, every FAT entry LZ10/LZ11-decompressed, and a per-offset
> correlation over every NARC with >= 650 entries (the personal data `/a/0/1/6`, 710 x 76 B,
> included). Best score anywhere was 67/120 against ground truth — chance is ~40. It is
> almost certainly in the **BLZ-compressed ARM9**, which none of these readers unpack.
> White 2 `/a/0/0/7` entry 0 holds the 3 real palettes; entry 1 repeats those 3 plus a
> greyscale one (the fainted/shadow icon).
> Colour-only heuristics against the species' own battle sprite top out at **82.5%**
> agreement (measured on a random 120-species sample), which is not good enough to ship.
> What `tools/build_sprites.py` does instead: the icon **pixels** come from the cartridge,
> and the 3-way index is resolved **exactly** by taking any correctly-palettised rip of the
> same icon (PokeAPI `generation-v/icons`, 32x32, cached) and picking the palette whose
> colours are a superset of the rip's opaque colour set. That is deterministic, not a guess
> — 649/649 species resolved with zero unexplained colours. The 82.5% heuristic remains as
> the offline fallback (`--no-download`).

**One open item:** which of the three palettes a given species uses is *not* in this NARC.
Gen 4/5 store a per-species icon palette index in the Pokémon personal data. Until that
table is located, render all three and pick by eye, or find the index in the personal
NARC. This is the only unresolved piece of the icon pipeline.

---

## 5. Trainer sprites and VS portraits

### Trainer battle sprites — same multicell rig as Pokémon

| Game | NARC | Entries | Sets |
|---|---|---|---|
| Black | `/a/0/7/2` | 760 | **95** (period 8) |
| White 2 | `/a/0/7/1` | 1,504 | **188** (period 8) |

Period-8 layout:

```
+0 NCGR  100 tiles          +1 NCGR  512 tiles (linear bitmap, the part atlas)
+2 NCER  +3 NANR  +4 NMCR  +5 NMAR  +6 raw  +7 NCLR (16 colours)
```

Structurally identical to the Pokémon sprites, including the linear-bitmap trap and the
multicell assembly. Whatever composer you write for Pokémon works here with only the slot
offsets changed. Partial renders confirm these are trainer battle sprites (caps, hair and
torsos assemble correctly).

White 2 additionally has `/a/0/7/2` and `/a/0/6/3` (248 entries each = 31 sets) with the
same period-8 shape — secondary trainer sets.

### VS / intro portraits — flat and trivial (verified)

| Game | NARC | Entries | Images |
|---|---|---|---|
| Black | `/a/1/8/0` | 44 | 22 |
| White 2 | `/a/2/6/7` | 76 | 53 |

Black: entries 0–21 are NCGRs of 256 tiles, entries 22–43 are the matching NCLRs —
**block-grouped, not interleaved**, so image *i* pairs with palette *22 + i*.
White 2: NCGRs 0–52, palettes from index 53.

Each renders as a clean **128×128** image at 16 tiles wide with no compression and no
assembly. Verified: Black gives Hilbert, Hilda, Cheren, Bianca, Professor Juniper and the
striped-trio gym leaders; White 2 gives Hugh, Cheren, Roxie, Elesa, Skyla, Drayden and
others. These are the highest-quality-per-effort art in the entire ROM.

---

## 6. Is White 2 a superset of Black?

**For assets: yes, take White 2. For paths: absolutely not — they are not interchangeable.**

Evidence:

* Pokémon sprites: Black 714 groups, **White 2 753** — B2W2 adds Therian formes, Black/White
  Kyurem, Keldeo-Resolute, Genesect drives and the Gen 5 formes Black lacks.
* Icons: Black 715, **White 2 774**.
* Trainers: Black 95 sets, **White 2 188** — almost exactly double.
* Map textures: Black `/a/0/1/4` 282 entries, **White 2 409**; White 2 also has far more
  interior/exterior banks.
* VS portraits: Black 22, **White 2 53**.
* 102 of Black's 234 `/a/` archives are byte-identical to a White 2 archive, confirming
  B2W2 carries the BW content forward wholesale.

But the numbering shifts. Verified examples:

| Asset | Black | White 2 |
|---|---|---|
| Pokémon sprites | `/a/0/0/4` | `/a/0/0/4` (same) |
| Icons | `/a/0/0/7` | `/a/0/0/7` (same) |
| Items | `/a/0/2/5` | `/a/0/2/5` (same) |
| Map textures | `/a/0/1/4` | `/a/0/1/4` (same) |
| Overworld chars | `/a/0/3/2` | **`/a/0/3/1`** |
| Trainer sprites | `/a/0/7/2` | **`/a/0/7/1`** |
| VS portraits | `/a/1/8/0` | **`/a/2/6/7`** |
| Legacy sprite dup | `/a/0/5/2` | **`/a/0/5/1`** |

**Recommendation: extract everything from White 2 (`IRDO`), and hard-code White-2 paths.**
Keep Black only as a cross-check when a White 2 archive looks wrong. Do not write a
"Gen 5" extractor that assumes one path table for both games.

---

## 7. Build-plan summary, ordered by effort

| Asset | Source | Effort | Notes |
|---|---|---|---|
| Party/box icons | W2 `/a/0/0/7` | **trivial** | dex-ordered, 32×64, 2 frames. Palette-index table still to find. |
| VS portraits | W2 `/a/2/6/7` | **trivial** | 128×128, block-grouped NCGR/NCLR. |
| Items / Poké Balls | W2 `/a/0/2/5` | **trivial** | 32×32, NCGR+NCLR pairs from entry 2. |
| Map tile library | W2 `/a/0/1/4` (+ `/a/1/7/4`, `/a/1/7/5`) | **low** | NSBTX/TEX0 decode + dedupe. 16×16 dominant. |
| Overworld chars (4 facings) | W2 `/a/0/3/1` | **low** | 32 sets, 32×32 frames. |
| Gen 4 battle sprites (fallback) | Platinum `pl_pokegra.narc` | **low** | flat 80×80 after a 5-line XOR. |
| Gen 5 battle sprites | W2 `/a/0/0/4` | **medium** | needs the multicell composer; ~90% done. |
| Gen 5 trainer sprites | W2 `/a/0/7/1` | **medium** | reuses the Pokémon composer. |
| Overworld walk/run cycles | ~~W2 `/a/2/9/1`~~ — **not in the ROM** | **high** | **Corrected:** `/a/2/9/1` is trainer-class battle art, not overworld (§2). Author the cycle by hand from `/a/0/3/1`'s four facing poses. |
| Automatic map reconstruction | — | **do not attempt** | 3D geometry; author maps in Godot instead. |

---

## 8. Format gotchas that cost me time — do not re-learn these

1. **The NCGR `linear` flag is at `CHAR + 0x14`, not `CHAR + 0x10`.** `+0x10` is the OBJ
   VRAM mapping/partition field. Getting this wrong makes every 512-tile atlas look like
   television static.
2. **A linear NCGR must be re-tiled before OAM tile indices work.** Cut the bitmap into
   8×8 tiles in reading order first.
3. **NCER's section magic is `KBEC`, not `RBEC`.** (NANR is `KNBA`, NMCR is `KBCM`,
   NMAR is `KNBA` too.)
4. **NANR sequence entries are 16 bytes and the frame pointer is the *last* u32** — a byte
   offset into the frame array, not the `startFrame` u16. Using the u16 makes every
   sequence return sequence 0's frames.
5. **NCLR `bitDepth` lies in Gen 5 pokegra** — it reads 4 (256-colour) while the data is a
   single 16-colour palette and the NCGR is 4bpp. Trust `dataSize` and `colorsPerPalette`.
6. **Git Bash mangles `/a/0/0/4` into a Windows path.** Set `MSYS_NO_PATHCONV=1`.
7. **PIL on this machine needs the Anaconda `Library/bin` on `PATH`** or `_imaging` fails
   to load:
   `export PATH="/c/Users/James/anaconda3:/c/Users/James/anaconda3/Library/bin:/c/Users/James/anaconda3/Library/mingw-w64/bin:$PATH"`

---

## 9. Scripts written (all in `tools/_work/gen5/`, gitignored)

| File | Purpose |
|---|---|
| `g5nds.py` | NDS FNT/FAT filesystem reader + NARC reader (handles BTAF/FATB spellings) |
| `nitrogfx.py` | LZ10/LZ11, NCLR, NCGR (tiled + linear), NCER, NANR, NSCR |
| `nsbtx.py` | NSBTX/BMD0 `TEX0` reader: Nitro 3D dictionary, all 7 texture formats incl. 4×4 block compression |
| `multicell.py` | BW battle-sprite rig: re-tile, NANR v2, NMCR nodes, cell compositor |
| `classify.py`, `sweep.py`, `sheet.py` | archive census and contact-sheet tooling used to identify every NARC above |

These are research scripts, not production code. The production extractor should be
rewritten cleanly under `tools/`, but the format knowledge above is the expensive part and
it is now settled.
