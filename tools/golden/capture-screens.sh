#!/bin/bash
# Regenerating golden screenshots is an OWNER-SIGNED action. A red G5 means a
# visual regression until proven otherwise -- never run this to silence a diff
# (AGENTS.md, same rule as G2/G3).
set -e
cd "$(dirname "$0")/../.."
TEMP_OUT=$(mktemp)
trap 'rm -f "$TEMP_OUT"' EXIT

xvfb-run -a love . screenshots > "$TEMP_OUT"
python3 tools/golden/screens.py capture --input "$TEMP_OUT"
