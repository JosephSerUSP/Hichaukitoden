# SPEC — Scenes as Data (Overhaul 4)

Audience: an agent executing ONE task. Your brief tells you which sections to
read. Do not change this spec; if your task conflicts with it, stop and report.

Integration branch: `fable-5-overhaul-4`. Ground rules and gates: identical to
overhaul-3's SPEC §Ground rules (G1 validate, G2 golden, G3 editor). Integrator
protocol: `docs/ORCHESTRATION.md`.

## S0 — Why, and the reference frame

Overhaul 3 made *game logic* data. It did not make *scenes* data. Today
`engine/scenes/crafting.lua` is 570 lines, ~62% of which is `drawCraftingScene`
(190) and `keypressedCraftingScene` (166) — drawing windows and moving a
cursor. The yield formula, outcome brackets and disciplines are already data.
So the hardcoded surface is **presentation and input**, not rules.

**RPG Maker is a reference for what a scene *is to the player*** — a discrete,
named, full-screen mode with its own windows, cursor and input grammar
(Scene_Title, Scene_MainMenu, Scene_Item, Scene_Status, Scene_Shop). It is
**not** an implementation template: RPG Maker's `Scene_*` and `Window_*` are
script classes, and MZ hardcodes a great deal. We are free to do better, and
this spec does something RPG Maker does not: make scene *behavior* authorable.

## S1 — The central move: the loop stays in code, the reactions become data

The naive reading of "scenes as event commands" is a blocking input loop in
data (`WAIT_INPUT`, `LOOP`, …). That demands a coroutine VM, is hostile to the
validator, and is untestable against a golden log. Overhaul 3's SPEC S9 rejected
it for exactly these reasons. We keep that rejection.

Instead:

> **The scene host owns the frame loop, rendering and cursor state.
> The data owns what happens.**

A scene is a set of **named command lists bound to lifecycle hooks**. Each hook
fires as a synchronous `interpreter.runImmediate` call — *the existing engine,
unchanged*. No third execution model, no coroutines.

This is precisely why the owner's observation is correct: a scene has the same
shape as `battle.victory` / `battle.round_end`. A scene phase and a battle
phase are the same object.

## S2 — Scene model

`data/scenes.json` (already in both manifests) becomes:

```json
{ "id": 3, "name": "Item Creation", "kind": "crafting",
  "config": { "alpha": 0.25, "disciplines": [ … ] },
  "hooks": {
    "on_enter":  [ { "cmd": "OPEN_WINDOW", "window": "discipline_list" } ],
    "on_select": [ { "cmd": "IF", "condition": "…", "then": [ … ] } ],
    "on_cancel": [ { "cmd": "SCENE_EVENT", "kind": "pop" } ],
    "on_frame":  [ … ],
    "on_exit":   [ … ]
  } }
```

- **Hook names v1:** `on_enter`, `on_exit`, `on_select` (confirm on the focused
  item), `on_cancel`, `on_cursor_move`, `on_frame`.
- Hooks run in **immediate mode**. Interactive commands are invalid inside them
  (validator-enforced), exactly as in `flows.json`.
- `kind` selects the host that supplies the scene's *nouns* (what a "list row"
  means). v1 kinds: `menu`, `crafting`. A kind with no bespoke host is a plain
  `menu`.
- **Scene-local variables** reuse `v` (flow-locals), scoped to the scene
  instance, so `SET_VAR` → `IF` chains work as they do in flows.
- `config` stays a small property bag (numbers, formulas, tables). It is *data
  the hooks read*, not behavior.

**Fallback rule (as in overhaul-3 S4):** a hook absent from `scenes.json` runs
the legacy Lua block. Every conversion is independently shippable and
revertable. That is what makes S6's ordering safe.

## S3 — Scene identity and navigation

- Scenes have **numeric ids** and stable string keys. Built-in scenes are
  authored as data with reserved ids: `title`, `main_menu`, `item`, `status`,
  `shop`, `crafting`, `battle`.
- Navigation is data: `SCENE_EVENT { kind: "push"|"pop"|"goto", scene: <id> }`
  emits an event the host consumes. **The interpreter never switches scenes
  itself** — unchanged from overhaul-3 S2.
- A scene **stack** (push/pop) replaces the current `previousSceneBeforeMenu`
  ad-hoc variable in `main.lua`.
- New scenes are creatable in the editor and get a fresh numeric id.

## S4 — The UI command vocabulary (the real work)

Hooks are useless without commands that manipulate the scene's windows. These
are new registry entries with `contexts: ["scene"]`, non-interactive:

| id | params | notes |
|---|---|---|
| `OPEN_WINDOW` | window, rect?, style? | window is a key into the scene's window set |
| `CLOSE_WINDOW` | window | |
| `SET_LIST` | window, source, format? | `source` = a list expression (inventory, party, `v.pool`) |
| `SET_TEXT` | window, term/text, args? | reuses `formatTerm` |
| `SET_CURSOR` | window, index:formula | |
| `FOCUS_WINDOW` | window | which window receives input |
| `PLAY_ANIM` | anim, args? | e.g. the crafting roulette |
| `WAIT` | seconds:formula | host-timed, non-blocking (defers remaining hook) |
| `SCENE_EVENT` | kind, scene? | push/pop/goto (S3) |

Window geometry and style live in data (`engine.json → windowLayout`), the same
way C4 moved battle coordinates into `battleLayout`. **BIBLE.md still holds: no
hardcoded coordinates.**

`WAIT` is the one concession to time. It does not block; the host suspends the
remaining commands of that hook and resumes them after the delay. This is
enough for the roulette (S7) without a coroutine VM.

## S5 — Validator and golden coverage

- Scene hooks validate exactly like flow phases: every `cmd` in the registry,
  `contexts` includes `scene`, no interactive commands, formulas compile,
  `window` params resolve to a declared window, `scene` params resolve to a
  scene id. Unknown `kind` is an error.
- **A golden harness for scenes.** Extend `validate golden` with
  `love . validate golden-ui`: drive a scripted input sequence (down, down,
  confirm, cancel, …) through a scene and print a normalized UI event log
  (`window|action|target|value` per line) between `UI GOLDEN BEGIN/END`, with
  a committed reference at `tools/golden/scene_<key>.log`.
  This is what makes deleting `keypressedCraftingScene` safe rather than
  terrifying. Same discipline as `battle.log`: **never regenerate to make a
  red diff green** (see `docs/ORCHESTRATION.md` §5).

## S6 — Conversion order (easiest first, golden-locked last)

1. **Crafting** — newest, least entangled, and its logic is already data. The
   composability proof for scenes, exactly as A8 was for commands.
2. **Title** — trivial; validates `on_select` + `SCENE_EVENT`.
3. **Main Menu / Item / Status** — proves the vocabulary generalises across
   list-driven menus and fixes the ESC/navigation feel.
4. **Shop** — has conditions and gold; proves formulas in a menu context.
5. **Battle — last.** Most entangled and `battle.log`-locked. Do not attempt
   until the vocabulary has survived the four above.

**The S8 rule, restated:** if a scene needs bespoke Lua, the *command set* gets
fixed — not the scene. `SCRIPT` is off-limits in shipped scene hooks; it would
hide gaps in the vocabulary. Validator-enforced (zero-SCRIPT for `scenes.json`).

> **AMENDMENT (owner feedback, 09.07.2026 — see FEEDBACK.md):** the zero-SCRIPT
> rule applies to **built-in scenes only** (title, menu, items, status, shop,
> battle). **Extra** (user-authored) scenes may use `SCRIPT` — it is their
> escape hatch, and the vocabulary must stay generic rather than grow
> hyper-specific commands (e.g. `CALC_CRAFT_YIELD` is deprecated). Item
> Creation (crafting) is reclassified as the sample *extra* scene and must end
> up with nothing hardcoded for it — including no `crafting` scene kind
> (brief D13).

Success criterion for each conversion: the scene's Lua shrinks to a thin host,
behavior is unchanged (UI-golden byte-identical), and every value it reads is
editable in the editor.

## S7 — Crafting, restated in this model

The Star Ocean-style dynamic crafting (yield `Y = floor((I1+I2)/2) +
floor(alpha*S)`, bracket pools, element-conflict/stat-deficit failure, ~5%
anomaly crit) is already data in `scenes.json → config`, reading item `meta`
(overhaul-3 C10). Under S2 the remaining Lua becomes hooks:

- `on_enter` → `OPEN_WINDOW` discipline list, `SET_LIST` from disciplines
- `on_select` → `IF` on selection depth: pick discipline → ingredients →
  compute yield (`SET_VAR` + formulas) → build pool (`SET_LIST` on `v.pool`)
  → `PLAY_ANIM roulette` → `WAIT` → `CHANGE_ITEM` consume/grant → `SET_TEXT`
- `on_cancel` → step back a level, or `SCENE_EVENT pop`

No new game logic. The 570 lines become a host + data.

## S8 — Editor: one model, one tab

The "Custom Scenes" property form and the "Phase Flows" command-list editor
collapse into **one Flows editor**. A scene is selected, its hooks listed as
phases, each hook edited with the existing `renderCommandList` + A6/C1 command
palette (filtered to `contexts: ["scene"]`). Scene `config` remains a small
property panel *inside* the scene, not a rival paradigm. `{ } JSON` toggle per
hook, as per overhaul-3 A6.

This directly resolves the owner's complaint. It is mostly deletion.

## S9 — Non-goals this round

Blocking input loops as data (S1). A visual WYSIWYG scene layout editor —
though S4's `windowLayout` data is its prerequisite, and the deferred
"interpret the Lua in JS for an accurate preview" idea becomes tractable only
once windows are declarative. Enemy AI scripting. The recruit system.

**Audio — deliberately deferred.** The sound design is not defined yet and is
lower priority than getting scenes working. Note the trap: `data/sounds.json`
exists, is loaded by `data/loader.lua` and shipped to the editor, but nothing
consumes it — there is no audio system anywhere in the engine (no `love.audio`,
no `newSource`). That implied-but-absent system is what led an agent to
hallucinate 21 calls to a non-existent `session:playSound()` in the C9 crafting
scene, and led two proposed "fixes" to want a `PLAY_SOUND` command backed by a
no-op stub.

Rules until audio is designed:
- **Do NOT register a `PLAY_SOUND` command**, and do not add `playSound` stubs.
  The validator now enforces this: every command in `engine.json → commands`
  must have a handler in `engine/interpreter.lua` (`interpreter.isImplemented`),
  so a stub command fails G1 by name.
- `sounds.json` is aspirational data with no consumer. Leave it inert.
- When audio is designed, it lands as one brief: an audio module reading
  `sounds.json`, plus `PLAY_SOUND` registered **together with a working
  handler** — never before.

## S10 — Task decomposition (briefs)

| id | task | gates |
|---|---|---|
| D1 | Scene host + hooks; `scenes.json` gains `hooks`; fallback to legacy Lua | G1 G2 |
| D2 | UI command vocabulary (S4) + `engine.json → windowLayout` | G1 G2 G3 |
| D3 | UI-golden harness `validate golden-ui` (S5) | G1 G2 |
| D4 | Convert Crafting to hooks (S7) — composability proof | G1 G2 G3 + UI-golden |
| D5 | Editor: unify Flows/Scenes into one tab (S8) | G1 G3 |
| D6 | Convert Title, Main Menu, Item, Status | G1 G3 + UI-golden |
| D7 | Convert Shop | G1 G3 + UI-golden |
| D8 | Battle as scene — **local only**, `battle.log`-sensitive | G1 G2 G3 |

D1–D3 are prerequisites and should land before any conversion. D3 before D4:
build the safety net before the first jump.
