"""Staging area and promote step for tools/asset-gen.

Generated art never lands in assets/ directly. Each run writes a folder under
the (gitignored) staging dir holding the raw model output, the processed sheet
per variant, a contact sheet, and a manifest recording exactly what was asked
for. Promoting copies one chosen variant to its real path -- an explicit,
reviewable action.

This exists because the sibling editor's dev server writes straight into the
repo, and unreviewed writes into a tracked tree have already cost time here.
"""

import datetime
import json
import os
import re
import shutil

from . import classes


def run_dir(staging_root, class_id, name):
    stamp = datetime.datetime.now().strftime("%Y%m%d-%H%M%S")
    safe = re.sub(r"[^\w\-]", "_", str(name)).strip("_") or "unnamed"
    path = os.path.join(staging_root, f"{class_id}-{safe}-{stamp}")
    os.makedirs(path, exist_ok=True)
    return path


def write_manifest(path, data):
    with open(os.path.join(path, "manifest.json"), "w", encoding="utf-8") as handle:
        json.dump(data, handle, indent=2)
        handle.write("\n")


def read_manifest(path):
    with open(os.path.join(path, "manifest.json"), "r", encoding="utf-8") as handle:
        return json.load(handle)


def list_runs(staging_root):
    if not os.path.isdir(staging_root):
        return []
    runs = []
    for entry in sorted(os.listdir(staging_root)):
        full = os.path.join(staging_root, entry)
        if os.path.isfile(os.path.join(full, "manifest.json")):
            runs.append((entry, read_manifest(full)))
    return runs


def resolve_run(staging_root, ref):
    """Accept a run folder name, a path, or 'latest'."""
    if ref in (None, "", "latest"):
        runs = list_runs(staging_root)
        if not runs:
            raise FileNotFoundError("no staged runs; generate something first")
        # list_runs is sorted by name (which leads with the class id); "latest"
        # means most recently written, so pick by mtime instead.
        newest = max(runs, key=lambda r: os.path.getmtime(os.path.join(staging_root, r[0])))
        return os.path.join(staging_root, newest[0])
    if os.path.isdir(ref):
        return ref
    candidate = os.path.join(staging_root, ref)
    if os.path.isdir(candidate):
        return candidate
    raise FileNotFoundError(f"no staged run '{ref}'")


def promote(staging_root, ref, variant, rename, force):
    """Copy one processed variant into its engine path. Returns the destination."""
    path = resolve_run(staging_root, ref)
    manifest = read_manifest(path)

    variants = manifest["variants"]
    if not variants:
        raise RuntimeError(f"{os.path.basename(path)} produced no usable variants")
    chosen = next((v for v in variants if v["index"] == variant), None)
    if chosen is None:
        available = ", ".join(str(v["index"]) for v in variants)
        raise KeyError(f"no variant {variant} in this run (have: {available})")

    ctx = classes.resolve(manifest["class"], manifest.get("options", {}))
    target_name = rename or manifest["name"]
    dest_dir = os.path.join(classes.ROOT, ctx["dir"])
    os.makedirs(dest_dir, exist_ok=True)
    dest = os.path.join(dest_dir, classes.filename(ctx, target_name, manifest.get("tokens")))

    if os.path.exists(dest) and not force:
        raise FileExistsError(f"{dest} already exists (pass --force to overwrite)")

    shutil.copyfile(os.path.join(path, chosen["file"]), dest)
    manifest.setdefault("promoted", []).append({
        "variant": variant,
        "dest": os.path.relpath(dest, classes.ROOT).replace("\\", "/"),
        "at": datetime.datetime.now().isoformat(timespec="seconds"),
    })
    write_manifest(path, manifest)
    return dest
