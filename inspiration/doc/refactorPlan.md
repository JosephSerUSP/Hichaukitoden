1) One source of truth for runtime state

Create a single GameSession (or Runtime) that owns:

party, inventory, map state, flags, run meta (seed/floor), battle state (nullable), interpreter state (nullable)

Scenes do not own “reality.” Scenes are orchestration + UI only.

2) Hard layer boundaries (enforced)

You currently have UI importing simulation (windows/* importing ProgressionSystem, etc.) and “core” importing data (src/core/utils.js importing data/traits.js). That must stop.

Target import rule:

engine/* cannot import from ui/*, windows/*, scenes/*

ui/* cannot import from engine/systems/* (only from engine/state + selectors)

data/* is read-only and accessed through a repository (no random imports)

This is enforced with ESLint + a simple “forbidden imports” config.

3) Systems return events; UI renders events

Battle/exploration/interpreter produce GameEvent[] (structured events).
Windows/scenes consume events and animate/log.

4) “Strangler with deletion”

We do not “refactor in place” indefinitely.
We build new engine surfaces, migrate a vertical slice, then delete the legacy slice immediately.

Target architecture (the end state)
Engine (pure-ish, testable, serializable)

src/engine/

session/ – runtime state + save/load serialization

systems/ – battle, exploration, encounters, interpreter, progression

rules/ – effects, traits, formulas (pure functions + registries)

events/ – event types + helpers

ports/ – interfaces for audio, storage, rng, clock, midi, etc.

adapters/ – DOM/audio/localStorage implementations of ports (thin wrappers)

Presentation (DOM-first, fast iteration)

src/presentation/

scenes/ – glue: translate user intent to engine commands; route to windows

windows/ – DOM UI only (no simulation imports)

selectors/ – “view models” derived from session state (selectPartyHUD(session))

Data (read-only)

data/ + src/data/

loader + validators

schemas (even lightweight) to fail loudly on broken content

Phase 0 — Lock behavior and make refactor safe (mandatory)

Goal: you can change architecture without changing gameplay accidentally.

Deliverables:

Deterministic RNG (one RNG service used everywhere)

Replace scattered randInt usage with rng.nextInt()

Golden logs for:

one battle seed (turn-by-turn event log)

one dungeon seed (map generation summary)

A tiny headless harness:

“run one battle with seed X and assert event log matches snapshot”

Exit criteria (hard gate):

You can run the harness and get identical results twice in a row.

If this isn’t true, refactor will rot into “it feels okay” debugging.

Phase 1 — Create the New Engine skeleton + import bans

Goal: lay the new foundation without mixing.

Steps:

Add src/engine/ with:

session/GameSessionState (plain JSON-able objects)

session/GameSession (methods that call systems)

events/types.js

ports/* (AudioPort, StoragePort, RNGPort)

Add src/presentation/selectors/* but keep it minimal at first.

Add ESLint rules:

forbid imports from src/presentation/** inside src/engine/**

forbid imports from src/engine/systems/** inside src/presentation/windows/**

Create src/legacy/ folder.

You don’t move everything immediately.

But once a slice migrates, its old files go to legacy/ or get deleted.

Exit criteria:

The project builds with the skeleton present.

Import bans are enforced (CI fails if violated).

Phase 2 — Migrate Battle as the first “vertical slice” (and delete legacy battle)

Battle is the best first slice because it’s contained and already partially systematized (BattleManager, EffectManager, TraitManager).

2A) Build the new battle surface

Create in src/engine/systems/battle/:

BattleState (serializable)

BattleSystem.start(session, encounterId, context)

BattleSystem.chooseAction(...)

BattleSystem.step(...) -> GameEvent[]

2B) Refactor rules out of hardcoded battle logic

You currently have game-specific behavior embedded in battle flow (e.g. summoner MP drain, special victory conditions). Move that to:

BattleRuleset or BattleHooks inside engine/rules/

onBeforeAction, onAfterAction, onTurnStart, onBattleEndCheck, etc.

2C) Bridge the UI (thin adapter, temporary)

Scene_Battle becomes:

ask BattleSystem for event list

pass events to Window_Battle for display/animation

Windows do not compute evolution/progression/battle legality. They show view models.

2D) Delete legacy battle path

Remove (or quarantine under legacy/) the old managers/battle.js code path.

Any old calls to BattleManager.executeAction() must be gone.

If an adapter exists, it must be one-way (UI → new engine), never “sometimes old, sometimes new.”

Exit criteria:

Golden battle log matches exactly (Phase 0 snapshot).

Old battle implementation is removed from mainline imports.

Phase 3 — Migrate Exploration + Encounters (delete legacy exploration)

Create src/engine/systems/exploration/:

ExplorationState (position, facing, per-tile discoveries)

ExplorationSystem.move(session, direction) -> GameEvent[]

ExplorationSystem.interact(session) -> GameEvent[]

EncounterSystem.roll(session) -> Encounter | null

Key change:

exploration emits events like PlayerMoved, DoorOpened, EncounterTriggered, EventTriggered

Scene_Map only dispatches intent + renders events

Delete:

legacy managers/exploration.js path once cut over

Exit criteria:

Deterministic movement + encounter rolls for a seed

Old exploration code removed from live imports

Phase 4 — Migrate Interpreter / Events (delete legacy interpreter)

Your event system will explode in complexity as story grows. It must be engine-side and serializable.

Build src/engine/systems/interpreter/:

InterpreterState (stack, instruction pointer, locals)

Interpreter.runUntilPause(session) -> GameEvent[]

Commands operate on session state (give item, start battle, show dialogue, set flag)

Presentation consumes events:

DialogueShown, ChoicePresented, ShopOpened, etc.

Delete:

legacy managers/interpreter.js usage once new interpreter powers the same content

Exit criteria:

One scripted sequence runs deterministically

Interpreter state can be serialized mid-event and resumed

Phase 5 — UI decoupling pass (this is where “maintainability” is won)

Right now UI imports simulation (ex: windows/utils.js importing ProgressionSystem). That’s a maintainability trap.

Replace with:

src/presentation/selectors/

selectBattlerDetails(session, battlerId)

selectPartyHUD(session)

selectEvolutionStatus(session, battlerId) (computed from state + data)

src/presentation/formatters/ for strings/icons/colors

Hard rule:

Windows can import only selectors + UI components

Windows never import engine/systems/* or engine/rules/*

Exit criteria:

windows/** has zero imports from src/managers/* and src/engine/systems/*

All UI is fed view models

Phase 6 — Save/Load becomes trivial (because Session exists)

Implement:

SessionSerializer.toJSON(session)

SessionSerializer.fromJSON(data, repository, ports)

This is the payoff for not letting scenes own state.

Exit criteria:

Save during map exploration, reload, continue

Save mid-battle (optional but ideal), reload, continue

Phase 7 — Remove the remaining legacy knot (the “purge”)

Big cleanups that eliminate long-term fragility:

Remove barrel-cycle risks:

retire src/objects/objects.js barrel imports in engine

Replace window.* debug globals with:

DebugTools behind config flag, registered in main.js only for dev

Stop “core” importing data (src/core/utils.js currently pulls trait definitions)

move trait definitions into data repository and pass them explicitly

Exit criteria:

src/legacy/** is empty or deleted

No live code depends on debug globals

Import graph is acyclic within engine/**

How we guarantee “no halfway / legacy swamp”

These are the enforcement mechanisms:

Vertical slice migrations only

Battle migrates completely → delete old battle.

Exploration migrates completely → delete old exploration.
No “half new battle manager but old effect pipeline,” etc.

Deletion gates
Every phase ends with a delete/quarantine PR:

Old module removed from live imports

ESLint ban prevents reintroducing it

Golden snapshots
Your engine produces event logs already. Use that:

If logs drift, it’s either a bug or an intentional design change (explicitly acknowledged).

One compatibility layer max
If you need a bridge, it lives in one place: src/presentation/legacy_bridge/.
It must have a planned deletion date and a checklist item.