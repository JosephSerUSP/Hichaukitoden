# Semantic Tiles and Baked Lighting

This is the authoring model introduced after the original atlas/vertex-light
implementation. Geometry remains a compact `#`/`.` layout; semantic material
overrides are an optional parallel `map.materials` grid.  This preserves map
shape and event coordinates while giving selected cells a named meaning.

## Tileset manifest

`assets/tilesets/<name>.json` has a `tiles` table.  Each key is a stable tile
id and its `atlas` is `[row, column]`, zero-based.

```json
"wall_torch": {
  "atlas": [1, 1],
  "solid": true,
  "emitsLight": { "color": [1, 0.58, 0.22], "radius": 4, "falloff": 2 }
}
```

The map editor's Tileset panel previews the atlas and edits these definitions.
Only cells that need a special identity need an entry in `materials`; ordinary
walls keep the atlas's deterministic visual variation.

## Lighting objects and bake

`map.lightObjects` contains lighting-only fixtures:

```json
{ "x": 10, "y": 5, "material": "wall_torch", "color": [1,0.58,0.22], "radius": 4, "falloff": 2 }
```

They are not map events.  Baking traces line-of-sight through the map geometry,
writes the existing vertex `map.light` grid, and starts from a dark ambient
baseline.  Artists then use Paint/Blur to overwrite that baked grid. Re-baking
is explicit and replaces the baseline, so it never silently destroys manual
lighting work.

Procedural dungeons create a deterministic set of wall-torch light objects
while generating their layout and bake the same vertex format at runtime.
