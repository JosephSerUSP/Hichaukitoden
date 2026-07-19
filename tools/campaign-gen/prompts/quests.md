# Stage: quests

Generate quests.json from the outline's quest list. Item requirements and
rewards must reference REAL item ids from the manifest (items are final now).

## Outline

{{OUTLINE}}

## Id manifest

{{MANIFEST}}

## Schema by example

{{SAMPLES}}

## Deliverable

ONE JSON object: `{ "quests.json": { "<quest_id>": { ... }, ... } }`

Rules:
- Quest ids: the outline's snake_case ids, exactly.
- requirements.items / rewards.items reference manifest item ids only.
- Every quest has name, giver, summary, description, objectives (2-4 strings),
  requirements, rewards -- same shape as the sample.
- Rewards stay modest (this is a 30-45 minute campaign).
