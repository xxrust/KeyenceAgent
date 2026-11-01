@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
set "PAUSE_AFTER=1"
set "SCRIPT_ARGS="
if /I "%~1"=="-NoPause" goto NOPAUSE
goto COLLECT_ARGS
:NOPAUSE
set "PAUSE_AFTER=0"
shift
:COLLECT_ARGS
if "%~1"=="" goto RUN_SCRIPT
set SCRIPT_ARGS=%SCRIPT_ARGS% %1
shift
goto COLLECT_ARGS
:RUN_SCRIPT
pushd "%~dp0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run-all.ps1" %SCRIPT_ARGS%
set "EXIT_CODE=%ERRORLEVEL%"
popd
echo.
if "%EXIT_CODE%"=="0" (echo KV STUDIO regression dispatch completed successfully.) else (echo KV STUDIO regression dispatch failed. Exit code: %EXIT_CODE%)
if "%PAUSE_AFTER%"=="1" pause
exit /b %EXIT_CODE%
