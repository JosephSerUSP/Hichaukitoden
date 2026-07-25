# PLAYBOOK — Overhaul 3 (human-only)

Agents never need this file. It covers: where to start, which environment gets
which task, and the protocols that keep quality constant while you hop between
Claude Code, Antigravity, and Jules.

## START HERE

**Step 0 — integration branch.** Already done: `fable-5-overhaul-3` exists on
origin with these plan files on it. Task branches are cut from it; PRs merge
back into it.

**Step 1 — fire the first three tasks (all independent, today):**

Universal prompt shape (works verbatim in Claude Code, Antigravity, and Jules —
only the task file name changes):

> In the repo JosephSerUSP/Hichaukitoden, check out branch `fable-5-overhaul-3`.
> Read `docs/plans/overhaul-3/briefs/<FILE>` and execute exactly that task,
> including its acceptance checklist and PR checklist. Read only the SPEC.md
> sections the brief lists. Do not read other plan files.

- → **Jules**: `A1-recon.md` (text-only; perfect async cloud task)
- → **local agent (Claude Code or Antigravity)**: `A3-golden-harness.md`
- → **Antigravity** (or whichever local has budget): `B0-editor-split.md`
  ⚠ nothing else may touch `tools/editor/index.html` until B0 merges

**Step 2 — merge A1/A3/B0**, then fire `A2-formula-engine.md` (local, G1
needed).

**Step 3 — merge A2**, then fire `A4-interpreter.md` (your strongest available
agent; this is the core). **Review A4 yourself before merging** — see gates
below.

**Step 4 — after A4 merges**, everything parallelizes:

- Conversions: A5a, A5c, A5e (Jules-able: golden-checkable), A5b and A5d
  (local — the ordering-sensitive ones). Merge one at a time, easiest first:
  A5a → A5c → A5e → A5b → A5d, re-running the golden check after each merge.
- Editor: B1, B2, B3, B4 in parallel (post-B0 they touch different modules).

**Step 5 —** A6 (palette, local w/ browser), A7 (Jules), then A8 (the crafting
proof), then B5. Final: one real play session by you — town → dungeon →
battle → victory → flee → craft.

## Environment routing

| Environment | Can run | Route here | Avoid |
|---|---|---|---|
| **Claude Code** (local, Windows) | everything (G1/G2/G3) | A2, A4, A5b, A5d, reviews, integration merges | burning limits on recon/bulk JSON |
| **Antigravity** (local IDE) | everything | B0–B5, A6, re-running gates on Jules PRs | deep engine refactors if diffs get sloppy — judge per result |
| **Jules** (cloud Linux, async, no browser) | G1 via `apt-get install love` (+`xvfb-run` if needed); node; no G3 | A1, A5a, A5c, A5e, A7, B4's server endpoint | anything whose primary gate is G3; concurrent index.html edits |
| **API-key sub-LLMs** (Gemma 24B, Flash Lite) | text-in/text-out | bulk generation *inside* another agent's loop (flows.json drafts from the A1 inventory, formulaHelp/scriptingHelp tables, label copy) | autonomous repo writes; sole review of engine changes |

Vendor-strength rules of thumb (weaker than brief quality + gates, but real):
Gemini-family agents for long-context sweeps and screenshot-matching UI work;
Claude agents for careful multi-step refactors; Jules for well-specified
low-supervision chores. When limits force a swap, swap — the gates hold the
quality floor, not the vendor.

## Protocols

- **Verification debt:** any gate an environment can't run is declared
  unchecked in the PR checklist with a reason. Debt is cleared before merge by
  a 5-minute local session (pull branch, run gates, comment results). Debt
  never merges silently.
- **Golden log discipline:** `tools/golden/battle.log` is regenerated only
  deliberately and reviewed when it happens — never to make a red diff green.
- **Escalation:** a task that bounces twice with a red gate moves up one tier
  (bigger model or local environment) with the failure logs pasted into the
  prompt. Don't iterate a third time in place.
- **Serialization:** index.html is single-writer until B0 merges. A5 tasks can
  be *worked* in parallel but *merge* serially with a golden re-check between.
- **Review gates you run personally:**
  1. After A4: read the sandbox env construction in `engine/formula.lua` /
     the SCRIPT env in `engine/interpreter.lua` line-by-line — nothing from
     `_G` may leak in. Run `/code-review` (or the heavyweight review tier) on
     the A2+A4 core if budget allows.
  2. After the A5 batch: `/code-review` the accumulated diff.
  3. End of round: the play-test. The golden log covers logic, not feel.
- **Do not delegate:** changes to SPEC.md; the A4 merge decision; the final
  play-test.

## Merge-order summary

```
A1, A3, B0  →  A2  →  A4(review)  →  A5a → A5c → A5e → A5b → A5d
                                   →  B1..B4 (parallel)
→  A6, A7  →  A8 (proof)  →  B5  →  /code-review  →  play-test  →  done
```
