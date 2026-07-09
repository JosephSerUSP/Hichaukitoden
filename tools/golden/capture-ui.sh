#!/bin/bash
cd "$(dirname "$0")/../.."
TEMP_LOG=$(mktemp)
xvfb-run -a love . validate golden-ui | awk '/UI GOLDEN BEGIN/{flag=1; next} /UI GOLDEN END/{flag=0} flag' > "$TEMP_LOG"

# Split by scene key: each block starts with "scene|<key>|..."
awk -v outdir="tools/golden" '
  /^scene\|/ {
    if (scene != "") close(outdir "/scene_" scene ".log")
    match($0, /^scene\|([^|]+)/, arr)
    scene = arr[1]
    print "UI GOLDEN BEGIN" > (outdir "/scene_" scene ".log")
    print > (outdir "/scene_" scene ".log")
    next
  }
  scene != "" {
    print >> (outdir "/scene_" scene ".log")
  }
  END {
    if (scene != "") print "UI GOLDEN END" >> (outdir "/scene_" scene ".log")
  }
' "$TEMP_LOG"
rm "$TEMP_LOG"
echo "Captured golden UI logs to tools/golden/scene_*.log"
