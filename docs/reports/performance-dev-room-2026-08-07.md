# Developer-room performance diagnostic

Date: 2026-08-07  
Target: developer room, map `8` (`Developer Room`)  
Baseline: 60 FPS = 16.67 ms/frame

## Executive finding

The developer room is genuinely below the 60 FPS budget in the real 3D
renderer. The headless renderer profile measured a 19.09 ms steady-state mean
(about 52.4 FPS), a 15.29 ms median, a 49.71 ms p95, and an 82.54 ms worst
frame over 300 frames.

The strongest measured correlation is the renderer path, not room size. Map 8
resolves the default tileset and reports about 184 model draws, 192 total draw
calls, 191 queued surfaces, and no resident structural vertices. These counts
are evidence of a different workload, not proof that draw-call count alone is
the bottleneck. CPU clipping, dynamic mesh preparation/upload, and draw
submission all remain plausible contributors. Comparable fixed rooms use
persistent structural batches and are much cheaper.

## Measurements

All measurements came from the existing `lovec . profile-3d <map> 300` mode.
That mode renders the real `presentation.viewport_3d` path, flushes the LÖVE
graphics batch, warms the renderer before sampling, and reports the renderer's
own frame statistics.

| Map | Mean ms | Median ms | P95 ms | Max ms | Approx. FPS | Draw calls | Model draws | Lua memory delta |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 8 Developer Room | 19.09 | 15.29 | 49.71 | 82.54 | 52.4 | 192 | 184 | 118.6 MB |
| 9 Showcase | 2.21 | 1.79 | 5.49 | 11.03 | 452.2 | 43 | 39 | 30.9 MB |
| 12 Depth Explore | 6.17 | 5.43 | 11.21 | 16.44 | 162.2 | 226 | 225 | 20.9 MB |
| 13 Wall/Recess Compare | 2.10 | 1.71 | 4.98 | 12.14 | 476.5 | 32 | 28 | 25.0 MB |
| 14 Height Compare | 5.37 | 4.86 | 9.80 | 17.19 | 186.2 | 36 | 32 | 65.4 MB |

The profile's `luaMemoryDeltaKb` is the difference between
`collectgarbage("count")` before sampling and after sampling. It is a memory
delta, not an allocation counter, and does not establish per-frame allocation
volume or GC causality. The map 8 value is approximately 118.6 MB over the
profile run; this is a signal worth investigating, not proof of transient
allocation or a cause of the frame spikes.

## Why the small room is expensive

Map 8 is only 15x8 cells and has no encounters, but it does not declare a
special tileset. The tileset resolver consequently selects `dungeon_default`.
That tileset declares a 24x24 height map and a 384-triangle height-surface
budget. In `presentation/viewport_3d.lua`, height surfaces are queued as
placed model surfaces for floors and ceilings, while visible wall surfaces and
event models are queued separately.

The renderer then walks and queues those placed surfaces every frame. Unlike
the showcase rooms, map 8 reports zero resident structural vertices and zero
persistent batch draws. This establishes that map 8 takes a substantially
different steady-state path; it does not yet isolate whether the time is spent
in model draws, CPU-side clipping, dynamic mesh work, or another stage of that
path.

The current quality presets can reduce geometry density and compilation cost.
The existing profile does not vary those presets or time their individual
stages, so the exact reason quality reduction helps remains to be measured.

## First instrumented profile

The diagnostic instrumentation was then run for 300 frames on maps 8 and 12.
The timers themselves add overhead, so these values should be used for relative
stage comparison, not as a replacement for the uninstrumented FPS result.

| Map | Queue phase | Visibility/depth | Near clip | Mesh upload | Model draw loop | Visited | Near-clipped |
|---|---:|---:|---:|---:|---:|---:|---:|
| 8 Developer Room | 13.25 ms | 6.60 ms | 3.10 ms | 3.40 ms | 0.27 ms | 200 | 28 |
| 12 Depth Explore | 9.05 ms | 4.96 ms | 2.48 ms | 1.06 ms | 0.38 ms | 351 | 17 |

This supports the narrower hypothesis: the expensive work is in preparing and
classifying placed geometry, not in the final model draw loop. It also shows
that map 12's higher raw model-draw count is not sufficient to explain map 8's
cost. The numbers do not yet isolate whether map 8's excess is caused by its
height-surface geometry, placement mix, clipping shape, or another preparation
detail.

## Profiling-only A/B controls

The profile command now accepts a fourth argument: `current`, `no-height`,
`no-draw`, or `no-clip`. These modes are diagnostic-only and are not used by
normal play or screenshot capture. `no-height` omits height-authored placed
surfaces; `no-draw` still prepares them but suppresses their final draws;
`no-clip` bypasses the CPU near-plane clipping path and is intentionally not a
visually valid rendering mode.

An initial 30-frame map-8 run, with instrumentation overhead present, measured:

| Variant | Mean ms | Queue phase | Near clip | Model draw loop | Model draws |
|---|---:|---:|---:|---:|---:|
| `current` | 25.82 | 16.44 | 5.84 | 0.28 | 184 |
| `no-height` | 1.46 | 0.06 | 0.00 | 0.04 | 3 |
| `no-draw` | 22.06 | 15.30 | 5.62 | 0.05 | 184 |
| `no-clip` | 8.32 | 6.24 | 0.00 | 0.27 | 184 |

The absolute values are not directly comparable to the uninstrumented
baseline, but the experiment is clear: suppressing final model draws barely
changes the cost, while bypassing CPU clipping removes a large portion of it.
Omitting height surfaces removes nearly all of the placed-surface queue work.
The leading optimization target is therefore CPU-side preparation of
height-authored geometry, with near-plane clipping the first narrow suspect.

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

1. Add a profiling-only counter/timer around `queuePlacedModels`, CPU clipping,
   dynamic mesh uploads, and the final model-draw loop.
2. Test a cached/batched path for repeated height-map floor and ceiling
   surfaces, preserving the existing depth ordering and near-plane clipping
   behavior.
3. Measure map 8 with the height-map path disabled as an A/B control, and run
   the same matrix at each quality preset. This will separate height-map cost,
   quality cost, and draw-submission cost.
4. After the bottleneck is confirmed, target a steady-state budget below
   16.67 ms and a p95 below that budget; do not judge success by mean FPS
   alone.

No gameplay or golden-reference changes were made. The renderer and profile
command now contain profiling-only instrumentation and A/B controls.
