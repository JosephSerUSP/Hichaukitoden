# F5: Sacrifice

**Context:** Read SPEC.md S6, `docs/game design/Permadeath.md`, and
`docs/game design/itemCreation.md`. Permanent creature removal (active or
reserve) for an MP refund plus optional gated item reward. **Can land
alongside F4** (independent mechanic, shares only the roster data F3 built).

**Role:** local agent; the shared-data-shape question below needs a check
against wherever Item Creation's discipline field stands before landing.

## Acceptance Criteria
- [ ] Sacrifice permanently removes a creature (active or reserve) from the
      roster — full growth reset if summoned again (same species can be
      re-summoned later as a fresh level-1 instance, per Summon).
- [ ] MP refund scaled by the sacrificed creature's level via a formula slot
      (same convention as F4's summon-cost formula — `data/system.json`).
- [ ] Optional item reward gated by (a) creature state at sacrifice time
      (HP%, level, conditions) AND (b) species/discipline. **Before adding a
      new per-species flavor table**, check whether Item Creation's
      discipline identity (`itemCreation.md`) already has a field in
      `actors.json` by the time you run this brief. If yes, reuse it. If
      no, add the field and document it explicitly as a SHARED field for
      both systems (comment in the data file, not just the PR) so Item
      Creation doesn't fork a second one later.
- [ ] Field-menu-only, same gating pattern as Summon (F4) — reuse that
      brief's UI entry-point gating approach rather than reinventing it.
- [ ] Confirm in the PR that Sacrifice and Permadeath share whatever
      "creature is permanently gone" removal code path already exists
      (from Permadeath, if implemented by the time this lands) rather than
      duplicating a second removal function.

**Gates:** G1, UI-golden for the field-menu scene gaining Sacrifice, G3
visual check. G2 unaffected unless found otherwise.
