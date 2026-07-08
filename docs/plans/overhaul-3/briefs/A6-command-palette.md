# A6 — One registry-driven command palette, everywhere

- Branch: `o3/a6-command-palette`
- Runtime needs: G3 (browser); G1 for a behavior spot-check
- Depends on: A4 merged; B0 merged (editor module split)
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S1, S2, S3, S6

## Goal

The editor's command UI (`renderCommandList` + the command add/edit dialog)
becomes registry-driven, serves all hosts, and gains the Flows tab and the
comment system.

## Do

- The add/edit dialog builds its fields from `engine.json → commands` param
  schemas. Widgets by param type: `formula` → text input + ⓘ popover listing
  `engine.json → formulaHelp`; `script` → monospace multiline textarea + ⓘ
  popover listing `scriptingHelp`; `term`/`state`/`item`/`skill` → pickers;
  `scope`/`battlerRef` → enum selects; `commands` → nested lists (like CHOICE
  branches today); `text`/`number`/`flag` → plain inputs.
- Palette filtering by host context (S1 `contexts`): Event editor and Common
  Events offer `map`/`common` commands; the new **Flows** tab in the Engine
  window (scene select → phase select, each phase badged "has data" or
  "legacy") offers `battle_phase` commands.
- Comment system per S3: every dialog gets an optional Comment field;
  `COMMENT` rows and per-command comment lines render green beneath their
  command; a "Show comments" toggle in every command-list header
  (localStorage-persisted, default on). SCRIPT rows render in their own
  distinct color.
- `{ } JSON` toggle per flow phase (reuse `attachJsonToggle`).

## Don't

- No engine Lua changes. Do not invent commands not in the registry.

## Acceptance

- [ ] Every registry command is addable/editable/nestable in its valid hosts
      and absent from invalid ones
- [ ] Comments: COMMENT rows + per-command comments render, toggle works and
      persists across reload
- [ ] A phase edited in the UI changes behavior in a test play (G1 spot-check)
- [ ] G3 green (zero console errors across a full click-through)
- [ ] PR checklist filled in
