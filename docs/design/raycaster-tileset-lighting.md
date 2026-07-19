# Raycaster Tileset, Doors, and Vertex Lighting — Design

Status: implemented (19.07.2026), first atlas (`assets/tilesets/town_001.png`)
landed and verified via the `preview-map` headless renderer. Extends the
existing first-person raycaster (`presentation/viewport_3d.lua`) rather than
replacing it. Directly supports [`commercial-identity.md`](commercial-identity.md)'s
town-as-real-space goal and the "different types of walls/floors/doors" ask
raised while reviewing generator campaign output.

## Why

Today the raycaster samples exactly one hardcoded texture
(`assets/textures/dungeon_tileset.jpg`) for every wall cell in every map, has
no floor/ceiling texturing (flat gradients only), and has no door concept —
map-to-map transitions are entirely scripted map events, not a renderable
tile type. Town is currently faked as a static-image-plus-menu scene
(`presentation/renderer.lua:drawTown`) rather than a walkable space, which
`docs/plans/overhaul-4/future-map-kind.md` already flags as a known
compromise.

Reference points considered: Wizardry (static image per location — the
compromise we're avoiding), Arcana SNES (looping panorama — its own
renderer, not reused), Shin Megami Tensei / Boundary Gate (raycast exterior
with a sky ceiling, door graphics in wall slices, static-image-plus-menu
interiors). SMT's approach reuses the raycaster we already have almost
entirely as-is, so it's the adopted direction: **town becomes a raycast map
like dungeons**, textured differently (sky ceiling, cobblestone floor,
building-front walls with doors), and doors are the general mechanism for
both town building entry and dungeon room/vault transitions.

The engine already has unused scaffolding for this:
`viewport_3d.lua` defines `tileW/tileH = 256, 256` and
`sheetW/sheetH = 1024, 1024` (room for a 4×4 atlas) but only ever samples
slot `(0,0)`. This is a "finish what's half-built" change.

## Tileset atlas format

Single PNG, nearest-neighbor filtered (already the engine's filter mode
everywhere). Grid cells are **64×64px** — painted at true low resolution so
nearest-neighbor upscaling gives the intended blocky/period-correct look,
rather than painting soft detail into an oversized cell.

As delivered (`assets/tilesets/town_001.png`, 256×256 = 4×4 cells):

| Row | Contents |
|---|---|
| 0 | Plain wall variants (4 cells: cobblestone, dark stone, gray stone, sandstone) |
| 1 | Decorated building-front wall variants (4 cells: plastered walls with windows/ivy/arches) — pooled with row 0 as one 8-variant wall set, not a separate "floor" row as originally sketched |
| 2 | Door variants (4 cells — all four are real doors, not 1-used-plus-reserved as originally sketched) |
| 3 | Sky — a **256×64 region** (all 4 cells), sampled as one continuous stretched image, not tiled per-column |

Multiple named atlases are expected over time (the `_001` suffix anticipates
this), so atlases live under `assets/tilesets/<name>.png` and each map opts
in via a `tileset` field naming one (e.g. `"tileset": "town_001"`). A map
without a `tileset` field renders exactly as before this feature existed,
via the legacy single-image `assets/textures/dungeon_tileset.jpg` path —
this is how existing/generated dungeon maps stay untouched.

## Wall/door variant selection: engine-random, not authored

Wall variants (8, pooling rows 0–1) and door variants (4, row 2) are **not**
stored per-cell in map data. The renderer picks a variant deterministically
from a hash of cell coordinates (`x, y`) — a different hash salt for walls
vs. doors so they don't correlate — giving free visual variety with zero
editor authoring burden and no map-schema growth. *Which* cells are doors,
however, is explicitly authored (gameplay-relevant transitions), living
alongside the existing map events system, not the ambient wall material.

## Doors

A door renders **into the wall slice itself** — same per-column
texture-sampling path used for ordinary walls, just indexing the door cell
instead of a wall-variant cell for that specific grid cell. This is
distinct from the existing billboard system (`getEventSprite`), which
renders camera-facing sprites for NPCs/items; doors are wall-shaped, not
billboards.

- Movement/collision: a door cell is walkable-through only via trigger
  (interact), not freely, mirroring how wall collision already works in
  `engine/exploration.lua:tryMove`.
- Triggering a door swaps to a static-image-plus-menu interior scene (the
  existing `scene_host` menu/window pattern already used for the current
  "faked" town — repurposed as **building/room interiors**, not the whole
  town). Matches the SMT/Boundary Gate pattern: raycast exterior, door
  graphic, VN-style interior.
- Interior backgrounds may be reused across multiple doors (e.g. a generic
  shop interior) rather than requiring a unique painted image per location;
  bespoke painted interiors are reserved for a handful of named,
  plot-important locations.
- Future extension (not in scope now): door variants beyond the standard
  door (locked, sealed by a trap-room event, etc.) — reserved atlas cells
  anticipate this.

## Per-map ceiling flag

A per-map property, e.g. `"ceilingStyle": "sky" | "solid"`, swaps the
existing upper-half draw (`drawVerticalGradient` in `viewport_3d.lua`)
between:

- **sky**: the atlas's 256×64 sky strip, stretched across the full screen
  width as one static image. Does **not** pan with player facing/view angle
  in this iteration — kept static for cost; wraparound skybox (panning by
  view angle) is an explicit, deliberately deferred future option, not
  designed further here.
- **solid**: existing flat/gradient ceiling behavior, unchanged.

This is a per-map decision (whole exterior gets sky, whole interior/dungeon
gets ceiling), not per-cell — matches how the reference games use it.

## Vertex lighting

Feasible without a real lighting engine, because wall slices are already
independently-drawn columns that can be tinted per-column. Colored, not
just grayscale-brightness — an `{r,g,b}` triple per vertex, so painted
light can carry hue (warm torch pools vs. cool moonlight), not just
intensity.

- **Storage**: a grid over map *vertices* (grid corners, not cells), sized
  `(mapW + 1) × (mapH + 1)`, each entry an `[r, g, b]` triple (each 0–1),
  stored directly in `maps.json` as a plain array of arrays of triples. No
  separate image asset — JSON is fine at map scale. Absent/unset vertices
  default to `[1,1,1]` (full white = no tint), so a map without `light` at
  all renders identically to before this feature existed.
- **Sampling**: at render time, for each wall slice, bilinearly interpolate
  each of the 4 surrounding vertices' R, G, and B channels independently
  using the same fractional hit position (`wallX`/world hit coords) already
  computed for texture sampling in `viewport_3d.lua`, then
  `love.graphics.setColor(litR, litG, litB, 1)` before drawing that slice
  (multiplied against the existing distance/side shading, same as the old
  scalar brightness was). Floor/ceiling gradient color stops get the same
  per-channel tinting, driven by the player-cell's interpolated color —
  each gradient stop's own R/G/B is multiplied by the matching light
  channel, so the base gradient's hue (e.g. the ceiling's purple-indigo)
  is preserved and just modulated by the painted tint, not overwritten by
  it. Sky is exempt (see above): daylight, not treated as a light source.
- **Authoring — done**: a third editor layer ("Light", alongside Map and
  Event, `tools/editor/index.html`/`js/map-editor.js`) paints `map.light`
  directly. Controls: an `<input type=color>` picker sets the tint hue, an
  Intensity slider (0–100%) scales it (white + 100% reproduces old pure-
  brightness painting), and a Brush Radius slider (0–6, was a number input
  originally — changed to a slider to match Intensity) applies the
  composed color to a square block of vertices around the cursor (uniform,
  no falloff). The canvas overlay renders an actual bilinearly-interpolated
  gradient fill between corners (a 4×4 sub-cell supersample per grid cell,
  the same math the engine does per-pixel, just at display resolution) —
  not discrete dots — so the painted gradient reads directly against the
  map, with small color-matched handle dots on top for precise click
  targeting. "Reset Map to Full Brightness" deletes `map.light` entirely.
  Free brush, not snapped to discrete levels. Unavailable on procedural
  maps (no fixed layout to paint vertices onto).

## Verification

`lovec . preview-map <mapId> [x] [y] [dir]` (added in `main.lua`, alongside
the existing `preview-scene`/`preview-window`/`preview-font` headless
preview modes) loads a map by id, positions the camera, runs the real
`viewport_3d.draw()` onto an offscreen canvas, and dumps a base64 PNG
between `PREVIEW BEGIN`/`PREVIEW END` markers — no interactive window
needed. Used to confirm the atlas, doors, sky, and lighting all render
correctly against `town_001.png` before this landed; reusable going
forward for any tileset/lighting iteration, and a natural fit for an
editor-side map preview later.

## Status of "explicitly out of scope" items

- Wraparound/panning sky: still deferred, as planned.
- Door variants beyond one standard door: **done differently than
  planned** — the delivered atlas has 4 real door variants (row 2), not 1
  used + 3 reserved, so door variant selection uses the same
  hash-per-cell approach as walls rather than always sampling column 0.
- Making town fully walkable end-to-end: still follow-on work. This pass
  landed the rendering substrate (atlas, doors-as-wall-texture, sky
  ceiling, lighting) and validated it against the existing town map's
  layout with test data (a temporary door + light grid), but did not
  redesign the town map itself or touch `drawTown`'s menu-fake path.
- Generator/asset-manifest changes: still a separate, identified gap.

## Implementation order (historical — see Status above for what shipped)

1. Atlas loader: replace hardcoded single-texture load in
   `viewport_3d.init()` with a real grid atlas (configurable `tileW/tileH`,
   variant-count-per-row), deterministic per-cell variant hash for
   walls/floors.
2. Door rendering: new tile/event type sampling the door atlas cell in the
   wall-slice draw path; collision treats it as trigger-only passable.
3. Sky ceiling: per-map `ceilingStyle` flag, swap upper-half draw between
   sky-strip stretch and existing gradient.
4. Vertex lighting: map schema addition (`light` vertex grid), bilinear
   sampling + per-column tint in the wall/floor draw paths.
5. Editor: lighting brush tool over the map grid.
6. Door-triggered interior scene: repurpose the existing
   menu-plus-static-image scene pattern as a building/room interior,
   reusable across multiple doors.
