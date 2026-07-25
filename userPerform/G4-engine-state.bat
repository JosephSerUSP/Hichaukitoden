@echo off
REM ============================================================
REM  G4 - ENGINE STATE (DOCUMENTATION) GATE
REM  Confirms docs\ENGINE-STATE.md still matches what the engine
REM  actually reports.
REM  PASS when it prints:  Engine state doc matches.
REM
REM  A RED G4 IS A STALE DOC, NOT A REGRESSION. Unlike G2/G3, the
REM  fix is to regenerate: run capture-state.ps1 (see below) and
REM  commit the updated docs\ENGINE-STATE.md.
REM ============================================================
cd /d "%~dp0.."
echo Running G4 engine state...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\golden\check-state.ps1"
echo.
echo ---------------------------------------------------------
echo G4 finished. If STALE, run:
echo   powershell -File tools\golden\capture-state.ps1
echo then commit docs\ENGINE-STATE.md
echo ---------------------------------------------------------
pause
