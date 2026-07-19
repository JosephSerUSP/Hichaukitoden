# Stage: maps

Generate maps.json from the outline: one town (hand-authored layout) and the
dungeon floors (procedural generation fields). NPC events on the town map get
PLACEHOLDER one-line TEXT scripts here -- the events stage replaces them with
full conversations next.

## Outline

{{OUTLINE}}

## Id manifest (actors/items are final; encounters and recruits reference
actor ids, treasures reference item ids)

{{MANIFEST}}

## Schema by example (note the town map's layout string format: `#` wall,
`.` floor, one string per row, all rows equal length)

{{SAMPLES}}

## Deliverable

ONE JSON object: `{ "maps.json": [ ... ] }`

Rules:
- Map ids: sequential integers from 1. The town is id 1 with
  `"category": "town"` and `"safe": true`.
- Town layout: 19-24 columns wide, 18-22 rows, outer walls, walkable plaza,
  building-ish wall clusters. Place one interact event per outline cast NPC
  at a sensible floor tile (0-indexed x/y on a FLOOR '.' tile adjacent to
  walkable space), sprite reused from existing `assets/sprites/NPC*.png`
  paths seen in the sample.
- Dungeon floors: follow the sample's procedural fields (generation, depth,
  encounters, treasures, recruits, encounterSteps); encounters/recruits use
  manifest actor ids, treasures use manifest item ids; difficulty scales
  with depth per the outline's acts.
- Every map title matches the outline's maps list.
