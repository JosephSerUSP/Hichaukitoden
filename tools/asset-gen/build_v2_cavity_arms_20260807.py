#!/usr/bin/env python3
"""Depth-weight arms for the two v2 fixtures that still read as additive.

The conditioning change fixed the inlay and the collapsed socket outright. The
fissure came back as raised ribbons lying ON the ceiling and the breach socket as
a plastered patch -- both are `replace` fixtures whose field cuts BELOW neutral,
and both were painted as objects added to the surface instead of material removed
from it. The collapsed socket, also `replace` and also below neutral, worked --
the difference is size: a large compact cavity is unambiguous, a thin seam or a
mid-sized wall recess is not.

So this varies the one control that decides how literally the model reads the
depth field, and adds vocabulary that names the sign explicitly.
"""
from __future__ import annotations
import json
from pathlib import Path

TOOL = Path(__file__).resolve().parent
ROOT = TOOL.parents[1]
SRC = TOOL / "batches" / "first_stratum_surface_fixture_v2_20260807.json"
OUT = TOOL / "batches" / "first_stratum_v2_cavity_arms_20260807.json"

TARGETS = {
    "first_stratum_v2_fixture_ceiling_mineral_fissure_thick": dict(
        negative=("tube, pipe, rope, cable, worm, snake, raised ridge, moulding, "
                  "applied trim, extruded shape, object lying on the surface, "
                  "polished marble, glossy stone, specular highlight"),
        extra=("material removed from the ceiling, open void between lips, dark interior, "
               "sunken seam, nothing added on top")),
    "first_stratum_v2_fixture_wall_breach_socket_hugged": dict(
        negative=("plaster patch, repaired render, applied blob, raised boss, bulge, "
                  "swelling, mound, spreading cracks across the wall, "
                  "polished marble, glossy stone, specular highlight"),
        extra=("material missing from the wall, open cavity, shadowed interior recess, "
               "you can see into it, damage confined to one place")),
}
# 0.80/0.76 produced additive reads. Lower weight lets the prompt carry the sign.
ARMS = [("d055", 0.55), ("d040", 0.40)]


def main() -> int:
    src = json.loads(SRC.read_text(encoding="utf-8"))
    jobs = []
    for job in src["jobs"]:
        tweak = TARGETS.get(job["name"])
        if not tweak:
            continue
        for suffix, weight in ARMS:
            arm = dict(job)
            arm["name"] = f"{job['name']}_{suffix}"
            arm["depthWeight"] = weight
            arm["seed"] = job["seed"] + int(weight * 1000)
            arm["negativeExtra"] = job["negativeExtra"] + ", " + tweak["negative"]
            arm["extra"] = job["extra"] + ", " + tweak["extra"]
            jobs.append(arm)
    spec = dict(src)
    spec["batchId"] = "first_stratum_v2_cavity_arms_20260807"
    spec["notes"] = __doc__.strip()
    spec["jobs"] = jobs
    OUT.write_text(json.dumps(spec, indent=2) + "\n", encoding="utf-8")
    print(f"{len(jobs)} jobs -> {OUT.relative_to(ROOT).as_posix()}")
    for j in jobs:
        print(f"  {j['name']:<62} depth {j['depthWeight']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
