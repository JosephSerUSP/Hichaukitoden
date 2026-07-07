# C9 — Scenes with IDs + menu-accessible Item Creation (flagship)

- Branch: `o3/c9-scenes-item-creation`  |  Runtime needs: G1 + G2 + G3;
  play-test debt for feel
- Depends on: A4b merged (registry commands run everywhere)
- Read first: SPEC.md Ground rules, S1, S4, S9 (this task deliberately
  extends S9's non-goal — owner-approved); FEEDBACK.md round 2, game item 2

## Goal
Item Creation becomes a first-class SCENE reachable from the game menu,
with its own Star Ocean-style interface (recipe list + ingredient/result
panel + success feedback), and scenes become data: numeric IDs, creatable
in the editor, flows edited under Engine → Flows.

## Do
1. `data/scenes.json` (add to BOTH server manifests): array of
   { id (numeric), name, kind: "crafting" (v1's only kind), config }.
   The crafting kind's config: recipes [{ ingredients: [{item,count}],
   result, chanceFormula }], terms for its texts.
2. Engine: a generic scene host (`engine/scenes/crafting.lua` or similar)
   driven by that config — selection UI reads recipes, consumption/roll/
   grant route through the SAME command handlers (runImmediate with a
   generated command list, so validator/golden semantics hold). Menu gains
   an entry (data-driven label via terms) opening scene by ID.
3. Editor: Engine → Flows gains a Scenes section — list scenes, create new
   (auto numeric ID), edit kind/config with pickers (itemSelect, formula
   with ⓘ). The Workbench common event stays as the data-block demo.
4. Keep the interpreter's rule: scenes change via scene_change events;
   the host switches, never the interpreter.

## Don't
- No SCRIPT in shipped scene configs; no golden regeneration; if the
  crafting UI needs a capability the command set lacks, report it in the
  PR rather than hardcoding gameplay in the scene host.

## Acceptance
- [ ] Item Creation opens from the menu, crafts with success/failure using
      recipes defined ENTIRELY in scenes.json
- [ ] New scene creatable in the editor with a fresh numeric ID
- [ ] scenes.json in both manifests; G1 + G2 + G3 green
- [ ] PR checklist filled in
