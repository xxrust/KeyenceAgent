@echo off
setlocal
set "SKILL_ROOT=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SKILL_ROOT%scripts\workflows\configure_kv_eip_devices.ps1" %*
exit /b %ERRORLEVEL%
