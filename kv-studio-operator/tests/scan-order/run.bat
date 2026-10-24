@echo off
setlocal
rem ============================================================
rem  TEST: saved scan-order verification (offline, no KV STUDIO)
rem  PASS = all synthetic cases match expected ok/error code
rem ============================================================
set "OUT=%TEMP%\kv-scan-order-bat-%RANDOM%"
echo [1/2] run offline cases
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" -WorkRoot "%OUT%"
if errorlevel 1 goto fail
echo [2/2] done
echo.
echo PASS - scan order verification
exit /b 0
:fail
echo.
echo FAIL - scan order verification
exit /b 1
