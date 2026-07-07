# C1 — Grouped Event Command selector

- Branch: `o3/c1-command-selector`
- Runtime needs: G3 (browser)
- Depends on: A6 merged
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S1

## Goal

Replace the flat Command Type `<select>` in the command add dialog with an
RPG-Maker-style selector modal: commands grouped under titled fieldsets
(reference: RPG Maker VX Ace "Event Commands", a paged dialog of grouped
buttons). Owner feedback item 3 in `docs/plans/overhaul-3/FEEDBACK.md`.

## Facts you need

- The registry is `data/engine.json → commands`; the dialog is built in
  `tools/editor/js/events.js` (`openAddCommandDialog` /
  `populateCmdTypeSelect` / `toggleCmdTypeFields`).
- Context filtering already exists (`cmdsForContext(hostCtx)`); the selector
  must keep it — a battle_phase host never offers TEXT.

## Do

- Add an optional `"category"` string to every entry in
  `engine.json → commands` (e.g. Message, Flow Control, Party, Battler,
  Progression, Advanced). Uncategorized commands fall into "Other".
- New `openCommandSelector(hostCtx, cb)` modal: one fieldset per category,
  full-width buttons per command (label + description as tooltip), filtered
  by hostCtx. Clicking a command closes the selector and opens the existing
  param dialog for that command (**adding** flow). The **edit** flow keeps
  opening the param dialog directly, with the type shown read-only.
- The `@>` add affordance in every command list opens the selector instead
  of the old dialog-with-dropdown.
- Registry rule stays: a new command with a `category` shows up in the right
  group with zero editor code.

## Don't

- No engine Lua changes. `category` is editor-only metadata; the validator
  must not require it.
- Do not break the A6 param dialog — it is reused as-is for step 2.

## Acceptance

- [ ] Every registry command reachable in its valid hosts, grouped by
      category; invalid hosts don't show it
- [ ] Add flow: selector → param dialog → command in list; edit flow
      unchanged
- [ ] G1 green (registry file changed — validator must still pass)
- [ ] G3 green
- [ ] PR checklist filled in
