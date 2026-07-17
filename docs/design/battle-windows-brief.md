# Battle Windows Conversion — Brief (rev. 2, matches design rev. 2)

**Context:** `docs/design/summoner-rework.md` (decided 17.07.2026,
rev. 2) and `docs/SPEC.md` §1.2. Converts the last legacy-drawn scene —
battle — to `"draw": "windows"`, then deletes the legacy renderer path.
Stage 1 touches `engine/battle.lua` and is **owner-supervised** (SPEC §5).

## Stage 1 — Engine prerequisites (owner-supervised) — DONE 17.07.2026

Landed with battle.log byte-identical (no sanctioned regen needed: the
golden fixture's summoner-spell cast became the same skill cast by its
owner). Validator gained wave/permadeath/row simulation coverage.

- [x] **Remove summoner spells**: the spell action type and the
      `system.summoner.spells` slot-1 path leave `resolveRound`; the
      config key and its validator check retire. (Skills the list pointed
      at remain valid data — only the battle-casting mechanic goes.)
- [x] **Emergency wave**: when every fielded spirit is down at a round
      boundary and the reserve is non-empty, the reserve wave (up to 4)
      deploys automatically at no MP cost; the party forfeits that round
      (enemies still act). Emits a `wave` event for the UI/log.
- [x] **Permadeath + auto-bank**: at battle end (victory or flee), every
      spirit still down is removed permanently and its EXP value banks at
      `summoner.sacrificeExpRate`; emits events the victory flow surfaces.
      No hardcoded values — rates/formulas from config.
- [x] **Game over** condition becomes: fielded party wiped AND reserve
      empty. (Previously: party wiped.)
- [x] **Row flag**: each fielded spirit carries `row = "front"|"back"`,
      persisted in the session, readable as a formula token. No combat
      math consumes it this round — state + access only.
- [x] Golden impact: battle.log WILL change (spell path removed, wipe
      semantics changed) — regeneration is sanctioned for this stage
      only, owner reads the diff before it lands. Validator updates:
      row values check, retired spell check removed.

## Stage 2 — Windows conversion (presentation only)

- [ ] **Shared cost/gain gauge preview** (windows schema feature, not a
      window): a gauge content block accepts a preview binding that tints
      the affected span red (often a single pixel) and optionally appends
      slim `cost: xxxx` / `gain: xxxx` text after the gauge. Built once,
      consumed by ritual (summon/promote/sacrifice), shops, item use —
      any scene with a gauged resource.
- [ ] Author the §5 window inventory (summoner-rework.md) in
      `data/scenes.json` battle: `enemy_row`, `party_grid` (row badge +
      slim MP gauge), `command_console` (per-spirit, no spell verb),
      `target_overlay`, `wave_notice`, `battle_log`.
- [ ] All geometry from `engine.json battleLayout` / shared helpers — no
      per-scene coordinate math (SPEC §2.1). Gauges interpolate; panels
      use gradient blends; damage popups stay in the animation system.
- [ ] The legacy battle drawing in `presentation/renderer.lua` /
      `battle_layout.lua` and the legacy branch in `main.lua` are
      DELETED, not left as dead paths. `window_renderer.lua`'s SPEC S2
      fallback flag plumbing is removed.
- [ ] battle.log byte-identical to stage 1's baseline (presentation only
      — if it moves, that's a layering violation: stop and report).
      Battle UI-golden trace regenerated (sanctioned, owner-reviewed);
      all other scenes byte-identical.

**Gates:** G1; G2 (stage-1 sanctioned regen, then strict); G3 (battle
regen sanctioned, others strict).
