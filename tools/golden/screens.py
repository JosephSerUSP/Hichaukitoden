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
import json
import os
import sys

BEGIN = "SCREENSHOTS BEGIN"
END = "SCREENSHOTS END"

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
REF_DIR = os.path.join(ROOT, "tools", "golden", "screens")
ACTUAL_DIR = os.path.join(ROOT, "tools", "golden", "screens-actual")


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
