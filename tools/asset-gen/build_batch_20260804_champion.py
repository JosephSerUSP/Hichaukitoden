"""The champion recipe, held fixed, with exactly one variable moved per arm.

`depth_wall_pilasters_ohmen_followup` averaged 5.33 stars across three variants
-- the highest any run has scored. Nothing else on 04.08 came close, and the two
arms that scored WORST that day (indoor_ at 2.00) differed from it in three ways
at once, so nothing was learned from them. The confound was request size: the
champion asked for 512x512, the indoor cards asked for 256x256. Every card here
is 512.

The recipe, verbatim from that manifest: ohmenOrigins V3, no LoRA, depth 0.60,
26 steps, cfg 7.0, 512x512, and the material line below with the class template's
own ambient-occlusion block appended. The refusals stay where the champion had
them (the shared negative prompt); only arm E adds any, and it adds them alone
so the effect is readable.

The arms answer, in order, the four things the ratings actually say:

  A  The owner's one complaint about the champion -- "it's weird how they imply
     geometry farther beyond what the heightmap suggests, which breaks the
     illusion up close". That is the albedo painting relief the height map does
     not have, so the fix is to make the depth guide louder. Overall, 0.85 rates
     higher than 0.60 (3.52 vs 3.00 across 896 variants), but the champion is a
     0.60 card, so the ladder is run at the champion's own seed and 1.0 is
     included to find where obedience turns into flatness.

  B  The champion prompt has only ever been asked for pilasters. Floors are the
     weak half of the corpus (floor_flagstones: seam 2.23, repeat x24) and have
     never seen this wording. ceiling_coffers (4.14) and wall_eroded (4.36) are
     the best-rated maps on the board and deserve a champion-recipe card.

  C  abyssorangemix2 sits at 4.20 stars -- the highest of any checkpoint -- on
     five variants. That is not a result, it is a hint, and it costs four cards
     to turn into one. newERA is the established number two and has never been
     run against the champion recipe head-on.

  D  The three texture-trained LoRAs top the LoRA table (Quake 3.69, WowTexture
     3.50, DiffuseTexture 3.47) but every one of those cards was generated at
     256 with the older wording. They also carry the worst seam figures on the
     board (1.55 / 1.49 / 1.32), so this arm is as much a seam test as a style
     test.

  E  Two rubble cards drew the note "outdoors" from the owner. The refusals that
     were meant to fix that were introduced in the same batch that also dropped
     to 256, so they have never been evaluated on their own.
"""

import json

MAPS = "assets/geometry/1_blender_depth_maps"

OHMEN = "ohmenOrigins_ohmenOriginsV3"

# Material lines only. The class tag template appends the shared block --
# orthographic albedo, baked AO, contact shadows, ambient fill -- so it must not
# be repeated here. This is the champion's line, unchanged.
MATERIAL = {
    "wall_pilasters": "dungeon wall masonry, restrained pilaster blocks, fitted limestone, "
                      "weathered stone, slate and muted ochre, flat head-on diffuse albedo, "
                      "low fantasy dungeon material",
    "wall_rubble": "dungeon wall of irregular rubble stone, mortared fieldstone, chipped edges, "
                   "weathered stone, slate and muted ochre, flat head-on diffuse albedo, "
                   "low fantasy dungeon material",
    "wall_eroded": "dungeon wall of eroded limestone, pitted faces, crumbling courses, "
                   "weathered stone, slate and muted ochre, flat head-on diffuse albedo, "
                   "low fantasy dungeon material",
    "floor_flagstones": "dungeon floor of fitted flagstones, worn tread, dark mortar joints, "
                        "weathered stone, slate and muted ochre, flat head-on diffuse albedo, "
                        "low fantasy dungeon material",
    "floor_cobbles_rough": "dungeon floor of rough cobbles, uneven set stones, packed grit joints, "
                           "weathered stone, slate and muted ochre, flat head-on diffuse albedo, "
                           "low fantasy dungeon material",
    "ceiling_coffers": "dungeon ceiling of coffered stone panels, recessed square bays, "
                       "weathered stone, slate and muted ochre, flat head-on diffuse albedo, "
                       "low fantasy dungeon material",
}

CLASS = {
    "wall_pilasters": "wallPiece",
    "wall_rubble": "wallPiece",
    "wall_eroded": "wallPiece",
    "floor_flagstones": "texturePiece",
    "floor_cobbles_rough": "texturePiece",
    "ceiling_coffers": "texturePiece",
}

# The scene error, as refusals. Arm E only. Stated for the SCENE, because the
# fault is that the model imagines an unroofed structure and then lights it
# correctly for the sky it invented.
NEGATIVE_EXTRA = ("sky, daylight, sunlight, sunbeam, open air, outdoors, exterior, "
                  "courtyard, roofless, overgrown, clouds, horizon, light from above")

CHAMPION_SEED = 982200


def card(name, map_name, **over):
    spec = {
        "name": name,
        "class": CLASS[map_name],
        "provider": "forge-quality",
        "model": OHMEN,
        "description": MATERIAL[map_name],
        "height": f"{MAPS}/{map_name}.png",
        "depthWeight": 0.85,
        "variants": 2,
        "steps": 26,
        "cfg": 7.0,
        "seed": CHAMPION_SEED,
        "requestSize": "512x512",
    }
    spec.update(over)
    return spec


jobs = []

# A -- depth ladder at the champion's own seed. 0.60 reproduces the champion.
for w in (0.60, 0.85, 1.00):
    jobs.append(card(f"champ_a_pilasters_d{int(w * 100):03d}", "wall_pilasters",
                     depthWeight=w, variants=3))

# B -- the champion prompt on the geometries it has never been asked for.
for m in ("floor_flagstones", "floor_cobbles_rough", "ceiling_coffers",
          "wall_rubble", "wall_eroded"):
    jobs.append(card(f"champ_b_{m}_ohmen", m))

# C -- the two checkpoints the table says are worth another look.
for key, model in (("abyss", "abyssorangemix2NSFW_abyssorangemix2Nsfw"),
                   ("newera", "newERANewEstheticRetro_retroV60VAE")):
    for m in ("wall_pilasters", "floor_flagstones"):
        jobs.append(card(f"champ_c_{m}_{key}", m, model=model))

# D -- the texture LoRAs, finally at 512 with the champion wording.
for key, (lora, trigger) in {
    "quake": ("Quake_Texture_v1", "quake texture"),
    "wowtex": ("SXZ_WowTexture_v2", "wow texture"),
}.items():
    for m in ("wall_pilasters", "wall_rubble"):
        jobs.append(card(f"champ_d_{m}_{key}", m,
                         description=f"{trigger}, {MATERIAL[m]}",
                         loras=[{"name": lora, "weight": 0.70}]))

# E -- the refusals, isolated, against the B rubble card they pair with.
jobs.append(card("champ_e_wall_rubble_indoor", "wall_rubble",
                 negativeExtra=NEGATIVE_EXTRA))

out = "out/batch-2026-08-04-champion-jobs.json"
json.dump(jobs, open(out, "w", encoding="utf-8"), indent=1)
images = sum(j["variants"] for j in jobs)
print(f"{len(jobs)} jobs / {images} images -> {out}   (~{images * 1.5:.0f} min)")
