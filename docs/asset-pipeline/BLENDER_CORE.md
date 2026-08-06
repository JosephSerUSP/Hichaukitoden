# Shared Blender Asset Core

Phase 4 establishes `tools/blender/second_rite_asset_core.py` as the canonical
low-level Blender infrastructure module for scene cleanup, collections,
selection preservation, local transforms, materials, modifiers, metadata,
bmesh objects, bounds, and OBJ export.

The item-model pipeline continues to use Blender as an authoring and export
authority. Surface baselines do not: their canonical numeric field is generated
before Blender and Blender receives it only as an inspection derivative.

## Canonical and vendored core

```text
tools/blender/second_rite_asset_core.py
tools/asset-language/contract.json
tools/asset-language/materials.json
```

The standalone item toolkit vendors byte-identical copies under:

```text
tools/blender/second-rite-item-model-toolkit/vendor/
```

Synchronize and check them with:

```text
python tools/blender/sync_asset_core.py
python tools/blender/sync_asset_core.py --check
```

Generated item-library `.blend` files embed the exporter, shared core, contract,
material registry, and toolkit readme as Text blocks.

## Item-model guarantees

The shared exporter preserves:

- selected geometry only;
- UVs and normals;
- material groups and MTL output;
- applied modifiers and triangulation;
- Blender `-Z` forward and `Y` up OBJ axes;
- authored root transforms;
- selection and active-object state;
- temporary collection cleanup;
- static shape-key variants.

The Phase 4 item checks continue to require 49 marked roots, 53 OBJ outputs,
structural OBJ equivalence, ordered `usemtl` equivalence, parsed MTL semantic
equivalence, vendor synchronization, and no provider or production writes.

## Surface baseline authority

The legacy depth pipeline sampled evaluated Blender geometry with first-hit ray
casts. Repeated Blender 5.1.2 diagnostics proved that
`wall_boulders_rough` was not pixel-repeatable on one machine. That experiment
is retained as evidence but no longer defines the future surface contract.

The V2 authority is:

```text
tools/asset-gen/surface_baselines_v2.py
assets/geometry/2_procedural_surface_baselines/
```

Canonical V2 outputs are fixed-point scalar fields serialized as
`height_metric.png` and `depth_guide.png`. Blender creates preview meshes and
renders only after checking the recorded field hash. It never ray-casts the
preview back into canonical pixels.

See `docs/asset-pipeline/SURFACE_BASELINES_V2.md` for recipes, encodings,
commands, assets, and validation gates.

## Project modeling skills

Claude/Luna guidance is installed at:

```text
.claude/skills/second-rite-blender-modeling/SKILL.md
.claude/skills/second-rite-surface-baselines/SKILL.md
```

The Blender skill is adapted from the Apache-2.0 `blender-3d-modeling` terminal
skill and adds Second Rite coordinate, metadata, determinism, low-poly, preview,
and production-safety rules.

## Legacy diagnostic status

The following remain historical diagnostics rather than V2 acceptance gates:

```text
assets/geometry/1_blender_depth_maps/
tools/blender/depth_baseline.py
```

They must not overwrite or become hidden inputs to the V2 baseline set.
