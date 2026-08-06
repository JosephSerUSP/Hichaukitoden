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
import subprocess

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

RUN_KIND, RUN_VERSION = "asset_gen_run", 1
def classify_manifest(data):
    if not isinstance(data, dict): return "other", ["manifest is not an object"]
    if data.get("manifestKind") == RUN_KIND:
        missing=[k for k in ("class","name","variants") if k not in data or (k != "variants" and not isinstance(data[k],str)) or (k == "variants" and not isinstance(data[k],list))]
        return ("invalid_run",missing) if missing else ("run",[])
    if data.get("manifestKind"): return "other",[]
    if any(k in data for k in ("class","name","variants")):
        missing=[k for k in ("class","name","variants") if k not in data or (k != "variants" and not isinstance(data[k],str)) or (k == "variants" and not isinstance(data[k],list))]
        return ("invalid_run",missing) if missing else ("run",[])
    return "other",[]
def scan_runs(staging_root):
    runs=[]; ignored=0
    if not os.path.isdir(staging_root): return runs,ignored
    for entry in sorted(os.listdir(staging_root)):
        full=os.path.join(staging_root,entry); mp=os.path.join(full,"manifest.json")
        if not os.path.isfile(mp): continue
        try: data=read_manifest(full)
        except Exception as e: raise RuntimeError(f"malformed manifest {mp}: {e}")
        kind, detail=classify_manifest(data)
        if kind=="run": runs.append((entry,data))
        elif kind=="invalid_run": raise RuntimeError(f"invalid asset-generation manifest {mp}; missing {', '.join(detail)}")
        else: ignored+=1
    return runs,ignored


def read_manifest(path):
    with open(os.path.join(path, "manifest.json"), "r", encoding="utf-8") as handle:
        return json.load(handle)


def list_runs(staging_root):
    return scan_runs(staging_root)[0]


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
        kind, _ = classify_manifest(read_manifest(ref))
        if kind != "run": raise RuntimeError(f"not an asset-generation run: {ref}")
        return ref
    candidate = os.path.join(staging_root, ref)
    if os.path.isdir(candidate):
        kind, _ = classify_manifest(read_manifest(candidate))
        if kind != "run": raise RuntimeError(f"not an asset-generation run: {candidate}")
        return candidate
    raise FileNotFoundError(f"no staged run '{ref}'")


def _edited_by_hand(path):
    """Does this tracked file have uncommitted changes?

    The guard on automatic promotion. Art here gets hand-corrected between runs,
    and a generator that overwrites a file someone has been editing destroys work
    that exists nowhere else -- which has already happened twice on this project.
    Git is the authority: if the file is clean, the worst an overwrite can cost
    is a `git checkout`.

    Unknown answers are treated as SAFE-to-write rather than blocking, since an
    untracked new asset is the normal case for generation; the plain existence
    check above already covers overwriting.
    """
    try:
        result = subprocess.run(
            ["git", "status", "--porcelain", "--", path],
            cwd=classes.ROOT, capture_output=True, text=True, timeout=20)
    except (OSError, subprocess.SubprocessError):
        return False
    if result.returncode != 0:
        return False
    for line in result.stdout.splitlines():
        # "?? path" is untracked -- new, so nothing to lose.
        if line[:2].strip() and not line.startswith("??"):
            return True
    return False


def promote(staging_root, ref, variant, rename, force, force_dirty=False):
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
    dest = os.path.join(dest_dir, classes.filename(ctx, target_name, manifest.get("tokens")))
    # dirname(dest), not dest_dir: a class whose filename carries a folder --
    # "{name}/albedo.png" for image-authored geometry -- lands one level deeper.
    os.makedirs(os.path.dirname(dest), exist_ok=True)

    if os.path.exists(dest) and not force:
        raise FileExistsError(f"{dest} already exists (pass --force to overwrite)")
    if os.path.exists(dest) and force and not force_dirty and _edited_by_hand(dest):
        raise RuntimeError(
            f"{os.path.relpath(dest, classes.ROOT)} has uncommitted changes -- it has "
            "been edited since it was last committed, and promoting would destroy that "
            "work. Commit or discard it first, or pass --force-dirty if you mean it.")

    shutil.copyfile(os.path.join(path, chosen["file"]), dest)
    manifest.setdefault("promoted", []).append({
        "variant": variant,
        "dest": os.path.relpath(dest, classes.ROOT).replace("\\", "/"),
        "at": datetime.datetime.now().isoformat(timespec="seconds"),
    })
    write_manifest(path, manifest)
    return dest
