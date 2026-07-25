# Agent orientation — Hichaukitoden

A LÖVE2D (Lua) first-person dungeon RPG with a summoner/creature economy, plus a
vanilla-JS+Node editor under `tools/editor`. Read this first; it is deliberately
short.

## Document authority (in order)

| Question | Source | Trust |
|---|---|---|
| What exists right now? | `docs/ENGINE-STATE.md` | **Generated + G4-gated. Highest.** |
| How does it work, and why? | `docs/SPEC.md` | Living spec, review-enforced |
| What are we trying to build? | `docs/design/`, `docs/game design/` | Intent only — **not status** |
| How do rounds/gates/branches work? | `docs/ORCHESTRATION.md` | Process |
| Anything under `docs/archive/` | frozen plans | **Never authoritative** |

**When prose and `ENGINE-STATE.md` disagree, ENGINE-STATE.md is right** — it is
generated from the live engine. When prose and *code* disagree, that is a bug in
one of them: fix it or flag it, never silently pick one.

Design docs describe intent. They must not assert implementation status; if you
need to state status, put it in `SPEC.md` (reviewed) or let the generator report
it. This rule exists because four documents once asserted false facts (battle
"frozen", permadeath "not implemented", Item Creation "quite early") and cost a
full wasted planning pass.

## Gates — run these; they are the safety net

`lovec` is LÖVE's console binary. On this machine use the full path:
`"C:\Program Files\LOVE\lovec.exe"`.

| Gate | Command | Guards |
|---|---|---|
| G1 | `lovec . validate` → `VALIDATE OK` | Every id cross-reference, command trees vs registry, formula compilation, targeting specs, scene draw modes, zero-SCRIPT battle phases |
| G2 | `tools/golden/check.ps1` | Battle simulation log byte-identity |
| G3 | `tools/golden/check-ui.ps1` | Per-scene UI trace identity |
| G4 | `tools/golden/check-state.ps1` | `docs/ENGINE-STATE.md` matches the live engine |
| unit | `lovec . unittest` → `ALL UNIT TESTS OK` | Behavior the golden gates can't see |
| save | `lovec . savetest` → `SAVETEST OK` | Save/load round-trip |

- G2/G3 red = a **behavioral regression**. Investigate. Never regenerate a
  golden log to silence a diff; regeneration is an owner-signed action.
- G4 red = the **doc is stale**, not the engine. Run
  `tools/golden/capture-state.ps1` and commit the result.
- `[formula] error in 'os.time()'` during G1 is the sandbox negative test, not a
  failure.

## Non-negotiables

- **Data drives the engine.** Content lives in `data/*.json`; Lua never
  hardcodes content. Adding a command/effect/trait = a `data/engine.json`
  registry entry **plus** a handler. The validator and editor read the registry.
- **No compatibility shims.** There is no shipped player base and saves are test
  artifacts that may break freely. When a schema changes, migrate the repo's own
  data in place and delete the old read path (SPEC §1.5). Dual-read paths are
  carrying cost, not compatibility.
- **Owner-supervised:** changes to `engine/battle.lua` and
  `engine/scenes/battle.lua` are never made autonomously.
- **No copy-pasted logic or coordinate math.** Layout/geometry lives in shared
  helpers; editor form fields come from the schema layer
  (`tools/editor/js/entity-forms.js`), not hand-written DOM.
- **The engine never requires presentation.** Use the
  `interpreter.bindPresentation` seam.

## Gotchas that cost real time

- **The editor dev server writes straight to `data/*.json`.** After browser
  testing, always `git diff data/` — it is not sandboxed.
- **`battler.equipment[slot]` is a shared reference to the loader's item
  table.** Never store per-instance state there (ward charges live on
  `battler.wardCharges`).
- **`usability.canUseItem` requires `type == "consumable"`.** An item with
  `type: "item"` is silently unusable and invisible in the menu.
- **Commands store their id under `cmd`**, always (the legacy `type` key was
  purged). Sub-command lists are always `commands`, never `script`.
- **After rewriting a JSON file programmatically, re-dump with its original
  indent** (`data/tilesets.json` is 4-space; most others are 2-space) or the
  diff becomes unreadable.
- **`docs/ENGINE-STATE.md` is ASCII-only on purpose** — it is byte-compared by
  both a PowerShell and a bash gate.
- Terminal-dialog slash commands and interactive git flags are unavailable here.

## Where things live

```
main.lua                 host: love.load/update/draw, CLI modes, input
engine/                  interpreter, validator, battle, flows, session,
                         savegame, scene_host, traits, effects, targeting
presentation/            window_renderer (declarative UI), world_renderer,
                         viewport_3d (raycaster), renderer (shared FX +
                         window-content drawers), animation_player
data/*.json              ALL content + engine.json registry
tools/editor/            Node + vanilla JS editor (no build step)
tools/golden/            gate scripts + reference logs
tests/                   unit suites, registered in main.lua's unittest branch
docs/archive/            frozen history — not instructions
```
