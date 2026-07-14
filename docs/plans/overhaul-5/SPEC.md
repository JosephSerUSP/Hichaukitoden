# SPEC — Visual Scene Authoring & Eventing Readability (Overhaul 5)

Audience: an agent executing ONE task. Your brief tells you which sections to
read. Do not change this spec; if your task conflicts with it, stop and report.

Integration branch: `fable-5-overhaul-5`. Ground rules and gates: identical to
overhaul-3's SPEC §Ground rules and overhaul-4's SPEC preamble. Integrator
protocol: `docs/ORCHESTRATION.md`.

## S0 — Why, and the reference frame

Overhaul 4 made *scenes* data: `data/scenes.json` hooks, a generic UI command
vocabulary (`OPEN_WINDOW`/`SET_LIST`/`SET_TEXT`/`SET_CURSOR`/`FOCUS_WINDOW`),
window geometry in `engine.json → windowLayout`, a UI-golden harness that
proves scene execution is deterministic and replayable, and (D13) a generic
window renderer with **zero** scene-kind-specific hardcoding — crafting is
now a plain data-driven "extra" scene using `SCRIPT` as its escape hatch.

That is the necessary precondition for this round, not the goal. The owner's
recurring complaint (overhaul-3 FEEDBACK, overhaul-4 FEEDBACK, this round's
FEEDBACK) is that **authoring is still hard to read and hard to see**: scenes
are edited as command lists with no visual feedback, and the command-list UI
itself has accumulated friction (inline buttons, no color, no keyboard model).
Overhaul 5 is the authoring-UX round built on overhaul 4's data model.

## S1 — Two independent tracks

**Track A — Visual Scene Editor** (S2–S4): a canvas that shows what a scene's
windows actually look like, editable by right-click, backed by the same data
D13 already made generic. This is the deep, local-only, highest-value item.

**Track B — Event-list readability** (S5): four small, mostly independent UI
fixes to `tools/editor/js/events.js`'s `renderCommandList` and friends. Low
risk, high cumulative payoff, Jules-shippable.

These tracks do not block each other. Track B can ship first and fast.

## S2 — Visual Scene Editor: rendering strategy

The core design question: how does the editor know what a scene's windows
*actually* look like, given that window content depends on hook execution
(`SET_LIST`, `SET_TEXT`, formula-driven `SET_CURSOR`, etc.), not just static
`windowLayout` rects?

**Two candidate strategies — pick (B).**

- **(A) Static layout preview.** Render `engine.json → windowLayout` rects
  directly: fast, zero engine dependency, but shows empty boxes, not real
  content (no list rows, no formatted text, no cursor position). Good enough
  for "where is this window," useless for "does this look right."
- **(B) Interpreted preview (recommended).** Shell out to the real engine —
  `lovec.exe . <a new headless preview command>` — with a scene id and a mock
  session (reuse the `mockCtx`/`mockItem`/`mockCrafter` construction pattern
  already in `main.lua`'s `validateScenes()`), run the scene's `on_enter` hook
  through `interpreter.runImmediate`, and dump the resulting window-event
  stream (`open_window`/`set_list`/`set_text`/`set_cursor`/`focus_window`) as
  JSON on stdout. The Node editor server (`tools/editor/server.js`) invokes
  this synchronously (same pattern as any other `love . validate*` gate) and
  the browser-side canvas renders that JSON.

  This is exactly the "interpret the Lua in JS for an accurate preview" idea
  overhaul-4 SPEC S9 flagged as deferred-but-tractable — except it does NOT
  require a JS reimplementation of the interpreter/formula engine (which
  would drift from the Lua original and rot). Reusing the real engine as a
  subprocess is slower per-preview but correct by construction, and the UI-
  golden harness already proves this execution path is deterministic and
  side-effect-scoped to a mock session.

  Only `on_enter` needs to run for the initial preview. A "step" control that
  re-runs with a synthetic input (`on_select`/`on_up`/`on_down`/...) appended
  is a natural follow-up but not required for v1 — see S6.

**Window rects come from `windowLayout`; window contents come from the
interpreted event stream.** The canvas overlays one on the other.

## S3 — Visual Scene Editor: interaction model

- **Canvas** renders at the game's native resolution (same tile/px constants
  `presentation/ui.lua` uses — read them from `engine.json`, do not
  re-hardcode).
- **Right-click a window** → context menu: *Edit Properties* (rect/style form
  for that `windowLayout` entry — reuse existing form-field widgets from
  `tools/editor/js/widgets.js`, do not build new input primitives),
  *Remove Window* (deletes the `windowLayout` entry; warn if `OPEN_WINDOW`
  commands still reference it rather than silently orphaning them),
  *Jump to Hook* (scrolls the existing command-list editor to the `OPEN_WINDOW`
  command that opens this window, for commands the visual editor doesn't yet
  cover).
- **Right-click empty canvas** → *Add Window*: creates a new `windowLayout`
  entry at the click position and appends an `OPEN_WINDOW` command to the
  scene's `on_enter` hook. Default size/style comes from a small preset list
  (list, panel, confirm — mirroring the `windowDefs` shapes D13 deleted from
  `engine/scenes/crafting.lua`, now generalized as editor-side presets, NOT
  reintroduced as engine-side scene-kind hardcoding).
- **Drag to reposition/resize** a window rect is in scope for v1 if time
  allows; it is a strict UI enhancement on top of the Edit Properties form
  and not a blocker — do not let it block shipping right-click editing.
- This is **additive** to the existing command-list editor (SPEC-4 S8), not a
  replacement. Anything not expressible visually (formulas, `IF` branches,
  `SCRIPT` blocks) stays in the command-list view; the visual editor is a
  companion lens onto the same `scenes.json` data, not a new source of truth.

## S4 — Map-kind scenes: explicitly harder, explicitly separate

Map scenes are not window-based: they render a tile grid, camera, actor
sprites, and triggers via `presentation/renderer.lua`'s map path and
`tools/editor/js/map-editor.js`'s existing tile/event authoring tools — this
predates overhaul 4 and is **not** expressed as `OPEN_WINDOW`-style events.
Do not try to force map content through the S2 window-event-stream preview.

For Map-kind scenes, the "visual editor" is: the canvas shows the tilemap +
actor/trigger markers (reuse what `map-editor.js` already draws — do not
reimplement tile rendering), and right-click there edits actor/trigger
placement and their associated event lists, not window layout. This is
functionally close to what `map-editor.js` may already do for the *map data*
layer (check before assuming a gap); the new work is specifically wiring
Map-kind `scenes.json` entries into the same right-click-to-edit model the
non-map visual editor uses, so the interaction model feels consistent even
though the underlying content differs.

**This is its own brief (E6), sequenced after the non-map visual editor (E5)
proves the interaction pattern.** It may slip a milestone without blocking
E5. Full parity between Map and window-based scene editing is a non-goal for
v1 — see S6.

## S5 — Event-list readability (Track B)

All four items below touch `tools/editor/js/events.js`'s `renderCommandList`
and the three specialized block renderers it delegates to (`renderCommentRow`,
`renderChoiceBlock`, `renderConditionalBlock`, `renderGenericBlock`) — the
✏️/❌ buttons and per-row styling are currently duplicated across all of
them (grep `✏️` in `events.js`: at least 4 call sites). Any change to row
chrome must be applied at all of them, not just the plain-command-line path,
or it will look fixed in the common case and inconsistent inside CHOICE/IF
blocks.

1. **Category color coding.** `engine.json → commands[].category` already
   exists (`Message`, `Flow Control`, `Party`, `Battler`, `Progression`,
   `Advanced`, `UI`, `Other`, plus the deprecated `Crafting`). Comments are
   already rendered green (`renderCommentRow`) — extend that pattern with one
   `category → color` map defined once, not per-renderer. One verified
   wrinkle: the owner wants variables red, but `SET_VAR` currently sits in
   `Flow Control` beside `IF`/`CHOICE`, so category-only coloring can't
   isolate it. Either (a) add a `Variables` category in `engine.json` and
   move the var/flag commands into it (also update the `categoryOrder` array
   in `events.js` and confirm the command palette grouping still reads
   sensibly — this is the RPG-Maker-conventional answer and the recommended
   one), or (b) keep categories as-is and allow per-command-id color
   overrides on top of the category map. Media/scene commands (`UI`
   category: `OPEN_WINDOW`, `PLAY_ANIM`, etc.) → teal. Exact hex values are
   an editor-CSS-variable decision, not a spec mandate — match the existing
   Windows-98-chrome palette in `tools/editor/css`.
2. **Row striping.** Alternate background color for even/odd rows in the
   command list, applied consistently across indent levels and inside nested
   blocks (CHOICE/CONDITIONAL_BRANCH bodies).
3. **Context menu + keyboard model**, replacing the inline ✏️/❌ buttons:
   - Right-click a row → context menu with Edit / Delete / Copy / Cut / Paste
     (and Duplicate, if cheap).
   - Space (on a focused row) → Edit. Delete key → Delete.
   - Ctrl+C / Ctrl+V → copy/paste one or more selected commands as JSON,
     inserted at the current cursor position within the same list.
   - Shift+Up / Shift+Down → extend a contiguous selection range from the
     currently focused row. Plain Up/Down moves focus without a mouse click
     currently being required — check whether row focus exists at all today;
     if not, this brief includes adding a focus concept to the list (e.g. a
     `tabindex` + visual focus ring per row), since selection has nothing to
     range from otherwise.
   - This needs real keyboard-event plumbing (the editor is a set of DOM
     widgets, not a canvas) — `keydown` handlers scoped to the command-list
     container, careful not to steal keystrokes from open modals/inputs
     elsewhere on the page.
4. **Load from template / reset to default**, replacing bare "Clear." For a
   built-in scene's hook with a legacy Lua fallback (overhaul-4 SPEC S2's
   fallback rule), "reset" should mean *delete the override, fall back to
   legacy* (this mechanism may already exist per-hook for battle phases —
   check `renderBattleFlowsEditor`'s "Remove Override" button before
   reinventing it). For hooks/scenes with no legacy fallback (all "extra"
   scenes), "load from template" should offer named starter templates from a
   small template library (see S4 of the preset-scenes item below — this and
   the preset-scenes gallery should likely share one template data source,
   not two).

## S6 — Preset custom scenes gallery

"+ Create Scene" in the unified Scenes editor (`tools/editor/js/engine-editor.js`,
the `addBtn` handler that pushes a hardcoded blank scene shape) currently has
exactly one shape: blank. Generalize it to a small gallery: "Blank" plus a
short list of starter templates, one of which is **Crafting** — now that D13
made Item Creation a plain `kind: "menu"` scene using `SCRIPT` as its only
non-generic content, it is a legitimate, nothing-hardcoded template rather
than a bespoke engine feature.

Templates are **data**, not per-template UI branches: a small JSON registry
(e.g. `tools/editor/templates/scenes/*.json`, one file per template, each a
full scene object shape matching `data/scenes.json` entries minus `id`) that
"+ Create Scene" reads to populate a picker, deep-clones on selection, and
assigns a fresh id. Adding a new preset later should mean "drop a JSON file
in," not "add an `if` branch" — the D13 lesson (kind-specific `if` branches
are what this whole round of scene work has been unwinding) applies here too.

This shares its template-loading mechanism with S5 item 4 — one registry,
two entry points (new scene, reset hook to template).

## S7 — Non-goals this round

- **Full parity for Map-kind visual editing** (S4). Ship the interaction
  model; deep map-content editing quality is iterative.
- **Drag-to-resize/reposition** windows in the visual editor is nice-to-have,
  not required (S3).
- **Audio.** No brief exists yet. See `audio-design-options.md` — this is a
  decision memo for the owner, not an implementation task. Overhaul-4 SPEC
  S9's rule still applies verbatim: no `PLAY_SOUND`/`PLAY_MUSIC` command, no
  stub handlers, until a brief lands with a real handler in the same commit.
- **Multi-scene canvas / scene-graph overview.** The visual editor previews
  one scene at a time; a zoomed-out map of how scenes connect via
  `SCENE_EVENT` push/pop/goto is a plausible future round, not this one.

## S8 — Task decomposition (briefs)

| id | task | track | gates |
|---|---|---|---|
| E0 | Category color coding in command list (S5.1) | B | G1 G3 |
| E1 | Row striping (S5.2) | B | G3 |
| E2 | Context menu + keyboard model, incl. multi-select + clipboard (S5.3) | B | G1 G3 |
| E3 | Load-from-template / reset-to-default for hooks (S5.4) | B | G1 G3 |
| E4 | Preset scene gallery + shared template registry (S6) | B | G1 G3 |
| E5 | Visual scene editor: headless preview subprocess + window canvas + right-click editing, non-map scenes (S2, S3) | A | G1 G3 |
| E6 | Visual scene editor: Map-kind scenes (S4) | A | G1 G3 |
| E7 | Control Variables: multi-assignment SET_VAR + editor row widget | B | G1 G2 G3 + UI-golden |
| E8 | smallBattler damage flash/shake + dead display; flash constants → data | C | G1 G2 + smoke |
| E9 | Game Over scene (data-authored) + defeat flow cleanup | C | G1 G2 G3 + UI-golden |
| E10 | Title New Game / Continue / Exit selector (data-authored) | C | G1 G3 + UI-golden |
| E11 | HEAL absorbs TRAIT_HEAL (delete command, migrate victory flow) | C | G1 **G2 byte-identical** G3 |

Track C (E8–E11) is the 10.07.2026 post-playtest batch — battle/system
polish, independent of Tracks A and B. E8/E10 are independent; E9 and E10
both touch the title/defeat navigation surface — merge serially. E11 is
local-only (golden-sensitive migration). Two recorded directions with no
briefs yet: the Animation System & editor tab (`future-animation-system.md`,
likely overhaul-6's flagship — E8 seeds its data), and save/load scenes
(E10's Continue stays disabled until a future round delivers them).

E0, E1, E2, E4 are independent of each other and of E5/E6; fire in parallel
(E0/E1/E2 all touch `events.js` — work them in parallel but *merge* serially
with a G3 re-check between, same discipline as overhaul-3's A5 batch). E3
consumes E4's template registry and merges after it. E5 is the big local-only
item and should get the strongest available agent + your own review. E6
depends on E5's interaction pattern landing first (S4).
