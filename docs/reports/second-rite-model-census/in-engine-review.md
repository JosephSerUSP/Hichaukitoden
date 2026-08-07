# Second Rite Model Census — In-Engine Rendering Review

**Branch:** `agent/second-rite-100-model-census`  
**Status:** **PRIOR 2026-08-06 VISUAL REVIEW INVALIDATED — corrected harness committed; rerun required**  
**Scope:** 16 concepts / 25 state products

## 1. Correction notice

The first in-engine review pass completed a large render matrix and produced a written set of 1–5 scores and promotion/revision/rejection verdicts. Inspection of the generated contact sheets subsequently showed that the evidence did not support those conclusions. This document therefore retracts the prior subjective scores and verdicts.

The failure was in the review instrumentation, not merely in contact-sheet aesthetics. Several placement adapters were not exercising the production renderer path they claimed to exercise; the three named visual contexts were not meaningfully distinct; and the oblique camera rotated away from the review target rather than orbiting it. The postprocessor could also count a declared failed path as though it were a successfully written frame.

**Do not use the previous “Top 5”, numeric scores, or concept verdicts for asset decisions.** They are invalidated pending a rerun with harness v2.

One previous finding remains independently valid: `census_altar_portable_reliquary_active.obj` reached the real OBJ/mesh parser and exposed degenerate face geometry. That geometry defect should still be repaired. It is not a visual-comparison verdict.

The five broken decision sheets from the invalidated pass are preserved under:

`docs/reports/second-rite-model-census/artifacts/invalidated-2026-08-06/`

They are retained as regression evidence for the harness itself.

## 2. Root-cause audit of the invalidated pass

### 2.1 `opening_model` bypassed the renderer's real opening source

Harness v1 populated a synthetic `reviewSession.openingCells` table while leaving the target map grid cell as `.`. The production world renderer does not treat that session field as authoritative. It prepares opening cells from map-grid cells whose value is `o`, then resolves a door spec from the active tileset.

Consequence: portcullis, chapel double door and bone-gate captures could be valid PNGs without actually placing the requested door model through the normal opening path.

Harness v2 authors a real `o` grid cell, constructs the surrounding corridor so `resolveOpeningAxis` has an unambiguous orientation, and uses a tileset `doors` model spec. There is no synthetic `session.openingCells` escape hatch.

### 2.2 Generated feature records used `id` where the renderer consumes `material`

Harness v1 inserted floor/wall placements such as `{ id = "census_feat", ... }`. The production renderer's material lookup reads `source.material` from `session.generatedFeatures`, then resolves that id through the tileset feature table.

Consequence: floor-feature and wall-feature captures frequently contained only the environment. This is visible in the old Tier B and Tier C sheets, where several labeled assets are effectively absent.

Harness v2 uses `material = "census_review_feature"` and places the corresponding feature spec in the ephemeral tileset.

### 2.3 Wall-bound models were not attached to an actual wall face

A `wall_feature_model` cannot be meaningfully reviewed by assigning metadata near an interior floor cell. The target material must resolve on a real `#` wall cell with a visible neighboring floor face.

Harness v2 creates that wall topology explicitly and exposes its south face to the review camera.

### 2.4 “neutral”, “first_stratum”, and “functional” were largely labels on the same scene

Harness v1 used the `dungeon_default` atlas for every context and rebuilt essentially the same empty 12×12 room each time. “Functional placement” also duplicated a property that should already be guaranteed by the adapter.

Harness v2 separates two actual visual questions:

1. **`neutral` — primary diagnostic context.** Runtime-generated unpatterned gray atlas, real Second Rite projection/depth/vertex snapping/affine treatment/dithering/nearest filtering, and the model's real materials. This answers: *what does the model itself do in the renderer?*
2. **`first_stratum` — legacy contextual material pass.** Current `dungeon_default` runtime presentation, explicitly labeled legacy because the atlas is aesthetically outdated and is not treated as target art direction. This answers: *what happens when the model competes with the current dungeon presentation?*

The old `functional` matrix dimension remains in the manifest for provenance but is now an explicit structured exclusion. Production placement correctness is a pre-matrix smoke-gated invariant instead.

Original full matrix: **900** combinations.  
Required v2 visual captures: **600**.  
Explicitly skipped `functional` combinations: **300**.

The accounting invariant is therefore:

`900 full = 600 required + 300 structured skips`

and after a run:

`600 required = successful PNGs + failed captures`.

### 2.5 Oblique camera turned away from the model

Harness v1 kept the camera directly south of the target and then drove the real N→E turn interpolation to its halfway point. That produces a real ~45° yaw, but the target remains due north while the camera looks northeast.

Consequence: models drift off-axis, walls enter the near plane, and the old sheets show giant/fragmented surfaces dominating some tiles.

Harness v2 preserves the production turn interpolation but **orbits the camera**. For the halfway N→E view the camera is moved southwest of the target, so the target lies on the northeast view ray. Frontal and oblique captures still share the same target/anchor.

### 2.6 Index metadata was allowed to impersonate a PNG

Harness/postprocessor v1 compared expected filenames to paths declared by index records. A record with `success=false` could therefore make a path appear present even though no PNG existed.

Harness/postprocessor v2 only counts a required frame as successful when:

- index metadata says `success == true`, **and**
- the referenced PNG exists on disk.

Failures remain failures and missing successful frames remain missing.

### 2.7 Decision evidence was disposable while conclusions were committed

The old report committed subjective conclusions while its contact sheets, journals and review CSV lived only under `out/model-census-review/`. That made the branch unable to audit its own review after the local worktree disappeared.

V2 keeps the exhaustive source-frame archive under `out/`, but the postprocessor publishes compact decision evidence into the tracked path:

`docs/reports/second-rite-model-census/artifacts/current/`

Published evidence includes run/index/journal metadata, `review.csv`, `smoke.json`, diagnostics, smoke control/model frames, decision contact sheets, and an SHA-256 artifact manifest. Raw hundreds-of-frame archives do not need to bloat ordinary Git history.

## 3. Harness v2 review protocol

### Gate Zero — materialized census and dependency provenance

Run:

```powershell
python tools/asset-production/materialize_model_census.py --build
```

The LÖVE harness verifies rather than rebuilds the census. It hashes every state OBJ, referenced MTL, `map_Kd` texture, review manifest, census asset-set manifest, current dungeon atlas, maps/tilesets/engine data, and the renderer/OBJ/mesh presentation modules.

### Gate One — five-adapter visibility smoke test

Before the 600-frame matrix begins, harness v2 renders a model-enabled frame and an otherwise identical no-model control for one representative of every production placement adapter:

| Adapter | Representative |
|---|---|
| `event_model` | Arched Reliquary Chest (`closed`) |
| `opening_model` | Ritual Portcullis (`closed`) |
| `floor_feature_model` | Azulejo Storage Jar (`intact`) |
| `wall_feature_model` | Hollow Saint Niche (`default`) |
| `large_floor_model` | Grand Processional Archway (`default`) |

The pair is pixel-differenced. If the renderer produces effectively identical control/model images, the harness aborts with:

`CAPTURE INVALID: MODEL NOT VISIBLE`

This gate exists specifically to prevent another hundreds-of-frames run whose labeled asset was never actually placed.

### Gate Two — corrected visual matrix

For every state product:

- contexts: `neutral`, `first_stratum` (legacy contextual)
- distances: `close`, `one_cell`, `far`
- angles: `frontal`, `oblique`
- lighting: `normal`, `dim_fogged`

The model is always placed through its real production adapter. Paired states mechanically share the same camera/geometry signature apart from model state.

### Gate Three — postprocessing and evidence publication

Run:

```powershell
python tools/asset-production/review_model_census.py
```

The postprocessor now:

- refuses to treat failed/missing PNGs as successful evidence;
- reports duplicate logical capture metadata;
- recovers complete rows from an interrupted `captures.jsonl`;
- emits border-occupancy warnings for likely clipping/near-plane failures;
- preserves any human-entered `review.csv` fields;
- builds decision sheets designed around the actual questions;
- publishes compact evidence to the tracked report artifact directory;
- exits nonzero while any required capture remains failed/missing or duplicated.

## 4. Contact-sheet design after correction

The previous sheets selected one `first_stratum + one_cell + oblique + normal` slice for almost everything. That made a single bad camera/context combination stand in for an entire model.

V2 Tier A/B/C sheets use four columns for every state at `one_cell + normal`:

1. neutral / frontal
2. neutral / oblique
3. legacy First Stratum / frontal
4. legacy First Stratum / oblique

This makes the model-first diagnostic and contextual compatibility question visible side-by-side.

The paired-state sheet groups each two-state concept and compares both states in both environments, with separate frontal and oblique rows. A separate `distance_readability.png` shows close / one-cell / far in the neutral diagnostic context. `adapter_smoke.png` exposes the five no-model/model control pairs. `failures.png` renders failed capture records as explicit error cards rather than silently substituting “MISSING”.

## 5. Human-review ownership

The Lua runner creates a blank template:

`asset_id,recognition,spatialFunction,styleIntegration,materialHierarchy,screenEconomy,emotionalFunction,verdict,notes`

The Python postprocessor merges and preserves existing human values. It does not generate aesthetic scores or verdicts.

The previous auto-authored subjective scores are retracted. **No replacement scores are asserted in this corrective commit.** They must be entered only after the corrected evidence exists and has been inspected.

The contextual pass should not be used to punish a model merely for conflicting with the obsolete `dungeon_default` aesthetics. `styleIntegration` should be judged primarily from the neutral model evidence plus the intended/current art direction; the legacy context is useful for runtime compatibility, silhouette competition, fog behavior and scale.

## 6. Verification status for this corrective commit

Python postprocessor tests were executed in the commit-authoring environment and cover:

- structured skip handling;
- failed metadata not satisfying a frame;
- `success=true` requiring an actual PNG;
- duplicate logical metadata;
- incomplete JSONL recovery;
- non-destructive human CSV merging;
- clipping heuristic behavior;
- four-view primary contact-sheet layout;
- tracked evidence publication and SHA-256 manifest generation.

The LÖVE runtime is not available in the remote commit-authoring environment used for this corrective commit. Therefore this document does **not** claim the new render matrix or engine gates have already passed. They must be run in the project Windows/LÖVE environment:

```powershell
python tools/asset-production/materialize_model_census.py --build
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

A visual review is eligible for approval only when the five-adapter smoke gate passes, required-capture accounting closes exactly, the postprocessor exits zero, and the tracked decision sheets visibly show the intended models rather than renderer/harness artifacts.

## 7. Current decision status

| Item | Status |
|---|---|
| Prior 1–5 scores | **INVALIDATED** |
| Prior promote/revise/reject verdicts | **INVALIDATED** |
| Prior Top 5 list | **INVALIDATED** |
| `census_altar_portable_reliquary_active.obj` degenerate geometry | **RETAINED AS PARSER/GEOMETRY FAILURE** |
| Harness v2 adapter semantics | **CORRECTIVE IMPLEMENTATION ADDED** |
| Neutral-gray diagnostic context | **ADDED** |
| Legacy First Stratum companion context | **ADDED / explicitly non-authoritative aesthetically** |
| Adapter model-vs-control smoke gate | **ADDED** |
| Corrected oblique orbit | **ADDED** |
| Strict successful-PNG validation | **ADDED** |
| Tracked decision-evidence publication | **ADDED** |
| New subjective review | **PENDING RERUN + HUMAN INSPECTION** |
