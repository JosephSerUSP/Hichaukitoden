@echo off
REM ============================================================
REM  G3 - GOLDEN UI GATE
REM  Drives every scene through scene_host and diffs each scene's
REM  UI trace against tools\golden\scene_<id>.log.
REM  PASS when every scene prints: Golden UI log matches for scene '<id>'.
REM
REM  Delegates to tools\golden\check-ui.ps1 (single source of truth).
REM  NEVER regenerate a scene log just to make a red diff green.
REM ============================================================
cd /d "%~dp0.."
echo Running G3 golden UI...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\golden\check-ui.ps1"
echo.
echo ---------------------------------------------------------
echo G3 finished. Every scene must report a match.
echo ---------------------------------------------------------
pause
