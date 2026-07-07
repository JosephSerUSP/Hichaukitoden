#!/bin/bash
xvfb-run love . validate golden | grep -A 1000 "GOLDEN BEGIN" | grep -B 1000 "GOLDEN END" > tools/golden/battle.log
