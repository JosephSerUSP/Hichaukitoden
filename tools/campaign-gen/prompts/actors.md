# Stage: actors

Generate the campaign's full actors.json (creatures, bosses, and the Summoner)
from the outline. Keep ALL existing actors whose role is "Summoner" exactly
as-is (copy them from the manifest ids); replace the rest of the roster with
the outline's cast, plus enough generic creatures for encounters (aim for
15-25 total).

## Outline

{{OUTLINE}}

## Fixed ruleset (roles/elements/states/passives/skills you may reference)

{{RULESET}}

## Current id manifest (the Summoner entry to preserve is in here)

{{MANIFEST}}

## Schema by example (copy this shape EXACTLY; unknown fields are tolerated
but every field shown matters)

Actor sample:
{{SAMPLES}}

## Deliverable

ONE JSON object: `{ "actors.json": [ ...complete actors array... ] }`

Rules:
- ids are sequential integers starting at 1, unique.
- spriteKey/smallBattler: reuse ONLY sprite keys that appear in the manifest's
  existing actors (asset generation is a separate step; placeholder reuse is
  correct here). Pick thematically closest.
- skills/passives/elements: only ids from the ruleset.
- CRITICAL: an actor's "role" field must be one of the ruleset's role ids
  EXACTLY (see RULESET.roles). The outline cast's npc/creature/boss labels
  are narrative categories, NOT role ids -- map each cast member to the
  closest real ruleset role.
- initialParty/isRecruitable/unlocked/tier/discipline follow the sample's
  conventions; give the player 2-3 unlocked starter creatures.
- Bosses get higher level/tier and a `flavor` line each.
