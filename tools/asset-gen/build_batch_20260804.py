"""Build the 04.08 batch: four arms, each answering a question the ratings asked.

Every arm exists because 423 owner judgements pointed at it, and nothing here
re-tests something those judgements already settled. Dropped outright, with the
evidence: depth 0.35 (1.38 stars over n=56), perfectWorld (2.34), SD1.5 base
(2.10), Ogre_Battle_SNES64 (2.15, worst measured dead-margin rate), and every
one-off checkpoint that scored 1.00-2.00 on n<=2.
"""

import json

MAPS = "assets/geometry/1_blender_depth_maps"

# The four checkpoints your ratings actually support, best first.
MODELS = {
    "artius":     "artius15_v20VAE",                          # 3.75 bare
    "newera":     "newERANewEstheticRetro_retroV60VAE",        # 4.00 w/ DiffuseTexture
    "mature":     "maturemalemix_v13",                         # 3.81 w/ DiffuseTexture
    "ohmen":      "ohmenOrigins_ohmenOriginsV3",               # 3.02 overall best
    "homosimile": "homosimile_v40",                            # 2.82
}

# A LoRA is inert unless its trained trigger appears in the prompt, so the
# trigger travels WITH the LoRA rather than being remembered at the call site.
LORAS = {
    "diffuse": ("DiffuseTexture_v11", 0.70, "diffuse texture"),
    "quake":   ("Quake_Texture_v1",   0.70, "texture, quake, old school"),
    "wowtex":  ("SXZ_WowTexture_v2",  0.70, "wowtexture of"),
    "control": (None, None, ""),
}

BASE = {
    "wall":    "muted limestone dungeon wall masonry, broad fitted blocks, weathered mineral variation, quiet low-fantasy architecture, restrained ochre and cool slate",
    "floor":   "worn dungeon floor pavement, broad fitted flagstones, scuffed mineral variation, quiet low-fantasy architecture, restrained ochre and cool slate",
    "ceiling": "ancient dungeon ceiling masonry seen from below, broad fitted stone courses, soot-stained mineral variation, quiet low-fantasy architecture, restrained ochre and cool slate",
}

# The vocabulary that won the earlier A/B: occlusion baked in, direct light refused.
AO = ("diffuse albedo with baked ambient occlusion, soft contact shadows in every joint "
      "and recess, gentle self-shadowing, deep crevices darker than raised faces, "
      "ambient fill only, no directional light, no cast shadows")

# Arm C's challenger. `harsh` is the single most common complaint on record (75
# of them), which says the ao vocabulary asks for occlusion but never actually
# forbids a light DIRECTION -- it only declines to request one. This states the
# refusal positively and describes the lighting that should be there instead.
AO_STRICT = ("diffuse albedo with baked ambient occlusion, soft contact shadows in every "
             "joint and recess, deep crevices darker than raised faces, lit only by even "
             "overcast skylight from every direction at once, perfectly uniform illumination, "
             "no sun, no torch, no lamp, no single light source, no light direction, "
             "no cast shadows, no highlights, no bright side and dark side")

CLASS = {"wall": "wallPiece", "floor": "texturePiece", "ceiling": "texturePiece"}
SURFACE = {}
for record in json.load(open(f"{MAPS}/manifest.json"))["maps"]:
    SURFACE[record["preset"]] = record["surface"]


def job(name, model_key, lora_key, map_name, depth=0.60, suffix=AO, weight=None, cfg=6.5):
    surface = SURFACE[map_name]
    lora, default_weight, trigger = LORAS[lora_key]
    description = f"{trigger}, {BASE[surface]}, {suffix}" if trigger else f"{BASE[surface]}, {suffix}"
    spec = {
        "name": name,
        "class": CLASS[surface],
        "provider": "forge-quality",
        "model": MODELS[model_key],
        "description": description,
        "height": f"{MAPS}/{map_name}.png",
        "depthWeight": depth,
        "variants": 2,
        "steps": 20,
        "cfg": cfg,
        # Held constant per geometry so a difference between two cards is the
        # factor under test and not a different roll of the dice.
        "seed": 940000 + (sorted(SURFACE).index(map_name) * 100),
        "requestSize": "256x256",
    }
    if lora:
        spec["loras"] = [{"name": lora, "weight": default_weight if weight is None else weight}]
    return spec


jobs = []

# ARM A -- the head-to-head the whole batch is for. One texture LoRA has beaten
# every game-aesthetic LoRA on record; two more just arrived. Four priors x four
# LoRAs x three geometries, so a winner has to win on more than one surface.
for map_name in ("wall_pilasters", "wall_rubble", "floor_flagstones"):
    for model_key in ("artius", "newera", "mature", "ohmen"):
        for lora_key in ("diffuse", "quake", "wowtex", "control"):
            jobs.append(job(f"tex_{map_name}_{model_key}_{lora_key}", model_key, lora_key, map_name))

# ARM B -- the cell that has never existed. Depth 0.85 beat 0.60 (3.04 vs 2.72)
# but was never once rendered WITH the best LoRA, so the two strongest knobs on
# record have never been in the same picture.
for map_name in ("wall_rubble", "floor_flagstones"):
    for model_key in ("newera", "mature"):
        for lora_key in ("diffuse", "quake"):
            jobs.append(job(f"deep_{map_name}_{model_key}_{lora_key}_d85",
                            model_key, lora_key, map_name, depth=0.85))

# ARM C -- the harsh-light fix, paired by seed against arm A's `ao` cards on the
# two checkpoints that produce the most harsh tags (ohmen 25, homosimile 26).
for map_name in ("wall_pilasters", "floor_flagstones"):
    for model_key in ("ohmen", "homosimile"):
        for lora_key in ("diffuse", "control"):
            jobs.append(job(f"strict_{map_name}_{model_key}_{lora_key}",
                            model_key, lora_key, map_name, suffix=AO_STRICT))

# ARM D -- how much texture prior is too much. artius alone scored 3.75 and
# artius + DiffuseTexture@0.7 scored 3.25 with burned x3, so the stack is
# over-cooking. Walk the weight down, and drop CFG on the two burned cells.
for map_name in ("wall_rubble", "ceiling_coffers"):
    for weight in (0.25, 0.45):
        jobs.append(job(f"stack_{map_name}_artius_diffuse_w{int(weight*100)}",
                        "artius", "diffuse", map_name, weight=weight))
    jobs.append(job(f"stack_{map_name}_artius_control_cfg55",
                    "artius", "control", map_name, cfg=5.5))

# Checkpoint switching costs real time on a 4 GB card, so group by model rather
# than letting the arms interleave and reload the same weights a dozen times.
jobs.sort(key=lambda j: (j["model"], j.get("loras", [{}])[0].get("name", "")))

out = "tools/asset-gen/out/batch-2026-08-04-jobs.json"
json.dump(jobs, open(out, "w", encoding="utf-8"), indent=1)
print(f"{len(jobs)} jobs -> {out}")
print(f"  ~{len(jobs) * 2 / 60:.1f}h at the measured ~2 min/job (2 variants, 256px, 20 steps)")
from collections import Counter
print("  by arm:  ", dict(Counter(j["name"].split("_")[0] for j in jobs)))
print("  by model:", dict(Counter(j["model"][:18] for j in jobs)))
