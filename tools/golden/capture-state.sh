#!/bin/bash
# Regenerates docs/ENGINE-STATE.md from the live engine + data.
cd "$(dirname "$0")/../.."
xvfb-run -a love . engine-state | awk '/ENGINE STATE BEGIN/{flag=1; next} /ENGINE STATE END/{flag=0} flag' > docs/ENGINE-STATE.md

if [ ! -s docs/ENGINE-STATE.md ]; then
    echo "ENGINE STATE capture produced no output -- is the engine erroring?"
    exit 1
fi
echo "Captured engine state -> docs/ENGINE-STATE.md ($(wc -l < docs/ENGINE-STATE.md) lines)"
