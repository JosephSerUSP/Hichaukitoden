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

On this 4 GB GTX 1650, `v1-5-pruned-emaonly` is the current quality baseline.
The provider explicitly selects `vaeFtMse840000EmaPruned_vaeFtMse840k.safetensors`
for SD1.5 requests. Do not restore the Forge SDXL additional module: it caused
liquid/wave decodes and isolated high-chroma specks in otherwise plausible
images. Ask before downloading anything that would take the session over 3 GB.

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
  `--provider forge-quality` is slower (~90s) and the one that actually obeys
  the prompt. **Prefer forge-quality whenever the art matters**; LCM is for
  exploring shapes, not for producing anything.
- `--seed N` makes a run reproducible; variants walk upward from it.
- `--promote` takes the best-scoring variant automatically.

For tilesets, do not ask SD for a whole 4x4 page. Generate one piece at a time
with several variants, then assemble the reviewed pieces with
`tools/asset-gen/assemble_atlas.py`. Use `wallPiece` for walls: it wraps only
horizontally, so bottom-anchored baseboards and lower courses stay at the
bottom. Use `texturePiece` for floors and ceilings, where both axes wrap. For
portraits, generate one `portraitPiece` at a time and assemble five selected
expression pieces into the engine sheet.

Ordinary atlas surfaces can use a tileset-level `heightMap` instead of a
separate `assets/geometry/<tile>/` directory. The map may be a full atlas or a
single tile-sized guide reused across the atlas; use `heightMapScale` to keep
wall, floor and ceiling relief separate. Keep directory-backed geometry for
fixtures and exceptional composed surfaces such as `shrine_recess`.

## Always hand back a page, not a paragraph

```bash
python tools/asset-gen/gen.py report            # -> out/report.html
```

Self-contained HTML: every variant's tile, its 3x3 layout, its score, and the
exact prompt and sampler settings. Pass several run names to compare them.
**Produce this whenever you generate anything and tell the user where it is** --
art cannot be reviewed from numbers, and every failure so far has been a
flawless tile of the wrong material.

For wall classes, report also asks the real engine for a temporary context
capture. It uses a two-tile-wide corridor and two side positions, with the
candidate pasted into a temporary atlas. The capture may specify a shared
authored height map and geometry density 4.0; it leaves floor and ceiling on
their reference material and labels that explicitly. Review this context image
before promoting even a visually interesting throwaway candidate.

`gen.py audit --out audit.html` does the same for art already on disk.

The report also shows each raw `raw-N.png` beside the processed result. Inspect
raw images before judging the tiny output: high-chroma specks and liquid/wave
artifacts can disappear during downsampling and quantization.

## Never ask the model for pixel art

The retro look comes from the pipeline, not the prompt: render at 512, reduce 4x
to 128, clamp the palette. That reduction *is* the pixelation, and it gives true
hard pixels. Ask SD1.5 for "16-bit pixel art" and you get a blurry imitation of
pixel art which then reduces to mush.

Prompt for the best, sharpest, most detailed version of the **real material**.
`pixel art, pixelated, low resolution` belong in the negative prompt. This
applies to the local `forge-*` providers only; the hosted models are drawing
finished sprites and still get the prose style bible.

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
- Describe visible material and render format only. Do not write phrases such as
  “following the supplied depth guide”, “with one ... along the left edge”, or
  other placement instructions: the depth/control image carries shape and
  position, while those words add unpredictable visual content to SD's prompt.

Steps: 20-30 for ordinary checkpoints, **4-8 for the LCM ones** (they are
distilled for it; more does not help). `--steps` overrides.

## Judge by the numbers, then confirm by eye

Every run prints ratios for its declared wrap axes, and `tilecheck` re-prints
them ranked with a repeated layout of each variant:

```bash
python tools/asset-gen/gen.py tilecheck
```

- `x` / `y` -- the declared wrap at the tile edge (`wallPiece` intentionally
  leaves `y` unmeasured).
- `centre_x` / `centre_y` -- the middle, where the seamless pass relocates the
  join. **The active axes matter.** A texture can wrap perfectly and still have
  a hard line down its centre.
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
- **A height map that does not tile on an active axis cannot yield an albedo that
  does.** Wall guides need only horizontal continuity; their vertical
  composition is intentionally preserved.
- **The `tiling` flag in the Forge API does nothing** on this build. The wrap
  comes from a second pass in `lib/provider.py`. Do not "simplify" it away.

Full detail, including how the seamless pass works and why: the "Local
generation" section of `tools/asset-gen/README.md`.
