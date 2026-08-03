#!/bin/bash
set -e
cd "$(dirname "$0")/../.."

# G6 drives the editor server and a headless Chrome from Python; no xvfb needed,
# Chrome runs headless on its own.
python3 tools/golden/editor-screens.py check
