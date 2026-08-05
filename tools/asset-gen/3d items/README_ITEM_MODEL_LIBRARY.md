# Second Rite item model library

This Blender file contains five low-poly sample item roots:

- Bottle family with `Tall`, `Round`, `Angular`, and `Molten` shape keys
- Silver blade assembled from child meshes
- Wind charm assembled from child meshes
- Void crystal
- Rotating-item placeholder concept shaped like a question mark

## Using the embedded exporter

1. Open `second_rite_item_model_library.blend` in Blender 5.0 or newer.
2. Switch to the **Scripting** workspace.
3. Open the embedded text `second_rite_item_exporter.py` and press **Run Script**.
4. Open the 3D View sidebar with **N**, then choose **Second Rite → Item OBJ Exporter**.
5. Select one or several item roots and click **Export Selected Items**.

Each top-level selected object is treated as one item. Descendants are included, so a multi-part object should have an Empty or mesh root. If both a root and its child are selected, only the root becomes a separate export.

The exporter duplicates each hierarchy into a temporary collection, subtracts the selected root's world-space pivot from every duplicated part, exports the duplicate, and deletes it. The original object can therefore be placed anywhere in the authoring scene and is not moved or altered.

The default mode uses the root pivot as `(0,0,0)`. A bounds-center option is also included.

When **Export Shape Keys** is enabled, Basis and every named shape key are exported as separate static OBJ files.

The branch workflow rebuilds and validates this library with Blender 5.0.1.
