# C9 — Scenes with IDs + Item Creation scene (flagship) — REV 2

- Branch: `o3/c9-scenes-item-creation`
- Runtime needs: G1 + G2 + G3; play-test debt for feel
- Depends on: **C10 (meta system) merged**; A4b merged
- Read first: SPEC.md Ground rules, S1, S4, S5, S9 (this task deliberately
  extends S9's non-goal — owner-approved); FEEDBACK.md round 2
- REV 2 supersedes the fixed-recipes v1 of this brief: the owner specified
  a Star Ocean 2-style DYNAMIC system — no static recipes; outcomes are
  computed from ingredient meta parameters and the crafter's stats.

## Goal

Item Creation becomes a first-class SCENE reachable from the game menu.
Scenes are data with numeric IDs, creatable in the editor, edited under
Engine → Flows. The crafting scene has its own interface: pick ingredients
→ yield evaluation → roulette animation over the outcome pool → result.

## Design (owner's spec, condensed)

- **No fixed recipes.** Combining 2 ingredients computes a Yield Score:
  `Y = floor((I1 + I2) / 2) + floor(alpha * S)` where I1/I2 come from the
  ingredients' `meta` (C10) and S is the governing stat of the crafting
  discipline. All formulas live in scene config as S5 formula strings —
  alpha, discipline→stat mapping, element-conflict penalty, and the ~5%
  "anomaly" critical (Y × 1.5) are DATA, not Lua constants.
- **Disciplines** (config, not code): blacksmithing→atk/def,
  tinkering→asp, alchemy→mat/mdf, cooking→maxHp. Each maps a `craftKind`
  meta tag to the stat used for S.
- **Pool generation:** Y maps to a bracket table (config) selecting 3-5
  candidate item ids by tier meta — junk / standard / rare; stat-deficit
  and element-conflict push into junk/fail brackets.
- **Roulette:** presentation-only. Cycle icons/names from the pool with
  increasing delay, settle on a random index. Timing values in the scene
  config (BIBLE.md: no hardcoded UI values).

## Do

1. `data/scenes.json` — add to BOTH server manifests (`engine/server.lua`
   + `tools/editor/server.js` DATA_FILES). Shape:
   `{ id (numeric), name, kind: "crafting", config }` — config carries
   disciplines, alpha, yield/penalty/anomaly formulas, bracket table,
   roulette timing, and term keys for its texts.
2. Engine: generic scene host keyed by `kind` (`engine/scenes/crafting.lua`
   v1). Ingredient consumption and item grants route through the EXISTING
   command handlers (build a command list, run via runImmediate) so events,
   validator semantics, and determinism hold. Yield math through
   engine/formula with ingredient meta views (C10). Menu gains a
   data-driven entry (label via terms) opening a scene by ID.
3. Editor: Engine → Flows gains a Scenes section — list, create (auto
   numeric ID), edit config with typed widgets: formula fields with the ⓘ
   help, item pickers for bracket tables, number fields for timing.
4. Validator: every scene's formulas compile against a mock context;
   bracket item ids resolve; discipline stats are real param ids; unknown
   `kind` = error.
5. The Workbench common event (A8) stays — it is the command-block demo;
   this scene is the systemic version.

## Don't

- No SCRIPT in shipped scene configs. No golden regeneration. Interpreter
  never switches scenes itself (scene_change events; host switches).
- If the roulette/UI needs a capability the command set or formula context
  lacks, report the gap in the PR instead of hardcoding gameplay in Lua.

## Acceptance

- [ ] Item Creation opens from the menu; combining ingredients with meta
      tags yields pool → roulette → result, entirely from scenes.json
      config (alpha/brackets/penalties editable in the editor, take effect
      in-game)
- [ ] Element conflict and stat deficit produce junk/fail; anomaly path
      reachable (seeded demonstration in the PR is fine)
- [ ] New scene creatable in the editor with a fresh numeric ID
- [ ] scenes.json in both manifests; G1 + G2 + G3 green
- [ ] PR checklist filled in
