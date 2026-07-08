# A5a — Convert victory rewards to a flow phase

- Branch: `o3/a5a-victory`
- Runtime needs: G1, G2
- Depends on: A4 merged
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S2, S4, S6
  (zero-SCRIPT rule); `docs/plans/overhaul-3/flow-inventory.md` (victory rows)

## Goal

Move the victory block (gold gain, per-survivor XP, POST_BATTLE_HEAL) from
`main.lua` into `data/flows.json → battle.victory` using registry commands
only.

## Do

- Author the default phase with `FOR_EACH` / `GAIN_GOLD` / `GRANT_XP` /
  `TRAIT_HEAL` / `EMIT_TEXT` (+ a `COMMENT` header row describing the phase).
- Default formulas must reproduce current behavior EXACTLY:
  gold `random(combat.victoryGoldMin, combat.victoryGoldMax)`, XP
  `combat.victoryExp` (the `combat` context table comes from SPEC S5).
- Guard the legacy Lua block with `if not flow.has("battle.victory")`; keep
  the legacy body in place (cleanup happens in a later round).

## Don't

- No SCRIPT commands (SPEC S6 zero-SCRIPT rule). No other phase conversions.

## Acceptance

- [ ] G1 green; G2 byte-identical
- [ ] Deleting the phase from flows.json restores legacy behavior (spot-check,
      then restore)
- [ ] PR checklist filled in
