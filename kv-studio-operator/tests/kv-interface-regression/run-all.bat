@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PAUSE_AFTER=1"
if /I "%~1"=="-NoPause" (
  set "PAUSE_AFTER=0"
  shift
)
pushd "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run-all.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
popd
echo.
if "%EXIT_CODE%"=="0" (echo KV STUDIO regression dispatch completed successfully.) else (echo KV STUDIO regression dispatch failed. Exit code: %EXIT_CODE%)
if "%PAUSE_AFTER%"=="1" pause
exit /b %EXIT_CODE%
