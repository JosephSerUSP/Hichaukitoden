# Dialogue portrait art direction

Portraits occupy a narrow 7.5x10-tile box. Compose every source with the face
and silhouette readable after severe downscaling. The bottom area carries the
speaker name directly over the drawing, without a separate name box; important
hands, jewelry, collars and facial features must stay above it.

The dialogue renderer permits a half-tile portrait overflow on every edge.
Final alpha-cut figures may let hair, hands and shoulders break the nominal
7.5x10 image rectangle slightly, but each pose must remain legible without
depending on that overflow and must not invade the message text area.

Expression sets are not facial swaps on one neutral model. Every emote is a
complete redraw: change the silhouette, posture, gesture, facing, crop and
foreshortening as aggressively as the acting beat warrants. A character may
lean into the frame, recoil, turn away, curl inward, loom, point or partly hide
their face. Recognition comes from the specific face, hair, costume and palette,
not from preserving a rigid model-sheet pose.

## Visual target

- handmade manga illustration by an idiosyncratic amateur-to-professional hand;
- slightly awkward anatomy: long necks, uneven eyes, stiff shoulders, unusual
  cheekbones, specific rather than conventionally attractive faces;
- visible graphite or colored-pencil construction under ink;
- Copic/alcohol-marker fills with overlaps, streaks and dry edges;
- scanned paper tooth, faint dust and imperfect registration;
- CMYK print character: restrained black, dirty cyan shadows, warm magenta skin
  accents and slightly displaced color edges;
- late-1990s console RPG portrait economy, but not pixel art and not a polished
  contemporary anime render;
- perfectly flat pure-black source background (`#000000`) without scenery or
  text, intended for deterministic area deletion after selection and cropping.

Avoid smooth digital airbrushing, perfect anatomy, glossy gacha rendering,
photorealism, clean vector lines, 3D models, bloom, cinematic lighting,
elaborate backgrounds, UI frames, written names and watermarks.

## Production prompt

```text
Use case: stylized-concept
Asset type: dialogue portrait source for a low-resolution first-person PSX-era
RPG; chest-up figure cropped to a tall narrow portrait box.

Subject: [CHARACTER DESCRIPTION].

Style/medium: genuinely handmade manga character drawing on off-white paper;
odd, specific anatomy and an individual face; visible graphite construction,
uneven pen line, colored-pencil hatching and Copic/alcohol-marker strokes;
scanned illustration with paper tooth, faint dust, imperfect CMYK registration,
dirty cyan shadows and restrained magenta/yellow color contamination. Feels
like obscure late-1990s Japanese computer or console RPG character art scanned
from a manual, not like in-engine graphics.

Composition: one strongly acted figure; redraw pose, silhouette, hands, facing,
crop and foreshortening for this specific emotion; face large and readable;
keep important features above the bottom 15 percent because the game overlays
the speaker name there.

Background: perfectly flat pure black #000000 for area deletion; no gradient,
texture, halo, scenery, shadow or vignette. Avoid pure black inside the
character where practical so the silhouette separates cleanly.

Constraints: one character only; no text, name box, frame, scenery or watermark.
Avoid: polished modern anime, gacha art, smooth digital painting, vector-clean
linework, photorealism, 3D rendering, perfect symmetry, fashion-model anatomy.
```

## First production group

Generate one coherent contact sheet for scale/composition checking, but create
comparison variants in separate generations.

1. Registrar Celina — severe Passage Office registrar; composed, watchful,
   practical formal clothing appropriate to Portuguese-colonial St. Maria.
2. Alicia — bakery proprietor; alert warmth rather than maternal softness;
   flour-marked working clothes and tired eyes.
3. Laura — forge proprietor; strong working posture, heat-marked skin,
   unromanticized physical build.
4. Sister Agnes — restrained chapel clothing; calm face that offers compassion
   without certainty.
5. Gate guard — weathered local professional; capable of delivering morbid
   advice without theatrical menace.
6. Foil Summoner — visually distinct from the player and townspeople; another
   outsider whose treatment of contracted creatures can be read immediately.

Creature portraits should receive a separate sheet and prompt family. Saban and
the first Pixie need to look like individuals rather than generic bestiary art.
