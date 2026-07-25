# A8 — Composability proof: Item Creation demo

- Branch: `o3/a8-crafting-demo`
- Runtime needs: G1 + a manual play session; G3 if you author via the editor
- Depends on: A4 merged; A6 merged makes authoring easier but data can be
  written by hand
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S2, S8

## Goal

Prove the command set is complete by authoring a small crafting system
("Workbench") as pure data — SPEC S8.

## Do

- A new common event "Workbench": recipe CHOICE (2–3 recipes), ingredient
  checks (hasItem conditions / `IF`), consume via `TAKE_ITEM`, success roll
  (`IF` with a formula using `session` context and `random`), grant via
  `GIVE_ITEM_ID`, consolation `EMIT_TEXT`/`TEXT` on failure. Use `COMMENT`
  rows to document each recipe block.
- Attach it to a town option or a map event on the town map.
- Recipes may use existing items only (e.g. 2× HP Tonic → 1× Elixir-tier
  item); pick sensible ones from `data/items.json`.

## Don't

- **No `SCRIPT` commands** — the demo exists to prove the block set; SCRIPT
  would hide gaps.
- No `engine/*.lua` changes. If a step is impossible without new Lua or
  SCRIPT, STOP and file a report naming the missing command instead of adding
  bespoke code.

## Acceptance

- [ ] Crafting works in a play session (success and failure paths both seen)
- [ ] `git diff --stat` shows data/editor files only — zero engine Lua changes
- [ ] G1 green
- [ ] PR checklist filled in
