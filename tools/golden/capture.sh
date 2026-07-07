#!/bin/bash
love . validate golden | awk '/^GOLDEN BEGIN/{p=1; next} /^GOLDEN END/{p=0} p {print}' > tools/golden/battle.log
