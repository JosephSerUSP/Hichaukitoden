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
import io
import json
import os
import sys
import time

from PIL import Image

# Prompts and manifests are ASCII, but a description passed on the command line
# need not be, and the Windows console's default codepage is not UTF-8.
if hasattr(sys.stdout, "reconfigure"):
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import classes, postprocess, provider, staging  # noqa: E402


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


def _cost_line(cfg, provider_entry, size, variants):
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
        key = "set" if os.environ.get(entry["apiKeyEnv"], "").strip() else "MISSING"
        mark = " (default)" if entry.get("default") else ""
        print(f"{entry['label']}{mark}  [{entry['apiKeyEnv']}: {key}]")
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
    out = postprocess.run(img, ctx, verbose=verbose)
    out_name = f"variant-{index}.png"
    out.save(os.path.join(run_path, out_name))
    return {"index": index, "raw": raw_name, "file": out_name}


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
    text = classes.prompt(ctx, args.name, args.description, args.extra)

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

    variants = args.variants or cfg["generate"]["variants"]
    run_path = staging.run_dir(_staging_root(cfg), args.asset_class, args.name)
    manifest = {
        "class": args.asset_class,
        "name": args.name,
        "description": args.description,
        "options": opts,
        "tokens": tokens,
        "provider": {"id": prov["id"], "model": prov["model"],
                     "quality": prov.get("quality")},
        "estimatedCostUsd": (lambda unit: unit and round(unit * variants, 4))(
            price_per_image(cfg, prov, ctx["requestSize"])[0]),
        "refs": [os.path.relpath(r, classes.ROOT).replace("\\", "/") for r in refs],
        "targetFile": classes.filename(ctx, args.name, tokens),
        "targetDir": ctx["dir"],
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


def cmd_promote(args):
    cfg = _config()
    dest = staging.promote(
        _staging_root(cfg), args.run, args.variant, args.rename, args.force
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

    rep = sub.add_parser("reprocess", help="re-run post-processing on staged raw output")
    rep.add_argument("run", nargs="?", default="latest")

    pro = sub.add_parser("promote", help="copy a staged variant into assets/")
    pro.add_argument("run", nargs="?", default="latest")
    pro.add_argument("--variant", type=int, default=1)
    pro.add_argument("--rename", help="promote under a different asset name")
    pro.add_argument("--force", action="store_true", help="overwrite an existing file")

    args = parser.parse_args(argv)
    handler = {
        "classes": cmd_classes, "models": cmd_models, "runs": cmd_runs,
        "generate": cmd_generate, "reprocess": cmd_reprocess, "promote": cmd_promote,
    }[args.command]
    try:
        return handler(args)
    except (KeyError, FileNotFoundError, FileExistsError, ValueError, RuntimeError) as err:
        print(f"error: {err}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
