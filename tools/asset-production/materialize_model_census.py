#!/usr/bin/env python3
"""Expand and optionally build the Second Rite 100-model census.

The connected repository writer cannot upload the generated binary contact sheets
or schedule a branch-defined workflow. The authored source is therefore stored
as a small, checksum-pinned bootstrap archive. This command expands it safely
into the normal repository paths and can immediately run the test/build gates.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import io
import subprocess
import sys
import tarfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
BOOTSTRAP = ROOT / ".census-bootstrap"
EXPECTED_SHA256 = "9fc9154819e7c8b9f4c92fccb0c74630e4aa095ca5b6634bcb940e914fd4c963"


def safe_extract(payload: bytes) -> None:
    root = ROOT.resolve()
    with tarfile.open(fileobj=io.BytesIO(payload), mode="r:gz") as archive:
        for member in archive.getmembers():
            target = (root / member.name).resolve()
            if target != root and root not in target.parents:
                raise RuntimeError(f"archive member escapes repository: {member.name}")
        archive.extractall(root)


def materialize() -> None:
    parts = sorted(BOOTSTRAP.glob("chunk-*.b64"))
    if not parts:
        raise FileNotFoundError(f"no census bootstrap chunks found in {BOOTSTRAP}")
    encoded = "".join(path.read_text(encoding="ascii") for path in parts)
    payload = base64.b64decode(encoded, validate=True)
    digest = hashlib.sha256(payload).hexdigest()
    if digest != EXPECTED_SHA256:
        raise RuntimeError(
            f"census source checksum mismatch: expected {EXPECTED_SHA256}, got {digest}"
        )
    safe_extract(payload)
    print(f"Expanded census source from {len(parts)} verified chunks.")


def run_build() -> None:
    commands = [
        [
            sys.executable,
            "-m",
            "unittest",
            "discover",
            "-s",
            "tools/asset-production/tests",
            "-p",
            "test_*.py",
            "-v",
        ],
        [sys.executable, "tools/asset-production/build_model_census.py"],
    ]
    for command in commands:
        subprocess.run(command, cwd=ROOT, check=True)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--build",
        action="store_true",
        help="run the census tests and regenerate all models/reports after expansion",
    )
    args = parser.parse_args()
    materialize()
    if args.build:
        run_build()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
