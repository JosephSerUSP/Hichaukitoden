# First-stratum rich surface + fixture batch — 2026-08-06

## What the latest ratings actually say

The current rating store was reviewed before defining this batch. The useful pattern is not simply “less detail.” It is a distinction between **repeatable material structure** and **localized environmental events**.

### Reliable structures

- Broad irregular flagstones are the clearest floor success. `damp_masonry_floor_flagstones_v2` scored **5 / 6 / 6**, with notes calling out excellent tiling.
- The intact/decayed and ochre/slate floor A/B sets were consistently strong, including several complete **6 / 6 / 6** groups.
- Broad varied slabs remain usable even when their material state changes. They fail occasionally through harshness, but much less systematically than cobbles.
- Wall pilasters and niches are stable when the prompt describes a concrete front-facing structure. The bronze-inlay pilaster groups are mostly **5–6**, and fitted-limestone niches are repeatedly **5**.
- Boulders and broad rubble can work because the authored geometry gives SD a large-scale structure to paint rather than asking it to invent many tiny repeated units.

### Repeated failure modes

- Small cobble geometry is the strongest recurring failure. Cold-slate cobbles scored **2 / 2 / 2**; damp-masonry cobbles scored **2 / 2 / 3**, and the rough version **3 / 3 / 2**, with repeated `repeat`, `seam`, and `harsh` tags.
- “Eroded wall,” “cistern infrastructure,” and similarly scene-bearing language repeatedly turns the material request into a photographed corridor, facade, or architectural view. The latest cistern-eroded and limewash-eroded wall groups scored **1 / 1 / 1** with `perspective` and `picture` tags.
- “Collapse,” “root incursion,” “scorch,” and “damp” are valuable art directions but unreliable as properties of a tile repeated every cell. Some outputs look compelling in the map preview or even in-game while still not being material textures.
- The old positive tag templates also pulled in two directions: they requested baked occlusion and deep dark joints while the global negative prompt rejected hard/black shadows, and they placed a literal negation in positive CLIP text. This batch replaces that wording with low-contrast value structure, local joint occlusion, and even ambient fill.

## Batch design

The batch contains **15 concepts × 3 variants = 45 candidates**.

### Six base surfaces

1. Broad irregular fitted flagstones
2. Broad varied restrained slabs
3. Broad ashlar wall courses
4. Quiet limewash undulation
5. Shallow crossed ceiling ribs
6. Wide ceiling coffers

These are fully opaque height maps and must tile on their active axes.

### Nine localized surface fixtures

1. Wall votive relief — `add`
2. Wall reliquary niche — `replace`
3. Wall breach socket — `replace`
4. Wall drain runnel — `replace`
5. Floor shallow puddle — `replace`
6. Floor collapsed socket — `replace`
7. Floor bronze rite inlay — `add`
8. Ceiling root fissure — `replace`
9. Ceiling drip boss — `add`

Fixtures deliberately reach **neutral grey and alpha 0** before every wrapping border. Alpha is not decorative transparency: it is geometric influence. At alpha 0 the base surface is ignored; through the feather it merges; at alpha 1 the fixture contributes according to `add` or `replace`.

Stable Diffusion does not author fixture alpha. The runner copies alpha from the height map into an equally sized albedo/height pair after generation and bleeds covered RGB underneath transparent texels to prevent edge fringes.

## Files

- Authored map generator: `tools/asset-gen/build_surface_fixture_batch_20260806.py`
- Height maps and visual sheet: `assets/geometry/3_authored_surface_maps/first_stratum_20260806/`
- Machine-readable render jobs: `tools/asset-gen/batches/first_stratum_surface_fixture_20260806.json`
- Sequential render/alpha runner: `tools/asset-gen/run_surface_fixture_batch_20260806.py`

## Exact render baseline

- Provider: `forge-quality`
- Checkpoint: `ohmenOrigins_ohmenOriginsV3`
- VAE: inherited from provider config, `vaeFtMse840000EmaPruned_vaeFtMse840k.safetensors`
- Sampler: `DPM++ 2M`
- Steps: `26`
- CFG: `6.5`
- Source request: `512×512`
- Variants: `3`
- Base depth weight: `0.52–0.62`
- Fixture depth weight: `0.76–0.84`
- Base tiling: provider tiling enabled
- Fixture tiling: provider circular padding disabled; the authored zero-alpha border makes the composed fixture tile safely

## Commands

Regenerate and validate authored geometry:

```bash
python tools/asset-gen/build_surface_fixture_batch_20260806.py
python tools/asset-gen/build_surface_fixture_batch_20260806.py --check
```

Inspect all exact SD commands without spending render time:

```bash
python tools/asset-gen/run_surface_fixture_batch_20260806.py --dry-run
```

Run sequentially after Forge is serving its API on port 7860:

```bash
python tools/asset-gen/run_surface_fixture_batch_20260806.py
```

Resume is automatic: a complete matching staged run is reused. Useful subdivisions:

```bash
python tools/asset-gen/run_surface_fixture_batch_20260806.py --group base
python tools/asset-gen/run_surface_fixture_batch_20260806.py --group fixture
python tools/asset-gen/run_surface_fixture_batch_20260806.py --start-at wall_reliquary
python tools/asset-gen/run_surface_fixture_batch_20260806.py --only puddle
```

## Curation gates

### Base surface candidate

Keep only when all are true:

- Reads as a material swatch, never a room, corridor, facade, floor plane receding in depth, or framed picture.
- Authored large-scale height structure remains legible without becoming harsh black crevices.
- No obvious repeated focal stone, face-like arrangement, burned contour, or central emblem.
- Active-axis wrap and relocated centre seam are both visually acceptable; metric target remains `<= 2.0`.
- The 64×64 processed result retains broad material grouping instead of collapsing into high-frequency noise.

### Fixture candidate

Keep only when all are true:

- Exactly one fixture is fully contained in frame with generous surrounding base material.
- It is front-facing/orthographic; a niche or breach must show a materially readable back plane, not a view into another scene.
- The prepared `fixture-N.png` and `fixture-height-N.png` have identical dimensions and alpha.
- Transparent borders remain empty on every active wrapping axis.
- At 64×64 the alpha silhouette still reads and is broad enough for the intended mesh sampling density.
- Review the prepared fixture composed over at least one quiet base wall/floor/ceiling; do not rate only the opaque raw SD image.

Do **not** auto-promote this batch. Selection should happen after the report, alpha preparation, seam inspection, and in-engine composition preview.
