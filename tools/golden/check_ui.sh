#!/bin/bash
cd "$(dirname "$0")/../.."
SCENE_KEY=$1

TEMP_LOG=$(mktemp)
xvfb-run -a love . validate golden-ui $SCENE_KEY | awk '/UI GOLDEN BEGIN/{flag=1; next} /UI GOLDEN END/{flag=0} flag' > "$TEMP_LOG"

if cmp -s "$TEMP_LOG" tools/golden/scene_${SCENE_KEY}.log; then
    echo "Golden UI log matches for $SCENE_KEY."
    rm "$TEMP_LOG"
else
    echo "Golden UI log MISMATCH for $SCENE_KEY!"
    diff -u tools/golden/scene_${SCENE_KEY}.log "$TEMP_LOG"
    rm "$TEMP_LOG"
    exit 1
fi
