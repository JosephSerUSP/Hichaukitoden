"""Shared Blender infrastructure for Second Rite asset pipelines.

This module is intentionally portable: it uses Blender modules only inside the
operations that need them, so the host sync and inspection tools can read its
version without importing ``bpy``.  The item toolkit vendors this exact file
for standalone .blend use.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


CORE_VERSION = 1
SUPPORTED_CONTRACT_VERSION = 1
_ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")
_TEXT_CONTRACT = "second_rite_contract.json"
_TEXT_MATERIALS = "second_rite_materials.json"


def _repository_root():
    here = Path(__file__).resolve()
    for parent in (here.parent, *here.parents):
        if (parent / "tools" / "asset-language").is_dir():
            return parent
    return here.parents[2]


def _vendor_root():
    here = Path(__file__).resolve().parent
    if here.name == "vendor":
        return here
    return here / "second-rite-item-model-toolkit" / "vendor"


def _read_json_file(path):
    try:
        return json.loads(Path(path).read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"malformed JSON in {path}: {exc}") from exc
    except OSError as exc:
        raise RuntimeError(f"cannot read {path}: {exc}") from exc


def _text_json(name):
    try:
        import bpy
    except ImportError:
        return None
    text = bpy.data.texts.get(name)
    if text is None:
        return None
    try:
        return json.loads(text.as_string())
    except json.JSONDecodeError as exc:
        raise RuntimeError(f"malformed Blender Text block {name}: {exc}") from exc


def _load_registry(explicit_path, canonical_path, vendor_path, text_name, label):
    if explicit_path is not None:
        return _read_json_file(explicit_path)

    canonical = Path(canonical_path)
    vendor = Path(vendor_path)
    canonical_data = _read_json_file(canonical) if canonical.is_file() else None
    vendor_data = _read_json_file(vendor) if vendor.is_file() else None
    if canonical_data is not None and vendor_data is not None and canonical_data != vendor_data:
        raise RuntimeError(f"canonical and vendor {label} disagree: {canonical} vs {vendor}")
    if canonical_data is not None:
        return canonical_data
    if vendor_data is not None:
        return vendor_data
    embedded = _text_json(text_name)
    if embedded is not None:
        return embedded
    raise RuntimeError(
        f"unable to locate {label}; tried explicit path, {canonical}, {vendor}, "
        f"and Blender Text block {text_name}"
    )


def load_contract(path=None):
    """Load the unified contract using repository, vendor, then Text fallback."""
    data = _load_registry(
        path,
        _repository_root() / "tools" / "asset-language" / "contract.json",
        _vendor_root() / "contract.json",
        _TEXT_CONTRACT,
        "contract",
    )
    if data.get("contractVersion") != SUPPORTED_CONTRACT_VERSION:
        raise RuntimeError(
            f"unsupported asset contract version {data.get('contractVersion')!r}; "
            f"core supports {SUPPORTED_CONTRACT_VERSION}"
        )
    return data


def load_material_registry(path=None):
    """Load the semantic material registry with the same fallback order."""
    data = _load_registry(
        path,
        _repository_root() / "tools" / "asset-language" / "materials.json",
        _vendor_root() / "materials.json",
        _TEXT_MATERIALS,
        "material registry",
    )
    if not isinstance(data.get("materials"), list):
        raise RuntimeError("material registry must contain a materials array")
    return data


def contract_value(path, default=None, contract=None):
    """Read a dotted contract value and return ``default`` when absent."""
    current = load_contract() if contract is None else contract
    for part in str(path).split("."):
        if not isinstance(current, dict) or part not in current:
            return default
        current = current[part]
    return current


def material_definition(material_id, registry=None):
    """Return one semantic material definition or fail on an unknown ID."""
    data = load_material_registry() if registry is None else registry
    for definition in data.get("materials", []):
        if definition.get("id") == material_id:
            return definition
    raise KeyError(f"unknown semantic material ID: {material_id}")


def _bpy():
    import bpy
    return bpy


def reset_scene(*, factory=False):
    """Clear objects/collections and unused data, matching the old builders."""
    bpy = _bpy()
    if factory:
        bpy.ops.wm.read_factory_settings(use_empty=True)
        return
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    for collection in list(bpy.data.collections):
        if collection.name != "Collection":
            bpy.data.collections.remove(collection)
    purge_unused_data()


def purge_unused_data():
    bpy = _bpy()
    for datablocks in (
        bpy.data.meshes, bpy.data.curves, bpy.data.materials,
        bpy.data.cameras, bpy.data.lights,
    ):
        for block in list(datablocks):
            if block.users == 0:
                datablocks.remove(block)


def ensure_collection(name, parent=None):
    bpy = _bpy()
    collection = bpy.data.collections.get(name)
    if collection is None:
        collection = bpy.data.collections.new(name)
        (parent or bpy.context.scene.collection).children.link(collection)
    return collection


def move_to_collection(obj, collection):
    for old_collection in list(obj.users_collection):
        old_collection.objects.unlink(obj)
    collection.objects.link(obj)
    return obj


def remember_selection(context):
    return {
        "selected": [obj.name for obj in context.selected_objects],
        "active": context.view_layer.objects.active.name
        if context.view_layer.objects.active else None,
    }


def restore_selection(context, state):
    bpy = _bpy()
    bpy.ops.object.select_all(action="DESELECT")
    for name in state.get("selected", []):
        obj = bpy.data.objects.get(name)
        if obj is not None:
            obj.select_set(True)
    active_name = state.get("active")
    active = bpy.data.objects.get(active_name) if active_name else None
    if active is not None:
        context.view_layer.objects.active = active


def delete_collection(name):
    bpy = _bpy()
    collection = bpy.data.collections.get(name)
    if collection is None:
        return
    for obj in list(collection.objects):
        data = obj.data
        bpy.data.objects.remove(obj, do_unlink=True)
        if data is not None and getattr(data, "users", 1) == 0:
            for datablocks in (bpy.data.meshes, bpy.data.curves, bpy.data.metaballs):
                if data.name in datablocks:
                    datablocks.remove(data)
                    break
    bpy.data.collections.remove(collection)


def parent_local(obj, root, loc=(0, 0, 0), rot=(0, 0, 0), scale=(1, 1, 1)):
    obj.parent = root
    obj.location = loc
    obj.rotation_euler = rot
    obj.scale = scale
    return obj


def assign_material(obj, material):
    if obj.data is not None and hasattr(obj.data, "materials"):
        obj.data.materials.append(material)
    return obj


def flat_shade(obj):
    if obj.type == "MESH":
        for polygon in obj.data.polygons:
            polygon.use_smooth = False
    return obj


def add_bevel_modifier(obj, width=0.06, segments=1, *, name="LowPolyBevel",
                       angle_degrees=30.0):
    if width <= 0:
        return obj
    modifier = obj.modifiers.new(name, "BEVEL")
    modifier.width = width
    modifier.segments = segments
    modifier.limit_method = "ANGLE"
    modifier.angle_limit = angle_degrees * 3.141592653589793 / 180.0
    return obj


def add_boolean_modifier(target, cutter, operation="DIFFERENCE"):
    modifier = target.modifiers.new(name="bool", type="BOOLEAN")
    modifier.operation = operation
    modifier.object = cutter
    modifier.solver = "EXACT"
    return target


def evaluated_bounds(objects, depsgraph=None):
    from mathutils import Vector
    points = []
    if depsgraph is None:
        depsgraph = _bpy().context.evaluated_depsgraph_get()
    for obj in objects:
        if obj.type not in {"MESH", "CURVE", "SURFACE", "FONT", "META"}:
            continue
        evaluated = obj.evaluated_get(depsgraph)
        points.extend(evaluated.matrix_world @ Vector(corner)
                      for corner in evaluated.bound_box)
    if not points:
        return Vector((0.0, 0.0, 0.0))
    minimum = Vector((min(point.x for point in points),
                      min(point.y for point in points),
                      min(point.z for point in points)))
    maximum = Vector((max(point.x for point in points),
                      max(point.y for point in points),
                      max(point.z for point in points)))
    return (minimum + maximum) * 0.5


def safe_export_name(value):
    value = str(value or "item").strip()
    value = re.sub(r"[^A-Za-z0-9._-]+", "_", value)
    value = re.sub(r"_+", "_", value).strip("_.-")
    return value.lower() or "item"


def _metadata_values(asset_id, representation, role, authoring_space,
                     placement_frame, states, default_state, variants):
    contract = load_contract()
    vocabularies = {
        "representation": contract.get("representations", {}),
        "role": contract.get("roles", {}),
        "authoring_space": contract.get("authoringSpaces", {}),
        "placement_frame": contract.get("placementFrames", {}),
    }
    for name, value in (("representation", representation), ("role", role),
                        ("authoring_space", authoring_space),
                        ("placement_frame", placement_frame)):
        if value not in vocabularies[name]:
            raise ValueError(f"unknown contract {name}: {value!r}")
    if not _ID_RE.fullmatch(str(asset_id)):
        raise ValueError(f"asset ID must be lower snake case: {asset_id!r}")
    if not isinstance(states, list) or not all(_ID_RE.fullmatch(str(x)) for x in states):
        raise ValueError("states must be lower-snake-case IDs")
    if default_state not in states:
        raise ValueError("defaultState must appear in states")
    if not isinstance(variants, list) or not all(_ID_RE.fullmatch(str(x)) for x in variants):
        raise ValueError("variants must be lower-snake-case IDs")
    return {
        "sr_contract_version": contract["contractVersion"],
        "sr_asset_id": str(asset_id),
        "sr_representation": representation,
        "sr_role": role,
        "sr_authoring_space": authoring_space,
        "sr_placement_frame": placement_frame,
        "sr_default_state": default_state,
        "sr_states_json": json.dumps(states, separators=(",", ":")),
        "sr_variants_json": json.dumps(variants, separators=(",", ":")),
    }


def tag_asset_target(target, *, asset_id, representation, role,
                     authoring_space, placement_frame, states=None,
                     default_state="default", variants=None, extra=None):
    """Store validated version-1 contract metadata on a Blender target."""
    values = _metadata_values(
        asset_id, representation, role, authoring_space, placement_frame,
        ["default"] if states is None else states, default_state,
        [] if variants is None else variants,
    )
    for key, value in values.items():
        target[key] = value
    for key, value in (extra or {}).items():
        if not key.startswith("sr_"):
            raise ValueError(f"shared metadata keys must use sr_ prefix: {key}")
        target[key] = value
    return target


def read_asset_metadata(target):
    fields = (
        "sr_contract_version", "sr_asset_id", "sr_representation",
        "sr_role", "sr_authoring_space", "sr_placement_frame",
        "sr_default_state", "sr_states_json", "sr_variants_json",
    )
    return {field: target.get(field) for field in fields if field in target}


def validate_asset_metadata(target):
    required = {
        "sr_contract_version", "sr_asset_id", "sr_representation", "sr_role",
        "sr_authoring_space", "sr_placement_frame", "sr_default_state",
        "sr_states_json", "sr_variants_json",
    }
    missing = sorted(field for field in required if field not in target)
    if missing:
        raise ValueError(f"asset metadata missing: {', '.join(missing)}")
    data = read_asset_metadata(target)
    try:
        states = json.loads(data["sr_states_json"])
        variants = json.loads(data["sr_variants_json"])
    except json.JSONDecodeError as exc:
        raise ValueError("asset state/variant metadata is malformed JSON") from exc
    _metadata_values(
        data["sr_asset_id"], data["sr_representation"], data["sr_role"],
        data["sr_authoring_space"], data["sr_placement_frame"], states,
        data["sr_default_state"], variants,
    )
    return True


def material_defaults(semantic_id=None, registry=None):
    if semantic_id is None:
        return {}
    definition = material_definition(semantic_id, registry)
    return {
        "color": tuple(value / 255.0 for value in definition["baseColorSrgb"]),
        "metallic": definition["metallicHint"],
        "roughness": definition["roughnessHint"],
    }


def make_material(name, *, semantic_id=None, color=None, metallic=None,
                  roughness=None, emission=None, alpha=None, scope=None):
    """Create/update a Principled material without changing explicit values."""
    bpy = _bpy()
    registry = load_material_registry()
    defaults = material_defaults(semantic_id, registry)
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    if mat.get("sr_material_id") not in (None, semantic_id):
        raise ValueError(f"material {name} already has a different semantic ID")
    if semantic_id is not None:
        mat["sr_material_id"] = semantic_id
        mat["sr_material_registry_version"] = registry.get("version")
    mat["sr_material_scope"] = scope or ("semantic_bound" if semantic_id else "legacy_derived")
    explicit_color = color if color is not None else defaults.get("color")
    explicit_metallic = metallic if metallic is not None else defaults.get("metallic", 0.0)
    explicit_roughness = roughness if roughness is not None else defaults.get("roughness", 0.55)
    explicit_alpha = 1.0 if alpha is None else alpha
    mat.diffuse_color = (*explicit_color, explicit_alpha)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf:
        bsdf.inputs["Base Color"].default_value = (*explicit_color, explicit_alpha)
        bsdf.inputs["Metallic"].default_value = explicit_metallic
        bsdf.inputs["Roughness"].default_value = explicit_roughness
        if emission is not None:
            if "Emission Color" in bsdf.inputs:
                bsdf.inputs["Emission Color"].default_value = (*emission, 1.0)
                bsdf.inputs["Emission Strength"].default_value = 1.2
            elif "Emission" in bsdf.inputs:
                bsdf.inputs["Emission"].default_value = (*emission, 1.0)
        if "Alpha" in bsdf.inputs:
            bsdf.inputs["Alpha"].default_value = explicit_alpha
    if explicit_alpha < 1.0 and hasattr(mat, "surface_render_method"):
        mat.surface_render_method = "DITHERED"
    return mat


def material_binding_report(materials):
    bound, unbound = [], []
    for material in materials:
        item = material.get("sr_material_id")
        if item:
            bound.append(item)
        else:
            unbound.append(material.name)
    return {"bound": sorted(bound), "unbound": sorted(unbound),
            "boundCount": len(bound), "unboundCount": len(unbound)}


def mesh_object_from_bmesh(name, bm, collection=None):
    bpy = _bpy()
    mesh = bpy.data.meshes.new(name)
    bm.to_mesh(mesh)
    bm.free()
    obj = bpy.data.objects.new(name, mesh)
    (collection or bpy.context.collection).objects.link(obj)
    return obj


def rotation_matrix(axis, angle):
    from mathutils import Matrix
    return Matrix.Rotation(angle, 4, axis)


def iter_hierarchy(root):
    yield root
    yield from root.children_recursive


def selected_roots(context):
    selected = list(context.selected_objects)
    selected_set = set(selected)
    roots = []
    for obj in selected:
        ancestor = obj.parent
        while ancestor is not None and ancestor not in selected_set:
            ancestor = ancestor.parent
        if ancestor is None:
            roots.append(obj)
    return roots


def marked_roots(context):
    candidates = [obj for obj in context.scene.objects
                  if bool(obj.get("item_export", False))]
    candidate_set = set(candidates)
    roots = []
    for obj in candidates:
        ancestor = obj.parent
        while ancestor is not None and ancestor not in candidate_set:
            ancestor = ancestor.parent
        if ancestor is None:
            roots.append(obj)
    return roots


def _operator_kwargs(operator, candidates):
    rna = operator.get_rna_type()
    supported = {prop.identifier for prop in rna.properties}
    kwargs = {name: value for name, value in candidates.items() if name in supported}
    for prop_name, preferred in (("forward_axis", ("NEGATIVE_Z", "-Z")),
                                ("up_axis", ("Y", "POSITIVE_Y"))):
        if prop_name not in supported:
            continue
        choices = {item.identifier for item in rna.properties[prop_name].enum_items}
        for candidate in preferred:
            if candidate in choices:
                kwargs[prop_name] = candidate
                break
    return kwargs


def export_obj(filepath):
    bpy = _bpy()
    candidates = {
        "filepath": str(filepath), "check_existing": False,
        "export_selected_objects": True, "export_uv": True,
        "export_normals": True, "export_colors": False,
        "export_materials": True, "export_pbr_extensions": False,
        "export_triangulated_mesh": True, "apply_modifiers": True,
        "path_mode": "COPY", "export_object_groups": True,
        "export_material_groups": True, "export_vertex_groups": False,
        "export_smooth_groups": True, "export_smooth_groups_bitflags": False,
    }
    kwargs = _operator_kwargs(bpy.ops.wm.obj_export, candidates)
    result = bpy.ops.wm.obj_export(**kwargs)
    if "FINISHED" not in result:
        raise RuntimeError(f"OBJ export failed for {filepath}: {result}")


def duplicate_hierarchy(context, root, collection_name="__SECOND_RITE_ITEM_EXPORT_TEMP__"):
    bpy = _bpy()
    from mathutils import Matrix
    delete_collection(collection_name)
    temp = bpy.data.collections.new(collection_name)
    context.scene.collection.children.link(temp)
    sources = list(iter_hierarchy(root))
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
    shift = Matrix.Translation(-root.matrix_world.translation)
    for source, duplicate in mapping.items():
        duplicate.matrix_world = shift @ world_matrices[source]
    return temp, mapping[root], list(mapping.values())


def _select_export_geometry(context, objects):
    bpy = _bpy()
    bpy.ops.object.select_all(action="DESELECT")
    geometry = [obj for obj in objects
                if obj.type in {"MESH", "CURVE", "SURFACE", "FONT", "META"}
                and not obj.hide_render]
    for obj in geometry:
        obj.hide_set(False)
        obj.hide_viewport = False
        obj.select_set(True)
    context.view_layer.objects.active = geometry[0] if geometry else None
    return geometry


def _shape_key_names(objects):
    names, seen = [], set()
    for obj in objects:
        if obj.type != "MESH" or obj.data.shape_keys is None:
            continue
        for key in obj.data.shape_keys.key_blocks:
            if key.name != "Basis" and key.name not in seen:
                seen.add(key.name)
                names.append(key.name)
    return names


def _set_shape_variant(objects, active_name):
    for obj in objects:
        if obj.type != "MESH" or obj.data.shape_keys is None:
            continue
        for key in obj.data.shape_keys.key_blocks:
            key.value = 1.0 if active_name is not None and key.name == active_name else 0.0


def export_asset_root(context, root, directory, *, export_shape_keys=False,
                      include_basis=True, center_mode="PIVOT",
                      export_name_property="item_export_name"):
    from mathutils import Matrix
    directory = Path(directory)
    directory.mkdir(parents=True, exist_ok=True)
    selection_state = remember_selection(context)
    outputs = []
    try:
        _temp, _duplicate_root, duplicates = duplicate_hierarchy(context, root)
        geometry = _select_export_geometry(context, duplicates)
        if not geometry:
            raise RuntimeError(f"{root.name} has no exportable geometry")
        if center_mode == "BOUNDS":
            center = evaluated_bounds(geometry, context.evaluated_depsgraph_get())
            shift = Matrix.Translation(-center)
            for obj in duplicates:
                obj.matrix_world = shift @ obj.matrix_world
        export_name = safe_export_name(root.get(export_name_property, root.name))
        shape_names = _shape_key_names(duplicates) if export_shape_keys else []
        variants = [("basis", None)] if shape_names and include_basis else []
        variants += [ (safe_export_name(name), name) for name in shape_names ]
        if not variants:
            variants = [(None, None)]
        for suffix, shape_name in variants:
            _set_shape_variant(duplicates, shape_name)
            context.view_layer.update()
            filename = f"{export_name}__{suffix}.obj" if suffix else f"{export_name}.obj"
            filepath = directory / filename
            export_obj(filepath)
            outputs.append(str(filepath))
        return outputs
    finally:
        delete_collection("__SECOND_RITE_ITEM_EXPORT_TEMP__")
        restore_selection(context, selection_state)


def export_asset_roots(context, roots, directory, **kwargs):
    outputs = []
    for root in roots:
        outputs.extend(export_asset_root(context, root, directory, **kwargs))
    return outputs
