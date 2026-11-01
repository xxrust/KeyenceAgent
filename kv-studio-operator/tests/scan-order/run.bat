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
rem ============================================================
rem  TEST: saved scan-order verification (offline, no KV STUDIO)
rem  PASS = all synthetic cases match expected ok/error code
rem ============================================================
set "OUT=%TEMP%\kv-scan-order-bat-%RANDOM%"
echo [1/2] run offline cases
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run.ps1" %SCRIPT_ARGS%
if errorlevel 1 goto fail
echo [2/2] done
echo.
echo PASS - scan order verification
exit /b 0
:fail
echo.
echo FAIL - scan order verification
exit /b 1
