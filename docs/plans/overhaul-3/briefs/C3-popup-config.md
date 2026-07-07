# C3 — Configurable damage popup text and colors

- Branch: `o3/c3-popup-config`
- Runtime needs: G1 + G2; G3 for the editor side
- Depends on: nothing beyond the current integration branch
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules; `BIBLE.md`
  (no hardcoded UI values)

## Goal

The damage/heal popup's text format and colors are hardcoded in the
renderer — the owner dislikes the "-" prefix on damage numbers and cannot
change it (feedback item 5 in `docs/plans/overhaul-3/FEEDBACK.md`).

## Do

1. Find the popup formatting/colors in `presentation/` (damage popups,
   heal popups, crit/miss variants if present).
2. Move them into `data/system.json → battle_screen.popup`:
   `damageFormat` (e.g. `"-{0}"` — the owner will likely set `"{0}"`),
   `healFormat` (e.g. `"+{0}"`), `damageColor`, `healColor` as rgb01
   arrays, and any existing hardcoded variant styles. Lua reads them with
   the current values as fallbacks so old payloads keep working.
3. Editor: add the new keys to `CONFIG_SCHEMA` (labels + help strings) so
   they appear in the existing Damage Popup Settings modal
   (`tools/editor/js/engine-editor.js`) — colors use the existing color
   widget pattern (see `ui.textPalette`).

## Don't

- No change to popup physics (that's already configurable).
- No new data files (stay inside system.json → both manifests untouched).
- The battle log line format ("- {0} takes {1} damage.") is already a term
  (`battle.takes_damage`) — leave it; this task is the floating popup only.

## Acceptance

- [x] Changing damageFormat/colors in the editor changes the in-game popup
- [x] Defaults reproduce today's exact appearance; G2 stays green
- [x] G1 + G3 green
- [x] PR checklist filled in
