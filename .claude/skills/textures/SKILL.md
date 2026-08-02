---
name: textures
description: Generate game art on the local GPU - seamless wall/floor/ceiling textures, tileset pages, sprites - via tools/asset-gen and the local Forge server. Use when asked to make, draw, restyle or batch textures and other art assets for this project, or when a geometry asset needs an albedo.
---

# Generating art on the local GPU

Free, offline, and the only source of this project's retro-game style: the
style LoRAs are installed on this machine and no hosted model has them.

## Always start the server first

```bash
python tools/asset-gen/forge.py status || python tools/asset-gen/forge.py start
```

First start loads a checkpoint and takes minutes; after that it is warm. Leave
it running for a batch and stop it when the work is done. `forge.py models`
lists the installed checkpoints and LoRAs -- read it rather than guessing a
name, because an unknown one silently falls back.

## Generate

```bash
python tools/asset-gen/gen.py generate surface mossy_limestone \
    "damp grey limestone blocks, dark mortar, patches of moss" \
    --provider forge-lcm --variants 4 --promote
```

- `surface` is the class for `assets/geometry/<name>/albedo.png` -- the image
  the 3D compiler skins a plane with. `tileset`, `sprite`, `smallBattler` and
  the rest still work; `gen.py classes` lists them.
- `--provider forge-lcm` is fast (~30s a tile) and loose with the prompt.
  `--provider forge-retro` is slower (~60-90s) and much closer to the intended
  look. **Prefer forge-retro whenever the art matters**; use LCM to explore.
- `--seed N` makes a run reproducible; variants walk upward from it.
- `--promote` takes the best-scoring variant automatically.

## Always hand back a page, not a paragraph

```bash
python tools/asset-gen/gen.py report            # -> out/report.html
```

Self-contained HTML: every variant's tile, its 3x3 layout, its score, and the
exact prompt and sampler settings. Pass several run names to compare them.
**Produce this whenever you generate anything and tell the user where it is** --
art cannot be reviewed from numbers, and every failure so far has been a
flawless tile of the wrong material.

`gen.py audit --out audit.html` does the same for art already on disk.

## Prompting a local SD1.5 model

Do not write prose for the `forge-*` providers. It is handled for you -- they
declare `promptStyle: "tags"` -- but if you touch a prompt template, keep to it:

- Material first, comma-separated keywords, style last. CLIP weights the
  earliest tokens and reads 75 per chunk.
- **Never write a prohibition into the prompt.** SD has no negation; "no
  perspective" adds perspective. Prohibitions go in `negativePrompt` in
  `config.json`.
- Keep it under ~75 tokens. The prose template measured ~400 and did not reach
  the material until token 100, which is why early tiles ignored the request.

Steps: 20-30 for ordinary checkpoints, **4-8 for the LCM ones** (they are
distilled for it; more does not help). `--steps` overrides.

## Judge by the numbers, then confirm by eye

Every run prints four ratios, and `tilecheck` re-prints them ranked with a 3x3
layout of each variant:

```bash
python tools/asset-gen/gen.py tilecheck
```

- `x` / `y` -- the wrap at the tile edge.
- `centre_x` / `centre_y` -- the middle, where the seamless pass relocates the
  join. **Both matter.** A texture can wrap perfectly and still have a hard line
  down its centre.
- 1.0 is "as smooth as the rest of the texture". Over 2.0 is visible once the
  texture repeats down a corridor.

Read the numbers to triage a batch without opening anything. Then look at one
`tiled-N.png` before promoting, because the numbers cannot see the failure that
matters most: a texture that wraps flawlessly and still reads as obvious
repetition because one feature dominates the middle.

## Batches

```bash
python tools/asset-gen/gen.py batch jobs.json --promote
```

`jobs.json` is a list of `{name, description, class?, provider?, variants?,
seed?, height?}`. Runs sequentially -- 4 GB of VRAM holds one model.

## Rules

- **Never promote over a file with uncommitted changes.** The tool refuses, and
  that refusal is correct: art gets hand-corrected between runs and the edit
  exists nowhere else. Ask before using `--force-dirty`.
- **Check `git status` before regenerating an existing asset** for the same
  reason.
- **Height maps are authored, not generated.** `heightgen.py` bakes them from
  intended geometry. Depth estimation on this project's art was measured
  useless. `--height <png>` runs the relationship the other way: it conditions
  the albedo on relief that already exists.
- **A height map that does not tile cannot yield an albedo that does.** Score it
  first; `generate` warns, and the warning is not advisory.
- **The `tiling` flag in the Forge API does nothing** on this build. The wrap
  comes from a second pass in `lib/provider.py`. Do not "simplify" it away.

Full detail, including how the seamless pass works and why: the "Local
generation" section of `tools/asset-gen/README.md`.
