# A2: Assignable Animations on Skills/Items

**Context:** Read SPEC.md S3. Skills and items reference animation entries
by id; the battle scene plays them on the event's target. **Depends on
A1.**

**Role:** owner-supervised IF the logger-serialization check (below) forces
touching `engine/battle.lua`; otherwise local agent. Determine this first
and report which mode applies before proceeding.

## Acceptance Criteria
- [ ] `skills.json` and `items.json` entries accept optional `animation`
      (animations.json id, class assignable). Absent → today's default
      visuals exactly (no data edits required for existing content).
- [ ] FIRST: check whether `tools/golden/battle.log` serializes whole
      event tables. If an `animation` field riding on battle events would
      appear in the log, resolve the id scene-side
      (`engine/scenes/battle.lua` consumes the event, looks up the
      skill/item's animation) and leave `engine/battle.lua` untouched.
      Document the finding either way.
- [ ] Playing an assignable animation goes through A1's player — no new
      timing code in the scene layer.
- [ ] Validator: dangling `animation` refs fail G1.
- [ ] At least two demo assignments ship in data (one skill, one item)
      using ported entries (e.g. `healing_sparkle`), owner-approved.

**Gates:** G1, G2 byte-identical (hard requirement — see serialization
check), G3 visual check.
