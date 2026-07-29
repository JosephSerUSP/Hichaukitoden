"""Asset-class resolution and prompt assembly for tools/asset-gen.

classes.json is the registry; nothing here hardcodes a class. Geometry is
resolved (including the animation class's computed sheet width), filenames are
built from the class's pattern including the engine's [key=value] tokens, and
prompts come from prompts/<promptFile> with {{TOKEN}} substitution -- the same
templating convention tools/campaign-gen uses.
"""

import json
import os
import re

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", "..", ".."))
TOOL_DIR = os.path.join(ROOT, "tools", "asset-gen")


def load(name):
    with open(os.path.join(TOOL_DIR, name), "r", encoding="utf-8") as handle:
        return json.load(handle)


def registry():
    return load("classes.json")


def resolve(class_id, opts):
    """Build the full working context for one generation: geometry, prompt, paths.

    opts may override cell size and frame count (the animation class is authored
    per-effect), and those overrides flow into both the geometry and the
    filename tokens, so the sheet the engine reads always matches its name.
    """
    reg = registry()
    class_def = reg["classes"].get(class_id)
    if not class_def:
        known = ", ".join(sorted(reg["classes"]))
        raise KeyError(f"unknown asset class '{class_id}'. Known: {known}")

    geom = dict(class_def["geometry"])
    cell = list(opts.get("cell") or geom["cell"])
    frames = int(opts.get("frames") or geom["frames"])

    size = geom.get("size")
    if not size:
        # Sheets whose extent depends on the frame count (particle strips).
        size = [cell[0] * frames, cell[1]]
    size = list(size)

    request = class_def.get("request", {})
    grid_hint = list(opts.get("grid") or request.get("gridHint") or [1, 1])

    return {
        "id": class_id,
        "classDef": class_def,
        "styleBible": reg["styleBible"],
        "size": size,
        "cell": cell,
        "frames": frames,
        "gridHint": grid_hint,
        "transparent": bool(geom.get("transparent")),
        "requestSize": opts.get("requestSize") or request.get("size", "1024x1024"),
        "dir": class_def["dir"],
    }


_TOKEN_GROUP = re.compile(r"\[[^\]]*\{[^}]+\}[^\]]*\]")


def filename(ctx, name, tokens=None):
    """Render the class's filename pattern for `name`.

    {Name} capitalises, {name} lowercases; [key={token}] groups whose token has
    no value are dropped whole, so `--fps 0` yields `Kappa.png` rather than a
    filename carrying an empty bracket the engine would then try to parse.
    """
    values = dict(ctx["classDef"].get("tokenDefaults") or {})
    values.update({k: v for k, v in (tokens or {}).items() if v not in (None, "")})
    values.update({"cw": ctx["cell"][0], "ch": ctx["cell"][1], "frames": ctx["frames"]})

    pattern = ctx["classDef"]["filename"]
    pattern = _TOKEN_GROUP.sub(
        lambda m: "" if any(
            key not in values for key in re.findall(r"\{(\w+)\}", m.group(0))
        ) else m.group(0),
        pattern,
    )
    safe = re.sub(r"[^\w\-]", "_", str(name)).strip("_") or "unnamed"
    values["Name"] = safe[:1].upper() + safe[1:]
    values["name"] = safe.lower()
    return pattern.format(**values)


def prompt(ctx, name, description, extra=""):
    path = os.path.join(TOOL_DIR, "prompts", ctx["classDef"]["promptFile"])
    with open(path, "r", encoding="utf-8") as handle:
        template = handle.read()

    grid = (f"{ctx['gridHint'][0]} columns x {ctx['gridHint'][1]} rows"
            if ctx["gridHint"] != [1, 1] else "a single image, no grid")
    replacements = {
        "STYLE_BIBLE": ctx["styleBible"],
        "NAME": str(name),
        "DESCRIPTION": description or "",
        "GRID": grid,
        "FRAMES": str(ctx["frames"]),
        "CELL": f"{ctx['cell'][0]}x{ctx['cell'][1]}",
        "FINAL_SIZE": f"{ctx['size'][0]}x{ctx['size'][1]}",
        "EXPRESSIONS": ", ".join(ctx["classDef"].get("expressions", [])),
        "BACKGROUND": (
            "a perfectly flat pure magenta (#FF00FF) background with no shadow, "
            "gradient or vignette on it -- it will be keyed out to transparency"
            if ctx["transparent"] else
            "a fully painted background; the image is opaque edge to edge"
        ),
        "EXTRA": extra or "",
    }
    for key, value in replacements.items():
        template = template.replace("{{" + key + "}}", value)
    return template.strip()
