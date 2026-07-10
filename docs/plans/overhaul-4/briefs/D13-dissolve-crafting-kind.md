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

- [x] Generic window rendering: the D2 vocabulary (OPEN_WINDOW/SET_LIST/
      SET_TEXT/SET_CURSOR/FOCUS_WINDOW + `engine.json → windowLayout`) actually
      draws windows, lists, text, and portraits — no crafting-specific draw
      code. — DONE 09.07.2026 (D13.1/D13.2, `presentation/window_renderer.lua`).
- [x] Inventory/list state lives in scene `v`/list sources resolved by the
      renderer, not in a module-local — DONE 10.07.2026: the module-local
      `inventoryItems` died with `engine/scenes/crafting.lua`; the SCRIPT
      rebuilds the same ordering via `api.items()`, matching the renderer's
      stable priority sort.
- [x] Yield/pool computation moves into `SCRIPT` — DONE 10.07.2026, with the
      generic sandbox additions: `ctx.config` (scene config, any scene),
      `api.eval`, `api.items`, `api.allItems`, `api.party`, plus a generic
      `SCRIPT ref` param resolving scene-local named scripts
      (`scenes.json → scene.scripts`) so five call sites share one body.
      Nothing crafting-named in the API.
- [x] `CALC_CRAFT_YIELD` and `START_ROULETTE` removed from registry +
      interpreter; the 5 scenes.json usages replaced with
      `SCRIPT ref=calcYield` — DONE 10.07.2026. (START_ROULETTE had a handler
      but no registry entry and no data usages; handler deleted.)
- [x] `kind: "crafting"` removed everywhere; crafting scene is plain `menu` —
      DONE 10.07.2026. Editor "+ Create Scene" now also creates a plain menu
      scene (and its numeric-id computation no longer NaNs on string ids).
- [x] Crafting-specific validator block replaced by generic checks — DONE
      10.07.2026: any `config.*Formula` string must compile; `scene.scripts`
      entries must be valid Lua; SCRIPT refs must resolve; SCRIPT counted.
- [x] Golden-UI input scripts move from `main.lua sceneScripts` into scene data
      (`scene.goldenScript`) — DONE 09.07.2026 alongside collapsing the `shop`
      kind into `menu` (owner feedback: shop is not a distinct kind).
- [x] `engine/scenes/crafting.lua` deleted — DONE 10.07.2026.
- [x] UI-golden: NO regeneration was needed — the SCRIPT port is behaviorally
      exact (same v-values, same RNG consumption, and neither the old
      CALC_CRAFT_YIELD nor SCRIPT emits logged events), so `scene_1.log` and
      all other scene references stayed byte-identical. Verified via
      `check-ui` on 10.07.2026.

**Gates:** G1, G2, G3, UI-golden.

**Sequencing:** before D8 Phase 4 (battle hooks) — battle's windows should be
the second consumer of the generic renderer, not the first.
