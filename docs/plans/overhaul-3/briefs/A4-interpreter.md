# A4 — Unified interpreter + command registry

- Branch: `o3/a4-interpreter`
- Runtime needs: G1, G2
- Depends on: A2 and A3 merged
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S1, S2, S3, S4, S6

## Goal

The core of the round: one interpreter for map/common events AND engine
phases, one command registry, the SCRIPT escape hatch, no live phase converted
yet.

## Do

- `engine/interpreter.lua`:
  - `runInteractive(commands, ctx)` — absorb `compileCommands` from `main.lua`
    (main.lua keeps only thin glue). Existing map/common-event behavior must
    be pixel-identical.
  - `runImmediate(commands, ctx) -> events[]` — synchronous execution for
    phases; interactive commands are an error here.
  - Handlers for every S2 command, including `COMMENT` (skip) and the
    `comment` field on any command (ignore).
  - `SCRIPT` per S6: widened sandbox, the `api` mutator table routing through
    `effects.apply` / inventory / state pipelines, honoring
    `engine.json → scripting.allowRawAccess` (default false).
- `engine/flow.lua`: `flow.run(phase, ctx)`, `flow.has(phase)`, reading
  `data/flows.json` (create it with an empty `battle` object). Header comment
  documents the ctx shape and how a future host (e.g. menu) declares phases.
- `engine.json`: full S2 `commands` registry (existing interactive ids
  included, with `contexts`/`interactive` flags), `scripting.allowRawAccess`,
  `scriptingHelp` (every `ctx`/`api` member documented).
- Add `flows` to BOTH server manifests (SPEC Ground rule 3).
- A `_test` scene key in flows.json exercising every non-interactive command,
  run by the validator in immediate mode. Include a `_test` SCRIPT proving
  `api.damage` emits normal damage events and that touching `io`/`os`/`loader`
  errors while `allowRawAccess` is false.

## Don't

- Do NOT convert any live battle phase (that is A5a–e).
- Do NOT change editor files (that is A6).

## Acceptance

- [ ] G1 and G2 green
- [ ] Manual play: an NPC dialogue, a chest, and the stairs-down choice behave
      exactly as before (now via the interpreter)
- [ ] `_test` phase runs every non-interactive command without error
- [ ] SCRIPT sandbox negative-test passes (raw access blocked by default)
- [ ] PR checklist filled in
