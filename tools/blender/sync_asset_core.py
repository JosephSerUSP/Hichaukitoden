#!/usr/bin/env python3
"""Synchronize canonical Blender contract sources into the portable toolkit."""

from __future__ import annotations

import argparse
import shutil
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
CANONICAL = {
    "second_rite_asset_core.py": ROOT / "tools" / "blender" / "second_rite_asset_core.py",
    "contract.json": ROOT / "tools" / "asset-language" / "contract.json",
    "materials.json": ROOT / "tools" / "asset-language" / "materials.json",
}
VENDOR = ROOT / "tools" / "blender" / "second-rite-item-model-toolkit" / "vendor"


def expected_pairs(canonical=None, vendor=None):
    canonical = CANONICAL if canonical is None else canonical
    vendor = VENDOR if vendor is None else Path(vendor)
    return [(Path(source), vendor / name) for name, source in canonical.items()]


def check_pairs(pairs):
    mismatches = []
    for source, target in pairs:
        if not source.is_file():
            mismatches.append(f"missing canonical file: {source}")
        elif not target.is_file():
            mismatches.append(f"missing vendor file: {target}")
        elif source.read_bytes() != target.read_bytes():
            mismatches.append(f"vendor differs: {target}")
    return mismatches


def sync_pairs(pairs):
    pairs = list(pairs)
    for source, target in pairs:
        if not source.is_file():
            raise SystemExit(f"missing canonical file: {source}")
    pairs[0][1].parent.mkdir(parents=True, exist_ok=True)
    for source, target in pairs:
        shutil.copyfile(source, target)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="check byte parity without writing")
    args = parser.parse_args(argv)
    pairs = expected_pairs()
    mismatches = check_pairs(pairs)
    if args.check:
        if mismatches:
            for mismatch in mismatches:
                print(mismatch)
            return 1
        print("vendor synchronization: passed")
        return 0
    sync_pairs(pairs)
    print("synchronized: " + ", ".join(target.name for _, target in pairs))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
