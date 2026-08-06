# Deterministic Surface Baselines V2

## Purpose

The first Blender depth-map library was authored before the project had a
shared Blender core or explicit procedural-modeling guidance. Its canonical
pixels depended on evaluated Blender geometry and first-hit ray casting. The
`wall_boulders_rough` diagnostic demonstrated that this is not a dependable
source of truth: Blender 5.1.2 produced different pixels across repeated runs on
the same machine.

V2 deliberately starts from new asset designs. It does not attempt to preserve
or cosmetically revise the legacy PNGs.

## Authority boundary

The canonical path is:

```text
fixed-point surface recipe
        ↓
signed Q15 scalar field
        ├── 16-bit height_metric.png
        ├── 8-bit depth_guide.png
        └── hashes and baseline.json
```

Blender consumes the same recipe and verifies the field hash before creating an
inspection mesh, `.blend`, or preview render:

```text
canonical recipe + recorded field hash
        ↓
Blender preview mesh/render (derivative, never canonical)
```

No Blender ray cast, BVH order, modifier evaluation order, camera, light,
material, render engine, or Blender version determines the canonical field.

## Generator

The repository-owned generator is:

```text
tools/asset-gen/surface_baselines_v2.py
```

It uses only deterministic integer operations for canonical geometry:

- a repository-defined 64-bit integer mixer;
- coordinate hashes rather than Python's `random` module;
- fixed integer seeds per recipe;
- signed Q15 relief values;
- integer square roots for radial forms;
- explicit copying of declared periodic edges;
- deterministic median and p99 guide normalization.

Pillow is used only to serialize already-determined integer samples to PNG.

Generate the complete baseline set:

```text
python tools/asset-gen/surface_baselines_v2.py --runs 3
```

Verify the checked-in baselines byte-for-byte:

```text
python tools/asset-gen/surface_baselines_v2.py --runs 3 --verify
```

`--verify` generates into a temporary directory and does not modify tracked
assets.

## Canonical baseline set

The first V2 set contains four intentionally new designs:

| Asset ID | Surface | Tiling | Intent |
| --- | --- | --- | --- |
| `wall_ritual_pilasters` | wall | X | Repeating pilaster bays, recessed panels, shallow arches, cornice and base course. |
| `floor_broken_flagstones` | floor | XY | Irregular periodic stones with deep mortar, crown variation and restrained chipping. |
| `ceiling_shallow_coffers` | ceiling | XY | Four-by-four coffers with raised ribs, bevelled recesses and small bosses. |
| `wall_ossuary_boulders` | wall | X | Ordered courses of irregular stones with deterministic crowns, chips and fissures. |

They live under:

```text
assets/geometry/2_procedural_surface_baselines/
```

Each asset directory contains:

```text
height_metric.png
  16-bit metric product. Neutral 32768. Explicit rangeCells 0.25.

depth_guide.png
  8-bit normalized guide. Neutral 128. Contrast range ±112.

baseline.json
  Contract vocabulary, seed, recipe version, dimensions, encoding, relief
  range and SHA-256 provenance.
```

The root `manifest.json` indexes all four baselines and their canonical hashes.

## Encoding

The scalar field is stored internally as signed Q15 relief:

```text
-32767 ≤ fieldQ15 ≤ 32767
```

Metric encoding follows contract version 1:

```text
encoded = 32768 + fieldQ15
reliefCells = fieldQ15 / 32767 × rangeCells
rangeCells = 0.25
```

The guide product follows the non-metric contract:

1. find the deterministic integer median;
2. subtract it;
3. find the deterministic p99 absolute deviation;
4. scale to ±112;
5. clamp to `[16, 240]` around neutral 128.

The exact median and p99 scale are recorded per asset.

## Blender preview

Use:

```text
blender --background --factory-startup \
  --python tools/asset-gen/blender/build_surface_v2_preview.py -- \
  --asset wall_ritual_pilasters \
  --out-dir <temporary-output>
```

The script:

1. loads the recipe directly;
2. regenerates the Q15 field;
3. compares it with `baseline.json`'s field hash;
4. creates a mesh with `mesh.from_pydata`;
5. assigns shared contract and material metadata;
6. saves a `.blend` and render in the requested temporary directory.

The `.blend` and render are inspection derivatives and must not be used to
reconstruct the canonical PNGs.

## Validation gates

Phase 4 V2 requires:

```text
recipe run 1 == run 2 == run 3
field Q15 hash exact
height_metric.png bytes exact
depth_guide.png bytes exact
declared tile edges exact
contract vocabulary valid
tracked baseline set == regenerated baseline set
Blender preview field hash == baseline field hash
no BVH or ray-cast canonical generation
```

The host test is:

```text
python -m unittest discover \
  -s tools/asset-gen/tests \
  -p "test_surface_baselines_v2.py" \
  -v
```

The Blender preview test remains machine-dependent and must be run on a system
with Blender 5.1 or another explicitly recorded supported build.

## Legacy status

`assets/geometry/1_blender_depth_maps/` remains intact as historical and
compatibility evidence. Its exact PNGs are not V2 acceptance targets.

`tools/blender/depth_baseline.py` remains a diagnostic tool for explaining the
legacy nondeterminism. It is not the canonical V2 generator and must not be used
to adopt V2 assets.
