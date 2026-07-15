# T1: Unified Target Spec + Resolver

**Context:** Read SPEC.md S0, S1, S5. Replaces the ad-hoc target-string
branches in `engine/battle.lua` with one declarative spec and one resolver
module. **This is the round's ONE sanctioned `battle.log` regeneration.**

**Role:** owner-supervised, never autonomous (touches `engine/battle.lua`).

## Acceptance Criteria
- [ ] `engine/targeting.lua` exists: `resolve(actor, spec, battleState,
      chosenTarget?) -> {targets}`. All target-list construction in
      `battle.lua` (AI branch ~L39–93, resolveRound, applyItem's
      `targetScope == "party"` branch) routes through it; the old
      per-string branches are deleted.
- [ ] Spec schema per SPEC S5: `{side, count, mode, state}` with string
      shorthands. Full-form and shorthand both accepted everywhere a spec
      is read; readers ignore unknown extra fields (extensibility rule).
- [ ] `skills.json`/`items.json` existing target strings all resolve;
      items' `targetScope` field is absorbed (field removed from data OR
      mapped with a deprecation note — decide with owner, document).
- [ ] Validator: unknown/unresolvable target specs fail G1. The current
      silent fallthrough (unrecognized string → whatever the last branch
      did) must be impossible afterward.
- [ ] AI behavior semantics preserved: random within the same legal target
      set as today. Any discovered behavioral bug (e.g. a scope string
      that never matched) is flagged to the owner, not silently fixed or
      preserved.
- [ ] `state:"dead"` filtering implemented in the resolver (door for
      revival); no revival content added.
- [ ] `battle.log` regenerated ONCE, owner reads the diff of the new log
      before commit. Byte-identity discipline resumes immediately after.

**Gates:** G1, G2 (sanctioned regen, then strict), G3 unaffected (flag if
not).
