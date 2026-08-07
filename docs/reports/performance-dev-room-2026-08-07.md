# Developer-room performance diagnostic

Date: 2026-08-07  
Target: developer room, map `8` (`Developer Room`)  
Baseline: 60 FPS = 16.67 ms/frame

## Executive finding

The developer room is genuinely below the 60 FPS budget in the real 3D
renderer. The headless renderer profile measured a 19.09 ms steady-state mean
(about 52.4 FPS), a 15.29 ms median, a 49.71 ms p95, and an 82.54 ms worst
frame over 300 frames.

The dominant structural difference is not room size. Map 8 resolves the
default tileset, whose height-map surfaces are represented as individual model
draws. Its frame contains about 184 model draws and 192 total draw calls, with
191 queued surfaces and no resident structural vertices. Comparable fixed
rooms use persistent structural batches and are much cheaper.

## Measurements

All measurements came from the existing `lovec . profile-3d <map> 300` mode.
That mode renders the real `presentation.viewport_3d` path, flushes the LÖVE
graphics batch, warms the renderer before sampling, and reports the renderer's
own frame statistics.

| Map | Mean ms | Median ms | P95 ms | Max ms | Approx. FPS | Draw calls | Model draws | Lua allocation delta |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 8 Developer Room | 19.09 | 15.29 | 49.71 | 82.54 | 52.4 | 192 | 184 | 118.6 MB |
| 9 Showcase | 2.21 | 1.79 | 5.49 | 11.03 | 452.2 | 43 | 39 | 30.9 MB |
| 12 Depth Explore | 6.17 | 5.43 | 11.21 | 16.44 | 162.2 | 226 | 225 | 20.9 MB |
| 13 Wall/Recess Compare | 2.10 | 1.71 | 4.98 | 12.14 | 476.5 | 32 | 28 | 25.0 MB |
| 14 Height Compare | 5.37 | 4.86 | 9.80 | 17.19 | 186.2 | 36 | 32 | 65.4 MB |

The Lua allocation figure is cumulative over the 300 sampled frames, not
retained memory. Map 8 therefore averages approximately 395 KB of transient
Lua allocation per frame, a likely contributor to its p95 and worst-frame
spikes.

## Why the small room is expensive

Map 8 is only 15x8 cells and has no encounters, but it does not declare a
special tileset. The tileset resolver consequently selects `dungeon_default`.
That tileset declares a 24x24 height map and a 384-triangle height-surface
budget. In `presentation/viewport_3d.lua`, height surfaces are queued as
placed model surfaces for floors and ceilings, while visible wall surfaces and
event models are queued separately.

The renderer then walks and queues those placed surfaces every frame. Unlike
the showcase rooms, map 8 reports zero resident structural vertices and zero
persistent batch draws. This makes the cost roughly proportional to the
number of visible height-surface placements rather than to the room's visual
complexity.

The current quality presets can reduce geometry density and compilation cost,
but they do not change the number of placed surfaces or the per-frame draw
submission pattern. That explains why quality reduction helps, but why the
room remains unusually sensitive to the preset.

## Correctness checks

- G1 validation: passed (`VALIDATE OK`); 76 `SCRIPT` usages reported.
- Save round-trip: passed (`SAVETEST OK`).
- G4 engine-state currency: passed (`Engine state doc matches.`).
- Unit tests: failed only because `test_model_census_review` crashes during
  preflight when its required `assets/authoring/second_rite_census` manifest
  and model set are absent. This is an asset/test-fixture problem, not a
  performance finding.
- G5 screenshots: failed, with 53/141 matching. The gate reports broad visual
  mismatches and one new recruit capture; no golden references were changed.
  This should be treated as a separate visual-regression investigation.

## Recommended next investigation

1. Add a profiling-only counter/timer around `queuePlacedModels`, clipping,
   dynamic mesh uploads, and the final model-draw loop.
2. Test a cached/batched path for repeated height-map floor and ceiling
   surfaces, preserving the existing depth ordering and near-plane clipping
   behavior.
3. Measure map 8 with the height-map path disabled as an A/B control. If it
   returns near the map 9/13 range, the diagnosis is confirmed.
4. After the bottleneck is confirmed, target a steady-state budget below
   16.67 ms and a p95 below that budget; do not judge success by mean FPS
   alone.

No gameplay, renderer, or golden-reference changes were made for this report.
