#!/bin/bash
cd "$(dirname "$0")/../.."

TEMP_LOG=$(mktemp)
xvfb-run -a love . validate golden-ui > "$TEMP_LOG" 2>&1

SCENES=("title" "main_menu" "item" "status" "shop" "crafting" "battle")

for SCENE in "${SCENES[@]}"; do
    awk "/UI GOLDEN BEGIN $SCENE/{flag=1; next} /UI GOLDEN END $SCENE/{flag=0} flag" "$TEMP_LOG" > "tools/golden/scene_${SCENE}.log"
done

rm "$TEMP_LOG"
