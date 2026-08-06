"""Launch Blender for one staged world-prop build from an asset-set record."""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
from pathlib import Path

from asset_set import DEFAULT_SET, ROOT, get_asset, load_asset_set


def _parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("asset", help="world_prop asset ID from the selected asset set")
    parser.add_argument("--set", dest="asset_set", default=str(DEFAULT_SET))
    parser.add_argument("--out-dir", default="out/asset-production/world-props")
    parser.add_argument("--state", action="append", default=[])
    parser.add_argument("--blender", default=os.environ.get("BLENDER_BIN", "blender"))
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main(argv=None):
    args = _parser().parse_args(argv)
    asset_set = load_asset_set(args.asset_set, root=ROOT, check_files=True)
    asset = get_asset(asset_set, args.asset, kind="world_prop")
    unknown = sorted(set(args.state) - set(asset["states"]))
    if unknown:
        raise SystemExit(f"unknown state(s) for {asset['id']}: {', '.join(unknown)}")
    set_path = Path(args.asset_set)
    if not set_path.is_absolute():
        set_path = ROOT / set_path
    out_dir = Path(args.out_dir)
    if not out_dir.is_absolute():
        out_dir = ROOT / out_dir
    command = [
        args.blender, "--background", "--factory-startup",
        "--python", str(ROOT / "tools" / "blender" / "build_world_props.py"),
        "--", "--set", str(set_path), "--asset", asset["id"],
        "--out-dir", str(out_dir),
    ]
    for state in args.state:
        command.extend(["--state", state])
    if args.dry_run:
        print(json.dumps({"assetId": asset["id"], "command": command}, indent=2))
        return 0
    if shutil.which(args.blender) is None and not Path(args.blender).is_file():
        raise SystemExit(
            f"Blender executable not found: {args.blender!r}; set BLENDER_BIN or pass --blender"
        )
    return subprocess.call(command, cwd=ROOT)


if __name__ == "__main__":
    raise SystemExit(main())
