@echo off
powershell -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
set "test_exit=%errorlevel%"
pause
exit /b %test_exit%
