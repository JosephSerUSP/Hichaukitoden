#!/bin/bash
cd "$(dirname "$0")/../.."
xvfb-run -a love . validate golden | awk '/GOLDEN BEGIN/{flag=1; next} /GOLDEN END/{flag=0} flag' > tools/golden/battle.log
