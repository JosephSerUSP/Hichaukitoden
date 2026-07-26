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

**Invoking the `.ps1` gates bare fails** with `UnauthorizedAccess` under the
default execution policy. Always run them as
`powershell -NoProfile -ExecutionPolicy Bypass -File tools\golden\check.ps1`
(this is what `userPerform/*.bat` does).

| Gate | Command | Guards |
|---|---|---|
| G1 | `lovec . validate` → `VALIDATE OK` | Every id cross-reference, command trees vs registry, formula compilation, targeting specs, scene draw modes, zero-SCRIPT battle phases |
| G2 | `tools/golden/check.ps1` | Battle simulation log byte-identity, per fixture in `data/goldenBattles.json` |
| G3 | `tools/golden/check-ui.ps1` | Per-scene UI trace identity |
| G4 | `tools/golden/check-state.ps1` | `docs/ENGINE-STATE.md` matches the live engine |
| unit | `lovec . unittest` → `ALL UNIT TESTS OK` | Behavior the golden gates can't see |
| save | `lovec . savetest` → `SAVETEST OK` | Save/load round-trip |

`lovec . reachability` is a **report, not a gate** (always exits 0): content that
resolves but that nothing can produce or trigger — unsellable shops, items no
craft yields, creatures no pool grants. See SPEC §3.1 for why that is advisory
while paired-data coherence is a G1 failure.

- G2/G3 red = a **behavioral regression**. Investigate. Never regenerate a
  golden log to silence a diff; regeneration is an owner-signed action.
- G4 red = the **doc is stale**, not the engine. Run
  `tools/golden/capture-state.ps1` and commit the result.
- `[formula] error in 'os.time()'` during G1 is the sandbox negative test, not a
  failure.

## The core philosophy: eventing is the backbone

This project is built by an RPG Maker 2003 developer of 20+ years, and it is a
deliberate recreation of that way of working: **entire systems assembled out of
event blocks.** The difference is that here the event blocks are far more
powerful, and **the engine itself is made of them** — battle phases, scene
logic, recovery sites, quest handling and trap behavior are all command lists in
`data/*.json` that an author can open and modify without touching Lua.

That is the *reason* for the data-driven architecture below, not a side effect of
it. Practical consequences an agent must internalize:

- **Prefer expressing a feature as event commands over writing Lua.** If a
  mechanic can be a command list in a flow, scene hook, or common event, that is
  the correct implementation — not a shortcut. Several traits are implemented
  entirely in data (see `data/flows.json`).
- **When Lua is needed, add a reusable primitive, not a special case.** The right
  move is a new registry command / a new ref or scope / a new formula token that
  data can then compose — e.g. `FOR_EACH`'s `neighbor` ref serves any adjacency
  trait, and `x.trait.<CODE>` made every trait readable from data at once.
- **Don't build a bespoke mechanism where an event can already do the job.**
  Traps are ordinary events with a step trigger — anything an event can do, a
  trap can do — so there is no separate "trap system" to maintain.
- Power belongs in the command language. Widening it lifts every author,
  including the campaign generator, which emits the same commands.

## Non-negotiables

- **Data drives the engine.** Content lives in `data/*.json`; Lua never
  hardcodes content. Adding a command/effect/trait = a `data/engine.json`
  registry entry **plus** a handler. The validator and editor read the registry,
  so the registry — not a hand-written list — is the extension point.
- **Behavior in data is real implementation.** Phase logic lives in
  `data/flows.json`, scene logic in `data/scenes.json` hooks, both run by one
  interpreter. Do not add a Lua fallback "in case the data is missing" — hosts
  call `flow.run(phase, ctx)` unconditionally and the validator requires the
  phase to exist. Two paths for one behavior is the bug.
- **Formulas over scripts.** Numeric/boolean params take sandboxed formulas over
  registry-declared tokens. `SCRIPT` is a rationed escape hatch: battle phases
  are zero-SCRIPT (G1 enforces), and every validate run prints the total SCRIPT
  count so growth stays visible.
- **One implementation, never an approximation.** The editor previews through the
  real engine (`lovec . preview-*`) and validates through the real validator
  (`GET /validate`) — it never re-implements rendering or schema in JS. If you
  find yourself writing a second version of something the engine already does,
  stop.
- **No compatibility shims.** There is no shipped player base and saves are test
  artifacts that may break freely. When a schema changes, migrate the repo's own
  data in place and delete the old read path (SPEC §1.5). A `foo.a or foo.b`
  dual-read of our own data is carrying cost, not compatibility.
- **Fail loud, never silently.** Unknown targeting specs, draw modes, label
  jumps and registry ids raise errors rather than defaulting; the validator
  turns invisible authoring mistakes into build failures. A feature that
  silently does nothing is the worst outcome — prefer a crash or a G1 failure.
- **Enforce with gates, not vigilance.** When a rule can be checked
  mechanically, add the check (G1 for data/registry rules, unit tests for
  behavior, G4 for doc currency) instead of writing it down and hoping. Rules
  that live only in prose have already failed here once.
- **Loader data is shared and immutable.** `loader.getItem(id)` /
  `getActor(id)` hand back the one table every holder sees — `battler.equipment[slot]`
  is a *reference*, not a copy. Per-instance state belongs on the instance
  (e.g. ward charges on `battler.wardCharges`, keyed by slot), and anything
  stored there must round-trip through `engine/savegame.lua`.
- **Owner-supervised:** changes to `engine/battle.lua` and
  `engine/scenes/battle.lua` are never made autonomously.
- **No copy-pasted logic or coordinate math.** Layout/geometry lives in shared
  helpers; editor form fields come from the schema layer
  (`tools/editor/js/entity-forms.js`), not hand-written DOM.
- **The engine never requires presentation.** Use the
  `interpreter.bindPresentation` seam. (`engine/validator.lua` and
  `engine/cli_tools.lua` are the deliberate exceptions: they are build tools
  that validate presentation data, not runtime engine code.)
- **Presentation feel is a rule, not a preference** — rich vertical gradients for
  major menus (never flat dark overlays), panels that slide via timer states,
  gauges that interpolate instead of jumping, damage numbers with velocity and
  gravity. Review-enforced; see SPEC §2.2–2.3 before touching UI.

## Gotchas that cost real time

Kept short on purpose: an entry earns its place only if it caused a real bug and
no gate can catch it. **If you hit a trap that a gate could have caught, add the
gate instead of adding a line here** (that is how the item-type trap below became
a G1 check).

- **The editor dev server writes straight to `data/*.json`.** After browser
  testing, always `git diff data/` — it is not sandboxed.
- **Commands store their id under `cmd`**, always (the legacy `type` key was
  purged). Sub-command lists are always `commands`, never `script`.
- **After rewriting a JSON file programmatically, re-dump with its original
  indent** (`data/tilesets.json` is 4-space; most others are 2-space) or the
  diff becomes unreadable noise.
- **`docs/ENGINE-STATE.md` is ASCII-only on purpose** — it is byte-compared by
  both a PowerShell and a bash gate, and PowerShell 5.1 reads files as ANSI.
- Terminal-dialog slash commands and interactive git flags are unavailable here.

Traps that are now **gated** rather than remembered: an item carrying `effects`
with a non-`consumable` `type` is silently unusable (G1 fails it); a scene with
no draw mode (G1); a registry entry nothing implements (G4 reports it).

## Where things live

```
main.lua                 host: love.load/update/draw, CLI modes, input
main.js                  Electron shell for the editor (npm start / runEditor.bat)
engine/                  interpreter, validator, battle, flows, session,
                         savegame, scene_host, traits, effects, targeting
presentation/            window_renderer (declarative UI), world_renderer,
                         viewport_3d (raycaster), renderer (shared FX +
                         window-content drawers), animation_player
data/*.json              ALL content + engine.json registry
tools/editor/            Node + vanilla JS editor (no build step)
tools/golden/            gate scripts + reference logs
tests/                   unit suites, registered in main.lua's unittest branch
userPerform/             .bat gate runners for the owner to run locally
docs/archive/            frozen history — not instructions
inspiration/             **A DIFFERENT (JavaScript) GAME** kept as reference.
                         Nothing in here describes this engine; never follow its
                         architecture docs. See inspiration/IMPORTANT.md.
```
