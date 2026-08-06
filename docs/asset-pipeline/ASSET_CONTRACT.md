# Unified Asset Contract

## Status and version

This is the Phase 2 authoring contract. `contractVersion` is the integer `1`. Additive vocabulary additions may retain version 1; a breaking reinterpretation increments it. Contract versioning is independent of tool versions. Existing assets without the field are legacy assets, not invalid, and no production asset must adopt version 1 in this phase.

## Scale and authoring spaces

The canonical design scale is `CELL_METRES = 2.5`.

| Space | Normative meaning | Uses |
|---|---|---|
| `world_cell` | 1 engine map-cell unit = 2.5m design scale; +X east, +Y south, +Z up | dungeon props, fixtures, openings, event props, world models |
| `item_display` | dimensionless local coordinates; viewport auto-fits bounds; no metre or world guarantee | inventory and inspection models |
| `depth_tile` | XY [0,1]×[0,1] is one 2.5m×2.5m surface cell; Z is signed relief in cell units | Blender depth and tile-periodic relief |
| `preview` | presentation-only coordinates with no gameplay, collision, metre, or placement authority | reports, contact sheets, turntables, inspection layouts |

These spaces are never interchangeable. Adapters may convert them later; no implicit conversion exists. Positive `depth_tile` relief points toward traversable/visible space: wall outward, floor upward, ceiling downward.

## Coordinate-system and interchange chain

Blender procedural model authoring is Z-up. Blender local coordinates remain distinct from engine world coordinates. Item-toolkit roots define exported pivots and children remain root-local.

The existing OBJ exporter requests forward axis `-Z` and up axis `Y`; the resulting OBJ interchange representation is Y-up. OBJ is an interchange coordinate system, not the engine coordinate system. The current loader converts `OBJ (x, y, z) -> engine (x, -z, y)`, and the engine representation is Z-up.

After conversion, world full-model coordinates use `world_cell`: +X is east/increasing map X, +Y is south/increasing map Y, and +Z is up. Model coordinates are added directly to cell-relative placement origins; no implicit model-scale multiplier exists. `item_display` models pass through the same OBJ conversion, after which item presentation auto-fits model bounds. Viewport fitting does not create a metre or world-scale contract.

No tool may treat Blender, OBJ, engine, `world_cell`, or `item_display` coordinates as interchangeable without an explicit adapter.

## Representations and roles

Version 1 representations are exactly `plane`, `shell`, `radial`, and `full_model`. They describe visible geometry and remain orthogonal to roles.

Version 1 roles are exactly `surface_material`, `surface_fixture`, `object_fixture`, `item_display`, `structural_opening`, `event_prop`, `overlay`, and `preview_only`. Current runtime roles `surfaceFixture` and `objectFixture` remain unchanged; adapters map the unified roles later. Collision is separate metadata, never inferred from geometry.

`plane` covers displaced surface fields; `shell` covers image-derived closed objects; `radial` covers rotational profiles; `full_model` covers explicit OBJ/MTL polygon geometry. Examples: shrine recess = `plane + surface_fixture`, pedestal = `radial + object_fixture`, reliquary = `full_model + event_prop`, inventory sword = `full_model + item_display`.

## Placement frames and pivots

Frames are `floor_center`, `wall_center`, `ceiling_center`, `opening_center`, `item_viewport`, `surface_domain`, and `preview_frame`. Floor origins are owning-cell centres with +Z up and contact plane Z=0. Wall origins are visible-face centres with +X outward, +Y tangent, +Z up, matching `viewport_3d.wallModelFrame`. Ceiling origins are ceiling-cell centres; hanging geometry normally extends negative Z. Opening origins are floor-level opening centres and do not define passability. Item viewport uses the exported root origin and bounds fitting. Surface domain is the depth-tile XY domain. Preview frame has no runtime authority.

Every future version-1 record declares one frame. Full models preserve an authoritative root origin and root-local children. Bounds-centre export requires an explicit declaration. Collision is never inferred from bounds.

## Naming, states, variants, and sockets

Fields use lowerCamelCase. Stable IDs and filenames use ASCII lower_snake_case: lowercase initial letter, then lowercase letters, digits, and underscores. Paths are repository-relative with `/`; absolute machine paths and spaces are forbidden. Display names are separate and may change without changing IDs.

States are semantic conditions, with reserved IDs `default`, `inactive`, `active`, `closed`, `open`, `sealed`, `unsealed`, `locked`, `unlocked`, `intact`, `damaged`, `broken`, `empty`, `filled`, and `spent`. `defaultState` is the authoritative fallback and must appear in `states`. The reserved ID `default` is available when no more meaningful semantic fallback exists; it is not mandatory when another explicit semantic state such as `inactive` is selected. Variants are parallel visual alternatives; state and variant namespaces are distinct, and provider candidate indices are not authored states.

Socket kinds are `interaction`, `actor`, `camera_focus`, `vfx`, `loot`, `hinge`, `light`, `audio`, and `attachment`. A socket has `id`, `kind`, and root-local `position`, with optional `rotationDegrees`, normalized `forward`/`up`, `state`, and `metadata`. Socket metadata alone creates no gameplay; runtime support is deferred and Blender objects are not automatically authoritative.

## Depth products

`height_metric.png` is geometric truth: 16-bit grayscale, neutral 32768, and an explicit per-asset or per-preset `rangeCells`, with `0=-rangeCells`, neutral `0`, and `65535=+rangeCells`. The current Blender-depth family uses `defaultRangeCells = 0.25`; this is not a universal immutable range. Encode `round(32768 + clamp(reliefCells / rangeCells, -1, 1) * 32767)` and decode `((encoded - 32768) / 32767) * rangeCells`. It has no median, percentile, or per-image normalization; clipping is reported and seam checks use raw/decoded metric relief.

`depth_guide.png` is separate 8-bit-compatible generation guidance: neutral 128, usable contrast ±112, made by median subtraction, p99 absolute-deviation normalization, and clipping to [0,255]. It is non-metric and never decoded as displacement. ControlNet receives the guide unless a future adapter explicitly converts another product.

Existing `height.png` remains the legacy ambiguous runtime product. Phase 2 does not rename or regenerate it, and no pipeline may silently alias guide depth to metric height. Later phases decide whether runtime consumes metric height directly or a deterministic compatibility derivative.

## Materials

`tools/asset-language/materials.json` is a semantic registry, not a PBR runtime promise. It contains the twelve version-1 IDs and restrained color, metallic, roughness, opacity, generation-tag, and legacy MTL hints. Existing MTL names are not renamed and no texture files are introduced.

## Future asset record

The normative future record contains `contractVersion`, `id`, `displayName`, `representation`, `role`, `authoringSpace`, `placementFrame`, `materials`, `states`, `defaultState`, `variants`, `sockets`, `sources`, `products`, and `provenance`. `materials` contains registered IDs; `defaultState` must be in `states`; sources are authoring references (`blenderScript`, `blendInspection`, `sourceImages`, `prompt`, `referenceImages`, `metadataSource`), while products may include `model`, `materialLibrary`, `albedo`, `heightMetric`, `depthGuide`, `legacyHeight`, `runtimeMetadata`, `preview`, `report`, and `manifest`. Provenance records `generator`, `generatorVersion`, `sourceCommit`, `command`, `inputs`, and `outputs`; all paths are relative and timestamps are not identity requirements.

Documentation-only example — not a production asset:

```json
{"contractVersion":1,"id":"example_shrine_recess","displayName":"Example Shrine Recess","representation":"plane","role":"surface_fixture","authoringSpace":"depth_tile","placementFrame":"surface_domain","materials":["old_limestone","ritual_gold"],"states":["inactive","active"],"defaultState":"inactive","variants":[],"sockets":[],"sources":{"metadataSource":"docs/asset-pipeline/ASSET_CONTRACT.md"},"products":{},"provenance":{"generator":"documentation","generatorVersion":"1","sourceCommit":"documentation-only","command":"none","inputs":[],"outputs":[]}}
```

## Preview and validation expectations

Plane previews show source albedo, metric false-colour/profile, guide, a 3× repeat on declared seams, and an in-engine or representative surface. Shell previews show front/rear, mask/silhouette, wireframe, turntable, and state comparison. Radial previews show front/profile, top, wireframe, turntable, and angular seam. World full models show front/side/top, pivot, one-cell reference, cell-unit bounds, material groups, states, and sockets. Item displays show turntable, auto-fit, bounds, and state/variant sheets. Preview-only evidence is visibly non-production. No preview generator is implemented here.

Future validation covers identity, vocabulary, representation/role compatibility, frame/space compatibility, world bounds and contact planes, strict OBJ/MTL parsing, metric-vs-guide depth products, clipping and seams, topology-specific checks, states/sockets, and distinguishable staged versus production provenance. Unsupported OBJ directives fail; default and socket IDs must be valid and unique; vectors must be finite and normalized where required.

## Compatibility and non-goals

Existing assets, `asset.json`, `data/engine.json`, `data/items.json`, `data/tilesets.json`, OBJ/MTL, `height.png`, depth presets, and runtime behavior remain unchanged. No production asset is regenerated. Runtime does not read `contract.json` or `materials.json`; no PBR shader, collision system, runtime sockets, automatic item reclassification, or paid provider call is introduced.

Future adapters are planned but not implemented: item toolkit → full_model/item_display; world prop builder → full_model/world role; Blender depth → height_metric + depth_guide; runtime geometry → representation/role; staging → provenance-aware albedo; atlas assembly → provenance-aware paired products.
