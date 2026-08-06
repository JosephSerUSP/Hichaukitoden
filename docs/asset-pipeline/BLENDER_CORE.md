# Shared Blender Asset Core

Phase 4 establishes `tools/blender/second_rite_asset_core.py` as the one
canonical low-level Blender infrastructure module. It owns scene reset and
datablock cleanup, collections, selection preservation, parent-local transforms,
materials, shading, modifiers, evaluated bounds, contract metadata, bmesh
object creation, and the item OBJ export mechanics. Item recipes and depth
preset recipes remain in their own pipelines.

## Canonical and vendored files

The canonical core is accompanied by the authoritative contract and semantic
material registry:

```text
tools/blender/second_rite_asset_core.py
tools/asset-language/contract.json
tools/asset-language/materials.json
```

The self-contained item toolkit contains byte-identical copies under
`tools/blender/second-rite-item-model-toolkit/vendor/`. Never edit those copies
independently. Synchronize and verify them with:

```text
python tools/blender/sync_asset_core.py
python tools/blender/sync_asset_core.py --check
```

The toolkit package includes the vendor directory. The generated library also
embeds the exporter, core, contract, materials, and toolkit readme as Blender
Text blocks so a copied `.blend` can still load its authoring infrastructure.

## Contract metadata

`tag_asset_target` writes validated `sr_` custom properties for version 1:
asset ID, representation, role, authoring space, placement frame, states,
default state, and variants. Item roots retain their legacy `item_*` export
properties and additionally declare `full_model` / `item_display` /
`item_viewport` metadata. Depth scenes declare `plane` / `surface_material` /
`depth_tile` / `surface_domain`, their surface and sampling view, and
`sr_depth_product=depth_guide`. Current depth output remains non-metric;
`sr_metric_depth_deferred=true` records that metric depth is not emitted in
this phase.

## Materials

`make_material` validates semantic IDs against the registry, uses registry
values only when a value was not explicitly supplied, and records
`sr_material_id` and `sr_material_registry_version`. Existing item material
colors, metallic/roughness, emission, and alpha values remain explicit
overrides, preserving the OBJ/MTL appearance contract. Defensible legacy
bindings are metadata; unbound legacy-derived and preview-only materials are
reported rather than guessed.

## OBJ and standalone behavior

The exporter keeps selected-geometry-only OBJ output, UVs, normals, material
groups, applied modifiers, triangulation, and Blender's `-Z` forward / `Y` up
axis settings. Root-pivot export duplicates a hierarchy temporarily, translates
the duplicate root to the origin, exports it, and restores authored transforms,
selection, and active-object state in a `finally` block. Shape-key variants
remain static OBJ outputs with their existing names.

The add-on first uses an importable canonical or vendored core, then a sibling
vendor copy when its own source file is available, then a stable module loaded
from the embedded `second_rite_asset_core.py` Text block. The fallback is safe
when the exporter is executed from a Blender Text block without `__file__`.
Contract and material Text blocks use the names `second_rite_contract.json` and
`second_rite_materials.json`. The smoke test executes the embedded exporter,
registers it, exports a marked root, and unregisters it again.

The core requires material registry version 1 to agree with
`contract.materialRegistry.version`. Canonical and vendor registries must also
agree before either can be used.

Depth sampling builds one evaluated BVH per mesh, orders objects by stable name,
selects the nearest world-space hit, and resolves effectively equal hits by
object name and polygon index. This preserves evaluated modifiers and booleans,
the existing viewer direction, pixel centres, and encoding while removing the
non-deterministic global `scene.ray_cast` traversal.

## Calibration and boundaries

Run the host driver for temporary-only smoke/build/calibration checks:

```text
python tools/blender/check_blender_core.py
```

It reports standalone 49-root/53-OBJ output, vendor-core origin, structural OBJ
equivalence, ordered `usemtl` equivalence, full MTL semantic equivalence, and
requires exact decoded-pixel equality for `wall_pilasters`, `floor_flagstones`,
`ceiling_coffers`, and `wall_boulders_rough`. A changed pixel fails the driver;
the installed Blender build currently cannot reproduce the tracked rough
fixture exactly, so that calibration remains a blocking finding. It never calls
a provider or writes production assets. Phase 4 intentionally does not migrate metric
depth, regenerate tracked assets, alter runtime loaders or data assignments,
author world props, add sockets/collision metadata, or change the unified
contract. Future world-prop builders should consume the core infrastructure,
then declare their own recipes and world-cell metadata explicitly.
