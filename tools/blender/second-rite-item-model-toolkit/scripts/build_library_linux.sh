#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TOOLKIT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BLENDER_BIN="${1:-${BLENDER_BIN:-blender}}"
OUTPUT_DIR="${2:-${SECOND_RITE_OUT:-$TOOLKIT_ROOT/output}}"

mkdir -p "$OUTPUT_DIR"
export SECOND_RITE_OUT="$OUTPUT_DIR"

RUNNER=("$BLENDER_BIN" --background --python "$TOOLKIT_ROOT/build_expanded_item_library.py")
if command -v xvfb-run >/dev/null 2>&1; then
  RUNNER=(xvfb-run -a "${RUNNER[@]}")
fi

"${RUNNER[@]}"

test -s "$OUTPUT_DIR/second_rite_item_model_library_expanded.blend"
test -s "$OUTPUT_DIR/second_rite_item_model_library_expanded_preview.png"
test -s "$OUTPUT_DIR/ITEM_MODEL_MANIFEST.md"
test -s "$TOOLKIT_ROOT/vendor/second_rite_asset_core.py"
test -s "$TOOLKIT_ROOT/vendor/contract.json"
test -s "$TOOLKIT_ROOT/vendor/materials.json"
OBJ_COUNT="$(find "$OUTPUT_DIR/exports" -maxdepth 1 -type f -name '*.obj' | wc -l | tr -d ' ')"
test "$OBJ_COUNT" -eq 53

(
  cd "$OUTPUT_DIR"
  rm -rf vendor
  cp -R "$TOOLKIT_ROOT/vendor" vendor
  sha256sum second_rite_item_model_library_expanded.blend \
            second_rite_item_model_library_expanded_preview.png \
            ITEM_MODEL_MANIFEST.md > SHA256SUMS.txt
  rm -f second-rite-expanded-item-model-library-local.zip
  zip -r second-rite-expanded-item-model-library-local.zip \
    second_rite_item_model_library_expanded.blend \
    second_rite_item_model_library_expanded_preview.png \
            ITEM_MODEL_MANIFEST.md SHA256SUMS.txt exports vendor
)

echo "Validated 49 roots / 53 OBJ outputs."
echo "Output: $OUTPUT_DIR"
