@echo off
REM ============================================================
REM  G3 - EDITOR GATE
REM  Starts the editor server on http://127.0.0.1:8080 and
REM  opens it in your browser.
REM  PASS when: the editor loads, you exercise the changed UI,
REM             the browser console shows ZERO errors, and a
REM             Save round-trips cleanly.
REM  Close this window (Ctrl+C) to stop the server when done.
REM ============================================================
cd /d "%~dp0.."
echo Starting editor server on http://127.0.0.1:8080 ...
start "" "http://127.0.0.1:8080"
node tools\editor\server.js
