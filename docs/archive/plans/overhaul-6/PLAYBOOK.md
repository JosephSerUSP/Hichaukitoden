# PLAYBOOK — Overhaul 6 (human-only)

Agents never need this file. Same protocols as overhaul-5's PLAYBOOK
(verification debt, golden discipline, escalation, review gates) — not
repeated here; only what's different.

## Why this round is different from o4/o5

Overhaul 4 and 5 mostly added data-driven capability without breaking
existing recorded behavior. This round **deliberately breaks
`tools/golden/battle.log`** — the Summoner stops fighting, so the golden
battle sequence that has the summoner acting and dying no longer describes
a real scenario. F1 is a sanctioned, one-time, owner-approved regeneration.
Everything after F1 goes back to strict byte-identity discipline against
the *new* log.

**Every brief that touches `engine/battle.lua` or
`engine/scenes/battle.lua` (F1, F2, F7) is owner-supervised** — pair or
review step-by-step, not end-of-brief only. This is the same rule
ORCHESTRATION.md already applies to overhaul-4's D8/D11, extended to cover
this round's battle-loop rewrite.

## START HERE

**Step 0 — cut `fable-6-overhaul-6`** from `main` (already has o5 merged in,
per the merge on 2026-07-14) with these plan files on it.

**Step 1 — F1 (summoner exits the battle loop).** Owner-supervised, no
exceptions. This is the round's foundational rewrite; nothing else in the
round can start until it's stable. Regenerate `battle.log` with explicit
owner sign-off on the new recorded sequence — read the diff of the new log
together before committing it, don't just eyeball "did it print."

**Step 2 — F2 (MP audit)**, immediately after F1, same file area, same
owner-supervision level. Confirm `battle.log` from F1 stays byte-identical
through this step — if it doesn't, that's a signal F2 changed behavior
instead of auditing it.

**Step 3 — parallel branch, both depend only on F1+F2 being stable:**
- **F3 (reserve roster)** — data-model half can start immediately; STOP
  before the swap-UI half until the owner picks a placement (map popup vs.
  elsewhere).
- Once F3's data model exists: **F4 (Summon)** and **F5 (Sacrifice)** can
  run in parallel with each other (independent mechanics, share only
  roster data). F5 needs a quick check against Item Creation's discipline
  field state before landing its item-reward gating — coordinate, don't
  fork a duplicate species-flavor table.

**Step 4 — F6 (Promotion)**, after F5 (may consume sacrifice-dropped
promotion-key items). Needs an owner check on ritual-UI placement before
building it.

**Step 5 — F7 (Item joins creature commands)**, last. **Do not start this
brief without first getting the owner's explicit answer** to the
player-driven-vs-AI-driven fork it describes — this single decision changes
its scope by an order of magnitude. Owner-supervised throughout, same as
F1/F2.

**Step 6 — end of round: one real playtest by you.** Full battle from start
to finish with the new creature-only loop, a Summon, a Sacrifice, a
Promotion if a creature is at threshold, and (depending on F7's outcome) an
Item use mid-battle from a creature's own menu. The gates cover mechanical
correctness, not whether the new loop actually feels right — that's what
this step is for.

**Step 7 — `/code-review` on the accumulated diff**, then merge
`fable-6-overhaul-6` → `main`, same protocol as o5's merge.

## Merge-order summary

```
cut fable-6-overhaul-6
F1 (owner-supervised, battle.log regenerated + signed off)
  → F2 (owner-supervised, battle.log stays byte-identical)
    → F3 data-model  →  [owner picks swap-UI placement]  →  F3 UI
       → F4 (Summon)  ‖  F5 (Sacrifice, coordinate w/ Item Creation data)
         → F6 (Promotion, after F5)
           → F7 (owner picks player-driven vs AI-driven FIRST, then owner-supervised build)
             → real playtest  →  /code-review  →  merge to main
```

## Balancing — explicitly deferred

No brief tunes MP costs/rates/damage numbers beyond "plumbing produces a
plausible non-zero value" (SPEC S9). Schedule a dedicated playtesting +
balancing pass after this round merges, once the mechanics exist to tune
against real numbers.

## Also queued, not part of this round

The Animation System (o5's `future-animation-system.md`) remains the other
flagship-sized item — do not fold it into this round; it's independent
scope and this round is already the size of two normal rounds on its own.
