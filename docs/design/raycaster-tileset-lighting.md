# Raycaster Tileset, Doors, and Vertex Lighting — Design

Status: decided direction (19.07.2026), not yet implemented. Extends the
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

| Row | Contents |
|---|---|
| 0 | Wall variants (3–4 cells) |
| 1 | Floor variants (3–4 cells) |
| 2 | Doors — 1 cell used (standard door), remaining cells reserved for future variants (locked, portcullis, etc.) |
| 3 | Sky — a dedicated **256×64 region** (4 grid-cells wide), sampled as one continuous stretched image, not tiled per-column |

Sky is wide because it must read as one continuous horizon/cloud image, not
a repeating pattern — it does not share the 64px per-cell tiling rule.

## Wall/floor variant selection: engine-random, not authored

Wall and floor variants are **not** stored per-cell in map data. The
renderer picks a variant deterministically from a hash of cell coordinates
(`x, y`), giving free visual variety with zero editor authoring burden and
no map-schema growth. Doors, by contrast, are explicitly authored — they're
gameplay-relevant transitions and live alongside the existing map events
system, not the ambient wall material.

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
independently-drawn columns that can be tinted per-column.

- **Storage**: a 2D float grid over map *vertices* (grid corners, not
  cells), sized `(mapW + 1) × (mapH + 1)`, values 0–1 brightness, stored
  directly in `maps.json` as a plain array of arrays. No separate image
  asset — JSON is fine at map scale.
- **Sampling**: at render time, for each wall slice, bilinearly interpolate
  the 4 surrounding vertex brightness values using the same fractional hit
  position (`wallX`) already computed for texture sampling in
  `viewport_3d.lua`, then `love.graphics.setColor(b, b, b, 1)` before
  drawing that slice. Floor/ceiling gradient color stops get the same
  per-column tinting, driven by the player-cell's interpolated brightness.
- **Authoring**: a new brush tool in the map editor (`tools/editor/`) to
  raise/lower brightness at grid vertices, visualized as an overlay on the
  map grid. This is UI work over a grid of numbers, not real pixel
  painting — small relative to the rest of this feature.
- Open (not decided): free float brush vs. snapping to a small discrete set
  of light levels for a more deliberately banded/retro look. Can be
  decided during editor-tool implementation without blocking the renderer
  work.

## Explicitly out of scope for this pass

- Wraparound/panning sky (noted as future).
- Door variants beyond the standard door.
- Making town fully walkable end-to-end (this doc covers the rendering
  substrate: atlas, doors-as-wall-texture, sky ceiling, lighting — wiring
  an actual town map onto it, and converting `drawTown` off the menu-fake
  path, is follow-on work once the substrate lands).
- Generator/asset-manifest changes so LLM-generated campaigns can reference
  real tileset variants — separate, already-identified gap (no asset
  listing is fed into `tools/campaign-gen/lib/context.js` today).

## Implementation order

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
