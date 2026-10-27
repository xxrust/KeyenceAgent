@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PAUSE_AFTER=1"
if /I "%~1"=="-NoPause" (set "PAUSE_AFTER=0" & shift)
powershell -STA -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run.ps1" %*
set "test_exit=%errorlevel%"
if "%PAUSE_AFTER%"=="1" pause
exit /b %test_exit%