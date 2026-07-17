# PLAYBOOK — Overhaul 7 (human-only)

Agents never need this file. Same protocols as o5/o6 PLAYBOOKs
(verification debt, golden discipline, escalation, review gates) — not
repeated; only what's different.

## Shape of the round

Three pillars that barely touch each other — this round parallelizes
better than o6 did:

- **A-series (animation system)** is presentation-layer; only A2 grazes
  `engine/battle.lua` (and possibly not even that — see SPEC S3's
  logger-serialization check).
- **T-series (targeting)** is the battle-loop surgery. T1 owns this
  round's ONE sanctioned `battle.log` regeneration.
- **S-series (windows in data)** touches `scenes.json` +
  `window_renderer.lua` + editor; regenerates UI-golden traces scene by
  scene, sanctioned each time.

**Owner-supervised (never autonomous): T1, T2, A2** — anything touching
`engine/battle.lua` or `engine/scenes/battle.lua`, same rule as o6.

## START HERE

**Step 0** — branch `fable-7-overhaul-7` already cut from main
(15.07.2026) with these plan files.

**Step 1 — T1 first.** It's the only battle.log-breaking brief; landing
it first means everything else in the round runs under stable
byte-identity discipline. Owner reads the new log diff before commit.

**Step 2 — three parallel tracks once T1 is stable:**
- **T2** (manual targeting UX) — owner-supervised, straight after T1.
- **A1** (animation runtime + system entries) — independent of T-series;
  can even start during T1 since it must not touch battle.lua at all.
- **S1w** (window schema + pilot scene) — independent of both.

**Step 3 —** A2 (assignable animations, needs A1; owner-supervised if it
turns out to need battle.lua), then A3 (editor tab, needs A1's schema
frozen; A2 not strictly required but the skills-editor picker lands with
A3, so prefer A2 first). S2w (remaining scenes) fans out after S1w's
schema survives its pilot — one commit per scene, one trace regen per
scene.

**Step 4 — round close:** G1/G2/G3 full pass, `animations.lua` confirmed
deleted, no orphaned Lua drawing paths (grep for the deleted function
names), SPEC S9 "not to do" list audited.

## Owner decision points (stop and ask, don't guess)

1. **T1 log diff sign-off** — the one regeneration.
2. **A3 preview channel** — engine-bridge preview vs. JS
   re-implementation; agent documents options, owner picks.
3. **S1w pilot choice** — items vs. status if items proves entangled.
4. **Each UI-golden trace regen** in S-series — owner reads each diff.
5. **Any animation-timing normalization** A1 surfaces (places where the
   same visual effect had inconsistent constants in different code paths).
