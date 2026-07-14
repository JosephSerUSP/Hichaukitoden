@echo off
REM ============================================================
REM  G2 - GOLDEN GATE
REM  Runs the battle golden-master and diffs it against
REM  tools\golden\battle.log (line-ending normalized).
REM  PASS when it prints:  Golden log matches.
REM
REM  Delegates to the existing tools\golden\check.ps1 so there
REM  is a single source of truth for the comparison logic.
REM  NEVER regenerate battle.log just to make a red diff green.
REM ============================================================
cd /d "%~dp0.."
echo Running G2 golden...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\golden\check.ps1"
echo.
echo ---------------------------------------------------------
echo G2 finished. Confirm it printed: Golden log matches.
echo ---------------------------------------------------------
pause
