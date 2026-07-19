# Stage: items

Generate items.json and shops.json for the campaign. Derive item flavor from
the outline's setting; keep counts close to the sample campaign's (30-45
items: consumables, equipment for the 3 slots, quest items, crafting
materials).

## Outline

{{OUTLINE}}

## Id manifest (actors are final now; quest items you invent here become the
ids the quests stage references)

{{MANIFEST}}

## Schema by example

{{SAMPLES}}

## Deliverable

ONE JSON object: `{ "items.json": [ ... ], "shops.json": { ... } }`

Rules:
- Item ids: sequential integers from 1, unique.
- Every quest in the outline that needs a fetch-object gets a matching item
  here (mark it type "key" or similar per the sample's conventions).
- shops.json: string-numeric keys ("1", "2", ...); each shop's items reference
  item ids that exist; shop count and stock sized to the outline's town.
- Meta keys (tier/density/potency/craftElement/craftKind) follow the sample.
