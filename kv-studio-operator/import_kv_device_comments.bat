@echo off
setlocal
set "SKILL_ROOT=%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File "%SKILL_ROOT%scripts\workflows\import_kv_device_comments.ps1" %*
exit /b %ERRORLEVEL%
