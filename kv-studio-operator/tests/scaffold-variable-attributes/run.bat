@echo off
setlocal
rem ============================================================
rem  TEST: scaffold variable-attribute contract (offline)
rem  PASS = render/validate/plan agree on variables.attributes
rem ============================================================
echo [1/2] run offline cases
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1"
if errorlevel 1 goto fail
echo [2/2] done
echo.
echo PASS - scaffold variable attributes
exit /b 0
:fail
echo.
echo FAIL - scaffold variable attributes
exit /b 1
