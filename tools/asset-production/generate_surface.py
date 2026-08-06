"""Generate one surface from a production asset-set record and annotate its run."""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

from asset_set import (DEFAULT_SET, ROOT, annotate_run_manifest, get_asset,
                       load_asset_set, surface_generate_command)


def _parser():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("asset", help="surface asset ID from the selected asset set")
    parser.add_argument("--set", dest="asset_set", default=str(DEFAULT_SET))
    parser.add_argument("--variants", type=int)
    parser.add_argument("--provider")
    parser.add_argument("--model")
    parser.add_argument("--quality")
    parser.add_argument("--steps", type=int)
    parser.add_argument("--cfg", type=float)
    parser.add_argument("--sampler")
    parser.add_argument("--seed", type=int)
    parser.add_argument("--depth-weight", type=float)
    parser.add_argument("--prompt-style", choices=("prose", "tags"))
    parser.add_argument("--lora", action="append", default=[])
    parser.add_argument("--dry-run", action="store_true")
    return parser


def main(argv=None):
    args = _parser().parse_args(argv)
    asset_set = load_asset_set(args.asset_set, root=ROOT, check_files=True)
    asset = get_asset(asset_set, args.asset, kind="surface")
    overrides = {
        key: value for key, value in {
            "variants": args.variants, "provider": args.provider,
            "model": args.model, "quality": args.quality, "steps": args.steps,
            "cfg": args.cfg, "sampler": args.sampler, "seed": args.seed,
            "depth_weight": args.depth_weight, "prompt_style": args.prompt_style,
        }.items() if value is not None
    }
    if args.lora:
        overrides["loras"] = args.lora
    command = surface_generate_command(asset, root=ROOT, overrides=overrides)
    if args.dry_run:
        print(json.dumps({"assetId": asset["id"], "command": command}, indent=2))
        return 0

    staged = None
    process = subprocess.Popen(
        command, cwd=ROOT, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        text=True, encoding="utf-8", errors="replace"
    )
    assert process.stdout is not None
    for line in process.stdout:
        print(line, end="")
        stripped = line.strip()
        if stripped.startswith("staged:"):
            staged = stripped.split(":", 1)[1].strip()
    return_code = process.wait()
    if return_code:
        return return_code
    if not staged:
        raise SystemExit("asset-gen completed without reporting a staged run")
    run_path = Path(staged)
    if not run_path.is_absolute():
        run_path = ROOT / run_path
    record = annotate_run_manifest(run_path, asset_set=asset_set, asset=asset, root=ROOT)
    print(json.dumps({
        "kind": "second_rite_surface_generation",
        "assetId": asset["id"],
        "run": str(run_path),
        "productionRecord": record,
    }, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
