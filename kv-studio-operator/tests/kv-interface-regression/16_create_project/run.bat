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
powershell -STA -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run.ps1" %SCRIPT_ARGS%
set "test_exit=%errorlevel%"
if "%PAUSE_AFTER%"=="1" pause
exit /b %test_exit%