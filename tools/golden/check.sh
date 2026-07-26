#!/bin/bash
# One reference log per fixture in data/goldenBattles.json, keyed by the
# "battle|<key>|name|<name>" header line. Mirrors check-ui.sh.
cd "$(dirname "$0")/../.."
TEMP_LOG=$(mktemp)
xvfb-run -a love . validate golden | awk '/GOLDEN BEGIN/{flag=1; next} /GOLDEN END/{flag=0} flag' > "$TEMP_LOG"

ALL_MATCH=true

awk -v tempdir="$(dirname "$TEMP_LOG")" '
  BEGIN { key = "" }
  /^battle\|[^|]+\|name\|/ {
    if (key != "") print "GOLDEN END" >> (tempdir "/battle_" key ".log.part")
    match($0, /^battle\|([^|]+)/, arr)
    key = arr[1]
    print "GOLDEN BEGIN" > (tempdir "/battle_" key ".log.part")
    print >> (tempdir "/battle_" key ".log.part")
    next
  }
  key != "" {
    print >> (tempdir "/battle_" key ".log.part")
  }
  END {
    if (key != "") print "GOLDEN END" >> (tempdir "/battle_" key ".log.part")
  }
' "$TEMP_LOG"

FOUND=false
for part in "$(dirname "$TEMP_LOG")"/battle_*.log.part; do
  [ -f "$part" ] || continue
  FOUND=true
  key=$(basename "$part" .log.part | sed 's/^battle_//')
  ref="tools/golden/battle_${key}.log"
  if [ ! -f "$ref" ]; then
    echo "WARNING: No reference log for fixture '$key' at $ref"
    ALL_MATCH=false
    rm "$part"
    continue
  fi
  if cmp -s "$part" "$ref"; then
    echo "Golden log matches for fixture '$key'."
  else
    echo "Golden log MISMATCH for fixture '$key'!"
    diff -u "$ref" "$part"
    ALL_MATCH=false
  fi
  rm "$part"
done

rm -f "$TEMP_LOG"

if [ "$FOUND" = false ]; then
  echo "No golden battle fixtures produced any output"
  exit 1
fi

# A captured log with no matching fixture means a fixture was deleted or
# renamed. Silently passing would quietly shrink battle coverage.
for ref in tools/golden/battle_*.log; do
  [ -f "$ref" ] || continue
  key=$(basename "$ref" .log | sed 's/^battle_//')
  if ! grep -q "\"id\"[[:space:]]*:[[:space:]]*\"${key}\"" data/goldenBattles.json; then
    echo "WARNING: $(basename "$ref") has no matching fixture in data/goldenBattles.json"
    ALL_MATCH=false
  fi
done

if [ "$ALL_MATCH" = false ]; then
  exit 1
fi
echo "All golden battle logs match."
