@echo off
setlocal
cd /d "%~dp0"
echo Running %~n0 ...
powershell -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
set RC=%ERRORLEVEL%
echo.
echo exit=%RC%
pause
exit /b %RC%