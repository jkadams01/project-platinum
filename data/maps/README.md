# `data/maps/` — hand-authored map geometry

**This directory is committed.** CLAUDE.md's "Hard rules" table lists
`data/maps/**` (hand-authored) in the *Committed* column, and DATA_CONTRACT.md 9
owns the shape.

## The rule

Everything in here is drawn by hand in **`tools/build_maps.py`** and regenerated
with:

```bash
python tools/build_maps.py          # write + validate
python tools/build_maps.py --check  # validate what is already on disk
```

No ROM is opened to produce these files. The only ROM-adjacent numbers are the
**tile indices** in `layers.*`, which are integer offsets into the gitignored
`assets/generated/tilesets/outdoor_sinnoh.png` atlas — the same kind of index the
committed `tests/fixtures/maps/*.json` have always carried. Collision codes,
warps, traversal obstacles and objects are all original design data.

## What must never land here

**ROM-extracted map geometry.** Platinum's real matrices, movement permissions
and event tables are copyrighted level design. If a pipeline is ever written to
dump them (the ARM9 map-header table at `0xE601C`, `/fielddata/`), it must write
to `data/rom/maps/` — which *is* gitignored — and never to this directory.

`git check-ignore -v <path>` before adding any new output path, per CLAUDE.md.

## What is here

The playable vertical slice, nine maps, 16 warps, every adjacency wired both
ways:

```
twinleaf_town → route_201 → sandgem_town → route_202 → jubilife_city
              → route_203 → oreburgh_gate → oreburgh_city → oreburgh_gym (Roark)
```

* Tall grass (collision `4`) on Routes 201/202/203, wired to the
  `route_20{1,2,3}` zones of `data/rom/encounters.json`.
* One `smash` obstacle in `oreburgh_gate` requiring `badge:coal`. It gates a
  **dead-end alcove only** — Roark is the boss who awards that badge, so a rock
  across the main corridor would make the slice unwinnable.
  `tools/build_maps.py` and `tests/test_maps.gd` both prove the two halves of
  that: Roark reachable with no badges, alcove reachable only with Coal.
