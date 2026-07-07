#!/bin/bash
cd "$(dirname "$0")/../.."
TEMP_LOG=$(mktemp)
xvfb-run -a love . validate golden | awk '/GOLDEN BEGIN/{flag=1; next} /GOLDEN END/{flag=0} flag' > "$TEMP_LOG"

if cmp -s "$TEMP_LOG" tools/golden/battle.log; then
    echo "Golden log matches."
    rm "$TEMP_LOG"
else
    echo "Golden log MISMATCH!"
    diff -u tools/golden/battle.log "$TEMP_LOG"
    rm "$TEMP_LOG"
    exit 1
fi
