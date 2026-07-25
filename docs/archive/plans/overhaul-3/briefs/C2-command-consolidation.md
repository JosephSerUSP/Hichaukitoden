# C2 — Command consolidation (CHANGE_ITEM and friends)

- Branch: `o3/c2-command-consolidation`
- Runtime needs: G1 + G2 (engine change); G3 for the editor side
- Depends on: A6, A7, A4b merged
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S1, S2

## Goal

Collapse redundant command pairs into single commands with a mode/sign
param, per owner feedback item 4 in `docs/plans/overhaul-3/FEEDBACK.md`.
The golden log and all existing data must stay byte-identical/valid — old
ids remain as **aliases**, not removals.

## Do

1. New `CHANGE_ITEM` command: params `item` (dropdown, with a special
   `"random"` option meaning the map's treasure roll), `count`
   (signed: positive gives, negative takes). One Lua handler in
   `engine/interpreter.lua` routing through the existing
   GIVE_ITEM/GIVE_ITEM_ID/TAKE_ITEM logic.
2. Keep `GIVE_ITEM`, `GIVE_ITEM_ID`, `TAKE_ITEM` registered and working
   (registry entries may gain `"deprecatedBy": "CHANGE_ITEM"`); the editor
   palette hides deprecated commands from the ADD flow but still renders
   and edits them in existing lists.
3. Same pattern for one more pair as proof it generalizes:
   `CHANGE_MP` (signed amount) aliasing DRAIN_MP/RESTORE_MP.
4. Validator: `deprecatedBy` entries pass validation; an info line counts
   deprecated-command usages across data files.

## Don't

- Do NOT rewrite existing data files to the new commands in this task —
  that migration is its own reviewable change later.
- Do NOT remove any handler or registry entry.
- Never regenerate `tools/golden/battle.log`; the alias handlers must keep
  event emission identical (G2 is the proof).

## Acceptance

- [ ] CHANGE_ITEM and CHANGE_MP work in a flow phase and in a map/common
      event (via the A4b bridge)
- [ ] Old ids still validate and run; deprecated ids absent from the ADD
      palette, present when editing existing data
- [ ] G1 + G2 green, G3 green
- [ ] PR checklist filled in
