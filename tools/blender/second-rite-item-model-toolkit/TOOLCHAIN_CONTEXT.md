# Second Rite Blender Toolchain Context

Read this file first when resuming work in a later conversation.

## Goal

Create many small, fully modeled, low-poly item assets for Second Rite. They are displayed in an orthographic in-game turntable viewport with PS1-like snapping, dithering, affine treatment, nearest filtering, and simple fixed lighting.

## Source-of-truth hierarchy

1. `build_expanded_item_library.py` — procedural model definitions and gallery composition.
2. `second_rite_item_exporter.py` — reusable export behavior.
3. Generated `.blend` — editable working library and embedded copy of the exporter.
4. Generated OBJ/MTL — runtime assets consumed by Hichaukitoden.

## Modeling language

- Blender Z-up.
- Low-poly, flat-shaded silhouettes with selective one-segment bevels.
- Simple material regions that survive OBJ/MTL export (`Kd` and material groups).
- Fully modeled volume; avoid billboard-only item construction.
- Distinct silhouette first, surface detail second.
- Items are authored as child geometry under an Empty root.
- Root location places the item in the gallery; child coordinates describe the item locally.
- Preview panels, labels, camera, and lights are not children of export roots.

## Root metadata

Each export root uses:

```python
root["item_export"] = True
root["item_export_name"] = "snake_case_filename"
root["item_display_name"] = "Human Name"
root["item_category"] = "Category"
root["item_description"] = "Optional description"
```

## Export semantics

- Selecting a root exports that root and all descendants as one OBJ.
- Selecting multiple roots exports one OBJ per top-level selected root.
- The exporter duplicates the hierarchy into a temporary collection.
- It preserves world transforms, then translates the duplicate so the chosen anchor is at the origin.
- The authored scene remains unchanged.
- Shape keys are not stored in OBJ; named keys are baked as separate OBJ variants.

## Expanded baseline

- 49 roots.
- 53 OBJ outputs because Bottle Family produces Basis plus four shape-key variants.
- Output names are listed in `reference/ITEM_MODEL_MANIFEST.md`.
- The initial expanded set covers weapons, armor, accessories, drinks, relics, crafting materials, and promotion keys.

## Important file-name dependency

`build_expanded_item_library.py` imports a sibling file named exactly:

```text
second_rite_item_exporter.py
```

Keep that filename when rebuilding.

## Preview strategy

The final validated CI preview uses Blender Workbench rather than Eevee because GitHub's software-rendered GPU made a large Eevee contact sheet unnecessarily slow. Workbench uses material colors, studio light, shadows, and cavity shading. This changes only the preview; authored materials remain in the `.blend` and OBJ/MTL outputs.

## Future extension pattern

- Add reusable primitives/helpers only when several items benefit.
- Keep item-specific composition in clearly named builder functions.
- Rebuild the whole library after source changes.
- Validate output count, file size, manifest, and preview.
- Promote selected OBJ/MTL files into `Hichaukitoden/assets/models/items/` and add direct `model` paths to `data/items.json`.

## Things deliberately not implemented

- Runtime Blender shape keys or morph targets.
- A model-family registry in game data.
- PBR dependency in the LÖVE runtime.
- Per-item manual camera/scale overrides.
- Generated textures or external asset services.
