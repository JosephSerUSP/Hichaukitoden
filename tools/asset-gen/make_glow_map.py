#!/usr/bin/env python3
"""Derive an emission (glow) mask from an albedo atlas.

The engine samples the glow map at the albedo's own uv, so this writes a
grayscale PNG of exactly the atlas's dimensions where white means "this texel
emits its own colour and ignores the light in the room" and black means "light
this texel normally". Nothing here is clever: it selects texels by hue,
saturation and value, feathers the selection, and reports coverage. The output
is meant to be hand-edited afterwards -- it is a starting mask, not an oracle.

Why derive rather than paint from scratch: the emissive parts of a texture are
almost always already the saturated bright ones, and a selection that starts
from the albedo can never glow where there is nothing to glow.

Determinism: same input plus same flags gives byte-identical output.
"""
from __future__ import annotations

import argparse
import colorsys
import json
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parents[2]


def hue_distance(hue: np.ndarray, center: float) -> np.ndarray:
    """Circular distance on the hue wheel, in turns (0..0.5)."""
    raw = np.abs(hue - center)
    return np.minimum(raw, 1.0 - raw)


def build_mask(albedo: Image.Image, hue_center, hue_width, min_sat, min_val,
               gain, feather, sat_full=None, val_full=None):
    rgb = np.asarray(albedo.convert("RGB"), dtype=np.float32) / 255.0
    maxc = rgb.max(axis=2)
    minc = rgb.min(axis=2)
    value = maxc
    chroma = maxc - minc
    # Saturation as HSV, guarding the black pixels where it is undefined.
    sat = np.where(maxc > 0.0, chroma / np.maximum(maxc, 1e-6), 0.0)

    # Vectorised hue, matching colorsys' convention so --hue-center can be read
    # off any colour picker.
    hue = np.zeros_like(value)
    safe = chroma > 1e-6
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    with np.errstate(invalid="ignore"):
        is_r = safe & (maxc == r)
        is_g = safe & (maxc == g) & ~is_r
        is_b = safe & ~is_r & ~is_g
        hue[is_r] = ((g[is_r] - b[is_r]) / chroma[is_r] % 6.0) / 6.0
        hue[is_g] = ((b[is_g] - r[is_g]) / chroma[is_g] + 2.0) / 6.0
        hue[is_b] = ((r[is_b] - g[is_b]) / chroma[is_b] + 4.0) / 6.0

    # Each term is a 0..1 ramp rather than a hard threshold, so the mask has a
    # gradient at its edges and a glowing gem does not get a stairstep halo.
    #
    # The ramps top out at the image's OWN high percentile, not at 1.0. Game
    # textures are rarely near-white or fully saturated -- this atlas peaks at
    # value 0.82 -- and normalising against the theoretical maximum silently
    # crushes the whole mask toward zero, which reads as "the selection missed"
    # when in fact the selection was right and only the scale was wrong.
    if sat_full is None:
        sat_full = float(np.percentile(sat, 99.0))
    if val_full is None:
        val_full = float(np.percentile(value, 99.0))
    sat_full = max(sat_full, min_sat + 1e-3)
    val_full = max(val_full, min_val + 1e-3)
    sat_term = np.clip((sat - min_sat) / (sat_full - min_sat), 0.0, 1.0)
    val_term = np.clip((value - min_val) / (val_full - min_val), 0.0, 1.0)
    mask = sat_term * val_term
    if hue_center is not None:
        dist = hue_distance(hue, hue_center)
        hue_term = np.clip(1.0 - dist / max(1e-6, hue_width), 0.0, 1.0)
        mask = mask * hue_term

    mask = np.clip(mask * gain, 0.0, 1.0)
    out = Image.fromarray((mask * 255.0 + 0.5).astype(np.uint8), mode="L")
    if feather > 0:
        out = out.filter(ImageFilter.GaussianBlur(radius=feather))
    return out


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--atlas", required=True, help="albedo atlas PNG (repo-relative or absolute)")
    ap.add_argument("--out", required=True, help="glow mask PNG to write")
    ap.add_argument("--hue-center", type=float, default=None,
                    help="hue to select, 0..1 (0.5 = cyan, 0.08 = flame orange). "
                         "Omit to select purely on saturation and value.")
    ap.add_argument("--hue-width", type=float, default=0.08,
                    help="half-width of the hue window in turns (default 0.08)")
    ap.add_argument("--min-saturation", type=float, default=0.45)
    ap.add_argument("--min-value", type=float, default=0.45)
    ap.add_argument("--sat-full", type=float, default=None,
                    help="saturation that counts as fully emissive "
                         "(default: the atlas's own 99th percentile)")
    ap.add_argument("--val-full", type=float, default=None,
                    help="value that counts as fully emissive "
                         "(default: the atlas's own 99th percentile)")
    ap.add_argument("--gain", type=float, default=1.0,
                    help="multiplies the mask before clamping; >1 hardens it")
    ap.add_argument("--feather", type=float, default=0.6,
                    help="gaussian blur radius in texels (default 0.6)")
    ap.add_argument("--dry-run", action="store_true",
                    help="report coverage without writing")
    args = ap.parse_args(argv)

    atlas_path = Path(args.atlas)
    if not atlas_path.is_absolute():
        atlas_path = ROOT / atlas_path
    if not atlas_path.is_file():
        raise SystemExit(f"atlas not found: {atlas_path}")
    albedo = Image.open(atlas_path)

    mask = build_mask(albedo, args.hue_center, args.hue_width,
                      args.min_saturation, args.min_value, args.gain, args.feather,
                      args.sat_full, args.val_full)
    arr = np.asarray(mask, dtype=np.float32) / 255.0
    report = {
        "atlas": str(atlas_path.relative_to(ROOT)) if atlas_path.is_relative_to(ROOT) else str(atlas_path),
        "size": f"{albedo.width}x{albedo.height}",
        "emissiveTexelsPct": round(float((arr > 0.02).mean()) * 100.0, 3),
        "fullyEmissivePct": round(float((arr > 0.98).mean()) * 100.0, 3),
        "meanGlow": round(float(arr.mean()), 4),
    }
    if not args.dry_run:
        out_path = Path(args.out)
        if not out_path.is_absolute():
            out_path = ROOT / out_path
        out_path.parent.mkdir(parents=True, exist_ok=True)
        mask.save(out_path)
        report["out"] = str(out_path.relative_to(ROOT)) if out_path.is_relative_to(ROOT) else str(out_path)
    print(json.dumps(report, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
