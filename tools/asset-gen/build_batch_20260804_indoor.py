"""Arm C, rebuilt: stop arguing with the light, state the SPACE.

The first attempt asked for "even overcast skylight from every direction" and
was wrong on the owner's own evidence. `skylight` and `overcast` are outdoor
words, so a prompt written to suppress light direction was simultaneously
telling the model it was outside -- and being outside is the whole fault. The
model was not choosing a bad light; it was imagining an unroofed structure and
then lighting it correctly for that.

So this arm does not describe lighting at all except to refuse the sky. It
describes the ROOM: sealed, underground, roofed, no opening. The lighting then
follows from the space, which is the direction the inference actually runs.

Seeds and geometry match arm C exactly, so every card here is the paired
counterpart of one already rendered under the skylight wording.
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
BASE = {
    "wall": "muted limestone dungeon wall masonry, broad fitted blocks, weathered mineral variation, quiet low-fantasy architecture, restrained ochre and cool slate",
    "floor": "worn dungeon floor pavement, broad fitted flagstones, scuffed mineral variation, quiet low-fantasy architecture, restrained ochre and cool slate",
}

# Names the enclosure first, because that is the thing being got wrong. The
# occlusion request stays -- the engine still never occludes a texture -- but
# every word that could imply sky is gone, and the refusals name the SCENE
# (sky, daylight, courtyard, ruin) rather than the lighting.
INDOOR = ("deep underground sealed chamber interior, fully enclosed room with a stone "
          "ceiling overhead, windowless, no opening to the outside, "
          "diffuse albedo with baked ambient occlusion, soft contact shadows in every "
          "joint and recess, deep crevices darker than raised faces, "
          "even enclosed ambient light with no direction, "
          "no sky, no daylight, no sunlight, no open air, no exterior, no courtyard, "
          "no roofless ruin, no light from above, no cast shadows")

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
            description = f"{trigger}, {BASE[surface]}, {INDOOR}" if trigger else f"{BASE[surface]}, {INDOOR}"
            spec = {
                "name": f"indoor_{map_name}_{model_key}_{lora_key}",
                "class": CLASS[surface],
                "provider": "forge-quality",
                "model": MODELS[model_key],
                "description": description,
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
print(f"{len(jobs)} jobs -> {out}   (~{len(jobs)*2} min)")
