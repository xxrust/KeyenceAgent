@echo off
setlocal
rem ============================================================
rem  TEST: axis pitch change (10 -> 25) on a fixture copy
rem  PASS = result json ok:true with ratio 400 AND reopen reads 25
rem ============================================================
set "REPO=H:\KeyenceAgent\kv-studio-operator"
set "KVS=H:\Keyence\KVS12\KVS\Kvs.exe"
set "FIX=%~dp0fixtures\QA_BlankProject"
set "OUT=%TEMP%\kv-test-pitch-%RANDOM%"
echo [1/6] copy fixture to %OUT%
robocopy "%FIX%" "%OUT%\QA_BlankProject" /E /NFL /NDL /NJH /NJS >nul
del /q "%OUT%\QA_BlankProject\DocumentWindowInfo.xml" 2>nul
echo [2/6] kill KVS and start it with the copy
taskkill /IM Kvs.exe /F >nul 2>nul
powershell -NoProfile -Command "Start-Sleep -Seconds 4"
start "" "%KVS%" "%OUT%\QA_BlankProject\QA_BlankProject.kpr"
powershell -NoProfile -Command "Start-Sleep -Seconds 20"
echo [3/6] run set_axis_pitch_guarded.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\scripts\runner_children\set_axis_pitch_guarded.ps1" -OutDir "%OUT%\pitch" -Pitch 25
if errorlevel 1 goto fail
echo [4/6] verify result json
set "RC=1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify.ps1" -OutDir "%OUT%" -Stage result
if errorlevel 1 goto fail
echo [5/6] reopen project and read back
taskkill /IM Kvs.exe /F >nul 2>nul
powershell -NoProfile -Command "Start-Sleep -Seconds 5"
start "" "%KVS%" "%OUT%\QA_BlankProject\QA_BlankProject.kpr"
powershell -NoProfile -Command "Start-Sleep -Seconds 20"
echo [6/6] read back pitch
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify.ps1" -OutDir "%OUT%" -Stage reopen
if errorlevel 1 goto fail
taskkill /IM Kvs.exe /F >nul 2>nul
echo.
echo PASS - out dir %OUT%
exit /b 0
:fail
taskkill /IM Kvs.exe /F >nul 2>nul
echo.
echo FAIL - out dir %OUT%
exit /b 1