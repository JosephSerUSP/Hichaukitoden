# C5 — Squash preserved legacy bugs (duplicated MP drain) — LOCAL ONLY

- Branch: `o3/c5-mp-drain-bug`
- Runtime needs: G1 + G2 **with a deliberate, reviewed golden regeneration**
- Depends on: A5 conversions merged (they preserved these bugs on purpose)
- Read first: `docs/plans/overhaul-3/SPEC.md` — Ground rules, S4, S7;
  `docs/plans/overhaul-3/PLAYBOOK.md` — Golden log discipline
- **Routing: local agent with the owner reviewing. Never Jules — this task
  regenerates `tools/golden/battle.log`, which the playbook forbids doing
  out of sight.**

## Goal

The A5 conversions mirrored legacy behavior bug-for-bug so the golden diff
proved equivalence. The owner has signed off on fixing the known bugs now
(feedback game item 1 in `docs/plans/overhaul-3/FEEDBACK.md`), which means
a deliberate golden log update.

## Do

1. Reproduce and document the duplicated MP drain: the golden log shows
   `mp_drain` rows emitted after `victory` and around `flee_success`
   (end-of-round ticks run even when the battle already ended). Trace the
   `battle.round_end` flow phase vs. the host loop in `engine/battle.lua`.
2. Fix by gating: the round_end phase must not run (or must skip drains)
   once the battle outcome is decided. Prefer fixing the HOST (don't run
   the phase after victory/flee) over adding IF guards to the flow data —
   the data mirrors designer intent; the double-run is host scheduling.
3. Audit the log for other preserved oddities and list them in the PR
   (fix only what the owner confirms; the MP drain is pre-approved).
4. Regenerate `tools/golden/battle.log` via `tools/golden/capture.*`, and
   put the before/after diff of the log IN the PR description with a
   line-by-line justification (each removed line must map to the bug).

## Don't

- No other behavior changes in the same PR — the golden diff must contain
  ONLY the approved fixes.

## Acceptance

- [ ] Duplicated MP drain gone in a play session (owner confirms)
- [ ] Golden regenerated deliberately; PR shows the exact log diff with
      justification; G1 + G2 green against the NEW log
- [ ] PR checklist filled in
