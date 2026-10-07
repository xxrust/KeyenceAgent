@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PAUSE_AFTER=1"
if /I "%~1"=="-NoPause" (set "PAUSE_AFTER=0" & shift)
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" (echo 13_project_text_snapshot completed successfully.) else (echo 13_project_text_snapshot failed. Exit code: %EXIT_CODE%)
if "%PAUSE_AFTER%"=="1" pause
exit /b %EXIT_CODE%
