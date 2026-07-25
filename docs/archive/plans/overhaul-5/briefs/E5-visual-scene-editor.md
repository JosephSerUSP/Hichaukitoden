# E5: Visual scene editor — canvas preview + right-click editing (non-map)

**Context:** SPEC S2 + S3. The flagship item of overhaul 5: a canvas in the
Scenes tab that shows what a scene's windows actually look like — real
content, not empty rects — with right-click editing. Built on overhaul-4's
data model: `engine.json → windowLayout` (geometry), scene hooks
(`OPEN_WINDOW`/`SET_LIST`/`SET_TEXT`/`SET_CURSOR`/`FOCUS_WINDOW` events),
and the D13 generic window renderer proving the event stream fully
describes a scene's UI.

**Role:** LOCAL ONLY, strongest available agent. Needs the LOVE runtime
(`lovec.exe`) and a browser; touches engine (`main.lua` preview command),
server, and editor. The orchestrator reviews this personally before merge.

## Part 1 — Headless preview command (engine side)

- [ ] A new CLI mode, e.g. `lovec.exe . preview-scene <sceneId>`, that:
      builds a mock session (reuse the `mockCtx`/mock-item/mock-crafter
      construction already in `main.lua validateScenes()` and/or the
      golden-ui harness's session setup — the golden-ui path at
      `main.lua:~129-243` already does almost exactly this; factor, don't
      duplicate), pushes the scene via `scene_host`, runs `on_enter`, and
      prints a single JSON document on stdout between `PREVIEW BEGIN` /
      `PREVIEW END` markers: the scene's resolved window state (per window:
      id, open/closed, rect from windowLayout, resolved list rows, resolved
      text, cursor index, focus) — i.e. the *materialized* result of the
      window-event stream, not the raw events.
- [ ] Resolved means resolved: `SET_LIST` sources (`inventory`, `party`,
      `config:...`, `static:...`, `v:...`) expanded to actual row strings via
      the same code paths the in-game generic renderer uses; `SET_TEXT`
      interpolations evaluated. If the engine's JSON-encoding facilities are
      limited, a minimal hand-rolled encoder for this fixed shape is fine —
      no new dependencies.
- [ ] Deterministic: seed `math.random` the way the golden harness does, so
      repeated previews of an unchanged scene are identical.
- [ ] Errors (bad hook, missing window, formula failure) must produce a
      structured error in the JSON payload, not a crash — the editor shows
      the error on the canvas; a broken scene is precisely when the author
      needs the preview most.

## Part 2 — Server plumbing

- [ ] `tools/editor/server.js` gains an endpoint (e.g.
      `GET /preview-scene?id=N`) that invokes the preview command
      synchronously against the *saved* data files and returns the JSON.
      Document the staleness caveat in the UI: the preview reflects the last
      save, not unsaved editor state (v1 accepts this; a "save then preview"
      affordance is acceptable).
- [ ] Windows path handling: the server must locate `lovec.exe` (config or
      PATH); degrade gracefully (canvas shows "preview unavailable — LOVE
      not found") rather than erroring the whole tab.

## Part 3 — Canvas + interaction (editor side)

- [ ] A canvas panel in the unified Scenes tab rendering the preview JSON at
      the game's native resolution (read tile/px constants from the served
      `engine.json`, do not re-hardcode; integer-scale to fit the panel).
      Draw window frames, titles, list rows, cursor marker, text — a
      readable schematic of the real UI, not a pixel-perfect clone (fonts
      will differ; that's fine, geometry and content must be right).
- [ ] Right-click a window → context menu: **Edit Properties** (form for
      that `windowLayout` entry — rect, style; reuse `widgets.js` form
      fields), **Remove Window** (deletes the layout entry; if any hook
      still references the id in `OPEN_WINDOW`/`SET_*` commands, warn and
      list the offending hooks instead of silently orphaning), **Jump to
      Hook** (focuses the existing command-list editor on the `OPEN_WINDOW`
      command that opens this window).
- [ ] Right-click empty canvas → **Add Window**: prompts for an id + preset
      shape (list / panel / confirm — editor-side presets, NOT engine-side
      kind hardcoding), creates the `windowLayout` entry at the click
      position, and appends an `OPEN_WINDOW` command to the scene's
      `on_enter` hook. Marks the editor dirty; a normal save persists both.
- [ ] Edits made in the command-list editor and edits made on the canvas are
      the same data — no divergence, no second source of truth. After a
      save, a refresh control re-runs the preview.
- [ ] Drag-to-move/resize window rects: in scope only if the above is done
      and solid; do not let it delay the brief (SPEC S3).
- [ ] Zero console errors; Save round-trips; `love . validate` green with
      canvas-created windows/commands.

**Gates:** G1, G3, and UI-golden (`check-ui`) — the preview command must not
disturb the golden harness's determinism; all `scene_*.log` references stay
byte-identical.

**Out of scope:** Map-kind scenes (E6). Battle-scene specifics beyond what
the generic window renderer already covers. Any change to hook semantics.
