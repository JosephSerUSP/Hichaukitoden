---
name: second-rite-blender-modeling
description: >-
  Create procedural Blender models for Second Rite using Python, raw mesh data,
  bmesh, curves, controlled modifiers, shared metadata, and deterministic
  recipes. Use for props, fixtures, item models, openings, and inspection meshes.
license: Apache-2.0
metadata:
  upstream: "terminal-skills blender-3d-modeling 1.0.0"
  adapted_for: "JosephSerUSP/Second-Rite"
  version: "1.0.0-second-rite.1"
  category: design
  tags: ["blender", "3d-modeling", "procedural", "bmesh", "second-rite"]
---

# Second Rite Blender Modeling

This skill adapts the Apache-2.0 `blender-3d-modeling` terminal skill from
`Andrew1326/dominations/.claude/skills/blender-3d-modeling` to the Second Rite
asset contract and shared Blender core. Attribution details are in `NOTICE.md`.

## Read first

```text
docs/asset-pipeline/BLENDER_CORE.md
docs/asset-pipeline/SURFACE_BASELINES_V2.md
tools/asset-language/contract.json
tools/asset-language/materials.json
tools/blender/second_rite_asset_core.py
```

## Choose the correct authority

### Props, items, fixtures and openings

Blender geometry may be canonical:

```text
procedural recipe → Blender mesh → OBJ/MTL → runtime or item display
```

### Wall, floor and ceiling relief baselines

Blender is derivative only:

```text
fixed-point scalar field → canonical PNGs → Blender inspection mesh
```

Do not ray-cast a Blender surface back into a V2 canonical height map.

## Coordinate and scale rules

- Blender authoring is Z-up.
- World props use `world_cell`; one cell is 2.5 metres of design scale.
- Item displays use dimensionless `item_display` coordinates and viewport fit.
- Surface previews use the `depth_tile` XY domain and relief along +Z.
- OBJ export is `-Z` forward and `Y` up.
- Engine conversion remains `(x, y, z) → (x, -z, y)`.
- Put world roots at the contract placement frame, not an arbitrary visual centre.

## Prefer data APIs over repeated operators

For simple static meshes:

```python
mesh = bpy.data.meshes.new("Name")
mesh.from_pydata(vertices, edges, faces)
mesh.update()
obj = bpy.data.objects.new("Name", mesh)
bpy.context.collection.objects.link(obj)
```

For topology operations use `bmesh` and always release it:

```python
bm = bmesh.new()
# create or transform geometry
bm.to_mesh(mesh)
bm.free()
mesh.update()
```

Use `bpy.ops` only where direct data APIs are impractical. Before an operator,
set selection, active object and mode explicitly.

## Shared core

Do not reimplement scene, material, metadata, hierarchy, bounds or OBJ-export
infrastructure. Import:

```python
import second_rite_asset_core as asset_core
```

Use shared functions such as:

```text
reset_scene
ensure_collection
parent_local
make_material
assign_material
flat_shade
add_bevel_modifier
tag_asset_target
validate_asset_metadata
export_asset_root
```

## Deterministic modeling

- Use fixed seeds and repository-owned integer hashes.
- Keep recipe parameters explicit and serializable.
- Sort objects and generated elements before export.
- Avoid unseeded `random`, particle systems, simulation, remeshing and adaptive
  geometry when they determine production output.
- Apply modifiers only when the resulting topology is required and tested.
- Prefer low segment counts, deliberate faceting and readable silhouettes.
- Treat PSX-era inadequacy as art direction, not as malformed geometry.

## Second Rite modeling vocabulary

Build forms from understandable families:

- primitives and CSG for doors, chests, altars, machinery and frames;
- profile extrusion for arches, ironwork, mouldings and relief silhouettes;
- curves for cables, roots, handles and trim;
- radial construction for vessels, seals and ritual mechanisms;
- fixed scalar fields for rocks, masonry and terrain-like relief;
- alpha slices only when a volume is intentionally sprite-like.

Do not start with high-poly sculpting when a controlled low-poly recipe can
express the same object.

## Materials

Bind defensible semantic IDs from `materials.json`:

```text
old_limestone
rough_limestone
ritual_gold
oxidized_bronze
wrought_iron
dark_wood
aged_cloth
smoked_glass
wet_residue
bone
wax
crystal
```

Preserve explicit legacy numeric values when equivalence is required. Do not
invent a semantic binding merely to eliminate an unbound-material report.

## Metadata

Every production or inspection root must call `tag_asset_target` with valid:

```text
asset_id
representation
role
authoring_space
placement_frame
states
variants
```

Use `preview_only` only for assets that must never be promoted. Surface preview
meshes remain `surface_material` but must record `sr_preview_only=true` and the
canonical field hash.

## Export and validation

- Duplicate authored hierarchies before origin-centering export.
- Never move the authored root as a side effect.
- Restore selection and active object in `finally`.
- Export only intended geometry.
- Validate OBJ counts, bounds, `usemtl`, `mtllib`, and parsed MTL semantics.
- Write builds and previews to temporary output unless production promotion is
  explicitly requested.

Run Blender scripts headlessly:

```text
blender --background --factory-startup --python <script.py> -- <arguments>
```

Print one machine-readable JSON result line for automation.
