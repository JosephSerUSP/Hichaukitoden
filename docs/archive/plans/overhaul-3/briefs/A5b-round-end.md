# A5b — Convert round-end ticks to a flow phase

- Branch: `o3/a5b-round-end`
- Runtime needs: G1, G2
- Depends on: A4 merged (recommended: after A5a/A5c/A5e merges — this is the
  ordering-sensitive one)
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S2, S4;
  `docs/plans/overhaul-3/flow-inventory.md` (round-end rows)

## Goal

Move regen/poison ticks, state-duration decay, per-ally MP drain, and MP
exhaustion damage from `engine/battle.lua` into
`data/flows.json → battle.round_end`.

## Do

- Use `STATE_TICKS`, `FOR_EACH`, `DRAIN_MP`, `DAMAGE`, `IF`, `EMIT_TEXT`.
- **Event ordering must be preserved exactly** — the golden log is the
  arbiter. If an ordering cannot be reproduced with existing commands, stop
  and report rather than approximating.
- Legacy fallback guard as in SPEC S4.

## Don't

- No SCRIPT commands. Do not "fix" any oddity you find in the current
  ordering — reproduce it and note it in the PR instead.

## Acceptance

- [ ] G1 green; G2 byte-identical
- [ ] PR checklist filled in
