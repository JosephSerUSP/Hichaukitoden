"""Image-model clients for tools/asset-gen.

Four provider shapes, all returning raw PNG/JPEG bytes so the rest of the tool
never learns which service drew the pixels:

  gemini-image      Google generateContent with responseModalities [IMAGE, TEXT]
  openai-images     OpenAI /images/generations (b64_json)
  openai-chat-image OpenAI-compatible chat whose reply carries image content
                    parts (OpenRouter's image-capable chat models)
  sdapi             a LOCAL Stable Diffusion server (Forge/A1111 /sdapi/v1),
                    started by tools/asset-gen/forge.py

Reference images (style conditioning) are passed through where the provider
supports them; openai-images ignores them and the caller is warned.

API keys come from the environment only -- never from a config file, never from
a command-line flag that would land in shell history. A provider marked
`"local": true` needs no key at all.
"""

import base64
import io
import json
import os
import time

import requests
from PIL import Image


class ProviderError(RuntimeError):
    pass


def _b64_png(path):
    with open(path, "rb") as handle:
        return base64.b64encode(handle.read()).decode("ascii")


def _retry(fn, max_retries, label):
    last = None
    for attempt in range(1, max_retries + 1):
        try:
            return fn()
        except ProviderError as err:
            last = err
            if not err.args or not getattr(err, "retryable", False):
                raise
            if attempt < max_retries:
                print(f"  [{label}] {err} -- retry {attempt}/{max_retries - 1}")
                time.sleep(attempt * 5)
        except requests.RequestException as err:
            last = err
            if attempt < max_retries:
                print(f"  [{label}] network error: {err} -- retry {attempt}/{max_retries - 1}")
                time.sleep(attempt * 5)
    raise ProviderError(f"{label} failed after {max_retries} attempts: {last}")


def _http(err_prefix, response):
    """Raise a ProviderError, flagged retryable for 429/5xx."""
    err = ProviderError(f"{err_prefix} HTTP {response.status_code}: {response.text[:400]}")
    err.retryable = response.status_code == 429 or response.status_code >= 500
    return err


# ---------------------------------------------------------------------------
# Google Gemini image generation
# ---------------------------------------------------------------------------
def _gemini_image(api_key, model, prompt, refs, size, timeout):
    parts = [{"text": prompt}]
    for ref in refs:
        parts.append({"inlineData": {"mimeType": "image/png", "data": _b64_png(ref)}})

    body = {
        "contents": [{"parts": parts}],
        "generationConfig": {"responseModalities": ["IMAGE", "TEXT"]},
    }
    url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"
    res = requests.post(
        url,
        json=body,
        # Key in a header, not the query string, so it stays out of logs/proxies.
        headers={"Content-Type": "application/json", "x-goog-api-key": api_key},
        timeout=timeout,
    )
    if not res.ok:
        raise _http("gemini", res)

    data = res.json()
    notes = []
    for candidate in data.get("candidates", []):
        for part in candidate.get("content", {}).get("parts", []):
            inline = part.get("inlineData") or part.get("inline_data")
            if inline and inline.get("data"):
                return base64.b64decode(inline["data"])
            if part.get("text"):
                notes.append(part["text"][:200])
    raise ProviderError(
        "gemini returned no image" + (f" (model said: {' | '.join(notes)})" if notes else "")
    )


# ---------------------------------------------------------------------------
# OpenAI /images/generations
# ---------------------------------------------------------------------------
def _openai_images(api_key, base_url, model, prompt, refs, size, timeout, transparent=False,
                   quality=None):
    """OpenAI images. gpt-image-1 can cut its own background and take references.

    `background: transparent` gives a real alpha channel, which beats keying a
    magenta backdrop after the fact -- so for transparent classes we ask for it
    and let key_background become a no-op. Reference images go through
    /images/edits, the only OpenAI image route that accepts them.
    """
    auth = {"Authorization": f"Bearer {api_key}"}
    fields = {"model": model, "prompt": prompt, "size": size, "n": 1}
    if quality:
        fields["quality"] = quality
    if transparent:
        fields["background"] = "transparent"
        fields["output_format"] = "png"

    if refs:
        # multipart: prompt as form fields, each reference as an image[] part.
        handles = [open(r, "rb") for r in refs]
        try:
            files = [("image[]", (os.path.basename(r), h, "image/png"))
                     for r, h in zip(refs, handles)]
            res = requests.post(f"{base_url}/images/edits", data={
                k: str(v) for k, v in fields.items()
            }, files=files, headers=auth, timeout=timeout)
        finally:
            for handle in handles:
                handle.close()
    else:
        res = requests.post(
            f"{base_url}/images/generations", json=fields,
            headers=dict(auth, **{"Content-Type": "application/json"}), timeout=timeout,
        )
    if not res.ok:
        raise _http("openai-images", res)
    payload = res.json().get("data") or []
    for entry in payload:
        if entry.get("b64_json"):
            return base64.b64decode(entry["b64_json"])
        if entry.get("url"):
            fetched = requests.get(entry["url"], timeout=timeout)
            if fetched.ok:
                return fetched.content
    raise ProviderError("openai-images returned no image data")


# ---------------------------------------------------------------------------
# OpenAI-compatible chat with image output (OpenRouter image models)
# ---------------------------------------------------------------------------
def _openai_chat_image(api_key, base_url, model, prompt, refs, size, timeout):
    content = [{"type": "text", "text": prompt}]
    for ref in refs:
        content.append({
            "type": "image_url",
            "image_url": {"url": "data:image/png;base64," + _b64_png(ref)},
        })
    res = requests.post(
        f"{base_url}/chat/completions",
        json={"model": model, "messages": [{"role": "user", "content": content}],
              "modalities": ["image", "text"]},
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {api_key}"},
        timeout=timeout,
    )
    if not res.ok:
        raise _http("openai-chat-image", res)

    message = ((res.json().get("choices") or [{}])[0].get("message")) or {}
    for image in message.get("images") or []:
        url = (image.get("image_url") or {}).get("url", "")
        if url.startswith("data:"):
            return base64.b64decode(url.split(",", 1)[1])
    body = message.get("content")
    if isinstance(body, list):
        for part in body:
            url = (part.get("image_url") or {}).get("url", "")
            if url.startswith("data:"):
                return base64.b64decode(url.split(",", 1)[1])
    raise ProviderError("openai-chat-image returned no image part")


# ---------------------------------------------------------------------------
# A local Stable Diffusion server (Forge / A1111 /sdapi/v1/txt2img)
# ---------------------------------------------------------------------------
def _sdapi(base, model, prompt, refs, size, timeout, options, control=None):
    """Local txt2img. `options` is the provider's `sampling` block from config.

    `tiling` is the one that matters here and has no cloud equivalent: it swaps
    the model's convolutions to circular padding, so the result wraps instead of
    merely looking repetitive. Post-hoc seam blending cannot produce this -- it
    only hides the discontinuity in a band along the edge.

    Reference images become an img2img-style prompt only in the sense that
    ControlNet takes them; a plain `refs` list is not supported and is reported
    rather than silently ignored, since a caller passing style refs would
    otherwise think they had been honoured.
    """
    width, height = (int(part) for part in str(size).lower().split("x"))
    # LoRAs ride in the prompt as <lora:name:weight>, which is how this API takes
    # them. Declared as data in config.json so a style is a config edit.
    for lora in options.get("loras") or []:
        prompt = f"{prompt} <lora:{lora['name']}:{lora.get('weight', 0.8)}>"
    body = {
        "prompt": prompt,
        "negative_prompt": options.get("negativePrompt", ""),
        "width": width,
        "height": height,
        "steps": options.get("steps", 20),
        "cfg_scale": options.get("cfgScale", 7.0),
        "sampler_name": options.get("sampler", "Euler a"),
        "scheduler": options.get("scheduler", "Automatic"),
        "seed": options.get("seed", -1),
        "batch_size": 1,
        "n_iter": 1,
        # Seamless output. The whole reason a texture pipeline wants a local model.
        "tiling": bool(options.get("tiling", False)),
        "override_settings": {"sd_model_checkpoint": model},
        "override_settings_restore_afterwards": False,
    }
    if options.get("clipSkip"):
        body["override_settings"]["CLIP_stop_at_last_layers"] = options["clipSkip"]
    if control:
        body["alwayson_scripts"] = {"controlnet": {"args": [control]}}

    res = requests.post(f"{base}/sdapi/v1/txt2img", json=body, timeout=timeout)
    if not res.ok:
        raise _http("sdapi", res)
    images = res.json().get("images") or []
    if not images:
        raise ProviderError("sdapi returned no image")
    first_pass = base64.b64decode(images[0])

    if options.get("tiling"):
        # `tiling` above is sent for completeness and does nothing on this
        # backend; the wrap is produced by the second pass. See _offset_inpaint.
        return _offset_inpaint(base, model, prompt, size, timeout, options,
                               first_pass, control)
    return first_pass


def _png_bytes(image):
    buffer = io.BytesIO()
    image.save(buffer, format="PNG")
    return buffer.getvalue()


def _roll_half(image):
    """Shift an image by half its size both ways, wrapping around.

    Four quadrants swapped diagonally; PIL has no roll and this is one.
    """
    width, height = image.size
    half_x, half_y = width // 2, height // 2
    rolled = Image.new(image.mode, (width, height))
    rolled.paste(image.crop((half_x, half_y, width, height)), (0, 0))
    rolled.paste(image.crop((0, half_y, half_x, height)), (width - half_x, 0))
    rolled.paste(image.crop((half_x, 0, width, half_y)), (0, height - half_y))
    rolled.paste(image.crop((0, 0, half_x, half_y)), (width - half_x, height - half_y))
    return rolled


def _offset_inpaint(base, model, prompt, size, timeout, options, first_pass, control=None):
    """Make a texture seamless by construction, in two passes.

    THE FLAG DOES NOT WORK. Forge accepts `tiling` in the payload and silently
    ignores it -- modules_forge/utils.py:apply_circular_forge has its body
    commented out and prints "Tiling is currently under maintenance". Measured:
    identical seeds with tiling on and off produce different pictures with
    equally bad seams, so the argument reaches the sampler and does nothing
    useful. Nothing warns you; the images simply do not tile.

    So the wrap is built here instead, by the standard offset trick:

      1. take the picture, and ROLL it by half its width and height. Whatever
         was at the four borders is now a cross through the middle -- and the
         new border is what used to be interior, which by definition already
         continues into itself.
      2. inpaint that cross, and only that cross. The outer edge is masked off
         and never repainted, so the wrap the roll created survives untouched.

    The result tiles exactly, whatever the model does with its convolutions.
    The cost is one extra pass -- seconds, on an LCM checkpoint.
    """
    image = Image.open(io.BytesIO(first_pass)).convert("RGB")
    width, height = image.size
    half_x, half_y = width // 2, height // 2
    rolled = _roll_half(image)

    # A white cross over the two joins the roll created: a vertical stripe down
    # the new middle, and a horizontal one across it. Everything else stays
    # black and is never repainted, which is what preserves the wrap.
    band = max(8, int(width * options.get("seamBand", 0.16)))
    mask = Image.new("L", (width, height), 0)
    mask.paste(Image.new("L", (band, height), 255), (half_x - band // 2, 0))
    mask.paste(Image.new("L", (width, band), 255), (0, half_y - band // 2))

    body = {
        "init_images": [base64.b64encode(_png_bytes(rolled)).decode("ascii")],
        "mask": base64.b64encode(_png_bytes(mask)).decode("ascii"),
        "prompt": prompt,
        "negative_prompt": options.get("negativePrompt", ""),
        "width": width,
        "height": height,
        # Enough steps to actually rebuild the band. An LCM checkpoint runs the
        # first pass in six, but six steps at full denoise cannot close a hard
        # join, and the result is a texture that wraps perfectly with a visible
        # line down its middle -- measured at 8x the texture's typical contrast.
        "steps": options.get("seamSteps", max(options.get("steps", 20), 12)),
        "cfg_scale": options.get("cfgScale", 7.0),
        "sampler_name": options.get("sampler", "Euler a"),
        "seed": options.get("seed", -1),
        # Full denoise: anything less keeps part of the discontinuity it is
        # there to destroy.
        "denoising_strength": options.get("seamDenoise", 1.0),
        "mask_blur": options.get("seamBlur", 8),
        "inpainting_fill": 1,          # keep the original pixels as the start
        "inpaint_full_res": False,     # repaint in place, at the real resolution
        "override_settings": {"sd_model_checkpoint": model},
        "override_settings_restore_afterwards": False,
    }
    if control:
        # The control map has to travel with the picture. Conditioning a ROLLED
        # image against an unrolled depth map asks the model to paint the seam
        # to match structure that is now half a texture away, and it obliges --
        # measured as the centre join getting five times worse.
        rolled_control = _roll_half(
            Image.open(io.BytesIO(base64.b64decode(control["image"]))))
        body["alwayson_scripts"] = {"controlnet": {"args": [
            dict(control, image=base64.b64encode(_png_bytes(rolled_control)).decode("ascii"))
        ]}}

    res = requests.post(f"{base}/sdapi/v1/img2img", json=body, timeout=timeout)
    if not res.ok:
        raise _http("sdapi img2img", res)
    images = res.json().get("images") or []
    if not images:
        raise ProviderError("sdapi img2img returned no image")
    painted = Image.open(io.BytesIO(base64.b64decode(images[0]))).convert("RGB")

    # Restore a thin outer ring from the rolled image. Inpainting is supposed to
    # leave unmasked pixels alone, but the pass round-trips the whole picture
    # through the VAE and composites the original back through a BLURRED mask,
    # so the border comes out slightly altered -- measured as a seam ratio of
    # 1.6-3.1 where the roll guarantees 1.0. These pixels came from the middle of
    # the original image and are wrap-exact by construction; taking them back
    # costs nothing and makes the guarantee absolute.
    ring = max(4, width // 64)
    for box in ((0, 0, width, ring), (0, height - ring, width, height),
                (0, 0, ring, height), (width - ring, 0, width, height)):
        painted.paste(rolled.crop(box), (box[0], box[1]))
    return _png_bytes(painted)


def controlnet_depth(base, height_map_path, model, weight=0.6):
    """A ControlNet unit conditioning generation on an authored height map.

    The map is passed as the control image with no preprocessor: it IS the depth
    hint. Running a depth ESTIMATOR over it would be the mistake -- estimation on
    this project's art was measured useless, and the whole point here is that the
    real height field already exists.

    The model name is resolved against the server's own list, because the API
    wants it with the checkpoint hash appended ("...depth [cfd03158]") and
    quietly does nothing for a name it does not recognise. Measured: a unit
    naming the model without its hash changed the picture -- so it looked like
    it worked -- while leaving its correlation with the height map at zero.
    """
    resolved = model
    try:
        listing = requests.get(f"{base}/controlnet/model_list", timeout=10).json()
        match = next((m for m in listing.get("model_list", []) if m.startswith(model)), None)
        if match:
            resolved = match
        else:
            print(f"  warning: ControlNet model '{model}' is not installed; "
                  f"conditioning will do nothing. Have: {listing.get('model_list')}")
    except (requests.RequestException, ValueError) as err:
        print(f"  warning: could not resolve the ControlNet model list ({err})")

    return {
        "enabled": True,
        "module": "None",
        "model": resolved,
        "weight": weight,
        "image": _b64_png(height_map_path),
        "resize_mode": "Just Resize",
        "control_mode": "Balanced",
        "pixel_perfect": True,
    }


# ---------------------------------------------------------------------------
def generate(provider, prompt, refs=(), size="1024x1024", timeout=180, max_retries=3,
             transparent=False, quality=None, sampling=None, control=None):
    """provider is a config.json providers[] entry with an 'id' key merged in."""
    key = ""
    if not provider.get("local"):
        key = os.environ.get(provider["apiKeyEnv"], "").strip()
        if not key:
            raise ProviderError(
                f"{provider['label']}: set {provider['apiKeyEnv']} in the environment"
            )

    kind = provider["type"]
    model = provider["model"]
    base = provider.get("baseUrl", "")
    refs = list(refs or [])

    if kind == "gemini-image":
        call = lambda: _gemini_image(key, model, prompt, refs, size, timeout)
    elif kind == "openai-images":
        call = lambda: _openai_images(key, base, model, prompt, refs, size, timeout,
                                      transparent, quality)
    elif kind == "openai-chat-image":
        call = lambda: _openai_chat_image(key, base, model, prompt, refs, size, timeout)
    elif kind == "sdapi":
        options = dict(provider.get("sampling") or {})
        options.update(sampling or {})
        if refs:
            print("  note: sdapi ignores --ref; use --height for ControlNet conditioning")
        call = lambda: _sdapi(base, model, prompt, refs, size, timeout, options, control)
    else:
        raise ProviderError(f"unknown provider type '{kind}'")

    return _retry(call, max_retries, provider["id"])
