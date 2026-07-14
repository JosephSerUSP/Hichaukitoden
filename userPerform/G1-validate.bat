@echo off
REM ============================================================
REM  G1 - VALIDATE GATE
REM  Runs the engine's data/formula validator.
REM  PASS when the output ends with:  VALIDATE OK
REM  Note: the line "[formula] error in 'os.time()'" is an
REM        EXPECTED sandbox negative-test, NOT a failure.
REM ============================================================
cd /d "%~dp0.."
echo Running G1 validate...
echo.
"C:\Program Files\LOVE\lovec.exe" . validate
echo.
echo ---------------------------------------------------------
echo G1 finished. Confirm the output ended with: VALIDATE OK
echo ---------------------------------------------------------
pause
