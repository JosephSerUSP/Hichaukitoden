"""Resume-safe first-stratum material-family run.

This is an orchestration layer over gen.py. It deliberately does not implement
another image pipeline: Forge, ControlNet, post-processing, seam metrics and
engine previews all remain the repository's existing path.
"""

from __future__ import annotations

import argparse
import base64
import ctypes
import datetime as dt
import html
import io
import json
import os
import re
import subprocess
import sys
import time
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
TOOL = ROOT / "tools" / "asset-gen"
OUT = TOOL / "out" / "first-stratum-overnight"
SPEC_PATH = TOOL / "first_stratum_materials.json"
STATE_PATH = OUT / "status.json"
JOBS_PATH = OUT / "jobs.json"
REPORT_PATH = OUT / "first-stratum-material-family-report.html"
SUMMARY_PATH = OUT / "summary.json"
MARKDOWN_PATH = OUT / "summary.md"
PYTHON = sys.executable

sys.path.insert(0, str(TOOL))
from lib import classes, postprocess, staging  # noqa: E402
import gen as asset_gen  # noqa: E402


def now():
    return dt.datetime.now().isoformat(timespec="seconds")


def atomic_json(path: Path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp = path.with_suffix(path.suffix + ".tmp")
    temp.write_text(json.dumps(value, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
    temp.replace(path)


def safe(value):
    return re.sub(r"[^\w\-]", "_", str(value)).strip("_") or "unnamed"


def geometry_records():
    path = ROOT / "assets" / "geometry" / "1_blender_depth_maps" / "manifest.json"
    data = json.loads(path.read_text(encoding="utf-8"))
    records = {}
    for item in data.get("maps", []):
        if item.get("wrapOk", True) is not True:
            continue
        preset = item.get("preset")
        if not preset or item.get("surface") not in ("wall", "floor", "ceiling"):
            continue
        rel = Path("assets/geometry/1_blender_depth_maps") / f"{preset}.png"
        if (ROOT / rel).is_file():
            records[preset] = {**item, "path": rel.as_posix()}
    return records


def load_spec():
    return json.loads(SPEC_PATH.read_text(encoding="utf-8"))


def description(family, surface, preset, variation=""):
    role = family["role"]
    state = family["state"]
    palette = family["palette"]
    surface_word = {"wall": "wall", "floor": "floor", "ceiling": "ceiling"}[surface]
    return (f"{family['label']}, {surface_word} material, {role}, {state}, {palette}, "
            f"authored {preset.replace('_', ' ')} geometry, flat head-on diffuse albedo, "
            f"quiet sacred undercroft, sharp detailed source texture, {variation}".strip(
                ", "))


def make_job(job_id, family, surface, preset, seed, variation=0, pair=None, side=None):
    spec = load_spec()
    family_id = family["id"]
    extra = ""
    if pair:
        extra = pair["a"] if side == "A" else pair["b"]
    else:
        variants = [
            "subtle localized mineral variation",
            "small areas of repair, wear and material history",
            "uneven age with restrained environmental storytelling",
        ]
        extra = variants[variation % len(variants)]
    name = f"first_stratum_{job_id}"
    return {
        "jobId": job_id,
        "name": name,
        "class": "wallPiece" if surface == "wall" else "texturePiece",
        "surface": surface,
        "geometryPreset": preset,
        "geometryMapPath": f"assets/geometry/1_blender_depth_maps/{preset}.png",
        "materialFamily": family_id,
        "materialFamilyLabel": family["label"],
        "architecturalRole": family["role"],
        "environmentalState": family["state"],
        "paletteBias": family["palette"],
        "promptFamilyId": family_id,
        "description": description(family, surface, preset, extra),
        "provider": spec["provider"],
        "model": spec["model"],
        "variants": spec["variantsPerJob"],
        "steps": spec["steps"],
        "cfg": spec["cfg"],
        "sampler": spec["sampler"],
        "seed": seed,
        "depthWeight": spec["depthWeight"],
        "requestSize": spec["requestSize"],
        "negativeExtra": spec["negativeExtra"],
        "pairId": pair["id"] if pair else None,
        "pairSide": side,
        "pairVariable": pair["variable"] if pair else None,
        "variation": variation + 1,
    }


def build_jobs():
    """Expand the compatibility matrix against the live geometry manifest."""
    spec = load_spec()
    maps = geometry_records()
    families = {f["id"]: f for f in spec["materialFamilies"]}
    by_surface = {s: [] for s in ("wall", "floor", "ceiling")}
    pairs_by_surface = {s: [] for s in by_surface}
    for pair_index, pair in enumerate(spec["abPairs"]):
        if pair["map"] not in maps or maps[pair["map"]]["surface"] != pair["surface"]:
            raise RuntimeError(f"A/B pair {pair['id']} references unavailable geometry {pair['map']}")
        family = families[pair["family"]]
        for side_index, side in enumerate(("A", "B")):
            job = make_job(
                f"ab_{pair['id']}_{side}", family, pair["surface"], pair["map"],
                140000 + pair_index * 100, pair=pair, side=side,
            )
            by_surface[pair["surface"]].append(job)
            pairs_by_surface[pair["surface"]].append(job)

    # Add one job per compatible family/map first, then a small number of
    # distinct material-state variations until the requested quota is reached.
    for surface in by_surface:
        base = []
        for family_index, family in enumerate(spec["materialFamilies"]):
            for preset in family.get("maps", {}).get(surface, []):
                record = maps.get(preset)
                if not record or record["surface"] != surface:
                    continue
                base.append((family_index, family, preset))
        target = spec["targetJobs"][surface]
        production_target = target - len(by_surface[surface])
        if production_target < len(base):
            raise RuntimeError(f"{surface} target is smaller than its compatibility matrix")
        jobs = []
        counts = {}
        for family_index, family, preset in base:
            key = (family["id"], preset)
            counts[key] = 1
            jobs.append(make_job(
                f"prod_{family['id']}_{preset}_v1", family, surface, preset,
                180000 + family_index * 10000 + len(jobs) * 17, variation=0,
            ))
        cursor = 0
        while len(jobs) < production_target:
            family_index, family, preset = base[cursor % len(base)]
            cursor += 1
            key = (family["id"], preset)
            if counts[key] >= 3:
                if cursor > len(base) * 10:
                    raise RuntimeError(f"could not fill {surface} quota without overusing a concept/map")
                continue
            counts[key] += 1
            jobs.append(make_job(
                f"prod_{family['id']}_{preset}_v{counts[key]}", family, surface, preset,
                180000 + family_index * 10000 + len(jobs) * 17, variation=counts[key] - 1,
            ))
        # Put the pair jobs at the beginning of each surface section. The
        # report preserves this ordering and keeps each pair's A/B cards together.
        by_surface[surface] = by_surface[surface] + jobs

    output = []
    for surface in ("wall", "floor", "ceiling"):
        output.extend(by_surface[surface])
    if {s: sum(1 for j in output if j["surface"] == s) for s in by_surface} != spec["targetJobs"]:
        raise RuntimeError("job quotas did not expand to the requested counts")
    return output


def summary_for_jobs(jobs):
    return {
        "jobs": len(jobs),
        "candidates": sum(j["variants"] for j in jobs),
        "bySurface": {
            surface: {
                "jobs": sum(1 for j in jobs if j["surface"] == surface),
                "candidates": sum(j["variants"] for j in jobs if j["surface"] == surface),
            } for surface in ("wall", "floor", "ceiling")
        },
        "abCandidates": sum(j["variants"] for j in jobs if j.get("pairId")),
        "families": sorted({j["materialFamily"] for j in jobs}),
    }


def run_dir_for(job):
    root = TOOL / "out"
    prefix = f"{job['class']}-{safe(job['name'])}-"
    candidates = []
    for path in root.glob(prefix + "*"):
        manifest_path = path / "manifest.json"
        if not manifest_path.is_file():
            continue
        try:
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        if manifest.get("name") != job["name"]:
            continue
        if len(manifest.get("variants") or []) < job["variants"]:
            continue
        if any(not (path / v.get("file", "")).is_file() for v in manifest.get("variants", [])):
            continue
        candidates.append(path)
    return max(candidates, key=lambda p: p.stat().st_mtime) if candidates else None


def augment_manifest(job, run_path, status="success", error=None):
    manifest_path = run_path / "manifest.json"
    manifest = json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.is_file() else {
        "class": job["class"], "name": job["name"], "variants": []
    }
    prompt = (run_path / "prompt.txt").read_text(encoding="utf-8") if (run_path / "prompt.txt").is_file() else job["description"]
    sampling = (manifest.get("provider") or {}).get("sampling") or {}
    overnight = {
        "jobId": job["jobId"], "candidateIdBase": job["jobId"], "surfaceType": job["surface"],
        "assetClass": job["class"], "geometryPreset": job["geometryPreset"],
        "geometryMapPath": job["geometryMapPath"], "materialFamily": job["materialFamily"],
        "materialFamilyLabel": job["materialFamilyLabel"], "architecturalRole": job["architecturalRole"],
        "environmentalState": job["environmentalState"], "paletteBias": job["paletteBias"],
        "promptFamilyId": job["promptFamilyId"], "exactPositivePrompt": prompt,
        "exactNegativePrompt": sampling.get("negativePrompt", ""), "model": job["model"],
        "loras": sampling.get("loras") or [], "sampler": sampling.get("sampler"),
        "steps": sampling.get("steps"), "cfg": sampling.get("cfgScale"), "seed": sampling.get("seed"),
        "depthWeight": manifest.get("provider", {}).get("heightControlWeight"),
        "activeWrapAxes": manifest.get("tileAxes"), "pairId": job.get("pairId"),
        "pairSide": job.get("pairSide"), "pairVariable": job.get("pairVariable"),
        "generationStatus": status, "error": error, "curation": {"decision": "unset", "notes": "", "tags": []},
        "updatedAt": now(),
    }
    manifest["overnight"] = overnight
    manifest["overnightJob"] = job
    for variant in manifest.get("variants", []):
        index = variant.get("index")
        variant["candidateId"] = f"{job['jobId']}#v{index}"
        variant["rawImagePath"] = (run_path / variant.get("raw", "")).relative_to(ROOT).as_posix() if variant.get("raw") else None
        variant["processedImagePath"] = (run_path / variant.get("file", "")).relative_to(ROOT).as_posix() if variant.get("file") else None
        variant["contextPreviewPaths"] = [
            (run_path / variant["context"]).relative_to(ROOT).as_posix()
        ] if variant.get("context") else []
        variant.setdefault("curation", {"decision": "unset", "notes": "", "tags": []})
        variant["generationStatus"] = status
    atomic_json(manifest_path, manifest)
    return manifest


def keep_awake(enable=True):
    if os.name != "nt":
        return
    try:
        kernel = ctypes.windll.kernel32
        flags = 0x80000000 | (0x00000001 if enable else 0)
        kernel.SetThreadExecutionState(flags)
    except Exception:
        pass


def state_template(jobs, mode="run"):
    return {"schemaVersion": 1, "mode": mode, "startedAt": now(), "updatedAt": now(), "summary": summary_for_jobs(jobs),
            "jobs": [{"jobId": j["jobId"], "name": j["name"], "status": "pending", "attempts": 0,
                       "pairId": j.get("pairId"), "pairSide": j.get("pairSide")} for j in jobs]}


def read_state(jobs, mode="run"):
    if STATE_PATH.is_file() and mode == "run":
        try:
            state = json.loads(STATE_PATH.read_text(encoding="utf-8"))
            if [x.get("jobId") for x in state.get("jobs", [])] == [x["jobId"] for x in jobs]:
                return state
        except (OSError, json.JSONDecodeError):
            pass
    return state_template(jobs, mode)


def write_summary(state, jobs):
    counts = {k: 0 for k in ("pending", "running", "success", "failed", "skipped")}
    for row in state["jobs"]:
        counts[row.get("status", "pending")] = counts.get(row.get("status", "pending"), 0) + 1
    candidates = {"selected": sum(j["variants"] for j in jobs), "succeeded": 0, "failed": 0, "skipped": 0}
    for job, row in zip(jobs, state["jobs"]):
        if row.get("status") in ("success", "skipped"):
            candidates["succeeded"] += job["variants"]
        elif row.get("status") == "failed":
            candidates["failed"] += job["variants"]
    summary = {"generatedAt": now(), "mode": state.get("mode"), "jobCounts": counts, "candidateCounts": candidates,
               "selection": state.get("summary"), "report": str(REPORT_PATH.relative_to(ROOT)).replace("\\", "/"),
               "status": str(STATE_PATH.relative_to(ROOT)).replace("\\", "/")}
    atomic_json(SUMMARY_PATH, summary)
    text = ["# First Stratum Material Family overnight run", "", f"Updated: {summary['generatedAt']}", "",
            f"Jobs: {sum(counts.values())} selected; success/skipped {counts.get('success', 0) + counts.get('skipped', 0)}; failed {counts.get('failed', 0)}; pending {counts.get('pending', 0)}.",
            f"Candidates: {candidates['selected']} selected; {candidates['succeeded']} complete; {candidates['failed']} failed/incomplete.", "",
            "## Distribution", "", "| Surface | Jobs | Candidates |", "|---|---:|---:|"]
    for surface, values in state["summary"]["bySurface"].items():
        text.append(f"| {surface} | {values['jobs']} | {values['candidates']} |")
    text += ["", f"A/B candidates: {state['summary']['abCandidates']}", f"Manifest/status: `{STATE_PATH.relative_to(ROOT).as_posix()}`", f"Report: `{REPORT_PATH.relative_to(ROOT).as_posix()}`", ""]
    MARKDOWN_PATH.write_text("\n".join(text), encoding="utf-8")


def data_uri(path: Path):
    if not path.is_file():
        return ""
    return "data:image/png;base64," + base64.b64encode(path.read_bytes()).decode("ascii")


def repeat_uri(path: Path):
    try:
        image = Image.open(path).convert("RGBA")
        repeated = Image.new("RGBA", (image.width * 3, image.height * 3))
        for y in range(3):
            for x in range(3):
                repeated.paste(image, (x * image.width, y * image.height))
        buf = io.BytesIO(); repeated.save(buf, format="PNG")
        return "data:image/png;base64," + base64.b64encode(buf.getvalue()).decode("ascii")
    except Exception:
        return ""


def candidate_card(run_path, manifest, variant):
    meta = manifest.get("overnight") or {}
    processed = run_path / variant.get("file", "")
    raw = run_path / variant.get("raw", "")
    context = run_path / variant.get("context", "")
    score = variant.get("tileScore") or {}
    scores = [score.get(axis) for axis in ("x", "y", "centre_x", "centre_y") if isinstance(score.get(axis), (int, float))]
    seam = max(scores) if scores else None
    quality = (variant.get("rawQuality") or {}).get("verdict", "unknown")
    warnings = []
    if quality != "pass": warnings.append("raw-quality")
    if seam is None or seam > 2.0: warnings.append("seam")
    if variant.get("contextError"): warnings.append("context")
    if not context.is_file(): warnings.append("no-context")
    warning_text = ", ".join(warnings) if warnings else "none"
    decision = (variant.get("curation") or {}).get("decision", "unset")
    raw_rel = str(raw.relative_to(ROOT)).replace("\\", "/") if raw.is_file() else "missing"
    prompt = html.escape(meta.get("exactPositivePrompt", manifest.get("description", "")))
    negative = html.escape(meta.get("exactNegativePrompt", ""))
    settings = html.escape(json.dumps({"model": meta.get("model"), "loras": meta.get("loras"), "sampler": meta.get("sampler"), "steps": meta.get("steps"), "cfg": meta.get("cfg"), "seed": meta.get("seed"), "depthWeight": meta.get("depthWeight"), "wrapAxes": meta.get("activeWrapAxes")}, indent=2))
    score_text = " / ".join(f"{axis}={score.get(axis, 'n/a')}" for axis in ("x", "y", "centre_x", "centre_y"))
    return f'''<article class="candidate" data-surface="{html.escape(meta.get('surfaceType', ''))}" data-family="{html.escape(meta.get('materialFamily', ''))}" data-geometry="{html.escape(meta.get('geometryPreset', ''))}" data-pair="{html.escape(meta.get('pairId') or 'none')}" data-warning="{'yes' if warnings else 'no'}" data-model="{html.escape(meta.get('model', ''))}">
      <div class="candidate-head"><span class="candidate-id">{html.escape(variant.get('candidateId', ''))}</span><span class="badge">v{variant.get('index')}</span><span class="badge {'bad' if warnings else 'ok'}">{html.escape(warning_text)}</span></div>
      <div class="images"><figure><img src="{data_uri(processed)}" alt="processed candidate"><figcaption>processed 64×64</figcaption></figure><figure><img src="{repeat_uri(processed)}" alt="three by three repeat"><figcaption>3×3 repeat</figcaption></figure>{f'<figure><img src="{data_uri(context)}" alt="engine context preview"><figcaption>engine context</figcaption></figure>' if context.is_file() else ''}</div>
      <div class="metrics">seam: {html.escape(score_text)} · raw: {html.escape(quality)} · warnings: {html.escape(warning_text)}</div>
      <details><summary>prompt, provenance and raw image</summary><div class="detail-grid"><div><b>Positive prompt</b><pre>{prompt}</pre><b>Negative prompt</b><pre>{negative}</pre></div><div><b>Settings</b><pre>{settings}</pre><p>raw: {html.escape(raw_rel)}</p></div></div></details>
      <div class="curation"><label>Decision <select data-candidate="{html.escape(variant.get('candidateId', ''))}"><option {'selected' if decision == 'unset' else ''}>unset</option><option {'selected' if decision == 'winner' else ''}>winner</option><option {'selected' if decision == 'runner_up' else ''}>runner_up</option><option {'selected' if decision == 'interesting_failure' else ''}>interesting_failure</option><option {'selected' if decision == 'technical_failure' else ''}>technical_failure</option><option {'selected' if decision == 'not_this_direction' else ''}>not_this_direction</option></select></label><input data-notes="{html.escape(variant.get('candidateId', ''))}" placeholder="notes / tags" value="{html.escape((variant.get('curation') or {}).get('notes', ''))}"></div>
    </article>'''


def build_report(jobs, state):
    records = []
    for job in jobs:
        path = run_dir_for(job)
        if not path:
            continue
        try:
            manifest = json.loads((path / "manifest.json").read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError):
            continue
        # Contexts are built in the worker immediately after a successful job;
        # this also repairs a missing/stale one when a report is requested.
        try:
            asset_gen._add_context_previews(str(path), manifest)
            for variant in manifest.get("variants", []):
                variant["tileScore"] = postprocess.tile_seam_score(
                    Image.open(path / variant["file"]), manifest.get("tileAxes", "xy"))
            (path / "manifest.json").write_text(json.dumps(manifest, indent=2, ensure_ascii=True) + "\n", encoding="utf-8")
        except Exception:
            pass
        records.append((job, path, manifest))
    groups = {}
    for job, path, manifest in records:
        key = (job["surface"], job["materialFamily"], job["geometryPreset"])
        groups.setdefault(key, []).append((job, path, manifest))
    surface_titles = {"wall": "Walls", "floor": "Floors", "ceiling": "Ceilings"}
    family_labels = {f["id"]: f["label"] for f in load_spec()["materialFamilies"]}
    sections = []
    for (surface, family, geometry), entries in sorted(groups.items()):
        body = [f'<section class="geometry-group" data-surface="{surface}" data-family="{family}" data-geometry="{geometry}"><h3>{html.escape(family_labels.get(family, family))} · {html.escape(geometry.replace("_", " "))}</h3>']
        entries = sorted(entries, key=lambda x: (x[0].get("pairId") or "zzz", x[0].get("pairSide") or "", x[0]["jobId"]))
        for job, path, manifest in entries:
            variants = manifest.get("variants", [])
            if job.get("pairId"):
                body.append(f'<div class="pair" data-pair="{html.escape(job["pairId"])}"><h4>A/B · {html.escape(job["pairId"])} <span>{html.escape(job.get("pairVariable") or "")}</span> · side {job.get("pairSide")}</h4><div class="pair-grid">')
            else:
                body.append(f'<div class="production"><h4>Production exploration · {html.escape(job["jobId"])}</h4><div class="candidate-grid">')
            body.extend(candidate_card(path, manifest, variant) for variant in variants)
            body.append("</div></div>")
        body.append("</section>")
        sections.extend(body)
    summary = state.get("summary", {})
    out_rel = str(OUT.relative_to(ROOT)).replace("\\", "/")
    status_rel = str(STATE_PATH.relative_to(ROOT)).replace("\\", "/")
    html_doc = f'''<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>First Stratum Material Family</title><style>
    :root{{color-scheme:dark;--bg:#111318;--panel:#1b1e26;--line:#3c4350;--gold:#d9b36c;--muted:#a7afbd;--bad:#e27777;--good:#86c994}}*{{box-sizing:border-box}}body{{margin:0;background:linear-gradient(#151821,#0d0f14);color:#eef0f4;font:14px system-ui,sans-serif}}main{{max-width:1800px;margin:auto;padding:24px}}h1{{color:var(--gold);margin:0 0 4px}}h2{{margin-top:30px;border-bottom:1px solid var(--line);padding-bottom:8px}}h3{{color:#f0d39b;margin:0 0 14px}}h4{{color:#e6eaf0;margin:0 0 10px}}h4 span{{color:var(--muted);font-weight:normal}}.sub,.meta,.metrics{{color:var(--muted)}}.toolbar{{position:sticky;top:0;z-index:4;background:#171a21eF;border:1px solid var(--line);padding:12px;margin:18px 0;backdrop-filter:blur(8px);display:flex;gap:8px;flex-wrap:wrap;align-items:end}}label{{color:var(--muted);display:flex;flex-direction:column;gap:4px}}select,input,button{{background:#252a34;color:#eef0f4;border:1px solid #555f70;border-radius:4px;padding:7px}}button{{cursor:pointer}}button:hover{{border-color:var(--gold)}}.stat{{padding:8px 12px;background:#242832;border-radius:4px}}.geometry-group{{margin:26px 0 38px}}.candidate-grid,.pair-grid{{display:grid;grid-template-columns:repeat(auto-fit,minmax(390px,1fr));gap:12px}}.candidate{{background:var(--panel);border:1px solid var(--line);border-radius:6px;padding:10px;min-width:0}}.candidate-head{{display:flex;gap:7px;align-items:center;margin-bottom:8px}}.candidate-id{{font-family:ui-monospace,monospace;font-size:12px;overflow:hidden;text-overflow:ellipsis;white-space:nowrap;flex:1}}.badge{{font-size:11px;padding:3px 6px;background:#303641;border-radius:3px;white-space:nowrap}}.badge.ok{{color:var(--good)}}.badge.bad{{color:var(--bad)}}.images{{display:grid;grid-template-columns:1fr 1fr 1fr;gap:6px}}figure{{margin:0;background:#101217;border:1px solid #313743;min-width:0}}figure img{{width:100%;aspect-ratio:1;object-fit:contain;image-rendering:pixelated;display:block}}figure:nth-child(2) img{{image-rendering:auto}}figcaption{{padding:4px;color:var(--muted);font-size:11px}}.metrics{{font-size:12px;margin:8px 0}}details{{border-top:1px solid #343a46;padding-top:6px}}summary{{cursor:pointer;color:#d9b36c}}pre{{white-space:pre-wrap;word-break:break-word;color:#cbd3df;font:11px ui-monospace,monospace;background:#101217;padding:7px;max-height:190px;overflow:auto}}.detail-grid{{display:grid;grid-template-columns:1fr 1fr;gap:10px}}.curation{{display:flex;gap:8px;margin-top:8px}}.curation label{{flex-direction:row;align-items:center}}.curation input{{flex:1;min-width:0}}.pair{{border:2px solid #705b36;padding:9px;margin:8px 0 14px;border-radius:6px}}.pair .candidate-grid{{display:none}}.pair-grid .candidate{{border-color:#77623b}}.hidden{{display:none!important}}.filters-status{{font-size:12px;color:var(--muted)}}@media(max-width:700px){{.candidate-grid,.pair-grid{{grid-template-columns:1fr}}.detail-grid{{grid-template-columns:1fr}}}}
    </style></head><body><main><h1>First Stratum Material Family</h1><p class="sub">Breakfast curation report · staged only · no assets promoted · generated {html.escape(now())}</p><div class="toolbar"><label>Surface<select id="surface"><option value="all">all</option><option>wall</option><option>floor</option><option>ceiling</option></select></label><label>Family<select id="family"><option value="all">all</option>{''.join(f'<option value="{html.escape(f["id"])}">{html.escape(f["label"])} </option>' for f in load_spec()["materialFamilies"])}</select></label><label>Geometry<select id="geometry"><option value="all">all</option>{''.join(f'<option>{html.escape(g)}</option>' for g in sorted({j["geometryPreset"] for j in jobs}))}</select></label><label>Model<select id="model"><option value="all">all</option><option>{html.escape(load_spec()["model"])}</option></select></label><label>Warnings<select id="warning"><option value="all">all</option><option value="yes">warnings</option><option value="no">no warnings</option></select></label><label>A/B<select id="pairFilter"><option value="all">all</option><option value="pair">A/B only</option><option value="production">production only</option></select></label><button id="apply">Apply filters</button><button id="download">Download curation JSON</button><span class="filters-status" id="filters-status">showing {len(records)} completed jobs / {sum(len(m.get("variants", [])) for _,_,m in records)} candidates</span></div><div class="stats"><span class="stat">selected {summary.get("candidates", 0)} candidates</span> <span class="stat">A/B {summary.get("abCandidates", 0)}</span> <span class="stat">complete jobs {sum(1 for r in state.get("jobs", []) if r.get("status") in ("success", "skipped"))}</span> <span class="stat">failed {sum(1 for r in state.get("jobs", []) if r.get("status") == "failed")}</span></div><p class="meta">Output root: {html.escape(out_rel)} · status: {html.escape(status_rel)} · report updates while the run proceeds.</p><h2>Candidate groups</h2>{''.join(sections)}</main><script>
    const key='first-stratum-curation'; const saved=JSON.parse(localStorage.getItem(key)||'{{}}'); document.querySelectorAll('select[data-candidate]').forEach(x=>{{if(saved[x.dataset.candidate])x.value=saved[x.dataset.candidate].decision||'unset';x.onchange=()=>{{saved[x.dataset.candidate]={{...(saved[x.dataset.candidate]||{{}}),decision:x.value}};localStorage.setItem(key,JSON.stringify(saved));}}}});document.querySelectorAll('input[data-notes]').forEach(x=>{{if(saved[x.dataset.notes])x.value=saved[x.dataset.notes].notes||'';x.onchange=()=>{{saved[x.dataset.notes]={{...(saved[x.dataset.notes]||{{}}),notes:x.value}};localStorage.setItem(key,JSON.stringify(saved));}}}});function apply(){{const s=document.querySelector('#surface').value,f=document.querySelector('#family').value,g=document.querySelector('#geometry').value,m=document.querySelector('#model').value,w=document.querySelector('#warning').value,p=document.querySelector('#pairFilter').value;let n=0;document.querySelectorAll('.candidate').forEach(c=>{{const ok=(s==='all'||c.dataset.surface===s)&&(f==='all'||c.dataset.family===f)&&(g==='all'||c.dataset.geometry===g)&&(m==='all'||c.dataset.model===m)&&(w==='all'||c.dataset.warning===w)&&(p==='all'||(p==='pair'?c.dataset.pair!=='none':c.dataset.pair==='none'));c.classList.toggle('hidden',!ok);if(ok)n++;}});document.querySelector('#filters-status').textContent='showing '+n+' candidates';}}document.querySelector('#apply').onclick=apply;document.querySelector('#download').onclick=()=>{{const out={{exportedAt:new Date().toISOString(),source:'first-stratum-material-family',decisions:saved}};const blob=new Blob([JSON.stringify(out,null,2)],{{type:'application/json'}});const a=document.createElement('a');a.href=URL.createObjectURL(blob);a.download='first-stratum-curation.json';a.click();}};
    </script></body></html>'''
    REPORT_PATH.write_text(html_doc, encoding="utf-8")
    return len(records)


def invoke(job, variants=None):
    args = [PYTHON, "-u", str(TOOL / "gen.py"), "generate", job["class"], job["name"], job["description"],
            "--provider", job["provider"], "--model", job["model"], "--variants", str(variants or job["variants"]),
            "--height", job["geometryMapPath"], "--depth-weight", str(job["depthWeight"]), "--steps", str(job["steps"]),
            "--cfg", str(job["cfg"]), "--sampler", job["sampler"], "--seed", str(job["seed"]),
            "--request-size", job["requestSize"], "--negative-extra", job["negativeExtra"]]
    return subprocess.run(args, cwd=ROOT, check=False)


def process(jobs, mode="run", preflight=False):
    OUT.mkdir(parents=True, exist_ok=True)
    if mode == "run":
        atomic_json(JOBS_PATH, jobs)
    state = read_state(jobs, mode)
    keep_awake(True)
    try:
        for index, job in enumerate(jobs):
            row = state["jobs"][index]
            complete = run_dir_for(job)
            if complete:
                augment_manifest(job, complete, "success")
                row.update({"status": "skipped", "runPath": complete.relative_to(ROOT).as_posix(), "updatedAt": now()})
                state["updatedAt"] = now(); atomic_json(STATE_PATH if mode == "run" else OUT / "preflight-status.json", state); write_summary(state, jobs)
                continue
            row.update({"status": "running", "attempts": row.get("attempts", 0) + 1, "startedAt": now()})
            state["updatedAt"] = now(); atomic_json(STATE_PATH if mode == "run" else OUT / "preflight-status.json", state)
            print(f"\n=== [{index + 1}/{len(jobs)}] {job['jobId']} ({job['surface']}, {job['geometryPreset']}) ===", flush=True)
            result = invoke(job, 1 if preflight else None)
            complete = run_dir_for(job) if not preflight else run_dir_for(job)
            if result.returncode == 0 and complete:
                try:
                    manifest = augment_manifest(job, complete, "success")
                    asset_gen._add_context_previews(str(complete), manifest)
                    atomic_json(complete / "manifest.json", manifest)
                    row.update({"status": "success", "runPath": complete.relative_to(ROOT).as_posix(), "updatedAt": now()})
                except Exception as err:
                    row.update({"status": "failed", "error": f"manifest/context: {err}", "updatedAt": now()})
            else:
                row.update({"status": "failed", "error": f"generator exit {result.returncode}", "updatedAt": now()})
            state["updatedAt"] = now(); atomic_json(STATE_PATH if mode == "run" else OUT / "preflight-status.json", state); write_summary(state, jobs)
            if index % 5 == 0 or index == len(jobs) - 1:
                build_report(jobs, state)
        build_report(jobs, state)
    finally:
        keep_awake(False)
    print(json.dumps(state.get("summary", {}), indent=2), flush=True)
    return 0 if all(x.get("status") in ("success", "skipped") for x in state["jobs"]) else 1


def main(argv=None):
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument("--preflight", action="store_true")
    parser.add_argument("--run", action="store_true")
    parser.add_argument("--report", action="store_true")
    args = parser.parse_args(argv)
    jobs = build_jobs()
    if args.dry_run:
        print(json.dumps(summary_for_jobs(jobs), indent=2))
        for surface in ("wall", "floor", "ceiling"):
            print(f"{surface}: {sum(1 for j in jobs if j['surface'] == surface)} jobs / {sum(j['variants'] for j in jobs if j['surface'] == surface)} candidates")
        print(f"A/B: {sum(j['variants'] for j in jobs if j.get('pairId'))} candidates in {len({j['pairId'] for j in jobs if j.get('pairId')})} pairs")
        return 0
    if args.report:
        state = read_state(jobs)
        print(f"report candidates: {build_report(jobs, state)} -> {REPORT_PATH}")
        return 0
    if args.preflight:
        chosen = []
        for surface in ("wall", "floor", "ceiling"):
            original = next(j for j in jobs if j["surface"] == surface and not j.get("pairId"))
            test = dict(original); test["jobId"] = f"preflight_{surface}_{original['geometryPreset']}"; test["name"] = f"first_stratum_preflight_{surface}_{original['geometryPreset']}"; test["variants"] = 1
            chosen.append(test)
        return process(chosen, mode="preflight", preflight=True)
    if args.run or not any((args.dry_run, args.report, args.preflight)):
        return process(jobs)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
