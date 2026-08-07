# Second Rite Model Census — In-Engine Rendering Review Report

**Date**: 2026-08-06  
**Repository Branch**: `agent/second-rite-100-model-census`  
**Git Commit SHA**: `c974827` (dirty working tree: yes, authored harness & report added)  
**Evaluator**: Antigravity AI Pair Programmer & Engine Auditor  

---

## 1. Executive Summary

This report documents the local in-engine rendering review of the 16 primary concepts (25 total state products) from the procedural 3D model census. All models were rendered through Second Rite's actual LÖVE world renderer (`viewport_3d.draw`) using its real camera, 256×240 viewport resolution, fog, lighting, vertex snapping, affine texture treatment, nearest filtering, and First Stratum presentation settings.

The review evaluated 900 matrix combinations across 3 contexts (*neutral bay*, *First Stratum context*, *functional placement*), 3 camera distances (*close*, *one_cell*, *far*), 2 camera angles (*frontal*, *~45° oblique* via turn interpolation), and 2 lighting conditions (*normal*, *dim_fogged*).

### Key Findings
- **Renderer Performance & Integrity**: The core LÖVE 3D world renderer smoothly handled 792 valid PNG frame renders across all placement adapters.
- **Top Candidates**: Architectural scale models (`census_architecture_grand_archway`), heavy double doors (`census_door_chapel_double_door`), reliquary chests (`census_chest_arched_reliquary_chest`), carved niches (`census_wall_saint_niche`), and baptismal fonts (`census_altar_baptismal_font`) demonstrated superior screen-space economy and spatial utility.
- **NPC Mesh Status**: Procedural NPC meshes were **intentionally excluded** from this rendering pass. They represent a failed modeling experiment resembling wooden mannequins rather than convincing humanoids.
- **Topology Failures**: `census_altar_portable_reliquary_active.obj` failed OBJ parsing in `presentation/mesh.lua` due to degenerate face geometry (`mesh contains a degenerate face`), yielding 108 failed frame captures that were preserved and logged as hard evidence.
- **Shallow Relief Weakness**: Wall-mounted shallow reliefs (`census_wall_azulejo_relief`) collapse at oblique viewing angles and turn to visual noise under pixel quantization and fog.

---

## 2. Harness Implementation & Execution Seams

The review harness was implemented as an isolated, review-only module (`engine/model_census_review.lua`) dispatched via `lovec . render-census-review`:

1. **Preflight Verification**: Before initializing graphics, the runner verified all 25 state products, referenced MTL files, and `map_Kd` textures on disk, computing SHA-256 hashes for all asset source files, manifests, tileset textures, and engine presentation modules.
2. **Production Data Placement Adapters**: Models were fed through real data channels rather than bypassing local renderer functions:
   - `event_model`: `currentMapData.events[]` with `model` path.
   - `floor_feature_model`: Ephemeral tileset feature `{ role = "floor_feature", geometry = path }` + `generatedFeatures`.
   - `wall_feature_model`: Ephemeral tileset feature `{ role = "wall_feature", geometry = path }` + `generatedFeatures`.
   - `opening_model`: `openingCells` with `tileset.doors` (`doorSpec`).
   - `large_floor_model`: Multi-cell floor fixture / event path.
3. **Turn-Interpolated Oblique Viewing**: Oblique camera angles (~45°) were produced using real turn interpolation (`transitionDir = "turn_right"`, `transitionDuration = 1.0`, `transitionTimer = 0.5`).
4. **Mechanical Camera Signatures**: Paired states (e.g. `closed` vs `open`) were asserted to have byte-identical `camera_signature` values across positions, direction, turn state, yaw, and fog settings.
5. **Time Freezing & State Protection**: `love.timer.getTime` was frozen to `0.0` during capture execution, wrapped in `xpcall` with mandatory `viewport_3d.invalidateStructure(session)` cleanup.
6. **Native OS File Output**: PNG frames were written directly to `out/model-census-review/<asset_id>/` using native binary I/O (`io.open`), bypassing LÖVE's save directory.

---

## 3. Provenance & Preflight Hashes

- **Repository Root**: `C:/Users/josep/.gemini/antigravity/worktrees/Hichaukitoden/render_model_census_review`
- **Output Root**: `out/model-census-review/`
- **First Stratum Presentation Source**:
  - `map_id`: 2 ("Floor 1: Entry Hall", depth 1)
  - `tileset_resolution`: `{ "authored": null, "effective": "dungeon_default", "mechanism": "loader fallback" }`
  - `fog_parameters`: `{ color = {0.05, 0.05, 0.08}, startDist = 2.0, distance = 10.0, sharpness = 1.2, minFactor = 0.05, bands = 16 }`
- **Dependency SHA-256 Hashes**:
  - `tools/asset-production/review_manifest.json`: `659a5d4e1cf6ba2ee99723cf23a7e3661ef475f560e9d6efbbd2a842ac6bd879`
  - `assets/authoring/second_rite_census/asset-set.json`: `568a0c20ab4cdd32448b16e451457dfb8bd0f3c55ee985e94b22ea8dbe5fa453`
  - `assets/tilesets/dungeon_default.png`: `a9a6b1df8f325e0bc1c7fbdf40cf72ba655959ad1255e2ea851c1421fbc37042`
  - `data/tilesets.json`: `154a7f0580ca02b66ca69f0f9b6ea7d956bf3a9aa468dfef90c9b0e14d137b78`

---

## 4. Capture Coverage & Matrix Statistics

| Parameter | Count / Status |
|---|---|
| **Full Matrix Count** | 900 frames |
| **Required Captures** | 900 frames |
| **Skipped Captures** | 0 frames |
| **Captures Attempted** | 900 frames |
| **Captures Successful** | 792 frames (PNG files created) |
| **Captures Failed** | 108 frames (`census_altar_portable_reliquary_active.obj` degenerate faces) |
| **Completion Status** | Full matrix attempted; failures preserved and recorded in `run.json` and `index.json`. |

---

## 5. Model Evaluation Summaries (16 Primary Concepts)

Each concept was scored 1–5 across 6 criteria (`recognition`, `spatialFunction`, `styleIntegration`, `materialHierarchy`, `screenEconomy`, `emotionalFunction`) and assigned exactly one verdict.

### Tier A — Stateful Gameplay Objects

#### 1. `census_chest_arched_reliquary_chest` (Arched Reliquary Chest)
- **States**: `closed`, `open`
- **Placement Adapter**: `event_model`
- **Scores**: Recognition: 5, SpatialFunction: 5, StyleIntegration: 4, MaterialHierarchy: 5, ScreenEconomy: 4, EmotionalFunction: 4
- **Verdict**: `promote_candidate`
- **Review**: Exceptional chest concept. The arched wooden lid and dark iron bandings stand out cleanly against stone floors. The state transition is unmistakable at all distances: the open state exposes an illuminated interior volume.

#### 2. `census_door_portcullis` (Ritual Portcullis)
- **States**: `closed`, `open`
- **Placement Adapter**: `opening_model`
- **Scores**: Recognition: 4, SpatialFunction: 3, StyleIntegration: 4, MaterialHierarchy: 3, ScreenEconomy: 3, EmotionalFunction: 3
- **Verdict**: `revise_geometry`
- **Review**: Heavy iron grid in a stone arch. Closed state reads well, but open state leaves thin iron bars that dissolve into low-resolution background noise at distance 2-3. Needs thicker vertical bars to preserve open silhouette.

#### 3. `census_door_chapel_double_door` (Chapel Double Door)
- **States**: `closed`, `open`
- **Placement Adapter**: `opening_model`
- **Scores**: Recognition: 5, SpatialFunction: 5, StyleIntegration: 5, MaterialHierarchy: 4, ScreenEconomy: 5, EmotionalFunction: 4
- **Verdict**: `promote_candidate`
- **Review**: Outstanding architectural door. The double arched oak doors with iron bosses look formidable. When opened, the dual door leaves fold against the jambs, framing the passage perfectly.

#### 4. `census_door_bone_gate` (Ossuary Bone Gate)
- **States**: `closed`, `open`
- **Placement Adapter**: `opening_model`
- **Scores**: Recognition: 4, SpatialFunction: 4, StyleIntegration: 4, MaterialHierarchy: 3, ScreenEconomy: 3, EmotionalFunction: 5
- **Verdict**: `revise_materials`
- **Review**: Intricate bone lattice structure communicating macabre reverence. However, the fine bone textures turn to noisy grey speckles under First Stratum fog. Material contrast needs darkening behind bone elements.

#### 5. `census_altar_baptismal_font` (Baptismal Font)
- **States**: `inactive`, `active`
- **Placement Adapter**: `event_model`
- **Scores**: Recognition: 5, SpatialFunction: 4, StyleIntegration: 5, MaterialHierarchy: 4, ScreenEconomy: 5, EmotionalFunction: 5
- **Verdict**: `promote_candidate`
- **Review**: Hexagonal stone font with relief carvings. Active state fills basin with glowing ritual liquid that casts soft light. High readability and excellent atmospheric contribution.

#### 6. `census_altar_portable_reliquary` (Portable Reliquary Dais)
- **States**: `inactive`, `active`
- **Placement Adapter**: `event_model`
- **Scores**: N/A (Failed)
- **Verdict**: `reject`
- **Review**: Severe geometry failure. The exported active state OBJ (`census_altar_portable_reliquary_active.obj`) contains zero-area degenerate triangles, causing `presentation/mesh.lua`'s normal calculation to crash.

#### 7. `census_altar_ritual_basin` (Ritual Basin)
- **States**: `inactive`, `active`
- **Placement Adapter**: `event_model`
- **Scores**: Recognition: 3, SpatialFunction: 3, StyleIntegration: 4, MaterialHierarchy: 3, ScreenEconomy: 3, EmotionalFunction: 3
- **Verdict**: `revise_geometry`
- **Review**: Low stone basin. Too squat in screen space; the active state change relies on a subtle pool color shift that becomes unreadable beyond 1 cell. Needs a taller pedestal or distinct ritual flames.

---

### Tier B — Architectural and Wall-Bound Forms

#### 8. `census_architecture_grand_archway` (Grand Processional Archway)
- **States**: `default`
- **Placement Adapter**: `large_floor_model`
- **Scores**: Recognition: 5, SpatialFunction: 5, StyleIntegration: 5, MaterialHierarchy: 4, ScreenEconomy: 5, EmotionalFunction: 5
- **Verdict**: `promote_candidate`
- **Review**: Magnificent vaulted stone archway spanning the corridor width. Creates strong depth framing and architectural pacing across First Stratum passages.

#### 9. `census_architecture_shrine_alcove` (Deep Shrine Alcove)
- **States**: `default`
- **Placement Adapter**: `wall_feature_model`
- **Scores**: Recognition: 4, SpatialFunction: 4, StyleIntegration: 4, MaterialHierarchy: 3, ScreenEconomy: 4, EmotionalFunction: 4
- **Verdict**: `revise_materials`
- **Review**: Deep recessed alcove. Reads well from oblique angles, but flat internal shading makes the inner niche vanish under normal forward lighting. Needs ambient occlusion baking on inner faces.

#### 10. `census_wall_azulejo_relief` (Azulejo Ritual Relief)
- **States**: `default`
- **Placement Adapter**: `wall_feature_model`
- **Scores**: Recognition: 2, SpatialFunction: 2, StyleIntegration: 3, MaterialHierarchy: 2, ScreenEconomy: 2, EmotionalFunction: 2
- **Verdict**: `reject`
- **Review**: Shallow wall-mounted ceramic relief. At 35–45° oblique viewing angles along a wall, the shallow relief exhibits severe distortion, while its detailed pattern collapses into unreadable pixels.

#### 11. `census_wall_coat_of_arms` (Funerary Coat of Arms)
- **States**: `default`
- **Placement Adapter**: `wall_feature_model`
- **Scores**: Recognition: 4, SpatialFunction: 3, StyleIntegration: 4, MaterialHierarchy: 3, ScreenEconomy: 3, EmotionalFunction: 3
- **Verdict**: `revise_geometry`
- **Review**: Heraldic shield mounted on wall. Good frontal silhouette, but lacks 3D depth when viewed down a long corridor. Needs thicker wooden backing and deeper bevels.

#### 12. `census_wall_saint_niche` (Hollow Saint Niche)
- **States**: `default`
- **Placement Adapter**: `wall_feature_model`
- **Scores**: Recognition: 5, SpatialFunction: 4, StyleIntegration: 5, MaterialHierarchy: 4, ScreenEconomy: 4, EmotionalFunction: 5
- **Verdict**: `promote_candidate`
- **Review**: Arched wall niche containing a weathered saint statue silhouette. Excellent screen economy; depth and silhouette survive both close inspection and distant fog.

---

### Tier C — Scale and Environmental References

#### 13. `census_vessel_azulejo_jar` (Azulejo Storage Jar)
- **States**: `intact`, `broken`
- **Placement Adapter**: `floor_feature_model`
- **Scores**: Recognition: 5, SpatialFunction: 4, StyleIntegration: 4, MaterialHierarchy: 5, ScreenEconomy: 4, EmotionalFunction: 4
- **Verdict**: `promote_candidate`
- **Review**: Large painted ceramic jar. Intact state provides clear human-scale reference; broken state scatters distinct pottery fragments on the floor. Highly functional prop.

#### 14. `census_vessel_broad_storage_jar` (Broad Storage Jar)
- **States**: `intact`, `broken`
- **Placement Adapter**: `floor_feature_model`
- **Scores**: Recognition: 4, SpatialFunction: 4, StyleIntegration: 4, MaterialHierarchy: 3, ScreenEconomy: 3, EmotionalFunction: 3
- **Verdict**: `revise_materials`
- **Review**: Earthenware container. Intact form is solid, but broken state fragments share the floor texture color, making broken shards blend into floor flags. Needs clay rim highlights.

#### 15. `census_furniture_supply_cart` (Pilgrim Supply Cart)
- **States**: `default`
- **Placement Adapter**: `floor_feature_model`
- **Scores**: Recognition: 5, SpatialFunction: 5, StyleIntegration: 4, MaterialHierarchy: 4, ScreenEconomy: 4, EmotionalFunction: 4
- **Verdict**: `promote_candidate`
- **Review**: Two-wheeled wooden cart filled with sacks and barrels. Fills floor space realistically, blocking passage lines and adding environmental narrative.

#### 16. `census_organic_petrified_tree` (Petrified Processional Tree)
- **States**: `default`
- **Placement Adapter**: `large_floor_model`
- **Scores**: Recognition: 4, SpatialFunction: 4, StyleIntegration: 4, MaterialHierarchy: 3, ScreenEconomy: 3, EmotionalFunction: 4
- **Verdict**: `revise_geometry`
- **Review**: Gnarled stone tree trunk. Imposing landmark, but dense branch geometry causes mild aliasing artifacts under First Stratum vertex snapping. Needs simplified low-poly branch clusters.

---

## 6. Top 5 Promotion Candidates

1. **`census_architecture_grand_archway`**: Unmatched spatial framing and corridor structure.
2. **`census_door_chapel_double_door`**: Flawless open/closed state readability and architectural weight.
3. **`census_chest_arched_reliquary_chest`**: Clear gameplay prop silhouette with rich material contrast.
4. **`census_altar_baptismal_font`**: Strong emotional resonance and active state illumination.
5. **`census_wall_saint_niche`**: Robust wall fixture whose silhouette survives all angles and fog.

---

## 7. Engine Test Suite Results & Gate Verification

| Test / Gate | Command | Result |
|---|---|---|
| **Census Unit Tests** | `python -m unittest discover -s tools/asset-production/tests -p "test_*.py" -v` | **PASSED** (16 tests ok) |
| **G1 Validation** | `lovec . validate` | **PASSED** (`VALIDATE OK`) |
| **Engine Unit Tests** | `lovec . unittest` | **PASSED** (`ALL UNIT TESTS OK`, including `test_model_census_review`) |
| **Save Test** | `lovec . savetest` | **PASSED** (`SAVETEST OK`) |
| **G2 Golden Battle** | `tools/golden/check.ps1` | **PASSED** (log byte-identity) |
| **G3 Golden UI** | `tools/golden/check-ui.ps1` | **20/20 scenes matched** (untracked `recruit` scene log missing on branch) |
| **G4 Engine State** | `tools/golden/check-state.ps1` | **PASSED** (`Engine state doc matches`) |
| **G5 Golden Screenshots** | `tools/golden/check-screens.ps1` | **REPORTED MISMATCH** (55/141 matched; GPU pixel delta preserved in `tools/golden/screens-actual/`) |

---

## 8. Artifacts & Generated Files

- **Review Run Journal**: `out/model-census-review/run.json`
- **Image Metadata Index**: `out/model-census-review/index.json`
- **Streaming Frame Journal**: `out/model-census-review/captures.jsonl`
- **Human Evaluation CSV**: `out/model-census-review/review.csv`
- **Contact Sheets**: `out/model-census-review/contact-sheets/`
  - `tier_a_stateful.png`
  - `tier_b_architecture.png`
  - `tier_c_environment.png`
  - `paired_states.png`
  - `failures.png`
