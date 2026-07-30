# userPerform — tasks for José to run locally

This folder holds scripts and directives for steps I can't run myself (no
LÖVE runtime or browser in my sandbox). When I finish a change that needs
local verification or a local action, I'll drop the script + instructions
here and tell you which to run.

Double-click a `.bat`, or run it from a terminal in this folder.

---

## The gates (numbering per `docs/SPEC.md` Sec.3)

Run whichever gates a change could affect. Re-run after each merge.

| Script | Gate | Pass condition |
|---|---|---|
| `G1-validate.bat` | Data/formula validator | Output ends with `VALIDATE OK` |
| `G2-golden.bat` | Battle golden-master | Prints `Golden log matches.` |
| `G3-golden-ui.bat` | Per-scene UI traces | Every scene prints `Golden UI log matches` |
| `G4-engine-state.bat` | Docs match the engine | Prints `Engine state doc matches.` |
| `G5-golden-screens.bat` | Rendered frame byte-identity | Prints `SCREENS OK` (122/122 match) |
| `editor-check.bat` | Editor console (not numbered) | Editor loads, **zero** console errors, Save round-trips |

Not a gate, but it lives here because it needs a browser and a paid API key:

| Script | What | Notes |
|---|---|---|
| `runAssetGen.bat` | Art generation UI (`tools/asset-gen`) | Needs Python + `Pillow`/`requests` and `OPENAI_API_KEY`. Writes into `assets/` only when you press Promote. |

Notes:
- **G1:** the line `[formula] error in 'os.time()'` is an expected sandbox
  negative-test, not a failure.
- **G2/G3:** never regenerate a golden log just to clear a red diff. A red
  golden gate is a behavioral regression. Regenerating is a deliberate,
  reviewed action for intentional changes only.
- **G4 is different:** a red G4 means `docs/ENGINE-STATE.md` is *stale*, not
  that the engine is wrong. Fix it by regenerating:
  `powershell -File tools\golden\capture-state.ps1`, then commit the file.
- **G5 is the only gate that sees the 3D world view.** G1 validates data, G2
  diffs battle logs, G3 diffs UI *events* — a renderer change can pass all of
  them and still be visibly broken. Frames that differ are written to
  `tools/golden/screens-actual/` (gitignored); open them next to
  `tools/golden/screens/` before touching anything. Same rule as G2/G3: never
  recapture to clear a red diff. It compares *pixels*, so a GPU/driver change
  can legitimately shift it — that is a judgement call for you, not a silent
  `capture-screens.ps1` run. Needs Python (already required by
  `tools/asset-gen`).
- **editor-check:** needs Node; close the window (Ctrl+C) to stop the server.
  The editor writes straight to `data/*.json` — run `git diff data/` after.
  (This script used to be called `G3-editor.bat`, which collided with SPEC's
  G3 = golden UI; renamed 24.07.2026.)

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
**Run:** `editor-check.bat` — open a flow/scene with plain commands AND
CHOICE/IF blocks, hover each, confirm identical navy+white highlight, that
selection (navy) and striping still read correctly, and zero console errors.

> ⚠ Environment note: the write path to this folder intermittently appends
> NUL padding to files (this is what corrupted main.lua / scene_host.lua /
> events.js). After any edit, worth a quick check:
> `git ls-files | while read f; do grep -qP '\x00' "$f" && echo "NULs: $f"; done`

### 2026-07-13 — Party-grid layout consolidation (needs G2 + G3)
Added one shared helper `actor_status.gridSlot(originX, originY, index,
session, cols)` and routed all four party-grid cell-position sites through
it: `renderer.drawPartyGrid`, `renderer.getBattlerCoords` (damage-popup
coords), and both `window_renderer` sites (`drawPartyGridStyle` and the
`cellOf:` anchor in `resolveAnchor`). Removes three copies of the `% cols` /
`floor(/cols)` arithmetic. **Behavior-preserving** — every site already
resolved to `actor_status.cellSize()` (= partyGridColWidth/RowHeight), so the
numbers are unchanged.
**Run:** `G2-golden.bat` — must still print `Golden log matches.` (byte-
identical; do NOT regenerate the log). Then `editor-check.bat` for a visual
sanity check of the party HUD / battle console / target grid.
