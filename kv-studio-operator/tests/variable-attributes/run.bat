@echo off
setlocal
rem ============================================================
rem  TEST: variable write-capability contract (offline)
rem  PASS = all allow/reject cases match the expected error code
rem ============================================================
echo [1/2] run offline cases
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1"
if errorlevel 1 goto fail
echo [2/2] done
echo.
echo PASS - variable write capability
exit /b 0
:fail
echo.
echo FAIL - variable write capability
exit /b 1
