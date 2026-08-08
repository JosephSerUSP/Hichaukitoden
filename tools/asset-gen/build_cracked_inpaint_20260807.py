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
import datetime as dt
import io
import json
import os
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import classes, postprocess, provider, staging  # noqa: E402
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

# The surrounding albedo is authoritative, including its local value structure.
# These are deliberately positive directions: a crack needs shaded broken walls
# and contact occlusion to read as damage. They do not ask for a global light
# source or cast shadow, which would bake scene lighting into a reusable tile.
LOCAL_DAMAGE_GUIDANCE = (
    "preserve the source material's existing colour, grain, value structure and "
    "local occlusion; shaded broken walls and contact occlusion inside the crack "
    "are desired material features, not a global cast shadow; do not flatten or "
    "bleach the surrounding relief"
)


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
    receipt, not a source -- inpainting needs the 512px raw, and the final check
    also needs the processed base tile to compare against.

    So this walks the scores downward and takes the best one whose raw and processed
    base files are actually on disk, and says out loud when it had to skip a better
    score. Silent substitution would mean cutting a crack into material the owner
    never approved while reporting the score of one they did.
    """
    store = json.loads((TOOL / "reviews" / "ratings.json").read_text(encoding="utf-8"))
    scored = []
    for key, row in store.items():
        if run_contains not in key or not row.get("score"):
            continue
        run, index = key.rsplit("#", 1)
        scored.append((int(row["score"]), int(index), run))
    if not scored:
        raise SystemExit(f"no owner ratings for any run matching {run_contains!r}; "
                         "a crack must be cut into material that was actually approved")
    # Rank individual rated pixels, not just the best rating in each run. A run
    # can have a missing high-scoring raw while a lower-scoring candidate from
    # that same run still exists and is a valid fallback.
    ranked = sorted(scored, reverse=True)
    skipped = []
    for score, index, run in ranked:
        source_dir = OUT / run
        raw = source_dir / f"raw-{index}.png"
        base_tile = source_dir / f"variant-{index}.png"
        missing = []
        if not raw.is_file():
            missing.append("raw image")
        if not base_tile.is_file():
            missing.append("processed base tile")
        if not missing:
            for other in skipped:
                print(f"    note: skipped {other[2]}#{other[1]} (score {other[0]}) "
                      f"-- {other[3]}")
    return run, index, score
        skipped.append((score, index, run, " and ".join(missing) + " is no longer in out/"))
    raise SourcePruned(
        f"every rated source matching {run_contains!r} is incomplete in out/; "
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


def source_height_control(source_dir: Path) -> str:
    """Return the source run's engine geometry map, not the crack guide."""
    source_manifest = staging.read_run_manifest(str(source_dir))
    height = (source_manifest.get("provider") or {}).get("heightControl")
    if not height:
        raise RuntimeError(
            f"{source_dir} has no source heightControl; refusing to preview a "
            "cracked variant against guessed geometry")
    full = Path(height) if os.path.isabs(height) else ROOT / height
    if not full.is_file():
        raise RuntimeError(f"source heightControl is missing: {full}")
    return str(height).replace("\\", "/")


def run_one(target: dict, options: dict, force: bool) -> dict:
    run, index, score = best_variant(target["run_contains"])
    source_dir = OUT / run
    raw = source_dir / f"raw-{index}.png"
    if not raw.is_file():
        raise SourcePruned(f"{raw} is missing; cannot inpaint into it")
    source_height = source_height_control(source_dir)
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
    prompt = f"{target['prompt']}, {LOCAL_DAMAGE_GUIDANCE}"
    painted = provider.inpaint_region(FORGE, options["model"], prompt,
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
        "manifestKind": staging.RUN_KIND, "manifestVersion": staging.RUN_VERSION,
        "class": target["cls"], "name": name,
        "surface": target["surface"],
        "description": prompt,
        "options": {}, "tokens": {},
        "provider": {"id": "forge-inpaint", "model": options["model"],
                     "sampling": opts,
                     # The engine preview must use the approved source geometry.
                     # The crack-only map is a model guide, not a room height map.
                     "heightControl": source_height,
                     "inpaintControl": str(control_path.relative_to(ROOT)).replace("\\", "/"),
                     "inpaintControlWeight": options["controlWeight"],
                     "inpaintSource": f"{run}#{index}",
                     "inpaintSourceScore": score},
        "estimatedCostUsd": None, "refs": [],
        "targetFile": ctx.get("file", ""), "targetDir": ctx["dir"],
        "tileAxes": axes,
        "variants": [],
    }
    row = gen._process_variant(_png(final), ctx, str(run_path), 1, verbose=False)

    # `_process_variant` has now applied the exact same resize and palette clamp
    # that produces the engine tile. Those operations can change an edge based
    # on the cracked interior (especially the adaptive quantizer), even though
    # the 512px source edge was frozen above. Restore the processed edge from
    # the actual base tile, then assert the property at the size the engine
    # consumes. This is deliberately a copy from the selected base candidate,
    # not a self-seam repair: variant == base on every shared border.
    base_tile_path = source_dir / f"variant-{index}.png"
    variant_path = run_path / row["file"]
    source_check = verify_source_border(
        source_dir / f"raw-{index}.png", run_path / row["raw"], axes, ring)
    row["sourceCompatibility"] = source_check
    with Image.open(variant_path) as processed_image:
        processed_border = max(1, int(round(ring * processed_image.width / size)))
    _restore_variant_border(variant_path, base_tile_path, axes, processed_border)
    with Image.open(variant_path) as processed_image:
        row["tileScore"] = postprocess.tile_seam_score(processed_image, axes)
    compatibility = verify_variant_compatibility(
        base_tile_path, variant_path, axes, processed_border)
    row["baseCompatibility"] = compatibility
    manifest["variants"].append(row)
    staging.write_manifest(str(run_path), manifest)
    return {"id": target["id"], "run": run_path.name, "source": f"{run}#{index}",
            "sourceScore": score, "baseTile": _relative(base_tile_path),
            "status": "generated"}


def _relative(path: Path) -> str:
    try:
        path = path.relative_to(ROOT)
    except ValueError:
        pass
    return str(path).replace("\\", "/")


def _border_boxes(size: int, axes: str, width: int):
    """Return the frozen-border rectangles for the declared wrap axes."""
    if width < 1 or width * 2 > size:
        raise ValueError(f"invalid border width {width} for {size}px tile")
    boxes = []
    if "x" in axes:
        boxes += [(0, 0, width, size), (size - width, 0, size, size)]
    if "y" in axes:
        boxes += [(0, 0, size, width), (0, size - width, size, size)]
    return boxes


def _restore_variant_border(variant_path: Path, base_path: Path,
                            axes: str, width: int) -> None:
    """Copy the base tile's shared border into a processed variant."""
    with Image.open(base_path) as base_image, Image.open(variant_path) as variant_image:
        base_image = base_image.convert("RGBA")
        variant_image = variant_image.convert("RGBA")
        if base_image.size != variant_image.size:
            raise RuntimeError(
                f"base tile {base_path} is {base_image.size}, but variant "
                f"{variant_path} is {variant_image.size}")
        for box in _border_boxes(variant_image.width, axes, width):
            variant_image.paste(base_image.crop(box), (box[0], box[1]))
        variant_image.save(variant_path)


def verify_variant_compatibility(base_path: Path, variant_path: Path,
                                 axes: str, width: int = 1) -> dict:
    """Assert dimensions and exact processed-edge equality against the base tile."""
    base, variant = _load_pair(base_path, variant_path)
    if base.shape != variant.shape:
        raise RuntimeError(
            f"base tile {base_path} has shape {base.shape}, but variant "
            f"{variant_path} has shape {variant.shape}")
    delta = _border_delta(base, variant, axes, width)
    if delta != 0:
        raise RuntimeError(
            f"{variant_path}: border differs from base tile {base_path} by {delta}; "
            "the variant would not tile against the tile it is a variant of")
    return {"width": int(variant.shape[1]), "height": int(variant.shape[0]),
            "borderWidth": int(width), "borderDelta": 0,
            "baseTile": _relative(base_path)}


def verify_source_border(base_path: Path, raw_path: Path, axes: str,
                         width: int) -> dict:
    """Assert that the high-resolution inpaint did not alter the source border."""
    base, raw = _load_pair(base_path, raw_path)
    if base.shape != raw.shape:
        raise RuntimeError(
            f"source {base_path} has shape {base.shape}, but inpaint raw "
            f"{raw_path} has shape {raw.shape}")
    delta = _border_delta(base, raw, axes, width)
    if delta != 0:
        raise RuntimeError(
            f"{raw_path}: source border differs from {base_path} by {delta}; "
            "the inpaint crossed a frozen tiling border")
    return {"width": int(raw.shape[1]), "height": int(raw.shape[0]),
            "borderWidth": int(width), "borderDelta": 0,
            "baseRaw": _relative(base_path)}


def _load_pair(first_path: Path, second_path: Path):
    with Image.open(first_path) as first_image, Image.open(second_path) as second_image:
        return (np.asarray(first_image.convert("RGBA"), dtype=np.int16),
                np.asarray(second_image.convert("RGBA"), dtype=np.int16))


def verify_existing() -> int:
    """Verify all staged cracked runs against the exact base candidates they cite."""
    checked = 0
    failures = []
    for run_path in sorted(OUT.glob("*-first_stratum_crackinp_*-*")):
        manifest_path = run_path / "manifest.json"
        if not run_path.is_dir() or not manifest_path.is_file():
            continue
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            source = manifest.get("provider", {}).get("inpaintSource", "")
            source_run, source_index = source.rsplit("#", 1)
            base_dir = OUT / source_run
            base_raw = base_dir / f"raw-{source_index}.png"
            base_tile = base_dir / f"variant-{source_index}.png"
            axes = manifest["tileAxes"]
            with Image.open(base_raw) as base_image:
                raw_width = base_image.width
            for row in manifest.get("variants", []):
                candidate_raw = run_path / row["raw"]
                candidate_tile = run_path / row["file"]
                raw_check = verify_source_border(
                    base_raw, candidate_raw, axes, max(6, int(raw_width * 0.05)))
                width = int(row.get("baseCompatibility", {}).get("borderWidth", 1))
                tile_check = verify_variant_compatibility(
                    base_tile, candidate_tile, axes, width)
                checked += 1
                print(f"  OK {run_path.name}/{row['file']}  "
                      f"raw {raw_check['borderDelta']}  tile {tile_check['borderDelta']}")
        except (OSError, KeyError, ValueError, RuntimeError) as err:
            failures.append(f"{run_path.name}: {err}")
    if failures:
        for failure in failures:
            print(f"  FAIL {failure}")
        print(f"verified {checked}; {len(failures)} run(s) failed")
        return 1
    print(f"verified {checked} cracked variant(s)")
    return 0


def _border_delta(source, painted, axes: str, ring: int) -> int:
    """Largest per-channel difference on the tiling borders. Must be zero."""
    if source.shape != painted.shape:
        raise ValueError(f"cannot compare border shapes {source.shape} and {painted.shape}")
    size = source.shape[0]
    worst = 0
    for left, top, right, bottom in _border_boxes(size, axes, ring):
        worst = max(worst, int(np.abs(
            source[top:bottom, left:right] - painted[top:bottom, left:right]).max()))
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
    ap.add_argument("--verify-existing", action="store_true",
                    help="verify every staged cracked variant against its cited base")
    args = ap.parse_args(argv)

    if args.verify_existing:
        return verify_existing()

    cfg = classes.load("config.json")
    sampling = {"steps": 26, "cfgScale": 6.5, "sampler": "DPM++ 2M",
                # 0.70 not 0.82: higher denoise discarded enough of the stone that the
                # crack interiors came back as flat black voids instead of shadowed
                # broken material. maskBlur 12 not 5: a hard mask edge is visible AS
                # an edge, and a crack has no outline.
                "denoise": 0.70, "maskBlur": 12,
                "inpaintFullRes": True, "inpaintFullResPadding": 32,
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
