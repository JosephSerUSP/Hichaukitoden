#!/bin/bash
set -e
cd "$(dirname "$0")/../.."
TEMP_OUT=$(mktemp)
trap 'rm -f "$TEMP_OUT"' EXIT

xvfb-run -a love . screenshots > "$TEMP_OUT"
python3 tools/golden/screens.py check --input "$TEMP_OUT"
