@echo off
REM ============================================================
REM  G6 - GOLDEN EDITOR SCREENSHOT GATE
REM  Boots tools\editor\server.js on a port of its own, drives a
REM  headless Chrome through every editor tab and modal, and
REM  byte-compares each frame against tools\golden\editor-screens\.
REM  PASS when it prints: EDITOR SCREENS OK
REM
REM  This is the ONLY gate that can see the editor. G1 validates
REM  the data the editor writes; nothing looked at the editor
REM  itself, so an empty form or a tab that throws before it
REM  paints stayed invisible until someone opened that exact tab.
REM
REM  Read-only: no step saves, so it cannot touch data\*.json.
REM
REM  Needs Node, Python (+ the websocket-client package) and
REM  Chrome. Set CHROME_PATH if Chrome is not in Program Files.
REM
REM  Delegates to tools\golden\check-editor.ps1 (single source of
REM  truth). Differing frames land in
REM  tools\golden\editor-screens-actual\ for side-by-side viewing.
REM  NEVER recapture references just to make a red diff green.
REM ============================================================
cd /d "%~dp0.."
echo Running G6 golden editor screenshots...
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "tools\golden\check-editor.ps1"
echo.
echo ---------------------------------------------------------
echo G6 finished. It must report EDITOR SCREENS OK.
echo ---------------------------------------------------------
pause
