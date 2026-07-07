# Overhaul 3 — Scene-Flow System & Editor UX

Execution plan for the third overhaul round. Two workstreams:

- **Workstream A (MAJOR):** transition engine behavior — starting with the battle
  life cycle — to a transparent, event-like **Flow system**: every phase of a scene
  is an editable command list, and every calculation is an editable formula.
  "Gold on victory" stops being a pair of min/max constants and becomes a
  `GAIN_GOLD` command whose formula the designer owns.
- **Workstream B (MEDIUM):** editor UX — icon picker, RPG-Maker-style grouped
  layouts with inner tabs, more data pickers, color-coded JSON.

This document has three parts:

- **Part 0 — Target architecture.** The spec all agents execute against. Read first.
- **Part 1 — Human plan.** Sequencing, delegation matrix, gates, briefing template.
- **Part 2 — Agent briefs.** One self-contained brief per task (A1–A7, B1–B5).

Ground rules that apply to every task:

1. All work lands on task branches cut from the integration branch
   `fable-5-overhaul-3` (create it from `fable-5-overhaul-2`).
2. `& "C:\Program Files\LOVE\lovec.exe" . validate` must print `VALIDATE OK`
   before any task is considered done.
3. After task A3 lands, the golden-master battle log must be **byte-identical**
   before/after every Workstream-A task unless the brief explicitly says behavior
   changes (none of them do — this round is a *transparency* refactor).
4. Any new data file must be added to BOTH server manifests:
   `DATA_FILES` in `engine/server.lua` and in `tools/editor/server.js`.
5. Editor changes are verified in a browser against `node tools/editor/server.js`
   (port 8080) with zero console errors.

---

## Part 0 — Target architecture

### 0.1 The Flow system in one paragraph

Scenes (battle first, exploration/menu later) stop hardcoding their life cycle in
Lua. Instead, each scene declares named **phases** (`battle_start`, `round_start`,
`turn_resolved`, `round_end`, `victory`, `defeat`, `flee_failed`, …). Each phase is
a **command list** stored in `data/flows.json` — the same shape as map-event
commands, so the editor reuses the existing command-list UI. A small
**FlowRunner** (`engine/flow.lua`) executes a phase's commands against a
**context** (session, battle, current actor, scoped loop variables) and emits the
same event stream (`damage`, `heal`, `text`, …) the renderer already consumes.
Engine Lua keeps doing what data cannot: input handling, rendering, and providing
the command implementations. The *orchestration* — what happens, in which order,
with which numbers — moves to data.

### 0.2 Formula Engine v2 — `engine/formula.lua`

Replaces/extends `evaluateFormula` in `engine/effects.lua` (keep a thin
backwards-compatible wrapper there).

```lua
formula.eval(exprString, context) -> number|boolean, err
```

- **Sandboxed:** compile with `load("return "..expr, "formula", "t", env)` where
  `env` is a fresh table containing ONLY the whitelisted helpers and context
  variables below. No access to `_G`, `os`, `io`, `love`.
- **Helpers (whitelist):** `random(a,b)` (integer if both integers, else float in
  [a,b]), `roundDown`/`floor`, `roundUp`/`ceil`, `round`, `abs`, `min`, `max`,
  `clamp(v,lo,hi)`, `pct(x)` (x/100).
- **Context variables** (read-only snapshots, present when applicable):
  - `a` — acting battler: `level, hp, maxHp, atk, def, mat, mdf, exp`
  - `b` / `enemy` / `ally` / `target` — same fields for the object of the command
  - `party` — `size, aliveCount, avgLevel, totalLevel`
  - `enemies` — `count, aliveCount, totalLevel, totalMaxHp`
  - `session` — `gold, mp, maxMp, floor` (dungeonFloor)
  - `battle` — `round`
  - `v` — flow-local variables set by `SET_VAR` (e.g. `v.goldPile`)
- On error: return fallback (0), log once, and the validator flags it (A7).
- Deterministic under `math.randomseed` (used by the golden harness) — do not
  reseed inside the module.

The user's canonical example must work as written:

```
roundDown(enemy.level * enemy.maxHp / 10 + random(1,20) * random(0.9,1.1))
```

### 0.3 FlowRunner — `engine/flow.lua` and `data/flows.json`

```lua
flow.run(phaseName, ctx) -> events[]   -- ctx = { session=, battle=, actor=, target=, v={} }
flow.has(phaseName) -> bool
```

`data/flows.json` shape:

```json
{
  "battle": {
    "victory": [
      { "cmd": "FOR_EACH", "scope": "enemies", "as": "enemy", "do": [
        { "cmd": "GAIN_GOLD", "formula": "roundDown(enemy.level * enemy.maxHp / 10 + random(1,20) * random(0.9,1.1))" }
      ]},
      { "cmd": "FOR_EACH", "scope": "living_allies", "as": "ally", "do": [
        { "cmd": "GRANT_XP", "target": "ally", "formula": "combat.victoryExp" },
        { "cmd": "TRAIT_HEAL", "target": "ally", "trait": "POST_BATTLE_HEAL" }
      ]},
      { "cmd": "EMIT_TEXT", "term": "battle.victory_full" }
    ]
  }
}
```

**Command set v1** (all registered in `engine.json → flowCommands`, each with a
`params` schema the editor renders generically):

| cmd | params | semantics |
|---|---|---|
| `SET_VAR` | name, formula | `ctx.v[name] = eval(formula)` |
| `IF` | condition (formula), then[], else[] | branch; condition is a formula evaluating truthy/falsy |
| `FOR_EACH` | scope, as, do[] | scope ∈ `enemies, living_enemies, allies, living_allies, party` |
| `GAIN_GOLD` | formula | `session.gold += floor(eval)` (clamped ≥ 0), emits text via term `battle.gold_gained` |
| `GRANT_XP` | target, formula | `battler:gainExp(eval)` |
| `HEAL` / `DAMAGE` | target, formula | routed through `effects.apply` so events/death stay consistent |
| `DRAIN_MP` | formula | shared MP pool, emits `mp_drain` event |
| `ADD_STATE` / `REMOVE_STATE` | target, state, duration? | routed through existing state functions |
| `TRAIT_HEAL` | target, trait | heal by `traits.getRate(target, trait)` if > 0 (generalizes POST_BATTLE_HEAL) |
| `STATE_TICKS` | — | the regen/poison/duration-decay block currently in `battle.lua` round end |
| `EMIT_TEXT` | term, fallback?, args? | pushes a `text` event through `loader.formatTerm` |
| `CALL_COMMON_EVENT` | id | reuse the existing common-event compiler (out-of-battle phases only, v1) |

**Execution model:** synchronous, appends to an `events` list that the caller
merges into the existing battle event queue. Commands never touch the renderer.

**Fallback rule:** if a phase is missing from `flows.json`, the engine runs its
legacy Lua block. This keeps every conversion task (A5.x) independently
shippable and trivially revertable (delete the phase → old behavior).

### 0.4 Command registry — `engine.json → flowCommands`

Same pattern as `effectTypes`/`traitCodes`. Each entry:

```json
{ "id": "GAIN_GOLD", "label": "Gain Gold",
  "params": [ { "key": "formula", "type": "formula" } ],
  "description": "Adds floor(formula) gold to the party." }
```

Param `type` drives the editor widget: `formula` (text + variable-reference
popover), `term` (term picker), `state` (state select), `scope` (enum select),
`commands` (nested list), `battlerRef` (enum: actor/target/ally/enemy/summoner).
The Engine window gets a **Flows** tab: scene select → phase select → the shared
`renderCommandList` UI with this palette.

### 0.5 Golden-master safety net (build BEFORE converting anything)

Extend the `validate` CLI mode:

- `lovec . validate golden` — seeds `math.randomseed(12345)`, builds a fixed
  session (skip the random parts of `newgame` by constructing the party
  explicitly), runs a scripted 3-round battle (fixed actions: round 1 all attack,
  round 2 spell+defend+attacks, round 3 flee), plus one victory resolution
  against a 1-HP enemy, and prints a normalized event log
  (`type|actorName|targetName|value|state` per line) between `GOLDEN BEGIN` /
  `GOLDEN END` markers.
- `tools/golden.ps1` (or `.sh`): captures that block to
  `tools/golden/battle.log` (write mode) or diffs against it (check mode),
  exiting nonzero on mismatch.

Every A-task runs the check mode. The log is committed once on A3 and only
regenerated deliberately (never to make a red diff green).

### 0.6 Explicit non-goals for this round

- **Full menu scripting** (input loops as data) is out — round 4 at the earliest.
  What IS in scope for menus this round: nothing beyond what already shipped
  (labels/options from terms/system). A design note for scene-as-data menus goes
  in the A4 deliverable as a README section, not code.
- Enemy AI scripting, dialogue-graph editor, recruit system: out.

---

## Part 1 — Human plan

### 1.1 Delegation matrix

| # | Task | Depends on | Agent class | Why this class |
|---|---|---|---|---|
| A1 | Hardcode inventory (recon doc) | — | **Explore agent** (read-only) or Haiku general-purpose | Pure reading + list-making; zero write risk |
| A2 | Formula Engine v2 | A1 | **Sonnet** general-purpose; **frontier review before merge** | Sandbox correctness is security/robustness-critical; small but load-bearing |
| A3 | Golden-master harness | — (parallel with A2) | **Sonnet** | Deterministic test plumbing; moderate judgment |
| A4 | FlowRunner + registry + flows.json skeleton | A2, A3 | **Sonnet** (strong prompt = Part 0); **frontier review before merge** | Core abstraction; the spec above removes most design ambiguity |
| A5a | Convert: victory rewards → flow | A4 | Sonnet or Haiku | Mechanical against spec + golden diff |
| A5b | Convert: round-end state ticks + MP drain/exhaustion | A4 | Sonnet | Trickiest conversion (event ordering) |
| A5c | Convert: flee resolution + gold penalty | A4 | Sonnet or Haiku | Small, well-bounded |
| A5d | Convert: battle start (encounter roll, enemy count/pick, opening text) | A4 | Sonnet | Touches main.lua trigger path |
| A5e | Convert: defeat + escape transitions | A4 | Haiku | Tiny |
| A6 | Flows tab in Engine window (+ formula popover) | A4 (registry frozen) | **Sonnet** | UI reuse of renderCommandList; needs care, not brilliance |
| A7 | Validator: flows + formulas | A4 | **Haiku** | Pattern-matching additions to runValidation |
| B1 | Icon picker widget | — | **Sonnet** | Canvas/grid math + UX polish |
| B2 | Layout pass: fieldsets, label-above, columns, inner tabs | — | **Sonnet** | Visual judgment against the reference screenshot |
| B3 | Color-coded JSON editing | — | **Haiku** | Self-contained, cosmetic, easily verified |
| B4 | More pickers (map, dialogue-graph via new `/api/graphs`, term) | — | **Sonnet** | Small server endpoint + widgets |
| B5 | Polish: registry-description tooltips, steppers, field help | B2 | **Haiku** | Mechanical |
| — | Review gate after A4 and after A5 batch | | **/code-review** (consider `/code-review ultra` for the A2+A4 core) | Cheapest way to catch cross-file regressions |

Rule of thumb: **Haiku** for tasks where the brief is effectively a checklist and
verification is automatic; **Sonnet** for tasks with real implementation choices
but a firm spec; **frontier (Opus/Fable — i.e. bring me back)** only for A2/A4
review, integration conflicts, and anything that changes the Part 0 spec.

### 1.2 Sequencing

```
Week-ish 1:  A1 ──▶ A2 ──┐
             A3 ─────────┤──▶ A4 ──▶ [review gate] ──▶ A5a..A5e (parallel)
             B1, B2, B3, B4 (parallel, independent)
Week-ish 2:  A6, A7, B5 ──▶ [review gate] ──▶ merge fable-5-overhaul-3, play-test
```

- Merge order within A5: A5a → A5c → A5e → A5b → A5d (easiest to hardest;
  golden diff catches ordering mistakes early).
- B-tasks can merge any time; they touch only `tools/editor/`.

### 1.3 Gates you (the human) personally run

1. After A2/A4: read the diff yourself or run `/code-review` on the branch;
   the sandbox env table in `formula.lua` is the one thing worth eyeballing
   line-by-line (nothing from `_G` may leak in).
2. After each A5 merge: `lovec . validate` + golden check both green.
3. After A6/B-tasks: open the editor, click every new widget once, watch the
   dev-tools console for errors.
4. End of round: one real play session — town → dungeon → battle → victory →
   flee → item use. The golden log covers logic, not feel.

### 1.4 How to brief an agent

Give each agent exactly this, nothing more:

> Read `docs/plans/overhaul-3.md` in repo JosephSerUSP/Hichaukitoden, branch
> `fable-5-overhaul-3`. Execute task **[ID]** from Part 2 only. Follow the ground
> rules at the top of the document. Work on a branch named `o3/[id]-short-name`
> and stop after the acceptance checklist passes.

Self-contained briefs are in Part 2; agents should not need this conversation.

---

## Part 2 — Agent briefs

> Shared verification commands (Windows):
> - Engine: `& "C:\Program Files\LOVE\lovec.exe" . validate` → must end `VALIDATE OK`
> - Golden (after A3 exists): run the check script in `tools/golden/`
> - Editor: `node tools/editor/server.js`, open `http://127.0.0.1:8080`, exercise
>   the changed UI, require zero console errors.

### A1 — Hardcode inventory (read-only recon)

Produce `docs/plans/flow-inventory.md`: an exhaustive table of every hardcoded
calculation, branch, constant, and player-visible string in `main.lua`,
`engine/battle.lua`, `engine/exploration.lua`, `engine/session.lua`,
`engine/effects.lua` that is not already read from `data/*.json`. Columns:
`file:line | what it does | proposed flow phase | proposed command | notes`.
Group by proposed phase (`battle_start`, `round_start`, `turn_resolved`,
`round_end`, `victory`, `defeat`, `flee_failed`, `step_taken`, …). Do not modify
any code. Acceptance: the doc exists, covers at minimum victory rewards, state
ticks, MP drain/exhaustion, flee penalty, encounter roll, level-up HP refill,
and lists file:line for each.

### A2 — Formula Engine v2

Implement `engine/formula.lua` per §0.2 exactly (API, helpers, context fields,
sandbox rule, error behavior). Convert `engine/effects.lua` to build its `a`/`b`
context via the new module while keeping the old `evaluateFormula` signature as
a wrapper. All existing skill formulas in `data/skills.json` must still work.
Add `engine.json → formulaHelp`: an array of `{ token, description }` for every
helper and context variable (the editor popover in A6 reads this).
Acceptance: `VALIDATE OK`; a temporary validation check evaluates the §0.2
canonical example against a mock context without error; grep proves `load(` is
called with an explicit env table and nowhere else.

### A3 — Golden-master harness

Implement §0.5: the `validate golden` CLI arg in `main.lua`, the normalized
event-log dump, and `tools/golden/` capture+check scripts. Commit the initial
`tools/golden/battle.log`. The scripted battle must construct its party/enemies
explicitly (no `newgame` randomness) and seed `math.randomseed(12345)` before
the first roll. Acceptance: running check mode twice in a row passes; editing
any damage formula in `data/skills.json` makes it fail (then revert).

### A4 — FlowRunner + command registry + flows skeleton

Implement §0.3 and §0.4: `engine/flow.lua`, `data/flows.json` (empty `battle`
object — phases are added by A5 tasks), `engine.json → flowCommands` with the
full v1 command table, and the legacy-fallback rule (`flow.has(phase)` guards in
Lua call sites are added by A5 tasks, not here). Add `flows` to BOTH server
manifests. Include a `README` section at the top of `engine/flow.lua` describing
the ctx shape and how a future menu scene would declare phases. Acceptance:
`VALIDATE OK`; golden check green; a scratch phase exercising every command id
(written in a test, then removed or kept under a `_test` scene key) runs without
error.

### A5a — Convert victory rewards to flow

Move the victory block (gold gain, per-survivor XP, POST_BATTLE_HEAL) from
`main.lua` into `data/flows.json → battle.victory` using `FOR_EACH`/`GAIN_GOLD`/
`GRANT_XP`/`TRAIT_HEAL`/`EMIT_TEXT`. Default formulas must reproduce current
behavior EXACTLY: gold `random(combat.victoryGoldMin, combat.victoryGoldMax)`
(expose the combat.* constants to formulas via context — add a `combat` table to
the formula context in this task), XP `combat.victoryExp`. Legacy Lua path stays
behind `if not flow.has("battle.victory")`. Acceptance: golden log identical;
`VALIDATE OK`.

### A5b — Convert round-end ticks to flow

Move regen/poison ticks, state-duration decay, MP drain per living ally, and MP
exhaustion damage from `engine/battle.lua` into `battle.round_end` using
`STATE_TICKS`, `FOR_EACH`, `DRAIN_MP`, `DAMAGE`, `IF`. Event **ordering must be
preserved** — the golden log is the arbiter. Acceptance: golden identical;
`VALIDATE OK`.

### A5c — Convert flee resolution

Move flee chance roll + failure gold penalty from `engine/battle.lua` into
`battle.flee_attempt` (succeeds → `flee_success` event; fails → penalty +
`EMIT_TEXT battle.flee_fail`). The FLEE_CHANCE_BONUS trait sum must appear in
the formula context (`party.fleeBonus`). Acceptance: golden identical (the
scripted round 3 flee exercises both paths via seed); `VALIDATE OK`.

### A5d — Convert battle start

Move encounter chance roll (`main.lua` step handler) and enemy-group
composition (count roll + weighted pick) into `battle.encounter_check` and
`battle.battle_start` phases. Add flow commands `ROLL_ENCOUNTER` and
`SPAWN_ENEMIES` to the registry (params: formula / weighted-table reference) as
part of this task, updating `engine.json` and the A6 palette. Acceptance:
golden identical; `VALIDATE OK`; encounters still trigger in a manual play test.

### A5e — Convert defeat/escape transitions

Move defeat text/reset and escape-to-map transitions into `battle.defeat` /
`battle.escaped` phases (`EMIT_TEXT` + a new `SET_FLAG`-style command only if
needed; scene switching itself stays in Lua — emit a `scene_change` event the
existing main.lua handler consumes). Acceptance: golden identical; `VALIDATE OK`.

### A6 — Flows tab in the Engine window

Add a **Flows** tab to the Engine modal: scene select (from `flows.json` keys +
known scenes), phase select (known phases with "has data / legacy" badge), and
the shared `renderCommandList` UI extended with a palette driven by
`engine.json → flowCommands` param schemas (`formula` params render a text field
with an ⓘ popover listing `engine.json → formulaHelp`; `term` params render a
term picker; `commands` params render nested lists exactly like CHOICE branches).
Include the `{ } JSON` toggle per phase. Acceptance: every command type can be
added/edited/removed/nested in the UI; saving round-trips through `/save`; a
phase edited in the UI changes behavior in a test play; zero console errors.

### A7 — Validator coverage for flows

Extend `runValidation`: every `cmd` in `flows.json` exists in `flowCommands`;
every `formula`/`condition` string compiles against a mock context; every `term`
reference resolves or has a fallback; every `state`/`scope` value is valid;
nested `do`/`then`/`else` lists are recursed. Acceptance: `VALIDATE OK` on clean
data; deliberately corrupting a formula or cmd id makes it fail (then revert).

### B1 — Icon picker widget

The game iconset is `assets/system/iconset.png`, 12×12-pixel cells, 10 columns,
ids 1-indexed (`col=(id-1)%10`, `row=floor((id-1)/10)` — see
`presentation/ui.lua → ui.drawIcon`). The editor server already serves
`assets/*`. Build `openIconPicker(currentId, cb)`: a modal rendering the sheet
as a scrollable grid of cells (CSS `background-position` or canvas), hover
shows the id, click selects. Replace every numeric "Icon #" field (items,
passives, states, elements forms) with a read-only id + live 12×12 preview
swatch + "Pick…" button. Acceptance: picking an icon updates the payload and
preview; all four forms use it; zero console errors.

### B2 — Layout pass with inner tabs

Reference: RPG Maker VX Ace's "Terms/Vocab" screen — dense grouped `fieldset`s,
labels **above** narrow inputs, 2–4 columns per group, and horizontal inner tabs
(e.g. `Battle1 | Battle2 | Shop | Others`) instead of one long scroll. Apply to:
Engine window tabs (Battle Flow currently wastes half the panel), the Database
System tab, and the Terms tab (group by top-level key as inner tabs). Implement
a reusable `buildTabbedSections(container, sections)` helper and a
`fieldset`-based `buildFieldGroup(title, cols)` helper; convert
`buildRecursiveForm`'s collapsible sections to use them (keep collapsibles only
for depth ≥ 2). Do not change any data bindings. Acceptance: before/after
screenshots of Engine→Battle Flow and Database→Terms; no horizontal scrollbars
at 1280×800; zero console errors.

### B3 — Color-coded JSON editing

Upgrade `attachJsonToggle`'s textarea to a highlighted editor: transparent
`<textarea>` overlaid on a `<pre>` that re-renders tokenized HTML on input
(strings/numbers/keys/booleans in distinct colors), scroll-synced. No external
dependencies. Keep the red-background invalid state. Acceptance: typing stays
responsive on the largest object (`data/system.json`), highlight matches
content, Apply/Back unchanged.

### B4 — More data pickers

1. Add `GET /api/graphs` to `tools/editor/server.js` returning
   `data/graphs/*.json` basenames.
2. Editor widgets: `graphPicker` (dropdown from that endpoint — use it for town
   option `graph` fields), `mapPicker` (already have map titles — extract the
   inline select into a reusable widget), `termPicker` (tree-walk of
   `dbPayload.terms` into dotted paths). Wire `termPicker` into the flow editor
   later (A6 consumes it if merged first; coordinate via the registry param
   types, not code coupling).
   Acceptance: town options edit with the graph dropdown; endpoint returns the
   11 graph names; zero console errors.

### B5 — Polish batch

Tooltips on effect/trait dropdowns from registry `description`s; `min`/`step`
attributes from `CONFIG_SCHEMA` applied everywhere; help text (`field-help`
span) rendered for schema entries that gain a `help` string; Enter-to-apply in
the Change Maximum dialog. Acceptance: visual spot-check; zero console errors.
