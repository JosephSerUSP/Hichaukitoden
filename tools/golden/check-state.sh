#!/bin/bash
# G4: docs/ENGINE-STATE.md must match what the engine actually reports.
# A diff means the generated doc is stale -- run capture-state.sh and commit.
cd "$(dirname "$0")/../.."
TEMP_REPORT=$(mktemp)
xvfb-run -a love . engine-state | awk '/ENGINE STATE BEGIN/{flag=1; next} /ENGINE STATE END/{flag=0} flag' > "$TEMP_REPORT"

if [ ! -s "$TEMP_REPORT" ]; then
    echo "ENGINE STATE produced no output -- is the engine erroring?"
    rm -f "$TEMP_REPORT"
    exit 1
fi

if [ ! -f docs/ENGINE-STATE.md ]; then
    echo "MISSING docs/ENGINE-STATE.md -- run tools/golden/capture-state.sh"
    rm -f "$TEMP_REPORT"
    exit 1
fi

if diff -q <(sed -e '$a\' docs/ENGINE-STATE.md) <(sed -e '$a\' "$TEMP_REPORT") > /dev/null; then
    echo "Engine state doc matches."
    rm -f "$TEMP_REPORT"
    exit 0
fi

echo "Engine state doc is STALE (docs/ENGINE-STATE.md != live engine)."
echo "Fix: run tools/golden/capture-state.sh and commit the updated file."
echo
diff docs/ENGINE-STATE.md "$TEMP_REPORT" | head -40
rm -f "$TEMP_REPORT"
exit 1
