#!/usr/bin/env python3
"""Post-process Second Rite model-census review captures.

This is deliberately stricter than the invalidated v1 review:
- a declared index path is not evidence; only success=true + an existing PNG counts;
- structured manifest exclusions are removed from the required matrix;
- failed captures remain failures instead of satisfying completeness;
- decision sheets compare neutral-gray diagnostic and legacy First Stratum context;
- model-vs-control adapter smoke evidence is surfaced explicitly;
- review.csv is merged non-destructively;
- compact decision evidence is published into a tracked docs directory while the
  exhaustive frame archive may remain under out/.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
import shutil
import sys
from dataclasses import dataclass
from datetime import datetime, timezone
from pathlib import Path
from typing import Any, Iterable

from PIL import Image, ImageDraw, ImageFont

DEFAULT_OUT = Path("out/model-census-review")
DEFAULT_MANIFEST = Path("tools/asset-production/review_manifest.json")
DEFAULT_PUBLISH = Path("docs/reports/second-rite-model-census/artifacts/current")
CONTACT_NAMES = (
    "tier_a_stateful.png",
    "tier_b_architecture.png",
    "tier_c_environment.png",
    "paired_states.png",
    "distance_readability.png",
    "adapter_smoke.png",
    "failures.png",
)


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for chunk in iter(lambda: f.read(1024 * 1024), b""):
            h.update(chunk)
    return h.hexdigest()


def read_json(path: Path) -> Any:
    with path.open("r", encoding="utf-8") as f:
        return json.load(f)


def recover_jsonl(path: Path) -> tuple[list[dict[str, Any]], list[str]]:
    """Recover every complete JSON object from a streaming journal.

    The harness flushes one object per line. A killed process may leave a final
    partial line; preserve its text as a recovery warning instead of discarding
    the preceding valid evidence.
    """
    rows: list[dict[str, Any]] = []
    warnings: list[str] = []
    if not path.exists():
        return rows, [f"journal missing: {path}"]
    with path.open("r", encoding="utf-8", errors="replace") as f:
        for line_no, line in enumerate(f, 1):
            text = line.strip()
            if not text:
                continue
            try:
                value = json.loads(text)
            except json.JSONDecodeError as exc:
                warnings.append(f"line {line_no}: incomplete/invalid JSONL record ({exc.msg})")
                continue
            if isinstance(value, dict):
                rows.append(value)
            else:
                warnings.append(f"line {line_no}: JSONL record is not an object")
    return rows, warnings


def rule_matches(rule: dict[str, Any], fields: dict[str, Any]) -> bool:
    match = rule.get("match") or {}
    return bool(match) and all(fields.get(k) == v for k, v in match.items())


def skip_rule(manifest: dict[str, Any], fields: dict[str, Any]) -> dict[str, Any] | None:
    for rule in manifest.get("skip_rules", []):
        if rule_matches(rule, fields):
            return rule
    return None


def iter_matrix(manifest: dict[str, Any]) -> Iterable[dict[str, Any]]:
    for asset in manifest.get("assets", []):
        aid = asset["asset_id"]
        for state in asset.get("states", []):
            for context in state.get("contexts", []):
                for distance in state.get("distances", []):
                    for angle in state.get("angles", []):
                        for lighting in state.get("lighting", []):
                            fields = {
                                "asset_id": aid,
                                "state": state["state"],
                                "context": context,
                                "distance": distance,
                                "angle": angle,
                                "lighting": lighting,
                            }
                            fields["path"] = (
                                f"{aid}/{context}__{distance}__{angle}__{lighting}__{state['state']}.png"
                            )
                            fields["skip_rule"] = skip_rule(manifest, fields)
                            yield fields


def logical_key(entry: dict[str, Any]) -> tuple[Any, ...]:
    return (
        entry.get("asset_id"),
        entry.get("state"),
        entry.get("context"),
        entry.get("distance"),
        entry.get("angle"),
        entry.get("lighting"),
    )


def normalize_rel_path(entry_path: str) -> str:
    p = entry_path.replace("\\", "/")
    prefix = "out/model-census-review/"
    return p[len(prefix):] if p.startswith(prefix) else p


@dataclass
class CaptureDiagnostics:
    full_count: int
    required_count: int
    skipped_count: int
    successful_count: int
    failed_count: int
    missing_paths: list[str]
    duplicate_keys: list[tuple[Any, ...]]
    failed_entries: list[dict[str, Any]]
    skipped_entries: list[dict[str, Any]]
    orphan_success_paths: list[str]

    @property
    def complete(self) -> bool:
        return not self.missing_paths and not self.duplicate_keys and self.failed_count == 0


def process_captures(
    manifest: dict[str, Any],
    index_entries: list[dict[str, Any]],
    out_dir: Path | str = DEFAULT_OUT,
) -> CaptureDiagnostics:
    out_dir = Path(out_dir)
    matrix = list(iter_matrix(manifest))
    required = [row for row in matrix if not row["skip_rule"]]
    skipped_matrix = [row for row in matrix if row["skip_rule"]]
    expected_paths = {row["path"] for row in required}

    by_key: dict[tuple[Any, ...], dict[str, Any]] = {}
    duplicates: list[tuple[Any, ...]] = []
    failed_entries: list[dict[str, Any]] = []
    skipped_entries: list[dict[str, Any]] = []
    successful_paths: set[str] = set()

    for entry in index_entries:
        key = logical_key(entry)
        if key in by_key:
            duplicates.append(key)
        else:
            by_key[key] = entry

        rel = normalize_rel_path(str(entry.get("path", "")))
        if entry.get("skipped"):
            skipped_entries.append(entry)
            continue
        if entry.get("success") is True:
            full_path = out_dir / rel
            # Critical v2 rule: metadata is not a frame. The PNG must exist.
            if rel and full_path.is_file():
                successful_paths.add(rel)
            else:
                failed_entries.append({**entry, "error": entry.get("error") or "success metadata points to missing PNG"})
        else:
            failed_entries.append(entry)

    missing = sorted(expected_paths - successful_paths)
    orphans = sorted(successful_paths - expected_paths)
    return CaptureDiagnostics(
        full_count=len(matrix),
        required_count=len(required),
        skipped_count=len(skipped_matrix),
        successful_count=len(successful_paths),
        failed_count=len(failed_entries),
        missing_paths=missing,
        duplicate_keys=duplicates,
        failed_entries=failed_entries,
        skipped_entries=skipped_entries,
        orphan_success_paths=orphans,
    )


def merge_review_csv(csv_path: Path | str, manifest_assets: list[dict[str, Any]]) -> None:
    csv_path = Path(csv_path)
    fieldnames = [
        "asset_id",
        "recognition",
        "spatialFunction",
        "styleIntegration",
        "materialHierarchy",
        "screenEconomy",
        "emotionalFunction",
        "verdict",
        "notes",
    ]
    existing: dict[str, dict[str, str]] = {}
    if csv_path.exists():
        with csv_path.open("r", newline="", encoding="utf-8") as f:
            for row in csv.DictReader(f):
                aid = row.get("asset_id")
                if aid:
                    existing[aid] = {name: row.get(name, "") for name in fieldnames}

    rows: list[dict[str, str]] = []
    for asset in manifest_assets:
        aid = asset["asset_id"]
        rows.append(existing.get(aid, {name: (aid if name == "asset_id" else "") for name in fieldnames}))

    csv_path.parent.mkdir(parents=True, exist_ok=True)
    with csv_path.open("w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def border_occupancy(path: Path, border: int = 2) -> float:
    """Heuristic used only as a warning for likely near-plane/edge clipping."""
    with Image.open(path) as source:
        img = source.convert("RGB")
    w, h = img.size
    if w <= border * 2 or h <= border * 2:
        return 1.0
    # Estimate background from a small center cross. Corners are deliberately
    # NOT used because the failure we are detecting is geometry plastered to
    # the frame edge; such geometry can occupy all four corners.
    cx, cy = w // 2, h // 2
    samples = [
        img.getpixel((cx, cy)),
        img.getpixel((max(0, cx - 1), cy)),
        img.getpixel((min(w - 1, cx + 1), cy)),
        img.getpixel((cx, max(0, cy - 1))),
        img.getpixel((cx, min(h - 1, cy + 1))),
    ]
    bg = tuple(sum(c[i] for c in samples) / len(samples) for i in range(3))
    coords: list[tuple[int, int]] = []
    for y in range(h):
        for x in range(w):
            if x < border or x >= w - border or y < border or y >= h - border:
                coords.append((x, y))
    occupied = 0
    for x, y in coords:
        px = img.getpixel((x, y))
        if sum(abs(px[i] - bg[i]) for i in range(3)) > 72:
            occupied += 1
    return occupied / max(1, len(coords))


def _font() -> ImageFont.ImageFont:
    try:
        return ImageFont.load_default()
    except Exception:
        return None  # type: ignore[return-value]


def make_contact_sheet(
    images_info: list[dict[str, Any]],
    output_path: Path | str,
    cols: int,
    tile_w: int = 256,
    tile_h: int = 240,
    header_h: int = 30,
) -> None:
    output_path = Path(output_path)
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if not images_info:
        Image.new("RGB", (tile_w, tile_h), color=(30, 30, 30)).save(output_path)
        return
    rows = (len(images_info) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tile_w, rows * (tile_h + header_h)), color=(18, 18, 22))
    draw = ImageDraw.Draw(sheet)
    font = _font()
    for idx, info in enumerate(images_info):
        row, col = divmod(idx, cols)
        x, y = col * tile_w, row * (tile_h + header_h)
        draw.rectangle((x, y, x + tile_w, y + header_h), fill=(40, 44, 52))
        draw.text((x + 5, y + 6), str(info.get("label", ""))[:45], fill=(232, 232, 232), font=font)
        img_path = Path(info["full_path"]) if info.get("full_path") else None
        if img_path and img_path.is_file():
            try:
                with Image.open(img_path) as src:
                    tile = src.convert("RGB")
                    if tile.size != (tile_w, tile_h):
                        tile = tile.resize((tile_w, tile_h), Image.Resampling.NEAREST)
                    sheet.paste(tile, (x, y + header_h))
            except Exception as exc:
                draw.rectangle((x, y + header_h, x + tile_w, y + header_h + tile_h), fill=(72, 18, 18))
                draw.text((x + 6, y + header_h + 10), f"ERROR {exc}"[:42], fill=(255, 160, 160), font=font)
        else:
            draw.rectangle((x, y + header_h, x + tile_w, y + header_h + tile_h), fill=(62, 18, 18))
            msg = str(info.get("message") or "MISSING")
            draw.text((x + 6, y + header_h + 10), msg[:42], fill=(255, 170, 170), font=font)
    sheet.save(output_path)


def build_entry_map(index_entries: list[dict[str, Any]], out_dir: Path) -> dict[tuple[Any, ...], dict[str, Any]]:
    result: dict[tuple[Any, ...], dict[str, Any]] = {}
    for entry in index_entries:
        if entry.get("success") is not True or entry.get("skipped"):
            continue
        rel = normalize_rel_path(str(entry.get("path", "")))
        full = out_dir / rel
        if full.is_file():
            result[logical_key(entry)] = {**entry, "full_path": str(full)}
    return result


def _tile(entry_map: dict[tuple[Any, ...], dict[str, Any]], key: tuple[Any, ...], label: str) -> dict[str, Any]:
    entry = entry_map.get(key)
    return {"full_path": entry.get("full_path") if entry else None, "label": label, "message": "MISSING"}


def generate_all_contact_sheets(
    out_dir: Path | str,
    manifest: dict[str, Any],
    index_entries: list[dict[str, Any]],
    diagnostics: CaptureDiagnostics | None = None,
) -> None:
    out_dir = Path(out_dir)
    sheets = out_dir / "contact-sheets"
    sheets.mkdir(parents=True, exist_ok=True)
    emap = build_entry_map(index_entries, out_dir)

    tiers: dict[str, list[dict[str, Any]]] = {"Tier A": [], "Tier B": [], "Tier C": []}
    paired: list[dict[str, Any]] = []
    distance: list[dict[str, Any]] = []

    for asset in manifest.get("assets", []):
        aid, display, tier = asset["asset_id"], asset.get("display_name", asset["asset_id"]), asset.get("tier", "Tier A")
        states = asset.get("states", [])
        for state in states:
            st = state["state"]
            # Four-column primary row: neutral F/O, legacy-context F/O.
            for context, angle, short in (
                ("neutral", "frontal", "N/F"),
                ("neutral", "oblique", "N/O"),
                ("first_stratum", "frontal", "FS/F"),
                ("first_stratum", "oblique", "FS/O"),
            ):
                key = (aid, st, context, "one_cell", angle, "normal")
                tiers.setdefault(tier, []).append(_tile(emap, key, f"{display} [{st}] {short}"))
            for dist in ("close", "one_cell", "far"):
                key = (aid, st, "neutral", dist, "frontal", "normal")
                distance.append(_tile(emap, key, f"{display} [{st}] {dist}"))

        if len(states) > 1:
            a, b = states[0]["state"], states[1]["state"]
            # Two rows per concept (frontal then oblique), four columns compare state A/B in both environments.
            for angle in ("frontal", "oblique"):
                for context, short in (("neutral", "N"), ("first_stratum", "FS")):
                    for st in (a, b):
                        key = (aid, st, context, "one_cell", angle, "normal")
                        paired.append(_tile(emap, key, f"{display} {short}/{angle[0].upper()} [{st}]"))

    make_contact_sheet(tiers.get("Tier A", []), sheets / "tier_a_stateful.png", cols=4)
    make_contact_sheet(tiers.get("Tier B", []), sheets / "tier_b_architecture.png", cols=4)
    make_contact_sheet(tiers.get("Tier C", []), sheets / "tier_c_environment.png", cols=4)
    make_contact_sheet(paired, sheets / "paired_states.png", cols=4)
    make_contact_sheet(distance, sheets / "distance_readability.png", cols=3)

    smoke_info: list[dict[str, Any]] = []
    smoke_path = out_dir / "smoke.json"
    if smoke_path.exists():
        smoke = read_json(smoke_path)
        for item in smoke.get("adapters", []):
            for variant in ("control", "model"):
                rel = item.get(variant)
                smoke_info.append({
                    "full_path": str(out_dir / rel) if rel else None,
                    "label": f"{item.get('adapter')} {variant} delta={item.get('changed_pixels', '?')}",
                })
    make_contact_sheet(smoke_info, sheets / "adapter_smoke.png", cols=2)

    failure_info: list[dict[str, Any]] = []
    failures = diagnostics.failed_entries if diagnostics else [e for e in index_entries if not e.get("success") and not e.get("skipped")]
    for entry in failures:
        failure_info.append({
            "full_path": None,
            "label": f"{entry.get('asset_id')} [{entry.get('state')}]",
            "message": str(entry.get("error") or "FAILED"),
        })
    make_contact_sheet(failure_info, sheets / "failures.png", cols=2)


def clipping_warnings(out_dir: Path, index_entries: list[dict[str, Any]], threshold: float = 0.55) -> list[dict[str, Any]]:
    warnings: list[dict[str, Any]] = []
    for entry in index_entries:
        if entry.get("success") is not True or entry.get("skipped"):
            continue
        rel = normalize_rel_path(str(entry.get("path", "")))
        path = out_dir / rel
        if not path.is_file():
            continue
        occupancy = border_occupancy(path)
        if occupancy >= threshold:
            warnings.append({"path": rel, "border_occupancy": occupancy})
    return warnings


def write_diagnostics(out_dir: Path, diagnostics: CaptureDiagnostics, clip_warnings: list[dict[str, Any]], journal_warnings: list[str]) -> Path:
    data = {
        "full_matrix_count": diagnostics.full_count,
        "required_capture_count": diagnostics.required_count,
        "skipped_capture_count": diagnostics.skipped_count,
        "successful_png_count": diagnostics.successful_count,
        "failed_capture_count": diagnostics.failed_count,
        "missing_required_pngs": diagnostics.missing_paths,
        "duplicate_logical_keys": [list(k) for k in diagnostics.duplicate_keys],
        "orphan_success_paths": diagnostics.orphan_success_paths,
        "clipping_warnings": clip_warnings,
        "journal_recovery_warnings": journal_warnings,
        "complete": diagnostics.complete,
    }
    path = out_dir / "diagnostics.json"
    path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    return path


def publish_evidence(out_dir: Path | str, publish_dir: Path | str = DEFAULT_PUBLISH) -> dict[str, Any]:
    out_dir, publish_dir = Path(out_dir), Path(publish_dir)
    publish_dir.mkdir(parents=True, exist_ok=True)
    files: list[Path] = []
    for name in ("run.json", "index.json", "captures.jsonl", "review.csv", "smoke.json", "diagnostics.json"):
        src = out_dir / name
        if src.is_file():
            dst = publish_dir / name
            shutil.copy2(src, dst)
            files.append(dst)
    for name in CONTACT_NAMES:
        src = out_dir / "contact-sheets" / name
        if src.is_file():
            dst = publish_dir / "contact-sheets" / name
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            files.append(dst)
    smoke_dir = out_dir / "smoke"
    if smoke_dir.is_dir():
        for src in sorted(smoke_dir.glob("*.png")):
            dst = publish_dir / "smoke" / src.name
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
            files.append(dst)

    manifest = {
        "schema": 1,
        "generated_at_utc": datetime.now(timezone.utc).isoformat(),
        "policy": "Tracked decision evidence only. Exhaustive raw frame archive remains under out/model-census-review.",
        "files": [
            {
                "path": str(path.relative_to(publish_dir)).replace("\\", "/"),
                "bytes": path.stat().st_size,
                "sha256": sha256_file(path),
            }
            for path in sorted(files)
        ],
    }
    manifest_path = publish_dir / "artifact-manifest.json"
    manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
    return manifest


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out-dir", type=Path, default=DEFAULT_OUT)
    parser.add_argument("--manifest", type=Path, default=DEFAULT_MANIFEST)
    parser.add_argument("--publish-dir", type=Path, default=DEFAULT_PUBLISH)
    parser.add_argument("--no-publish", action="store_true")
    args = parser.parse_args(argv)

    if not args.manifest.is_file():
        print(f"manifest not found: {args.manifest}", file=sys.stderr)
        return 2
    if not (args.out_dir / "index.json").is_file():
        print(f"index not found: {args.out_dir / 'index.json'}", file=sys.stderr)
        return 2

    manifest = read_json(args.manifest)
    index_entries = read_json(args.out_dir / "index.json")
    if not isinstance(index_entries, list):
        print("index.json must contain a list", file=sys.stderr)
        return 2

    journal_rows, journal_warnings = recover_jsonl(args.out_dir / "captures.jsonl")
    diagnostics = process_captures(manifest, index_entries, args.out_dir)
    merge_review_csv(args.out_dir / "review.csv", manifest.get("assets", []))
    generate_all_contact_sheets(args.out_dir, manifest, index_entries, diagnostics)
    clip_warnings = clipping_warnings(args.out_dir, index_entries)
    write_diagnostics(args.out_dir, diagnostics, clip_warnings, journal_warnings)

    print(
        "[review_model_census] "
        f"full={diagnostics.full_count} required={diagnostics.required_count} skipped={diagnostics.skipped_count} "
        f"successful_pngs={diagnostics.successful_count} failed={diagnostics.failed_count} "
        f"missing={len(diagnostics.missing_paths)} duplicates={len(diagnostics.duplicate_keys)} "
        f"journal_rows={len(journal_rows)}"
    )

    if not args.no_publish:
        published = publish_evidence(args.out_dir, args.publish_dir)
        print(f"[review_model_census] published {len(published['files'])} tracked decision artifacts to {args.publish_dir}")

    if not diagnostics.complete:
        print("[review_model_census] REVIEW INCOMPLETE: do not approve subjective scores/verdicts", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
