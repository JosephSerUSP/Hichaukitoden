@echo off
REM ============================================================
REM  G5 - GOLDEN SCREENSHOT GATE
REM  Renders every scene (and every goldenScript/screenshotScript
REM  step) at native resolution and byte-compares each frame
REM  against tools\golden\screens\.
REM  PASS when it prints: SCREENS OK
REM
REM  This is the ONLY gate that can see the 3D world view --
REM  G1 validates data, G2 diffs battle logs, G3 diffs UI events.
REM  A renderer change that breaks nothing else breaks this.
REM
REM  Delegates to tools\golden\check-screens.ps1 (single source of
REM  truth). Differing frames land in tools\golden\screens-actual\
REM  for side-by-side inspection.
REM  NEVER recapture references just to make a red diff green.
REM ============================================================
cd /d "%~dp0.."
echo Running G5 golden screenshots...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\golden\check-screens.ps1"
echo.
echo ---------------------------------------------------------
echo G5 finished. It must report SCREENS OK.
echo ---------------------------------------------------------
pause
