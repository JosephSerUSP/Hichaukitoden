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

for UI_LOG in tools/golden/scene_*.log; do
    if [ ! -f "$UI_LOG" ]; then continue; fi
    SCENE_KEY=$(basename "$UI_LOG" | sed 's/scene_\(.*\)\.log/\1/')
    TEMP_UI_LOG=$(mktemp)
    xvfb-run -a love . validate golden-ui "$SCENE_KEY" | awk '/UI GOLDEN BEGIN/{flag=1; next} /UI GOLDEN END/{flag=0} flag' > "$TEMP_UI_LOG"

    if cmp -s "$TEMP_UI_LOG" "$UI_LOG"; then
        echo "Golden UI log for scene '$SCENE_KEY' matches."
        rm "$TEMP_UI_LOG"
    else
        echo "Golden UI log for scene '$SCENE_KEY' MISMATCH!"
        diff -u "$UI_LOG" "$TEMP_UI_LOG"
        rm "$TEMP_UI_LOG"
        exit 1
    fi
done
