"""Self-contained HTML reports for staged runs.

Numbers alone are not reviewable. A seam ratio says whether a texture wraps; it
cannot say whether the picture is the material that was asked for, and every
failure so far has been of the second kind -- a flawless tile of the wrong thing.
So a run gets a page: the tile, the tile repeated, the score, and the exact
prompt and settings that produced it, side by side for every variant.

Everything is inlined as base64 with no external CSS, script or font, so the file
can be opened from disk, mailed, or kept next to the art it documents. It renders
in light or dark to match whatever is reading it.
"""

import base64
import html
import io
import json
import os

from PIL import Image

from . import postprocess, raw_quality, staging


def _embed(image, scale=1):
    if scale != 1:
        image = image.resize((image.width * scale, image.height * scale), Image.NEAREST)
    buffer = io.BytesIO()
    image.convert("RGBA").save(buffer, format="PNG")
    return "data:image/png;base64," + base64.b64encode(buffer.getvalue()).decode("ascii")


CSS = """
:root { color-scheme: light dark;
  --bg:#fbfaf8; --fg:#1c1a17; --dim:#6b6560; --line:#e0dcd6; --card:#ffffff;
  --good:#2f7d4f; --warn:#a8761c; --bad:#b0392c; }
@media (prefers-color-scheme: dark) { :root {
  --bg:#17161a; --fg:#eae7e2; --dim:#9b948c; --line:#33302e; --card:#201e22; } }
* { box-sizing:border-box; }
body { margin:0; padding:2rem 1.25rem 4rem; background:var(--bg); color:var(--fg);
  font:15px/1.55 ui-sans-serif,system-ui,-apple-system,Segoe UI,sans-serif; }
main { max-width:1100px; margin:0 auto; }
h1 { font-size:1.5rem; margin:0 0 .25rem; letter-spacing:-.01em; }
h2 { font-size:1.05rem; margin:2.5rem 0 .5rem; padding-bottom:.4rem;
  border-bottom:1px solid var(--line); }
.sub { color:var(--dim); margin:0 0 2rem; }
.meta { color:var(--dim); font-size:.85rem; margin:.1rem 0 1rem; }
pre { background:var(--card); border:1px solid var(--line); border-radius:8px;
  padding:.7rem .85rem; overflow-x:auto; font-size:.8rem; white-space:pre-wrap;
  word-break:break-word; margin:.4rem 0 1rem; }
.grid { display:grid; gap:1rem; grid-template-columns:repeat(auto-fill,minmax(260px,1fr)); }
.card { background:var(--card); border:1px solid var(--line); border-radius:10px;
  padding:.85rem; }
.card.best { border-color:var(--good); box-shadow:0 0 0 1px var(--good); }
.card img { width:100%; height:auto; display:block; border-radius:6px;
  image-rendering:pixelated; background:#0000; }
.pair { display:grid; grid-template-columns:1fr 1fr; gap:.5rem; }
.trio { display:grid; grid-template-columns:repeat(3,1fr); gap:.5rem; }
.context { margin-top:.65rem; max-width:520px; }
.tag { display:inline-block; font-size:.72rem; padding:.1rem .45rem; border-radius:999px;
  border:1px solid var(--line); color:var(--dim); margin-right:.3rem; }
.scores { font:12px/1.5 ui-monospace,SFMono-Regular,Consolas,monospace; margin-top:.5rem; }
.good{color:var(--good)} .warn{color:var(--warn)} .bad{color:var(--bad)}
.label { font-size:.72rem; color:var(--dim); text-transform:uppercase;
  letter-spacing:.06em; margin:.5rem 0 .2rem; }
table { border-collapse:collapse; width:100%; font-size:.85rem; }
th,td { text-align:left; padding:.35rem .6rem; border-bottom:1px solid var(--line); }
th { color:var(--dim); font-weight:600; }
td.num { font-family:ui-monospace,Consolas,monospace; }
"""


def _verdict(value, good=2.0):
    if value is None:
        return '<span class="warn">unmeasurable</span>'
    css = "good" if value <= good else ("warn" if value <= good * 2 else "bad")
    return f'<span class="{css}">{value}</span>'


def _score_block(score):
    if not score:
        return '<div class="scores warn">not scored</div>'
    return ('<div class="scores">'
            f'wrap&nbsp;&nbsp; x {_verdict(score.get("x"))} &nbsp; y {_verdict(score.get("y"))}<br>'
            f'centre x {_verdict(score.get("centre_x"))} &nbsp; '
            f'y {_verdict(score.get("centre_y"))}</div>')


def _inpaint_base(run_path, manifest):
    source = (manifest.get("provider") or {}).get("inpaintSource") or ""
    try:
        source_run, source_index = source.rsplit("#", 1)
        source_index = int(source_index)
    except (ValueError, TypeError):
        return None, None
    if not source_run or os.path.basename(source_run) != source_run:
        return None, None
    source_path = os.path.join(os.path.dirname(run_path), source_run)
    try:
        source_manifest = staging.read_run_manifest(source_path)
    except (OSError, RuntimeError):
        return None, None
    row = next((item for item in source_manifest.get("variants") or []
                if item.get("index") == source_index), None)
    if not row:
        return None, None
    filename = row.get("file") or ""
    path = os.path.join(source_path, filename)
    if not filename or os.path.basename(filename) != filename or not os.path.isfile(path):
        return None, None
    return Image.open(path).convert("RGBA"), f"approved base — {source_run}#{source_index}"


def variant_card(run_path, variant, best=False, repeat=3, axes="xy",
                 base_image=None, base_label=None):
    path = os.path.join(run_path, variant["file"])
    tile = Image.open(path)
    score = variant.get("tileScore") or postprocess.tile_seam_score(tile, axes)
    sheet = postprocess.tiled_sheet(path, repeat, scale=1, axes=axes)
    raw_path = os.path.join(run_path, variant.get("raw", f"raw-{variant['index']}.png"))
    raw = Image.open(raw_path).convert("RGBA") if os.path.isfile(raw_path) else None
    context_name = variant.get("context")
    context_path = os.path.join(run_path, context_name) if context_name else ""
    context = (Image.open(context_path).convert("RGBA")
               if context_name and os.path.isfile(context_path) else None)
    # Re-score on every report run so the metric can be corrected without
    # leaving old manifests with stale verdicts.
    raw_score = raw and raw_quality.analyze(raw)
    raw_label = "raw source"
    if raw_score:
        raw_label += (f" — {raw_score['verdict']}, chroma {raw_score['highChromaRatio']}"
                      f", outliers {raw_score['chromaOutlierRatio']}")
    if raw_score:
        raw_label = (f"raw source — {raw_score['verdict']}, "
                     f"chroma {raw_score['highChromaRatio']}, "
                     f"outliers {raw_score['chromaOutlierRatio']}")
    return f"""
    <div class="card{' best' if best else ''}">
      <div class="trio">
        <div><div class="label">tile</div><img src="{_embed(tile, 3)}" alt=""></div>
        {f'<div><div class="label">{html.escape(base_label)}</div><img src="{_embed(base_image, 3)}" alt=""></div>' if base_image else ''}
        <div><div class="label">{repeat}x along {'horizontal' if axes == 'x' else 'both axes'}</div><img src="{_embed(sheet)}" alt=""></div>
        {f'<div><div class="label">{html.escape(raw_label)}</div><img src="{_embed(raw)}" alt=""></div>' if raw else ''}
      </div>
      {f'<div class="context"><div class="label">{html.escape(variant.get("contextLabel", "in-engine context"))}</div><img src="{_embed(context)}" alt=""></div>' if context else ''}
      {f'<div class="scores warn">context preview unavailable: {html.escape(variant.get("contextError"))}</div>' if variant.get("contextError") else ''}
      <div class="label">variant {variant['index']}{' &mdash; best' if best else ''}</div>
      {_score_block(score)}
    </div>"""


def image_cards(title, intro, cards):
    """A labelled grid of arbitrary images -- used by `audit` to SHOW a seam.

    A table saying an asset scores 14.2 is an assertion. The same asset laid out
    three by three is the evidence, and the two belong on one page.
    """
    body = []
    for card in cards:
        panes = "".join(
            f'<div><div class="label">{html.escape(label)}</div>'
            f'<img src="{_embed(image, scale)}" alt=""></div>'
            for label, image, scale in card["images"])
        body.append(f"""
        <div class="card">
          <div class="pair">{panes}</div>
          <div class="label">{html.escape(card['title'])}</div>
          {card.get('body', '')}
        </div>""")
    return f"""
    <h2>{html.escape(title)}</h2>
    <p class="meta">{intro}</p>
    <div class="grid">{''.join(body)}</div>"""


def run_section(run_path, manifest, rank=None):
    prov = manifest.get("provider", {})
    sampling = prov.get("sampling") or {}
    variants = manifest.get("variants", [])
    best_index = None
    if rank and variants:
        best_index = min(variants, key=rank).get("index")

    prompt_path = os.path.join(run_path, "prompt.txt")
    prompt_text = ""
    if os.path.isfile(prompt_path):
        with open(prompt_path, "r", encoding="utf-8") as handle:
            prompt_text = handle.read().strip()

    tags = [prov.get("id"), prov.get("model")]
    for key in ("steps", "cfgScale", "sampler", "seed"):
        if sampling.get(key) is not None:
            tags.append(f"{key} {sampling[key]}")
    if sampling.get("loras"):
        tags += [f"lora {l['name']}@{l.get('weight')}" for l in sampling["loras"]]
    if prov.get("heightControl"):
        tags.append("controlnet depth")
    if prov.get("heightControlWeight") is not None:
        tags.append(f"depth weight {prov['heightControlWeight']}")

    negative_prompt = sampling.get("negativePrompt")
    negative_block = (f'<div class="label">negative prompt as sent</div><pre>{html.escape(negative_prompt)}</pre>'
                      if negative_prompt else '')

    axes = manifest.get("tileAxes", "xy")
    base_image, base_label = _inpaint_base(run_path, manifest)
    cards = "\n".join(variant_card(run_path, v, v.get("index") == best_index,
                                   axes=axes, base_image=base_image,
                                   base_label=base_label)
                      for v in variants)
    return f"""
    <h2>{html.escape(str(manifest.get('name')))}
        <span class="meta">{html.escape(str(manifest.get('class')))}</span></h2>
    <div class="meta">{''.join(f'<span class="tag">{html.escape(str(t))}</span>'
                               for t in tags if t)}</div>
    <div class="label">prompt as sent</div>
    <pre>{html.escape(prompt_text)}</pre>
    {negative_block}
    <div class="grid">{cards}</div>"""


def write(path, title, subtitle, sections, preamble=""):
    document = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{html.escape(title)}</title><style>{CSS}</style></head>
<body><main>
<h1>{html.escape(title)}</h1>
<p class="sub">{subtitle}</p>
{preamble}
{''.join(sections)}
</main></body></html>"""
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(document)
    return path
