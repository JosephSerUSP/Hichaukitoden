#!/usr/bin/env python3
"""G5 -- golden screenshot gate: capture and comparison.

The world view (presentation/viewport_3d.lua) is invisible to G1-G4: G1
validates data, G2 compares battle simulation logs, G3 compares UI *event*
traces (tools/golden/scene_map.log is 17 lines of open_window/set_cursor and
never sees a pixel), and G4 checks doc currency. This gate closes that hole by
byte-comparing the frames `lovec . screenshots` renders.

Both tools/golden/capture-screens.ps1 and .sh are thin runners around this
file, so the extract/decode/compare logic exists once rather than being
transcribed into PowerShell and bash separately.

Determinism: cli.runScreenshots already pins love.timer.getTime, seeds
math.randomseed(12345), fixes the generated-map os.time() seed, and settles
every animation through explicit seams. Verified 30.07.2026: two consecutive
runs produced 122 byte-identical captures. That holds run-to-run on one
machine and GPU; it is NOT a claim about cross-machine reproducibility, and
a GPU or driver change may legitimately shift pixels. See the roadmap doc,
docs/design/renderer-3d-roadmap.md section 3.

Usage:
    python tools/golden/screens.py capture --input <lovec-stdout-file>
    python tools/golden/screens.py check   --input <lovec-stdout-file>
"""

import argparse
import base64
import html
import json
import os
import sys

BEGIN = "SCREENSHOTS BEGIN"
END = "SCREENSHOTS END"

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REF_DIR = os.path.join(ROOT, "tools", "golden", "screens")
ACTUAL_DIR = os.path.join(ROOT, "tools", "golden", "screens-actual")
COMPARISON_HTML = os.path.join(ROOT, "tools", "golden", "screens-comparison.html")


def extract_payload(text):
    """Pull the JSON document the harness prints between its markers."""
    try:
        start = text.index(BEGIN) + len(BEGIN)
        end = text.index(END)
    except ValueError:
        sys.stderr.write(
            "screens.py: no SCREENSHOTS BEGIN/END block in the harness output.\n"
            "The run probably crashed -- inspect the captured stdout directly.\n")
        raise SystemExit(2)
    return json.loads(text[start:end].strip())


def safe_relpath(path):
    """cli.runScreenshots slugs every path component, so this should never
    trip -- but a gate that writes attacker-controlled paths is not a gate."""
    norm = os.path.normpath(path).replace("\\", "/")
    if norm.startswith("/") or norm.startswith("..") or ":" in norm:
        raise SystemExit("screens.py: refusing unsafe capture path: " + path)
    return norm


def load_captures(input_path):
    with open(input_path, "r", encoding="utf-8", errors="replace") as handle:
        payload = extract_payload(handle.read())

    if payload.get("error"):
        sys.stderr.write("screens.py: harness reported an error: %s\n" % payload["error"])
        raise SystemExit(2)

    captures = payload.get("captures") or []
    if not captures:
        raise SystemExit("screens.py: harness produced no captures")
    return captures


def do_capture(captures):
    written = 0
    for cap in captures:
        rel = safe_relpath(cap["path"])
        dest = os.path.join(REF_DIR, rel)
        os.makedirs(os.path.dirname(dest), exist_ok=True)
        with open(dest, "wb") as handle:
            handle.write(base64.b64decode(cap["image"]))
        written += 1
    print("Captured %d golden screenshots -> tools/golden/screens/" % written)


def do_check(captures):
    seen = set()
    mismatched, missing = [], []

    for cap in captures:
        rel = safe_relpath(cap["path"])
        seen.add(rel)
        ref = os.path.join(REF_DIR, rel)
        actual = base64.b64decode(cap["image"])

        if not os.path.exists(ref):
            missing.append(rel)
            write_actual(rel, actual)
            continue

        with open(ref, "rb") as handle:
            if handle.read() != actual:
                mismatched.append(rel)
                write_actual(rel, actual)

    # A reference with no capture is as real a change as a differing pixel:
    # a scene or goldenScript step was removed.
    orphaned = []
    for dirpath, _, filenames in os.walk(REF_DIR):
        for name in filenames:
            if not name.endswith(".png"):
                continue
            rel = os.path.relpath(os.path.join(dirpath, name), REF_DIR).replace("\\", "/")
            if rel not in seen:
                orphaned.append(rel)

    total = len(captures)
    ok = total - len(mismatched) - len(missing)
    print("Golden screenshots: %d/%d match." % (ok, total))

    for rel in sorted(mismatched):
        print("  MISMATCH  %s" % rel)
    for rel in sorted(missing):
        print("  NO REFERENCE  %s (new capture)" % rel)
    for rel in sorted(orphaned):
        print("  ORPHANED REFERENCE  %s (no longer captured)" % rel)

    write_comparison_html(seen, mismatched, missing, orphaned)

    if mismatched or missing or orphaned:
        print("")
        print("Differing frames written to tools/golden/screens-actual/ -- open them")
        print("side by side with tools/golden/screens/ before doing anything else.")
        print("")
        print("A red G5 is a VISUAL REGRESSION until proven otherwise. Regenerating")
        print("the references to make it green is an owner-signed action, exactly as")
        print("it is for G2/G3 (AGENTS.md).")
        raise SystemExit(1)

    print("SCREENS OK")


def write_comparison_html(seen, mismatched, missing, orphaned):
    """Write a local side-by-side gallery after every G5 comparison."""
    reference_paths = set()
    for dirpath, _, filenames in os.walk(REF_DIR):
        for name in filenames:
            if name.endswith(".png"):
                reference_paths.add(os.path.relpath(
                    os.path.join(dirpath, name), REF_DIR).replace("\\", "/"))

    actual_paths = set()
    if os.path.isdir(ACTUAL_DIR):
        for dirpath, _, filenames in os.walk(ACTUAL_DIR):
            for name in filenames:
                if name.endswith(".png"):
                    actual_paths.add(os.path.relpath(
                        os.path.join(dirpath, name), ACTUAL_DIR).replace("\\", "/"))

    paths = sorted(reference_paths | actual_paths | set(seen))
    mismatch_set, missing_set, orphaned_set = set(mismatched), set(missing), set(orphaned)
    rows = []
    for rel in paths:
        status = ("mismatch" if rel in mismatch_set else
                  "missing" if rel in missing_set else
                  "orphaned" if rel in orphaned_set else "match")
        ref_src = "screens/" + rel if rel in reference_paths else ""
        actual_src = "screens-actual/" + rel if rel in actual_paths else ""
        ref_img = '<img src="%s" loading="lazy" alt="reference">' % html.escape(ref_src) if ref_src else '<div class="empty">No reference</div>'
        actual_img = '<img src="%s" loading="lazy" alt="actual">' % html.escape(actual_src) if actual_src else '<div class="empty">No actual capture</div>'
        rows.append("""<article class=\"card %s\" data-status=\"%s\">\n"
                    "<div class=\"title\"><span>%s</span><b>%s</b></div>\n"
                    "<div class=\"pair\"><figure><figcaption>Reference</figcaption>%s</figure>"
                    "<figure><figcaption>Actual</figcaption>%s</figure></div>\n"
                    "</article>""" % (
                        status, status, html.escape(rel), status.upper(), ref_img, actual_img))

    counts = {key: sum(1 for rel in paths if ("mismatch" if rel in mismatch_set else
              "missing" if rel in missing_set else "orphaned" if rel in orphaned_set else "match") == key)
              for key in ("match", "mismatch", "missing", "orphaned")}
    document = """<!doctype html>
<meta charset="utf-8">
<title>G5 screenshot comparison</title>
<style>
*{box-sizing:border-box}body{margin:0;background:#111827;color:#e5e7eb;font:14px system-ui,sans-serif}
header{position:sticky;top:0;z-index:2;padding:16px 20px;background:#1f2937;border-bottom:1px solid #374151}
h1{margin:0 0 8px;font-size:20px}button{margin-right:6px;padding:6px 10px;border:1px solid #4b5563;border-radius:5px;background:#111827;color:#e5e7eb;cursor:pointer}button.active{background:#2563eb;border-color:#60a5fa}
#grid{display:grid;grid-template-columns:repeat(auto-fit,minmax(520px,1fr));gap:14px;padding:16px}
.card{background:#1f2937;border:2px solid #374151;border-radius:8px;padding:10px}.card.mismatch{border-color:#ef4444}.card.missing{border-color:#f59e0b}.card.orphaned{border-color:#a855f7}.card.match{border-color:#166534}
.title{display:flex;justify-content:space-between;gap:12px;margin-bottom:8px;font:12px ui-monospace,monospace}.title b{font:11px system-ui,sans-serif}.mismatch .title b{color:#fca5a5}.missing .title b{color:#fcd34d}.orphaned .title b{color:#d8b4fe}.match .title b{color:#86efac}
.pair{display:grid;grid-template-columns:1fr 1fr;gap:8px}figure{margin:0;background:#030712;padding:5px}figcaption{color:#9ca3af;font-size:11px;margin-bottom:4px}img{display:block;width:100%%;image-rendering:auto}.empty{height:180px;display:grid;place-items:center;color:#6b7280}
</style>
<header><h1>G5 screenshot comparison</h1><div id=\"summary\">Generated after the latest G5 run: %d match, %d mismatch, %d missing, %d orphaned.</div><p><button class=\"active\" data-filter=\"all\">All</button><button data-filter=\"mismatch\">Mismatches</button><button data-filter=\"missing\">Missing</button><button data-filter=\"orphaned\">Orphaned</button><button data-filter=\"match\">Matches</button></p></header>
<main id=\"grid\">%s</main>
<script>document.querySelectorAll('button').forEach(b=>b.onclick=()=>{document.querySelectorAll('button').forEach(x=>x.classList.remove('active'));b.classList.add('active');let f=b.dataset.filter;document.querySelectorAll('.card').forEach(c=>c.hidden=f!='all'&&c.dataset.status!=f)})</script>
""" % (counts["match"], counts["mismatch"], counts["missing"], counts["orphaned"], "\n".join(rows))
    with open(COMPARISON_HTML, "w", encoding="utf-8") as handle:
        handle.write(document)
    print("Wrote screenshot comparison: tools/golden/screens-comparison.html")


def write_actual(rel, data):
    dest = os.path.join(ACTUAL_DIR, rel)
    os.makedirs(os.path.dirname(dest), exist_ok=True)
    with open(dest, "wb") as handle:
        handle.write(data)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("mode", choices=["capture", "check"])
    parser.add_argument("--input", required=True,
                        help="file holding the stdout of `lovec . screenshots`")
    args = parser.parse_args()

    captures = load_captures(args.input)
    if args.mode == "capture":
        do_capture(captures)
    else:
        do_check(captures)


if __name__ == "__main__":
    main()
