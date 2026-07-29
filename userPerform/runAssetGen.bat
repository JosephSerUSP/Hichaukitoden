@echo off
REM ============================================================
REM  ASSET-GEN UI
REM  Opens the art generation tool in your browser.
REM  This is NOT the editor: it calls paid image models and
REM  writes PNGs. Nothing lands in assets\ until you press
REM  Promote on a variant.
REM
REM  Set your key once, in a normal command prompt:
REM      setx OPENAI_API_KEY sk-...
REM  (then reopen the prompt), or paste it into the Key box in
REM  the UI, where it is kept in memory only and never saved.
REM
REM  Requires Python with Pillow and requests:
REM      python -m pip install Pillow requests
REM ============================================================
cd /d "%~dp0.."
echo Starting asset-gen UI...
echo Close this window to stop the server.
echo.
python tools\asset-gen\server.py
pause
