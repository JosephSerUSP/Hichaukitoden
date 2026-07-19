# Floor/Ceiling Texturing — Shader Plan

Status: planning (19.07.2026), not yet implemented. Extends
[`raycaster-tileset-lighting.md`](raycaster-tileset-lighting.md), which
explicitly deferred this: floors and ceilings are currently flat vertical
gradients, tinted by vertex light but never textured. This doc plans the
shader-based floor/ceiling caster and, deliberately, the data-model room
needed so later "unorthodox" requests (variable height, non-grid shapes)
don't force a rewrite of what we build now.

## Why a shader, not more draw calls

Walls work as one `love.graphics.draw` per screen column (256 of them):
each column is a single distance, so one texture slice, one tint, one
draw call. Floors and ceilings don't have that property — every *row*
below/above the horizon is a constant distance, but every *pixel within
a row* is a different world position, because you're looking across the
ground rather than into a flat vertical plane. Classic "floor casting"
(Wolfenstein 3D and every raycaster since) computes a distinct world (x,y)
per pixel. At 256×72 pixels per half-screen, that's ~18,000 individual
texture lookups a frame in pure Lua draw calls — impractical. A GPU
fragment shader does exactly this per-pixel work natively and cheaply;
LÖVE's `love.graphics.newShader` gives us that directly.

## Rendering approach

Standard floor-casting math, run once as a fragment shader over a
256×72-pixel region (mirrored for the ceiling):

1. For screen row `y`, the perpendicular distance to the floor at that row
   is constant: `rowDist = (halfH) / (y - halfH)` (using the same `halfH`
   the current gradient split already uses).
2. The world position of pixel `(x, y)` is found by linearly interpolating
   between the world position the leftmost ray hits at `rowDist` and where
   the rightmost ray hits, using the *same* camera vectors
   (`dirX, dirY, planeX, planeY`, player `cx, cy`) `viewport_3d.lua` already
   computes for wall raycasting every frame — no new camera math, just the
   same numbers handed to the GPU as uniforms instead of used in a Lua loop.
3. `floorTexCoord = worldPos mod 1` gives the atlas UV within whichever
   64px cell the pixel falls in; `floor(worldPos)` gives the cell
   coordinate, which feeds the *same* deterministic wall-variant hash
   (`wallVariant`'s formula) so floor material variety follows the same
   "engine-random, not authored" rule wall variants already use — visual
   language stays consistent between the two.
4. Ceiling is the same math mirrored above the horizon, sampling the
   atlas's `ceilingRow` instead of `floorRow` (see manifest changes below),
   and only runs when `ceilingStyle` isn't `"sky"` (sky keeps its existing
   static-stretch path unchanged — this shader is additive, not a
   replacement for that).

## Vertex lighting on the GPU: light-as-texture

The current CPU-side `sampleLight` bilinearly interpolates a Lua table by
hand, once per wall column. A shader can't cheaply walk a Lua table, but
it doesn't need to: **bake `map.light` into a small texture** —
`(mapW+1) × (mapH+1)` pixels, RGB = the stored triple — uploaded once per
map load (cached alongside the atlas the same way `getAtlas` already
caches per name; invalidate/rebuild only when the map's `light` data
changes, e.g. after an editor save). Sampling it with **linear filtering**
gets bilinear interpolation *for free* from the GPU's native texture
sampling — no manual bilerp code needed in the shader at all, which is
simpler than the CPU version it's replacing. UV = world position / map
size, same as the walls already compute.

This also opens a later option (not required now, worth naming): if wall
rendering ever moves into a shader too, it could sample the exact same
light texture instead of the current per-column Lua bilerp, unifying the
lighting code path across walls/floor/ceiling into one sampler. Not part
of this phase — walls keep their existing, working draw-call approach.

## Manifest changes

`assets/tilesets/<name>.json` gains two more optional keys, alongside the
existing `wallRows`/`doorRow`/`skyRow`:

```json
{
  "wallRows": [0, 1],
  "doorRow": 2,
  "skyRow": 3,       // town_001: unchanged, static stretch
  "floorRow": null,  // new: single atlas row, floor-cast per-pixel
  "ceilingRow": null // new: single atlas row, ceiling-cast per-pixel (solid ceilings only, not sky)
}
```

`dungeon_001.json` already declares `ceilingRow: 3` (the roots texture,
corrected out of `wallRows` in this same pass) — it's dormant data right
now, consumed only once this shader lands. `floorRow` stays unset on both
current atlases until floor art exists; the flat gradient remains the
fallback for any map/atlas that doesn't declare the relevant row, or if
shader compilation fails (wrap `love.graphics.newShader` in `pcall`, log
and fall back — same resilience pattern the atlas loader already uses for
missing files).

## Scalability: what we make room for now vs. later

You asked specifically for this to stay sturdy against "unorthodox
elements like height, more advanced shapes." Being concrete about where
the line is:

**Cheap to reserve now, do later:** per-cell floor/ceiling *height* as
data. Add a `map.heights` grid — `H × W` (per **cell**, unlike `light`
which is per **vertex** — height is a property of a room/sector, not
something you'd want smoothly blended between four corners) — each entry
`{floor: number, ceiling: number}`, defaulting to `{floor: 0, ceiling: 1}`
everywhere so nothing changes today. Reserving the shape now means that
when variable height is actually tackled, it slots into an
already-GPU-resident per-cell texture (same light-as-texture pattern)
instead of requiring a new data pipeline built from scratch under time
pressure later.

**Not cheap, explicitly not happening in this phase:** actually *rendering*
variable height. The floor-casting formula above assumes one flat plane —
a single `rowDist` formula for the whole screen. Real multi-height
rendering (a Doom-style step up into the next room, seeing over a low
wall into a lower room) requires either a portal/sector renderer or a
per-column vertical raymarch against a heightfield — a materially
different rendering technique, not an extension of this shader. If/when
that's wanted, it's its own design pass with its own tradeoffs (portal
culling vs. raymarch cost vs. how it interacts with the existing
grid-based map format at all).

**Hard ceiling on this architecture, not a future phase of it:**
non-grid shapes (angled walls, curved rooms, true polygonal rooms).
Grid-based raycasting is fundamentally a uniform-cell-size technique —
diagonal or curved geometry needs a different map representation entirely
(a sector/portal graph or polygon mesh), which is a different engine, not
a bigger version of this one. Worth having said plainly now rather than
letting "scalable" imply this grid raycaster will eventually grow into
that — it won't, by construction. If that's ever wanted, it's a rewrite
of the spatial representation, not an extension.

## Implementation order (planned, not started)

1. Manifest: add `floorRow`/`ceilingRow` reading to `getAtlas()` (pure
   data plumbing, same shape as the existing `skyRow` read).
2. Light-as-texture: build/cache an Image from `map.light` per map load,
   linear-filtered.
3. Floor-cast shader: fragment shader implementing the per-pixel world-pos
   math above, sampling `floorRow`'s atlas region + the light texture,
   applying the same distance-based shading walls already use so floors
   don't look flatter/brighter than the walls around them.
4. Ceiling-cast shader: same shader (or a mirrored second pass) for
   `ceilingRow`, gated on `ceilingStyle ~= "sky"`.
5. Fallback wiring: gradient stays the path when the relevant atlas row is
   absent or shader compilation fails.
6. Floor art for at least one atlas (cobblestone for `town_001`, a stone
   floor for `dungeon_001`) so this is visually provable, not just
   technically correct.
7. `map.heights` scaffold (data only, default-flat, unconsumed) — reserved
   per the scalability section, not wired to any rendering behavior yet.

Verification plan: extend the existing `preview-map` headless tool (no
new tooling needed) to confirm floor/ceiling texture + lighting render
correctly before/after, same as the wall atlas and vertex-lighting work
was verified.
