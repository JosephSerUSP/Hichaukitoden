# E0: Command-list category color coding

**Context:** SPEC S5 item 1. `tools/editor/js/events.js`'s `renderCommandList`
already color-codes comments green (`renderCommentRow`). Extend that with a
single, reusable `category → color` map.

**Role:** Jules-shippable (editor-only, no engine/data changes required).

## Acceptance Criteria
- [ ] Define one `category → color` map in `events.js` (or a small shared
      constants module), not per-renderer inline colors.
- [ ] Apply it to every place a command row gets rendered: the plain-line
      path, `renderChoiceBlock`, `renderConditionalBlock`, `renderGenericBlock`
      — grep `renderCommentRow|renderChoiceBlock|renderConditionalBlock|renderGenericBlock`
      in `events.js` to find all call sites; a fix that only touches the
      plain-line path will look inconsistent inside CHOICE/IF bodies.
- [ ] Cover at minimum: comments (existing green, unchanged), variable/flag
      commands (red), UI/media/scene commands — `category: "UI"` in
      `engine.json` (teal), and a sensible default for uncategorized/`Other`.
      Verified fact: `SET_VAR` currently lives in `Flow Control` beside
      `IF`/`CHOICE`, so category-only coloring cannot make variables red.
      Recommended fix (SPEC S5.1): add a `Variables` category in
      `data/engine.json` and move the var/flag commands into it, updating
      the `categoryOrder` array in `events.js` (line ~267) so the command
      palette groups it sensibly. If you instead keep categories unchanged,
      support per-command-id color overrides on top of the category map —
      pick one, don't do both.
- [ ] Colors match the existing Windows-98-chrome CSS variable palette in
      `tools/editor/css` — don't introduce a clashing ad-hoc palette.
- [ ] Zero console errors; command list still fully functional (add/edit/
      delete/reorder all still work).

**Gates:** G1 (required if you take the recommended `Variables`-category
route, since that edits `data/engine.json`), G3 (visual —
open the editor, load a scene/flow with a mix of command categories, confirm
colors render and are readable against both selected/unselected row states).
