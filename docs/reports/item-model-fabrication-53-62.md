# Item model fabrication batch: items 53–62

Date: 2026-08-07

## Scope

This batch takes the first contiguous block after the existing modeled roster and creates ten new deterministic low-poly runtime models:

| ID | Item | Model | Design cue |
|---:|---|---|---|
| 53 | Celestial Fossil | `assets/models/items/celestial_fossil.obj` | faceted fossil tablet, spiral ribs, cold crystal heart |
| 54 | Blackroot | `assets/models/items/blackroot.obj` | knotted tuber with five crooked roots and wet growth |
| 55 | Molten Manacle | `assets/models/items/molten_manacle.obj` | visibly broken C-shaped shackle with hot fracture caps |
| 56 | Adamant Weight | `assets/models/items/adamant_weight.obj` | dense faceted calibration/plumb weight with a metal lug |
| 57 | Iron Knife | `assets/models/items/iron_knife.obj` | short work knife with a minimal guard |
| 58 | Steel Sword | `assets/models/items/steel_sword.obj` | plain, legible one-handed sword |
| 59 | Knight Sword | `assets/models/items/knight_sword.obj` | broader heraldic sword with gold fuller and lifted quillons |
| 60 | Greatsword | `assets/models/items/greatsword.obj` | oversized two-handed blade, reinforced ricasso, wrapped grip |
| 61 | Adamant Blade | `assets/models/items/adamant_blade.obj` | heavy split-tip blade with shoulder fins, gold structure and crystal counterweight |
| 62 | Hazel Wand | `assets/models/items/hazel_wand.obj` | crooked forked branch holding a subdued crystal |

The batch generator is `tools/asset-production/build_item_models_53_62.py`. It writes the OBJ files plus a shared semantic MTL deterministically and, in a normal local checkout, also assigns their paths to items 53–62 in `data/items.json`. The generated OBJ/MTL files are included in this branch so review does not depend on running the builder.

Because this run published through GitHub object writes rather than a full repository checkout, the resulting `data/items.json` rewrite is **not** included in this branch. Running the batch generator in a normal checkout performs those ten explicit assignments. Until that step is committed, the runtime still treats IDs 53–62 as unassigned and uses its missing-model fallback.

## Creative process

The item viewer is small and continuously rotating, so the first design question was not fine surface detail but whether an object can be identified from silhouette and massing. I treated the ten as a miniature library rather than ten isolated props.

The four promotion keys deliberately use different object grammars: a flat fossil cross-section, an organic radial root, an open circular restraint, and a dense hanging weight. This avoids a common procedural-library failure mode where “different relics” are one primitive with different colors.

The five mundane weapon tiers are a progression in construction rather than only scale. Iron Knife is almost purely functional. Steel Sword establishes the baseline sword. Knight Sword introduces heraldic structure and a decorative fuller. Greatsword becomes visibly two-handed and materially rougher at the grip. Adamant Blade stops looking like a historical upgrade and becomes a strange high-tier artifact: thicker, split at the tip, finned at the shoulders and counterweighted with crystal. That lets tier read before the item name does.

Hazel Wand was intentionally kept irregular. A perfectly straight cylinder with a gem would read as “generic RPG wand”; a sequence of slightly misaligned tapered branch segments gives it a found, natural character that fits a low-tier alchemical implement.

All of the forms stay coarse enough to suit Second Rite's low-poly/PSX presentation. The extra geometry is spent on silhouette changes, negative space and material boundaries rather than hidden curvature.

## Experience with the repository's 3D fabrication tools

### What worked well

The repository has a strong authorial contract even though its 3D tooling is spread across several layers. The item-model toolkit is explicit that the Python recipe is source, Blender is compiler, pivots are normalized, and OBJ/MTL are generated products. The asset-language material registry gives procedural work a shared vocabulary instead of allowing every script to invent arbitrary colors. The runtime OBJ loader is also pleasantly strict and small: it makes the actual delivery format easy to reason about.

The best design rule in the toolkit is “distinct silhouettes and material regions rather than relying only on recoloring.” It is concrete enough to influence modeling decisions, and it maps directly onto the way the item preview is seen in game. The same is true of the census tooling's emphasis on screen-space readability, topology sanity and distinguishable variants.

### Friction encountered

The canonical item library is still coupled to Blender 5.0+, and its main generator is a large monolithic script. That is excellent for reproducing the established 49-root gallery, but comparatively expensive when the task is “add ten small runtime props.” There is no narrow item CLI analogous to the asset-production adapters for world props.

The asset-production documentation also describes a backend-neutral direct mesh recipe/compiler for the model census, but that reusable layer is not exposed as a general item-fabrication API in the current repository tree. In practice there is a gap between the elegant semantic contract and a small dependency-free way to author one-off item geometry.

This execution environment did not provide Blender 5, so I could not honestly claim a Blender rebuild or `.blend` inspection. Rather than hand-write opaque OBJ files, I used the runtime contract directly and added a deterministic standard-library-only batch builder. It consumes the tracked semantic material registry, centers each model, emits only supported OBJ directives, and validates every face/material reference after export. This kept the work reproducible while making the missing “small direct item compiler” seam visible.

I would not replace the Blender toolkit with this script. The useful architectural direction is the opposite: extract the tiny mesh primitives and deterministic OBJ/MTL writer into a shared library, then let both Blender-backed recipes and direct low-poly item batches consume the same geometry description.

## Mechanical checks performed

The local deterministic build completed for all ten models. Post-export validation checked:

- every OBJ has vertices, triangles and an `mtllib` declaration;
- every `mtllib` resolves to the generated sibling MTL;
- every `usemtl` is declared by that MTL;
- all face indices are in range;
- all faces are triangles and non-degenerate;
- every material ID comes from `tools/asset-language/materials.json`;
- all models have non-zero centered bounds;
- a neutral 3D contact-sheet inspection confirmed the ten silhouettes are distinguishable and the weapon progression remains readable.

Build sizes:

| Item | Vertices | Triangles |
|---|---:|---:|
| Celestial Fossil | 84 | 140 |
| Blackroot | 103 | 174 |
| Molten Manacle | 158 | 264 |
| Adamant Weight | 82 | 136 |
| Iron Knife | 42 | 68 |
| Steel Sword | 42 | 68 |
| Knight Sword | 82 | 132 |
| Greatsword | 90 | 140 |
| Adamant Blade | 86 | 136 |
| Hazel Wand | 100 | 168 |

The LÖVE verification commands and Blender rebuild were not run in this environment because neither `lovec` nor Blender is available here. The branch therefore reports those as unexecuted rather than treating local geometric validation as equivalent to the repository's in-engine gates.
