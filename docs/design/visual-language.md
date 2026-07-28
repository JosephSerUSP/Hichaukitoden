# Visual language — Second Rite: Thestra no Jijou

> Intent, not implementation status. This brief guides image generation,
> selection, downscaling, palette work and future authored presentation.

## Production hierarchy

- **5x5 — ideation.** Twenty-five small frames search vocabulary: subjects,
  lighting, camera, materials and recurring motifs. Crops are references, not
  presumed final art.
- **3x3 — finished-level batches.** Nine closely related frames commit to one
  location, event or visual family. Each crop remains larger than 256x240 and
  is suitable for a deliberate RetroDither pass.
- **1x1 — hero exception.** Reserved for a title, ending or composition that
  cannot tolerate contact-sheet compromises.

The default has since changed: use **3x3** for both production and ideation,
preferably as three authored subjects with three controlled treatments each.
The earlier 5x5 workflow produced weak, generic breadth and is now reserved for
exceptional taxonomies where all twenty-five cells have named production
purposes.

Keep the untouched contact sheet beside its crops. Use
`tools/image/split-contact-sheet.ps1` to produce aspect-correct masters and
native nearest-neighbour previews.

Feed direct captures from the live raycaster into image generation whenever
the new art must belong beside gameplay. Screenshots are authoritative for
screen proportions, darkness, texture density, palette and the engine's actual
spatial limitations. Describe explicitly whether the output is a raycast
asset, a static close-up plate or prerendered cinematic art; a reference
screenshot does not mean every output should pretend to be engine-rendered.

### Dialogue-backed plate geometry

The runtime canvas is 256x240, but dialogue begins at y=144 and occupies the
bottom 96 pixels. A dialogue-backed CG therefore has a **256x144 (16:9) safe
visual area** at the top. The source image may continue behind the window, but
faces, objects, evidence, entrances and other essential composition must remain
fully legible above y=144.

Use **2x3 contact sheets** for batches of six dialogue-backed plates unless the
generator can produce an exact layout better matched to six 16:9 frames. The
six cells should be six distinct required assets, not several nominal
variations of one image.

Generate comparison variants in separate image-generation calls. Variants
placed together on one sheet tend to converge on nearly identical composition,
lighting and geometry, which makes the comparison misleading. A contact sheet
is for economical asset batching; iteration is across batches.

Use `tools/image/split-dialogue-contact-sheet.ps1` for this format. It crops
each generated cell to 16:9, writes that image into the upper 256x144 safe
area, and extends the runtime canvas to 256x240 so the ordinary location
renderer does not scale or crop it again.

## Three distinct presentation families

### Raycast gameplay

The town and Labyrinth are explored through the engine's actual first-person
raycaster. This family is defined by composite wall textures, rectilinear map
geometry, textured floors and ceilings, wall fixtures and billboard objects.
There is no visible protagonist and no free-camera polygonal environment.

Do not prompt gameplay views as third-person low-poly PSX scenes. The limited
raycaster is an authored visual constraint, not an approximation of a general
3D engine.

### Static location plates

Door entry may replace the raycast map layer with a static image for an
interior or focused location. The door zoom and fade are only a transition;
the plate's camera is free to use the strongest establishing composition for
the room. It does not need to be seen from the doorway and should not acquire a
foreground doorframe merely to explain how the player entered.

These plates may use richer prerendered CG than gameplay. Generate environments
separately from character imagery. Unoccupied plates are the default; people
belong only where the authored scene specifically requires them.

### Prerendered FMV

Prompt anchor: **"a frame from a lost PSX JRPG's prerendered FMV."**

Use for memory, travel, boundary crossing, rites and major transitions. Prefer
chunky offline CG, baked light, waxy materials, dithered gradients, color
bleeding, banding and muddy MPEG-like compression. It may be more composed and
symbolic than the in-engine family, but not more modern.

The governing references are awkward early productions such as *D* and
*Ancient Roman*, not polished modern "PSX-inspired" art. Technical inadequacy
is part of the image language: primitive box modeling, stiff mannequins, crude
faces, stretched or poorly aligned textures, blunt Gouraud shading, baked
shadows, sparse sets, inconsistent scale, clumsy perspective and compositions
that feel staged by an inexperienced 1996 CG team. The result should be
earnest, uncanny and sometimes faintly embarrassing. Do not beautify these
defects into a tasteful low-poly aesthetic.

## St. Maria

St. Maria's defining architectural influence is **Portuguese colonial Brazil,
especially Santos, Sao Paulo**. It must not collapse into a generic medieval
European mountain village. Its strongest forms include:

- limewashed stucco over brick and stone;
- peeling ochre, white, faded blue, green and rose facades;
- terracotta tiled roofs and deep, weather-darkened eaves;
- Portuguese azulejo used sparingly on thresholds, interiors and civic or
  religious surfaces;
- narrow irregular streets, small attached houses, internal courtyards and
  wrought-iron balconies;
- baroque and colonial religious forms scaled to a poor remote settlement,
  rather than a monumental Gothic church;
- salt bloom, damp plaster, rust, mildew, rain channels and vegetation
  returning through cracks;
- hard Atlantic daylight, humid haze and sudden warm reflected color.

Santos is an influence in material memory rather than a requirement that the
fictional settlement reproduce the real city's geography. St. Maria may remain
remote and topographically strange, but it should feel culturally and
architecturally descended from a humid Portuguese colonial port town.

St. Maria is poor, inhabited and maintained. Alongside plaster, tile and
terracotta, its recurring materials are old timber, smoke, flour, iron, wax,
patched cloth and small amber lights. Residents should usually be occupied
rather than posed.

Ordinary town states remain desaturated and cold. The first festival is
effective because handmade lanterns and crowded streets introduce an almost
excessive warmth into an established gray place. Decorations must still look
cheap, local and physically hung by residents; avoid spectacular magical
illumination.

Interiors are dense with evidence of use. The assigned home retains traces of
earlier occupants. The bakery, forge and tavern are workplaces first. Painted
plaster, exposed roof timber, patterned tile floors, shutters and small internal
courtyards should distinguish them from generic northern-European rooms. The
chapel uses colonial baroque proportions, emptiness, water, wax, azulejo and
memorial objects rather than Gothic verticality or monumental grandeur.

## The Labyrinth

Early spaces remain materially legible: threshold stone, damp brick, black
water, bone and corroded fixtures. Depth gradually damages perspective and
spatial certainty. Impossible geometry should arrive as a corruption of
familiar masonry, not as abstract cosmic spectacle.

Characters remain small against entrances and chambers. The Labyrinth gains
scale by swallowing human proportion, not through ornamental complexity.

## Summoning imagery

Summoning is a boundary problem, not elemental fireworks. Recurring motifs:

- doubled or delayed silhouettes;
- a human shadow separating from its owner;
- narrow blue seams;
- chalk, bindings, metal and spent light;
- empty restraints after sacrifice;
- named tokens and worn belongings after death;
- bodies or rooms briefly losing shared perspective.

Creature manifestation can be brighter than the environment, but should remain
localized and physically awkward. A rite leaves residue.

## Palette and finishing

Base colors: slate blue, dirty gray-green, wet brown, soot black and sparse
amber, joined in town by lime white, terracotta, faded colonial blue, ochre and
weathered rose. Purple-red belongs primarily to altered town states. Blue marks
boundary failure and portals; keep it narrow enough to remain special.

High-resolution generation sources remain outside the repository. Runtime
images target 256x240 and a 64- or 128-color palette through RetroDither.
Antialiased downsampling is allowed; preserve large value shapes, silhouettes
and readable light sources, while fine generated texture is disposable.

## Retained production plates

Only game-referenced cinematic plates live in the repository. Four interior
studies remain under `assets/cinematics/ideation/`; they predate the
Santos/Portuguese-colonial correction and are composition references, not final
architectural authority. The Ines mark, salt table and borrowed-room references
remain under `assets/cinematics/campaign_inspection/`, with their dialogue-safe
runtime derivatives under `assets/locationArt/campaign_*.png`.

The root-level arrival cart, rain road and Labyrinth threshold plates form the
current opening. Continuity matters more than any single image's novelty: the
battered case, coat, rain, time of day, village silhouette and screen direction
should recur if that sequence is regenerated. Rejected boards, unused variants
and high-resolution generation sources remain outside the repository.

## Prompt anchors for St. Maria

Include language such as:

> a dark lost late-1990s PSX JRPG interpretation of a humid Portuguese
> colonial Brazilian settlement, strongly influenced by old Santos, Sao Paulo;
> limewashed plaster, terracotta roof tile, restrained azulejo, baroque chapel,
> wrought iron, salt bloom, tropical damp and Atlantic light

Explicitly avoid:

> generic medieval European village, Alpine town, northern stone hamlet,
> Gothic castle, Tudor timber framing, pristine tourist-colonial architecture
