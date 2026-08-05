"""Run inside Blender to inspect a generated Second Rite item library.

Usage:
    blender second_rite_item_model_library_expanded.blend --background \
      --python scripts/inspect_library.py
"""

import bpy

roots = [obj for obj in bpy.context.scene.objects if bool(obj.get("item_export", False))]
roots.sort(key=lambda obj: str(obj.get("item_export_name", obj.name)))

print("=== Second Rite Item Library Report ===")
print(f"Blender: {bpy.app.version_string}")
print(f"File: {bpy.data.filepath or '<unsaved>'}")
print(f"Export roots: {len(roots)}")
print(f"Scene expected_obj_count: {bpy.context.scene.get('expected_obj_count', '<unset>')}")
print(f"Embedded exporter: {'second_rite_item_exporter.py' in bpy.data.texts}")

for root in roots:
    descendants = list(root.children_recursive)
    meshes = [obj for obj in descendants if obj.type == "MESH"]
    shape_keys = []
    for mesh_obj in meshes:
        keys = getattr(mesh_obj.data, "shape_keys", None)
        if keys:
            shape_keys.extend(key.name for key in keys.key_blocks if key.name != "Basis")
    print(
        f"- {root.get('item_export_name', root.name)}: "
        f"{len(meshes)} mesh child(ren), "
        f"shape keys={shape_keys or 'none'}"
    )

if len(roots) != 49:
    raise SystemExit(f"Expected 49 export roots, found {len(roots)}")
