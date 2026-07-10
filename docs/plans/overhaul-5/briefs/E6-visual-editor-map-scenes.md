# E6: Visual scene editor — Map-kind scenes

**Context:** SPEC S4. Map scenes are not window-based: they render tiles,
camera, actors and triggers through the renderer's map path, and
`tools/editor/js/map-editor.js` already has substantial tile/event authoring
(including a right-click context menu — see its `addItem('✏️ Edit Event...')`
usage). This brief extends the E5 visual-editing interaction model to
Map-kind scenes *without* forcing map content through the window-event
preview, and without duplicating what map-editor.js already does.

**Role:** local preferred. **Sequenced after E5** — the interaction pattern
(canvas + right-click context menu + property forms) must be proven there
first, and this brief reuses its primitives.

**First step is reconnaissance, not code:** inventory what `map-editor.js`
already covers (tile painting, event placement/editing, trigger editing —
where, in which functions) and what a Map-kind entry in `data/scenes.json`
does or doesn't exist yet (see `docs/plans/overhaul-4/future-map-kind.md`
for the owner's direction on the future map scene kind — read it; if the
map kind itself hasn't been introduced in engine data yet, this brief's
scope is the *editor-side unification only* and must say so in its PR
rather than inventing engine-side map-scene semantics on the fly).

## Acceptance Criteria
- [ ] From the unified Scenes tab, selecting a Map-kind scene (or the map
      editing surface, if map scenes aren't yet first-class in scenes.json —
      per the recon above) shows the map canvas: tilemap + actor/trigger
      markers, reusing map-editor.js rendering. No reimplementation of tile
      drawing.
- [ ] Right-click interaction matches E5's model (same context-menu
      primitive, same look): on an actor/trigger → edit its properties and
      its event command list (the existing event modal); on empty ground →
      add actor/trigger/event options as map-editor.js supports today.
- [ ] Any window-based overlays a map scene *does* declare (e.g. a HUD
      window in windowLayout, if the map kind gains hooks later) render via
      E5's preview path on top of the map canvas — but do NOT invent map
      hooks to make this true; only wire it if the data already supports it.
- [ ] No regression to the existing standalone map editor workflows —
      map-editor.js's current entry points keep working.
- [ ] Zero console errors; saves round-trip.

**Gates:** G1, G3.

**Non-goal (SPEC S7):** full parity between map and window-scene editing.
Ship the consistent interaction model; deep map-editing improvements are
iterative follow-ups.
