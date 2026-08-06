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
| OBJ/MTL | exporter | runtime OBJ/MTL is authoritative input | generated/tracked | `engine/mesh.lua` / item view | no | item build |
| item manifest/preview | builder | no; report | generated | human/tooling | no | item build |
| Blender depth PNG | `render_depth.py` | generated from `scenes.py` | tracked production input | `gen.py --height`, geometry authoring | no | `python tools/asset-gen/blendergeom.py` |
| depth manifest | `blendergeom.py` | generated index | tracked | tooling/documentation | no | same |
| `albedo.png` / `height.png` | authoring or generation/promotion | together form geometry input | tracked production asset | geometry compiler | no | `authorgeom.py`/staging/promotion |
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
| atlas companion metadata | no companion found in inspected outputs | UNKNOWN | UNKNOWN | UNKNOWN | UNKNOWN | identify consumer/format first |

Generated inspection files are not source scripts; staging files are temporary candidates; runtime meshes are recreated and not persisted.

## 3. Blender Item-Model Pipeline

Path: `build_expanded_item_library.py` recipe functions (`create_root`, `parent_local`, `add_cube`, `add_cylinder`, `add_prism`, `add_sword`, and family builders) create a scene and root objects. `create_root` assigns `item_export=true`, `item_export_name`, display/category/description properties. Children are parented with local transforms. The gallery location is root placement; authored geometry remains root-local.

`second_rite_item_exporter.py` finds marked top-level roots, duplicates each hierarchy, applies root-pivot export semantics, converts shape-key variants to static meshes, triangulates/normalizes the export copy as required, and writes one OBJ plus MTL per output name. The filename is the root `item_export_name` (family suffixes identify static variants). The builder asserts 49 roots and 53 OBJ outputs. `build_library_windows.ps1` supplies Blender and output paths; the generated `.blend`, preview and manifest are inspection/report outputs.

Runtime assignment is explicit `model` paths in `data/items.json`; `loader.getItem` supplies the path to `presentation/item_model_view.lua`, whose `resolveModel`/`draw` uses the shared OBJ loader/cache. `engine/mesh.lua` is the runtime loader. Tests `tests/test_item_model_assignments.lua`, `tests/test_item_model_view.lua`, and `tests/test_item_display.lua` protect assignment, missing/fallback behavior, fit, and drawing.

Arrow contract: recipe functions → Blender scene objects (input: dimensions/materials; output: child meshes); marked roots → duplicate export hierarchy (input: custom properties; output: isolated root); shape keys → static variant objects (input: keyed mesh; output: one mesh per named state); export → OBJ/MTL (input: root-local geometry and simple diffuse materials; output: files); item data → path assignment (input: item id; output: filename); loader → GPU mesh (input: OBJ/MTL; output: LÖVE mesh/material groups); item view → fit/draw (input: bounds and viewport; output: displayed model).

**FACT:** coordinates are Blender/LÖVE object coordinates with Y depth and Z up in the authoring helpers; the exporter recentres around the root pivot. The toolkit documents one Blender unit as the toolkit’s item authoring unit, but no repository contract establishes a real-world metre equivalence. Therefore item models are display-scale authored assets, not proven world-scale assets. Final display fit/scale is applied in `presentation/item_model_view.lua` (`calculateFit`/`draw`), not in item data. Pivot convention is root origin; children remain root-local.

The runtime consumes OBJ positions, faces, UVs, `mtllib`/`usemtl`, and MTL diffuse material groups/colors used by the loader. Principled shader graphs and non-exported Blender properties are discarded by the OBJ/MTL interchange. **INFERENCE:** these models are not directly world props without a separate world placement/scale/collision contract; no such assignment was found. Item IDs associate indirectly through `data/items.json`, not through OBJ contents. Export assumptions specific to item display include one marked root per item, origin-centred/root-pivot output, simple diffuse groups, and static variants.

Invariants: 49 marked roots; 53 named outputs; marked root metadata; root-local children; root-origin export; OBJ/MTL-compatible diffuse groups; explicit item-path assignment; no inference that a display model is world-scale or collision-ready.

## 4. Blender Depth-Map Pipeline

`tools/asset-gen/blender/scenes.py` is the preset authority. `blendergeom.py` selects presets, discovers Blender through `BLENDER`, fixed Windows paths, then `blender`, and launches `--background --factory-startup --python render_depth.py`. `render_depth.py` builds evaluated Blender geometry, including periodic solids and boolean cutters duplicated over tile boundaries, raycasts the evaluated scene, and emits numeric relief. `CELL_METRES = 2.5` is the documented physical cell scale used when converting tile-relative geometry to metre-sized room/cell dimensions; Blender object coordinates and generated map values remain distinct. Exact per-helper conversions are in `scenes.py`; no code establishes that PNG values are metres.

Wall samples along the face axis and one depth axis; floor samples from above; ceiling samples from below. Manifest `view` is the sampling/view vocabulary emitted by the preset (`above` for walls/floors and `below` for ceilings). **INFERENCE:** wall `above` is legacy vocabulary rather than a physical camera direction, because walls are face samples and tile only `x`; it is not safe to reinterpret without changing consumers.

The emitted field is normalized around 128: manifest convention is opaque RGBA, `128 = dominant surface`, `+-112 relief`. Raw relief comes from ray-hit distance/height relative to the dominant surface, then median/percentile normalization and contrast encode it. The PNG is both ControlNet depth conditioning (`gen.py --height`) and an authored runtime geometry input when registered in `assets/geometry/**`; the repository does not prove that its grayscale value is physical height. Runtime displacement magnitude is supplied by geometry metadata (`heightScale`/`depthScale`), not by treating 128 as metres.

Wall tiles on `x`; floor/ceiling on `xy`. Periodic solids are duplicated across relevant tile boundaries; boolean cutters are likewise duplicated so subtraction remains continuous. Wrap acceptance is `ratio <= 3.0 OR step <= 0.03` per axis; either criterion can pass by design. Selective `--preset` renders only requested presets, merges existing valid records, replaces matching records, and writes the merged manifest so omitted maps are not lost. `.blend` files beside PNGs are inspection copies rebuilt wholesale; the PNG and manifest are the production inputs. Phase 0 measured four representatives and recorded all `wrapOk`; those measurements are retained in `docs/asset-pipeline/baseline/blender-depth-summary.json` and were not rerun.

Current ambiguity: physical height, normalized depth, ControlNet guidance depth, and runtime displacement share a PNG but have different scales. **UNKNOWN:** a single canonical physical-height interpretation is not declared; resolving it needs an owner-approved contract plus a paired sample showing metres-to-pixel-to-runtime displacement.

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

Promotion calculates the destination from the resolved class output path and name tokens. `{name}/albedo.png` geometry destinations are supported by class output configuration; the sibling height/depth guide is supplied separately through `--height`/context and recorded in run/context metadata. **UNKNOWN:** structural provenance is not proven to survive every promotion/atlas path, and no automatic albedo-height pairing check was found beyond dimensions and recorded paths. Atlas assembly tiles selected images into an atlas; the inspected assembler preserves image placement sufficient for the runtime atlas but no companion metadata file was found, so source run/class/height provenance is not guaranteed to survive. Real-engine context previews invoke the engine preview path; reports use generated contact sheets/metrics, making them distinct evidence.

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

1. `tools/blender/second-rite-item-model-toolkit/build_expanded_item_library.py:create_root` → Blender child objects via `parent_local` → marked roots (`item_export`) → `second_rite_item_exporter.py` duplicate/shape-key static conversion → `assets/models/items/*.obj` + `.mtl` → `data/items.json:model` → `engine/mesh.lua` OBJ/MTL loader → `presentation/item_model_view.lua:draw`.

2. `tools/asset-gen/blender/scenes.py` preset → `render_depth.py` evaluated scene → raycast samples → relief normalization → `blendergeom.py` grayscale PNG/manifest → `gen.py:_control_from_height` ControlNet conditioning → promoted `assets/geometry/<name>/albedo.png` plus height → `engine/geometry/schema.lua`/plane/shell/radial compiler.

3. `assets/geometry/<name>/{asset.json,albedo.png,height.png}` → `schema.parse` → `images.data` and topology sampling → dense plane/shell mesh or radial facets → `decimate.run` where plane/shell applies → `presentation.mesh` GPU mesh/material groups → world renderer placement.

4. `classes.json` + `classes.py` → prompt construction in `gen.py` → provider module / `forge.py` → `raw-N.png` → `postprocess.py` → seam scoring/repair → staged variant + `lib/staging.py` manifest → report/contact sheet/context preview → guarded `promote` → resolved runtime destination (including geometry albedo path).

## 8. Duplication and Shared-Concept Matrix

| Concept | Item toolkit | Depth pipeline | Other implementation | Same semantics? | Classification | Evidence |
|---|---|---|---|---|---|---|
| Blender discovery | wrapper/build | `blender_executable` search | none | no | SYSTEM-SPECIFIC — KEEP SEPARATE | different launch contracts |
| scene clearing | builder | scene helpers | none | unknown | INSUFFICIENT EVIDENCE | helper bodies differ |
| collection/material/flat shading | item builders | depth scenes | runtime materials | no | CENTRALIZE ONLY THROUGH ADAPTERS | different output roles |
| primitive/bevel construction | item-specific helpers | preset geometry | geometry compilers | no | SYSTEM-SPECIFIC — KEEP SEPARATE | semantics differ |
| root/metadata/variant naming | item exporter | preset records | staging manifests | no | SYSTEM-SPECIFIC — KEEP SEPARATE | schemas differ |
| output paths/manifest writing | item build | depth build | staging | no | CENTRALIZE ONLY THROUGH ADAPTERS | artifact contracts differ |
| preview setup | Workbench item gallery | Blender depth inspection | engine context preview | no | SYSTEM-SPECIFIC — KEEP SEPARATE | different consumers |
| scale constants/conversion | item display units | `CELL_METRES=2.5` | runtime cell units | no | INSUFFICIENT EVIDENCE | no shared metre contract |
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
| structural provenance | promotion/atlas output lacks confirmed full lineage | audit trail may end at image | Phase 7 |
| atlas metadata loss | no companion metadata found | source pairing may be unrecoverable | Phase 7 |

## 10. Confirmed Invariants

Item exports are 49 roots/53 outputs with marked root metadata, root-local children, root-pivot OBJ/MTL output, and simple diffuse compatibility. Blender scripts, not inspection `.blend` files, are item/depth authority. `CELL_METRES=2.5` applies in the Blender depth scene scale; it is not proven to apply to item display models. Walls tile `x`, floors/ceilings tile `xy`; ceilings sample below. Authored height must be registered through `asset.json` and matching image dimensions. Geometry validates topology/role and compiles dense samples before decimation for plane/shell; radial uses explicit facets. Generation is staged; manual edits and promotion are guarded; context previews use the real engine. Generation parameters and seeds are recorded in run manifests where a valid run manifest exists.

## 11. Unresolved Questions

| Question | Why unresolved | Blocks Phase 2? | Smallest safe action |
|---|---|---|---|
| What is the canonical metre meaning of item units? | no declaration or measured contract | yes | owner-approved scale specimen and test |
| Is depth `view` legacy or physical vocabulary? | consumers do not define semantics | yes | trace all consumers and approve terminology contract |
| What exact physical height does 128/±112 represent? | normalization and runtime scale are separate | yes | paired calibration fixture |
| Does every promotion preserve height/source provenance? | no complete metadata chain found | yes | inspect a disposable staged run and manifest schema |
| Is any atlas companion metadata generated elsewhere? | no file/consumer found in inspected paths | yes | repository-wide search plus runtime atlas consumer trace |
| Are any item models intended as world props? | no role/assignment contract found | no, but blocks migration | owner decision and collision/scale test |
| Are sockets/attachments authoritative anywhere? | no registry/schema evidence | no | search all data and presentation consumers |
| Exact `--force` versus `--force-dirty` behavior in all promotion branches | implementation has branches beyond summary | no | read-only branch matrix from `staging.py` |
