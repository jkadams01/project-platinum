# Pokémon Platinum (US, CPUE) — Where the game data lives

Research target: establish exact in-ROM locations and binary layouts for every data domain
needed to rebuild Platinum as a Godot fan remake.

**Status: verified against the real ROM.** Every path, count and struct below was confirmed by
dumping the actual cartridge filesystem in Python and parsing the bytes, not just read from a wiki.
Where a claim is only documented-but-unverified it says so explicitly.

---

## 1. ROM identity

| Field | Value |
|---|---|
| File | `References/Roms/Platinum/3541 - Pokemon Platinum Version (US)(XenoPhobia).nds` |
| Internal title | `POKEMON PL` |
| Game code | `CPUE` (C=DS, PU=Platinum, **E**=USA/English) |
| Maker | `01` (Nintendo) |
| FAT entries | **462** (= 340 named files + 122 ARM9 overlays) |
| Directories | 89 |
| ARM9 | ROM offset `0x4000`, size `0x1023F8`, load address `0x02000000`, **uncompressed** |
| Overlay table | ROM offset `0x106600`, 122 overlays |

Counts for the other reference ROMs (all US): Black `IRBO` 484 FAT / 247 named, White 2 `IRDO`
662 / 318, HeartGold `IPKE` 513 / 384. Those are Gen 5 / HGSS and use different layouts; they are
useful only as cross-checks, not as sources for Platinum structures.

### Reading the filesystem

Standard NDS FNT/FAT. Header `0x40`=FNT offset, `0x44`=FNT size, `0x48`=FAT offset, `0x4C`=FAT size.
FAT is 8 bytes/file (`u32 start`, `u32 end`). FNT directory entries are 8 bytes
(`u32 subtableOffset`, `u16 firstFileID`, `u16 parentID`); subtable entry type byte `0x01..0x7F` =
file name of that length, `0x81..0xFF` = directory (length `type & 0x7F`) followed by `u16 dirID`.

Overlays occupy file IDs `0..121`; named files start at ID 122. **That is why `len(FAT)` (462) is
larger than the number of named paths (340).**

### NARC container

Nearly every data file is a NARC. Layout: `"NARC"` magic, BOM, version, filesize,
`u16 headerSize`, `u16 numBlocks`; then blocks. `BTAF`/`FATB` holds `u16 numFiles` then
`u32 start, u32 end` per file (relative to the image base); `BTNF`/`FNTB` is usually a stub;
`GMIF`/`FIMG` + 8 is the image base. Sub-file *i* = `blob[base+start : base+end]`.

> **NARC sub-files are padded to a 4-byte boundary.** This matters for `trpoke.narc` — see §3.3.

---

## 2. Master table: narc path → contents → struct

Sizes are the real byte counts from this ROM. "n" is the sub-file count inside the NARC.

| In-ROM path | n | Contents | Per-entry layout |
|---|---|---|---|
| `/fielddata/encountdata/pl_enc_data.narc` | 183 | **Platinum wild encounters** (the live one) | fixed **424 B** — see §3.1 |
| `/fielddata/encountdata/d_enc_data.narc` | 183 | Diamond encounter tables (unused by Plat) | 424 B, same layout |
| `/fielddata/encountdata/p_enc_data.narc` | 183 | Pearl encounter tables (unused by Plat) | 424 B, same layout |
| `/arc/encdata_ex.narc` | 12 | Feebas tile species, honey-tree slots, Trophy Garden + Great Marsh daily rotations | see §3.2 |
| `/poketool/trainer/trdata.narc` | 928 | **Trainer headers** | fixed **20 B** — see §3.3 |
| `/poketool/trainer/trpoke.narc` | 928 | **Trainer parties** (parallel index) | variable, 8/10/16/18 B per mon, 4-byte padded |
| `/poketool/trmsg/trtbl.narc` | 1 | `(u16 trainerID, u16 msgType)` pairs, 2497 of them | 4 B/pair |
| `/poketool/trmsg/trtblofs.narc` | 1 | 928 × `u16` byte-offsets into `trtbl` | 2 B |
| `/fielddata/mapmatrix/map_matrix.narc` | 289 | **World layout matrices** | variable header + 3 arrays — §3.4 |
| `/fielddata/land_data/land_data.narc` | 666 | **Map chunks**: collision, props, 3D model, height mesh | 4×`u32` sizes + 4 sections — §3.5 |
| `/fielddata/areadata/area_data.narc` | 75 | Per-area tileset/texture/lighting selector | fixed **8 B** (4×`u16`) — §3.6 |
| `/fielddata/areadata/area_map_tex/map_tex_set.narc` | 74 | **Map textures** (NSBTX sets) | NSBTX |
| `/fielddata/areadata/area_build_model/area_build.narc` | 71 | Map-prop model ID lists per area | `u16` list |
| `/fielddata/areadata/area_build_model/areabm_texset.narc` | 71 | Map-prop textures | NSBTX |
| `/fielddata/build_model/build_model.narc` | 590 | Building / map-prop 3D models | NSBMD |
| `/fielddata/areadata/area_move_model/move_model_list.narc` | 75 | Preloaded overworld-sprite sets per area | `u16` list |
| `/data/mmodel/mmodel.narc` | 470 | **Overworld character sprites** | NSBMD/sprite |
| `/fielddata/eventdata/zone_event.narc` | 534 | **NPC / warp / trigger / sign placement per map** | 4 counted blocks — §3.7 |
| `/fielddata/script/scr_seq.narc` | 1124 | **Event scripts** | offset table + bytecode — §3.8 |
| `/msgdata/pl_msg.narc` | **724** | **All Platinum text** | encrypted string archive — §3.9 |
| `/msgdata/msg.narc` | 624 | Leftover Diamond/Pearl text (unused) | same format |
| `/msgdata/scenario/scr_msg.narc` | 16 | Scenario/debug strings | same format |
| `/fielddata/maptable/mapname.bin` | — | Map-name helper blob (not a NARC) | — |
| `/poketool/personal/pl_personal.narc` | 508 | **Species base stats + TM/HM compat** | fixed **44 B** — §3.10 |
| `/poketool/personal/wotbl.narc` | 508 | **Level-up learnsets** | `u16` packed, `0xFFFF` term — §3.10 |
| `/poketool/personal/evo.narc` | 508 | **Evolutions** | 7×6 B + 2 pad = 44 B — §3.10 |
| `/poketool/personal/pl_growtbl.narc` | 8 | EXP curves (8 growth rates) | `u32` per level |
| `/poketool/waza/pl_waza_tbl.narc` | 471 | **Move data** | fixed **16 B** — §3.11 |
| `/itemtool/itemdata/pl_item_data.narc` | 446 | **Item data** | fixed **34 B** — §3.11 |
| `/itemtool/itemdata/nuts_data.narc` | 64 | Berry growth data | — |
| `/poketool/pokegra/pl_pokegra.narc` | 2964 | Battle sprites (6 files/species) | NCGR/NCLR |
| `/poketool/icongra/pl_poke_icon.narc` | 547 | Party icons | NCGR |
| `/poketool/trgra/trfgra.narc` | 525 | Trainer battle sprites | NCGR/NCLR |
| **ARM9 `0xE601C`** | 593 | **Map header table** (not a NARC) | fixed **24 B** — §3.12 |

Platinum-specific files are prefixed `pl_`. The un-prefixed twins (`personal.narc`, `item_data.narc`,
`waza_tbl.narc`, `batt_bg.narc`, …) are the Diamond/Pearl originals left in the ROM and are **not**
what the game reads. Always take the `pl_` variant where one exists — except `wotbl.narc`,
`evo.narc` and `trdata/trpoke.narc`, which have no `pl_` twin and are the live files.

---

## 3. Struct layouts

### 3.1 Wild encounters — `pl_enc_data.narc`, 424 bytes fixed

One file per encounter set; a map header points at one by index. Matches
`WildEncounters` in pret/pokeplatinum `include/overlay006/wild_encounters.h`
and the packer `tools/jsoncnv/encounter.py`.

```
off  size  field
0x000  4   u32 landEncounterRate
0x004 96   GrassEncounter grass[12]   // each: s8 level; u8 pad[3]; u32 species  (8 B)
0x064  8   u32 swarm[2]               // species
0x06C  8   u32 dayOnly[2]             // species, replaces grass slots 2..3 by day
0x074  8   u32 nightOnly[2]           // species, replaces grass slots 2..3 by night
0x07C 16   u32 pokeRadar[4]           // species, replaces grass slots 4,5,10,11
0x08C 20   u32 encounterRatesForms[5]
0x0A0  4   u32 unownTableID
0x0A4  8   u32 dualSlot_Ruby[2]
0x0AC  8   u32 dualSlot_Sapphire[2]
0x0B4  8   u32 dualSlot_Emerald[2]
0x0BC  8   u32 dualSlot_FireRed[2]
0x0C4  8   u32 dualSlot_LeafGreen[2]
0x0CC 44   WaterEncounters surf       // u32 rate; then 5 x { u8 maxLvl; u8 minLvl; u8 pad[2]; u32 species }
0x0F8 44   WaterEncounters unused     // always zero-ish; keep the hole, it is real
0x124 44   WaterEncounters oldRod
0x150 44   WaterEncounters goodRod
0x17C 44   WaterEncounters superRod
       = 424
```

Note the asymmetry: **grass levels are a single `s8 level`; water entries carry `maxLevel` then
`minLevel` (max first).** Dual-slot slots replace grass slots 8..9 when the matching GBA cart is
inserted.

Spot-check from the ROM (encounter set 140 = Route 201):
grass rate 30, slots `Starly L2, Bidoof L2, Starly L3, Kricketot L3, …`;
day `Starly/Bidoof`, night `Kricketot/Bidoof`, radar `Nidoran♂/♀`, swarm `Doduo`;
dual-slot FireRed `Growlithe`. Set 135 (Lake Verity) gives Ruby→`Solrock`, Sapphire→`Lunatone`.
All match published Platinum data.

### 3.2 `encdata_ex.narc` — special encounter tables

| file | size | contents (decoded) |
|---|---|---|
| 0 | 4 | `u32` = FEEBAS (the Feebas-tile species) |
| 1 | 1068 | mixed table, starts `02 00 00 00 / E4 00 00 00 / 2C 01 00 00` then `u16`s — *not fully identified* |
| 2,3,5,6 | 24 | honey-tree slot species ×6 (`Combee, Wurmple, Burmy, Cherubi, Aipom, Aipom` / `Burmy, Cherubi, Combee, Aipom, Aipom, Heracross`) |
| 4,7 | 24 | Munchlax ×6 (rare honey-tree slot) |
| 8 | 64 | **Trophy Garden daily rotation**, 16 × `u32` species (Eevee, Bonsly, Happiny, Meowth, Cleffa, Clefairy, Igglybuff, Plusle, Jigglypuff, Ditto, Castform, Minun, Mime Jr., Marill, Chansey, Azurill) |
| 9 | 128 | **Great Marsh daily rotation**, post-National-Dex, 32 × `u32` |
| 10 | 128 | Great Marsh daily rotation, pre-National-Dex |
| 11 | 144 | `u16` pairs — *not fully identified* |

Corresponds to pret's `overlay006/great_marsh_daily_encounters.h`,
`trophy_garden_daily_encounters.h`, `dual_slot_encounters.h`.

### 3.3 Trainers — `trdata.narc` (20 B) + `trpoke.narc` (variable)

Two parallel NARCs, same index, 928 entries each. `trdata[i]` is the header, `trpoke[i]` is that
trainer's party blob.

```c
// trdata.narc — 20 bytes, matches pret struct TrainerHeader
struct TrainerHeader {
  u8  monDataType;   // 0..3, selects the party entry variant (see below)
  u8  trainerClass;  // index into text bank 619 (TRAINER_CLASS_NAMES)
  u8  sprite;
  u8  partySize;     // 0..6
  u16 items[4];      // battle items the AI may use
  u32 aiMask;        // AI flag bits (0x7 typical, 0xF for smarter bosses)
  u32 battleType;    // 0 = single, 2 = double
};
```

`monDataType` is the flags byte. **Bit 0 = has moves, bit 1 = has held item.**

| monDataType | variant | party entry layout | size |
|---|---|---|---|
| 0 | base | `u16 ivScale; u16 level; u16 species; u16 cbSeal` | **8 B** |
| 1 | with moves | `u16 ivScale; u16 level; u16 species; u16 moves[4]; u16 cbSeal` | **16 B** |
| 2 | with item | `u16 ivScale; u16 level; u16 species; u16 item; u16 cbSeal` | **10 B** |
| 3 | moves + item | `u16 ivScale; u16 level; u16 species; u16 item; u16 moves[4]; u16 cbSeal` | **18 B** |

- `species` field: low 11 bits = species, **upper bits (>> 10) = form**.
- `ivScale` low byte scales all IVs (`0..255`, 255 = perfect); gym leaders use 200–250.
- `cbSeal` is the capsule/ball-seal field, always present as the trailing `u16`.
- **The blob is `partySize × entrySize` rounded up to a multiple of 4.**

Verified: with the 4-byte rounding rule applied, predicted blob size equals the real NARC sub-file
size for **927 / 927** real trainers (trainer 0 is a dummy with `partySize = 0` but 8 bytes
allocated). Without the rounding rule, 43 entries mismatch — every one of them a `monDataType 3`
trainer with an odd party size (e.g. 3 × 18 = 54 stored in 56 bytes).

Distribution in this ROM: `monDataType` 0 → 672, 1 → 198, 2 → 4, 3 → 54.
`battleType` 0 → 900 single, 2 → 28 double.

**Trainer dialogue**: `trtbl.narc` file 0 is a flat array of 2497 `(u16 trainerID, u16 messageType)`
pairs. Message *k* of **text bank 617** (`NPC_TRAINER_MESSAGES`) belongs to `trtbl[k]`. Verified:
bank 617 has exactly 2497 entries, and pair 3 = `(246, 15)` → Roark, whose bank-617 string 3 is
*"Think you can take down the next Pokémon like you did earlier?"*. `trtblofs.narc` file 0 is
928 `u16` byte-offsets into `trtbl` (835 non-zero) giving each trainer's first pair.

### 3.4 Map matrix — `map_matrix.narc`, 289 entries

Defines world layout: which 32×32 land-data chunk, which map header, and what base altitude sits at
each cell of a grid. Layout confirmed against pret `tools/jsoncnv/map_matrix.py` **and** by exact
size arithmetic on all 289 files.

```
u8  width
u8  height
u8  hasHeaders     // bool
u8  hasAltitudes   // bool
u8  nameLength
char name[nameLength]      // ASCII, e.g. "map", "ugmap", "m_dun0602_"
u16 headers[w*h]     // only if hasHeaders
u8  altitudes[w*h]   // only if hasAltitudes
u16 maps[w*h]        // land_data.narc file index per cell; 0xFFFF = empty
```

All 289 files parse with the computed length exactly equal to the file size (0 mismatches).

- **Matrix 0 = `"map"`, 30×30, has headers and altitudes** — this is the Sinnoh overworld.
  `5 + 3 + 900*2 + 900 + 900*2 = 4508` bytes, exactly the real file size.
- Matrix 1 = `"single"` 1×1 (13 B), matrix 2 = `"ugmap"` 15×15 (460 B, the Underground).
- Interior maps get their own tiny matrix (`m_dun….`), typically 1×1 or 3×3, with no header array.

### 3.5 Land data — `land_data.narc`, 666 entries

One 32×32-tile map chunk per file.

```
u32 permissionsSize   // always 2048 = 1024 x u16 = 32x32 terrain-attribute tiles
u32 objectsSize       // map-prop placement records
u32 modelSize         // NSBMD ("BMD0")
u32 bdhcSize          // BDHC height mesh ("BDHC")
u8  permissions[permissionsSize]
u8  objects[objectsSize]
u8  model[modelSize]
u8  bdhc[bdhcSize]
```

Verified across **all 666 files**: `16 + permissions + objects + model + bdhc == fileSize`, zero
mismatches, and the `BMD0` / `BDHC` magic bytes appear exactly at the computed offsets.
`permissionsSize` is 2048 in every file — one `u16` terrain attribute per tile in a 32×32 grid.

### 3.6 Area data — `area_data.narc`, 8 bytes × 75

```c
struct AreaDataFile {   // pret include/overlay005/area_data.h
  u16 mapPropArchivesID;   // -> area_build.narc + areabm_texset.narc   (max seen 70, n=71)
  u16 mapTextureArchiveID; // -> map_tex_set.narc                        (max seen 73, n=74)
  u16 dummy04;             // varies in the NARC, unused by the code     (max seen 9)
  u16 areaLightArchiveID;  // -> data/arealight.narc                     (max seen 2, n=4)
};
```
Every value is inside its target archive's file count.

### 3.7 Overworld events — `zone_event.narc`, 534 entries

Four length-prefixed blocks, in this order. Confirmed against pret `tools/jsoncnv/event.py`.

```
u32 nBgEvents;      BgEvent      bg[nBgEvents];        // 20 B each — signs / interactables
u32 nObjectEvents;  ObjectEvent  obj[nObjectEvents];   // 32 B each — NPCs and trainers
u32 nWarpEvents;    WarpEvent    warp[nWarpEvents];    // 12 B each — doors / stairs
u32 nCoordEvents;   CoordEvent   trig[nCoordEvents];   // 16 B each — step triggers
```

```c
struct BgEvent {      // 20 B  — signposts, hidden items, interact-from-a-direction
  u16 scriptID; u16 type; u32 x; u32 z; u32 y; u16 playerFacingDir; u16 pad;
};
struct ObjectEvent {  // 32 B  — NPC / trainer placement
  u16 localID; u16 graphicsID; u16 movementType; u16 trainerType;
  u16 hiddenFlag;    // a var/flag id, or a map-header id in some entries
  u16 scriptID; u16 initialDir;
  u16 data[3];       // script params; for a trainer, data[0] is the local trainer slot
  u16 movementRangeX; u16 movementRangeZ;
  u16 x; u16 z;
  u32 y;             // fx32: tile height << 16
};
struct WarpEvent {    // 12 B
  u16 x; u16 z; u16 destHeaderID; u16 destWarpID; u32 pad;
};
struct CoordEvent {   // 16 B  — position triggers
  u16 scriptID; u16 x; u16 z; u16 width; u16 length; u16 y; u16 value; u16 varID;
};
```

Verified: parsing all 534 files with these sizes consumes **exactly** the file length —
**0 failures**. Totals across the game: 682 bg events, 3555 object events, 1213 warps,
186 coord triggers.

### 3.8 Scripts — `scr_seq.narc`, 1124 entries

Each file starts with a table of `u32` **relative** offsets (target = `positionAfterField + value`).
The table ends when the next `u32`'s low half-word is `0xFD13`; bytecode follows.

Example from the ROM, file 427 (Route 201's scripts): 16 entry-point offsets, table terminating at
`0x40`, first entries at byte 66, 114, 2528, 2700, 2852, 3958. Sizes across the archive run 4 B
(empty stub, 251 of them) to 9132 B.

Script opcodes are `u16`; the command table is large and game-specific — pret's
`include/data/scripts/scrcmd.h` is the reference. **Opcode semantics were not exhaustively verified
here.**

### 3.9 Text — `pl_msg.narc`, 724 entries

Each sub-file is one bank (one "text archive"). **Bank index == pret's `TEXT_BANK_*` enum ordinal**
— pret's `generated/text_banks.txt` has exactly 724 lines, matching the NARC's 724 files, and every
bank decodes cleanly under that mapping.

**Bank format** (per file):
```
u16 numEntries
u16 initialKey
{ u32 offset; u32 size; } table[numEntries]   // encrypted, size is in u16 units
u16 data[...]                                  // encrypted
```

**Decryption** (index `i` is 1-based):
```
key  = (initialKey * 0x2FD) & 0xFFFF
k    = (key * i) & 0xFFFF
mask = k | (k << 16)
offset ^= mask ;  size ^= mask

ck = (0x91BD3 * i) & 0xFFFF
for each u16 in the string:
    plain = raw ^ ck
    ck = (ck + 0x493D) & 0xFFFF
```

Character codes are **not** Unicode — they go through Game Freak's charmap
(pret `tools/msgenc/charmap.txt`, 2890 entries). Core ranges: `0x0121-0x012A` = `0-9`,
`0x012B-0x0144` = `A-Z`, `0x0145-0x015E` = `a-z`, `0x01DE` = space.
`0xFFFF` terminates, `0xFFFE` introduces a control code, `0xE000` is a newline.

**Name banks use a second compression layer.** If the first decrypted `u16` is `0xF100`, the rest is
a 9-bit-per-character packed bitstream — and critically, **only 15 of each `u16`'s bits are used**,
not 16. Terminator is `0x1FF`. (This is the detail that trips people up; a 16-bit accumulator
decodes the first character correctly and garbles everything after it.) Algorithm, straight from
pret's `MessagesDecoder::DecodeTrainerNameMessage`:

```
bit = 0; p = 1
loop:
    c = (msg[p] >> bit) & 0x1FF
    bit += 9
    if bit >= 15:
        p += 1; bit -= 15
        if bit != 0 and p < len: c |= (msg[p] << (9 - bit)) & 0x1FF
    if c == 0x1FF: stop
    emit c
```

**Banks you will need:**

| Bank | Name | n | Content |
|---|---|---|---|
| 392 | `ITEM_NAMES` | 468 | `None, Master Ball, Ultra Ball, …` |
| 412 | `SPECIES_NAME` | 496 | `-----, BULBASAUR, IVYSAUR, …` |
| **433** | `LOCATION_NAMES` | 126 | **Map / zone names** — `Mystery Zone, Twinleaf Town, Sandgem Town, …` |
| 610 | `ABILITY_NAMES` | 124 | |
| 615 | `TOWN_MAP` | 130 | Town-map blurbs |
| **617** | `NPC_TRAINER_MESSAGES` | 2497 | **Trainer battle dialogue** (paired via `trtbl`) |
| **618** | `NPC_TRAINER_NAMES` | 928 | **Trainer names** — 0xF100-compressed, 1:1 with `trdata` |
| 619 | `TRAINER_CLASS_NAMES` | 105 | `Youngster, Lass, …, Leader, Elite Four, Champion` |
| 624 | `POKEMON_TYPE_NAMES` | 18 | |
| 647 | `MOVE_NAMES` | 468 | |
| 699–707 | `SPECIES_POKEDEX_ENTRY_*` | 494 | Dex entries, incl. FR/DE/IT/ES/JP |
| 711 | `SPECIES_CATEGORY` | 494 | `Seed Pokémon` etc. |

Map names are reached as `LOCATION_NAMES[mapHeader.mapLabelTextID]` — verified: header 3
(Jubilife City) has `mapLabelTextID = 6` → bank 433 entry 6 = `"Jubilife City"`.

### 3.10 Species data

**`pl_personal.narc` — 44 bytes × 508** (493 species + index 0 + 14 alternate-form entries):

```
0x00 u8  baseHP        0x01 u8  baseAtk       0x02 u8  baseDef
0x03 u8  baseSpeed     0x04 u8  baseSpAtk     0x05 u8  baseSpDef
0x06 u8  type1         0x07 u8  type2
0x08 u8  catchRate     0x09 u8  baseExpReward
0x0A u16 evYields      // 2 bits each: HP,Atk,Def,Spe,SpA,SpD (low->high)
0x0C u16 heldItemCommon (50%)
0x0E u16 heldItemRare   (5%)
0x10 u8  genderRatio    0x11 u8  hatchCycles
0x12 u8  baseFriendship 0x13 u8  expRate (growth curve, indexes pl_growtbl.narc)
0x14 u8  eggGroup1      0x15 u8  eggGroup2
0x16 u8  ability1       0x17 u8  ability2
0x18 u8  safariFleeRate
0x19 u8  bodyColor : 7 | flipSprite : 1
0x1A u16 padding
0x1C u32 tmHmLearnset[4]   // 128 bits; bit k (0-based) = TM(k+1) for k<92, HM(k-91) for k>=92
     = 44
```

Verified against known values: Bulbasaur `45/49/49/45/65/65` Grass/Poison, catch 45, base exp 64,
EV +1 SpA, hatch 20, friendship 70, ability Overgrow. Garchomp `108/130/95/102/80/85` Dragon/Ground,
EV +3 Atk. Giratina `150/100/120/90/100/120` Ghost/Dragon, catch 3, friendship 0.
Field order is **HP, Atk, Def, Speed, SpAtk, SpDef** — Speed sits at index 3, not last.

**`wotbl.narc` — level-up learnsets, 508 entries, variable length.** Array of `u16`, terminated by
`0xFFFF`. Each entry packs `move = value & 0x1FF`, `level = value >> 9`.
Verified: Bulbasaur → `L1 Tackle, L3 Growl, L7 Leech Seed, L9 Vine Whip, L13 PoisonPowder,
L13 Sleep Powder, L15 Take Down, L19 Razor Leaf, …`; Turtwig → `L1 Tackle, L5 Withdraw, L9 Absorb,
L13 Razor Leaf, L17 Curse, L21 Bite, …`.

**`evo.narc` — 44 bytes × 508.** Seven slots of `{ u16 method; u16 param; u16 targetSpecies }`
(= 42 B) plus 2 bytes padding. Unused slots have `method == 0`.
Verified: Bulbasaur → `method 4 (level-up), param 16 → Ivysaur`; Eevee → all seven slots used
(Leafeon `m25`, Glaceon `m26`, Jolteon/Vaporeon/Flareon `m7` = use item, params 83/84/82,
Espeon `m2`, Umbreon `m3`); Snorunt → `m4 param 42 → Glalie` and `m17 param 109 → Froslass`.
Method constants are enumerated in pret `generated/evolution_methods.txt`.

### 3.11 Moves and items

**`pl_waza_tbl.narc` — 16 bytes × 471:**
```
0x00 u16 battleEffect
0x02 u8  category        // 0 = physical, 1 = special, 2 = status
0x03 u8  power
0x04 u8  type
0x05 u8  accuracy
0x06 u8  pp
0x07 u8  effectChance
0x08 u16 range / target
0x0A u8  priority
0x0B u8  flags           // contact, protectable, mirror-move-able, etc.
0x0C ..  contest data
```
Verified: Pound `pow 40 / acc 100 / pp 35 / Normal / physical`; Fire Punch `75/100/15 Fire physical,
effectChance 10`; Thunderbolt `95/100/15 Electric special`; Flamethrower `95/100/15 Fire special`;
Hyper Beam `150/90/5 Normal special`. The Gen-4 physical/special split is per-move in byte `0x02`,
not per-type.

**`pl_item_data.narc` — 34 bytes × 446:**
```
0x00 u16 price
0x02 u8  heldEffect
0x03 u8  heldParam
0x04 ... battle/field use flags, bag pocket, use-script params
```
Verified: Master Ball 0, Poké Ball 200, Great Ball 600, Ultra Ball 1200, Potion 300
(`heldParam = 20`, the HP it restores), Lansat Berry `heldEffect 63`.
Note `pl_item_data` has 446 entries vs D/P's 442 — Platinum adds items, so **do not** use
`item_data.narc`.

### 3.12 Map headers — ARM9, not a NARC

**Location: ARM9 file offset `0xE601C` → RAM `0x020E601C`. 593 entries × 24 bytes = 14232 bytes.**

This is the hub that ties everything together. The ARM9 in this ROM is uncompressed, so the table is
readable straight out of `ROM[0x4000 + 0xE601C]`.

```c
struct MapHeader {                 // 24 bytes
  /* 0x00 */ u8  areaDataArchiveID;              // -> area_data.narc            [0..74]
  /* 0x01 */ u8  preloadedMapObjectsArchiveID;   // -> area_move_model/move_model_list.narc
  /* 0x02 */ u16 mapMatrixID;                    // -> map_matrix.narc           [0..288]
  /* 0x04 */ u16 scriptsArchiveID;               // -> scr_seq.narc              [2..1123]
  /* 0x06 */ u16 initScriptsArchiveID;           // -> scr_seq.narc              [502..1050]
  /* 0x08 */ u16 msgArchiveID;                   // -> pl_msg.narc               [23..644]
  /* 0x0A */ u16 dayMusicID;
  /* 0x0C */ u16 nightMusicID;
  /* 0x0E */ u16 wildEncountersArchiveID;        // -> pl_enc_data.narc, 0xFFFF = none
  /* 0x10 */ u16 eventsArchiveID;                // -> zone_event.narc           [0..533]
  /* 0x12 */ u8  mapLabelTextID;                 // -> text bank 433             [0..125]
  /* 0x13 */ u8  mapLabelWindowID;               // popup frame style
  /* 0x14 */ u8  weather;
  /* 0x15 */ u8  cameraType;
  /* 0x16 */ u16 mapType : 7;                    // 1=town/city 2=outdoors 3=cave 4=indoors 5=PC 6=underground
             u16 battleBG : 5;
             u16 isBikeAllowed : 1;
             u16 isRunningAllowed : 1;
             u16 isEscapeRopeAllowed : 1;
             u16 isFlyAllowed : 1;
};
```

**How the offset was established (two independent methods, agreeing):**

1. *Fingerprint match against the decomp.* pret's `include/data/map_headers.h` gives a symbolic
   `msgArchiveID` for 593 headers; resolving those `TEXT_BANK_*` names through
   `generated/text_banks.txt` yields a 593-long integer fingerprint. Scanning the ARM9 at stride 24
   scored **593/593 at `0xE601C`**; the runner-up offset scored 115.
2. *DSPRE agrees.* `DS_Map/RomInfo.cs` → `SetHeaderTableOffset()` hardcodes
   `GameFamilies.Plat` + `GameLanguages.English` = **`0xE601C`**.

**Whole-table sanity check** — every index field in all 593 headers is inside its target archive:

| field | min | max | archive size | in range |
|---|---|---|---|---|
| `areaDataArchiveID` | 0 | 74 | 75 | yes |
| `preloadedMapObjectsArchiveID` | 0 | 55 | 75 | yes |
| `mapMatrixID` | 0 | 288 | 289 | yes |
| `scriptsArchiveID` | 2 | 1123 | 1124 | yes |
| `initScriptsArchiveID` | 502 | 1050 | 1124 | yes |
| `msgArchiveID` | 23 | 644 | 724 | yes |
| `eventsArchiveID` | 0 | 533 | 534 | yes |
| `mapLabelTextID` | 0 | 125 | 126 | yes |
| `wildEncountersArchiveID` | 0 | 182 (439 are `0xFFFF`) | 183 | yes |

> **Count gotcha: 593, not 596.** pret's `generated/map_headers.txt` has 596 lines, but the last
> three are enum sentinels (`MAP_HEADER_COUNT`, `MAP_HEADER_INVALID`, `MAP_HEADER_DYNAMIC = 4095`),
> not headers. Reading 596 entries walks 72 bytes past the table and produces garbage
> (`mapMatrixID = 843`, `mapLabelTextID = 155`, …). Reading 593 makes every field validate.

---

## 4. How a zone resolves to a header (and to everything else)

```
                           ┌── areaDataArchiveID ──> area_data.narc[n] ──> map_tex_set.narc  (map textures)
                           │                                          └──> area_build.narc + areabm_texset.narc (props)
                           ├── mapMatrixID ────────> map_matrix.narc[n]
                           │                          ├── maps[]      -> land_data.narc[n]  (collision + NSBMD + BDHC)
   MapHeader (ARM9 0xE601C)┤                          ├── headers[]   -> MapHeader (per cell, outdoor only)
                           │                          └── altitudes[]
                           ├── eventsArchiveID ────> zone_event.narc[n]  (NPCs, warps, triggers, signs)
                           ├── scriptsArchiveID ───> scr_seq.narc[n]
                           ├── wildEncountersArchiveID -> pl_enc_data.narc[n]   (0xFFFF = no encounters)
                           ├── msgArchiveID ───────> pl_msg.narc[n]     (this map's dialogue)
                           └── mapLabelTextID ─────> pl_msg.narc[433][id]  (the map's display name)
```

Two different directions, and it is easy to conflate them:

- **Indoor / dungeon maps** own a private matrix (`m_dun…`, usually 1×1 or 3×3) with no `headers[]`
  array. The header you are in is fixed — the one you warped into.
- **The Sinnoh overworld** is one 30×30 matrix (matrix 0). 84 headers declare `mapMatrixID == 0`,
  and matrix 0's `headers[]` array says which of them applies to each 32×32 cell. **The current
  header is a function of where you are standing**, which is how walking from Route 201 into
  Sandgem Town swaps music, encounters and the map-name popup with no warp.

Self-consistency check: matrix 0's `headers[]` references 67 distinct headers, and **all 67 have
`mapMatrixID == 0`** — the mapping is closed. The 17 headers that claim matrix 0 but never appear in
`headers[]` are `MAP_HEADER_NOTHING` plus 16 `MAP_HEADER_UNKNOWN_*` unused entries.
Matrix 0's `maps[]` has 468 live cells (of 900), all pointing inside `land_data.narc`'s 666 files;
across all 289 matrices, **zero** cells point outside `land_data.narc`.

---

## 5. Boss levels → level-cap table

All rosters below were decoded from `trdata`/`trpoke` in this ROM. `#` is the trainer ID.
Note Platinum's gym order differs from Diamond/Pearl: **Fantina is 3rd**, not 5th — and the level
data confirms it (Fantina 24–26 sits between Gardenia 20–22 and Maylene 28–32).

### Gym Leaders

| # | Badge | Leader | Roster | Ace | **Cap** |
|---|---|---|---|---|---|
| 246 | 1 Coal | **Roark** | Geodude 12, Onix 12, **Cranidos 14** | Cranidos | **14** |
| 315 | 2 Forest | **Gardenia** | Turtwig 20, Cherrim 20, **Roserade 22** | Roserade | **22** |
| 318 | 3 Relic | **Fantina** | Duskull 24, Haunter 24, **Mismagius 26** | Mismagius | **26** |
| 317 | 4 Cobble | **Maylene** | Meditite 28, Machoke 29, **Lucario 32** | Lucario | **32** |
| 316 | 5 Fen | **Crasher Wake** | Gyarados 33, Quagsire 34, **Floatzel 37** | Floatzel | **37** |
| 250 | 6 Mine | **Byron** | Magneton 37, Steelix 38, **Bastiodon 41** | Bastiodon | **41** |
| 319 | 7 Icicle | **Candice** | Sneasel 40, Piloswine 40, Abomasnow 42, **Froslass 44** | Froslass | **44** |
| 320 | 8 Beacon | **Volkner** | Jolteon 46, Raichu 46, Luxray 48, **Electivire 50** | Electivire | **50** |

### Elite Four + Champion

| # | Trainer | Roster | **Cap** |
|---|---|---|---|
| 261 | **Aaron** (Bug) | Yanmega 49, Scizor 49, Vespiquen 50, Heracross 51, **Drapion 53** | **53** |
| 262 | **Bertha** (Ground) | Whiscash 50, Gliscor 53, Hippowdon 52, Golem 52, **Rhyperior 55** | **55** |
| 263 | **Flint** (Fire) | Houndoom 52, Flareon 55, Rapidash 53, Infernape 55, **Magmortar 57** | **57** |
| 264 | **Lucian** (Psychic) | Mr. Mime 53, Espeon 55, Bronzong 54, Alakazam 56, **Gallade 59** | **59** |
| 267 | **Cynthia** (Champion) | Spiritomb 58, Roserade 58, Togekiss 60, Lucario 60, Milotic 58, **Garchomp 62** | **62** |

Every E4 member carries 2 Full Restores; Cynthia carries 4. Aces hold a Sitrus Berry.
Lucian's `aiMask` is `0xF` (the others are `0x7`) — he gets the smarter AI.

### Rival (default name "Cedric"; player renames him, canonically Barry) — trainer class 63

Each fight exists as **three consecutive trainer IDs**, one per starter the player chose
(the rival takes the type advantage). IDs below are the Turtwig / Chimchar / Piplup triple.

| # | Where | Party | **Cap** |
|---|---|---|---|
| 850–852 | Lake Verity (scripted) | starter 5 | 5 |
| 247–249 | Route 203 | Starly 7, starter 9 | 9 |
| 470–472 | Floaroma / Valley Windworks era | Staravia 25, Buizel/Roselia 23, Ponyta/Roselia 23, starter-2 27 | 27 |
| 473–475 | Veilstone | Staravia 34, +32s, starter-2 36 | 36 |
| 476–478 | Canalave | Staraptor 36, Floatzel/Roserade 35, Heracross 37, Rapidash 35, starter-3 38 | 38 |
| 607, 619, 620 | Mt. Coronet | Munchlax 40, Staraptor 42, …, starter-3 44 | 44 |
| 479–481 | Pokémon League | Staraptor 48, 47s, Snorlax 49, **starter-3 51** | **51** |
| 923–925 | post-game | up to 56 | 56 |
| 837–839 / 840–842 / 871–873 | post-game rematches | 65 / 75 / 85 | — |

### Team Galactic

| # | Trainer | Roster | **Cap** |
|---|---|---|---|
| 295 | **Mars** — Valley Windworks | Zubat 15, **Purugly 17** | **17** |
| 406 | **Jupiter** — Eterna Galactic Building | Zubat 21, **Skuntank 23** | **23** |
| 913 | **Cyrus** — Celestic Town | Sneasel 34, Golbat 34, **Murkrow 36** | **36** |
| 408 | **Saturn** — Lake Valor | Golbat 38, Bronzor 38, **Toxicroak 40** | **40** |
| 405 | **Mars** — Lake Verity | Golbat 38, Bronzor 38, **Purugly 40** | **40** |
| 409 | **Saturn** — Galactic HQ | Golbat 42, Bronzor 42, **Toxicroak 44** | **44** |
| 403 | **Cyrus** — Galactic HQ | Sneasel 44, Crobat 44, **Honchkrow 46** | **46** |
| 528 / 407 | **Mars & Jupiter** — Distortion World (double) | Bronzor/Golbat 44, **Purugly / Skuntank 46** | **46** |
| 404 | **Cyrus** — Distortion World (final) | Houndoom 45, Honchkrow 47, Crobat 46, Gyarados 46, **Weavile 48** | **48** |
| 921 / 922 / 926 / 927 | post-game (Volkner 58, Flint 58, Mars 60, Jupiter 60) | | — |

### Suggested level-cap progression

Taking the ace level of each mandatory story fight, in play order:

```
  5  rival (Lake Verity)          14  Roark            22  Gardenia
  9  rival (Route 203)            17  Mars  (Windworks)
 23  Jupiter (Eterna)             26  Fantina          27  rival
 32  Maylene                      36  Cyrus (Celestic) 37  Crasher Wake
 38  rival (Canalave)             40  Mars/Saturn (Lakes)
 41  Byron                        44  Candice / Saturn / rival (Coronet)
 46  Cyrus (HQ) / Mars+Jupiter    48  Cyrus (Distortion World)
 50  Volkner                      51  rival (League)
 53  Aaron  55  Bertha  57  Flint  59  Lucian  62  Cynthia
```

---

## 6. US vs JP (and other-language) differences

**The safe rule: address NARCs by path, never by file ID.**

- **File IDs are not portable.** Of the 77 paths present in *both* Platinum (US) and HeartGold (US),
  **100% have a different FAT index** (e.g. `/data/arealight.narc` is file 168 in Platinum and 397
  in HeartGold). The same instability applies across regional builds of the same game. Resolve the
  FNT and look paths up by name.

- **`/resource/<lang>/` is the language-specific directory.** This US ROM carries `/resource/eng/…`
  (7 files: `batt_rec_gra`, `frontier_bg`, `frontier_obj`, `pms_aikotoba`, `scratch`,
  `wlmngm_tool`, `zukan`). A JP build carries the JP equivalent instead. DSPRE also notes that in
  Spanish/Italian/French/German builds `fld_trade.narc` moves from
  `fielddata/pokemon_trade/` to `resource/<lang>/pokemon_trade/`. *(Path-shift documented by DSPRE;
  I do not have a JP or EU ROM here to confirm directly.)*

- **The ARM9 map-header table offset is language-specific.** It is *not* in a NARC, so it has to be
  hardcoded per build. From DSPRE's `RomInfo.SetHeaderTableOffset()`:

  | Platinum build | ARM9 offset |
  |---|---|
  | **English** | **`0xE601C`** ← verified byte-exact against this ROM |
  | Spanish | `0xE60B0` |
  | Italian | `0xE6038` |
  | French | `0xE60A4` |
  | German | `0xE6074` |
  | **Japanese** | **`0xE56F0`** |

  (For contrast: D/P English `0xEEDBC` / JP `0xF0D68`–`0xF0D6C`; HGSS English `0xF6BE0` / JP
  `0xF6390`.) Only the English value is verified here.

- **Text bank *count* is build-dependent.** This US ROM's `pl_msg.narc` holds 724 banks, and that
  exactly matches pret's `generated/text_banks.txt` — pret targets the US build. A JP ROM will not
  have the FR/DE/IT/ES Pokédex banks (699–705), so bank indices above ~690 will not line up.
  Bank indices at or below the gameplay banks used here (392, 412, 433, 617–619, 624, 647) should be
  re-derived, not assumed, if a non-US ROM is ever used.

- **Structure layouts (encounters, trainers, personal, matrices, land data, events) are
  region-independent.** Only indices and offsets move.

---

## 7. Verification log

Everything below was executed against the real ROM in this session.

| Claim | How it was checked | Result |
|---|---|---|
| FAT/FNT parse | dumped full filesystem | 340 named files + 122 overlays = 462 FAT, matches expectation |
| encounter struct = 424 B | `Counter` over all sub-file sizes | 183/183 are exactly 424 B; C struct arithmetic also sums to 424 |
| encounter contents | decoded Routes 201/203, Lake Verity, Route 212 | matches published Platinum tables incl. dual-slot Solrock/Lunatone |
| trainer header = 20 B | all sub-file sizes | 928/928 exactly 20 B |
| trpoke variant sizes + 4-byte padding | predicted size from `monDataType`+`partySize`, compared to real | **927/927 exact** (43 mismatches without the padding rule) |
| map matrix layout | recomputed length from w/h/flags/name for every matrix | 289/289 exact size fit |
| land data layout | `16+perm+objs+model+bdhc == filesize` | **666/666 exact**; `BMD0`/`BDHC` magic at computed offsets |
| event file layout | parsed 4 counted blocks, compared consumed bytes to size | **534/534 exact, 0 failures** |
| map header table offset | 593-value `msgArchiveID` fingerprint from pret, scanned ARM9 at stride 4 | **593/593 at `0xE601C`**, next best 115 |
| map header offset (independent) | DSPRE `RomInfo.SetHeaderTableOffset()` | `0xE601C` for Plat/English — agrees |
| map header field semantics | bounds-checked all 8 index fields across 593 headers | every value inside its target archive |
| header count = 593 | fields validate at 593, break at 596 | last 3 `map_headers.txt` lines are enum sentinels |
| text decryption + charmap | decoded all 724 banks | all decode; move/item/ability/type names read correctly |
| 0xF100 15-bit unpacking | decoded bank 618 | `Tristan, Logan, Natalie, Michael, Mickey, …` |
| text bank index == pret enum | 724 files vs 724 lines in `text_banks.txt` | 1:1, and labels match content |
| trainer message pairing | bank 617 entry count vs `trtbl` pair count | 2497 == 2497; spot-checked Roark's line |
| personal struct | decoded Bulbasaur / Garchomp / Giratina | base stats, types, catch rate, abilities all correct |
| learnset packing | decoded Bulbasaur, Turtwig | matches published learnsets |
| evolution struct | decoded Eevee (7 branches), Snorunt, Slowpoke | all branches correct |
| move struct | decoded Pound, Fire Punch, Thunderbolt, Flamethrower, Hyper Beam | power/acc/pp/type/category all correct |
| item struct | decoded ball + Potion prices | 0 / 200 / 600 / 1200 / 300 — correct |
| boss rosters | decoded all leaders, E4, Cynthia, rival, Galactic | matches published Platinum rosters exactly |
| zone→header closure | matrix 0 `headers[]` vs headers claiming matrix 0 | 67 referenced, all 67 have `mapMatrixID == 0` |
| file-ID instability | 77 shared paths, Platinum vs HeartGold | 77/77 differ |

### Sources

- [pret/pokeplatinum](https://github.com/pret/pokeplatinum) — `include/overlay006/wild_encounters.h`,
  `include/constants/wild_encounters.h`, `include/struct_defs/trainer_data.h`, `include/map_header.h`,
  `include/overlay005/area_data.h`, `include/constants/narc.h`, `src/narc.c`,
  `tools/jsoncnv/{event,encounter,map_matrix,area_data}.py`, `tools/msgenc/{MessagesDecoder.cpp,charmap.txt}`,
  `generated/{text_banks.txt,map_headers.txt,species_data_params.txt}`, `include/data/map_headers.h`
- [DSPRE](https://github.com/DS-Pokemon-Rom-Editor/DSPRE) — `DS_Map/RomInfo.cs` (header table offsets,
  per-version narc paths)
- [Project Pokémon Platinum file list](https://projectpokemon.org/rawdb/platinum/)

---

## 8. Gotchas that will bite the extractor

1. **`monDataType` party blobs are 4-byte aligned.** 3 mons × 18 B = 54, stored in 56. Read
   `partySize × entrySize`, ignore the tail.
2. **Map header count is 593, not 596.** The extra three are enum sentinels.
3. **0xF100 name text packs 9-bit chars into 15 usable bits per `u16`**, not 16. A 16-bit
   accumulator decodes exactly the first character correctly, which makes the bug look like a
   charmap problem.
4. **Use the `pl_` files.** `personal.narc` (501), `item_data.narc` (442) and `waza_tbl.narc` are
   D/P leftovers; Platinum reads `pl_personal.narc` (508), `pl_item_data.narc` (446),
   `pl_waza_tbl.narc`. But `wotbl`, `evo`, `trdata`, `trpoke` have **no** `pl_` twin.
5. **Personal stat order is HP, Atk, Def, Speed, SpAtk, SpDef** — Speed is third, not last.
6. **Water encounters store maxLevel before minLevel**; grass stores a single level.
7. **Don't index NARCs by FAT file ID.** Resolve the FNT and use paths.
8. `land_data` `permissions` is a 32×32 grid of `u16` terrain attributes — 2048 bytes in every one
   of the 666 files.
9. Encounter set index `0xFFFF` in a map header means "no wild encounters", not "set 65535".
   439 of 593 headers use it.
10. The Sinnoh overworld's current map header depends on **the matrix cell you stand on**, not on a
    warp. Zone transitions on the world map have no event behind them.
