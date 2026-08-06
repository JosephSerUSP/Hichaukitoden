"""Load and validate small production asset sets without replacing the core contract."""
from __future__ import annotations

import hashlib
import json
import os
import re
import sys
from pathlib import Path

ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")
MODULE_RE = re.compile(r"^[a-z][a-z0-9_]*(?:\.[a-z][a-z0-9_]*)+$")
MANIFEST_KIND = "second_rite_asset_set"
MANIFEST_VERSION = 1
RUN_RECORD_VERSION = 1

ROOT = Path(__file__).resolve().parents[2]
DEFAULT_SET = ROOT / "assets" / "authoring" / "first_stratum" / "asset-set.json"


class AssetSetError(ValueError):
    """Raised when a production set cannot be interpreted safely."""


def _json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except FileNotFoundError as exc:
        raise AssetSetError(f"missing JSON file: {path}") from exc
    except json.JSONDecodeError as exc:
        raise AssetSetError(f"malformed JSON in {path}: {exc}") from exc


def repository_path(value, *, root=ROOT, label="path") -> Path:
    path = Path(str(value))
    if path.is_absolute():
        raise AssetSetError(f"{label} must be repository-relative: {value}")
    normalized = Path(os.path.normpath(str(path)))
    if normalized.parts and normalized.parts[0] == "..":
        raise AssetSetError(f"{label} escapes the repository: {value}")
    return Path(root) / normalized


def relative_posix(path: Path, *, root=ROOT) -> str:
    try:
        return path.resolve().relative_to(Path(root).resolve()).as_posix()
    except ValueError:
        return str(path.resolve())


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _ids(mapping):
    return set(mapping.keys()) if isinstance(mapping, dict) else set(mapping or [])


def _validate_common(asset, contract, material_ids):
    asset_id = asset.get("id")
    if not isinstance(asset_id, str) or not ID_RE.fullmatch(asset_id):
        raise AssetSetError(f"asset id must be lower snake case: {asset_id!r}")
    for field, vocabulary in (
        ("representation", _ids(contract.get("representations"))),
        ("role", _ids(contract.get("roles"))),
        ("authoringSpace", _ids(contract.get("authoringSpaces"))),
        ("placementFrame", _ids(contract.get("placementFrames"))),
    ):
        if asset.get(field) not in vocabulary:
            raise AssetSetError(f"{asset_id}: unknown {field} {asset.get(field)!r}")
    states = asset.get("states")
    known_states = set(contract.get("states") or [])
    if not isinstance(states, list) or not states:
        raise AssetSetError(f"{asset_id}: states must be a non-empty list")
    if any(not ID_RE.fullmatch(str(state)) or state not in known_states for state in states):
        raise AssetSetError(f"{asset_id}: invalid semantic state in {states!r}")
    if len(states) != len(set(states)):
        raise AssetSetError(f"{asset_id}: duplicate states")
    if asset.get("defaultState") not in states:
        raise AssetSetError(f"{asset_id}: defaultState must appear in states")
    variants = asset.get("variants")
    if not isinstance(variants, list) or any(not ID_RE.fullmatch(str(item)) for item in variants):
        raise AssetSetError(f"{asset_id}: variants must be lower-snake-case IDs")
    materials = asset.get("materials")
    if not isinstance(materials, list) or not materials:
        raise AssetSetError(f"{asset_id}: materials must be a non-empty list")
    unknown = sorted(set(materials) - material_ids)
    if unknown:
        raise AssetSetError(f"{asset_id}: unknown semantic materials: {', '.join(unknown)}")


def _validate_surface(asset, *, root, check_files):
    asset_id = asset["id"]
    generation = asset.get("generation")
    if not isinstance(generation, dict):
        raise AssetSetError(f"{asset_id}: surface requires generation")
    if generation.get("assetClass") not in {"wallPiece", "texturePiece"}:
        raise AssetSetError(f"{asset_id}: unsupported production surface class")
    if not generation.get("name") or not asset.get("description"):
        raise AssetSetError(f"{asset_id}: surface generation needs name and description")
    if generation.get("promptStyle") not in {"prose", "tags"}:
        raise AssetSetError(f"{asset_id}: promptStyle must be prose or tags")
    weight = generation.get("depthWeight")
    if not isinstance(weight, (int, float)) or not 0 <= weight <= 2:
        raise AssetSetError(f"{asset_id}: depthWeight must be between 0 and 2")
    candidates = generation.get("candidates")
    if not isinstance(candidates, int) or candidates < 1:
        raise AssetSetError(f"{asset_id}: candidates must be a positive integer")
    for field in ("height", "heightMetric"):
        full = repository_path(generation.get(field), root=root, label=f"{asset_id}.{field}")
        if check_files and not full.is_file():
            raise AssetSetError(f"{asset_id}: missing {field}: {full}")
    albedo = (asset.get("products") or {}).get("albedo")
    repository_path(albedo, root=root, label=f"{asset_id}.products.albedo")


def _validate_world_prop(asset, *, root):
    asset_id = asset["id"]
    recipe = asset.get("recipe")
    if not isinstance(recipe, str) or not MODULE_RE.fullmatch(recipe):
        raise AssetSetError(f"{asset_id}: recipe must be a dotted lower-snake-case module")
    if not isinstance(asset.get("parameters"), dict):
        raise AssetSetError(f"{asset_id}: parameters must be an object")
    products = asset.get("products") or {}
    repository_path(products.get("outputRoot"), root=root,
                    label=f"{asset_id}.products.outputRoot")
    state_products = products.get("states")
    if not isinstance(state_products, dict) or set(state_products) != set(asset["states"]):
        raise AssetSetError(f"{asset_id}: products.states must cover every semantic state")
    for state, path in state_products.items():
        repository_path(path, root=root, label=f"{asset_id}.products.states.{state}")


def load_asset_set(path=DEFAULT_SET, *, root=ROOT, check_files=True):
    root = Path(root)
    path = repository_path(path, root=root, label="asset set") if not Path(path).is_absolute() else Path(path)
    data = _json(path)
    if data.get("manifestKind") != MANIFEST_KIND or data.get("manifestVersion") != MANIFEST_VERSION:
        raise AssetSetError(f"unsupported asset-set manifest in {path}")
    if not ID_RE.fullmatch(str(data.get("id", ""))):
        raise AssetSetError("asset-set id must be lower snake case")
    contract = _json(root / "tools" / "asset-language" / "contract.json")
    if data.get("contractVersion") != contract.get("contractVersion"):
        raise AssetSetError("asset-set contractVersion disagrees with contract.json")
    material_registry = _json(root / "tools" / "asset-language" / "materials.json")
    material_ids = {row.get("id") for row in material_registry.get("materials", [])}
    assets = data.get("assets")
    if not isinstance(assets, list) or not assets:
        raise AssetSetError("asset set must contain assets")
    seen = set()
    for asset in assets:
        if not isinstance(asset, dict):
            raise AssetSetError("asset entries must be objects")
        _validate_common(asset, contract, material_ids)
        if asset["id"] in seen:
            raise AssetSetError(f"duplicate asset id: {asset['id']}")
        seen.add(asset["id"])
        if asset.get("kind") == "surface":
            _validate_surface(asset, root=root, check_files=check_files)
        elif asset.get("kind") == "world_prop":
            _validate_world_prop(asset, root=root)
        else:
            raise AssetSetError(f"{asset['id']}: unknown kind {asset.get('kind')!r}")
    data["_path"] = path
    data["_assetsById"] = {asset["id"]: asset for asset in assets}
    return data


def get_asset(asset_set, asset_id, *, kind=None):
    asset = asset_set.get("_assetsById", {}).get(asset_id)
    if asset is None:
        known = ", ".join(sorted(asset_set.get("_assetsById", {})))
        raise AssetSetError(f"unknown asset {asset_id!r}; known: {known}")
    if kind is not None and asset.get("kind") != kind:
        raise AssetSetError(f"{asset_id} is {asset.get('kind')}, not {kind}")
    return asset


def surface_generate_command(asset, *, root=ROOT, overrides=None,
                             python_executable=None):
    if asset.get("kind") != "surface":
        raise AssetSetError(f"{asset.get('id')} is not a surface")
    generation = asset["generation"]
    values = dict(overrides or {})
    command = [
        python_executable or sys.executable,
        "tools/asset-gen/gen.py",
        "generate",
        generation["assetClass"],
        generation["name"],
        asset["description"],
        "--height", generation["height"],
        "--depth-weight", str(values.pop("depth_weight", generation["depthWeight"])),
        "--prompt-style", str(values.pop("prompt_style", generation["promptStyle"])),
        "--variants", str(values.pop("variants", generation["candidates"])),
    ]
    flag_map = (
        ("provider", "--provider"), ("model", "--model"),
        ("quality", "--quality"), ("steps", "--steps"),
        ("cfg", "--cfg"), ("sampler", "--sampler"), ("seed", "--seed"),
    )
    for key, flag in flag_map:
        value = values.pop(key, None)
        if value is not None:
            command.extend([flag, str(value)])
    for lora in values.pop("loras", []) or []:
        command.extend(["--lora", str(lora)])
    if values:
        raise AssetSetError(f"unsupported surface command overrides: {', '.join(sorted(values))}")
    return command


def annotate_run_manifest(run_path, *, asset_set, asset, root=ROOT):
    run_path = Path(run_path)
    manifest_path = run_path / "manifest.json"
    manifest = _json(manifest_path)
    if manifest.get("manifestKind") != "asset_gen_run":
        raise AssetSetError(f"not an asset-gen run manifest: {manifest_path}")
    height_path = repository_path(asset["generation"]["height"], root=root, label="height")
    metric_path = repository_path(asset["generation"]["heightMetric"], root=root,
                                  label="heightMetric")
    record = {
        "version": RUN_RECORD_VERSION,
        "assetSet": asset_set["id"],
        "assetId": asset["id"],
        "sourceRecord": relative_posix(asset_set["_path"], root=root),
        "contractVersion": asset_set["contractVersion"],
        "depthGuide": {
            "path": relative_posix(height_path, root=root),
            "sha256": sha256_file(height_path)
        },
        "heightMetric": {
            "path": relative_posix(metric_path, root=root),
            "sha256": sha256_file(metric_path)
        },
        "intendedProducts": asset.get("products", {})
    }
    previous = manifest.get("productionRecord")
    if previous and previous.get("assetId") != asset["id"]:
        raise AssetSetError(
            f"run already belongs to {previous.get('assetId')}, not {asset['id']}"
        )
    manifest["productionRecord"] = record
    temporary = manifest_path.with_suffix(".json.tmp")
    temporary.write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    os.replace(temporary, manifest_path)
    return record
