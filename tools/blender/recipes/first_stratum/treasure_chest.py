"""Deterministic closed/open First Stratum treasure chest."""
from __future__ import annotations

import math

from .common import box, empty, material, socket_row


def build(*, root, asset, state, core):
    if state not in {"closed", "open"}:
        raise ValueError(f"treasure chest does not support state {state!r}")
    p = asset["parameters"]
    width = float(p["width"])
    depth = float(p["depth"])
    base_height = float(p["baseHeight"])
    lid_height = float(p["lidHeight"])
    bevel = float(p.get("bevel", 0.0))
    wood = material(core, "dark_wood")
    bronze = material(core, "oxidized_bronze")
    gold = material(core, "ritual_gold")

    box("chest_base", root, (width, depth, base_height),
        (0, 0, base_height / 2), wood, core, bevel=bevel)
    for x in (-width * 0.34, width * 0.34):
        box(f"foot_{'l' if x < 0 else 'r'}", root,
            (width * 0.16, depth * 0.9, base_height * 0.14),
            (x, 0, base_height * 0.07), bronze, core, bevel=bevel * 0.5)
    for x in (-width * 0.32, 0.0, width * 0.32):
        box(f"base_band_{x:+.3f}", root,
            (width * 0.075, depth * 1.025, base_height * 1.02),
            (x, 0, base_height / 2), bronze, core, bevel=bevel * 0.35)

    hinge_location = (0.0, -depth / 2, base_height)
    lid_hinge = empty("socket_hinge", root, hinge_location, core, socket_kind="hinge")
    lid_hinge.rotation_euler.x = 0 if state == "closed" else math.radians(-float(p["openAngleDegrees"]))
    box("chest_lid", lid_hinge, (width, depth, lid_height),
        (0, depth / 2, lid_height / 2), wood, core, bevel=bevel)
    for x in (-width * 0.32, 0.0, width * 0.32):
        box(f"lid_band_{x:+.3f}", lid_hinge,
            (width * 0.075, depth * 1.025, lid_height * 1.05),
            (x, depth / 2, lid_height / 2), bronze, core, bevel=bevel * 0.35)
    box("ritual_lock", root, (width * 0.16, depth * 0.055, base_height * 0.28),
        (0, depth / 2 + depth * 0.025, base_height * 0.68), gold, core,
        bevel=bevel * 0.35)

    sockets = [
        socket_row("socket_hinge", "hinge", hinge_location),
        socket_row("socket_interaction", "interaction", (0, depth * 0.66, base_height * 0.7)),
        socket_row("socket_camera_focus", "camera_focus", (0, 0, base_height + lid_height * 0.45)),
        socket_row("socket_loot", "loot", (0, 0, base_height * 0.82)),
    ]
    for row in sockets[1:]:
        empty(row["name"], root, row["location"], core, socket_kind=row["kind"])
    return {"materials": asset["materials"], "sockets": sockets}
