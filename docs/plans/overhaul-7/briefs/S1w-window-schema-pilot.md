# S1w: Window Schema + Pilot Scene Conversion

**Context:** Read SPEC.md S7. Defines the `windows` array schema for
`data/scenes.json` and converts ONE pilot scene from hand-drawn Lua to
data-authored windows.

**Role:** local agent; pilot-scene choice (items vs. status) and the
UI-golden trace regen both need owner sign-off.

## Acceptance Criteria
- [ ] Window schema per SPEC S7: `{id, rect, visible, content:[...]}` with
      content block types `text`, `list`, `gauge`, `image`. Exprs evaluate
      in the existing sandboxed hook env (`v.*`, formulaEngine) — no new
      expression language. Unknown block types fail soft; unknown optional
      fields ignored.
- [ ] `presentation/window_renderer.lua` gains a generic
      `drawWindowFromData` path driven entirely by the schema.
- [ ] Pilot scene converted: `items` by default; if its Lua drawing is
      entangled with the battle item-submenu code, fall back to `status`
      and report why. The replaced Lua drawing code is DELETED, not left
      as a dead path.
- [ ] Scene canvas (`tools/editor/js/scene-canvas.js`) renders the
      data-authored windows click-to-edit; `window-editor.js` edits
      content blocks. Editing rect in the canvas round-trips to
      scenes.json.
- [ ] Validator: window `id` uniqueness per scene, term-key refs in
      `text` blocks resolve, gauge exprs parse — failures fail G1.
- [ ] Pilot scene's UI-golden trace regenerated (sanctioned; owner reads
      the diff). Every other scene's trace byte-identical.

**Gates:** G1, G2 byte-identical, G3 (one sanctioned regen + all others
strict).
