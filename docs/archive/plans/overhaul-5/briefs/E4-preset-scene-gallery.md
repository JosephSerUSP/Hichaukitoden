# E4: Preset scene gallery + shared template registry

**Context:** SPEC S6. "+ Create Scene" in `tools/editor/js/engine-editor.js`
currently pushes one hardcoded blank scene shape (and, until D13's cleanup
lands, a stale crafting-flavored one — check the current state of that
handler first; D13 may have already blanked it). Replace it with a
data-driven template gallery. **This brief owns the template registry schema
and loader; E3 consumes it.**

**Role:** Jules-shippable (editor + static JSON; no engine changes).

## Acceptance Criteria
- [ ] A template registry at `tools/editor/templates/scenes/*.json` — one
      file per template, each a full scene object matching `data/scenes.json`
      entry shape minus `id` (name, kind, config, hooks, goldenScript
      optional), plus a small metadata block the gallery displays (e.g.
      `_template: { label, description }` — pick a key that clearly can't
      collide with real scene fields, and strip it on instantiation).
- [ ] Served to the browser by `tools/editor/server.js` (an endpoint that
      lists + returns template files; follow how DATA_FILES are already
      served rather than inventing a new pattern). Templates are read-only
      from the editor's perspective — Save Database must not write them.
- [ ] Ship at least two templates: **Blank** (empty hooks, minimal config)
      and **Crafting** — a faithful copy of the post-D13 Item Creation scene
      from `data/scenes.json` (kind `menu`, SCRIPT-based yield logic,
      windowLayout-referencing hooks). Note: if the crafting template
      references `windowLayout` entries in `engine.json`, instantiating it
      needs those to exist — decide and document whether the template
      carries its own windowLayout entries to merge in, or whether v1 simply
      documents the dependency; don't silently create broken scenes.
- [ ] "+ Create Scene" opens a picker (list with label + description) built
      from the registry; choosing one deep-clones the template, strips
      template metadata, assigns a fresh numeric id, and selects the new
      scene for editing.
- [ ] Adding a future preset requires only dropping a JSON file in the
      templates directory — zero JS changes (no per-template `if` branches;
      that's the D13 lesson applied to the editor).
- [ ] Zero console errors; created scenes validate (G1) and save round-trip.

**Gates:** G1 (a scene created from each template must pass
`love . validate`), G3.
