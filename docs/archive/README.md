# Archive — frozen history, never authoritative

**Nothing in this directory describes how the engine works today.** These are
point-in-time planning records: what someone intended to build during a given
round, written before or during the work. Many statements in here were true when
written and are false now.

If you are an agent (or a human) trying to understand current behavior:

| Question | Read |
|---|---|
| What exists right now? | [`../ENGINE-STATE.md`](../ENGINE-STATE.md) — generated, G4-gated |
| How does it work, and why? | [`../SPEC.md`](../SPEC.md) — the living spec |
| What are we trying to build? | `../design/`, `../game design/` — intent, not status |
| How do rounds/branches/gates work? | [`../ORCHESTRATION.md`](../ORCHESTRATION.md) |

Contents:

- `plans/` — the overhaul rounds (`overhaul-3` … `overhaul-7`) plus assorted
  round plans. Surviving rules from these were merged into `SPEC.md`; cite
  `SPEC.md`, not these.
- `root-plans/` — three plan documents that used to sit in a second `plans/`
  directory at the repo root, which nothing referenced and which duplicated the
  purpose of `plans/`.

Kept because the rationale is occasionally worth reading — *why* a design went
one way is hard to recover from git history alone. Moved out of `docs/` proper
on 24.07.2026 because greps for engine behavior kept landing here first and
producing stale answers (four separate documents asserted implementation facts
that had become false, costing a full wasted planning pass).
