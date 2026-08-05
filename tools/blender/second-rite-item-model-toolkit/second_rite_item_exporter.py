bl_info = {
    "name": "Second Rite Item OBJ Exporter",
    "author": "OpenAI for JosephSerUSP",
    "version": (1, 0, 0),
    "blender": (5, 0, 0),
    "location": "View3D > Sidebar > Second Rite",
    "description": "Export selected or marked item roots as individual origin-centered OBJ files",
    "category": "Import-Export",
}

import bpy
import os
import re
from pathlib import Path
from mathutils import Matrix, Vector
from bpy.props import BoolProperty, EnumProperty, StringProperty
from bpy.types import Operator, Panel, PropertyGroup

SUPPORTED_TYPES = {"MESH", "CURVE", "SURFACE", "FONT", "META"}
TEMP_COLLECTION_NAME = "__SECOND_RITE_ITEM_EXPORT_TEMP__"


def _safe_name(value: str) -> str:
    value = str(value or "item").strip()
    value = re.sub(r"[^A-Za-z0-9._-]+", "_", value)
    value = re.sub(r"_+", "_", value).strip("_.-")
    return value.lower() or "item"


def _iter_hierarchy(root):
    yield root
    for child in root.children_recursive:
        yield child


def _selected_roots(context):
    selected = list(context.selected_objects)
    selected_set = set(selected)
    roots = []
    for obj in selected:
        ancestor = obj.parent
        has_selected_ancestor = False
        while ancestor is not None:
            if ancestor in selected_set:
                has_selected_ancestor = True
                break
            ancestor = ancestor.parent
        if not has_selected_ancestor:
            roots.append(obj)
    return roots


def _marked_roots(context):
    candidates = [obj for obj in context.scene.objects if bool(obj.get("item_export", False))]
    candidate_set = set(candidates)
    roots = []
    for obj in candidates:
        ancestor = obj.parent
        has_marked_ancestor = False
        while ancestor is not None:
            if ancestor in candidate_set:
                has_marked_ancestor = True
                break
            ancestor = ancestor.parent
        if not has_marked_ancestor:
            roots.append(obj)
    return roots


def _remember_selection(context):
    return {
        "selected": [obj.name for obj in context.selected_objects],
        "active": context.view_layer.objects.active.name if context.view_layer.objects.active else None,
    }


def _restore_selection(context, state):
    bpy.ops.object.select_all(action="DESELECT")
    for name in state["selected"]:
        obj = bpy.data.objects.get(name)
        if obj is not None and obj.name in context.view_layer.objects:
            obj.select_set(True)
    active = bpy.data.objects.get(state["active"]) if state["active"] else None
    if active is not None and active.name in context.view_layer.objects:
        context.view_layer.objects.active = active


def _delete_temp_collection():
    collection = bpy.data.collections.get(TEMP_COLLECTION_NAME)
    if collection is None:
        return
    objects = list(collection.objects)
    for obj in objects:
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and getattr(data, "users", 1) == 0:
            for datablocks in (
                bpy.data.meshes,
                bpy.data.curves,
                bpy.data.metaballs,
            ):
                try:
                    if data.name in datablocks:
                        datablocks.remove(data)
                        break
                except TypeError:
                    pass
    bpy.data.collections.remove(collection)


def _duplicate_hierarchy(context, root):
    _delete_temp_collection()
    temp = bpy.data.collections.new(TEMP_COLLECTION_NAME)
    context.scene.collection.children.link(temp)

    sources = list(_iter_hierarchy(root))
    mapping = {}
    world_matrices = {source: source.matrix_world.copy() for source in sources}

    for source in sources:
        duplicate = source.copy()
        if source.data is not None:
            duplicate.data = source.data.copy()
        duplicate.animation_data_clear()
        temp.objects.link(duplicate)
        mapping[source] = duplicate

    for source, duplicate in mapping.items():
        duplicate.parent = mapping.get(source.parent)
        duplicate.matrix_parent_inverse = source.matrix_parent_inverse.copy()
        duplicate.matrix_world = world_matrices[source]

    anchor = root.matrix_world.translation.copy()
    shift = Matrix.Translation(-anchor)
    for source, duplicate in mapping.items():
        duplicate.matrix_world = shift @ world_matrices[source]

    return temp, mapping[root], list(mapping.values())


def _bounds_center_world(objects, depsgraph):
    points = []
    for obj in objects:
        if obj.type not in SUPPORTED_TYPES:
            continue
        evaluated = obj.evaluated_get(depsgraph)
        for corner in evaluated.bound_box:
            points.append(evaluated.matrix_world @ Vector(corner))
    if not points:
        return Vector((0.0, 0.0, 0.0))
    minimum = Vector((min(p.x for p in points), min(p.y for p in points), min(p.z for p in points)))
    maximum = Vector((max(p.x for p in points), max(p.y for p in points), max(p.z for p in points)))
    return (minimum + maximum) * 0.5


def _shape_key_names(objects):
    names = []
    seen = set()
    for obj in objects:
        if obj.type != "MESH" or obj.data.shape_keys is None:
            continue
        for key in obj.data.shape_keys.key_blocks:
            if key.name == "Basis" or key.name in seen:
                continue
            seen.add(key.name)
            names.append(key.name)
    return names


def _set_shape_variant(objects, active_name):
    for obj in objects:
        if obj.type != "MESH" or obj.data.shape_keys is None:
            continue
        for key in obj.data.shape_keys.key_blocks:
            key.value = 1.0 if active_name is not None and key.name == active_name else 0.0


def _operator_kwargs(operator, candidates):
    rna = operator.get_rna_type()
    supported = {prop.identifier for prop in rna.properties}
    kwargs = {name: value for name, value in candidates.items() if name in supported}

    for prop_name, preferred in (
        ("forward_axis", ("NEGATIVE_Z", "-Z")),
        ("up_axis", ("Y", "POSITIVE_Y")),
    ):
        if prop_name not in supported:
            continue
        prop = rna.properties[prop_name]
        choices = {item.identifier for item in prop.enum_items}
        for candidate in preferred:
            if candidate in choices:
                kwargs[prop_name] = candidate
                break
    return kwargs


def _export_obj(filepath):
    candidates = {
        "filepath": str(filepath),
        "check_existing": False,
        "export_selected_objects": True,
        "export_uv": True,
        "export_normals": True,
        "export_colors": False,
        "export_materials": True,
        "export_pbr_extensions": False,
        "export_triangulated_mesh": True,
        "apply_modifiers": True,
        "path_mode": "COPY",
        "export_object_groups": True,
        "export_material_groups": True,
        "export_vertex_groups": False,
        "export_smooth_groups": True,
        "export_smooth_groups_bitflags": False,
    }
    kwargs = _operator_kwargs(bpy.ops.wm.obj_export, candidates)
    result = bpy.ops.wm.obj_export(**kwargs)
    if "FINISHED" not in result:
        raise RuntimeError(f"OBJ export failed for {filepath}: {result}")


def _select_export_geometry(context, objects):
    bpy.ops.object.select_all(action="DESELECT")
    geometry = [obj for obj in objects if obj.type in SUPPORTED_TYPES and not obj.hide_render]
    for obj in geometry:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.select_set(True)
    context.view_layer.objects.active = geometry[0] if geometry else None
    return geometry


def export_item_root(context, root, directory, *, export_shape_keys=False, include_basis=True, center_mode="PIVOT"):
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    selection_state = _remember_selection(context)
    outputs = []

    try:
        _temp, duplicate_root, duplicates = _duplicate_hierarchy(context, root)
        geometry = _select_export_geometry(context, duplicates)
        if not geometry:
            raise RuntimeError(f"{root.name} has no exportable geometry")

        if center_mode == "BOUNDS":
            center = _bounds_center_world(geometry, context.evaluated_depsgraph_get())
            shift = Matrix.Translation(-center)
            for obj in duplicates:
                obj.matrix_world = shift @ obj.matrix_world

        export_name = _safe_name(root.get("item_export_name", root.name))
        shape_names = _shape_key_names(duplicates) if export_shape_keys else []
        variants = []
        if shape_names:
            if include_basis:
                variants.append(("basis", None))
            variants.extend((_safe_name(name), name) for name in shape_names)
        else:
            variants.append((None, None))

        for suffix, shape_name in variants:
            _set_shape_variant(duplicates, shape_name)
            context.view_layer.update()
            filename = f"{export_name}__{suffix}.obj" if suffix else f"{export_name}.obj"
            filepath = directory / filename
            _export_obj(filepath)
            outputs.append(str(filepath))

        return outputs
    finally:
        _delete_temp_collection()
        _restore_selection(context, selection_state)


def export_roots(context, roots, directory, *, export_shape_keys=False, include_basis=True, center_mode="PIVOT"):
    outputs = []
    for root in roots:
        outputs.extend(export_item_root(
            context,
            root,
            directory,
            export_shape_keys=export_shape_keys,
            include_basis=include_basis,
            center_mode=center_mode,
        ))
    return outputs


def _resolved_directory(context):
    settings = context.scene.second_rite_item_export
    raw = settings.directory or "//exports/items"
    return bpy.path.abspath(raw)


class SecondRiteItemExportSettings(PropertyGroup):
    directory: StringProperty(
        name="Export Directory",
        subtype="DIR_PATH",
        default="//exports/items",
    )
    export_shape_keys: BoolProperty(
        name="Export Shape Keys",
        description="Export Basis and every named shape key as separate OBJ files",
        default=True,
    )
    include_basis: BoolProperty(
        name="Include Basis",
        default=True,
    )
    center_mode: EnumProperty(
        name="Center Using",
        items=(
            ("PIVOT", "Root Pivot", "Move the selected root object's world-space pivot to 0,0,0"),
            ("BOUNDS", "Bounds Center", "Center the complete evaluated hierarchy by its bounds"),
        ),
        default="PIVOT",
    )


class SECOND_RITE_OT_export_selected_items(Operator):
    bl_idname = "second_rite.export_selected_items"
    bl_label = "Export Selected Items"
    bl_options = {"REGISTER"}

    def execute(self, context):
        settings = context.scene.second_rite_item_export
        roots = _selected_roots(context)
        if not roots:
            self.report({"ERROR"}, "Select at least one item root")
            return {"CANCELLED"}
        try:
            outputs = export_roots(
                context,
                roots,
                _resolved_directory(context),
                export_shape_keys=settings.export_shape_keys,
                include_basis=settings.include_basis,
                center_mode=settings.center_mode,
            )
        except Exception as exc:
            self.report({"ERROR"}, str(exc))
            raise
        self.report({"INFO"}, f"Exported {len(outputs)} OBJ file(s)")
        return {"FINISHED"}


class SECOND_RITE_OT_export_marked_items(Operator):
    bl_idname = "second_rite.export_marked_items"
    bl_label = "Export All Marked Items"
    bl_options = {"REGISTER"}

    def execute(self, context):
        settings = context.scene.second_rite_item_export
        roots = _marked_roots(context)
        if not roots:
            self.report({"ERROR"}, "No objects have the item_export custom property")
            return {"CANCELLED"}
        outputs = export_roots(
            context,
            roots,
            _resolved_directory(context),
            export_shape_keys=settings.export_shape_keys,
            include_basis=settings.include_basis,
            center_mode=settings.center_mode,
        )
        self.report({"INFO"}, f"Exported {len(outputs)} OBJ file(s)")
        return {"FINISHED"}


class SECOND_RITE_PT_item_exporter(Panel):
    bl_label = "Item OBJ Exporter"
    bl_idname = "SECOND_RITE_PT_item_exporter"
    bl_space_type = "VIEW_3D"
    bl_region_type = "UI"
    bl_category = "Second Rite"

    def draw(self, context):
        layout = self.layout
        settings = context.scene.second_rite_item_export
        layout.prop(settings, "directory")
        layout.prop(settings, "center_mode")
        layout.prop(settings, "export_shape_keys")
        row = layout.row()
        row.enabled = settings.export_shape_keys
        row.prop(settings, "include_basis")
        layout.separator()
        layout.operator("second_rite.export_selected_items", icon="EXPORT")
        layout.operator("second_rite.export_marked_items", icon="FILE_TICK")
        layout.separator()
        layout.label(text="Multi-part item: select its root only.", icon="INFO")


CLASSES = (
    SecondRiteItemExportSettings,
    SECOND_RITE_OT_export_selected_items,
    SECOND_RITE_OT_export_marked_items,
    SECOND_RITE_PT_item_exporter,
)


def register():
    for cls in CLASSES:
        try:
            bpy.utils.register_class(cls)
        except ValueError:
            pass
    if not hasattr(bpy.types.Scene, "second_rite_item_export"):
        bpy.types.Scene.second_rite_item_export = bpy.props.PointerProperty(type=SecondRiteItemExportSettings)


def unregister():
    if hasattr(bpy.types.Scene, "second_rite_item_export"):
        del bpy.types.Scene.second_rite_item_export
    for cls in reversed(CLASSES):
        try:
            bpy.utils.unregister_class(cls)
        except RuntimeError:
            pass


if __name__ == "__main__":
    register()
