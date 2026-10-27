@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PAUSE_AFTER=1"
if /I "%~1"=="-NoPause" (set "PAUSE_AFTER=0" & shift)
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" (echo 15_complete_station_fb completed successfully.) else (echo 15_complete_station_fb failed. Exit code: %EXIT_CODE%)
if "%PAUSE_AFTER%"=="1" pause
exit /b %EXIT_CODE%