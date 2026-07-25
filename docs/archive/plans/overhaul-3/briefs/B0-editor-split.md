# B0 — Split the editor into modules (enabler — do early)

- Branch: `o3/b0-editor-split`
- Runtime needs: G3 (browser)
- Depends on: nothing. Serializes with ALL other editor tasks: nothing else
  may touch `tools/editor/index.html` while this runs.
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules

## Goal

`tools/editor/index.html` is ~4k lines and the merge bottleneck for every
editor task. Split the inline script into modules so later tasks can run in
parallel.

## Do

- Extract the inline `<script>` into plain scripts served by the existing
  static server, loaded in explicit order from `index.html`:
  `js/state.js` (dbPayload, dirty tracking), `js/net.js` (fetch/save/assets),
  `js/widgets.js` (makeSelect, list editors, pickers, schema fields),
  `js/database.js` (DB modal tabs/forms), `js/engine-editor.js`,
  `js/map-editor.js` (canvas/tree/paint), `js/events.js` (command list +
  command modal + event modal).
- Keep every `onclick="..."` attribute working: expose the handlers on
  `window` (e.g. `window.setDbTab = setDbTab`) or convert to addEventListener —
  your choice, but be consistent.
- Zero behavior changes. Zero renames beyond what the split forces.

## Don't

- No refactors of logic, no new features, no formatting churn inside moved
  code (move blocks verbatim where possible so diffs stay reviewable).

## Acceptance

- [ ] G3 green across a full click-through: every DB tab, Engine window tabs,
      map paint, event modal open/edit/save, Test Play button, save round-trip
      (`/save` then reload page, data intact)
- [ ] `index.html` contains no inline script beyond the loader tags
- [ ] PR checklist filled in
