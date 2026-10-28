@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PAUSE_AFTER=1"
if /I "%~1"=="-NoPause" (set "PAUSE_AFTER=0" & shift)
echo Running %~n0 ...
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run.ps1" %*
set RC=%ERRORLEVEL%
echo.
echo exit=%RC%
if "%PAUSE_AFTER%"=="1" pause
exit /b %RC%
