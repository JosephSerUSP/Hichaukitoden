# F2: MP as the central resource (audit, not rebuild)

**Context:** Read SPEC.md S1 and S3. Two MP systems already exist
(round-end drain in `engine/battle.lua:340-374`, command-driven
`CHANGE_MP`/`DRAIN_MP`/`RESTORE_MP` in `engine/interpreter.lua:368-388`).
This brief audits and adjusts them for a post-F1 world, it does not build
MP drain from scratch. **Must land after F1.**

**Role:** owner-supervised (touches `battle.lua` again, same file F1 just
rewrote).

## Acceptance Criteria
- [ ] Round-end drain (`battle.lua:340-374`) confirmed correct with the
      summoner gone: no leftover summoner-specific branching, drains
      `session.mp` from active-creature `mpd` params exactly as before.
- [ ] MP-exhaustion damage confirmed to iterate active creatures correctly
      post-F1 (it should already — verify, don't assume).
- [ ] Spell/item MP-cost call sites in `data/skills.json` audited for any
      summoner-specific assumption (e.g. a formula referencing a summoner
      stat that no longer exists as a Battler) — fix if found.
- [ ] MP display: propose a small persistent MP readout location (SPEC S3
      recommends the shared bottom party-window strip) to the owner, get a
      quick nod, then implement. Do not ship a UI placement decision
      unreviewed.
- [ ] No new balancing — costs/rates/thresholds unchanged unless a value is
      provably broken by F1 (division by a now-absent summoner stat, etc.).
      If you find one, fix the minimum needed to not crash/misbehave; do not
      use this as license to retune numbers generally.

**Gates:** G1, G2 (`battle.log` must be BYTE-IDENTICAL to F1's regenerated
log — this brief is plumbing/audit, not new mechanics; if your change makes
the log differ, that's a signal you changed behavior, not just confirmed
it), UI-golden for whichever scene gains the MP readout.
