#!/bin/bash
love . validate golden | awk '/^GOLDEN BEGIN/{p=1; next} /^GOLDEN END/{p=0} p {print}' > tools/golden/temp.log
if ! cmp -s tools/golden/battle.log tools/golden/temp.log; then
    echo "Golden master check failed!"
    diff tools/golden/battle.log tools/golden/temp.log
    rm tools/golden/temp.log
    exit 1
else
    echo "Golden master check passed."
    rm tools/golden/temp.log
    exit 0
fi
