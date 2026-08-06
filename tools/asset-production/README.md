# Asset production adapters

This directory is the first production use of the unified asset vocabulary. It
does **not** replace `tools/asset-gen`, the shared Blender core, the V2 surface
baselines, or the future full asset-record schema. It gives one coherent asset
set stable identities and connects those identities to the specialized tools
that already work.

## First Stratum set

`assets/authoring/first_stratum/asset-set.json` currently describes:

- four depth-conditioned wall/floor/ceiling surface products;
- a treasure chest with matching `closed` and `open` exports;
- a static ritual dais;
- a static offering pedestal.

Every entry uses contract representation, role, authoring space, placement
frame, semantic materials, states and intended product paths.

## Generate a surface

Inspect the exact existing `gen.py` invocation without spending credits:

```text
python tools/asset-production/generate_surface.py \
  first_stratum_floor_broken_flagstones --dry-run
```

Run it normally by removing `--dry-run`. The adapter invokes the existing
`wallPiece` or `texturePiece` pipeline, supplies the V2 `depth_guide.png`, and
then adds a `productionRecord` to the resulting `asset_gen_run` manifest. That
record hashes both the guide and metric height products and preserves the
intended albedo destination. The original run manifest lifecycle remains intact.

Provider/model/sampling overrides remain available, for example:

```text
python tools/asset-production/generate_surface.py \
  first_stratum_wall_ritual_pilasters \
  --provider sdapi --variants 6 --seed 1200 --lora JoStyle:0.65
```

## Build staged world props

Preview the Blender command:

```text
python tools/asset-production/build_world_prop.py \
  first_stratum_treasure_chest --dry-run
```

Build all declared states:

```text
python tools/asset-production/build_world_prop.py \
  first_stratum_treasure_chest
```

Set `BLENDER_BIN` when Blender is not on `PATH`. Builds go to
`out/asset-production/world-props/` by default. The Blender-side builder refuses
to write beneath `assets/`; promotion remains an explicit reviewed action.

Each state receives:

- deterministic OBJ/MTL export through `second_rite_asset_core.py`;
- an inspection `.blend`;
- contract metadata and semantic material bindings;
- bounds and socket data;
- SHA-256 output provenance in one `build.json` report.

The chest states are separate static models generated from one recipe and one
floor pivot. Runtime event-page switching is intentionally not part of this
commit.

## Validate

```text
python -m unittest discover \
  -s tools/asset-production/tests \
  -p "test_*.py" -v
```
