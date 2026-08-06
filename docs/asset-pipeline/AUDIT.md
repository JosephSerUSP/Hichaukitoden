# Phase 1 — Existing Asset Pipeline Audit

## 1. Audit Method and Scope

Branch: `feat/unified-asset-pipeline`. Starting commit: `d290e96320bf2514ab30d51e193710d9752fa5b6`.

Inspected source and generated state included `AGENTS.md`, `docs/asset-pipeline/BASELINE.md`, `tools/blender/second-rite-item-model-toolkit/{README.md,TOOLCHAIN_CONTEXT.md,build_expanded_item_library.py,second_rite_item_exporter.py,scripts/build_library_windows.ps1}`, `tools/asset-gen/{gen.py,classes.json,config.json,authorgeom.py,blendergeom.py,blender/{render_depth.py,scenes.py},lib/*.py,assemble_atlas.py,README.md}`, `engine/geometry/*.lua`, `presentation/{item_model_view.lua,viewport_3d.lua,mesh.lua}`, item data/tests, `data/engine.json`, representative `assets/geometry/**`, and the baseline manifests/summaries.

Navigation and verification commands: `git status --short --branch`, `git rev-parse HEAD`, `rg --files`, `rg -n`, PowerShell `Get-Content`, and the validation commands recorded in the baseline. No Blender generation, provider call, editor save, asset promotion, schema change, or production-source edit was performed.

**FACT** means directly established by code, data, tests, or command output. **INFERENCE** means a conclusion supported by evidence but not directly declared. **UNKNOWN** means the repository/environment does not establish it safely. Facts and inferences are separated where ambiguity matters.

## 2. Artifact Authority Matrix

| Artifact | Producer | Source of truth? | Tracked/generated | Consumers | Safe to edit manually? | Rebuild command/path |
|---|---|---|---|---|---|---|
| Blender Python recipes | `build_expanded_item_library.py` | FACT: yes | tracked source | Blender build | yes, as source | `scripts/build_library_windows.ps1` |
| exporter | `second_rite_item_exporter.py` | FACT: yes | tracked source; embedded copy also generated | Blender OBJ export | source only | same build script |
| inspection `.blend` | Blender build | no; inspection copy | generated/tracked in some bundles | human inspection | no; overwritten | item build or `blendergeom.py` |
| OBJ/MTL | `second_rite_item_exporter.py` | runtime OBJ/MTL is authoritative input | generated/tracked | `presentation/item_model_view.lua`, `presentation/viewport_3d.lua`, `presentation/obj_model.lua`, `presentation/mesh.lua` | no | item build or prop-specific build |
| item manifest/preview | builder | no; report | generated | human/tooling | no | item build |
| Blender depth PNG | `render_depth.py` | generated from `scenes.py` | tracked production input | `gen.py --height`, geometry authoring | no | `python tools/asset-gen/blendergeom.py` |
| depth manifest | `blendergeom.py` | generated index | tracked | tooling/documentation | no | same |
| item-view OBJ use | `data/items.json` model path | assignment is data authority | tracked data + generated OBJ | item view | edit data intentionally | item build |
| dungeon/world OBJ use | `data/tilesets.json` feature `model` | tileset feature is placement authority | tracked data + generated OBJ | viewport world renderer | edit data intentionally | prop-specific build |
| `albedo.png` | authoring or generation/promotion | albedo only | tracked production asset or staged candidate | geometry compiler/atlas | no | authoring or `gen.py promote` |
| `height.png` + `asset.json` | geometry author | together with metadata are runtime geometry authority | tracked production asset | geometry compiler | no | authoring/atlas/depth path |
| shell masks/front-back maps | authored image + `asset.json` layout | image pixels plus metadata | tracked | `shell.checkMasks`, shell builder | no | authoring pipeline |
| `asset.json` | author | FACT: schema authority for asset instance | tracked | `engine/geometry/schema.lua` | only as intentional authoring | manual/editor |
| runtime mesh | `geometry.load` and topology builders | no; cache product | in-memory generated | world renderer/GPU | no | first load |
| run manifest | `lib/staging.py`/`gen.py` | run record | generated staging | `runs`, reprocess, promote, reports | no | `gen.py generate` |
| raw provider output | provider response | no; immutable evidence | staging | postprocess/reprocess | no | provider command |
| processed variants | `postprocess.py` | candidate output | staging | ranking/promotion/report | no | generate/reprocess |
| contact sheet/report | report/postprocess | no | staging | human review/context preview | no | report command / `_finish` |
| context preview | real engine preview path | no | temporary/staging | human review | no | class context preview command |
| promoted runtime asset | `staging.promote` | production file after owner approval | tracked production | engine | no | `gen.py promote` |
| atlas image | `assemble_atlas.py` | assembled output, not source pieces | tracked/generated | runtime atlas consumer | no | atlas command |
| atlas companion metadata | `assemble_atlas.py` emits no machine-readable companion manifest | no | HTML report only | no | SYSTEM-SPECIFIC — KEEP SEPARATE | code inspection |

Generated inspection files are not source scripts; staging files are temporary candidates; runtime meshes are recreated and not persisted.

## 3. Blender Item-Model Pipeline

Path: `build_expanded_item_library.py` recipe functions (`create_root`, `parent_local`, `add_cube`, `add_cylinder`, `add_prism`, `add_sword`, and family builders) create a scene and root objects. `create_root` assigns `item_export=true`, `item_export_name`, display/category/description properties. Children are parented with local transforms. The gallery location is root placement; authored geometry remains root-local.

`second_rite_item_exporter.py` finds marked top-level roots, duplicates each hierarchy, applies root-pivot export semantics, converts shape-key variants to static meshes, triangulates/normalizes the export copy as required, and writes one OBJ plus MTL per output name. The filename is the root `item_export_name` (family suffixes identify static variants). The builder asserts 49 roots and 53 OBJ outputs. `build_library_windows.ps1` supplies Blender and output paths; the generated `.blend`, preview and manifest are inspection/report outputs.

Runtime assignment is explicit `model` paths in `data/items.json`; `loader.getItem` supplies the path to `presentation/item_model_view.lua`, whose `resolveModel`/`draw` calls `presentation/obj_model.lua:load`. `presentation/obj_model.lua` parses positions, UVs, normals, polygon fans, positive/negative indices, `mtllib`, `usemtl`, MTL `Kd` and `map_Kd`, refuses unsupported directives, caches by path, and converts OBJ coordinates. `presentation/mesh.lua` owns the shared model/group representation, builders, material binding, textures and bounds used by both OBJ models and image-authored geometry. Tests `tests/test_item_model_assignments.lua`, `tests/test_item_model_view.lua`, and `tests/test_item_display.lua` protect assignment, missing/fallback behavior, fit, and drawing.

### Coordinate chain

The Blender procedural scene is Z-up. The exporter requests forward axis `-Z` and up axis `Y`, so the written OBJ is Y-up. `presentation/obj_model.lua:objToWorld` converts `OBJ (x,y,z) -> engine (x,-z,y)`. The engine model representation is Z-up; item-view presentation then auto-fits model bounds to its viewport. These are separate Blender, interchange, and engine coordinate systems.

### World OBJ and Dungeon-Prop Pipeline

`data/tilesets.json` feature variants declare models such as `wall_torch` (`assets/models/dungeon/dungeon_torch_bracket.obj`, `emitsLight`), `dungeon_column` (floor feature, `blocksMovement`), `dungeon_chest` (blocking floor feature), and `ruins_crystal` (floor feature, `emitsLight`). `engine/tileset_resolver.lua:resolve` resolves the tileset variant. `presentation/viewport_3d.lua:meshSource` selects `obj:<path>`; wall/floor/ceiling/opening placement builds placements, and `ensurePlacedModel` loads `presentation.obj_model.load`, consumes the shared `presentation.mesh` groups, and creates world-space GPU meshes. The renderer adds local coordinates directly: `worldX = originX + localX`, `worldY = originY + localY`, `worldZ = localZ`; there is no model-scale multiplier. Thus one model unit is one map-cell coordinate unit in this path, and vertical 0..1 occupies one cell. This is distinct from item-view fitting and from the separate 2.5-metre authoring interpretation.

Wall local frames are +X outward, +Y tangent, +Z up; `viewport_3d.wallModelFrame` maps this frame to all visible wall directions. Floor features use the current floor-feature placement around the selected cell and retain local Z as world height. Ceiling and opening placement is driven by the corresponding `ensurePlacedModel` call sites and axis/origin arguments; the code does not establish a broader universal convention. Item-toolkit OBJ files are technically loadable here, but suitability depends on bounds, pivot, orientation, and intended dimensions; no automatic item-to-world assignment exists. Relevant protection includes viewport/model tests and the resolver/geometry tests; no evidence supports treating item toolkit models as dungeon props.

Arrow contract: recipe functions → Blender scene objects (input: dimensions/materials; output: child meshes); marked roots → duplicate export hierarchy (input: custom properties; output: isolated root); shape keys → static variant objects (input: keyed mesh; output: one mesh per named state); export → OBJ/MTL (input: root-local geometry and simple diffuse materials; output: files); item data → path assignment (input: item id; output: filename); loader → GPU mesh (input: OBJ/MTL; output: LÖVE mesh/material groups); item view → fit/draw (input: bounds and viewport; output: displayed model).

**FACT:** coordinates are Blender/LÖVE object coordinates with Y depth and Z up in the authoring helpers; the exporter recentres around the root pivot. The toolkit documents one Blender unit as the toolkit’s item authoring unit, but no repository contract establishes a real-world metre equivalence. Therefore item models are display-scale authored assets, not proven world-scale assets. Final display fit/scale is applied in `presentation/item_model_view.lua` (`calculateFit`/`draw`), not in item data. Pivot convention is root origin; children remain root-local.

The runtime consumes OBJ positions, faces, UVs, `mtllib`/`usemtl`, and MTL diffuse material groups/colors used by the loader. Principled shader graphs and non-exported Blender properties are discarded by the OBJ/MTL interchange. **INFERENCE:** these models are not directly world props without a separate world placement/scale/collision contract; no such assignment was found. Item IDs associate indirectly through `data/items.json`, not through OBJ contents. Export assumptions specific to item display include one marked root per item, origin-centred/root-pivot output, simple diffuse groups, and static variants.

Invariants: 49 marked roots; 53 named outputs; marked root metadata; root-local children; root-origin export; OBJ/MTL-compatible diffuse groups; explicit item-path assignment; no inference that a display model is world-scale or collision-ready.

## 4. Blender Depth-Map Pipeline

`tools/asset-gen/blender/scenes.py` is the preset authority. `blendergeom.py` selects presets, discovers Blender through `BLENDER`, fixed Windows paths, then `blender`, and launches `--background --factory-startup --python render_depth.py`. Every preset builds relief over a unit XY tile; `render_depth.py:sample` casts rays along Blender Z. `view="above"` places the viewer above the XY surface and casts toward `-Z`; `view="below"` places it below and casts toward `+Z`. Walls and floors use `above`; ceilings use `below` because the visible corridor face is the underside. A wall preset is not physically vertical in this scene: it is a 2-D wall parameter domain over XY, with Z carrying relief. Wall X is horizontal repetition and wall Y is vertical composition, so only X wraps; floors and ceilings wrap XY. `CELL_METRES = 2.5` is the documented physical cell scale used when converting tile-relative geometry to metre-sized room/cell dimensions; Blender object coordinates and generated map values remain distinct.

Wall, floor, and ceiling samples are therefore all Z-directed XY relief samples, with `view` recording the side of the XY domain from which the viewer-relative ray arrives. `view="above"` is a physical sampling direction in the Blender depth scene, not unexplained legacy vocabulary.

`sample()` returns raw viewer-relative relief against `scenes.BASE_Z`; positive raw relief points toward the viewer. Manifest `reliefMin`/`reliefMax` describe that raw field. `write_height()` subtracts the median, divides by the 99th percentile of absolute deviation, and maps the normalized result around 128 with ±112 contrast. Thus 128 is the dominant/median surface, not necessarily `BASE_Z`, and the PNG is not metric-height encoding. The PNG is both ControlNet depth conditioning (`gen.py --height`) and an authored runtime geometry input when registered in `assets/geometry/**`; runtime displacement magnitude is supplied by geometry metadata (`heightScale`/`depthScale`).

Wall tiles on `x`; floor/ceiling on `xy`. Periodic solids are duplicated across relevant tile boundaries; boolean cutters are likewise duplicated so subtraction remains continuous. Wrap acceptance is `ratio <= 3.0 OR step <= 0.03` per axis; either criterion can pass by design. Selective `--preset` renders only requested presets, merges existing valid records, replaces matching records, and writes the merged manifest so omitted maps are not lost. `.blend` files beside PNGs are inspection copies rebuilt wholesale; the PNG and manifest are the production inputs. Phase 0 measured four representatives and recorded all `wrapOk`; those measurements are retained in `docs/asset-pipeline/baseline/blender-depth-summary.json` and were not rerun.

Current ambiguity: physical height, normalized depth, ControlNet guidance depth, and runtime displacement share a PNG but have different scales. The exact cross-pipeline contract remains a Phase 2 decision, not an unknown about current sampling semantics.

Protection is via `blendergeom.py` wrap checking and the documented commands; no dedicated depth unit suite was found.

## 5. Image-Authored Runtime Geometry

The live roles are registered in `data/engine.json` and parsed by `engine/geometry/schema.lua`: `surfaceFixture` and `objectFixture`. Representation (`plane`, `shell`, `radial`) and gameplay role are separate fields in current data, although `blocksMovement` is legal only for `objectFixture`. `surfaceFixture` layers onto a matching base surface; `objectFixture` is standalone and may block movement.

All assets require `asset.json`, `albedo.png`, and `height.png`. `geometry.check` validates metadata/pixels; `geometry.load` parses, validates, composes, samples, builds, decimates where applicable, uploads, and caches by compiler/quality/path plus file modification metadata. Meshes are in-memory and recreated after restart/invalidating changes.

### Plane

Plane uses surface wall/floor/ceiling, `heightOperation` (`add`, `replace`, `none`), heightScale in cell-relative displacement, mesh/sample columns and rows, triangle budget, and offset. `plane.sampleField` composes layers in order: add accumulates, replace substitutes, none contributes no height. Shared atlas height surfaces require matching dimensions and registration; periodic sampling wraps image coordinates. Wall skirts close the displaced face back to the structural plane and prevent edge gaps/holes. UVs follow the image; material groups are built from albedo and metadata id. Wall bounds reject displacement below half a cell. Runtime placement is surface-specific; collision remains structural/metadata-driven rather than derived from a render mesh.

### Shell

Shell requires `surfaceMode`, `layout`, edge mode/color, depthScale, mesh/sample density, and optional front/back albedo/layout, mask matching, symmetry (`imageX`, `imageY`, `frontBack`), and pinch width. Front/back layouts represent two faces in one atlas; masks are checked for coverage, matching components, and valid layout. Stitch joins rims; pinch controls the narrow side transition; symmetry mirrors image coordinates/front-back depth; edge mode controls rim treatment. Shell builds dense front/back surfaces and a stitched rim, then decimates under the triangle budget. Invalid front/back-with-single-layout, mismatched masks, and disconnected/empty masks fail loudly. It is an object representation, not a generic walkable surface.

### Radial

Radial requires baseRadius, height, `heightScale` (radius scale), angular/vertical segments, optional caps, signed radius, and angular symmetry. Height samples around a closed angular seam and along height; 128 is neutral for signed radius, while unsigned values add. The seam closes by using modulo angular positions and a final `u=1` sample; top/bottom caps are optional triangle fans with opposite winding. Degenerate triangles from intentional zero-radius pinches are skipped. Radius plus scale is bounded to half a cell. No decimation pass exists; authored segment counts are facets.

### Surface-fixture composition

`viewport_3d.composedWallSpec` composes a base image-authored wall and its surface fixture into one ordered geometry surface. When the base is an ordinary atlas wall, a geometry fixture may remain a separate placed mesh over that wall. Composition order matters because height operations are not commutative. `coversFace` suppresses the atlas wall only when a geometry surface replaces the full face; it does not mean every surface fixture is always merged.

Current schema summary:

| Field | Plane | Shell | Radial |
|---|---|---|---|
| required images | albedo/height | albedo/height | albedo/height |
| identity | id, topology, role | id, topology, role | id, topology, role |
| geometry controls | surface, operation, heightScale, grids, budget, offset | mode/layout/edge, depthScale, grids, budget | radius, height, radiusScale, angular/vertical segments, caps |
| role restriction | fixture composition by surface | standalone object use | standalone object use |
| units | cell-relative | cell-relative depth | cell-relative radius/height |

Existing demonstrations include `assets/geometry/sd_ffxii_*`, `fluted_pillar`, `shrine_recess`, `sacred_idol`, `muse`, and tests under `tests/fixtures/geometry/{valid_plane,valid_shell,valid_radial,...}`. `tests/test_geometry.lua` directly loads/compiles plane, shell, radial; it also protects composition, masks, sampling, bounds, seams, and decimation. No generated runtime mesh is persisted.

## 6. Image and Albedo Generation Pipeline

`classes.json` declares class identity, prompt files/tags, geometry/size/frame/output conventions, tile axes, post-processing and context-preview data. `lib/classes.py` resolves class context; prompt style and provider details remain in Python/config. `config.json` declares providers, models, prices, local status, ControlNet depth model/weight, and sampling defaults. CLI overrides include provider/model/quality, seed, sampler, steps, CFG, LoRA/sampling and tiling where supported.

`gen.py` resolves class → prompt → provider. `--dry-run` resolves and prints effective configuration/cost without requesting or staging an image. A real request writes `raw-N.png`, processed variant(s), quality/seam metrics, and a manifest containing class/name, effective context/parameters, variants, promotion state and paths. `cmd_runs` requires `class`, `name`, and `variants`; the three `depth-height-patterns*/manifest.json` files are pattern manifests without those fields, created by `make_height_patterns.py` and located under the same staging root. **FACT:** `gen.py runs` currently fails on them; this is both a schema collision and a directory-boundary problem. It is intentionally not fixed here.

Post-processing distinguishes raw provider bytes from processed files; contact sheets are built in `_finish` through `postprocess.contact_sheet`. Seam axes come from class context. Walls generally join left/right only (`x`); floor/ceiling can tile `xy`. Seam scores measure edge differences; relocated centre seams are separately evaluated by the seam-repair/scoring functions. Variants rank by worst seam score, with raw-quality information retained. Local repair uses offset/inpaint through the local provider path. Manual edits are protected by promotion checks: ordinary promotion refuses dirty destination changes; `--force` bypasses selection/quality safeguards as documented, while `--force-dirty` permits overwriting a destination with local edits. Exact flag semantics are implemented in `lib/staging.py`; no production promotion was run.

Promotion behavior is exact and guarded. `gen.py:cmd_promote` requires an explicit/default variant, resolves class/manifest destination, and copies the selected processed image. Existing destinations require `--force`; an existing destination with uncommitted edits additionally requires `--force-dirty`. `--force-dirty` alone does not permit overwrite. Manual promotion has no automatic seam threshold: it copies the explicitly selected variant. `_auto_promote` considers scored variants, refuses unmeasurable candidates and scores above `SEAM_GOOD`, then calls lower-level promotion with overwrite enabled; dirty overwrite requires `--force-dirty`.

`_control_from_height` records the repository-relative guide in `manifest.provider.heightControl` and weight in `manifest.provider.heightControlWeight`; these remain in the staged manifest. `staging.promote` copies only the chosen processed variant: not the guide, metric field, `asset.json`, or provenance sidecar. For `{name}/albedo.png`, only the albedo destination is created/updated; a runtime geometry directory separately needs compatible `height.png` and `asset.json`. Staged provenance is present; production-side provenance is absent unless retained manually, and automatic albedo/height identity enforcement during promotion is absent. `assemble_atlas.py` supports albedo `--out`, optional height `--height-out`, independent `--cell` and `--height-cell` ROW,COLUMN mappings, optional base albedo and base height atlases, exact cell-dimension validation, and an HTML report containing human-readable source paths. It emits no machine-readable companion manifest; the HTML is evidence, not runtime provenance. Albedo and height mappings are independent, so the script does not prove cell pairing. It explicitly never promotes into `assets/`, though a caller can choose an output path. Real-engine context previews invoke the engine preview path; reports use generated contact sheets/metrics.

Manual promotion has no automatic seam threshold: it copies the explicitly selected variant. Existing destinations require `--force`; dirty overwrites additionally require `--force-dirty`. Auto-promotion alone applies the `SEAM_GOOD` threshold and selects among scored variants.

Local Forge differs at provider request and repair: `forge.py` talks to a locally running Forge/SD server, with no paid API; it still enters the same staging/postprocess/manifest path. Paid calls are possible for configured remote providers only.

Command safety:

| Command | Reads | Writes | Paid call possible? | Production assets modified? |
|---|---|---|---|---|
| `gen.py classes` | classes/config | none | no | no |
| `gen.py models` | config/pricing | none | no | no |
| `gen.py runs` | `out/*/manifest.json` | none | no | no; currently fails on pattern manifests |
| `generate --dry-run` | class/config/prompts | none | no | no |
| normal `generate` | class/config/provider | staging run | yes | no |
| `reprocess` | staged raw files | staged variants/manifest | no | no |
| `promote` | staged run/destination | production destination | no | yes, guarded |
| report/context preview | staged data/engine | report or temporary preview | no | no |
| atlas assembly | selected inputs | atlas output | no | only if destination is production |
| Blender depth | scenes/Blender | PNG/manifest, optional inspection `.blend` | no | yes if pointed at production path |
| local Forge | config/local server | staged raw/variants | no | no |

## 7. Four End-to-End Pipeline Diagrams

1. `tools/blender/second-rite-item-model-toolkit/build_expanded_item_library.py:create_root` → Blender child objects via `parent_local` → marked roots (`item_export`) → `second_rite_item_exporter.py` duplicate/shape-key static conversion → `assets/models/items/*.obj` + `.mtl` → `data/items.json:model` → `presentation/item_model_view.lua` → `presentation/obj_model.lua:load` → `presentation/mesh.lua` model groups → item viewport auto-fit/draw.

2. `tools/asset-gen/blender/scenes.py` preset → `render_depth.py:sample` evaluated XY relief → `write_height` normalized PNG → `blendergeom.py` manifest → `gen.py:_control_from_height` ControlNet conditioning → processed candidate → `staging.promote` albedo destination only; separately existing `height.png` + `asset.json` → `engine/geometry/schema.lua`/plane/shell/radial compiler.

3. `assets/geometry/<name>/{asset.json,albedo.png,height.png}` → `schema.parse` → `images.data` and topology sampling → dense plane/shell mesh or radial facets → `decimate.run` where plane/shell applies → `presentation.mesh` GPU mesh/material groups → world renderer placement.

4. `classes.json` + `classes.py` → prompt construction in `gen.py` → provider module / `forge.py` → `raw-N.png` → `postprocess.py` → seam scoring/repair → staged variant + `lib/staging.py` manifest → report/contact sheet/context preview → guarded `promote` → resolved runtime destination (including geometry albedo path).

5. **World OBJ prop:** `data/tilesets.json:model` → `engine/tileset_resolver.lua:resolve` → `viewport_3d.meshSource` → `viewport_3d.ensurePlacedModel` → `presentation.obj_model.load` → `presentation.mesh` model groups → cell-relative world placement → world GPU mesh.

## 8. Duplication and Shared-Concept Matrix

| Concept | Item toolkit | Depth pipeline | Other implementation | Same semantics? | Classification | Evidence |
|---|---|---|---|---|---|---|
| Blender discovery | wrapper/build | `blender_executable` search | none | no | SYSTEM-SPECIFIC — KEEP SEPARATE | different launch contracts |
| scene clearing | builder | scene helpers | none | unknown | INSUFFICIENT EVIDENCE | helper bodies differ |
| OBJ loading | exporter output | no | `presentation.obj_model.lua` shared by item/world | yes | SAFE TO CENTRALIZE | one parser/cache path |
| collection/material/flat shading | item builders | depth scenes | runtime materials | no | CENTRALIZE ONLY THROUGH ADAPTERS | different output roles |
| primitive/bevel construction | item-specific helpers | preset geometry | geometry compilers | no | SYSTEM-SPECIFIC — KEEP SEPARATE | semantics differ |
| root/metadata/variant naming | item exporter | preset records | staging manifests | no | SYSTEM-SPECIFIC — KEEP SEPARATE | schemas differ |
| output paths/manifest writing | item build | depth build | staging | no | CENTRALIZE ONLY THROUGH ADAPTERS | artifact contracts differ |
| preview setup | Workbench item gallery | Blender depth inspection | engine context preview | no | SYSTEM-SPECIFIC — KEEP SEPARATE | different consumers |
| scale constants/conversion | item display units | `CELL_METRES=2.5` | runtime cell units | no | INSUFFICIENT EVIDENCE | no shared metre contract |
| coordinate conversion | Blender/exporter assumptions | depth sampling Z | `obj_model.objToWorld` OBJ→engine | no | SYSTEM-SPECIFIC — KEEP SEPARATE | explicit `x,-z,y` conversion |
| shared model representation | OBJ output | no OBJ | `presentation.mesh` also serves geometry | yes | SAFE TO CENTRALIZE | shared builder/model groups |
| world placement | item viewport fit | no | `viewport_3d.ensurePlacedModel` raw cell offsets | no | SYSTEM-SPECIFIC — KEEP SEPARATE | distinct consumers |
| item viewport fitting | `item_model_view.calculateFit` | no | world placement does not fit | no | SYSTEM-SPECIFIC — KEEP SEPARATE | viewport contract |
| model caching | `obj_model.load` path cache | no | geometry composition cache | no | CENTRALIZE ONLY THROUGH ADAPTERS | different cache keys |
| collision/blocksMovement | no item collision field | no | tileset feature metadata / geometry role | no | SYSTEM-SPECIFIC — KEEP SEPARATE | gameplay metadata is not mesh data |
| bounds/geometry/seam validation | exporter asserts | wrap checks | schema/mesh checks | no | CENTRALIZE ONLY THROUGH ADAPTERS | predicates differ |
| generated cleanup | build wholesale | selective merge | staging safeguards | no | CENTRALIZE ONLY THROUGH ADAPTERS | lifecycle differs |
| material identity | Blender diffuse groups | grayscale relief | albedo/MTL/runtime materials | no | SYSTEM-SPECIFIC — KEEP SEPARATE | identities are lost/transformed |
| sockets/attachments | not found | not applicable | no runtime contract found | unknown | INSUFFICIENT EVIDENCE | no authoritative schema |

Tile periodicity, cutter duplication, sampling/backplanes, item builders, and runtime topology compilers remain specialized.

## 9. Current Contract Mismatches and Risks

| Risk | Evidence | Current consequence | Phase |
|---|---|---|---|
| item display vs world scale | no metre contract; view applies fit | world reuse unsafe | Phase 2 |
| Blender discovery differs | wrapper vs `blendergeom.py` search | environment-dependent builds | Phase 2 |
| physical vs normalized depth | 128 convention plus runtime scale | same PNG has ambiguous meaning | Phase 2 / 6 |
| material identity loss | Principled→OBJ/MTL/albedo paths | appearance cannot be inferred across pipelines | Phase 2 |
| representation vs gameplay role | schema separates topology/role; blocks rule | authors must encode both correctly | Phase 2 |
| manifest collision | pattern manifests break `runs` | read-only listing fails | Phase 3 |
| inspection vs source | docs/code say `.blend` overwritten | edits can silently disappear | Phase 2 |
| absolute paths | tracked depth manifest contains `D:/...` | portability/reproducibility risk | Phase 2 |
| state/variant naming | exporter suffixes and staging variant indices differ | association requires explicit mapping | Phase 2/5 |
| pivot consistency | exporter root pivot, runtime fit | world placement not established | Phase 5 |
| collision metadata | `blocksMovement` only schema role; mesh not collision | render geometry does not imply collision | Phase 2 |
| structural provenance | staged guide fields are not copied by `staging.promote` | production albedo has no automatic backlink | Phase 7 |
| atlas pairing | independent `--cell`/`--height-cell`, HTML only | caller can pair wrong cells without machine proof | Phase 7 |

## 10. Confirmed Invariants

Item exports are 49 roots/53 outputs with marked root metadata, root-local children, root-pivot OBJ/MTL output, and simple diffuse compatibility. Blender scripts, not inspection `.blend` files, are item/depth authority. `CELL_METRES=2.5` applies in the Blender depth scene scale; it is not proven to apply to item display models. Walls tile `x`, floors/ceilings tile `xy`; ceilings sample below. Authored height must be registered through `asset.json` and matching image dimensions. Geometry validates topology/role and compiles dense samples before decimation for plane/shell; radial uses explicit facets. Generation is staged; manual edits and promotion are guarded; context previews use the real engine. Generation parameters and seeds are recorded in run manifests where a valid run manifest exists.

## 11. Unresolved Questions

| Question | Why unresolved | Blocks Phase 2? | Smallest safe action |
|---|---|---|---|
| item-unit/world-scale mapping | item view has no metre declaration; world OBJ uses raw cell units | no; Phase 2 must define the unified contract | owner decision plus measured specimen |
| What exact physical height does 128/±112 represent across runtime scale? | current encoding is known, cross-system contract is not | no | Phase 2 calibration fixture |
| What exact physical height does 128/±112 represent? | normalization and runtime scale are separate | yes | paired calibration fixture |
| Are any item models intended as world props? | no automatic assignment or suitability measurement | no | measure bounds/pivot/orientation before reuse |
| Are sockets/attachments authoritative anywhere? | no registry/schema evidence | no | search all data and presentation consumers |
| Are sockets/attachments authoritative anywhere? | no registry/schema evidence | no | search all data and presentation consumers |
| Exact `--force` versus `--force-dirty` behavior in all promotion branches | implementation has branches beyond summary | no | read-only branch matrix from `staging.py` |
