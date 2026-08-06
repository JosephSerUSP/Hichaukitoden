#!/usr/bin/env python3
"""Render the Blender depth-map presets into a versioned height-map library.

PRE-PRESS, like heightgen.py and make_height_patterns.py: the output of this is
the height PNG that depth-guided generation is conditioned on, and that
engine/geometry/ later compiles. It emits no mesh for the engine -- the scenes
live in blender/scenes.py as code, so a map can be regenerated from a diff
rather than from a binary nobody can review.

Each preset does also drop a .blend beside its PNG so the geometry can be
opened and examined. Those are an inspection copy, not a source: they are
rebuilt wholesale on every run and nothing reads them back, so an edit made
inside Blender will be silently overwritten -- change scenes.py instead.

    python tools/asset-gen/blendergeom.py                 # all presets
    python tools/asset-gen/blendergeom.py --preset wall_niche --size 1024
    python tools/asset-gen/blendergeom.py --no-blend      # PNGs only

Every map is checked for wrap before it is accepted. A height map that does not
tile is worse than no height map at all: it teaches SD a seam, and the seam then
shows up in every texture generated from it, scored as a material fault.
"""

from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]
SCRIPT = Path(__file__).resolve().parent / "blender" / "render_depth.py"
DEFAULT_OUT = ROOT / "assets" / "geometry" / "1_blender_depth_maps"
sys.path.insert(0, str(ROOT / "tools" / "blender"))
import second_rite_asset_core as asset_core  # noqa: E402

PRESETS = ["wall_pilasters", "wall_niche", "floor_flagstones", "floor_inlay",
           "ceiling_coffers", "ceiling_vault",
           # Organic set, added 03.08: rounder, steeper, per-stone height.
           "wall_rubble", "wall_cave", "floor_cobbles", "floor_slabs_varied",
           "ceiling_dripstone",
           # Displaced set, added 03.08: noise-broken surfaces on the same forms.
           "wall_boulders_rough", "wall_eroded", "floor_cobbles_rough",
           "ceiling_dripstone_rough",
           # Architectural set, added 04.08. The presets above vary how stone is
           # cut and stacked; these vary what the room IS -- an arcade, a fan
           # vault, a floor with a void under it -- which is the axis the owner
           # found missing.
           "wall_blind_arcade", "ceiling_fan_vault", "floor_hypocaust"]

# A tile is accepted when the seam is either an ordinary interior step (ratio)
# or negligible against the relief the map expresses (step). Both are generous
# because a real break is not marginal: the one genuine failure seen so far
# scored 11.7 on ratio and 0.30 on step, while every correct map -- flat
# architecture and organic alike -- came in under 2 and under 0.02.
WRAP_RATIO_TOLERANCE = 3.0
WRAP_STEP_TOLERANCE = 0.03

SEARCH = [
    os.environ.get("BLENDER"),
    r"C:\Program Files\Blender Foundation\Blender 5.1\blender.exe",
    r"C:\Program Files\Blender Foundation\Blender 4.2\blender.exe",
    r"C:\Program Files\Blender Foundation\Blender 4.1\blender.exe",
    "blender",
]


def blender_executable():
    for candidate in SEARCH:
        if candidate and (os.path.isfile(candidate) or candidate == "blender"):
            return candidate
    raise SystemExit("no Blender found; set the BLENDER environment variable")


def render(executable, preset, out_dir, size, contrast, blend=True):
    target = out_dir / f"{preset}.png"
    command = [
        executable, "--background", "--factory-startup",
        "--python", str(SCRIPT), "--",
        "--preset", preset,
        "--out", str(target).replace("\\", "/"),
        "--size", str(size),
        "--contrast", str(contrast),
    ]
    if blend:
        command += ["--blend",
                    str(out_dir / f"{preset}.blend").replace("\\", "/")]
    print(f"  {preset} ...", end="", flush=True)
    result = subprocess.run(command, capture_output=True, text=True)
    for line in result.stdout.splitlines():
        if line.startswith("HEIGHTMAP "):
            record = json.loads(line[len("HEIGHTMAP "):])
            record["wrapOk"] = all(
                seam["ratio"] <= WRAP_RATIO_TOLERANCE
                or seam["step"] <= WRAP_STEP_TOLERANCE
                for seam in record["wrapError"].values())
            seams = " ".join(f"{axis} {seam['ratio']:.2f}/{seam['step']:.3f}"
                             for axis, seam in record["wrapError"].items())
            print(f" {record['surface']:8} tiles {record['tileAxes']:2} "
                  f" relief {record['reliefMin']:+.3f}..{record['reliefMax']:+.3f}"
                  f"  seam {seams}"
                  f"  {'ok' if record['wrapOk'] else 'FAILS TO TILE'}")
            return record
    print(" FAILED")
    sys.stdout.write(result.stdout[-2000:])
    sys.stderr.write(result.stderr[-2000:])
    return None


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preset", action="append", choices=PRESETS,
                        help="repeatable; default is every preset")
    parser.add_argument("--out", default=str(DEFAULT_OUT))
    parser.add_argument("--size", type=int, default=512)
    parser.add_argument("--contrast", type=float, default=1.0)
    parser.add_argument("--no-blend", dest="blend", action="store_false",
                        help="skip the .blend inspection copies")
    args = parser.parse_args()

    out_dir = Path(args.out)
    out_dir.mkdir(parents=True, exist_ok=True)
    executable = blender_executable()
    print(f"blender: {executable}\nout:     {out_dir}\n")

    records, failures = [], 0
    for preset in (args.preset or PRESETS):
        record = render(executable, preset, out_dir, args.size, args.contrast,
                        args.blend)
        if record is None or not record["wrapOk"]:
            failures += 1
        if record:
            records.append(record)

    # Merged, not replaced. A selective `--preset` run would otherwise drop
    # every map it did not render from the manifest, and the room previews read
    # this file to learn which surface a map is for -- so re-rendering one
    # ceiling would silently cost the other ten maps their previews.
    manifest_path = out_dir / "manifest.json"
    new_manifest = not manifest_path.exists()
    merged = {}
    try:
        for record in json.loads(manifest_path.read_text(encoding="utf-8"))["maps"]:
            if (out_dir / f"{record['preset']}.png").is_file():
                merged[record["preset"]] = record
    except (OSError, KeyError, json.JSONDecodeError):
        pass
    for record in records:
        merged[record["preset"]] = record
    manifest = {
        "source": "tools/asset-gen/blender/scenes.py",
        "method": "orthographic first-hit raycast against evaluated geometry",
        "convention": "opaque RGBA, 128 = dominant surface, +-112 relief",
        "maps": [merged[name] for name in sorted(merged)],
    }
    if new_manifest:
        manifest.update({
            "coreVersion": asset_core.CORE_VERSION,
            "contractVersion": asset_core.contract_value("contractVersion"),
            "representation": "plane",
            "role": "surface_material",
            "authoringSpace": "depth_tile",
            "placementFrame": "surface_domain",
            "depthProduct": "depth_guide",
            "metricDepthDeferred": True,
            "defaultMetricRangeCells": 0.25,
        })
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

    print(f"\n{len(records)} map(s) written, {failures} problem(s).")
    return 1 if failures else 0


if __name__ == "__main__":
    raise SystemExit(main())
