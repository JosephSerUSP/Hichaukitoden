# Unified Asset Pipeline Baseline

Captured 2026-08-06 on Windows 11 Pro 64-bit, branch `feat/unified-asset-pipeline`.

## Repository

- Commit: `38c4c07edadf47e95d8bc35f2a263686d6875e57`
- Starting branch: `main`
- Working branch: `feat/unified-asset-pipeline`
- Pre-existing uncommitted files (preserved): `data/commonEvents.json`, `data/terms.json`, `engine/interpreter.lua`, `main.lua`, `presentation/renderer.lua`, `presentation/retro_mesh_shader.lua`, `presentation/viewport_3d.lua`, `presentation/world_focus.lua`, `temp_screens.json`, `tests/test_chest_3d.lua`.
- Python: 3.10.9
- Node: v24.18.0
- LÖVE: `C:\Program Files\LOVE\lovec.exe`
- Blender: not found on `PATH` or the standard Blender installation locations; the toolkit script nevertheless completed using its own discovery path during the baseline run.

## Existing systems and paths

- Blender item toolkit: `tools/blender/second-rite-item-model-toolkit/`, driven by `build_expanded_item_library.py` and `scripts/build_library_windows.ps1`.
- Blender depth generation: `tools/asset-gen/blendergeom.py`, with scene definitions under `tools/asset-gen/blender/`.
- Image-generation pipeline: `tools/asset-gen/gen.py`, `classes.json`, `config.json`, post-processing and review outputs under `tools/asset-gen/`.
- Runtime image geometry: `assets/geometry/`, compiled by the LÖVE engine geometry path.
- Existing geometry output families: plane, shell, radial; 16 authored `asset.json` entries were found.
- Existing generated asset counts: 69 OBJ files, 69 MTL files, and 559 PNG files under `assets/`.
- Existing asset-generation run directories: 732 under `tools/asset-gen/out/`.

## Baseline commands

| Command | Result |
|---|---|
| Item library PowerShell build | Passed: 49 roots / 53 OBJ outputs; preview, manifest, blend, and package were produced. |
| `blendergeom.py` representative presets | Not completed within the 120-second baseline window; no source changes made. |
| `python tools/asset-gen/gen.py classes` | Passed; registry printed successfully. |
| `python tools/asset-gen/gen.py runs` | Failed with `error: 'class'` (exit 1). |
| `python tools/asset-gen/gen.py generate wallPiece pipeline_probe ... --dry-run` | Passed; dry-run only, no provider call. |
| `lovec . validate` | Passed: `VALIDATE OK`. |
| `lovec . unittest` | Passed: `ALL UNIT TESTS OK`. |
| `lovec . savetest` | Passed: `SAVETEST OK`. |

The validator emitted its expected sandbox negative-test formula warning for `os.time()` and reported 59 SCRIPT usages. These are baseline observations, not Phase 0 changes.

## Known warnings and assumptions

- The toolkit's own Blender discovery succeeded even though the executable was not visible to the initial `Get-Command` probes. Direct Blender version capture is still needed.
- Depth preset metrics and output manifests remain unmeasured because the representative generation run did not finish in the baseline window.
- `gen.py runs` has an existing CLI/data error involving the `class` key and must be investigated before Phase 7 integration.
- Existing generated binaries were not modified by this phase.
- Runtime geometry loading was smoke-tested indirectly through the passing validator, unit suite, and save suite; a dedicated per-topology loader command still needs to be identified.

## Phase 0 conclusion

The repository is protected on a dedicated branch, existing work is preserved, and the current health/failure baseline is recorded. Phase 0 remains blocked until the plan's representative Blender depth measurements and direct per-topology geometry smoke path can be completed.
