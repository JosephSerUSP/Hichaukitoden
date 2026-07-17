# Battle Windows Conversion — Brief (gated on engine prerequisites)

**Context:** `docs/design/summoner-rework.md` (design, decided
17.07.2026) and `docs/SPEC.md` §1.2. Converts the last legacy-drawn
scene — battle — to `"draw": "windows"` in `data/scenes.json`, then
deletes the legacy renderer path. Split into two stages because stage 1
touches `engine/battle.lua`, which is **owner-supervised, never
autonomous** (SPEC §5).

## Stage 1 — Engine prerequisites (owner-supervised)

- [ ] **Swap action**: a battle action `{type = "swap", slot, reserveIdx}`
      resolved in `resolveRound` — swaps a fielded spirit with a reserve
      spirit at an MP cost (config key, e.g. `summoner.swapCostBase`,
      formula-capable; no hardcoded values). Swapped-out spirits keep
      HP/states. Reserve list has NO hardcoded size limit.
- [ ] **Row flag**: each fielded spirit carries `row = "front"|"back"`,
      persisted in the session, readable as a formula token
      (`a.row`, target-spec filters may reference it later). No combat
      math changes this round — state + access only, per owner decision.
- [ ] **Console verbs**: player input produces only Spell / Swap /
      round-control actions (no per-spirit command loop). Spirits act via
      the existing AI path.
- [ ] Golden impact: battle.log WILL change (action-set change is
      mechanical, not presentational) — regeneration is sanctioned for
      this stage only, owner reads the diff. Validator gains checks:
      swap-cost formula compiles, row values are front/back.

## Stage 2 — Windows conversion (presentation only)

- [ ] Author the §5 window inventory (summoner-rework.md) in
      `data/scenes.json` battle: `enemy_row`, `party_grid` (+row badge),
      `summoner_panel` (MP gauge first-class), `command_console`,
      `spell_menu` (MP costs, unaffordable disabled), `swap_menu`
      (scrolling reserve list), `target_overlay`, `battle_log`.
- [ ] All geometry from `engine.json battleLayout` / shared helpers —
      no per-scene coordinate math (SPEC §2.1). Gauges interpolate;
      panels use gradient blends; damage popups stay in the animation
      system, not windows.
- [ ] The legacy battle drawing in `presentation/renderer.lua` /
      `battle_layout.lua` and the legacy branch in `main.lua` are
      DELETED, not left as dead paths. `window_renderer.lua`'s SPEC S2
      fallback rule becomes obsolete — remove the flag plumbing.
- [ ] battle.log byte-identical to stage 1's baseline (this stage is
      presentation only — if it moves, that's a layering violation:
      stop and report). Battle UI-golden trace regenerated (sanctioned,
      owner-reviewed); all other scenes byte-identical.

**Gates:** G1; G2 (stage-1 sanctioned regen, then strict); G3 (battle
regen sanctioned, others strict).
