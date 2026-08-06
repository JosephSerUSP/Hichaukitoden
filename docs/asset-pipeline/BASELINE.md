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
- Blender: `C:\Program Files\Blender Foundation\Blender 5.1\blender.exe`
- Blender version: Blender 5.1.2 (build `ec6e62d40fa9`)

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
| Blender executable `--version` | Passed: Blender 5.1.2 at the path above. |
| `blendergeom.py` representative presets | Passed separately at `--size 512 --no-blend` into a temporary directory outside production assets; all four `wrapOk`. |
| `python tools/asset-gen/gen.py classes` | Passed; registry printed successfully. |
| `python tools/asset-gen/gen.py runs` | Failed with `error: 'class'` (exit 1). |
| `python tools/asset-gen/gen.py generate wallPiece pipeline_probe ... --dry-run` | Passed; dry-run only, no provider call. |
| `lovec . validate` | Passed: `VALIDATE OK`. |
| `lovec . unittest` | Passed: `ALL UNIT TESTS OK`; includes registered `tests/test_geometry.lua`, with plane, shell, and radial fixture load/compile coverage. |
| `lovec . savetest` | Passed: `SAVETEST OK`. |

The validator emitted its expected sandbox negative-test formula warning for `os.time()` and reported 59 SCRIPT usages. These are baseline observations, not Phase 0 changes.

## Known warnings and assumptions

- `gen.py runs` has an existing CLI/data error because these local staged manifests are pattern manifests, not generation-run manifests: `tools/asset-gen/out/depth-height-patterns/manifest.json`, `tools/asset-gen/out/depth-height-patterns-64/manifest.json`, and `tools/asset-gen/out/depth-height-patterns-v2/manifest.json`. They lack `class`, `name`, and `variants`. No manifest was edited.
- The depth baseline was written only to `%TEMP%\hichaukitoden-phase0-depth`; production PNGs and the tracked production manifest were restored unchanged.
- Existing generated binaries were not modified by this phase.
- Runtime geometry loading was smoke-tested indirectly through the passing validator, unit suite, and save suite; a dedicated per-topology loader command still needs to be identified.

## Phase 0 conclusion

The repository is protected on a dedicated branch, existing work is preserved, and the current health/failure baseline is recorded. Phase 0 exit conditions are satisfied; Phase 1 has not begun.
