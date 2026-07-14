# userPerform — tasks for José to run locally

This folder holds scripts and directives for steps I can't run myself (no
LÖVE runtime or browser in my sandbox). When I finish a change that needs
local verification or a local action, I'll drop the script + instructions
here and tell you which to run.

Double-click a `.bat`, or run it from a terminal in this folder.

---

## The three gates (from `docs/ORCHESTRATION.md`)

Run whichever gates a change could affect. Re-run after each merge.

| Script | Gate | Pass condition |
|---|---|---|
| `G1-validate.bat` | Data/formula validator | Output ends with `VALIDATE OK` |
| `G2-golden.bat` | Battle golden-master | Prints `Golden log matches.` |
| `G3-editor.bat` | Editor console | Editor loads, **zero** console errors, Save round-trips |

Notes:
- **G1:** the line `[formula] error in 'os.time()'` is an expected sandbox
  negative-test, not a failure.
- **G2:** never regenerate `tools/golden/battle.log` just to clear a red
  diff. Regenerating is a deliberate, reviewed action for intentional battle
  changes only.
- **G3:** needs Node installed; close the window (Ctrl+C) to stop the server.

Assumes LÖVE is installed at `C:\Program Files\LOVE\` (with `lovec.exe` for
the console output G1/G2 need). If your path differs, edit the `.bat`s.

---

## Pending actions

<!-- I append dated entries here as work lands. -->

### 2026-07-13 — Corruption repair (merged)
Ran G1/G2/G3 after the NUL-byte + truncation fixes to `main.lua`,
`engine/scenes/battle.lua`, `engine/scene_host.lua`. — done by José.

### 2026-07-13 — Command-row hover cohesion (needs G3)
Unified command-list hover into one shared CSS rule
(`.cmd-row[tabindex]:hover` in `tools/editor/index.html`) and removed the
per-row inline `onmouseover/onmouseout` from the plain-line path in
`tools/editor/js/events.js`. Effect: block headers (CHOICE / IF / generic)
now highlight on hover exactly like plain rows; read-only rows stay inert.
**Run:** `G3-editor.bat` — open a flow/scene with plain commands AND
CHOICE/IF blocks, hover each, confirm identical navy+white highlight, that
selection (navy) and striping still read correctly, and zero console errors.

> ⚠ Environment note: the write path to this folder intermittently appends
> NUL padding to files (this is what corrupted main.lua / scene_host.lua /
> events.js). After any edit, worth a quick check:
> `git ls-files | while read f; do grep -qP '\x00' "$f" && echo "NULs: $f"; done`
