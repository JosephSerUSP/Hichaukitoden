# SPEC — Unified Event Engine (Overhaul 3)

Audience: an agent executing ONE task. Your brief tells you which sections to
read. Do not change this spec; if your task conflicts with it, stop and report.

## Ground rules (every task, every environment)

1. Work on a task branch `o3/<id>-<short-name>` cut from the integration
   branch `fable-5-overhaul-3`.
2. Gates — run all that your environment supports; declare the rest as
   unchecked "verification debt" in your PR description with the reason:
   - **G1 validate:** `& "C:\Program Files\LOVE\lovec.exe" . validate`
     (Windows) or `love . validate` (Linux; `apt-get install love`, may need
     `xvfb-run`). Must end `VALIDATE OK`.
   - **G2 golden:** run the check script in `tools/golden/` (exists after task
     A3). The committed reference log must remain byte-identical. Never
     regenerate the log to make a red diff green.
   - **G3 editor:** `node tools/editor/server.js`, open
     `http://127.0.0.1:8080`, exercise the changed UI, zero console errors.
3. New data files go into BOTH server manifests: `DATA_FILES` in
   `engine/server.lua` AND in `tools/editor/server.js`.
4. Do not edit `tools/editor/index.html` if another task might be running
   against it, unless your brief says the B0 module split has merged.
5. End your PR description with this checklist, filled honestly:
   > Gates: [ ] G1 validate [ ] G2 golden [ ] G3 editor-console.
   > Unchecked = verification debt; reason: …
   > Spec deviations: none / list.
   > Files touched outside the brief's list: none / list.

## S1 — One command language, one interpreter

Today there are two half-languages: map/common-event commands (`TEXT`,
`CHOICE`, `CONDITIONAL_BRANCH`, `GIVE_ITEM`, `BATTLE`, …) compiled by
`compileCommands` in `main.lua`, and hardcoded Lua for everything the engine
itself does. This round merges them.

- **`engine/interpreter.lua`** owns command semantics. Two run modes:
  - `interpreter.runInteractive(commands, ctx)` — player-paced; absorbs the
    current `compileCommands`/GraphWalker path (TEXT waits for input, CHOICE
    branches on selection). Map events, common events, dialogue keep working
    exactly as now, through this door.
  - `interpreter.runImmediate(commands, ctx) -> events[]` — synchronous; for
    engine phases (battle round end, victory, …). Emits the same event stream
    (`damage`, `heal`, `text`, `mp_drain`, …) the battle log/renderer already
    consumes. Interactive commands are **invalid** here (validator enforces).
- **`engine.json → commands`** is the single registry. Entry shape:

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
  `text`, `number`, `flag`, `script` (multiline Lua — see S6).
- Because NPC/chest/common events run on the same registry, every command
  whose `contexts` includes `map`/`common` automatically appears in the
  existing Event editor. That is the point: system-grade blocks become
  available to ordinary game eventing.

## S2 — Command set v1

Existing interactive commands keep their ids and behavior: `TEXT`, `CHOICE`,
`CONDITIONAL_BRANCH`, `RECOVER_PARTY`, `DESCEND`, `BATTLE`, `GIVE_ITEM`,
`CALL_COMMON_EVENT`. New v1 commands (non-interactive unless noted):

| id | params | notes |
|---|---|---|
| `COMMENT` | text | no-op; documentation only; valid in ALL contexts and both run modes; interpreter skips it entirely |
| `SET_VAR` | name, value:formula | flow-local variable, readable as `v.name` in formulas |
| `SET_FLAG` | flag, value | session flag (same flags conditions read) |
| `IF` | condition:formula, then:commands, else:commands | CONDITIONAL_BRANCH's string conditions stay valid alongside |
| `FOR_EACH` | scope, as, do:commands | scope ∈ enemies, living_enemies, allies, living_allies, party |
| `GAIN_GOLD` | amount:formula | clamped ≥ 0 |
| `GRANT_XP` | target:battlerRef, amount:formula | |
| `DAMAGE` / `HEAL` | target:battlerRef, amount:formula | routed through `effects.apply` so death/events stay consistent |
| `ADD_STATE` / `REMOVE_STATE` | target:battlerRef, state, duration? | |
| `DRAIN_MP` / `RESTORE_MP` | amount:formula | shared pool |
| `STATE_TICKS` | — | the regen/poison/duration-decay block as one block command |
| `TRAIT_HEAL` | target:battlerRef, trait | generalizes POST_BATTLE_HEAL |
| `EMIT_TEXT` | term, fallback?, args? | battle-log/text event via formatTerm |
| `TAKE_ITEM` | item, count? | inventory remove (fails soft) |
| `GIVE_ITEM_ID` | item, count? | specific item (`GIVE_ITEM` stays the "random treasure" command) |
| `ROLL_ENCOUNTER` | chance:formula | added in task A5d |
| `SPAWN_ENEMIES` | count:formula, table | weighted pick from map encounters; task A5d |
| `SCENE_EVENT` | kind | emits a `scene_change`-style event main.lua consumes; the interpreter never switches scenes itself |
| `SCRIPT` | code:script | sandboxed Lua escape hatch — see S6; forbidden in shipped default flows |

Adding a command later = one Lua handler + one registry entry; editor and
validator pick it up from the registry with zero editor code.

## S3 — Comments

Two mechanisms, both inert at runtime:

1. The `COMMENT` command (table above): a standalone documentation row in any
   command list, RPG-Maker style.
2. **Every command may carry an optional `comment` string field.** The
   interpreter and validator ignore it (it must not trip unknown-param
   checks). The editor's command edit dialog always offers a small "Comment"
   input; the field is stored only when non-empty.

Editor rendering: `COMMENT` rows and per-command comment lines render in a
distinct color (green, monospace) beneath their command. A **"Show comments"
toggle** in every command-list header shows/hides them (persist the preference
in `localStorage`; default on).

## S4 — Hosts and phases

`data/flows.json` maps scene phases to command lists (immediate mode):

```json
{ "battle": {
    "victory": [
      { "cmd": "COMMENT", "text": "Rewards: gold per enemy, XP per survivor" },
      { "cmd": "FOR_EACH", "scope": "enemies", "as": "enemy", "do": [
        { "cmd": "GAIN_GOLD", "amount": "<formula>" } ] },
      { "cmd": "FOR_EACH", "scope": "living_allies", "as": "ally", "do": [
        { "cmd": "GRANT_XP", "target": "ally", "amount": "combat.victoryExp" },
        { "cmd": "TRAIT_HEAL", "target": "ally", "trait": "POST_BATTLE_HEAL" } ] },
      { "cmd": "EMIT_TEXT", "term": "battle.victory_full" } ] } }
```

Phase names v1: `battle.encounter_check`, `battle.battle_start`,
`battle.flee_attempt`, `battle.round_end`, `battle.victory`, `battle.defeat`,
`battle.escaped`.

**Fallback rule:** a phase absent from `flows.json` runs the legacy Lua block
(`if not flow.has(phase)` guards). Every conversion is independently shippable
and revertable. `engine/flow.lua` exposes `flow.run(phase, ctx) -> events[]`
and `flow.has(phase)`.

## S5 — Formulas (a param type, not the architecture)

Where a number is needed, a `formula` param accepts an expression over a
documented, sandboxed context.

- Syntax is the implementer's choice (realistically Lua expression syntax,
  since evaluation is sandboxed `load`), but it must be documented in data:
  `engine.json → formulaHelp` = array of `{ token, description }` for every
  variable and helper. The requirement is expressiveness: reward curves over
  `enemy.level / enemy.maxHp / session.floor / party.aliveCount` with
  randomness and rounding must be writable in one line — and equivalently
  composable as a `SET_VAR` chain for designers who prefer pure blocks.
- Sandbox: fresh env table via `load(expr, name, "t", env)`; whitelisted
  helpers only (`random`, `floor`, `ceil`, `round`, `abs`, `min`, `max`,
  `clamp`); no `_G`/`os`/`io`/`love`/`require`.
- Context (read-only snapshots where applicable): `a`/`b`/`target`/`enemy`/
  `ally` battler views (`level, hp, maxHp, atk, def, mat, mdf`), `party` and
  `enemies` aggregates (`size/count, aliveCount, avgLevel, totalLevel,
  totalMaxHp`), `session` (`gold, mp, maxMp, floor`), `battle` (`round`),
  `combat` (the system.json combat table), `v` (flow-locals).
- On error: fallback 0, log once, validator flags it.
- Deterministic under `math.randomseed` (golden harness depends on it); do not
  reseed inside the module.

## S6 — Script Call (sandboxed escape hatch)

`SCRIPT` executes a multiline Lua chunk from event/flow data, so one-off ideas
never block on a missing command. Recurring script patterns are the backlog
for new registered commands.

- **Curated environment, not raw globals.** Same sandbox family as formulas,
  widened: `ctx` (live handles — session view, battle, actor, target, `v`
  flow-locals), the `math`/`string`/`table` stdlib, the seeded `random`, and
  an **`api` table whose mutators route through existing pipelines so the
  event stream stays consistent**: `api.damage(target, n)` /
  `api.heal(target, n)` (via `effects.apply` — death/animation/log events emit
  normally), `api.giveItem(id, n)`, `api.takeItem(id, n)`, `api.gainGold(n)`,
  `api.grantXp(target, n)`, `api.addState(target, id, dur)` /
  `api.removeState(target, id)`, `api.setFlag(flag, val)`, `api.emit(event)`.
  Explicitly absent: `io`, `os`, `love`, `require`, raw `loader`/`session`
  mutation.
- **Owner opt-out:** `engine.json → scripting.allowRawAccess` (default
  `false`) additionally injects real `session`/`loader` references.
- **Zero-SCRIPT rule:** the default `battle.*` phases written by the A5
  conversions must contain no `SCRIPT` commands — validator-enforced.
- **Determinism:** scripts using the provided `random` stay golden-compatible.
- Documented in `engine.json → scriptingHelp` (same pattern as `formulaHelp`).

## S7 — Golden-master harness

Extension of the existing `validate` CLI mode:

- `love . validate golden` — seeds `math.randomseed(12345)`, constructs a
  fixed party/enemy setup explicitly (no newgame randomness), runs a scripted
  3-round battle (round 1 all attack; round 2 spell+defend+attacks; round 3
  flee) plus one victory resolution, and prints a normalized event log
  (`type|actor|target|value|state` per line) between `GOLDEN BEGIN` /
  `GOLDEN END` markers.
- `tools/golden/` holds capture + check scripts (`.ps1` and `.sh` variants)
  and the committed reference log `tools/golden/battle.log`.

## S8 — Composability proof (crafting)

The architecture is accepted only when a small Item Creation system can be
authored as pure data: a common event that lets the player pick a recipe
(CHOICE), checks ingredients (hasItem conditions / IF), consumes them
(TAKE_ITEM), rolls success against a formula (IF + random), and grants the
crafted item (GIVE_ITEM_ID) or a consolation text. If that needs bespoke Lua,
the command set — not the demo — is what gets fixed. `SCRIPT` is off-limits in
the demo: it would hide gaps in the block set.

## S9 — Non-goals this round

Full menu scripting (input loops as data), enemy AI scripting, dialogue-graph
editor UI, the recruit system. The interpreter is built so these become data
work later; none ships now.
