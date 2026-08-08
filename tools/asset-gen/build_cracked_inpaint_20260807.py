#!/usr/bin/env python3
"""Cracked variants inpainted into albedos the owner already approved.

Every "cracked" surface so far was generated from scratch against a fractured
height map, which means the model invented both the stone AND the damage. The
cracked tile and the intact tile it sits beside therefore share a prompt but not
a material: different stone colour, different mortar tone, different wear. Placed
in adjacent cells they read as two different walls, and no amount of prompt
matching fixes it, because the model never saw the original.

Here the untouched region IS the approved albedo, pixel for pixel, and only the
fracture is repainted. The crack is synthesised knowing exactly what it breaks.
The authored height map still travels as ControlNet guidance so the fracture keeps
its designed shape -- depth map AND base tile, not one instead of the other.

Tiling here means something stricter than usual, and getting it wrong is invisible
until two tiles meet in a map. A variant lives in the same weighted pool as the
tile it is a variant OF, so the engine places the cracked wall directly beside the
intact one: the cracked tile has to tile with its BASE, not merely with copies of
itself. A toroidal crack network satisfies the weaker property and fails this one.
So all damage is confined to the interior, the tiling borders keep the original
pixels exactly, and that equality is asserted rather than hoped for.

Sources are chosen from reviews/ratings.json rather than named here: the material
a crack is cut into should be one the owner scored highly, and the store is the
only record of that.
"""
from __future__ import annotations

import argparse
import collections
import datetime as dt
import io
import json
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import classes, provider, staging  # noqa: E402
import build_surface_fixture_batch_20260806 as base  # noqa: E402
import build_fractured_baselines_20260807 as frac  # noqa: E402
import gen  # noqa: E402

ROOT = Path(classes.ROOT)
TOOL = ROOT / "tools" / "asset-gen"
OUT = TOOL / "out"
FORGE = "http://127.0.0.1:7860"
SUMMARY = OUT / "cracked-inpaint-20260807-summary.json"

# Each entry: the intact surface to crack, and how to crack it. `run` is resolved
# against the ratings store so a poorly-scored source can never be used silently.
TARGETS = [
    dict(id="flagstones", surface="floor", cls="texturePiece",
         run_contains="first_stratum_prod_damp_masonry_floor_flagstones_v2",
         seed=381100, cells=6, share=0.24, depth=0.32,
         prompt=("worn damp limestone flagstone paving, several slabs split by open "
                 "cracks with crumbling edges and dark interiors, broken stone, "
                 "orthographic floor material seen from directly above")),
    dict(id="slabs", surface="floor", cls="texturePiece",
         run_contains="first_stratum_rich_floor_slabs_varied_restrained",
         seed=381200, cells=5, share=0.26, depth=0.30,
         prompt=("cool muted slate and limestone slab floor, several slabs split by "
                 "open fractures with crumbling lips and dark interiors, broken "
                 "stone, orthographic floor material seen from directly above")),
    dict(id="coffers", surface="ceiling", cls="texturePiece",
         run_contains="first_stratum_rich_ceiling_wide_coffers",
         seed=381300, cells=4, share=0.22, depth=0.30,
         prompt=("aged limestone coffered ceiling, one region split by open structural "
                 "cracks with crumbling lips and dark interiors, intact coffers "
                 "elsewhere, orthographic ceiling material")),
    dict(id="ashlar", surface="wall", cls="wallPiece",
         run_contains="first_stratum_rich_wall_broad_ashlar_courses",
         seed=381400, cells=5, share=0.28, depth=0.26,
         prompt=("old fitted limestone ashlar wall, fracture lines running across "
                 "several blocks, split stone faces with chipped crumbling edges and "
                 "dark crack interiors, quiet undercroft wall material")),
]


class SourcePruned(RuntimeError):
    """The material was approved once but its pixels are gone."""


NEGATIVE = ("mosaic, tile pattern, crazy paving, grout, mortar joints between separate "
            "tiles, inlay, deliberate stonework pattern, new stonework, repaired render, "
            "raised ridge, tube, pipe, moulding, applied trim, object lying on the "
            "surface, perspective, camera view, scene, framed picture, diagram labels")


def best_variant(run_contains: str):
    """The highest-scored variant we can still inpaint into, and what it scored.

    "Still" is the operative word. A rating outlives its pixels: the store is
    tracked, `out/` is not, so the highest-scored source can easily be a run whose
    images were pruned months ago. The 64px exemplar kept beside the rating is a
    receipt, not a source -- inpainting needs the 512px raw.

    So this walks the scores downward and takes the best one whose raw file is
    actually on disk, and says out loud when it had to skip a better score. Silent
    substitution would mean cutting a crack into material the owner never approved
    while reporting the score of one they did.
    """
    store = json.loads((TOOL / "reviews" / "ratings.json").read_text(encoding="utf-8"))
    scored = collections.defaultdict(list)
    for key, row in store.items():
        if run_contains not in key or not row.get("score"):
            continue
        run, index = key.rsplit("#", 1)
        scored[run].append((int(row["score"]), int(index)))
    if not scored:
        raise SystemExit(f"no owner ratings for any run matching {run_contains!r}; "
                         "a crack must be cut into material that was actually approved")
    ranked = sorted(((max(v), r) for r, v in scored.items()), reverse=True)
    skipped = []
    for (score, index), run in ranked:
        if (OUT / run / f"raw-{index}.png").is_file():
            for other in skipped:
                print(f"    note: skipped {other[1]}#{other[0][1]} (score {other[0][0]}) "
                      f"-- its raw image is no longer in out/")
            return run, index, score
        skipped.append(((score, index), run))
    raise SourcePruned(
        f"every rated run matching {run_contains!r} has been pruned from out/; "
        "re-render one before inpainting into it")


def tile_axes_for(surface: str) -> str:
    return "x" if surface == "wall" else "xy"


def interior_only(mask: np.ndarray, axes: str, margin: int) -> np.ndarray:
    """Clear the mask near every tiling border.

    A VARIANT has to tile with the tile it is a variant OF, not merely with
    itself. Both are in the same weighted pool, so the engine will place the
    cracked wall directly beside the intact one and their shared edge has to
    match. A toroidal crack network satisfies the weaker property -- it wraps
    against its own opposite edge -- and fails this one, because the intact tile
    has no crack at that border. The result tiles perfectly with copies of itself
    and visibly breaks against its own base.

    So damage is confined to the interior and the border stays the original
    pixels, exactly. This also makes the offset seam pass unnecessary: nothing
    crosses the wrap, so there is no join to repair.

    Only the axes that actually tile are protected. A wall wraps on x, so its
    left and right edges are frozen while its top and bottom are free.
    """
    out = mask.copy()
    size = out.shape[0]
    if "x" in axes:
        out[:, :margin] = False
        out[:, size - margin:] = False
    if "y" in axes:
        out[:margin, :] = False
        out[size - margin:, :] = False
    return out


def crack_inputs(target: dict, size: int, axes: str):
    """The fracture mask and the signed height field for one target."""
    mask = frac.fracture_mask(size, target["seed"], cells=target["cells"],
                              fragment_share=target["share"])
    # 6% of the tile: wide enough that mask blur and the VAE round-trip cannot
    # reach the frozen border, since a repainted border is a broken border even
    # if the crack itself stopped short of it.
    mask = interior_only(mask, axes, margin=max(12, int(size * 0.06)))
    field = frac.cut_fracture(np.zeros((size, size)), mask,
                              depth=target["depth"] * 0.6, lip=0.03)
    return mask, np.clip(field, -1.0, 1.0)


def run_one(target: dict, options: dict, force: bool) -> dict:
    run, index, score = best_variant(target["run_contains"])
    source_dir = OUT / run
    raw = source_dir / f"raw-{index}.png"
    if not raw.is_file():
        raise SystemExit(f"{raw} is missing; cannot inpaint into it")
    init = Image.open(raw).convert("RGB")
    size = init.width
    axes = tile_axes_for(target["surface"])

    mask_bool, field = crack_inputs(target, size, axes)
    mask = Image.fromarray((mask_bool * 255).astype(np.uint8), mode="L")
    # The control map is the crack alone over neutral: the intact relief is
    # already present in the init image, and asking ControlNet to also restate it
    # would fight the pixels it is supposed to preserve.
    control_grey = np.clip(np.rint(base.NEUTRAL + field * 127.0), 0, 255).astype(np.uint8)
    control_path = OUT / f"_crack-control-{target['id']}.png"
    Image.fromarray(np.dstack([control_grey] * 3), mode="RGB").save(control_path)

    name = f"first_stratum_crackinp_{target['id']}"
    run_path = Path(staging.run_dir(str(OUT), target["cls"], name))
    run_path.mkdir(parents=True, exist_ok=True)

    control = provider.controlnet_depth(
        FORGE, str(control_path), options["controlModel"], weight=options["controlWeight"])
    opts = dict(options["sampling"], seed=target["seed"], negativePrompt=NEGATIVE)

    # Pass 1: the crack, in the picture's own coordinates.
    painted = provider.inpaint_region(FORGE, options["model"], target["prompt"],
                                      init, mask, opts, control)
    image = Image.open(io.BytesIO(painted)).convert("RGB")

    # No offset seam pass. With an interior-only mask nothing crosses the wrap, so
    # there is no join to repair -- and rolling the picture to repair one would
    # itself round-trip the frozen border through the VAE and break the very
    # property this variant exists to keep.
    #
    # Restore the border from the SOURCE, not from the painted result: inpainting
    # composites unmasked pixels back through a blurred mask after a full VAE
    # round-trip, so they drift slightly even when never selected. A border that
    # drifts is a border that no longer matches the intact tile, which is the whole
    # failure mode. Taking the original pixels back makes the match exact.
    final = image
    ring = max(6, int(size * 0.05))
    boxes = []
    if "x" in axes:
        boxes += [(0, 0, ring, size), (size - ring, 0, size, size)]
    if "y" in axes:
        boxes += [(0, 0, size, ring), (0, size - ring, size, size)]
    for box in boxes:
        final.paste(init.crop(box), (box[0], box[1]))

    # The property this whole design exists for, asserted rather than assumed.
    border_delta = _border_delta(np.asarray(init, dtype=np.int16),
                                np.asarray(final, dtype=np.int16), axes, ring)
    if border_delta != 0:
        raise RuntimeError(
            f"{target['id']}: border differs from its base by {border_delta}; "
            "the variant would not tile against the tile it is a variant of")

    # Through the project's own pixel pipeline, so the staged tile is produced
    # exactly as every other run's is.
    ctx = classes.resolve(target["cls"], {})
    manifest = {
        "manifestKind": "assetRun", "manifestVersion": 1,
        "class": target["cls"], "name": name,
        "description": target["prompt"],
        "options": {}, "tokens": {},
        "provider": {"id": "forge-inpaint", "model": options["model"],
                     "sampling": opts,
                     "heightControl": str(control_path.relative_to(ROOT)).replace("\\", "/"),
                     "inpaintSource": f"{run}#{index}",
                     "inpaintSourceScore": score},
        "estimatedCostUsd": None, "refs": [],
        "targetFile": ctx.get("file", ""), "targetDir": ctx["dir"],
        "tileAxes": axes,
        "variants": [],
    }
    row = gen._process_variant(_png(final), ctx, str(run_path), 1, verbose=False)
    manifest["variants"].append(row)
    staging.write_manifest(str(run_path), manifest)
    return {"id": target["id"], "run": run_path.name, "source": f"{run}#{index}",
            "sourceScore": score, "status": "generated"}


def _border_delta(source, painted, axes: str, ring: int) -> int:
    """Largest per-channel difference on the tiling borders. Must be zero."""
    size = source.shape[0]
    worst = 0
    slices = []
    if "x" in axes:
        slices += [(slice(None), slice(0, ring)), (slice(None), slice(size - ring, size))]
    if "y" in axes:
        slices += [(slice(0, ring), slice(None)), (slice(size - ring, size), slice(None))]
    for rows, cols in slices:
        worst = max(worst, int(np.abs(source[rows, cols] - painted[rows, cols]).max()))
    return worst


def _png(image):
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", action="append", help="target id; repeatable")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--plan", action="store_true", help="resolve sources and stop")
    args = ap.parse_args(argv)

    cfg = classes.load("config.json")
    sampling = {"steps": 26, "cfgScale": 6.5, "sampler": "DPM++ 2M",
                # 0.70 not 0.82: higher denoise discarded enough of the stone that the
                # crack interiors came back as flat black voids instead of shadowed
                # broken material. maskBlur 12 not 5: a hard mask edge is visible AS
                # an edge, and a crack has no outline.
                "denoise": 0.70, "maskBlur": 12,
                "vae": "vaeFtMse840000EmaPruned_vaeFtMse840k.safetensors",
                "timeout": 300}
    options = {"model": "ohmenOrigins_ohmenOriginsV3",
               "controlModel": cfg["providers"]["forge-quality"].get(
                   "controlnetDepthModel", "control_v11f1p_sd15_depth"),
               "controlWeight": 0.38, "sampling": sampling}

    targets = [t for t in TARGETS if not args.only or t["id"] in args.only]
    if args.plan:
        for t in targets:
            try:
                run, index, score = best_variant(t["run_contains"])
            except SourcePruned as err:
                print(f"  {t['id']:<12} SKIPPED: {err}")
                continue
            print(f"  {t['id']:<12} <- {run}#{index}  (owner score {score})")
        return 0

    results = []
    for t in targets:
        print(f"=== {t['id']} ({t['surface']})")
        try:
            results.append(run_one(t, options, args.force))
        except SourcePruned as err:
            print(f"    SKIPPED: {err}")
            results.append({"id": t["id"], "status": "skipped", "reason": str(err)})
            continue
        print(f"    {results[-1]['run']}  from {results[-1]['source']} "
              f"(score {results[-1]['sourceScore']})  border delta 0")
    SUMMARY.write_text(json.dumps(
        {"batch": "cracked-inpaint-20260807",
         "updatedAt": dt.datetime.now().isoformat(timespec="seconds"),
         "results": results}, indent=2) + "\n", encoding="utf-8")
    print(f"summary: {SUMMARY.relative_to(ROOT).as_posix()}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
