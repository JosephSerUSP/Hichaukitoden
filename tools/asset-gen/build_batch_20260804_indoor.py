"""Arm C, rebuilt twice, and the second rebuild is the one that matters.

Attempt 1 asked for "even overcast skylight from every direction". `skylight`
and `overcast` are outdoor words, so a wording written to suppress light
direction was simultaneously telling the model it was outside -- and being
outside is the fault. The model was not choosing a bad light; it had imagined an
unroofed structure and was lighting it correctly for that.

Attempt 2 named the room but did it in prose, and in the POSITIVE prompt:
"fully enclosed room with a stone ceiling overhead, windowless, no opening to
the outside". Two things wrong, both from the owner.

  Negation does not exist. CLIP has no "no". "no opening to the outside" is
  read as roughly {opening, outside} -- five tokens arguing FOR the thing they
  were written to forbid. Every refusal now lives in the negative prompt, which
  is the only place refusal is real, via the new --negative-extra.

  Prose does not survive. This is SD1.5, not a multimodal model that parses a
  sentence. It sees a bag of weighted tokens, so a five-word clause expressing
  one concept is five diluted concepts. Short noun-phrase tags, most important
  first, is the form these checkpoints were trained on.

Not literal booru tags: those are the vocabulary of anime character models, and
the checkpoints carrying this project (artius, newera, ohmen, homosimile) are
photo and illustration merges that never saw `1girl, solo`. The useful half of
the idea is the SHAPE -- short, comma-separated, concrete -- not the danbooru
dictionary. So: tag-shaped, in this project's own material vocabulary.

Seeds and geometry still match arm C exactly, so each card is the paired
counterpart of one rendered under the skylight wording.
"""

import json

MAPS = "assets/geometry/1_blender_depth_maps"

MODELS = {
    "ohmen": "ohmenOrigins_ohmenOriginsV3",
    "homosimile": "homosimile_v40",
}
LORAS = {
    "diffuse": ("DiffuseTexture_v11", 0.70, "diffuse texture"),
    "control": (None, None, ""),
}

# Tag-shaped: short, concrete, most important first. No clauses, no negation,
# nothing that needs to be parsed as a sentence to mean anything.
BASE = {
    "wall": "dungeon wall masonry, fitted limestone blocks, weathered stone, "
            "ochre and slate, low fantasy architecture",
    "floor": "dungeon floor pavement, fitted flagstones, worn stone, "
             "ochre and slate, low fantasy architecture",
}

# The room, as tags. `underground` and `crypt` do the work the prose clause
# "no opening to the outside" was failing to do -- single tokens the model has a
# strong prior for, each carrying enclosure with it.
INDOOR = "underground, subterranean, crypt interior, enclosed chamber, windowless, cave depths"

# The lighting, positively stated. Only what SHOULD be there; everything that
# should not is in the negative below.
LIGHT = ("ambient occlusion, soft contact shadows, dark crevices, "
         "even ambient light, diffuse albedo, flat lighting")

# Where the refusals actually work. Named for the SCENE, because the fault is a
# scene error: the model builds an unroofed structure and then lights it
# correctly for the sky it invented.
NEGATIVE_EXTRA = ("sky, daylight, sunlight, sunbeam, open air, outdoors, exterior, "
                  "courtyard, roofless, ruins, overgrown, clouds, horizon, "
                  "light from above, top lighting, cast shadow, harsh shadow")

CLASS = {"wall": "wallPiece", "floor": "texturePiece"}
SURFACE = {r["preset"]: r["surface"]
           for r in json.load(open(f"{MAPS}/manifest.json"))["maps"]}
ORDER = sorted(SURFACE)

jobs = []
for map_name in ("wall_pilasters", "floor_flagstones"):
    surface = SURFACE[map_name]
    for model_key in ("ohmen", "homosimile"):
        for lora_key in ("diffuse", "control"):
            lora, weight, trigger = LORAS[lora_key]
            parts = [p for p in (trigger, INDOOR, BASE[surface], LIGHT) if p]
            spec = {
                "name": f"indoor_{map_name}_{model_key}_{lora_key}",
                "class": CLASS[surface],
                "provider": "forge-quality",
                "model": MODELS[model_key],
                "description": ", ".join(parts),
                "negativeExtra": NEGATIVE_EXTRA,
                "height": f"{MAPS}/{map_name}.png",
                "depthWeight": 0.60,
                "variants": 2,
                "steps": 20,
                "cfg": 6.5,
                # Identical to the strict_ card it answers, so any difference is
                # the wording and not a different roll.
                "seed": 940000 + ORDER.index(map_name) * 100,
                "requestSize": "256x256",
            }
            if lora:
                spec["loras"] = [{"name": lora, "weight": weight}]
            jobs.append(spec)

jobs.sort(key=lambda j: (j["model"], j.get("loras", [{}])[0].get("name", "")))
out = "tools/asset-gen/out/batch-2026-08-04-indoor-jobs.json"
json.dump(jobs, open(out, "w", encoding="utf-8"), indent=1)
print(f"{len(jobs)} jobs -> {out}   (~{len(jobs) * 2} min)")
print("\npositive:", jobs[0]["description"])
print("\nnegative extra:", jobs[0]["negativeExtra"])
