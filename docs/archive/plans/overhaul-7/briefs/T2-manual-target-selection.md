# T2: Manual Target Selection Everywhere

**Context:** Read SPEC.md S5, S6. Every player action with a
`mode:"choose"` spec goes through the o6 reticle picker, driven by the
T1 resolver's constraints. **Depends on T1.**

**Role:** owner-supervised, never autonomous (touches
`engine/scenes/battle.lua`).

## Acceptance Criteria
- [ ] Skills, items, and basic attack all route through one picker code
      path when their spec is `mode:"choose"`; no action type keeps a
      bespoke selection flow.
- [ ] Picker candidate set comes from `targeting.resolve`'s legal-set
      logic (side/state filters) — no duplicated filtering in the scene
      layer.
- [ ] `count:"all"` actions show the reticle over the whole group; select
      confirms, cancel backs out.
- [ ] Dead-target specs highlight dead battlers in the picker (filter path
      built now, content later).
- [ ] o6 action-undo works through all new picker states (undo from
      target-selection returns to the command menu with prior choices
      intact).
- [ ] Player selection consumes no battle RNG — G2 byte-identical.

**Gates:** G1, G2 byte-identical, G3 battle-scene UI-golden trace
regenerated (sanctioned, owner reads the diff).
