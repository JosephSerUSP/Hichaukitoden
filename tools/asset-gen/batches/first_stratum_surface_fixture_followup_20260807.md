# First Stratum surface-fixture follow-up — 2026-08-07

## Evidence reviewed

This follow-up is based on the committed owner ratings and exemplars in commit
`ed0de35e570260b9355848b73131a0373ccfa42f`. The original rated batch and its
height maps are deliberately left untouched so the evidence remains reproducible.

## What the ratings say

- **Ceiling ribs are the clearest success:** 6/6/6, with the note “these look especially great”.
- **Wide coffers are also production-worthy:** 6/5/6.
- **Broad floors worked:** irregular flagstones scored 5/5/5; restrained slabs scored 6/5/6.
- **The slab language should be retained but made denser:** “love this heightmap. could be denser / smaller in scale though.”
- **Ashlar albedo was acceptable but the geometry was not convincing:** 5/5/5 with “not a fan of this heightmap”.
- **Votive relief was strong:** 5/6/5, but its displacement was “maybe a tad too strong”.
- **Reliquary niche was stable:** 5/5/5.
- **Bronze inlay was stable:** 5/5/5, but the preview made the height look too strong.
- **Drip boss was stable:** 5/5/5.
- **Root fissure failed as material art:** 2/2/3, all tagged `picture`.
- **Breach socket plateaued at 4/4/4** and wants a quieter cavity/rim.
- **Runnel and collapsed socket must not be inverted on the basis of the old preview.** Their authored fields are already signed below neutral. The owner explicitly noted that transparent depth maps should be previewed against neutral material while executing the full alpha pipeline.

## Root cause fixed in this PR

The fixture runner prepared authoritative alpha files, but the cached rating
context still represented the ordinary opaque generated variant. It did not show
what the engine receives after alpha is copied from the height map, nor what the
signed displacement becomes when merged over a neutral plane.

The new preview path now records, for each fixture variant:

1. albedo with authoritative height alpha over neutral grey;
2. the exact signed height composition over opaque RGB=128 neutral height;
3. a neutral shaded diagnostic using the job's recommended scale.

The preview is stamped `surface-fixture-neutral-alpha-v2` and stored in the
manifest's existing `context` field, so the report/rater uses it instead of a
stale opaque room preview.

## Focused follow-up batch

Six jobs, three variants each (18 candidates):

1. denser 4x5 floor slabs;
2. irregular five-course ashlar;
3. softer votive relief;
4. restrained breach socket;
5. nearly flush bronze rite inlay;
6. mineral hairline fissure with root/scene vocabulary removed.

The previously successful ribs, coffers, flagstones, niche, puddle variants and
drip boss are not rerendered. Runnel and collapsed socket should first be
re-rated with the corrected preview before changing their already-negative
geometry.

## Validation and commands

```text
python -m py_compile \
  tools/asset-gen/lib/fixture_preview.py \
  tools/asset-gen/build_surface_fixture_followup_20260807.py \
  tools/asset-gen/run_surface_fixture_batch_20260806.py

python -m unittest discover -s tools/asset-gen/tests -p 'test_fixture_preview.py' -v
python tools/asset-gen/build_surface_fixture_followup_20260807.py
python tools/asset-gen/build_surface_fixture_followup_20260807.py --check

# Rebuild truthful previews for the existing nine fixture runs without Forge:
python tools/asset-gen/run_surface_fixture_batch_20260806.py \
  --group fixture --prepare-only

# Inspect the exact new generation commands, then render 18 candidates:
python tools/asset-gen/run_surface_fixture_batch_20260806.py \
  --jobs tools/asset-gen/batches/first_stratum_surface_fixture_followup_20260807.json \
  --dry-run
python tools/asset-gen/run_surface_fixture_batch_20260806.py \
  --jobs tools/asset-gen/batches/first_stratum_surface_fixture_followup_20260807.json
```

Do not auto-promote. Compare the new slab, ashlar, votive, breach, inlay and
mineral-fissure candidates against the committed exemplars and rate all 18.
