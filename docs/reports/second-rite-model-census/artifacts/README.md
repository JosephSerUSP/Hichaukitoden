# Model census review evidence

This directory contains the **decision evidence** for the Second Rite model-census review. It exists because the invalidated 2026-08-06 pass committed conclusions while keeping the images and journals only under the disposable `out/model-census-review/` tree.

Policy after the harness-v2 correction:

- `out/model-census-review/` remains the exhaustive local frame archive and may be disposable.
- `artifacts/current/` is populated by `tools/asset-production/review_model_census.py` and is intended to be committed with any review conclusion. It contains compact contact sheets, smoke controls, journals/indexes, diagnostics, review CSV, and SHA-256 provenance—not hundreds of raw frames.
- `artifacts/invalidated-2026-08-06/` preserves the broken sheets that exposed the first harness failure. They are regression evidence, not valid asset evaluations.

A written model verdict without its matching tracked decision evidence should be treated as incomplete.
