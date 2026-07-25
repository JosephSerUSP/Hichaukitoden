# A5c — Convert flee resolution to a flow phase

- Branch: `o3/a5c-flee`
- Runtime needs: G1, G2
- Depends on: A4 merged
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S2, S4, S5;
  `docs/plans/overhaul-3/flow-inventory.md` (flee rows)

## Goal

Move the flee chance roll and failure gold penalty from `engine/battle.lua`
into `data/flows.json → battle.flee_attempt`.

## Do

- Success → emit the `flee_success` event; failure → gold penalty
  (`random(combat.goldLossOnFleeMin, combat.goldLossOnFleeMax)`) +
  `EMIT_TEXT battle.flee_fail`.
- Expose the party's FLEE_CHANCE_BONUS trait sum to formulas as
  `party.fleeBonus` (add to the formula context builders; document in
  `formulaHelp`).
- Legacy fallback guard as in SPEC S4.

## Don't

- No SCRIPT commands. No other phases.

## Acceptance

- [ ] G1 green; G2 byte-identical (the golden round 3 exercises flee)
- [ ] `party.fleeBonus` appears in `engine.json → formulaHelp`
- [ ] PR checklist filled in
