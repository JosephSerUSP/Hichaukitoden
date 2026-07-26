#!/bin/bash
# One reference log per fixture in data/goldenBattles.json, keyed by the
# "battle|<key>|name|<name>" header line. Mirrors capture-ui.sh.
cd "$(dirname "$0")/../.."
TEMP_LOG=$(mktemp)
xvfb-run -a love . validate golden | awk '/GOLDEN BEGIN/{flag=1; next} /GOLDEN END/{flag=0} flag' > "$TEMP_LOG"

awk -v outdir="tools/golden" '
  /^battle\|[^|]+\|name\|/ {
    if (key != "") print "GOLDEN END" >> (outdir "/battle_" key ".log")
    match($0, /^battle\|([^|]+)/, arr)
    key = arr[1]
    print "GOLDEN BEGIN" > (outdir "/battle_" key ".log")
    print >> (outdir "/battle_" key ".log")
    next
  }
  key != "" {
    print >> (outdir "/battle_" key ".log")
  }
  END {
    if (key != "") print "GOLDEN END" >> (outdir "/battle_" key ".log")
  }
' "$TEMP_LOG"
rm "$TEMP_LOG"
echo "Captured golden battle logs to tools/golden/battle_*.log"
