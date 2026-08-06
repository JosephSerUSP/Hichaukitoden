import json
from pathlib import Path
try:
    from PIL import Image
except ImportError:
    Image=None
ROOT = Path(__file__).resolve().parents[3]


def diagnostic(kind, path, message):
    """Return a stable structured diagnostic for CLI and test consumers."""
    return {"collection": kind, "path": str(path).replace("\\", "/"),
            "field": "", "message": message}


def walk_models(data, source, node=None, path='$'):
    node = data if node is None else node
    out = []
    if isinstance(node,dict):
        for k, v in node.items():
            out += walk_models(data, source, v, path + "." + k)
        if isinstance(node.get('model'),str) and node['model'].lower().endswith('.obj'): out.append({'source':source,'jsonPath':path+'.model','model':node['model']})
    elif isinstance(node,list):
        for i, v in enumerate(node):
            out += walk_models(data, source, v, f"{path}[{i}]")
    return out
def obj_metrics(root, ref):
    p = root / ref
    vs, uvs, ns = [], [], []
    faces = uses = 0
    lib = None
    for line in p.read_text(encoding='utf-8').splitlines():
        if line.startswith('v '):
            values = line.split()[1:4]
            if len(values) != 3:
                raise ValueError(f"{ref}: malformed vertex")
            vs.append([float(x) for x in values])
        elif line.startswith('vt '):
            uvs.append(line)
        elif line.startswith('vn '):
            ns.append(line)
        elif line.startswith('f '):
            faces += 1
        elif line.startswith('usemtl '):
            uses += 1
        elif line.startswith('mtllib '):
            lib = line.split(None, 1)[1].strip()
    if lib and not (p.parent / lib).is_file():
        raise FileNotFoundError(f"{ref}: missing MTL {lib}")
    bounds = {
        "min": [round(min(v[i] for v in vs), 6) for i in range(3)] if vs else [0, 0, 0],
        "max": [round(max(v[i] for v in vs), 6) for i in range(3)] if vs else [0, 0, 0],
    }
    return {
        "path": str(ref).replace("\\", "/"),
        "vertexCount": len(vs),
        "uvCount": len(uvs),
        "normalCount": len(ns),
        "faceCount": faces,
        "materialUseCount": uses,
        "mtllib": lib,
        "bounds": bounds,
    }


def snapshot(root=ROOT):
    def read(rel):
        path = root / rel
        return json.loads(path.read_text(encoding="utf-8"))

    items = walk_models(read("data/items.json"), "data/items.json")
    worlds = walk_models(read("data/tilesets.json"), "data/tilesets.json")
    refs = sorted(items + worlds, key=lambda x: (x["source"], x["jsonPath"], x["model"]))
    assets = []
    for ap in sorted((root / "assets/geometry").rglob("asset.json")):
        rel = ap.relative_to(root).as_posix()
        try:
            data = json.loads(ap.read_text(encoding="utf-8"))
        except Exception as exc:
            raise ValueError(diagnostic("geometry-json", rel, str(exc))) from exc
        images = []
        for name in ("albedo.png", "height.png"):
            image_path = ap.parent / name
            try:
                with Image.open(image_path) as image:
                    images.append({"path": name, "width": image.width,
                                   "height": image.height, "mode": image.mode})
            except Exception as exc:
                raise ValueError(diagnostic("geometry-image", image_path.relative_to(root), str(exc))) from exc
        assets.append({"assetJson": rel, "id": data.get("id"),
                       "topology": data.get("topology"), "role": data.get("role"),
                       "requiredImages": images})
    manifest = read("assets/geometry/1_blender_depth_maps/manifest.json")
    depths = [{key: entry.get(key) for key in
               ("preset", "surface", "view", "tileAxes", "size", "wrapOk")}
              for entry in manifest.get("maps", [])]
    models = []
    for x in refs:
        if (root / x["model"]).is_file():
            try:
                models.append(obj_metrics(root, x["model"]))
            except Exception as exc:
                raise ValueError(diagnostic("obj", x["model"], str(exc))) from exc
    return {
        "snapshotVersion": 1,
        "sourceCommit": git_commit(root),
        "contractVersion": 1,
        "itemModelReferences": sorted(items, key=lambda x: (x["jsonPath"], x["model"])),
        "worldModelReferences": sorted(worlds, key=lambda x: (x["jsonPath"], x["model"])),
        "geometryAssets": assets,
        "depthPresets": sorted(depths, key=lambda x: x["preset"]),
        "referencedModels": sorted(models, key=lambda x: x["path"]),
    }


def git_commit(root):
    import subprocess
    try: return subprocess.check_output(['git','rev-parse','HEAD'],cwd=root,text=True,stderr=subprocess.DEVNULL).strip()
    except Exception: return None
def compare(root, baseline):
    try:
        current = snapshot(root)
    except Exception as exc:
        return [diagnostic("snapshot", str(root), str(exc))]

    diagnostics = []
    for key in ("itemModelReferences", "worldModelReferences",
                "geometryAssets", "depthPresets", "referencedModels"):
        before = baseline.get(key, [])
        after = current.get(key, [])
        if key in ("itemModelReferences", "worldModelReferences"):
            locations = {(x["source"], x["jsonPath"]): x["model"] for x in after}
            for entry in before:
                location = (entry["source"], entry["jsonPath"])
                if location not in locations:
                    diagnostics.append(diagnostic(key, entry["jsonPath"], "baseline reference removed"))
                elif locations[location] != entry["model"]:
                    diagnostics.append(diagnostic(key, entry["jsonPath"], "model path changed"))
            for entry in after:
                if not (root / entry["model"]).is_file():
                    diagnostics.append(diagnostic(key, entry["model"], "referenced OBJ is missing"))
            continue

        if key == "geometryAssets":
            for entry in before:
                match = next((item for item in after if item["assetJson"] == entry["assetJson"]), None)
                if match is None:
                    diagnostics.append(diagnostic(key, entry["assetJson"], "baseline asset removed"))
                elif match != entry:
                    diagnostics.append(diagnostic(key, entry["assetJson"], "identity or required image metrics changed"))
        elif key == "depthPresets":
            for entry in before:
                match = next((item for item in after if item["preset"] == entry["preset"]), None)
                if match is None:
                    diagnostics.append(diagnostic(key, entry["preset"], "baseline preset removed"))
                elif match != entry or match.get("wrapOk") is not True:
                    diagnostics.append(diagnostic(key, entry["preset"], "semantic fields changed or preset is not wrap-safe"))
            for entry in after:
                if entry.get("wrapOk") is not True and not any(
                        item.get("preset") == entry.get("preset") for item in before):
                    diagnostics.append(diagnostic(key, entry.get("preset"), "new preset is not wrap-safe"))
        else:
            for entry in before:
                match = next((item for item in after if item["path"] == entry["path"]), None)
                if match is None:
                    diagnostics.append(diagnostic(key, entry["path"], "baseline OBJ was removed"))
                elif match != entry:
                    diagnostics.append(diagnostic(key, entry["path"], "OBJ metrics, bounds, or MTL changed"))
    return sorted(diagnostics, key=lambda item: (
        item["collection"], item["path"], item["field"], item["message"]))
