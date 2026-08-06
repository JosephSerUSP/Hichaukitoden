# Phase 3 Regression Harness

The Phase 3 harness protects the unified contract, future asset-record semantics, and a structural baseline of existing item/world model references, geometry identities and image dimensions, depth-preset semantics, and referenced OBJ structure/bounds. It does not hash artwork pixels.

`check.py contract` validates the contract, material registry, and portable schema. `check.py record FILE...` validates future records without requiring products to exist. `check.py regression` compares the live repository to the tracked baseline. `check.py all` runs contract and regression. `check.py snapshot --output PATH [--force]` writes an explicit deterministic snapshot and refuses accidental overwrite. Exit code 0 is success, 1 is validation/regression failure, and 2 is guarded usage/overwrite failure.

The baseline is sorted structural data. Additive valid references/assets/models
and wrap-safe depth presets are allowed; changes to existing assignments,
topology/role, required image dimensions/modes, depth semantic fields, OBJ
metrics/bounds, or required MTLs are regressions. The tests exercise these
rules with temporary miniature repositories: each mutation captures a real
snapshot, changes one input, calls `compare`, and asserts the resulting pass
or path-specific diagnostic. Diagnostics identify their collection, path, and
message, and are sorted deterministically. Artwork pixels are not hashed
because this harness protects structure and semantics rather than freezing art
binaries.

Depth manifest `path` and `blend` are ignored because the legacy file contains
machine-specific absolute paths. A new depth preset with `wrapOk=false` is a
regression, as is changing an established preset to non-wrapping. Malformed
items, tilesets, geometry records/images, OBJ/MTL data, and depth entries fail
with diagnostics instead of being silently omitted.

Staging manifests use `manifestKind=asset_gen_run`/version 1 for runs and `manifestKind=height_pattern_set`/version 1 for pattern sets. Complete legacy run manifests remain usable; non-run manifests are ignored by listing and direct run operations reject them. Malformed or partial run-shaped manifests fail loudly. `gen.py runs` reports ignored non-run manifests without indexing them as runs. Legacy manifests are upgraded with the explicit kind/version when `reprocess` writes them back; existing fields are preserved.

Read-only commands are contract/record/regression/all, explicit snapshots, and `gen.py runs`. Generation, promotion, Blender depth rebuilding, and production asset editing remain out of scope. The harness does not call providers or Blender. To intentionally update the baseline, review the structural change, then run `python tools/asset-language/check.py snapshot --output docs/asset-pipeline/baseline/asset-regression.json --force` and commit the reviewed result.
