"""Image-model clients for tools/asset-gen.

Three provider shapes, all returning raw PNG/JPEG bytes so the rest of the tool
never learns which service drew the pixels:

  gemini-image      Google generateContent with responseModalities [IMAGE, TEXT]
  openai-images     OpenAI /images/generations (b64_json)
  openai-chat-image OpenAI-compatible chat whose reply carries image content
                    parts (OpenRouter's image-capable chat models)

Reference images (style conditioning) are passed through where the provider
supports them; openai-images ignores them and the caller is warned.

API keys come from the environment only -- never from a config file, never from
a command-line flag that would land in shell history.
"""

import base64
import json
import os
import time

import requests


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
def generate(provider, prompt, refs=(), size="1024x1024", timeout=180, max_retries=3,
             transparent=False, quality=None):
    """provider is a config.json providers[] entry with an 'id' key merged in."""
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
    else:
        raise ProviderError(f"unknown provider type '{kind}'")

    return _retry(call, max_retries, provider["id"])
