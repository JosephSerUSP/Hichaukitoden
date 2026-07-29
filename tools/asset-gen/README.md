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

## Commands

| Command | What it does |
|---|---|
| `classes` | List asset classes, their geometry and their target directory |
| `generate <class> <Name> ["description"]` | Render N variants into a staged run |
| `runs` | List staged runs and which have been promoted |
| `reprocess [run]` | Re-run the pixel pipeline on staged raw output. **No API call, no cost** |
| `promote [run] --variant N` | Copy one variant to its real path in `assets/` |

Useful `generate` flags: `--variants N`, `--provider`, `--model`, `--ref <png>`
(style-match an existing asset; repeatable), `--cell WxH` / `--frames N` (sheet
classes), `--grid ColsxRows` (what layout to ask the model for), `--extra "..."`
(extra art direction), `--token fps=12`, `--dry-run` (print the prompt, call
nothing).

`reprocess` is the important one: tuning `classes.json` geometry or a
post-processing step costs nothing, because the expensive part is already on
disk.

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

Override per run with `--provider` / `--model`, or set `ASSET_GEN_PROVIDER`.
All three accept `--ref` style conditioning; on OpenAI that switches the call to
`/images/edits`, the only route there that takes reference images.

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
