# C7 — Actor Skills/Passives as "+ Add" rows

- Branch: `o3/c7-add-skill-rows`  |  Runtime needs: G3
- Read first: SPEC.md Ground rules; FEEDBACK.md round 2, editor item 2

## Goal
The Actors form lists EVERY skill/passive as a checkbox (buildChecklistField
in tools/editor/js/widgets.js). Replace with compact "+ Add" row lists like
the Effects/Traits editors: one row per assigned entry (dropdown of
skills/passives + × delete), plus "+ Add Skill" / "+ Add Passive" buttons.

## Do
- Reuse makeListBox/makeSelect/makeRowDeleteBtn/makeAddRowBtn.
- No data shape change (arrays of ids stay arrays of ids).
- Keep buildChecklistField for the System-tab uses that still fit it
  (summoner spells, bonus items) — only Actors' skills/passives change.

## Acceptance
- [ ] Add/remove skill and passive on an actor round-trips through Save
- [ ] G3 green; PR checklist filled in
