"""Reusable deterministic tiered dais and offering-pedestal recipe."""
from __future__ import annotations

from .common import box, empty, material, socket_row


def build(*, root, asset, state, core):
    if state != "default":
        raise ValueError(f"ritual platform does not support state {state!r}")
    p = asset["parameters"]
    tiers = p["tiers"]
    bevel = float(p.get("bevel", 0.0))
    old_stone = material(core, "old_limestone")
    rough_stone = material(core, "rough_limestone")
    gold = material(core, "ritual_gold")
    z = 0.0
    for index, dimensions in enumerate(tiers):
        width, depth, height = (float(value) for value in dimensions)
        current = old_stone if index % 2 == 0 else rough_stone
        box(f"tier_{index + 1}", root, (width, depth, height),
            (0, 0, z + height / 2), current, core, bevel=bevel)
        z += height
    inlay_w, inlay_d, inlay_h = (float(value) for value in p["topInlay"])
    box("ritual_inlay", root, (inlay_w, inlay_d, inlay_h),
        (0, 0, z + inlay_h / 2), gold, core, bevel=bevel * 0.3)
    sockets = [
        socket_row("socket_interaction", "interaction", (0, 0, z + inlay_h)),
        socket_row("socket_camera_focus", "camera_focus", (0, 0, z * 0.7)),
        socket_row("socket_vfx", "vfx", (0, 0, z + inlay_h * 2)),
    ]
    for row in sockets:
        empty(row["name"], root, row["location"], core, socket_kind=row["kind"])
    return {"materials": asset["materials"], "sockets": sockets}
