# E12: Reusable Window Editor

**Context:** Owner feedback 12.07.2026. Overhaul 5's window vocabulary has
grown a real registry of reusable pieces — `windowLayout` entries
(geometry/style), the `partyGrid` style + `presentation/actor_status.lua`
(the one shared party-member cell), `layout.gauges` (declarative label+bar
pairs), `layout.pages`/`pageFormula` (paged panels like the promoted status
scene) — but the only way to edit any of it is hand-editing
`data/engine.json`. E5 built a canvas + right-click editing model for a
*scene's* windows; this brief is the same interaction model applied to the
`windowLayout` **registry itself**, independent of any one scene — a
window editor, not a scene editor (the owner's framing; don't blur the
two). Read `E5-visual-scene-editor.md` first — this brief reuses its
canvas/context-menu/drag-resize primitives rather than rebuilding them.

**Role:** local preferred (needs `lovec.exe` + a browser, same as E5).
**Sequenced after E5's primitives exist** — this is not a green-field editor
surface, it is E5's toolkit pointed at a different data root.

## Scope decisions (settled, don't relitigate)

- **Every `windowLayout` entry is in scope**, not a curated subset — this
  tab is "the windowLayout registry, visually," matching the Effect
  Types/Trait Codes registry precedent already in the Engine editor. A
  window nobody's scene currently opens is still editable here (e.g. while
  designing a new reusable piece before wiring it up).
- **Preview content is a synthetic, editor-local "mock binding"** — never
  written to `data/*.json`. Per window being edited, the author picks what
  to preview against: a list source (`party`, `inventory`, `static:a,b,c`,
  a small config-like array) for list/partyGrid/roulette/confirm styles, or
  sample `{expr}`-bearing text for panel/frame. This is what makes a
  never-yet-wired-up window previewable at all. Where the window **is**
  already opened by a real scene (found the same way E5's
  `scanForWindowRefs` finds `OPEN_WINDOW` references, extended to scan
  *all* scenes, not one), surface a **"View in Scene"** link that jumps
  into the existing E5 canvas for that scene with this window selected —
  do not build a second real-content-rendering path; that one already
  exists and is correct by construction.
- **Dedicated widgets for the newer vocabulary**, not a JSON escape hatch:
  a gauge-list editor (add/remove rows: label, value formula, max formula,
  x/y/width/color/fill), a page tab strip for `layout.pages` (add/remove
  page, edit `pageFormula`, edit each page's property overrides including
  its own gauges), a `gridColumns` field for `partyGrid`. Mirrors the
  polish E0–E3 gave the command list — this tab IS the authoring surface
  for these features now, it should be complete, not a stopgap.
- **Canvas shows one window in isolation** by default (not a composed
  scene) — centered at its own declared size, nothing else drawn around
  it. This is the core "not a scene editor" decision from the owner.

## Part 1 — Headless single-window preview (engine side)

- [ ] New CLI mode, e.g. `lovec.exe . preview-window <windowId>
      [mockSpecJSON]`, reusing `makeHarnessSession` (factor further if
      needed) but **skipping `scene_host.push`/hooks entirely** — a raw
      `windowLayout` entry has no scene, so build a minimal
      `state.winState[windowId]` directly from `mockSpecJSON` (open=true,
      listId/text/cursor as specified) and render just that one window.
- [ ] `window_renderer.lua` needs a single-window entry point (e.g.
      `wr.drawOne(windowId, layout, mockState, ctx, env)` and a matching
      `wr.resolveOne(...)` for the JSON metadata) — reuse the existing
      `drawWindow`/list-resolution internals, don't fork them. `layout`
      here is looked up directly from `engine.json → windowLayout`, not
      from any scene's hook-built state.
- [ ] `mockSpecJSON` shape mirrors what a scene's hooks would have set:
      `{ listId, format, sprite, gaugeValue, gaugeMax, text, cursor }` —
      whatever the window's style needs. Missing/absent fields degrade
      gracefully (empty list, blank text), same "never crash, show the
      error" discipline as E5's `preview-scene`.
- [ ] Same 1:1 rendering principle as E5: PNG-embed the real engine frame,
      not a JS reimplementation. Deterministic (seeded), errors become a
      structured payload.

## Part 2 — Server plumbing

- [ ] `tools/editor/server.js`: `GET /preview-window?id=<id>&mock=<json>`
      invokes Part 1's CLI mode the same way `/preview-scene` invokes
      `preview-scene` (argument-list `execFile`, no shell, id
      whitelisted, timeout, structured failure on missing LOVE).
- [ ] A way to enumerate, for a given window id, which scenes reference it
      (extend or reuse `scanForWindowRefs`'s pattern server-side or
      client-side — client-side is fine since `dbPayload.scenes` is
      already in the browser) for the "View in Scene" link and for
      Remove-Window warnings (a shared window can now be referenced by
      **multiple** scenes — the warning must list all of them, not just
      one).

## Part 3 — Editor: the Windows tab

- [ ] New top-level tab (Engine Editor or its own window, matching
      existing chrome) listing every `windowLayout` key. Selecting one
      opens the canvas + inspector, reusing E5's `scene-canvas.js`
      primitives (drag-move, drag-resize, right-click context menu,
      inspector dock) rather than duplicating them — factor shared pieces
      out of `scene-canvas.js` if the reuse is clean; if it's awkward,
      note the duplication in the PR rather than blocking on a forced
      abstraction.
- [ ] Per-window mock-binding controls (list source picker / sample text)
      driving Part 2's endpoint; changing the mock re-fetches the preview,
      same "Save & Refresh" staleness caveat E5 already established for
      content (geometry edits still overlay live).
- [ ] Property form: existing fields (x/y/width/height/style/title,
      contentX/contentY/lineSpacing, portrait/portraitX/portraitY) plus
      the ones E5 didn't need (visibleRows, rowPitch, spriteSize,
      gaugeHeight, emptyText, gridColumns).
- [ ] Gauge editor: add/remove rows, each with label/value/max as text
      inputs (formulas), x/y/width as numbers, color/fill as simple RGB
      pickers or raw arrays.
- [ ] Page editor: tab strip over `layout.pages` (add/remove page), a
      `pageFormula` text field, and — per page — the same property form
      recursively (a page override is itself a partial layout).
- [ ] "+ New Window": id prompt + style presets (list/panel/confirm/
      roulette/partyGrid — the same preset set E5's Add Window uses),
      creates an empty `windowLayout` entry, no scene wiring (that's a
      scene's job via its own hooks, unchanged).
- [ ] Remove Window: warn with the full list of referencing scenes+hooks
      (per Part 2) before deleting, exactly like E5's existing warning but
      scanning every scene instead of one.
- [ ] "View in Scene" (when reference scan finds at least one): navigates
      to the Scenes tab, selects that scene, and pre-selects this window
      in E5's canvas — a thin trigger, not new rendering code.

## Non-goals

- No new list-source types, no scenes.json/hook vocabulary changes.
- Map-kind scenes: still out of scope (per E6/future-map-kind.md).
- Not a scene composer — arranging multiple windows together relative to
  each other is what the Scenes tab / E5 already does; this tab edits one
  window's own geometry and content rules.

**Gates:** G1 (new CLI mode + registry additions must validate), G3
(editor — new tab, mock-binding preview, gauge/page editors, create/
delete, View in Scene link, zero console errors). No G2 impact expected
(draw/editor-only); no UI-golden impact expected (no scene or hook
changes) — run both anyway, gates are cheap.
