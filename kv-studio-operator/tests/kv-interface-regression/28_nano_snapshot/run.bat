@echo off
setlocal
powershell -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
set "test_exit=%ERRORLEVEL%"
if not "%KV_TEST_NO_PAUSE%"=="1" pause
exit /b %test_exit%
