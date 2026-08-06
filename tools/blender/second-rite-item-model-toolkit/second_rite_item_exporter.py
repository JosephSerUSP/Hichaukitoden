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
import sys
import types
from pathlib import Path
from bpy.props import BoolProperty, EnumProperty, StringProperty
from bpy.types import Operator, Panel, PropertyGroup

TEMP_COLLECTION_NAME = "__SECOND_RITE_ITEM_EXPORT_TEMP__"


def _load_shared_core():
    module = sys.modules.get("second_rite_asset_core")
    if module is not None:
        return module
    try:
        import second_rite_asset_core
        return second_rite_asset_core
    except ImportError:
        vendor = Path(__file__).resolve().parent / "vendor"
        if vendor.is_dir() and str(vendor) not in sys.path:
            sys.path.insert(0, str(vendor))
        try:
            import second_rite_asset_core
            return second_rite_asset_core
        except ImportError:
            text = bpy.data.texts.get("second_rite_asset_core.py")
            if text is None:
                raise RuntimeError(
                    "second_rite_asset_core.py is not importable and is absent "
                    "from the generated Blender Text blocks"
                )
            module = types.ModuleType("second_rite_asset_core")
            module.__file__ = "<Blender Text: second_rite_asset_core.py>"
            sys.modules["second_rite_asset_core"] = module
            exec(compile(text.as_string(), module.__file__, "exec"), module.__dict__)
            return module


asset_core = _load_shared_core()
_safe_name = asset_core.safe_export_name
_iter_hierarchy = asset_core.iter_hierarchy
_selected_roots = asset_core.selected_roots
_marked_roots = asset_core.marked_roots
_remember_selection = asset_core.remember_selection
_restore_selection = asset_core.restore_selection
_delete_temp_collection = lambda: asset_core.delete_collection(TEMP_COLLECTION_NAME)
_duplicate_hierarchy = lambda context, root: asset_core.duplicate_hierarchy(
    context, root, TEMP_COLLECTION_NAME)
_bounds_center_world = asset_core.evaluated_bounds
_shape_key_names = asset_core._shape_key_names
_set_shape_variant = asset_core._set_shape_variant
_operator_kwargs = asset_core._operator_kwargs
_export_obj = asset_core.export_obj
_select_export_geometry = asset_core._select_export_geometry


def export_item_root(context, root, directory, *, export_shape_keys=False, include_basis=True, center_mode="PIVOT"):
    return asset_core.export_asset_root(
        context, root, directory,
        export_shape_keys=export_shape_keys,
        include_basis=include_basis,
        center_mode=center_mode,
    )


def export_roots(context, roots, directory, *, export_shape_keys=False, include_basis=True, center_mode="PIVOT"):
    return asset_core.export_asset_roots(
        context, roots, directory,
        export_shape_keys=export_shape_keys,
        include_basis=include_basis,
        center_mode=center_mode,
    )


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
