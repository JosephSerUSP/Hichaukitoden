# Fog Presets, Panorama Layers, and the Tileset Tab — Design

Status: implemented (20.07.2026). Extends
[`raycaster-tileset-lighting.md`](raycaster-tileset-lighting.md) and the fog
work reviewed/cleaned up the same day. Three asks bundled because the third
depends on the first two: shared fog presets (so editing one preset updates
every map using it), panorama fog (scrolling mist images, not just a flat
color, with room for multiple blended layers), and a Tileset tab in the
editor to manage both plus the tileset atlas manifests.

## Why panorama forced a rendering refactor

The existing fog mix was `finalColor = mix(fogColor, shaded, fogAlpha)` —
computed per-surface (once in the floor/ceiling shader, duplicated by hand
in the wall loop and the sprite tint). That formula blends toward a single
*solid color*. A scrolling mist texture isn't a color, so panorama support
is not addable on top of that formula — it needs the fog "color" to be
something the GPU composites as a layer, not a uniform.

The fix is simpler than the thing it replaces: draw the fog background
(flat fill, or one or more scrolling panorama layers) to the screen
**first**, then draw walls/floor/ceiling/sprites with `alpha = fogAlpha`
using ordinary alpha blending, letting distant/fogged pixels reveal
whatever was drawn underneath. This means:

- The floor/ceiling shader no longer needs a `fogColor` uniform or a
  `mix()` call — it outputs `vec4(shaded, fogAlpha * texColor.a)` and lets
  LÖVE's default alpha blend mode do the compositing.
- The wall loop's fog/no-fog branch (the thing flagged as duplicated in the
  last review) collapses further: `love.graphics.setColor(litR, litG, litB,
  fogAlpha)` unconditionally, no background-rectangle-per-column, no
  manual `color*(1-a) + fog*a` arithmetic.
- Sprites: same, `setColor(r, g, b, fogAlpha)` instead of a pre-mixed tint.
- A flat fog color is just the degenerate case: one full-screen rectangle
  fill instead of a scrolling image. No special-casing needed at the
  surface level — only `drawFogBackground()` branches on flat-vs-panorama.

This is the refactor recommended in the prior review (unify the shading
model instead of maintaining parallel copies), arrived at because panorama
required it, not as a separate speculative pass.

## Panorama layers

`fog.panorama` is a **list** (even though today there's one image in
`assets/panorama/`), so multiple blended layers are additive later, not a
schema break:

```json
"panorama": [
  { "image": "fog_001", "scrollX": 0.01, "scrollY": 0.0, "blendMode": "alpha", "opacity": 1.0 }
]
```

Each layer is drawn as a screen-covering quad sampling a repeat-wrapped
image, offset by `love.timer.getTime() * scroll* * imageDimension` (mod
the image size) — the standard scrolling-background technique, one draw
call per layer, no shader needed for the scroll itself. `blendMode` maps
directly to `love.graphics.setBlendMode()`; supported values: `alpha`
(normal), `add`, `multiply`, `screen`. Layers draw back-to-front in list
order. An empty/absent `panorama` list means flat-color fog, unchanged
from before.

## Fog presets: shared, not copied

`data/engine.json` (and each campaign's own `engine.json`) gains
`fogPresets`: a named registry, same shape/editing pattern as the existing
`effectTypes`/`traitCodes`/`metaKeys` registries (`buildRegistryRows` in
`engine-editor.js`).

A map's `fog` field is now either:
- `{ "preset": "misty_dusk" }` — resolved against `loader.engine.fogPresets`
  at render time. Editing the preset updates every map referencing it,
  which is the actual ask ("consistent across different maps").
- Inline fields (`color`/`density`/`minFactor`/`panorama`), exactly as
  before — for a one-off map that shouldn't be a shared preset.

Preset resolution happens in `getFogConfig`, which now takes the `session`
(for `session.loader.engine.fogPresets`) instead of just `mapData`. A
`preset` naming a missing id falls back to the black/no-fog default rather
than erroring, matching how the rest of this renderer degrades on missing
data (missing atlas, missing light grid, etc.) — the validator catches the
authoring mistake separately.

## Tileset tab

New Engine Editor tab, alongside Rendering/Effect Types/etc. Two panels:

- **Fog Presets**: a list+detail editor (like the encounters list pattern
  in Map Properties) — select a preset on the left, edit color/density/
  minFactor/panorama layers on the right. Lives in `dbPayload.engine`, so
  it saves through the normal Save Changes flow.
- **Tilesets**: `assets/tilesets/*.png` atlases aren't part of any
  DATA_FILES payload — they're static assets shared across every campaign,
  like the PNGs themselves. New server endpoints (`GET /api/tilesets`,
  `POST /api/tilesets/save`) list and write the sidecar `.json` manifests
  directly, on their own save action, independent of the Database's Save
  Changes button — editing an atlas's row layout is now a form instead of
  hand-editing JSON.

Map Properties' fog section gains a preset dropdown (`(custom)` keeps the
existing inline-field behavior); selecting a preset stores the reference
and disables the manual fields, since they're no longer this map's own data.

## Explicitly out of scope

- Painting/authoring new panorama images — that's still hand-painted art
  dropped in `assets/panorama/`, same as tileset atlases.
- Per-layer masking or blend-mode combinations beyond LÖVE's built-in
  `setBlendMode` values.
- Panorama on the gradient fallback path (no atlas at all) — that stays
  opaque and ambient-tinted only, unchanged; it's the rare "atlas file
  missing entirely" case, not worth extending.
