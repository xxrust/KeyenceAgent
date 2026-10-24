@echo off
setlocal
rem ============================================================
rem  TEST: Universal Library dependency check (offline)
rem  PASS = synthetic + optional live trees match expected codes
rem ============================================================
echo [1/2] run offline cases
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1"
if errorlevel 1 goto fail
echo [2/2] done
echo.
echo PASS - library dependency check
exit /b 0
:fail
echo.
echo FAIL - library dependency check
exit /b 1
