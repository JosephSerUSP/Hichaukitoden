#!/bin/bash
set -e
cd "$(dirname "$0")/../.."

# OWNER-SIGNED action -- see capture-editor.ps1.
python3 tools/golden/editor-screens.py capture
