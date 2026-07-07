# A7 — Validator coverage for the unified system

- Branch: `o3/a7-validator`
- Runtime needs: G1
- Depends on: A4 merged
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S1, S2, S3, S5, S6

## Goal

Extend `runValidation` in `main.lua` so the unified event system is fully
reference-checked.

## Do

Checks over all command lists (map events, common events, flows.json, nested
`do`/`then`/`else`/CHOICE options, recursively):

- every `cmd` exists in `engine.json → commands`;
- commands appear only in hosts allowed by their `contexts`;
- `interactive` commands never appear in immediate hosts (flows.json);
- every `formula`/`condition` param compiles against a mock context;
- every `script` param compiles (`load` syntax check — never executed);
- the zero-SCRIPT rule (S6) holds for default `battle.*` phases in
  `data/flows.json`;
- `term`/`state`/`item`/`scope`/`battlerRef` params resolve;
- `COMMENT` commands and `comment` fields are accepted everywhere and never
  flagged;
- an info line reports total SCRIPT usages across all data files.

## Don't

- No behavior changes to the interpreter; validation only.

## Acceptance

- [ ] G1 green on clean data
- [ ] Corrupting (one at a time, then reverting): a cmd id, a formula, a
      script body, and a context placement each turn validation red
- [ ] PR checklist filled in
