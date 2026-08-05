# Current Gate Baseline Report

**Historical Baseline Snapshot Commit:** `ff87f85957de3065a38d1291280bd7e7303ddb0f`  
**Current Base Commit:** `fb2c70460adad8c84134a0846eb47c9ee3167f6c`  
**Verification Scope:** Corrected working tree based on `fb2c70460adad8c84134a0846eb47c9ee3167f6c`  
**Branch:** `main`  
**Environment:** Windows 10/11, PowerShell 5.1 / 7, LÖVE 11.4 (`C:\Program Files\LOVE\lovec.exe`), Node.js v20+, Chrome (headless for G6).  
**Date:** August 5, 2026

---

## Summary Gate Status Table

| Gate | Command | Status | Result / Mismatch Count | Reproducibility |
|---|---|---|---|---|
| **G1** | `& "C:\Program Files\LOVE\lovec.exe" . validate` | **PASS** | `VALIDATE OK` (0 errors, 59 SCRIPT usages) | 100% Pass |
| **G2** | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\golden\check.ps1` | **PASS** | Matches all 3 fixtures (`affinity`, `default`, `growth`) | 100% Pass |
| **G3** | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\golden\check-ui.ps1` | **PASS** | Matches all 19 scenes | 100% Pass |
| **G4** | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\golden\check-state.ps1` | **PASS** | `Engine state doc matches.` | 100% Pass |
| **G5** | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\golden\check-screens.ps1` | **FAIL** | 57/140 match (83 visual mismatches) | Stable across runs |
| **G6** | `powershell -NoProfile -ExecutionPolicy Bypass -File tools\golden\check-editor.ps1` | **FAIL** | 24/37 match (13 editor screen mismatches) | Stable across runs |
| **unit** | `& "C:\Program Files\LOVE\lovec.exe" . unittest` | **PASS** | `ALL UNIT TESTS OK` (includes `test_reachability`) | 100% Pass |
| **save** | `& "C:\Program Files\LOVE\lovec.exe" . savetest` | **PASS** | `SAVETEST OK` | 100% Pass |
| **reachability** | `& "C:\Program Files\LOVE\lovec.exe" . reachability` | **REPORT** | Always exits 0; 16 items without direct source (13 craft-only, 3 uncraftable), 14 uncraftable pool items, 9 actors unobtainable | 100% Stable |

---

## Detailed Failure Evidence

### 1. G5 Game Screenshots (`check-screens.ps1`)
* **Status:** Failed (Exit code 1).
* **Matches:** 57 / 140 frames.
* **Mismatches:** 83 frames across `battle/`, `map/`, and `menu/` (`1`, `controls`, `datalog`, `developer_3d`, `developer_menu`, `dialogue`, `items`, `options`, `quest_log`, `reserve`, `ritual`, `save_menu`, `shop`, `status`).
* **Stability:** Stable across consecutive runs.
* **Nature of Difference:** Visual differences reflect GPU/renderer driver pipeline precision shifts alongside upstream presentation updates.

### 2. G6 Editor Screenshots (`check-editor.ps1`)
* **Status:** Failed (Exit code 1).
* **Matches:** 24 / 37 frames.
* **Mismatches (13 frames):**
  - `campaign-gen/default.png`
  - `database/actors.png` (reflects recent actor portrait additions/updates on main)
  - `database/items.png`
  - `database/quests.png`
  - `icon-picker/default.png`
  - `map-editor/command-selector.png`
  - `map-editor/event-modal.png`
  - `map-editor/map-properties.png`
  - `map-editor/mode-event.png`
  - `map-editor/mode-light.png`
  - `map-editor/mode-map.png`
  - `map-editor/mode-override.png`
  - `studio/preferences.png`
* **Stability:** Stable 13-mismatch set at current HEAD.

---

## Non-Reproducible Historical Failures

- **G1 failure rumors:** None. G1 passes cleanly.
- **G2 / G3 regressions:** None. Battle logs and UI event traces are byte-identical to golden references.
- **Unit test failures:** None. Unit tests pass (including `test_reachability`).
- **Savetest failure:** None. Save/load round-trip is 100% clean.

---

## Currently Reproducible Failures Ordered by Severity

1. **G5 Reference Mismatch (High Visual Scope, 83 frames):** Game scene rendering differs at pixel level from recorded golden images in `tools/golden/screens/`. Requires owner inspection of `tools/golden/screens-actual/` to approve reference update.
2. **G6 Reference Mismatch (13 editor modal/tab frames):** Headless Chrome rendering of vanilla JS editor differs from `tools/golden/editor-screens/`. Requires owner inspection of `tools/golden/editor-screens-actual/`.

---

## Recommended Owner Actions

- Inspect diffs in `tools/golden/screens-actual/` against `tools/golden/screens/`. If visual changes are due to GPU environment differences or accepted UI layout updates, run `powershell -NoProfile -ExecutionPolicy Bypass -File tools\golden\capture-screens.ps1` to update golden assets.
- Inspect `tools/golden/editor-screens-actual/` against `tools/golden/editor-screens/`. If approved, update golden editor references via `tools/golden/capture-editor.py`.
