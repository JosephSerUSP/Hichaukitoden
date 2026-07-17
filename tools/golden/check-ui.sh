#!/bin/bash
cd "$(dirname "$0")/../.."
TEMP_LOG=$(mktemp)
xvfb-run -a love . validate golden-ui | awk '/UI GOLDEN BEGIN/{flag=1; next} /UI GOLDEN END/{flag=0} flag' > "$TEMP_LOG"

ALL_MATCH=true

# Split by scene key into per-scene temp files
awk -v tempdir="$(dirname "$TEMP_LOG")" '
  BEGIN { scene = "" }
  /^scene\|[^|]+\|name\|/ {
    if (scene != "") close(tempdir "/scene_" scene ".log.part")
    match($0, /^scene\|([^|]+)/, arr)
    scene = arr[1]
    print "UI GOLDEN BEGIN" > (tempdir "/scene_" scene ".log.part")
    print > (tempdir "/scene_" scene ".log.part")
    next
  }
  scene != "" {
    print >> (tempdir "/scene_" scene ".log.part")
  }
  END {
    if (scene != "") print "UI GOLDEN END" >> (tempdir "/scene_" scene ".log.part")
  }
' "$TEMP_LOG"

for part in "$(dirname "$TEMP_LOG")"/scene_*.log.part; do
  [ -f "$part" ] || continue
  key=$(basename "$part" .log.part | sed 's/^scene_//')
  ref="tools/golden/scene_${key}.log"
  if [ ! -f "$ref" ]; then
    echo "WARNING: No reference log for scene '$key' at $ref"
    ALL_MATCH=false
    continue
  fi
  if cmp -s "$part" "$ref"; then
    echo "Golden UI log matches for scene '$key'."
  else
    echo "Golden UI log MISMATCH for scene '$key'!"
    diff -u "$ref" "$part"
    ALL_MATCH=false
  fi
  rm "$part"
done

rm -f "$TEMP_LOG"

if [ "$ALL_MATCH" = false ]; then
  exit 1
fi
echo "All golden UI logs match."
