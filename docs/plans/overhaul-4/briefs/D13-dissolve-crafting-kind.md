# D13: Dissolve the "crafting" Scene Kind

**Context:** Owner feedback 09.07.2026 (FEEDBACK.md) + SPEC S6 amendment. Item
Creation is the sample **extra** scene: it must be authorable entirely in the
editor, with NOTHING hardcoded for it in the engine or editor — no `crafting`
kind, no crafting-specific commands, no bespoke Lua host.

**Role:** LOCAL preferred (touches UI-golden references and the generic
renderer battle work will reuse).

## Current hardcoding inventory (what this brief deletes)

| Where | What |
|---|---|
| `engine/scenes/crafting.lua` (~736 lines) | Bespoke host: rendering, module-local `inventoryItems`, `calcCraftYield`, roulette |
| `engine/interpreter.lua` | `CALC_CRAFT_YIELD` and `START_ROULETTE` handlers |
| `data/engine.json → commands` | `CALC_CRAFT_YIELD` (already `deprecatedBy: SCRIPT`), `START_ROULETTE` |
| `main.lua` validateScenes | `if scene.kind == "crafting"` block (disciplines/formulas/brackets checks) |
| `tools/editor/js/engine-editor.js` | `if (scene.kind === 'crafting')` config field block |
| `data/scenes.json` crafting entry | `kind: "crafting"` |

## Acceptance Criteria

- [ ] Generic window rendering: the D2 vocabulary (OPEN_WINDOW/SET_LIST/
      SET_TEXT/SET_CURSOR/FOCUS_WINDOW + `engine.json → windowLayout`) actually
      draws windows, lists, text, and portraits — no crafting-specific draw code.
- [ ] Inventory/list state lives in scene `v` (e.g. `v.inventory` built by
      hooks), not in a module-local; the renderer reads what the hooks set.
- [ ] Yield/pool computation moves into a `SCRIPT` call in the crafting scene's
      hooks (permitted: crafting is an extra scene). The SCRIPT sandbox may
      need small **generic** additions: read access to `scene.config`, a
      formula-eval helper (`api.eval`), and an inventory query (`api.items`).
      Nothing crafting-named goes into the API.
- [ ] `CALC_CRAFT_YIELD` and `START_ROULETTE` removed from registry +
      interpreter; scenes.json usages replaced (5 CALC + roulette usages).
- [ ] `kind: "crafting"` removed everywhere; crafting scene becomes plain
      `menu` kind (or kindless). Editor kind dropdown already excludes it.
- [ ] Crafting-specific validator block replaced by generic checks (formulas
      in `config` compile; SCRIPT counted).
- [x] Golden-UI input scripts move from `main.lua sceneScripts` into scene data
      (`scene.goldenScript`) — DONE 09.07.2026 alongside collapsing the `shop`
      kind into `menu` (owner feedback: shop is not a distinct kind).
- [ ] `engine/scenes/crafting.lua` deleted (or reduced to nothing).
- [ ] UI-golden reference for the crafting scene regenerated with line-by-line
      justification (events will change shape); all other scene references
      byte-identical.

**Gates:** G1, G2, G3, UI-golden.

**Sequencing:** before D8 Phase 4 (battle hooks) — battle's windows should be
the second consumer of the generic renderer, not the first.
