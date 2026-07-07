# Overhaul 3 — Unified Event Engine & Editor UX

Execution plan for the third overhaul round. Two workstreams:

- **Workstream A (MAJOR):** converge on **one event-command language** for the
  whole engine. Map events, common events, battle life-cycle phases — and later
  menus and entirely new systems — are all command lists in the same JSON shape,
  executed by one interpreter, edited with one command palette. The goal is not
  "expose more constants": it is that the *composition* of every system becomes
  data. The acceptance bar for the architecture is composability: a crafting
  system (Star Ocean-style Item Creation) must be buildable from the blocks
  alone, with no bespoke Lua (task A8 proves it).
- **Workstream B (MEDIUM):** editor UX — icon picker, RPG-Maker-style grouped
  layouts with inner tabs, more data pickers, color-coded JSON — plus one
  enabler task (B0) that splits the single-file editor so multiple agents can
  work in parallel without merge hell.

Document layout:

- **Part 0 — Target architecture.** The spec all agents execute against.
- **Part 1 — Human plan.** Multi-environment delegation, gates, protocols.
- **Part 2 — Agent briefs.** Self-contained briefs (A1–A8, B0–B5).

Ground rules for every task, in every environment:

1. Work on a task branch `o3/<id>-<short-name>` cut from the integration branch
   `fable-5-overhaul-3` (create it from `fable-5-overhaul-2` if absent).
2. Gates (run all that your environment supports; record the rest as
   *verification debt* — see §1.4):
   - **G1 validate:** `lovec.exe . validate` (Windows) or `love . validate`
     (Linux) prints `VALIDATE OK`.
   - **G2 golden:** the golden-master battle log (after A3 lands) is
     byte-identical unless the brief says otherwise (none do).
   - **G3 editor:** `node tools/editor/server.js`, exercise the changed UI at
     `http://127.0.0.1:8080`, zero console errors.
3. New data files go into BOTH server manifests: `DATA_FILES` in
   `engine/server.lua` AND `tools/editor/server.js`.
4. Never edit `tools/editor/index.html` in parallel with another task until B0
   (module split) has merged. Editor tasks are serialized before B0, parallel
   after it.
5. Do not change the Part 0 spec. If a brief conflicts with reality, stop and
   report; do not improvise architecture.

---

## Part 0 — Target architecture

### 0.1 One command language, one interpreter

Today there are two half-languages: map/common-event commands (`TEXT`, `CHOICE`,
`CONDITIONAL_BRANCH`, `GIVE_ITEM`, `BATTLE`, …) compiled by `compileCommands` in
`main.lua`, and hardcoded Lua for everything the engine itself does. This round
merges them:

- **`engine/interpreter.lua`** owns command semantics. Two run modes:
  - `interpreter.runInteractive(commands, ctx)` — player-paced; this absorbs the
    current `compileCommands`/GraphWalker path (TEXT waits for input, CHOICE
    branches on selection). Map events, common events, dialogue keep working
    exactly as now, through this door.
  - `interpreter.runImmediate(commands, ctx) -> events[]` — synchronous; for
    engine phases (battle round end, victory, …). Emits the same event stream
    (`damage`, `heal`, `text`, `mp_drain`, …) the battle log/renderer already
    consumes. Interactive commands are **invalid** here (validator enforces).
- **`engine.json → commands`** is the single registry. Each entry:

```json
{ "id": "GAIN_GOLD", "label": "Gain Gold",
  "params": [ { "key": "amount", "type": "formula" } ],
  "contexts": ["battle_phase", "map", "common"],
  "interactive": false,
  "description": "Adds floor(amount) gold to the party." }
```

  - `contexts` controls where the editor offers the command and where the
    validator accepts it (`map`, `common`, `battle_phase`, `menu`, `any`).
  - `params[].type` drives the editor widget: `formula`, `term`, `state`,
    `item`, `skill`, `actor`, `scope`, `battlerRef`, `commands` (nested list),
    `text`, `number`, `flag`.
- **The payoff for plain game eventing:** because NPC/chest/common events run on
  the same registry, every system-level command whose `contexts` includes
  `map`/`common` immediately becomes available in the existing Event editor.
  Designers get `GAIN_GOLD`, `GRANT_XP`, `TAKE_ITEM`, `SET_VAR`, `IF`,
  `FOR_EACH` in ordinary chest/NPC scripts for free — which is what makes
  crafting menus, visual-novel scenes, or other genre experiments possible
  without engine work.

### 0.2 Command set v1

Existing interactive commands keep their ids and behavior: `TEXT`, `CHOICE`,
`CONDITIONAL_BRANCH`, `RECOVER_PARTY`, `DESCEND`, `BATTLE`, `GIVE_ITEM`,
`CALL_COMMON_EVENT`. New v1 commands (all non-interactive unless noted):

| id | params | notes |
|---|---|---|
| `SET_VAR` | name, value:formula | flow-local variable, readable as `v.name` in formulas |
| `SET_FLAG` | flag, value | session flag (the same flags conditions already read) |
| `IF` | condition:formula, then:commands, else:commands | supersedes CONDITIONAL_BRANCH's string conditions over time; both stay valid |
| `FOR_EACH` | scope, as, do:commands | scope ∈ enemies, living_enemies, allies, living_allies, party |
| `GAIN_GOLD` | amount:formula | clamped ≥ 0 |
| `GRANT_XP` | target:battlerRef, amount:formula | |
| `DAMAGE` / `HEAL` | target:battlerRef, amount:formula | routed through `effects.apply` so death/events stay consistent |
| `ADD_STATE` / `REMOVE_STATE` | target:battlerRef, state, duration? | |
| `DRAIN_MP` / `RESTORE_MP` | amount:formula | shared pool |
| `STATE_TICKS` | — | the regen/poison/duration-decay block, as one block command |
| `TRAIT_HEAL` | target:battlerRef, trait | generalizes POST_BATTLE_HEAL |
| `EMIT_TEXT` | term, fallback?, args? | battle-log/text event via formatTerm |
| `TAKE_ITEM` | item, count? | inventory remove (fails soft; pairs with hasItem conditions) |
| `GIVE_ITEM_ID` | item, count? | give a *specific* item (GIVE_ITEM stays the "random treasure" command) |
| `ROLL_ENCOUNTER` | chance:formula | (A5d) |
| `SPAWN_ENEMIES` | count:formula, table | weighted pick from map encounters (A5d) |
| `SCENE_EVENT` | kind | emits a `scene_change`-style event that main.lua consumes; the interpreter never switches scenes itself |

Adding a command later = one Lua handler + one registry entry; the editor and
validator pick it up from the registry with zero editor code.

### 0.3 Hosts and phases

`data/flows.json` maps scene phases to command lists (immediate mode):

```json
{ "battle": {
    "victory": [
      { "cmd": "FOR_EACH", "scope": "enemies", "as": "enemy", "do": [
        { "cmd": "GAIN_GOLD", "amount": "<designer-owned formula>" } ] },
      { "cmd": "FOR_EACH", "scope": "living_allies", "as": "ally", "do": [
        { "cmd": "GRANT_XP", "target": "ally", "amount": "combat.victoryExp" },
        { "cmd": "TRAIT_HEAL", "target": "ally", "trait": "POST_BATTLE_HEAL" } ] },
      { "cmd": "EMIT_TEXT", "term": "battle.victory_full" } ] } }
```

Phase names v1: `battle.encounter_check`, `battle.battle_start`,
`battle.flee_attempt`, `battle.round_end`, `battle.victory`, `battle.defeat`,
`battle.escaped`. **Fallback rule:** a phase absent from `flows.json` runs the
legacy Lua block — every conversion (A5x) is independently shippable and
revertable. Menus/exploration get phases in a later round; `engine/flow.lua`'s
header documents how a new host declares them.

### 0.4 Formulas are a param type, not the architecture

Where a number is needed, a `formula` param accepts an expression over a
documented, sandboxed context. Design constraints:

- **Syntax is the implementer's choice** (it will realistically be Lua
  expression syntax, since evaluation is sandboxed `load`), but it must be
  *documented in data* (`engine.json → formulaHelp`: every variable and helper
  with a description) so the editor can show an insert-variable popover.
  There is **no required pseudocode compatibility**; the requirement is
  *expressiveness*: reward curves over `enemy.level / enemy.maxHp /
  session.floor / party.aliveCount` with randomness and rounding must be
  writable in one line — and equivalently composable as a `SET_VAR` chain for
  designers who prefer pure blocks over expressions.
- Sandbox: fresh env table, whitelisted helpers only (`random`, `floor`, `ceil`,
  `round`, `abs`, `min`, `max`, `clamp`), no `_G`/`os`/`io`/`love` access.
- Context (read-only snapshots): `a`/`b`/`target`/`enemy`/`ally` battler views
  (`level, hp, maxHp, atk, def, mat, mdf`), `party`, `enemies` aggregates,
  `session` (`gold, mp, maxMp, floor`), `battle` (`round`), `combat` (the
  system.json combat table), `v` (flow-locals).
- On error: fallback 0, log once, validator flags it.
- Deterministic under `math.randomseed` (golden harness depends on it).

### 0.5 Golden-master safety net (build BEFORE converting anything)

Extend the `validate` CLI mode:

- `love . validate golden` — seeds `math.randomseed(12345)`, constructs a fixed
  party/enemy setup explicitly (no newgame randomness), runs a scripted 3-round
  battle (round 1 all attack; round 2 spell+defend+attacks; round 3 flee) plus
  one victory resolution, and prints a normalized event log
  (`type|actor|target|value|state` per line) between `GOLDEN BEGIN`/`GOLDEN END`.
- `tools/golden/` capture + check scripts (PowerShell and sh variants so both
  Windows and Linux environments can run them). The reference log
  `tools/golden/battle.log` is committed once at A3 and regenerated only
  deliberately — never to make a red diff green.

### 0.6 Composability proof — the crafting demo (A8)

The architecture is accepted only when a small **Item Creation** system can be
authored as *data*: a common event (attachable to an NPC or town option) that
lets the player pick a recipe (CHOICE), checks ingredients (hasItem
conditions / IF), consumes them (TAKE_ITEM), rolls success against a formula
(IF + random), and grants the crafted item (GIVE_ITEM_ID) or a consolation
text. If A8 needs bespoke Lua beyond the generic v1 commands, the command set —
not the demo — is what gets fixed.

### 0.7 Non-goals this round

Full menu scripting (input loops as data), enemy AI scripting, dialogue-graph
editor UI, the recruit system. The interpreter is built so these become data
work later, but none ships this round.

---

## Part 1 — Human plan (multi-environment delegation)

You will be routing tasks across **Claude Code**, **Google Antigravity**, and
**Google Jules**, switching by rate limits, possibly with API-key sub-LLM calls
(Gemma 24B, Gemini Flash 2.5 Lite) for bulk text work. The plan therefore
standardizes on things that survive vendor switching: self-contained briefs in
this file, mechanical gates (G1–G3), a fixed branch/PR protocol, and a
verification-debt rule for environments that can't run a gate.

### 1.1 What each environment is good for (capability first, vendor second)

| Environment | Runtime capabilities | Best-fit tasks | Avoid |
|---|---|---|---|
| **Claude Code (local, Windows)** | Full: LOVE runtime, node, browser preview, git push | A2/A4 core, A5b/A5d (the two risky conversions), integration merges, review gates | Burning limits on recon or bulk JSON |
| **Google Antigravity (local IDE, Windows)** | Full local runtime + browser tooling | All B tasks (UI-heavy, screenshot-verifiable), A6 editor work, re-running gates on Jules PRs | Deep multi-file engine refactors if its diffs get sloppy — judge per result |
| **Google Jules (cloud Linux VM, async)** | Repo + shell; `apt-get install love` works for G1 (headless may need xvfb — if it fails, declare debt); node works for server-side checks; **no real browser** | A1 recon, A7 validator, A5a/A5c/A5e (golden-checkable), B4 server endpoint, doc tasks | Anything needing G3 (browser) as its primary gate; anything touching index.html pre-B0 concurrently with another task |
| **API-key sub-LLMs (Gemma 24B, Flash 2.5 Lite)** | Text-in/text-out only | Bulk generation *inside* a bigger agent's loop: label/description tables, formulaHelp entries, flows.json drafts from the A1 inventory, JSON reshaping, commit-message drafting | Never as autonomous repo writers; never as the sole reviewer of engine-semantics changes |

Vendor-strength heuristics (useful, but weaker than brief quality + gates):
Gemini-family agents tend to shine on long-context repo sweeps and
screenshot-matching UI work; Claude agents on careful multi-step refactors with
test discipline; Jules on well-specified, low-supervision chores. When limits
force a swap, swap — the gates keep the quality floor, not the vendor.

A practical sub-LLM pattern that respects safety: the orchestrating agent (any
environment) writes a short script that calls your API for the bulk generation
(e.g., "produce flows.json victory/round_end drafts from flow-inventory.md"),
then *reviews and commits the output itself*. The small model never holds the
pen on engine code.

### 1.2 Capability tags on every task

Each brief in Part 2 carries tags:

- **[G1]** needs LOVE runtime (any OS) — Jules usually can, with apt + possible
  xvfb; otherwise debt.
- **[G2]** needs the golden check (same requirement as G1 once A3 lands).
- **[G3]** needs a real browser against the node server — local environments
  only.
- **[TEXT]** no runtime needed.

### 1.3 Sequencing

```
Stage 1 (parallel):   A1 [TEXT→Jules]   A3 [G1→local]   B0 [G3→local/Antigravity]
Stage 2:              A2 [G1]  ──▶  A4 [G1,G2]  ──▶ review gate (frontier)
Stage 3 (parallel):   A5a,c,e [G1,G2→Jules ok]   A5b,d [G1,G2→local]   B1..B4 [G3, post-B0 parallel]
Stage 4:              A6 [G3]   A7 [G1→Jules]   A8 [G1,G3]   B5 [G3]
Stage 5:              review gate ▶ merge fable-5-overhaul-3 ▶ human play-test
```

Serialization constraints: nothing touches `tools/editor/index.html` in
parallel until B0 merges; A5 tasks may run in parallel with each other (they
touch disjoint Lua blocks + disjoint flows.json keys) but merge one at a time,
easiest first (A5a → A5c → A5e → A5b → A5d), re-running G2 after each merge.

### 1.4 Protocols that make vendor-hopping safe

- **Briefing template (works verbatim in all three environments):**
  > Read `docs/plans/overhaul-3.md` in JosephSerUSP/Hichaukitoden, branch
  > `fable-5-overhaul-3`. Execute task **[ID]** from Part 2 only, following the
  > ground rules at the top. Branch: `o3/[id]-short-name`. Stop when the
  > acceptance checklist passes; fill in the PR checklist.
- **PR checklist (paste into every PR description):**
  > Gates: [ ] G1 validate [ ] G2 golden [ ] G3 editor-console.
  > Unchecked = verification debt; state the reason (e.g. "Jules: no browser").
  > Spec deviations: none / list. Files touched outside the brief's list: none / list.
- **Verification debt** is cleared before merge by any full-capability
  environment (a 5-minute Antigravity/Claude Code session: pull branch, run
  gates, comment results). Debt never merges silently.
- **Review gates:** after A4 and after Stage 3, run a code review in whichever
  environment has budget (`/code-review` in Claude Code; the A2+A4 core
  justifies the heavyweight review tier if available). The one thing to eyeball
  personally regardless of tooling: the sandbox env table in the formula
  module — nothing from `_G` may leak in.
- **Escalation rule:** if any single task bounces twice with a red gate, stop
  iterating in-place and pull it up one capability tier (bigger model or local
  environment) with the failure logs pasted into the brief.

### 1.5 What not to delegate at all

Spec changes to Part 0; the A4 merge decision; the final play-test. Those are
yours (with a frontier model when limits allow).

---

## Part 2 — Agent briefs

> Shared verification:
> - G1: `& "C:\Program Files\LOVE\lovec.exe" . validate` (Windows) or
>   `love . validate` (Linux, `apt-get install love`, may need `xvfb-run`) →
>   must end `VALIDATE OK`.
> - G2: `tools/golden/check` script green (after A3).
> - G3: `node tools/editor/server.js` → `http://127.0.0.1:8080`, exercise the
>   changed UI, zero console errors.

### A1 — Hardcode inventory [TEXT]

Produce `docs/plans/flow-inventory.md`: an exhaustive table of every hardcoded
calculation, branch, constant, and player-facing behavior in `main.lua`,
`engine/battle.lua`, `engine/exploration.lua`, `engine/session.lua`,
`engine/effects.lua` not already read from `data/*.json`. Columns:
`file:line | behavior | proposed phase | proposed command(s) | notes`. Group by
proposed phase. Must cover at minimum: victory rewards, state ticks, MP
drain/exhaustion, flee resolution, encounter roll + enemy composition, defeat
reset, level-up HP refill, treasure GIVE_ITEM path. Read-only — no code
changes. Acceptance: doc exists with file:line for every row.

### A2 — Formula engine [G1]

Implement `engine/formula.lua` per §0.4 (API `formula.eval(expr, ctx)`, sandbox
rule, helper whitelist, context snapshot builders for battlers/party/enemies/
session/combat/v). Keep `engine/effects.lua`'s `evaluateFormula` as a wrapper;
all existing `data/skills.json` formulas must keep working. Write
`engine.json → formulaHelp` (every token + description). Acceptance: G1 green;
a validation check compiles a representative reward-curve expression using
`enemy.*`, `session.floor`, `random`, and rounding against a mock context;
grep shows `load(` only with an explicit env argument.

### A3 — Golden-master harness [G1]

Implement §0.5: the `validate golden` mode in `main.lua`, normalized event-log
dump, `tools/golden/` capture+check scripts (both `.ps1` and `.sh`), commit the
initial `tools/golden/battle.log`. Fixed seed, explicit party construction, no
newgame randomness. Acceptance: check mode passes twice consecutively; editing
any damage formula in `data/skills.json` turns it red (then revert).

### A4 — Unified interpreter + command registry [G1][G2]

Implement §0.1–§0.3: `engine/interpreter.lua` with `runInteractive` (absorb
`compileCommands` from `main.lua` — main.lua keeps only thin glue) and
`runImmediate`; `engine/flow.lua` (`flow.run(phase, ctx)`, `flow.has(phase)`);
`data/flows.json` (empty `battle` object); `engine.json → commands` with the
full §0.2 registry (existing interactive command ids included, with `contexts`
and `interactive` flags). Add `flows` to BOTH server manifests. Handlers for
every v1 command, exercised by a `_test` scene key in flows.json that the
validator runs in immediate mode (interactive commands excluded). Do NOT
convert any live phase — that's A5. Header comment documents ctx shape and how
a future host (menu) declares phases. Acceptance: G1+G2 green; map/common
events still play identically (they now run through the interpreter);
`_test` phase exercises every non-interactive command without error.

### A5a — Convert victory rewards [G1][G2] · A5b — round-end ticks [G1][G2] · A5c — flee resolution [G1][G2] · A5d — battle start/encounter [G1][G2] · A5e — defeat/escape [G1][G2]

Each task: move the corresponding hardcoded block (per `flow-inventory.md`)
into `data/flows.json` default phases using registry commands only, guarded by
`if not flow.has(phase)` legacy fallback in Lua. Defaults must reproduce
current behavior exactly — G2 is the arbiter (event ordering included). A5d
additionally implements `ROLL_ENCOUNTER`/`SPAWN_ENEMIES` handlers + registry
entries. A5e uses `SCENE_EVENT` so the interpreter never touches scene state
directly. Acceptance per task: G1+G2 green; the moved Lua block is reduced to
the fallback guard + legacy body (deleted only after a full round of green
merges, as a follow-up cleanup).

### A6 — One command palette, everywhere [G3]

Extend the editor's existing command UI (`renderCommandList` + the command
modal) to be **registry-driven**: the add/edit dialog builds its fields from
`engine.json → commands` param schemas (`formula` params get an ⓘ popover
listing `formulaHelp`; `term`/`state`/`item`/`skill` params get pickers;
`commands` params render nested lists like CHOICE branches today). The palette
filters by host context: Event editor + Common Events offer `map`/`common`
commands; a new **Flows** tab in the Engine window (scene select → phase select
with "has data / legacy" badges) offers `battle_phase` commands. Include the
`{ } JSON` toggle per phase. Acceptance: every registry command is addable/
editable/nestable in its valid hosts and absent from invalid ones; a phase
edited in the UI changes behavior in a test play; G3 green.

### A7 — Validator coverage for the unified system [G1]

Extend `runValidation`: every `cmd` exists in the registry; commands only
appear in hosts allowed by `contexts`; `interactive` commands never appear in
immediate hosts (flows.json); every formula/condition compiles against a mock
context; `term`/`state`/`item`/`scope`/`battlerRef` params resolve; nested
lists recurse. Acceptance: G1 green on clean data; corrupting a cmd id, a
formula, and a context placement each turn it red (then revert).

### A8 — Composability proof: Item Creation demo [G1][G3]

Author §0.6's crafting system as pure data: a new common event "Workbench"
(recipe CHOICE built from 2–3 recipes; ingredient checks; TAKE_ITEM;
success-roll IF with a formula using `session` context; GIVE_ITEM_ID on
success, consolation EMIT_TEXT/TEXT on failure), attach it to a town option or
a map event on the town map. If any step is impossible without new Lua, STOP
and file a report naming the missing command instead of adding bespoke code.
Acceptance: crafting works in a play session; `git diff --stat` shows data/
editor files only (no engine/*.lua changes); G1 green.

### B0 — Split the editor into modules [G3] (enabler — do early)

`tools/editor/index.html` is ~4k lines and is the merge bottleneck. Split the
inline script into ES modules or plain scripts served by the existing static
server: `js/state.js` (dbPayload, dirty), `js/widgets.js` (makeSelect, list
editors, pickers), `js/database.js` (tabs/forms), `js/engine-editor.js`,
`js/map-editor.js`, `js/events.js` (command list/modal), `js/net.js`
(fetch/save/assets). No behavior changes; keep load order explicit; keep
`onclick=` handlers working (export to `window` where needed). Acceptance: G3
green across a full click-through (all DB tabs, Engine tabs, map paint, event
modal, save round-trip); diff of served page behavior = none.

### B1 — Icon picker widget [G3]

Iconset: `assets/system/iconset.png`, 12×12 cells, 10 columns, ids 1-indexed
(`col=(id-1)%10`, `row=floor((id-1)/10)` — see `presentation/ui.lua →
ui.drawIcon`); the editor server already serves `assets/*`. Build
`openIconPicker(currentId, cb)`: modal grid of cells (CSS background-position
or canvas), hover shows id, click selects. Replace every numeric "Icon #" field
(items, passives, states, elements) with preview swatch + "Pick…" button.
Acceptance: picking updates payload + preview in all four forms; G3 green.

### B2 — Layout pass with inner tabs [G3]

Reference style: RPG Maker VX Ace "Terms" screen — dense grouped `fieldset`s,
labels **above** narrow inputs, 2–4 columns per group, horizontal inner tabs
instead of long scrolls. Build reusable `buildTabbedSections` +
`buildFieldGroup(title, cols)` helpers; apply to Engine window tabs (Battle
Flow currently wastes half the panel), Database System tab, and Terms tab
(top-level keys become inner tabs). Keep collapsibles only at depth ≥ 2. No
data-binding changes. Acceptance: before/after screenshots; no horizontal
scrollbars at 1280×800; G3 green.

### B3 — Color-coded JSON editing [G3]

Upgrade `attachJsonToggle` to a highlighted editor: transparent `<textarea>`
over a scroll-synced `<pre>` re-tokenized on input (keys/strings/numbers/
booleans distinct), no external dependencies, keep the red invalid state.
Acceptance: responsive on `data/system.json`; Apply/Back unchanged; G3 green.

### B4 — More data pickers [G3, server part TEXT]

1. `GET /api/graphs` in `tools/editor/server.js` → basenames of
   `data/graphs/*.json`.
2. Widgets: `graphPicker` (used by town-option `graph` fields), `mapPicker`
   (extract the existing inline select), `termPicker` (dotted-path tree of
   `dbPayload.terms`; A6 consumes it via the registry param type — coordinate
   through `engine.json`, not shared code).
Acceptance: town options use the graph dropdown; endpoint lists all graphs; G3
green.

### B5 — Polish batch [G3]

Tooltips on effect/trait/command dropdowns from registry descriptions;
`min`/`step` from `CONFIG_SCHEMA` everywhere; `field-help` rendering for
schema `help` strings; Enter-to-apply in Change Maximum. Acceptance: visual
spot-check; G3 green.
