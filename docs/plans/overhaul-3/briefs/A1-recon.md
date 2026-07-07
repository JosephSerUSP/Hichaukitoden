# A1 — Hardcode inventory (recon, read-only)

- Branch: `o3/a1-recon`
- Runtime needs: none (text only)
- Depends on: nothing
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S1, S2, S4

## Goal

Produce `docs/plans/overhaul-3/flow-inventory.md`: an exhaustive table of every
hardcoded calculation, branch, constant, and player-facing behavior in
`main.lua`, `engine/battle.lua`, `engine/exploration.lua`,
`engine/session.lua`, `engine/effects.lua` that is not already read from
`data/*.json`.

## Do

- Table columns: `file:line | behavior | proposed phase | proposed command(s) | notes`.
- Group rows by proposed phase (use the S4 phase names; invent
  `exploration.*` phase names where map mechanics warrant them).
- Must cover at minimum: victory rewards, state ticks, MP drain/exhaustion,
  flee resolution, encounter roll + enemy composition, defeat reset, level-up
  HP refill, the treasure GIVE_ITEM path.

## Don't

- Do not modify any code or data file. This task creates exactly one new
  markdown file.

## Acceptance

- [x] `flow-inventory.md` exists with a `file:line` reference for every row
- [x] All eight minimum behaviors above are present
- [x] PR checklist from SPEC Ground rules filled in (gates: N/A — text only)
