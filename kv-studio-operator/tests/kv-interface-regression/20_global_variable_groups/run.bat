@echo off
powershell.exe -STA -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
