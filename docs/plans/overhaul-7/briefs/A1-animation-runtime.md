# A1: Animation Runtime + System Animations Become Data

**Context:** Read SPEC.md S0, S1, S2 and
`docs/plans/overhaul-5/future-animation-system.md` (owner direction —
design source of truth). Creates `data/animations.json` + a presentation
animation player; dissolves hardcoded renderer animation constants into it.

**Role:** local agent. Must NOT touch `engine/battle.lua` or
`engine/scenes/battle.lua` — this brief is presentation + data only.

## Acceptance Criteria
- [ ] `data/animations.json` per SPEC S2 schema: `class` system/assignable,
      entries composed of typed TRACKS (`tint`, `blend`, `transform` with
      independent x/y scale, `shake`, `particles`, `text_flow`), each with
      t0/duration/easing. Unknown track types fail soft (one log line,
      skip track). Readers ignore unrecognized optional fields.
- [ ] Particles track built on LÖVE `ParticleSystem` (texture ref or
      colored-quad fallback; rate, lifetime, spread/velocity, gravity,
      color-over-life, blend mode). `mask: "target"` clips particles to
      the target sprite's silhouette via stencil test against sprite
      alpha; absent → unclipped. At least one demo assignable entry
      exercises particles + masking together.
- [ ] Transform track supports per-axis scaling about the sprite anchor;
      SPRITE scaling only — the o5 rule stands: never graphics-scale a
      windowskin.
- [ ] The ported `system.death` entry is expressed as tracks
      (blend add + tint purple/fade + transform y-offset), reproducing
      today's `renderer.lua` ~L690 composite. If any ported entry can't
      be expressed in tracks, fix the schema, don't special-case.
- [ ] All reserved system ids present and validated by G1:
      `system.damage_flash`, `system.damage_shake`, `system.death`,
      `system.small_damage`, `system.enemy_slide_in`, `system.heal`.
- [ ] Animation player module owns all battler animation timing; the
      inline timers/constants in `presentation/renderer.lua` (flash,
      death tint/fade, enemy slide-in) and the values in
      `config.battle_screen.animations` (read by `small_battlers.lua:31`)
      migrate into animations.json entries. Old constants deleted, not
      shadowed.
- [ ] `data/animations.lua`'s 4 entries ported; file deleted;
      `data/loader.lua:38` loads the JSON. Grep for every consumer of
      `loader.animations` before deleting.
- [ ] Inconsistent duplicate constants discovered during migration are
      reported to the owner, not silently normalized.
- [ ] Check the existing `PLAY_ANIM` interpreter command: it must keep
      working (or be pointed at the new player) — no new interpreter
      commands added.

**Gates:** G1 (validator gains the system-key check), G2 byte-identical
(presentation only), G3 visual check on battle + any scene using
PLAY_ANIM.
