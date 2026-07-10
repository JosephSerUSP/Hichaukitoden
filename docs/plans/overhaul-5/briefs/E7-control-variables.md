# E7: Control Variables — multi-assignment SET_VAR

**Context:** Owner feedback 10.07.2026 (FEEDBACK.md item 6). One event command
that sets one *or several* variables. RPG Maker's "Control Variables" is the
naming reference; our mechanics stay formula-driven.

**Role:** local preferred (editor modal work needs a browser; engine change is
trivial).

## Design constraints

- **Keep the command id `SET_VAR`.** It is used widely across `scenes.json` /
  `flows.json`; renaming the id churns every data file for zero behavior. Only
  the `label` in `data/engine.json` changes, to "Control Variables".
- **Backward compatible:** the existing single `{name, value}` shape keeps
  working unchanged, forever. New optional param `assignments`: a list of
  `{name, value}` rows. If `assignments` is present, the handler loops it (in
  order) and ignores `name`/`value`; otherwise legacy behavior.
- **In-order evaluation:** each row's `value` formula is evaluated after the
  previous rows are assigned, so later rows can read earlier ones via `v.`.
  Document this in the command's `description`.
- SET_VAR emits no logged events, so golden logs are structurally safe — but
  run G2 + UI-golden anyway (the gates are cheap; assumptions aren't).

## Acceptance Criteria

- [ ] `engine/interpreter.lua` `handlers.SET_VAR`: supports `assignments`
      (loop, in order, each via the same `evalFormula`); legacy shape
      untouched.
- [ ] `data/engine.json` SET_VAR entry: label "Control Variables", new
      `assignments` param, description documents both shapes and the in-order
      rule.
- [ ] Validator (`main.lua` `validateCommands`): each assignment's `value`
      compiles as a formula and each `name` is a non-empty string — the
      existing `formula` param-type check covers only top-level `value`;
      extend for the list (either a new param type, e.g. `assignments`,
      handled where `formula`/`commands` types are, or an explicit SET_VAR
      case — prefer the param type so the next list-of-pairs command
      inherits it).
- [ ] Editor command modal: a repeatable name/value row widget (add row,
      delete row, reorder is nice-to-have) for the `assignments` param. Build
      it as a *generic* param-type widget in the modal renderer, not a
      SET_VAR special case.
- [ ] `describeCommand` renders a readable summary: single form unchanged
      (`Set Variable: x = 1`), multi form like
      `Control Variables: a = 1, b = v.a * 2` (truncate long lists).
- [ ] Editing an existing single-form SET_VAR keeps it single-form (no silent
      migration of saved data); the modal offers "+ row" to grow it into the
      multi form, at which point saving writes `assignments`.
- [ ] Optional, only if trivially safe: a one-time editor affordance to merge
      a selected run of consecutive SET_VARs into one Control Variables
      command (pairs with E2's multi-select). Do NOT bulk-rewrite data files.
- [ ] Zero console errors; saves round-trip; a scene using the multi form
      validates and runs (verify against the crafting scene's `on_enter`
      copy in a scratch scene — do not modify the shipped crafting scene in
      this brief; golden references stay untouched).

**Gates:** G1, G2, G3, UI-golden (all byte-identical — this brief changes no
shipped data).
