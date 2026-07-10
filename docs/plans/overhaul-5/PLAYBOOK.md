# PLAYBOOK — Overhaul 5 (human-only)

Agents never need this file. Same protocols as overhaul-3's PLAYBOOK
(verification debt, golden discipline, escalation, review gates) — they are
not repeated here; only what's different.

## START HERE

**Step 0 — close out overhaul 4 first.** D13 (dissolve crafting kind) must
be merged and green on `fable-5-overhaul-4`, and that branch merged to
`main`, before cutting `fable-5-overhaul-5`. E4's Crafting template and E5's
preview both build on the post-D13 state; starting overhaul 5 against
pre-D13 data guarantees rework.

**Step 1 — cut `fable-5-overhaul-5`** from main with these plan files on it.

**Step 2 — fire the independent Track B briefs:**

Universal prompt shape (unchanged from overhaul-3):

> In the repo JosephSerUSP/Hichaukitoden, check out branch
> `fable-5-overhaul-5`. Read `docs/plans/overhaul-5/briefs/<FILE>` and
> execute exactly that task, including its acceptance checklist. Read only
> the SPEC.md sections the brief lists. Do not read other plan files.

- → **Jules**: `E1-row-striping.md`, `E4-preset-scene-gallery.md` (both
  well-specified, low-supervision)
- → **Jules or local**: `E0-command-color-coding.md`
- → **local agent**: `E2-context-menu-keyboard.md` (interaction-heavy;
  needs a real browser to verify honestly)

⚠ E0/E1/E2 all touch `tools/editor/js/events.js`. Work in parallel is fine;
**merge serially** (suggested order: E1 → E0 → E2, smallest diff first),
re-running G3 after each merge.

**Step 3 — after E4 merges**, fire `E3-load-from-template.md` (local).

**Step 4 — E5** (`E5-visual-scene-editor.md`): strongest available local
agent. This is the round's core. Review it yourself before merging — same
personal-review rule as overhaul-3's A4: read the new `main.lua` preview
command and the server endpoint line-by-line (subprocess invocation +
anything that touches the filesystem from a web endpoint deserves eyes).
Run `/code-review` on the accumulated diff if budget allows.

**Step 5 — after E5 merges**, fire `E6-visual-editor-map-scenes.md` (local).
Its first step is recon; expect its PR to possibly re-scope (see the brief).

**Step 6 — end of round:** one real authoring session by you — create a
scene from the Crafting template, edit its windows on the canvas, re-order
some commands with the keyboard, save, run the game, enter the scene.
The gates cover correctness, not authoring feel — and feel is what this
round is for.

## Audio

No brief this round. Read `audio-design-options.md`, pick a path (the memo
recommends Path 4: re-produce the existing compositions as samples, played
through thin `sounds.json`-driven plumbing), answer the three questions at
the bottom, and the audio brief gets written for the next round — with the
handler and the command registration landing in the same commit, per
overhaul-4 SPEC S9.

## Merge-order summary

```
D13 merged, o4 → main, cut fable-5-overhaul-5
E1 → E0 → E2 (serial merges, shared file)   E4 (parallel)
                                  →  E3 (after E4)
→  E5 (review personally)  →  E6  →  /code-review  →  authoring-session test  →  done
```

## Environment routing deltas vs overhaul-3

Same table as overhaul-3's PLAYBOOK, with one addition: **E5 and E6 are
local-only** — they need `lovec.exe` (the preview subprocess) *and* a
browser in the same environment, which rules out Jules entirely, not just
for G3.
