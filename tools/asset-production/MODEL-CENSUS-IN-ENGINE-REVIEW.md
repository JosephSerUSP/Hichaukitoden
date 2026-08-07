# Second Rite Model Census — In-Engine Review Protocol (v2)

This is the authoritative review protocol for the 16-concept / 25-state procedural model census.

**The 2026-08-06 v1 review is invalidated.** Its contact sheets exposed placement-adapter and camera/context defects. See `docs/reports/second-rite-model-census/in-engine-review.md` and the preserved invalid sheets under `docs/reports/second-rite-model-census/artifacts/invalidated-2026-08-06/`.

## Purpose

The review answers two separate questions instead of conflating them:

1. **Model diagnostic:** does the asset's geometry, scale, material hierarchy, state change and silhouette survive Second Rite's actual renderer?
2. **Context compatibility:** how does the same asset behave against the current legacy First Stratum presentation?

The first question is primary. The current `dungeon_default` atlas is aesthetically outdated, so the contextual pass is useful for runtime scale/readability/fog competition but is not treated as the target art-direction authority.

All captures must pass through `presentation.viewport_3d.draw(session)` and the normal production placement channels. Review code may construct hermetic sessions and temporary tilesets, but it must not call renderer-local mesh queue functions directly.

## Cohort

### Tier A — Stateful gameplay objects

- `census_chest_arched_reliquary_chest` — `closed`, `open`
- `census_door_portcullis` — `closed`, `open`
- `census_door_chapel_double_door` — `closed`, `open`
- `census_door_bone_gate` — `closed`, `open`
- `census_altar_baptismal_font` — `inactive`, `active`
- `census_altar_portable_reliquary` — `inactive`, `active`
- `census_altar_ritual_basin` — `inactive`, `active`

### Tier B — Architectural / wall-bound forms

- `census_architecture_grand_archway` — `default`
- `census_architecture_shrine_alcove` — `default`
- `census_wall_azulejo_relief` — `default`
- `census_wall_coat_of_arms` — `default`
- `census_wall_saint_niche` — `default`

### Tier C — Scale / environmental references

- `census_vessel_azulejo_jar` — `intact`, `broken`
- `census_vessel_broad_storage_jar` — `intact`, `broken`
- `census_furniture_supply_cart` — `default`
- `census_organic_petrified_tree` — `default`

NPC procedural meshes remain excluded as a separate failed experiment.

## Gate Zero — materialization and provenance

Materialize first:

```powershell
python tools/asset-production/materialize_model_census.py --build
```

The LÖVE harness verifies and hashes the already-materialized inputs. It does not rebuild them. Hash coverage includes OBJ, MTL, `map_Kd` dependencies, `review_manifest.json`, the census asset-set manifest, current dungeon atlas, map/tileset/engine data, and the renderer/OBJ/mesh presentation modules.

Any missing dependency aborts before visual work begins.

## Production placement adapters

The manifest assigns exactly one adapter to each concept.

### `event_model`

Use `currentMapData.events[]` with `model = <obj path>` and a non-wall event. The production event presentation resolver must decide that it is a model placement.

### `floor_feature_model`

Create a temporary tileset feature:

```lua
{ id = "census_review_feature", role = "floor_feature", model = "...obj" }
```

and a generated placement using the **production lookup key**:

```lua
{ material = "census_review_feature", x = ..., y = ... }
```

Do not use `id` on the generated placement; the renderer reads `material`.

### `wall_feature_model`

Create the same feature/material relationship with `role = "wall_feature"`, attach it to an actual `#` wall cell, and expose a neighboring floor face to the camera.

`wallEvent = true` is not a generic wall-OBJ adapter.

### `opening_model`

The map grid itself must contain `o`. The renderer derives prepared opening cells from that grid value and resolves the door model through `tileset.doors` / door spec. Do not invent or depend on `session.openingCells`.

The review fixture uses a north-south corridor with walls immediately west/east of the `o` cell so opening-axis resolution is deterministic.

### `large_floor_model`

Use the production event-model path at the declared interaction-facing anchor, with camera distance derived from concept bounds so oversized architecture does not intersect the camera.

## Gate One — adapter visibility smoke test

Before the full visual matrix, render five model/control pairs in the neutral context, `one_cell`, frontal, normal lighting:

- chest closed → `event_model`
- portcullis closed → `opening_model`
- azulejo jar intact → `floor_feature_model`
- saint niche default → `wall_feature_model`
- grand arch default → `large_floor_model`

For each adapter, render:

1. fixture with the production placement but no model payload;
2. otherwise identical fixture with the model payload.

Compute pixel difference. The harness requires at least a small non-zero changed-pixel count and mean absolute delta. An effectively identical pair aborts the run:

`CAPTURE INVALID: MODEL NOT VISIBLE`

This gate is an instrumentation invariant, not a human art score.

## Visual contexts

### `neutral` — primary diagnostic

- runtime-generated unpatterned neutral-gray atlas;
- very small luminance separation between wall/floor/ceiling only to preserve orientation;
- no decorative texture or panorama;
- model retains its own real materials;
- real Second Rite projection, hardware depth, affine treatment, vertex snapping, dithering and nearest filtering;
- controlled fog/time behavior.

This is the main model-comparison surface.

### `first_stratum` — legacy contextual companion

- current effective `dungeon_default` runtime atlas;
- First Stratum source is map id 2 (`Floor 1: Entry Hall`);
- map-authored fog is copied if present;
- explicitly recorded as legacy contextual evidence rather than target aesthetic authority.

### `functional` — structured exclusion

`functional` remains in the manifest so the original 900-combination design is preserved and auditable, but it is no longer rendered as a third visual environment. Correct functional placement is enforced by the adapter smoke gate.

The manifest therefore records a structured skip rule matching `context = functional`.

## Matrix and accounting

Original full matrix:

`25 states × 3 contexts × 3 distances × 2 angles × 2 lighting = 900`

V2 required visual matrix:

`25 states × 2 rendered contexts × 3 distances × 2 angles × 2 lighting = 600`

Structured skips:

`25 × 1 functional context × 3 × 2 × 2 = 300`

Required invariants:

- `full_matrix_count == required_capture_count + skipped_capture_count`
- `required_capture_count == successful_capture_count + failed_capture_count`
- `skipped_capture_count == sum(structured skip rules)`

Skipped records are journaled explicitly and never masquerade as failures or PNGs.

## Camera fixtures

### Frontal

Place the camera south of the target on the target's X axis, facing north.

### Oblique

Use the real turn interpolation:

```lua
playerDir = "N"
transitionDir = "turn_right"
transitionDuration = 1.0
transitionTimer = 0.5
```

but **orbit the camera southwest of the target** by the same anchor distance. The camera then looks northeast at ~45° while the target remains on-axis. Turning in place from the frontal camera position is forbidden because it points away from the target.

Distances are adapter/concept aware and derive from the maximum state bounds for a concept. Paired states share the same target and camera fixture.

## Paired-state signature

For every state pair and matrix coordinate, mechanically assert the same comparison signature across:

- player position/direction;
- transition state and effective yaw;
- target/anchor;
- nominal and actual anchor distance;
- review-bay geometry identity;
- context and lighting identity.

The model path/state is intentionally excluded from the pair signature.

## Capture journals

The runner writes under `out/model-census-review/`:

- `run.json` before and after the run;
- `captures.jsonl`, flushed once per attempted/skipped combination;
- `index.json` containing success, failure and structured-skip records;
- `review.csv` blank human-review template if absent;
- `smoke.json` plus five model/control image pairs;
- raw PNG matrix frames.

A failed render gets an index/journal failure record but no fake PNG.

## Postprocessor correctness

`review_model_census.py` only counts a frame as successful when both are true:

1. the index record says `success == true`;
2. the referenced PNG exists on disk.

It detects duplicate logical capture keys, missing required PNGs, failed records, interrupted JSONL tails, and high border occupancy as a clipping warning.

It must return non-zero while the required evidence set is incomplete.

## Decision contact sheets

Tier sheets use one row per state and four columns at `one_cell + normal`:

1. neutral frontal
2. neutral oblique
3. legacy First Stratum frontal
4. legacy First Stratum oblique

Additional sheets:

- `paired_states.png` — grouped state A/B comparison in both contexts for frontal and oblique;
- `distance_readability.png` — neutral frontal close / one-cell / far;
- `adapter_smoke.png` — all five control/model smoke pairs;
- `failures.png` — explicit error cards for required failed captures.

A sheet tile must never silently substitute another context/angle when the requested evidence is missing.

## Human review ownership

The score fields remain:

`asset_id,recognition,spatialFunction,styleIntegration,materialHierarchy,screenEconomy,emotionalFunction,verdict,notes`

The runner creates them blank. The postprocessor preserves human-entered values and never generates subjective scores or verdicts.

No concept is promoted/rejected solely because it clashes with the legacy `dungeon_default` look.

## Tracked evidence policy

The exhaustive frame archive can stay disposable under `out/`. Any committed written conclusion must have compact evidence published to:

`docs/reports/second-rite-model-census/artifacts/current/`

The postprocessor publishes:

- run/index/journal metadata;
- review CSV;
- smoke metadata and model/control frames;
- diagnostics;
- decision contact sheets;
- SHA-256 `artifact-manifest.json`.

The invalidated v1 sheets remain separately tracked as a harness regression fixture.

## Verification commands

```powershell
python tools/asset-production/materialize_model_census.py --build
python -m unittest discover -s tools/asset-production/tests -p "test_*.py" -v
"C:\Program Files\LOVE\lovec.exe" . unittest
"C:\Program Files\LOVE\lovec.exe" . validate
"C:\Program Files\LOVE\lovec.exe" . savetest
"C:\Program Files\LOVE\lovec.exe" . render-census-review
python tools/asset-production/review_model_census.py
powershell -NoProfile -ExecutionPolicy Bypass -File tools\golden\check.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\golden\check-ui.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\golden\check-state.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\golden\check-screens.ps1
```

A review is eligible for subjective evaluation only after the smoke gate passes and the postprocessor exits zero.
