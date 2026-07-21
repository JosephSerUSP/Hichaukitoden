# Hichaukitoden — Living Spec

The single current-state authority for architecture and design rules.
`BIBLE.md` (root) points here; everything under `docs/plans/` is a
**historical** record of how each overhaul round got us here — read those
for context, never as instructions. If code and this document disagree,
that is a bug in one of them: fix it or flag it, don't silently pick one.

Last consolidated: 2026-07-17 (post overhaul-7 merge to main).

---

## 1. Architecture

### 1.1 Data drives the engine

- **All game content lives in `data/*.json`** — actors, items, skills,
  passives, states, roles, elements, maps, events, commonEvents, quests,
  shops, sounds, themes, terms, animations, scenes, flows, system, engine.
  `data/loader.lua` loads them; Lua never hardcodes content.
- **`data/engine.json` is the registry**: command definitions (id, params,
  contexts, interactive flag), effect types, trait codes, meta keys,
  formula tokens. Adding a command/effect/trait means a registry entry +
  a handler — the validator and the editor pick it up from the registry.
- **Flows are the single source of truth for phase logic.**
  `data/flows.json` maps phases (`battle.victory`, `battle.defeat`,
  `battle.encounter_check`, …) to command lists run in immediate mode by
  `engine/interpreter.lua`. There are no legacy Lua fallback blocks; hosts
  call `flow.run(phase, ctx)` unconditionally and the validator requires
  the phases they depend on to exist and execute.
- **One command language, one interpreter** (`engine/interpreter.lua`).
  Map events, common events, battle phases, and scene hooks all compile
  through it. Interactive commands (TEXT, CHOICE, …) compile to dialogue
  graphs; non-interactive runs compile to immediate-mode blocks
  (RUN_IMMEDIATE bridges mixed lists).
- **Formulas, not scripts** (`engine/formula.lua`): numeric/boolean params
  accept sandboxed expressions over registry-declared tokens
  (`session.encounterRate`, `enemy.maxHp`, …). The sandbox rejects any
  environment access (`os.*` etc.).
- **SCRIPT is a sandboxed escape hatch, rationed.** Default battle phases
  are zero-SCRIPT (the validator enforces it); elsewhere SCRIPT usage is
  counted and reported at every validate run so growth is visible.
  `engine.json scripting.allowRawAccess` defaults to false and the
  validator asserts that.

### 1.2 Presentation

- **Scenes are data** (`data/scenes.json`): `{id, name, kind, hooks,
  scripts, windows}`. Scenes with `"draw": "windows"` are rendered
  entirely from their `windows` array by `presentation/window_renderer.lua`.
- **Battle is the one legacy-drawn holdout**, frozen pending the Summoner
  rework (see `docs/design/summoner-rework.md`). Do not extend the legacy
  renderer; new UI work happens in the windows system.
- **Animations are data** (`data/animations.json`): typed track lists
  (tint, blend, transform, shake, particles, force_field, gradient_map,
  screen_flash). `system.*` reserved entries (damage_flash, shake, death,
  …) must exist and hard-validate; assignable entries soft-validate so new
  track types can ship data-first.
- **Targeting is one resolver** (`engine/targeting.lua`): declarative
  target specs on skills/items, expanded by `targeting.expand` for both AI
  and player paths. `expand` errors on unknown specs; the validator gates
  every spec in data.

### 1.3 Campaign roots (18.07.2026, "no-move" design)

- **`data/` IS the default campaign.** `campaigns/<name>/` directories are
  drop-in alternates carrying the same file set. Nothing else moves.
- Active root resolution (data/loader.lua `resolveRoot`): CLI arg
  `campaign=<name>` > `campaign.json` pointer at the repo root
  (`{"active": "<name>"}`) > `data/`. The dev server's `/data`/`/save`
  endpoints and `engine/config.lua` follow the same root.
- G1 validates whatever root is active. Golden logs (G2/G3) are recorded
  against the default campaign only — run gates with `data/` active.
- **Non-default `campaigns/<name>/` roots are disposable test artifacts**
  of the generation pipeline (21.07.2026 decision). They are not held to
  sync parity with `data/` — a scene/menu feature landing in the default
  campaign does not obligate porting it to `thestra_no_jijou_2/3/4` etc.
  Regenerate them from the pipeline when needed instead of hand-syncing.

### 1.4 Scene layout convention: context-help bar + bottom dock

Every `"draw": "windows"` menu scene shares one skeleton instead of each
scene inventing its own chrome:

- **Top: a "CONTEXT HELP" bar** (style `frame`, full width, docked at
  `y=0`). It never holds a fixed hint string — its `content` text is a
  formula keyed on scene state (`v.state`, `v.combatState`, …) so the same
  window reads as nav hints in one state and as contextual explanation
  (an item/equip description, victory spoils, …) in another. This replaces
  the old pattern of a separate description/info panel next to a static
  "UP/DOWN: select ENTER: use" bar — one window, state-dependent text, no
  redundant real estate. (Applied to the `items` scene's `help` window and
  `battle`'s `battle_help` window during `victory`.)
- **Bottom: a persistent dock**, one of two things depending on scene:
  1. **Persistent party status** — the current/selected member's compact
     status, always visible regardless of what's happening above it.
  2. **Context-aware content laid out like the dialogue box** — left pane
     is an info panel (portrait/name/stat summary), right pane is the
     larger, interactive pane (lists, explanations, previews — anything
     the player can act on lives here, not in the narrow left pane).
  Both variants share the dialogue scene's exact footprint and column
  split: left column width starts from `battle_layout.partyGridColWidth`
  (68px = 8.5 tiles — the same fixed cell width `actor_status.draw` uses
  everywhere else) but widens as needed (currently 9.5 tiles, to fit the
  status dock's stats), right column takes the remaining width. **The
  left column's width is the authority**: if a scene's info panel needs
  more room to read cleanly, widen the shared dialogue footprint to match
  rather than shrinking the info panel's content — don't let two scenes
  drift to two different "narrow left column" widths, and don't let the
  same width live in two places either (`data/engine.json`'s windowLayout
  entry AND a scene's own `rect` both set x/y/w/h — the scene's `rect`
  always wins, so when the shared width changes, both need editing or the
  engine.json one silently does nothing).
- A scene can layer scene-specific chrome above this dock (e.g. status's
  equipment-slot header + portrait), but the dock itself — and the
  context-help bar — should look and behave the same everywhere it's used.

### 1.5 Extensibility (round-wide rule since o7, keep it)

Every schema tolerates unknown future fields: readers ignore keys they
don't understand, validators warn rather than reject on unrecognized
*optional* fields, and new entry types arrive behind `kind`/version
discriminators — old data never needs migrating.

---

## 2. Design rules (from the BIBLE — enforced by review)

### 2.1 Code sharing and reuse (CRITICAL)

No copy-pasted logic or coordinate mappings. Layout systems (party grid,
window geometry) are shared helpers used by exploration menus, battle
consoles, and target overlays alike. Math/physics (gravity, bouncing,
interpolation) lives in general update code, not scattered ad-hoc.
This applies to the editor too: form fields come from the schema layer
(`tools/editor/js/entity-forms.js`, `CONFIG_SCHEMA`), not hand-written DOM.

### 2.2 UI aesthetics

- Rich vertical gradients for major menus — never flat dark overlays.
- Micro-animations: panels slide in/out via timer states.
- Elements render as colored orb bullets from the system iconset
  (`data/elements.json` supplies the icon).

### 2.3 Battle feel

- Gauges never jump: smooth interpolation for damage and healing.
- Actors flash white/cyan on action, red on impact (system animations).
- Damage numbers launch with velocity and bounce under gravity.

---

## 3. Gates (what keeps all of the above true)

| Gate | Command | Guards |
|------|---------|--------|
| G1 validate | `lovec . validate` → `VALIDATE OK` | Cross-references (every id link in data, incl. graphs/quests/scriptIds), command trees vs registry, formula compilation, targeting specs, scene windows, animation tracks, meta keys, zero-SCRIPT battle phases, required flow phases. |
| G2 golden battle | `tools/golden/check.ps1` | Battle simulation event log byte-identity (`tools/golden/battle.log`). Never regenerate to silence a red diff — regeneration is a reviewed, owner-signed action. |
| G3 golden UI | `tools/golden/check-ui.ps1` | Per-scene UI trace identity for every scene. |

The `[formula] error in 'os.time()'` line during G1 is the sandbox
negative-test, not a failure. The editor runs G1 automatically after every
save (`/validate` endpoint) and surfaces problems in the UI.

Mechanical-rule enforcement map: registry/context/zero-SCRIPT/dangling-id
rules → G1; behavioral regressions → G2; scene rendering → G3; the
aesthetic and code-sharing rules (§2) are review-enforced — call them out
in PR review when violated.

---

## 4. Editor (tools/editor)

- Vanilla JS + Node server (`server.js`), no build step. Data round-trips
  through `/data` and `/save` with stale-save (409) and shape guards.
- Database tabs are schema-driven where possible: `ENTITY_FORM_SCHEMAS`
  (entity tabs) and `CONFIG_SCHEMA` (system/engine config). A new simple
  tab should be a schema entry, not a bespoke panel. Complex editors
  (animation timeline, event commands, map painter) are custom by design.
- Previews go through the REAL engine (`lovec . preview-*`) — the editor
  never approximates rendering in the browser.
- Validation goes through the real engine too (`lovec . validate` via
  `GET /validate`) — no duplicated schema in JS.

---

## 5. Process

- `docs/ORCHESTRATION.md` is the integrator runbook (branches, briefs,
  candidate evaluation). Gates above are its G1–G3.
- Owner-supervision rule: work touching `engine/battle.lua` /
  `engine/scenes/battle.lua` is owner-supervised, never autonomous.
- `docs/plans/<round>/` directories are frozen history. New rounds add a
  directory; they do not edit old ones. When a round's rule survives, it
  gets merged into THIS file and cited from here.
