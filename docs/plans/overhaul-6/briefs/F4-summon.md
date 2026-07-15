# F4: Summon

**Context:** Read SPEC.md S5. Mints a fresh creature instance into an empty
reserve slot (or per owner decision if roster's full), gated by a new
per-species unlock flag. **Depends on F3** (needs a reserve slot to summon
into).

**Role:** local agent; data-shape decisions below need a quick owner check
before landing, not a full supervised pairing session.

## Acceptance Criteria
- [ ] `data/actors.json` gains an unlock concept. First check whether
      `isRecruitable`/`initialParty` can be repurposed with matching
      semantics before adding a new field — only add `unlocked` (default
      false, true for starting species) if reuse genuinely doesn't fit.
      Document the decision in the PR either way.
- [ ] At least one unlock-trigger mechanism ships: an interpreter command
      (e.g. `UNLOCK_SPECIES <id>`) usable from any event/dialogue script —
      covers NPC-offer, contract-trigger, and defeat-triggered unlock (via
      existing battle-end event hooks) without building three separate
      systems. Do not build every unlock source Summoner.md mentions — this
      one command is the intentionally minimal viable set; leave room for
      more later.
- [ ] Summon mints a fresh level-1 instance by default. A formula (in
      `data/system.json`, following the existing formula-driven-config
      convention, not hardcoded Lua) allows paying extra MP for a higher
      starting level.
- [ ] Summon cost scales by species — since no tier field exists yet,
      either add one or derive a defensible proxy from existing stats;
      document which and why. No species may end up with an undefined cost.
- [ ] Summon is reachable ONLY from the field menu — gate at the UI entry
      point (menu construction), not by special-casing battle scenes to
      hide it.
- [ ] Full-roster behavior (12/12 already, no empty reserve slot) decided
      with the owner — Summoner.md doesn't specify; a quick confirm is
      enough, don't build a whole slot-selection UI speculatively if the
      owner just wants "blocked with a message" for v1.

**Gates:** G1, UI-golden for the field-menu scene gaining Summon, G3 visual
check. G2 unaffected unless you find otherwise (flag if so).
