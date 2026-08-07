# Deterministic world-model census

`build_model_census.py` is a batch extension of the existing asset contract and
world-prop production path. It is not a second runtime model system and it does
not promote content into maps or data registries.

## Design justification

Second Rite already separates semantic asset identity, materials, procedural
recipes, Blender export and explicit promotion. A comparison batch needs to
exercise that vocabulary hundreds of times, including bad ideas, without making
Blender installation a prerequisite for enumeration or scoring. The census
therefore adds one backend-neutral mesh recipe layer:

- `mesh_recipe.py` owns reusable geometry operations and reads the existing
  `tools/asset-language/materials.json` registry;
- the direct compiler writes deterministic OBJ/MTL/UV products and small
  semantic microtextures;
- `tools/blender/recipes/second_rite_census/catalogue.py` consumes the same mesh
  result for inspection and selective polish rather than reimplementing it;
- authored identities, risks, score adjustments, manual judgments and explicit
  failure injections live in the asset-set JSON, not hidden condition tables;
- all products remain staged and require an owner-reviewed in-engine G5 pass.

This follows the repository rules of one implementation, reusable primitives,
fail-loud validation, contract-owned materials and mechanically enforced rules.
It does not change runtime schemas or engine behavior.

The census source is the tracked `assets/authoring/second_rite_census/asset-set.json`
expanded from the checksum-pinned `.census-bootstrap/` archive. Generated models,
evaluation files, contact sheets and raw review captures are local reproducible
products and are ignored by Git. Build them explicitly with
`python tools/asset-production/materialize_model_census.py --build`; then run
the strict in-engine gate with `lovec . census-review`. The ordinary
`lovec . unittest` command does not require census fixtures.

## Build

From the repository root:

```text
python tools/asset-production/build_model_census.py
```

The default source is
`assets/authoring/second_rite_census/asset-set.json`. The command requires
Python, NumPy and Pillow. It recreates:

- 100 distinct concept records;
- 157 state-specific OBJ exports plus one shared MTL;
- 12 deterministic 64x64 semantic material textures;
- contact sheets, machine-readable scores and written review for every concept.

States do not increase the concept count. `closed` and `open` are two products
of one chest concept, not two models for census accounting.

## Evaluation contract

The build rejects or penalizes malformed topology, non-finite coordinates,
degenerate faces, bad floor pivots, unjustified multi-cell spans, inefficient
polygon use, weak screen-space readability, indistinguishable semantic states,
and within-family designs that are structurally or visually too close to count
as a new approach.

Novelty is not judged from the outer silhouette alone. Surface fixtures and
structural openings can share a mounting frame while differing meaningfully in
relief, negative space and material hierarchy, so the evaluator combines:

1. geometry identity without material names;
2. normalized projected silhouette overlap;
3. flat semantic-material appearance difference.

The contact sheets deliberately use flat colors. The small generated textures
are interchange experiments, not camouflage for weak forms.

## Failure preservation

`census.failureInjection` deliberately produces a closed set of known failures.
The suite asserts that only those declared interchange files are malformed.
Other failures remain valid OBJ files but are rejected aesthetically or
production-wise. This distinction is recorded in `evaluation.json`,
`all-models.md` and `failed-models.md`.

## Tests

```text
python -m unittest discover \
  -s tools/asset-production/tests \
  -p "test_*.py" -v
```

The tests enforce exactly 100 unique concepts, 157 state products, no census
variants, distinct state geometry, material-registry use, explicit failure
injections, UV-bearing exports and the expected malformed-OBJ set.
