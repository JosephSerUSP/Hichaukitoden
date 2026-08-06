---
name: second-rite-surface-baselines
description: >-
  Author deterministic wall, floor, and ceiling surface baselines for Second
  Rite. Use for metric height fields, depth guides, tileable procedural relief,
  baseline manifests, and Blender inspection meshes derived from canonical
  scalar fields.
license: project
metadata:
  version: "1.0.0"
  category: asset-pipeline
  tags: ["surface", "heightmap", "depth", "procedural", "deterministic"]
---

# Second Rite Surface Baselines

## Governing rule

Canonical surface pixels must exist **before Blender**.

Use this authority chain:

```text
fixed-point recipe
→ signed Q15 scalar field
→ height_metric.png + depth_guide.png + baseline.json
→ optional Blender mesh/render derivative
```

Never use Blender BVH traversal, `scene.ray_cast`, evaluated modifier order,
Cycles, EEVEE, compositing, or a rendered image as the source of canonical
height values.

## Canonical generator

```text
tools/asset-gen/surface_baselines_v2.py
```

Before changing a recipe, read:

```text
docs/asset-pipeline/SURFACE_BASELINES_V2.md
tools/asset-language/contract.json
```

## Deterministic recipe requirements

A canonical recipe must:

- use a fixed integer seed;
- use the repository mixer/hash helpers rather than `random`;
- perform canonical geometry in integer or explicitly quantized arithmetic;
- return exactly `size × size` signed Q15 values;
- clamp to `[-32767, 32767]`;
- declare wall, floor, or ceiling;
- declare `x` or `xy` tile axes;
- make declared opposite edges exactly equal;
- contain no reads from tracked output PNGs;
- contain no preset-specific correction masks;
- contain no timestamp or machine-dependent input.

Use intentional forms before noise:

- architectural modules, bays, ribs, mouldings, joints, coffers and recesses;
- stone cells, crowns, mortar, courses, chips and fissures;
- explicit silhouettes and spacing;
- low-amplitude hashed damage subordinate to the large form.

Do not use noise as the design.

## Encodings

### Metric product

```text
file: height_metric.png
mode: 16-bit grayscale
neutral: 32768
rangeCells: explicit, currently 0.25
encoded = 32768 + fieldQ15
```

### Guide product

```text
file: depth_guide.png
mode: 8-bit grayscale
neutral: 128
contrast: ±112
normalization: median subtract, p99 absolute-deviation scale, clamp
```

The metric product is geometric truth. The guide is non-metric conditioning and
human inspection data.

## Baseline metadata

Every asset directory must include `baseline.json` recording:

- schema and generator versions;
- asset ID and display name;
- recipe version and integer seed;
- contract representation, role, authoring space and placement frame;
- surface and tile axes;
- semantic material ID;
- size and rangeCells;
- guide median and p99 scale;
- min/max relief in cell units;
- SHA-256 of the signed field and both PNGs;
- generator source SHA-256.

The root `manifest.json` must index all assets and hashes.

## Required validation

Run:

```text
python tools/asset-gen/surface_baselines_v2.py --runs 3 --verify
python -m unittest discover \
  -s tools/asset-gen/tests \
  -p "test_surface_baselines_v2.py" \
  -v
```

A baseline change passes only when:

```text
run 1 == run 2 == run 3
tracked files == regenerated files
declared seams are exact
contract vocabulary is valid
```

## Blender inspection

Use:

```text
blender --background --factory-startup \
  --python tools/asset-gen/blender/build_surface_v2_preview.py -- \
  --asset <asset_id> \
  --out-dir <temporary_directory>
```

The Blender script must regenerate the field and verify
`fieldQ15LeSha256` before building a mesh. `.blend` and rendered previews are
noncanonical and belong in temporary or explicitly reviewed derivative output.

## Production safety

Do not modify `assets/geometry/1_blender_depth_maps/` while working on V2.
Do not promote a Blender preview file into the V2 canonical directory.
Do not change runtime loaders in a surface-baseline task unless separately
scoped and reviewed.
