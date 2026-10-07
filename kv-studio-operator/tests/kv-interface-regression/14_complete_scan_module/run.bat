@echo off
setlocal
set "SCRIPT_DIR=%~dp0"
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT_DIR%run.ps1" %*
set "EXIT_CODE=%ERRORLEVEL%"
echo.
if "%EXIT_CODE%"=="0" (echo 14_complete_scan_module completed successfully.) else (echo 14_complete_scan_module failed. Exit code: %EXIT_CODE%)
pause
exit /b %EXIT_CODE%
