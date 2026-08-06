# Second Rite model census — local in-engine review

This brief defines the first local engine-rendering pass for the procedural model
census. It is deliberately narrower than production integration: the goal is to
learn which architectural and environmental model families survive Second Rite's
actual first-person renderer, scale, fog, snapping, dithering and materials.

## Purpose

Use the real LÖVE runtime and existing world renderer to produce repeatable,
comparable screenshots of a curated 16-concept cohort. Judge models in ordinary
play conditions rather than in Blender or isolated contact-sheet lighting.

This pass must not:

- promote census models into production maps or registries;
- redesign or repair models during capture;
- add model-specific runtime branches;
- introduce a second renderer, OBJ loader, camera implementation or material
  authority;
- update or recapture golden reference images;
- spend time on the census NPC meshes. The humanoid grammar is considered a
  failed experiment for this pass and remains preserved only as evidence.

## Materialize the census

From the repository root:

```text
python tools/asset-production/materialize_model_census.py --build
```

Before implementing a review harness, verify that these exist:

```text
assets/authoring/second_rite_census/asset-set.json
assets/models/second_rite_census/
docs/reports/second-rite-model-census/evaluation.json
```

The materializer validates its archive checksum, expands the authored source,
runs the census tests and regenerates all staged products.

## Primary cohort

State products follow this exact path pattern:

```text
assets/models/second_rite_census/<asset_id>_<state>.obj
```

States are products of one concept, not separate concepts.

### Tier A — stateful gameplay objects

| Asset ID | Display name | States | Role / placement |
|---|---|---|---|
| `census_chest_arched_reliquary_chest` | Arched Reliquary Chest | `closed`, `open` | event prop / floor centre |
| `census_door_portcullis` | Ritual Portcullis | `closed`, `open` | structural opening / opening centre |
| `census_door_chapel_double_door` | Chapel Double Door | `closed`, `open` | structural opening / opening centre |
| `census_door_bone_gate` | Ossuary Bone Gate | `closed`, `open` | structural opening / opening centre |
| `census_altar_baptismal_font` | Baptismal Font | `inactive`, `active` | event prop / floor centre |
| `census_altar_portable_reliquary` | Portable Reliquary Dais | `inactive`, `active` | event prop / floor centre |
| `census_altar_ritual_basin` | Ritual Basin | `inactive`, `active` | event prop / floor centre |

### Tier B — architectural and wall-bound forms

| Asset ID | Display name | States | Role / placement |
|---|---|---|---|
| `census_architecture_grand_archway` | Grand Processional Archway | `default` | multi-cell architecture / floor centre |
| `census_architecture_shrine_alcove` | Deep Shrine Alcove | `default` | multi-cell architecture / wall context |
| `census_wall_azulejo_relief` | Azulejo Ritual Relief | `default` | surface fixture / wall centre |
| `census_wall_coat_of_arms` | Funerary Coat of Arms | `default` | surface fixture / wall centre |
| `census_wall_saint_niche` | Hollow Saint Niche | `default` | surface fixture / wall centre |

### Tier C — scale and environmental references

| Asset ID | Display name | States | Role / placement |
|---|---|---|---|
| `census_vessel_azulejo_jar` | Azulejo Storage Jar | `intact`, `broken` | object fixture / floor centre |
| `census_vessel_broad_storage_jar` | Broad Storage Jar | `intact`, `broken` | object fixture / floor centre |
| `census_furniture_supply_cart` | Pilgrim Supply Cart | `default` | object fixture / floor centre |
| `census_organic_petrified_tree` | Petrified Processional Tree | `default` | landmark / floor centre |

## Harness rules

Inspect the existing map data, model placement path, event representation, CLI
capture tools and G5 screenshot machinery before changing anything.

Prefer, in order:

1. an existing data-driven temporary map or preview scene;
2. an existing CLI/golden-script route that can enter that map and set a fixed
   camera;
3. one small reusable review-only command or scene if the current engine has no
   suitable route.

The harness must use the existing OBJ/MTL loader and real world renderer. It
must not special-case chest, door or census IDs in production rendering code.
Missing model files, materials, states or placement frames must fail loudly.

Keep all review data isolated and clearly named. A temporary review map may live
in ordinary data only when it is unreachable from the campaign and explicitly
identified as review-only. Prefer an output or test fixture when the current
architecture already supports one.

## Capture matrix

Each concept must be captured in three contexts where applicable:

1. **neutral geometry bay** — simple floor, wall and ceiling with no flattering
   decorative competition;
2. **First Stratum context** — current representative First Stratum surfaces,
   normal fog and normal renderer effects;
3. **functional placement** — the model performing its implied role: gate
   blocking a passage, alcove terminating a wall, relief mounted on a wall,
   cart occupying plausible floor space, and so on.

Use these camera conditions:

- close interaction range;
- one cell away;
- two to three cells away;
- frontal view;
- approximately 35–45 degree oblique view.

Paired semantic states must use exactly the same camera transform and renderer
settings. Do not choose a more flattering camera for one state.

Capture both:

- the normal First Stratum baseline;
- a dim/fogged condition representative of actual play.

Do not add custom showcase lighting that the campaign does not use.

Write screenshots under:

```text
out/model-census-review/<asset_id>/<context>__<distance>__<angle>__<state>.png
```

Use stable ASCII lower-snake-case values for every filename component.

## Required outputs

The completed local run must contain:

- every requested PNG, including visibly failed or clipped frames;
- `out/model-census-review/run.json` with commit, branch, command line, platform,
  renderer settings and timestamps;
- `out/model-census-review/index.json` mapping every image to asset, state,
  context and camera transform;
- `out/model-census-review/review.csv` with one row per concept;
- contact sheets grouped by tier and by paired state;
- `docs/reports/second-rite-model-census/in-engine-review.md` summarising the run,
  failures, strongest candidates and recommended next action.

The written report must distinguish geometry problems from material problems.
Do not claim that a model is production-ready merely because it renders.

## Evaluation

Score each criterion from 1 to 5 and explain scores briefly:

- `recognition` — does the object read at ordinary play distance?
- `spatialFunction` — does blocking, passage, use, danger or activation read?
- `styleIntegration` — does it belong beside current First Stratum surfaces?
- `materialHierarchy` — do stone, metal, wood, bone, cloth and accents remain
  distinguishable?
- `screenEconomy` — does meaningful structure survive the game's resolution and
  renderer effects?
- `emotionalFunction` — does it communicate dread, reverence, habitation,
  vulnerability or history rather than generic ornament?

Assign exactly one verdict:

- `promote_candidate`
- `revise_geometry`
- `revise_materials`
- `reject`

The census' previous automated score is context only. The in-engine verdict has
higher authority for this review.

## Stop conditions

Stop and report rather than widening scope when:

- the baseline world renderer or existing gates regress;
- the task appears to require a broad renderer rewrite;
- a model can only be made convincing by changing its geometry during capture;
- the existing OBJ loader rejects a supposedly valid non-injected product;
- capture cannot be made deterministic with the current test/CLI seams.

Preserve failed screenshots, console output and error logs. Do not delete an
unflattering result and do not silently substitute another model.

## Validation

At minimum, run the census tests:

```text
python -m unittest discover -s tools/asset-production/tests -p "test_*.py" -v
```

Run the relevant engine gates on the local Windows machine. The expected LÖVE
console binary is:

```text
C:\Program Files\LOVE\lovec.exe
```

G5 is a regression check. Never recapture or update golden references to make it
pass. If it differs, preserve `tools/golden/screens-actual/`, inspect the frames
and report the exact mismatch.

## Completion definition

The review is complete only when:

- all 16 primary concepts have attempted captures;
- paired states use identical cameras;
- all outputs and metadata above exist;
- every failure is preserved and explained;
- the report explicitly identifies which model families deserve another
  iteration and which procedural approaches should stop;
- any harness change is small, reusable, tested and separate from production
  content promotion.
