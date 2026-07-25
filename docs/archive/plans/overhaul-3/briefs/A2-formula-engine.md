# A2 — Formula engine

- Branch: `o3/a2-formula-engine`
- Runtime needs: G1 (LOVE runtime)
- Depends on: A1 merged (for context names), A3 not required
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S5

## Goal

Implement `engine/formula.lua` exactly per SPEC S5: sandboxed expression
evaluation with documented context and helpers.

## Do

- API: `formula.eval(exprString, ctx) -> value, err` plus context-builder
  helpers for battler views, party/enemies aggregates, session, combat, `v`.
- Sandbox per S5 (fresh env via `load(expr, name, "t", env)`; whitelisted
  helpers only; no `_G`/`os`/`io`/`love`/`require`).
- Convert `engine/effects.lua` to build its `a`/`b` context through the new
  module; keep the old `evaluateFormula` signature as a thin wrapper. Every
  existing formula in `data/skills.json` must keep working.
- Write `engine.json → formulaHelp`: `{ token, description }` for every
  context variable and helper you expose.
- Add a validation check (in `runValidation`, `main.lua`) that compiles a
  representative reward-curve expression using `enemy.*`, `session.floor`,
  `random`, and rounding against a mock context.

## Don't

- No flows/interpreter work (that is A4). No editor work.

## Acceptance

- [ ] G1 green
- [ ] All `data/skills.json` formulas still evaluate (validate exercises a battle)
- [ ] `grep -n "load(" engine/*.lua data/*.lua` shows `load` called only with
      an explicit env argument
- [ ] `formulaHelp` covers every exposed token
- [ ] PR checklist filled in
