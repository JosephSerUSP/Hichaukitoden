# A3 — Golden-master harness

- Branch: `o3/a3-golden-harness`
- Runtime needs: G1 (LOVE runtime)
- Depends on: nothing (parallel with A1/A2)
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S7

## Goal

Implement the golden-master battle log per SPEC S7, the regression net for all
later conversion tasks.

## Do

- Add a `golden` argument to the existing `validate` CLI mode in `main.lua`
  (`love . validate golden`): fixed seed `math.randomseed(12345)`, explicitly
  constructed party and enemies (no `engine/newgame.lua` randomness), scripted
  3-round battle (round 1 all attack; round 2 spell+defend+attacks; round 3
  flee) plus one victory resolution against a 1-HP enemy.
- Print a normalized log — one line per event, `type|actor|target|value|state`
  (empty fields allowed) — between `GOLDEN BEGIN` and `GOLDEN END` markers.
- Create `tools/golden/capture.ps1`, `tools/golden/capture.sh`,
  `tools/golden/check.ps1`, `tools/golden/check.sh` (capture writes
  `tools/golden/battle.log`; check diffs against it, exit nonzero on mismatch).
- Commit the initial `tools/golden/battle.log`.

## Don't

- Do not touch battle logic itself; this task only observes it.

## Acceptance

- [ ] G1 green
- [ ] Check script passes twice consecutively
- [ ] Temporarily editing a damage formula in `data/skills.json` turns the
      check red; reverted afterward
- [ ] PR checklist filled in
