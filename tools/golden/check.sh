#!/bin/bash
TMP_LOG=$(mktemp)
xvfb-run love . validate golden | grep -A 1000 "GOLDEN BEGIN" | grep -B 1000 "GOLDEN END" > "$TMP_LOG"
diff -u tools/golden/battle.log "$TMP_LOG"
STATUS=$?
rm "$TMP_LOG"
exit $STATUS
