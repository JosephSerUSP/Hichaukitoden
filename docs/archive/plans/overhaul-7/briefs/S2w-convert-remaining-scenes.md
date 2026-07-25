# S2w: Convert Remaining Menu Scenes to Data-Authored Windows

**Context:** Read SPEC.md S7, S8. Fans the S1w schema out across the
remaining menu scenes. **Depends on S1w surviving its pilot.**

**Role:** local agent; each scene's trace regen is owner-reviewed.

## Acceptance Criteria
- [ ] Converted, one commit per scene, each with its own sanctioned
      UI-golden trace regen: `status`, `shop`, `reserve`, `title`,
      `game_over` (plus `items` or `status` — whichever S1w didn't take).
- [ ] **`battle` and `map` are NOT converted** (SPEC S8 — entangled with
      T2 picker states; future round).
- [ ] Each conversion deletes the Lua drawing path it replaces — grep for
      the removed function names at round close; no orphaned callers.
- [ ] Missing content-block needs are met by extending the schema
      additively (new block type or optional field), never by
      special-case Lua. Schema extensions get validator coverage and a
      one-line note in SPEC S7's block-type list via PR description (not
      by editing the SPEC).
- [ ] Scene canvas + window editor work on every converted scene.

**Gates:** G1, G2 byte-identical, G3 (per-scene sanctioned regens; all
unconverted scenes strict).
