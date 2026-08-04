"""asset-gen -- prompt to game-ready art for Hichaukitoden.

    python tools/asset-gen/gen.py classes
    python tools/asset-gen/gen.py generate smallBattler Kappa "a river-turtle imp"
    python tools/asset-gen/gen.py runs
    python tools/asset-gen/gen.py promote latest --variant 1

This is deliberately NOT part of tools/editor: it spends money, it is slow, and
it writes binaries. It shares the editor's philosophy instead -- asset classes
are a data registry (classes.json), the post-processing pipeline is named steps
in data, and nothing here re-implements what the engine already knows.

`reprocess` re-runs the pixel pipeline over a run's raw model output with no API
call, which is how you tune post-processing (or classes.json geometry) without
paying for another render.
"""

import argparse
import base64
import io
import json
import os
import subprocess
import sys
import time

from PIL import Image, ImageColor

# Prompts and manifests are ASCII, but a description passed on the command line
# need not be, and the Windows console's default codepage is not UTF-8.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import (classes, postprocess, provider, ratings, raw_quality,  # noqa: E402
                 report, staging)


def _config():
    return classes.load("config.json")


def _provider(cfg, name, model_override, quality_override=None):
    providers = cfg["providers"]
    if not name:
        name = os.environ.get("ASSET_GEN_PROVIDER") or next(
            (k for k, v in providers.items() if v.get("default")), None
        )
    entry = providers.get(name)
    if not entry:
        raise KeyError(f"unknown provider '{name}'. Known: {', '.join(providers)}")
    entry = dict(entry, id=name)
    if model_override:
        known = [m["id"] for m in entry.get("models", [])]
        if known and model_override not in known:
            # Not fatal -- new models appear faster than this config is updated --
            # but an unpriced model means no estimate, so say so once.
            print(f"  note: '{model_override}' is not in config.json for {name}; "
                  f"no cost estimate. Known: {', '.join(known)}")
        entry["model"] = model_override
    if quality_override:
        entry["quality"] = quality_override
    return entry


def price_per_image(cfg, provider_entry, size):
    """Config-table lookup. Returns (usd_or_None, why_none)."""
    model = next((m for m in provider_entry.get("models", [])
                  if m["id"] == provider_entry["model"]), None)
    if model is None:
        return None, f"{provider_entry['model']} is not in config.json"
    if not model.get("prices"):
        return None, model.get("note") or "this model is not priced per image"
    quality = provider_entry.get("quality") or "low"
    by_size = model["prices"].get(quality)
    if not by_size:
        return None, f"no price listed for quality '{quality}'"
    if size not in by_size:
        return None, f"no price listed for size {size}"
    return by_size[size], None


def _variant_seed(sampling, index):
    """Distinct seeds per variant, reproducible when one was asked for.

    Reusing one seed across variants would render the same picture N times; -1
    lets the server roll its own. An explicit seed walks upward so the whole run
    can be reproduced from the manifest.
    """
    seed = sampling.get("seed")
    if seed is None or seed < 0:
        return -1
    return seed + index - 1


def _cost_line(cfg, provider_entry, size, variants):
    if provider_entry.get("local"):
        return "  cost: free (local GPU)"
    unit, why = price_per_image(cfg, provider_entry, size)
    checked = cfg.get("pricing", {}).get("checkedOn", "?")
    if unit is None:
        return f"  cost: no estimate available ({why})"
    return (f"  cost: ~${unit * variants:.3f} for {variants} "
            f"({provider_entry.get('quality', 'low')} quality, ${unit:.3f}/image, "
            f"price table checked {checked} -- estimate only)")


def _staging_root(cfg):
    return os.path.join(classes.ROOT, cfg["generate"]["stagingDir"])


def _parse_pair(text, label):
    try:
        w, h = str(text).lower().split("x")
        return [int(w), int(h)]
    except Exception:
        raise SystemExit(f"--{label} wants WxH, e.g. 24x24 (got '{text}')")


# ---------------------------------------------------------------------------
def cmd_classes(args):
    reg = classes.registry()
    for class_id, definition in reg["classes"].items():
        geom = definition["geometry"]
        size = geom.get("size")
        label = f"{size[0]}x{size[1]}" if size else f"{geom['cell'][1]}px tall strip"
        pending = "" if definition.get("engineWired", True) else "  [NOT ENGINE-WIRED]"
        print(f"{class_id:14s} {label:>16s}  {geom['frames']} frame(s)"
              f"  -> {definition['dir']}{pending}")
        print(f"{'':14s} {definition['note']}")
    return 0


def cmd_models(args):
    cfg = _config()
    pricing = cfg.get("pricing", {})
    print(f"USD per image at 1024x1024. Table checked {pricing.get('checkedOn', '?')} "
          f"against {pricing.get('source', 'the provider')}.")
    print("These are ESTIMATES from a local table -- your invoice is the truth.\n")
    for pid, entry in cfg["providers"].items():
        if entry.get("local"):
            status = "local GPU, no key needed"
        else:
            status = (f"{entry['apiKeyEnv']}: "
                      + ("set" if os.environ.get(entry["apiKeyEnv"], "").strip() else "MISSING"))
        mark = " (default)" if entry.get("default") else ""
        print(f"{entry['label']}{mark}  [{status}]")
        for model in entry.get("models", []):
            active = " <- current" if model["id"] == entry["model"] else ""
            prices = model.get("prices")
            if prices:
                costs = "  ".join(
                    f"{q}=${prices[q]['1024x1024']:.3f}" for q in ("low", "medium", "high")
                    if q in prices
                )
                print(f"   {model['id']:22s} {costs}{active}")
            else:
                print(f"   {model['id']:22s} no per-image price{active}")
                print(f"   {'':22s}   {model.get('note', '')}")
        print()
    return 0


def cmd_runs(args):
    cfg = _config()
    runs = staging.list_runs(_staging_root(cfg))
    if not runs:
        print("no staged runs")
        return 0
    for name, manifest in runs:
        promoted = manifest.get("promoted") or []
        mark = f"  promoted-> {promoted[-1]['dest']}" if promoted else ""
        print(f"{name}  [{manifest['class']}] {manifest['name']}  "
              f"{len(manifest['variants'])} variant(s){mark}")
    return 0


def _process_variant(raw_bytes, ctx, run_path, index, verbose=True):
    """Raw model bytes -> staged raw file + processed sheet. Returns manifest row."""
    raw_name = f"raw-{index}.png"
    with open(os.path.join(run_path, raw_name), "wb") as handle:
        handle.write(raw_bytes)

    img = Image.open(io.BytesIO(raw_bytes))
    ctx.pop("tileScore", None)
    out = postprocess.run(img, ctx, verbose=verbose)
    out_name = f"variant-{index}.png"
    out.save(os.path.join(run_path, out_name))
    row = {"index": index, "raw": raw_name, "file": out_name,
           "rawQuality": raw_quality.analyze(img)}
    if verbose:
        quality = row["rawQuality"]
        print(f"  raw: {quality['verdict']} high-chroma={quality['highChromaRatio']}"
              f" outliers={quality['chromaOutlierRatio']}")
    # Left behind by the tile_score post step, for classes that declare it.
    score = ctx.pop("tileScore", None)
    if score:
        row["tileScore"] = score
        if verbose:
            print(f"  seam ({ctx.get('classDef', {}).get('tileAxes', 'xy')}): "
                  f"wrap x={score.get('x')} y={score.get('y')}"
                  f"  centre x={score.get('centre_x')} y={score.get('centre_y')}"
                  + (f"  ({score['note'].strip()})" if score.get("note") else ""))
    return row


# How the seam ratio is read everywhere. 1.0 is "indistinguishable from the
# interior"; the threshold is where a join starts being visible once a texture
# repeats across a corridor, and is deliberately one number in one place.
SEAM_GOOD = 2.0


SEAM_AXES = ("x", "y", "centre_x", "centre_y")


def seam_rank(row, axes=SEAM_AXES):
    """Sort key for picking the best variant: worst measured axis first.

    The centre readings are ranked alongside the wrap ones deliberately. The
    technique that produces the wrap moves the discontinuity into the middle of
    the texture, so judging on the wrap alone would systematically prefer
    exactly the variants where that relocation went worst.

    An unmeasurable axis is not a free pass -- it sorts last, because a texture
    whose seam cannot be seen is not a texture whose seam is known to be good.
    """
    scores = [row.get("tileScore", {}).get(axis) for axis in axes]
    measured = [s for s in scores if isinstance(s, (int, float))]
    if not measured:
        return (1, 0.0)
    return (0, max(measured))


def _finish(run_path, manifest):
    sheet = postprocess.contact_sheet(
        [os.path.join(run_path, v["file"]) for v in manifest["variants"]]
    )
    if sheet:
        sheet.save(os.path.join(run_path, "contact-sheet.png"))
    staging.write_manifest(run_path, manifest)
    print(f"\nstaged: {run_path}")
    print(f"  preview: {os.path.join(run_path, 'contact-sheet.png')}")
    print(f"  promote: python tools/asset-gen/gen.py promote "
          f"{os.path.basename(run_path)} --variant {manifest['variants'][0]['index']}")


def _sampling_overrides(args):
    """CLI knobs that only the local sdapi provider understands."""
    override = {}
    for flag, key in (("steps", "steps"), ("cfg", "cfgScale"), ("sampler", "sampler"),
                      ("seed", "seed")):
        value = getattr(args, flag, None)
        if value is not None:
            override[key] = value
    if getattr(args, "no_tiling", False):
        override["tiling"] = False
    loras = []
    for item in getattr(args, "lora", None) or []:
        name, separator, weight_text = item.rpartition(":")
        if not separator:
            name, weight = item, 0.8
        else:
            try:
                weight = float(weight_text)
            except ValueError:
                raise SystemExit(f"--lora wants NAME or NAME:WEIGHT (got '{item}')")
        name = name.strip()
        if not name:
            raise SystemExit(f"--lora wants NAME or NAME:WEIGHT (got '{item}')")
        loras.append({ "name": name, "weight": weight })
    if loras:
        override["loras"] = loras
    return override


def _class_tile_axes(class_id):
    definition = classes.registry()["classes"].get(class_id) or {}
    return definition.get("tileAxes", definition.get("tiles", False))


def _control_from_height(cfg, args):
    """Build the ControlNet unit for --height, or None."""
    path = getattr(args, "height", None)
    if not path:
        return None, None
    full = path if os.path.isabs(path) else os.path.join(classes.ROOT, path)
    if not os.path.isfile(full):
        raise SystemExit(f"height map not found: {full}")
    # A control map that does not tile cannot produce art that tiles: the
    # conditioning re-imposes its own discontinuity at the border, and the
    # seamless pass then has to fight it. Measured on this project's own
    # limestone wall -- whose height map has a hard join -- conditioning took the
    # seam from ~1.0 to ~3.8. Say so, rather than hand back a worse texture with
    # no explanation.
    if _class_tile_axes(getattr(args, "asset_class", None)):
        axes = _class_tile_axes(args.asset_class)
        score = postprocess.tile_seam_score(Image.open(full), axes)
        worst = max((v for v in (score.get("x"), score.get("y"))
                     if isinstance(v, (int, float))), default=0)
        if worst > SEAM_GOOD:
            print(f"  warning: {path} does not tile (seam {worst}). Conditioning on it "
                  "will push that seam into the albedo; the height map has to wrap first.")

    local = cfg.get("local", {})
    depth_weight = getattr(args, "depth_weight", None)
    if depth_weight is None:
        depth_weight = local.get("depthWeight", 0.6)
    unit = provider.controlnet_depth(
        _provider(cfg, args.provider, args.model).get("baseUrl", ""),
        full, local.get("controlnetDepthModel"), depth_weight)
    return unit, os.path.relpath(full, classes.ROOT).replace("\\", "/")


def _auto_promote(cfg, run_path, manifest, force_dirty=False):
    """Promote the best-scoring variant. Returns the destination, or None."""
    scored = [v for v in manifest["variants"] if v.get("tileScore")]
    if not scored:
        return None
    best = min(scored, key=seam_rank)
    worst_axis = seam_rank(best)
    if worst_axis[0] == 1:
        print("  auto-promote skipped: no variant has a measurable seam")
        return None
    if worst_axis[1] > SEAM_GOOD:
        print(f"  auto-promote skipped: the best seam is {worst_axis[1]}, over the "
              f"{SEAM_GOOD} threshold -- none of these tile well enough")
        return None
    dest = staging.promote(_staging_root(cfg), os.path.basename(run_path),
                           best["index"], None, force=True, force_dirty=force_dirty)
    print(f"  auto-promoted variant {best['index']} (seam {worst_axis[1]}) -> "
          f"{os.path.relpath(dest, classes.ROOT)}")
    return dest


def cmd_generate(args):
    cfg = _config()
    opts = {}
    if args.cell:
        opts["cell"] = _parse_pair(args.cell, "cell")
    if args.frames:
        opts["frames"] = args.frames
    if args.grid:
        opts["grid"] = _parse_pair(args.grid, "grid")
    if args.request_size:
        opts["requestSize"] = args.request_size

    ctx = classes.resolve(args.asset_class, opts)
    tokens = dict(t.split("=", 1) for t in (args.token or []))
    # The provider decides how its model wants to be talked to, not the class.
    prov_style = (getattr(args, "prompt_style", None)
                  or _provider(cfg, args.provider, args.model).get("promptStyle", "prose"))
    text = classes.prompt(ctx, args.name, args.description, args.extra, prov_style)

    if args.dry_run:
        preview = _provider(cfg, args.provider, args.model, args.quality)
        print(text)
        print(f"\n--- would produce {classes.filename(ctx, args.name, tokens)} "
              f"({ctx['size'][0]}x{ctx['size'][1]}) in {ctx['dir']}")
        print(f"--- via {preview['model']} at {ctx['requestSize']}")
        print("-" + _cost_line(cfg, preview, ctx["requestSize"],
                               args.variants or cfg["generate"]["variants"]))
        return 0

    prov = _provider(cfg, args.provider, args.model, args.quality)
    refs = [os.path.join(classes.ROOT, r) if not os.path.isabs(r) else r
            for r in (args.ref or [])]
    for ref in refs:
        if not os.path.isfile(ref):
            raise SystemExit(f"reference image not found: {ref}")

    sampling = _sampling_overrides(args)
    # The local provider's seamless pass is an offset/inpaint operation. It is
    # correct for a material tile, but it destroys non-tile art such as a
    # portrait by repainting a cross through the subject.
    if not ctx["classDef"].get("tiles"):
        sampling["tiling"] = False
    else:
        sampling["tilingAxes"] = ctx["classDef"].get(
            "tileAxes", ctx["classDef"].get("tiles", True))
    if ctx["classDef"].get("negativePrompt"):
        sampling["negativePrompt"] = ctx["classDef"]["negativePrompt"]
    control, control_source = _control_from_height(cfg, args)

    variants = args.variants or cfg["generate"]["variants"]
    run_path = staging.run_dir(_staging_root(cfg), args.asset_class, args.name)
    manifest = {
        "class": args.asset_class,
        "name": args.name,
        "description": args.description,
        "options": opts,
        "tokens": tokens,
        "provider": {"id": prov["id"], "model": prov["model"],
                     "quality": prov.get("quality"),
                     "sampling": dict(prov.get("sampling") or {}, **sampling) or None,
                     "heightControl": control_source,
                     "heightControlWeight": control and control.get("weight")},
        "estimatedCostUsd": (lambda unit: unit and round(unit * variants, 4))(
            price_per_image(cfg, prov, ctx["requestSize"])[0]),
        "refs": [os.path.relpath(r, classes.ROOT).replace("\\", "/") for r in refs],
        "targetFile": classes.filename(ctx, args.name, tokens),
        "targetDir": ctx["dir"],
        "tileAxes": ctx["classDef"].get(
            "tileAxes", ctx["classDef"].get("tiles", False)),
        "variants": [],
    }
    with open(os.path.join(run_path, "prompt.txt"), "w", encoding="utf-8") as handle:
        handle.write(text)

    print(f"{prov['label']} / {prov['model']} -- {variants} variant(s) of "
          f"{args.asset_class} '{args.name}'")
    print(_cost_line(cfg, prov, ctx["requestSize"], variants))
    print("  each render typically takes 20-60s; the log updates per variant.")

    started = time.time()
    for index in range(1, variants + 1):
        print(f"\n[{index}/{variants}] rendering...")
        mark = time.time()
        try:
            raw = provider.generate(
                prov, text, refs,
                size=ctx["requestSize"],
                timeout=cfg["generate"]["timeoutSeconds"],
                max_retries=cfg["generate"]["maxRetries"],
                transparent=ctx["transparent"],
                quality=prov.get("quality"),
                sampling=dict(sampling, seed=_variant_seed(sampling, index)),
                control=control,
            )
            print(f"  received in {time.time() - mark:.0f}s")
            manifest["variants"].append(_process_variant(raw, ctx, run_path, index))
        except Exception as err:
            # One bad variant must not throw away the ones that worked.
            print(f"  variant {index} failed: {err}")

    print(f"\ndone in {time.time() - started:.0f}s")

    if not manifest["variants"]:
        staging.write_manifest(run_path, manifest)
        print(f"\nno variants succeeded; run kept at {run_path}")
        return 1
    _finish(run_path, manifest)
    if args.promote:
        _auto_promote(cfg, run_path, manifest, args.force_dirty)
    return 0


def cmd_reprocess(args):
    """Re-run the pixel pipeline over staged raw output -- no API call, no cost."""
    cfg = _config()
    run_path = staging.resolve_run(_staging_root(cfg), args.run)
    manifest = staging.read_manifest(run_path)
    ctx = classes.resolve(manifest["class"], manifest.get("options", {}))

    rows = []
    raws = sorted(f for f in os.listdir(run_path) if f.startswith("raw-"))
    for raw_name in raws:
        index = int(raw_name.split("-")[1].split(".")[0])
        print(f"[{index}] {raw_name}")
        with open(os.path.join(run_path, raw_name), "rb") as handle:
            rows.append(_process_variant(handle.read(), ctx, run_path, index))
    if not rows:
        raise SystemExit(f"no raw-*.png in {run_path}")
    manifest["variants"] = rows
    manifest["targetFile"] = classes.filename(ctx, manifest["name"], manifest.get("tokens"))
    _finish(run_path, manifest)
    return 0


def cmd_tilecheck(args):
    """Score a staged run's seams and lay each variant out 3x3 to see them.

    The numbers are the point -- they are what lets a batch be triaged without
    anyone opening an image -- but the sheet is what catches the failure the
    numbers cannot describe: a texture that wraps perfectly and still reads as
    obvious repetition because one feature dominates the middle.
    """
    cfg = _config()
    run_path = staging.resolve_run(_staging_root(cfg), args.run)
    manifest = staging.read_manifest(run_path)
    rows = []
    for variant in manifest["variants"]:
        path = os.path.join(run_path, variant["file"])
        axes = _class_tile_axes(manifest.get("class"))
        score = postprocess.tile_seam_score(Image.open(path), axes)
        variant["tileScore"] = score
        sheet_name = f"tiled-{variant['index']}.png"
        postprocess.tiled_sheet(path, args.repeat, axes=axes).save(
            os.path.join(run_path, sheet_name))
        rows.append((variant["index"], score, sheet_name))

    staging.write_manifest(run_path, manifest)
    print(f"{os.path.basename(run_path)}  [{manifest['class']}] {manifest['name']}")
    print(f"  ratios: 1.0 = as smooth as the interior, over {SEAM_GOOD} = visible join.")
    print("  wrap = the declared tile edge; centre = the join the seamless pass relocates inward")
    ranked = sorted(rows, key=lambda row: seam_rank({"tileScore": row[1]}))
    for position, (index, score, sheet) in enumerate(ranked):
        parts = [f"{axis}={score.get(axis) if score.get(axis) is not None else 'unmeasurable'}"
                 for axis in SEAM_AXES]
        best = "  <- best" if position == 0 else ""
        print(f"  variant {index}: {'  '.join(parts)}   {sheet}{best}")
        if score.get("note"):
            print(f"      {score['note'].strip()}")
    return 0


HEIGHT_MAP_MANIFESTS = [
    "assets/geometry/1_blender_depth_maps/manifest.json",
]

TILESET_DATA = "data/tilesets.json"
SURFACE_KEY = {"wall": "walls", "floor": "floors", "ceiling": "ceilings"}


def _surface_cells(tileset_id, surface):
    """Atlas cells a surface draws from, as (col, row), from tilesets.json.

    Two things this gets right that a hand-written cell in classes.json did not.

    The ORDER: the engine reads `atlas[1]` as the row and `atlas[2]` as the
    column (viewport_3d.lua). The old preview treated the pair as (x, y), which
    is the same thing for the wall at [1,1] and the ceiling at [0,0] and wrong
    for the floor at [3,0] -- so floors previewed with the stock dungeon texture
    under the new height map, looking like the geometry had applied and the
    material had not.

    The COUNT: a surface usually has several weighted variants, so painting one
    cell leaves the others stock and the preview mixes the candidate with the
    old texture at random. Every variant of the surface gets the candidate.
    """
    if not tileset_id:
        return []
    try:
        with open(os.path.join(classes.ROOT, TILESET_DATA), "r", encoding="utf-8") as handle:
            tilesets = json.load(handle)
    except (OSError, json.JSONDecodeError):
        return []
    entry = tilesets.get(tileset_id) or {}
    cells = []
    for variant in (entry.get("base") or {}).get(SURFACE_KEY.get(surface, ""), []):
        coord = variant.get("atlas") or variant.get("middle")
        if coord and len(coord) >= 2:
            cells.append((coord[1], coord[0]))
    return cells


def _height_map_surface(height_path):
    """Which surface a height map was authored for, from its own manifest.

    Read from data rather than guessed from the filename: blendergeom.py already
    records `surface` per map, and a preview that puts a ceiling vault on the
    floor is worse than no preview because it looks like a result.
    """
    if not height_path:
        return None
    want = os.path.splitext(os.path.basename(height_path))[0]
    for rel in HEIGHT_MAP_MANIFESTS:
        try:
            with open(os.path.join(classes.ROOT, rel), "r", encoding="utf-8") as handle:
                for record in json.load(handle).get("maps") or []:
                    if record.get("preset") == want:
                        return record.get("surface")
        except (OSError, json.JSONDecodeError):
            continue
    # Legacy staged experiments predate the Blender height-map manifest and
    # kept their authored guides under tools/asset-gen/out. They still carry
    # the exact guide path in each run manifest, so classify those guides here
    # instead of silently falling back to the class default (the wall column,
    # or the floor for texturePiece). This affects preview surface/cell choice;
    # it does not pretend to change what the model was conditioned on.
    legacy = {
        "wall_relief": "wall",
        "recessed_holes": "wall",
        "broken_flagstones": "floor",
        "stalactite_ceiling": "ceiling",
    }
    return legacy.get(want)


def _tile_sized_height(run_path, height_rel, class_def):
    """A copy of the height map at the size the engine's preview accepts.

    Generation wants the map large -- ControlNet reads a 512 map far better than
    a 64 one -- but the tileset preview requires it to match the atlas or a
    single tile. Rather than shrink the authored map and lose the guidance,
    a downsampled copy is staged next to the run that used it.
    """
    cell = (class_def.get("geometry") or {}).get("cell") or [64, 64]
    source = os.path.join(classes.ROOT, height_rel)
    image = Image.open(source)
    if image.size == tuple(cell):
        return height_rel
    scaled = os.path.join(run_path, "context-height.png")
    # BOX, not NEAREST: the map is a continuous field, and point-sampling an 8x
    # reduction would drop whole mortar joints between samples.
    image.convert("RGBA").resize(tuple(cell), Image.Resampling.BOX).save(scaled)
    return os.path.relpath(scaled, classes.ROOT).replace("\\", "/")


def _preview_surface(manifest, context):
    """Which surface this run's preview should paint, one answer in one place.

    Both the builder and the cache check have to agree on this or a stale
    preview can never be spotted, so neither computes it for itself.
    """
    run_height = (manifest.get("provider") or {}).get("heightControl")
    return _height_map_surface(run_height) or context.get("defaultSurface")


def _preview_is_stale(variant, want):
    """Whether a cached preview provably painted the wrong surface.

    Deliberately conservative: it re-renders only what it can PROVE is wrong,
    never merely what it cannot vouch for. Previews predating `contextSurface`
    are the overwhelming majority and nearly all of them are correct, so
    treating "unstamped" as "suspect" would rebuild thousands of good previews
    through the engine to fix sixteen bad ones.

    For those, the surface is recovered from the label the preview already
    carries -- each surface words it distinctly -- and only a genuine
    disagreement counts.
    """
    if not want:
        return False
    recorded = variant.get("contextSurface")
    if recorded is not None:
        return recorded != want
    label = (variant.get("contextLabel") or "").lower()
    for surface in ("wall", "floor", "ceiling"):
        if f"this {surface}'s own" in label:
            return surface != want
    return False


def _context_preview(run_path, manifest, variant):
    """Render one staged tile through the real engine for report evidence."""
    class_def = classes.registry()["classes"].get(manifest.get("class"), {})
    context = class_def.get("contextPreview")
    if not context:
        return
    # The height map the TEXTURE was conditioned on, not the class default.
    # Previewing a wall generated against an arched niche on the old flat
    # column map shows a room that was never asked for, and the mismatch is
    # invisible unless you already know both maps.
    run_height = (manifest.get("provider") or {}).get("heightControl")
    surface = _preview_surface(manifest, context)
    context = dict(context, **(context.get("bySurface", {}).get(surface) or {}))
    try:
        if run_height:
            context["heightMap"] = _tile_sized_height(run_path, run_height, class_def)
        base_path = os.path.join(classes.ROOT, context["base"])
        candidate_path = os.path.join(run_path, variant["file"])
        atlas_path = os.path.join(run_path, f"context-atlas-{variant['index']}.png")
        source = Image.open(base_path).convert("RGBA")
        # Everything that is NOT under test is painted flat. The stock dungeon
        # tileset is a busy, high-contrast material, and surrounding a candidate
        # with it makes the candidate hard to read and easy to misjudge -- the
        # eye compares it to the neighbour instead of assessing it. A dead grey
        # surround puts the only detail in the frame on the thing being rated.
        neutral = context.get("neutral")
        atlas = (Image.new("RGBA", source.size, ImageColor.getrgb(neutral))
                 if neutral else source)
        tile = Image.open(candidate_path).convert("RGBA")
        cell_w, cell_h = source.width // 4, source.height // 4
        tile = tile.resize((cell_w, cell_h), Image.Resampling.NEAREST)
        cells = (_surface_cells(context.get("tileset"), surface)
                 or [tuple(context.get("cell", [1, 1]))])
        for cell_x, cell_y in cells:
            atlas.paste(tile, (cell_x * cell_w, cell_y * cell_h))
        atlas.save(atlas_path)

        love = os.environ.get("LOVE_BIN", r"C:\Program Files\LOVE\lovec.exe")
        rel_atlas = os.path.relpath(atlas_path, classes.ROOT).replace("\\", "/")
        preview_command = [love, ".", "preview-texture", rel_atlas]
        if context.get("heightMap"):
            preview_command.extend(["--height-map", context["heightMap"]])
        preview_command.extend([
            "--quality-density", str(context.get("qualityDensity", 4.0)),
            "--height-scale", json.dumps(context.get("heightMapScale", {})),
            "--height-columns", str(context.get("heightMapMeshColumns", 16)),
            "--height-rows", str(context.get("heightMapMeshRows", 16)),
            "--height-samples-x", str(context.get("heightMapSampleColumns", 24)),
            "--height-samples-y", str(context.get("heightMapSampleRows", 24)),
            "--height-budget", str(context.get("heightMapTriangleBudget", 96)),
        ])
        proc = subprocess.run(
            preview_command,
            cwd=classes.ROOT, capture_output=True, text=True, timeout=120,
        )
        output = proc.stdout
        start, end = output.find("PREVIEW BEGIN"), output.find("PREVIEW END")
        if proc.returncode != 0 or start < 0 or end < 0:
            raise RuntimeError((proc.stderr or output or "lovec preview failed").strip())
        payload = json.loads(output[start + len("PREVIEW BEGIN"):end].strip())
        if payload.get("error"):
            raise RuntimeError(payload["error"])
        context_name = f"context-{variant['index']}.png"
        with open(os.path.join(run_path, context_name), "wb") as handle:
            handle.write(base64.b64decode(payload["image"]))
        variant["context"] = context_name
        # The height map is named in the label because a preview cannot show
        # which one it used, and getting that wrong is invisible: a correct
        # albedo displaced by the wrong geometry looks like a plausible room.
        # Both directions of that mistake shipped before this line existed.
        # Names the AUTHORED map, not the downscaled copy staged beside the run
        # -- every run's copy is called context-height.png, which would make the
        # label identical everywhere and useless for spotting a mismatch.
        shown = run_height or context.get("heightMap") or "none"
        variant["contextLabel"] = (
            f"{context.get('label', 'in-engine context')} "
            f"[geometry: {os.path.splitext(os.path.basename(shown))[0]}]")
        # Recorded so the cache can be INVALIDATED rather than merely populated.
        # A preview is only reusable if the surface it was painted on is still
        # the surface this run resolves to; see _add_context_previews.
        variant["contextSurface"] = surface
    except Exception as err:
        variant["contextError"] = str(err)


def _add_context_previews(run_path, manifest, persist=True):
    """Build any missing room previews and remember them in the manifest.

    Previously these were rendered into the run directory but only ever held in
    the report's in-memory copy of the manifest, so the PNG existed on disk and
    nothing recorded that it did. Anything else wanting the preview -- the
    rating queue, most of all -- had no way to find it.

    A cached preview is also RE-CHECKED, not just reused. The surface logic has
    been wrong before: runs staged before height maps declared their own surface
    painted every texturePiece on the floor, so wall relief and ceiling
    stalactites were rated as if they were pavement. Those previews were built
    once and, because the only test was whether a preview existed, were kept
    forever -- the owner met them again months later while re-rating, and a
    preview that is confidently wrong is worse than none, because it looks like
    a result. A preview whose recorded surface no longer matches this run's is
    now rebuilt.
    """
    built = False
    class_def = classes.registry()["classes"].get(manifest.get("class"), {})
    context = class_def.get("contextPreview") or {}
    want = _preview_surface(manifest, context) if context else None
    for variant in manifest.get("variants", []):
        if variant.get("context") and not _preview_is_stale(variant, want):
            # Correct, or not provably wrong: stamp it so the next reader gets a
            # cheap comparison instead of re-deriving it from prose.
            variant.setdefault("contextSurface", want)
            continue
        _context_preview(run_path, manifest, variant)
        built = built or bool(variant.get("context"))
    if built and persist:
        staging.write_manifest(run_path, manifest)
    return built


def cmd_audit(args):
    """Score the tiling of art that already exists on disk.

    Generation is not the only thing that can produce a texture that does not
    wrap; hands can too, and did. Every plane asset is instanced once per cell,
    so its albedo AND its height map both have to tile, and a height map that
    does not is the harder failure -- it puts a ridge across the mesh that no
    amount of decimation care will hide.
    """
    root = os.path.join(classes.ROOT, args.dir)
    rows = []
    for name in sorted(os.listdir(root)):
        folder = os.path.join(root, name)
        if not os.path.isdir(folder):
            continue
        entry = {"name": name}
        for kind in ("albedo", "height"):
            path = os.path.join(folder, f"{kind}.png")
            if os.path.isfile(path):
                entry[kind] = postprocess.tile_seam_score(Image.open(path))
        rows.append(entry)

    def worst(score):
        values = [v for k, v in (score or {}).items()
                  if k in SEAM_AXES and isinstance(v, (int, float))]
        return max(values) if values else None

    print(f"{'asset':22s} {'albedo':>10s} {'height':>10s}   verdict")
    for entry in rows:
        a, h = worst(entry.get("albedo")), worst(entry.get("height"))
        bad = [k for k, v in (("albedo", a), ("height", h)) if v is not None and v > SEAM_GOOD]
        verdict = "tiles" if not bad else "DOES NOT TILE: " + ", ".join(bad)
        print(f"{entry['name']:22s} {a if a is not None else '-':>10} "
              f"{h if h is not None else '-':>10}   {verdict}")
    print(f"\n1.0 = seam as smooth as the interior; over {SEAM_GOOD} = a visible join.")
    print("A figure or fixture is not meant to tile, and its score is meaningless.")

    if args.out:
        cards = []
        for entry in rows:
            folder = os.path.join(root, entry["name"])
            images, body = [], []
            for kind in ("albedo", "height"):
                path = os.path.join(folder, f"{kind}.png")
                if os.path.isfile(path):
                    images.append((f"{kind} 3x3", postprocess.tiled_sheet(path, 3, scale=1), 1))
                    value = worst(entry.get(kind))
                    body.append(f"{kind}: {report._verdict(value)}")
            cards.append({"title": entry["name"], "images": images,
                          "body": '<div class="scores">' + "<br>".join(body) + "</div>"})
        report.write(args.out, "Tiling audit of existing geometry art",
                     "Each asset repeated three by three. A join you can see in the "
                     "picture is a join the renderer draws in every corridor.",
                     [report.image_cards(args.dir, "worst seam ratio per map; "
                                         f"over {SEAM_GOOD} does not tile", cards)])
        print(f"wrote {args.out}")
    return 0


def cmd_report(args):
    """Write a self-contained HTML page showing what a run actually produced.

    Exists because the scores cannot answer the question that has failed most
    often: is this the material that was asked for? A ratio of 0.6 describes a
    perfect tile of a red hallway just as happily as a perfect tile of grey
    limestone. The page puts the picture next to the number next to the prompt.
    """
    cfg = _config()
    refs = args.runs or ["latest"]
    sections = []
    for ref in refs:
        run_path = staging.resolve_run(_staging_root(cfg), ref)
        manifest = staging.read_manifest(run_path)
        _add_context_previews(run_path, manifest)
        # Always re-score rather than trusting the manifest. The metric has been
        # corrected twice; a page mixing numbers from different versions of it
        # would be worse than no page.
        for variant in manifest.get("variants", []):
            axes = manifest.get("tileAxes", _class_tile_axes(manifest.get("class")))
            variant["tileScore"] = postprocess.tile_seam_score(
                Image.open(os.path.join(run_path, variant["file"])), axes)
        sections.append(report.run_section(run_path, manifest, rank=seam_rank))

    out = args.out or os.path.join(_staging_root(cfg), "report.html")
    report.write(out, args.title or "asset-gen run report",
                 f"wrap and centre seam ratios; 1.0 is as smooth as the texture's "
                 f"own interior, over {SEAM_GOOD} is a join you will see.", sections)
    print(f"wrote {out}")
    return 0


def cmd_ratings(args):
    """Report what the owner's scores say, per knob, beside what the metrics say.

    The rating itself is done in the browser; this is the read-out, so a sweep's
    conclusion can be quoted from a terminal and pasted into a commit message
    without a screenshot.
    """
    root = _staging_root(_config())
    store = ratings.load()
    scored = sum(1 for entry in store.values() if entry.get("score") is not None)
    print(f"{scored} scored variant(s) in {ratings.STORE}")
    if args.prefix:
        print(f"filtered to runs containing '{args.prefix}'")
    for facet in (args.facet or ("model", "lora", "depthWeight", "heightMap", "class")):
        rows = ratings.leaderboard(root, args.prefix, facet)
        if not rows:
            continue
        print(f"\n== by {facet}")
        print(f"{'':28}{'stars':>7}{'n':>5}{'seam':>7}   why not")
        for row in rows:
            seam = "-" if row["seamRatio"] is None else f"{row['seamRatio']:.2f}"
            why = " ".join(f"{tag}x{count}" for tag, count in row["tags"].items())
            print(f"{row['value'][:27]:28}{row['score']:>7.2f}{row['n']:>5}"
                  f"{seam:>7}   {why}")
    if not scored:
        print("\nNothing scored yet. Run the server and open /rate.")
    return 0


def cmd_batch(args):
    """Run many assets from one job file, into one staging run each.

    Sequential on purpose: 4 GB of VRAM holds exactly one model, and running
    these in parallel would only thrash the checkpoint in and out.
    """
    with open(args.jobs, "r", encoding="utf-8") as handle:
        jobs = json.load(handle)
    if isinstance(jobs, dict):
        jobs = jobs.get("jobs", [])

    results = []
    for position, job in enumerate(jobs, 1):
        print(f"\n=== [{position}/{len(jobs)}] {job.get('class')} '{job.get('name')}' ===")
        argv = [job.get("class", args.default_class), job["name"], job.get("description", "")]
        for flag in ("provider", "variants", "extra", "height", "steps", "cfg",
                     "sampler", "seed", "cell", "model", "requestSize", "depthWeight"):
            if job.get(flag) is not None:
                cli_flag = ({"requestSize": "request-size", "depthWeight": "depth-weight"}
                            .get(flag, flag))
                argv += [f"--{cli_flag}", str(job[flag])]
        for lora in job.get("loras") or []:
            if isinstance(lora, dict):
                lora = f"{lora['name']}:{lora.get('weight', 0.8)}"
            argv += ["--lora", str(lora)]
        if job.get("promote", args.promote):
            argv.append("--promote")
        if args.force_dirty:
            argv.append("--force-dirty")
        try:
            code = main(["generate"] + argv)
        except SystemExit as err:            # argparse inside the nested call
            code = err.code or 1
        results.append((job.get("name"), code))

    print("\n=== batch summary ===")
    for name, code in results:
        print(f"  {'ok  ' if code == 0 else 'FAIL'} {name}")
    return 0 if all(code == 0 for _, code in results) else 1


def cmd_promote(args):
    cfg = _config()
    dest = staging.promote(
        _staging_root(cfg), args.run, args.variant, args.rename, args.force,
        args.force_dirty
    )
    print(f"promoted -> {os.path.relpath(dest, classes.ROOT)}")
    print("Review it in-game, then commit the binary deliberately.")
    return 0


# ---------------------------------------------------------------------------
def main(argv=None):
    parser = argparse.ArgumentParser(prog="asset-gen", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("classes", help="list asset classes and their geometry")
    sub.add_parser("models", help="list models and what they cost per image")
    sub.add_parser("runs", help="list staged runs")

    gen = sub.add_parser("generate", help="generate variants of one asset")
    gen.add_argument("asset_class", help="see `classes`")
    gen.add_argument("name", help="asset name, e.g. Kappa (drives the filename)")
    gen.add_argument("description", nargs="?", default="", help="what it looks like")
    gen.add_argument("--variants", type=int, help="candidates to render (default from config)")
    gen.add_argument("--provider", help="gemini | openai | openrouter")
    gen.add_argument("--model", help="override the provider's model (see `models`)")
    gen.add_argument("--quality", choices=["low", "medium", "high"],
                     help="OpenAI render quality; drives cost (default from config)")
    gen.add_argument("--ref", action="append",
                     help="reference image for style matching; repeatable")
    gen.add_argument("--cell", help="override cell size, WxH")
    gen.add_argument("--frames", type=int, help="override frame count")
    gen.add_argument("--grid", help="override the layout asked of the model, ColsxRows")
    gen.add_argument("--request-size", help="size asked of the provider, e.g. 1024x1024")
    gen.add_argument("--token", action="append",
                     help="filename token, e.g. --token fps=12; repeatable")
    gen.add_argument("--extra", default="", help="extra prompt direction")
    gen.add_argument("--dry-run", action="store_true", help="print the prompt, call nothing")
    # Local-model knobs. Ignored by the cloud providers, which have no equivalent.
    gen.add_argument("--steps", type=int, help="[local] denoising steps")
    gen.add_argument("--cfg", type=float, help="[local] CFG scale")
    gen.add_argument("--sampler", help="[local] sampler name, e.g. LCM")
    gen.add_argument("--seed", type=int, help="[local] base seed; variants walk upward")
    gen.add_argument("--prompt-style", choices=["prose", "tags"],
                     help="override how the prompt is written (default: the provider's)")
    gen.add_argument("--no-tiling", action="store_true",
                     help="[local] disable circular padding (tiles are seamless by default)")
    gen.add_argument("--height", help="[local] condition on an authored height map "
                                      "via ControlNet depth, e.g. assets/geometry/x/height.png")
    gen.add_argument("--depth-weight", type=float,
                     help="[local] ControlNet depth weight (default from config)")
    gen.add_argument("--lora", action="append",
                     help="[local] LoRA as NAME or NAME:WEIGHT; repeatable")
    gen.add_argument("--promote", action="store_true",
                     help="promote the best-scoring variant automatically")
    gen.add_argument("--force-dirty", action="store_true",
                     help="allow promoting over a file with uncommitted changes")

    rep = sub.add_parser("reprocess", help="re-run post-processing on staged raw output")
    rep.add_argument("run", nargs="?", default="latest")

    pro = sub.add_parser("promote", help="copy a staged variant into assets/")
    pro.add_argument("run", nargs="?", default="latest")
    pro.add_argument("--variant", type=int, default=1)
    pro.add_argument("--rename", help="promote under a different asset name")
    pro.add_argument("--force", action="store_true", help="overwrite an existing file")
    pro.add_argument("--force-dirty", action="store_true",
                     help="overwrite even if the target has uncommitted changes")

    tile = sub.add_parser("tilecheck", help="score a run's seams and lay it out 3x3")
    tile.add_argument("run", nargs="?", default="latest")
    tile.add_argument("--repeat", type=int, default=3, help="tiles per side (default 3)")

    aud = sub.add_parser("audit", help="score the tiling of art already on disk")
    aud.add_argument("dir", nargs="?", default="assets/geometry")
    aud.add_argument("--out", help="also write a visual HTML report here")

    rep_html = sub.add_parser("report", help="write a self-contained HTML page for run(s)")
    rep_html.add_argument("runs", nargs="*", help="run names, or none for the latest")
    rep_html.add_argument("--out", help="output path (default out/report.html)")
    rep_html.add_argument("--title", help="page title")

    rat = sub.add_parser("ratings", help="report owner scores per model/lora/geometry")
    rat.add_argument("--prefix", default="", help="only runs whose name contains this")
    rat.add_argument("--facet", action="append",
                     choices=("model", "lora", "depthWeight", "heightMap", "class"),
                     help="repeatable; default is every facet")

    bat = sub.add_parser("batch", help="generate many assets from a job file")
    bat.add_argument("jobs", help="JSON list of {class, name, description, ...}")
    bat.add_argument("--default-class", default="surface",
                     help="class for jobs that do not name one")
    bat.add_argument("--promote", action="store_true",
                     help="promote the best variant of every job")
    bat.add_argument("--force-dirty", action="store_true",
                     help="allow promoting over files with uncommitted changes")

    args = parser.parse_args(argv)
    handler = {
        "classes": cmd_classes, "models": cmd_models, "runs": cmd_runs,
        "generate": cmd_generate, "reprocess": cmd_reprocess, "promote": cmd_promote,
        "tilecheck": cmd_tilecheck, "batch": cmd_batch, "ratings": cmd_ratings, "report": cmd_report, "audit": cmd_audit,
    }[args.command]
    try:
        return handler(args)
    except (KeyError, FileNotFoundError, FileExistsError, ValueError, RuntimeError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
