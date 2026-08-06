# asset-gen

Prompt -> game-ready art, at the exact dimensions, layout and filename the
engine already expects.

This is **not part of the editor**, deliberately: it spends money, it takes
minutes per asset, and it writes binaries. The editor stays a fast, free,
offline authoring surface.

## Quick start (visual)

Double-click `userPerform\runAssetGen.bat`. It serves a local page on
127.0.0.1:7801 and opens it: pick a class, type a name and a description, press
Generate, then Promote the variant you like. Staged variants are shown upscaled
with nearest-neighbour so you can actually judge the pixels.

Set `OPENAI_API_KEY` once with `setx OPENAI_API_KEY sk-...` (then reopen the
prompt), or paste a key into the Key box — the UI keeps it in the server
process's memory only and never writes it anywhere.

Every button in the UI runs the CLI command below it with captured output; there
is no second code path, and the log on the page is the log the CLI printed.

## Quick start (terminal)

```
set OPENAI_API_KEY=sk-...
python tools/asset-gen/gen.py classes
python tools/asset-gen/gen.py generate smallBattler Kappa "a river-turtle imp with a mossy shell and a water-filled skull dish on its head"
python tools/asset-gen/gen.py promote latest --variant 2
```

Nothing reaches `assets/` until you `promote`. Generation writes to
`tools/asset-gen/out/` (gitignored): the raw model output, each processed
variant, a `contact-sheet.png` upscaled 4x so you can actually judge the pixels,
and a `manifest.json` recording the prompt, provider, model and target path.

New generation manifests contain `manifestKind: "asset_gen_run"` and
`manifestVersion: 1`. The height-pattern tool writes
`manifestKind: "height_pattern_set"`; these are not runs. Complete legacy run
manifests without a kind remain accepted when they contain `class`, `name`, and
`variants`. `gen.py runs` ignores non-run manifests and reports a concise note;
direct run operations reject non-run folders.

## Commands

| Command | What it does |
|---|---|
| `classes` | List asset classes, their geometry and their target directory |
| `generate <class> <Name> ["description"]` | Render N variants into a staged run |
| `runs` | List staged runs and which have been promoted |
| `reprocess [run]` | Re-run the pixel pipeline on staged raw output. **No API call, no cost** |
| `promote [run] --variant N` | Copy one variant to its real path in `assets/` |
| `tilecheck [run]` | Score a run's seams and write a 3x3 layout of each variant |
| `batch <jobs.json>` | Generate many assets from one job file, sequentially |
| `report [run ...]` | Self-contained HTML: every variant, its score, its prompt |
| `audit [dir] --out x.html` | Score the tiling of art already on disk |

Useful `generate` flags: `--variants N`, `--provider`, `--model`, `--ref <png>`
(style-match an existing asset; repeatable), `--cell WxH` / `--frames N` (sheet
classes), `--grid ColsxRows` (what layout to ask the model for), `--extra "..."`
(extra art direction), `--token fps=12`, `--dry-run` (print the prompt, call
nothing).

`reprocess` is the important one: tuning `classes.json` geometry or a
post-processing step costs nothing, because the expensive part is already on
disk. When it writes a complete legacy run manifest back, it adds
`manifestKind: "asset_gen_run"` and `manifestVersion: 1` while preserving the
legacy fields. A direct path must resolve to a validated run; pattern-set and
other manifest directories are rejected before processing or context preview.

## Asset classes

`classes.json` is the registry, and it is the only extension point — a new class
is an entry there plus a `prompts/<file>.md`, never a branch in `gen.py`. Each
entry pins the final size, the cell grid, the filename pattern (including the
engine's `[key=value]` tokens), and the ordered post-processing pipeline.

| Class | Final size | Notes |
|---|---|---|
| `smallBattler` | 72x24 | 3-frame idle strip; `[fps=N]` lives in the filename |
| `bigBattler` | 128x128 | **New class, not engine-wired yet** — see below |
| `portrait` | 640x192 | 5 x 128x192 expression columns; `ui.lua` slices column 0 |
| `sprite` | 48x64 | Single billboard for the 3D view — never a sheet |
| `tileset` | 256x256 | 16 seamless 64x64 textures, flat and unlit |
| `texturePiece` | 64x64 | One floor/ceiling material; wraps on both axes |
| `wallPiece` | 64x64 | One wall material; wraps horizontally only |
| `panorama` | 256x256 | Wraps horizontally; the seam is cross-faded |
| `locationArt` | 192x256 | Region establishing shot |
| `eventArt` | 496x208 | Wide cutscene banner |
| `animation` | cell x frames | Greyscale flipbook; tinted at runtime |

Every class inherits `styleBible` from `classes.json` — edit that one string to
move the whole game's art direction.

`iconset` is deliberately absent. A 12x12 icon grid keyed by ID
(`assets/system/README.md`) is a job for generated code, not a diffusion model.

## Post-processing

Image models return large, smooth, opaque pictures; the engine wants small,
hard-edged, palette-limited, usually transparent sheets. `lib/postprocess.py`
holds the named steps and `classes.json` orders them:

`key_background` (chroma-key the magenta backdrop the prompt asks for, falling
back to a flat corner colour) - `slice_grid` (cut the model's grid into cells
and repack them the way the engine reads them) - `pixel_fit` - `quantize`
(adaptive palette, alpha preserved separately so edges don't fringe) -
`harden_alpha` (no semi-transparent pixels) - `greyscale` - `seam_blend_x`.

A run fails loudly if the pipeline does not land on the class's exact size.

## Providers

`config.json`, same shape as `tools/campaign-gen/config.json`. Keys come from
the environment only, never from the config file or a flag.

| Provider | Env var | Type | Default model |
|---|---|---|---|
| `openai` (default) | `OPENAI_API_KEY` | `openai-images` | `gpt-image-1-mini` |
| `gemini` | `GEMINI_API_KEY` | `gemini-image` | `gemini-3.1-flash-lite-image` |
| `openrouter` | `OPENROUTER_API_KEY` | `openai-chat-image` | an image-capable chat model |
| `forge-lcm` | none (local) | `sdapi` | `dreamshaper_8LCM` -- ~30s per tile |
| `forge-quality` | none (local) | `sdapi` | `perfectWorld_v3Baked`, 26 steps -- the default local one |

Override per run with `--provider` / `--model`, or set `ASSET_GEN_PROVIDER`.
All three accept `--ref` style conditioning; on OpenAI that switches the call to
`/images/edits`, the only route there that takes reference images.

## Local generation (the `forge-*` providers)

Free, offline, and the only way to get art in this project's own retro-game
style, because the style LoRAs live on this machine and no hosted model has
them. It drives an existing Forge install (`FORGE_HOME`, default
`D:\AI\webui_forge_cu121_torch231`) through its HTTP API.

```
python tools/asset-gen/forge.py start       # detached; first start is slow
python tools/asset-gen/forge.py models      # what checkpoints and LoRAs exist
python tools/asset-gen/gen.py generate surface mossy_limestone "damp grey limestone blocks" \
    --provider forge-lcm --variants 4 --promote
python tools/asset-gen/gen.py tilecheck
python tools/asset-gen/forge.py stop
```

`forge.py` never modifies the install: it sets `COMMANDLINE_ARGS` itself and
calls `webui.bat`, because Forge's own `webui-user.bat` hard-codes those args
and would drop `--api`.

Extra `generate` flags, local only: `--steps`, `--cfg`, `--sampler`, `--seed`
(variants walk upward from it, so a run is reproducible), `--no-tiling`,
`--height <png>`, `--promote`, `--force-dirty`.

### Seamless is done here, not by the model

Forge accepts `tiling` in its payload and **silently ignores it** --
`modules_forge/utils.py:apply_circular_forge` has its body commented out and
prints "Tiling is currently under maintenance". So a tiling class gets its wrap
from an axis-aware second pass instead: the picture is rolled by half its size
on each declared wrapping axis, then only those middle joins are inpainted.
wallPiece declares x only, so the vertical edges are never rolled or joined.
The outer edge is masked off and restored afterwards, then the repaired image
is rolled back to its original coordinates. That last inverse roll is
important when --height is used: the seamless pass must not move the albedo
away from the authored height map.

Measured on limestone: seam ratio 6.9 before, 0.5-1.0 after.

### Reading the numbers

`tilecheck` and every `generate` print ratios for the active axes. 1.0 means "as smooth as the
rest of the texture"; over 2.0 is a join you will see once the texture repeats
down a corridor.

- `x` / `y` -- the declared wrap at the tile edge. `wallPiece` intentionally
  leaves y unmeasured.
- `centre_x` / `centre_y` -- the middle, where the seamless pass relocates the
  active join. Judging on the wrap alone systematically prefers the variants
  where that went worst, so the active wrap and centre are ranked together.

An axis reads `unmeasurable` when the edges are transparent: that is a cut-out,
not a tile, and it scores last rather than perfect.

### Do not ask for pixel art. Ask for a good texture and let the pipeline squash it

The retro look is produced by the *post-processing*, not by the prompt. The
model renders at 512, `pixel_fit` reduces that 4x to 128, and `quantize` clamps
it to a small palette -- and that reduction IS the pixelation. It produces true
hard-edged pixels on a tight palette.

Asking SD1.5 for "16-bit pixel art" instead gets you a soft, blurry *imitation*
of pixel art, which then goes through the same reduction and comes out as mush.
Detail in the source survives the squash as legible texture; mush does not.

So the local prompt asks for the best, sharpest, most detailed version of the
real material -- `masterpiece, best quality, highly detailed, sharp focus, 4k,
substance designer material` -- and `pixel art, pixelated, low resolution` are
in the *negative* prompt. The style bible's retro prose is still what the hosted
models get, since they are being asked to draw a finished sprite rather than
source material for a reduction.

`forge-quality` (Perfect World, 26 steps, CFG 7, no style LoRA) is the default
local provider for this reason.

### Prompts: SD1.5 is not a hosted model and will not read a paragraph

The hosted models take the prose template in `prompts/<class>.md`, including its
prohibitions. Local SD1.5 gets `prompts/<class>.tags.md` instead, chosen by the
provider's `promptStyle: "tags"`, and the difference is not cosmetic:

- **CLIP reads 75 tokens per chunk and weights the earliest most.** Measured, the
  prose template runs to about 400 tokens and does not reach the material until
  roughly token 100 -- so the model was being asked for "retro JRPG pixel art in
  the RPG Maker 2003 tradition" and only faintly for limestone. That is the real
  reason early tiles came out as red hallways.
- **SD cannot negate.** "no perspective, no baked lighting" contributes
  *perspective* and *lighting* to the picture. Every prohibition belongs in the
  provider's `negativePrompt`, which is where it actually subtracts.
- **Material first, then framing, then style**, comma-separated.

`styleTags` in `classes.json` is the style bible in that form. Override per run
with `--prompt-style prose|tags` to compare.

### Steps: LCM checkpoints are the exception, not the rule

20-30 steps is right for an ordinary checkpoint, and `forge-quality` uses 26. The
LCM checkpoints are distilled to converge in **4-8** steps at low CFG (~2), and
running them longer does not improve them. `--steps` overrides either. The
sweep behind these defaults is reproducible:

```
python tools/asset-gen/gen.py generate surface probe "grey limestone" \
    --provider forge-lcm --steps 4 --seed 4242 --variants 2
python tools/asset-gen/gen.py report <run> <run> --out compare.html
```

### Looking at the results

```
python tools/asset-gen/gen.py report            # latest run -> out/report.html
python tools/asset-gen/gen.py audit --out audit.html
```

`report` writes one self-contained page -- images inlined as base64, no external
anything -- with each variant's tile, its repeated layout, its scores and the
exact prompt and sampler settings that made it. Pass several run names to
compare them side by side. The scores cannot tell you whether the picture is the
material you asked for; the page can. Classes with contextPreview also get a
real-engine screenshot: wall candidates are pasted into a temporary atlas and
rendered in a two-tile-wide corridor from both side positions. The preview can
use a shared authored height map and an explicit geometry density, so relief,
side continuity and in-game lighting are reviewed before promotion. The
generated material remains staged; the context atlas is never campaign data.

Use `wallPiece` for walls and `texturePiece` for floors or ceilings. A
`wallPiece` wraps only horizontally, so a bottom-anchored baseboard or lower
course remains at the bottom of the tile; `texturePiece` wraps on both axes.
Generate one material piece at a time and assemble the reviewed pieces into an
atlas. Prompt descriptions should contain visible material and map style only:
the depth/control image supplies relief and placement, so avoid phrases such as
"following the supplied depth guide" or "along the left edge".

For walls, prefer prompts that name the material and albedo intent directly:
unlit albedo, diffuse base color only, flat material colour, soft diffuse
lighting, gentle ambient fill, broad low-contrast shading. Put hard/deep/black
shadows, baked or directional lighting, torchlight, ambient occlusion and
dramatic lighting in the negative prompt. The report prints the exact negative
prompt sent to Forge beside each comparison.

`audit` scores art that already exists. Both the albedo and the height map of a
plane asset have to tile, and a height map that does not is the worse failure:
it puts a ridge across the mesh no amount of decimation care can hide.

### Conditioning on an authored height map

`--height assets/geometry/<name>/height.png` adds a ControlNet depth unit so the
albedo follows relief the mesh will actually have. Verified by measurement:
edge-structure correlation with the height map rose from +0.09 to +0.25.
Direction matters -- height is authored by `heightgen.py` and the *picture* is
made to agree with it. Height is never estimated from art; that was measured
useless on this project's pixel work.

**A height map that does not tile on an active axis cannot produce an albedo
that does.** Wall guides need only horizontal continuity; their vertical
composition is intentionally preserved. Floor and ceiling guides still need
both axes.

### Batches

```json
[
  { "name": "mossy_limestone", "description": "damp grey limestone blocks", "variants": 4 },
  { "name": "cracked_flagstone", "description": "worn grey flagstone floor", "provider": "forge-lcm" }
]
```

`python tools/asset-gen/gen.py batch jobs.json --promote` runs them one at a
time -- 4 GB of VRAM holds one model, so parallelism would only thrash the
checkpoint -- and prints a pass/fail summary.

`--promote` takes the best-scoring variant, and refuses if its seam is over the
threshold or if the destination has **uncommitted changes**: art gets
hand-corrected between runs, and overwriting an edit that exists nowhere else
has already cost real work here. `--force-dirty` overrides.

### Reusable checkpoint sweeps

For a deliberately non-agentic overnight comparison of the installed
SD1.5-family checkpoints, use the persistent wrapper. It runs one checkpoint at
a time, saves raw and processed output under `tools/asset-gen/out`, writes an
HTML matrix for each prompt family, and resumes completed runs after a stop.
It never promotes or overwrites game assets.

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tools\asset-gen\start_checkpoint_sweep.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\asset-gen\status_checkpoint_sweep.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File tools\asset-gen\stop_checkpoint_sweep.ps1
```

The worker log is `tools/asset-gen/out/overnight-wall-checkpoint-sweep.log`.
The sweep intentionally excludes SDXL checkpoints because this Forge profile
uses the SD1.5 material/ControlNet path; those need a separate XL-compatible
test profile to produce meaningful comparisons.

### Models and what they cost

```
python tools/asset-gen/gen.py models
```

Per-image USD at 1024x1024, from the table in `config.json`
(checked 2026-07-27 against <https://developers.openai.com/api/docs/pricing>):

| Model | low | medium | high |
|---|---|---|---|
| `gpt-image-1-mini` **(default)** | $0.005 | $0.011 | $0.036 |
| `gpt-image-1.5` | $0.009 | $0.034 | $0.133 |
| `gpt-image-1` | $0.011 | $0.042 | $0.167 |
| `gpt-image-2` | — | — | — |

The 1536x1024 sizes `eventArt` uses cost more; the table in `config.json` has
those columns too. `gpt-image-2` is billed per token with no per-image table
published, so the tool refuses to estimate it rather than guess.

**Prices in this repo go stale.** Everything here is labelled an estimate, the
table carries the date it was checked, and nothing computes a price in code —
correct a number by editing `config.json`.

**Why `gpt-image-1-mini` at `low` is the default:** the art gets crushed to 72x24
or 128x128 and then quantized to a couple of dozen colours. High quality buys
fine detail that the downscale throws away, at 7x the price for the same model
and ~30x the price of the default. Reach for `gpt-image-1.5` at medium when a
class keeps its detail — `portrait`, `locationArt`, `eventArt` — or when prompt
adherence is the problem (`tileset` ignoring "no perspective", say). Everything
is per-run: `--model` and `--quality`, or the dropdowns in the UI.

On transparent classes the OpenAI path asks for `background: transparent` and
gets a real alpha channel back, so `key_background` finds nothing to key and
says so — that message is expected, not a warning. Gemini has no such option and
genuinely relies on the magenta backdrop the prompt requests.

## Pending engine wiring: `bigBattler`

`spriteKey` currently does double duty — it names both the world sprite in
`assets/sprites` and the portrait in `assets/portraits`, and the battle renderer
draws that portrait as the enemy. `bigBattler` splits the battle sprite out, so
a creature has three distinct pieces of art: **smallBattler** (party grid strip),
**bigBattler** (enemy in battle), **portrait** (dialogue face).

The generator produces and promotes `bigBattler` today. The engine does not read
`assets/bigBattlers` yet; that change touches the actor schema, the validator's
asset sweep, `presentation/renderer.lua` and the editor's actor form, and is its
own pass.

## Requirements

Python 3 with `Pillow` and `requests`.
