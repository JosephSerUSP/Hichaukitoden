# Stage: outline (walkthrough-first)

You are designing a complete small RPG campaign for a dungeon-crawler engine
(first-person exploration, one town hub, dungeon floors, a Summoner protagonist
who fields summoned creatures; creatures die permanently and convert to banked
EXP). The campaign must be finishable in 30-45 minutes.

## The pitch

{{PITCH}}

## Fixed ruleset you design WITHIN (do not invent new roles/elements/states)

{{RULESET}}

## Deliverable

Reply with ONE JSON object, no other text:

```json
{
  "outline": {
    "title": "...",
    "logline": "one sentence",
    "setting": "2-3 sentences",
    "acts": [ { "name": "...", "beats": ["..."], "mapsUsed": ["map title"], "climax": "..." } ],
    "cast": [ { "name": "...", "role": "npc|creature|boss", "concept": "...", "location": "map title" } ],
    "maps": [ { "title": "...", "category": "town|dungeon", "concept": "...", "depth": 1 } ],
    "quests": [ { "id": "snake_case", "name": "...", "giver": "cast name", "summary": "...", "act": 1 } ],
    "ending": "how the campaign concludes"
  },
  "walkthrough": "# <title> -- Walkthrough\n\nFull markdown walkthrough of the critical path, act by act: where the player starts (which map), who to talk to, which quests to take, which floors to descend, the boss, the ending. Every later generation stage derives from THIS document, so anything you name here (NPCs, items, maps, quests) must appear in the outline arrays above."
}
```

Rules: exactly one town map. 3-6 dungeon maps. 2-4 quests. The cast list is
the complete NPC + boss roster. Keep the scope small enough to actually finish.
