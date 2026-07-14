# E10: title screen — New Game / Continue / Exit selector

**Context:** Owner feedback 10.07.2026 item 10 (FEEDBACK.md). The title
screen is currently "Press ENTER to start / ESC to exit"
(`renderer.drawTitle` + hardcoded key handling). It needs a proper
three-option selector.

**Role:** local preferred.

**Design constraint:** the title scene already exists in `scenes.json`
(built-in, id `title`) with hooks. Extend it as data: the selector is a
window (`OPEN_WINDOW`/`SET_LIST static:...`/`SET_CURSOR` + windowLayout
entry), cursor movement via `on_up`/`on_down`, dispatch via `on_select` —
the same pattern the converted menus use. Title is a BUILT-IN scene:
zero-SCRIPT applies (o4 SPEC S6); if the vocabulary is missing something,
fix the vocabulary, don't reach for SCRIPT.

**Save-data dependency (feedback item 11):** save/load does not exist yet.
"Continue" must be present but degrade gracefully: shown dimmed/disabled
(and skipped or refused on select) until a save system lands in a future
round. Do NOT implement save data in this brief.

## Acceptance Criteria
- [ ] Title shows a New Game / Continue / Exit selector (labels from
      terms.json), navigable with up/down, confirmed with ENTER/SPACE.
- [ ] New Game starts the game exactly as ENTER does today.
- [ ] Continue is visibly disabled and does nothing (or shows a small
      "no save data" notice) — no save system yet.
- [ ] Exit quits (as ESC does today); decide and document what bare ESC on
      the title does now (recommend: moves cursor to Exit rather than
      instant-quitting).
- [ ] Implemented in scene data + windowLayout as far as the vocabulary
      allows; any hardcoded title key-handling in `main.lua` that the hooks
      supersede is removed (fallback rule: hooks present = legacy dead).
- [ ] Title `goldenScript` updated to drive the selector; `scene_title.log`
      regenerated with line-by-line justification. All other references
      byte-identical.
- [ ] G3: labels editable in the editor (terms + scene hooks).

**Gates:** G1, G3, UI-golden (title reference regenerated + justified).
