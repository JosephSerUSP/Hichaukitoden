@echo off
setlocal
cd /d "%~dp0.."
echo First Stratum Material Family overnight generator
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File tools\asset-gen\start_first_stratum_overnight.ps1
echo.
echo Double-clicking this launcher again is safe; an active worker will be reused.
pause
