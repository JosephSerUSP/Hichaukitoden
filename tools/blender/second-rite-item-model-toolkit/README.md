# Second Rite Item Model Toolkit

A self-contained Blender 5.0+ toolchain for rebuilding and extending the procedural low-poly item library used by **Second Rite**.

This bundle preserves the tools that generated `second_rite_item_model_library_expanded.blend` and its 53 centered OBJ exports. It is intentionally script-first and deterministic: the Python generator is the source of truth, Blender is the compiler, and the `.blend`, OBJ/MTL files, preview, and manifest are generated outputs.

## Contents

- `build_expanded_item_library.py` — procedural authoring source. Builds 49 marked item roots, materials, gallery layout, embedded exporter/readme, preview, manifest, and 53 OBJ results.
- `second_rite_item_exporter.py` — Blender add-on/script. Exports selected or marked top-level roots as individual origin-centered OBJ files without moving the authored scene objects.
- `vendor/` — byte-synchronized standalone copies of the shared core, unified contract, and semantic material registry. Never edit these files manually.
- `BUILD_LIBRARY_WINDOWS.bat` — double-click entry point for Windows.
- `scripts/build_library_windows.ps1` — Windows build, validation, and ZIP packaging.
- `scripts/build_library_linux.sh` — Linux/macOS-style headless build and validation.
- `scripts/inspect_library.py` — Blender-side report for an existing generated `.blend`.
- `github-actions/build-expanded-item-library-original.yml` — exact final GitHub Actions recipe used during generation.
- `github-actions/build-expanded-item-library-portable.yml` — cleaner reusable workflow for a repository that stores these scripts directly.
- `TOOLCHAIN_CONTEXT.md` — compact re-entry notes for a future assistant or collaborator.
- `REPRODUCTION_NOTES.md` — build failures encountered and their fixes.
- `reference/ITEM_MODEL_MANIFEST.md` — catalog from the validated expanded library.
- `TOOLCHAIN_MANIFEST.json` and `SHA256SUMS.txt` — provenance and integrity information.

The canonical infrastructure lives at `tools/blender/second_rite_asset_core.py`.
From the repository root, synchronize or check the toolkit copy with
`python tools/blender/sync_asset_core.py` and
`python tools/blender/sync_asset_core.py --check`.

## Requirements

- Blender **5.0 or newer**.
- No pip packages. Both scripts use Blender's bundled `bpy` and `mathutils` modules.
- Windows: PowerShell 5+ is sufficient for the wrapper.
- Linux headless preview rendering: Mesa/EGL plus Xvfb may be needed.

## Fastest Windows use

1. Extract this toolkit to a writable folder.
2. Double-click `BUILD_LIBRARY_WINDOWS.bat`.
3. The script searches common Blender installation paths and `PATH`.
4. Generated files appear in `output/`.

An explicit Blender path can be supplied from PowerShell:

```powershell
./scripts/build_library_windows.ps1 -BlenderExe "C:\Program Files\Blender Foundation\Blender 5.0\blender.exe"
```

## Direct command

The generator expects `second_rite_item_exporter.py` beside it.

```text
blender --background --python build_expanded_item_library.py
```

Set a custom output directory with `SECOND_RITE_OUT`:

```text
SECOND_RITE_OUT=/path/to/output blender --background --python build_expanded_item_library.py
```

## Using the exporter in Blender

The generated `.blend` contains the exporter as a Text block. It can also be loaded from this toolkit:

1. Open Blender's **Scripting** workspace.
2. Open or paste `second_rite_item_exporter.py`.
3. Run the script.
4. Open **3D View → Sidebar → Second Rite → Item OBJ Exporter**.
5. Select one or more top-level item roots and choose **Export Selected Items**, or choose **Export All Marked Items**.

### Export contract

- Top-level roots carry `item_export = true` and `item_export_name` custom properties.
- Children of a selected root are included as one item.
- Each export uses a temporary duplicate hierarchy.
- Authored scene objects are never moved.
- Root-pivot mode exports the hierarchy as if its root pivot were at `(0,0,0)`.
- Bounds-center mode is also available.
- Shape keys can be baked into separate static files: `__basis`, `__tall`, `__round`, and so on.
- Materials remain simple OBJ/MTL-compatible diffuse groups for the current LÖVE loader.
- Roots also carry version-1 `sr_` item-display metadata. The generated scene
  embeds the exporter, shared core, contract, materials, and readme as Text
  blocks, so standalone copies do not need the repository at export time.
- The exporter first tries normal and real-file sibling-vendor imports. When it
  is executed from a Blender Text block, where `__file__` is absent or not a
  filesystem path, it loads one shared core from the embedded Text block and
  keeps that module in `sys.modules`.

## Editing the library

Prefer editing `build_expanded_item_library.py`, then regenerate. Manual edits to the `.blend` are fine for experimentation, but they are not automatically reflected in the procedural source.

To add an item:

1. Write a builder function using the existing low-poly helpers.
2. Add one `add_item(...)` call near the bottom of the generator.
3. Keep the root at the origin in its own local coordinates; the gallery placement belongs to the root object.
4. Use distinct silhouettes and material regions rather than relying only on recoloring.
5. Update `assert len(items) == ...` and the expected OBJ count if needed.
6. Rebuild and inspect the generated contact sheet.

## Validated baseline

The original expanded library was generated with Blender **5.0.1** and validated for:

- 49 marked roots;
- 53 OBJ outputs;
- a saved `.blend` larger than 100 KB;
- a generated preview and manifest;
- every OBJ existing and containing nontrivial geometry.

See `TOOLCHAIN_CONTEXT.md` before changing architectural assumptions.
