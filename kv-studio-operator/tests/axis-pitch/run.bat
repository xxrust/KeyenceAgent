@echo off
setlocal
rem ============================================================
rem  TEST: axis pitch change (10 -> 25) on a fixture copy
rem  PASS = result json ok:true with ratio 400 AND reopen reads 25
rem ============================================================
for %%I in ("%~dp0..\..") do set "REPO=%%~fI"
set "FIX=%~dp0fixtures\QA_BlankProject"
set "OUT=%TEMP%\kv-test-pitch-%RANDOM%"
set "KPR=%OUT%\QA_BlankProject\QA_BlankProject.kpr"
set "KVS_PID="
echo [1/6] copy fixture to %OUT%
robocopy "%FIX%" "%OUT%\QA_BlankProject" /E /NFL /NDL /NJH /NJS >nul
del /q "%OUT%\QA_BlankProject\DocumentWindowInfo.xml" 2>nul
echo [2/6] start KV STUDIO with the copy
for /f %%P in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tests\_helpers\start-owned-kvs.ps1" -ProjectPath "%KPR%"') do set "KVS_PID=%%P"
if not defined KVS_PID goto fail
powershell -NoProfile -Command "Start-Sleep -Seconds 20"
echo [3/6] run set_axis_pitch_guarded.ps1
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\scripts\runner_children\set_axis_pitch_guarded.ps1" -OutDir "%OUT%\pitch" -Pitch 25
if errorlevel 1 goto fail
echo [4/6] verify result json
set "RC=1"
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify.ps1" -OutDir "%OUT%" -Stage result
if errorlevel 1 goto fail
echo [5/6] reopen project and read back
if defined KVS_PID powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tests\_helpers\stop-owned-kvs.ps1" -ProcessId %KVS_PID% -ProjectPath "%KPR%"
set "KVS_PID="
for /f %%P in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tests\_helpers\start-owned-kvs.ps1" -ProjectPath "%KPR%"') do set "KVS_PID=%%P"
if not defined KVS_PID goto fail
powershell -NoProfile -Command "Start-Sleep -Seconds 20"
echo [6/6] read back pitch
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify.ps1" -OutDir "%OUT%" -Stage reopen
if errorlevel 1 goto fail
if defined KVS_PID powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tests\_helpers\stop-owned-kvs.ps1" -ProcessId %KVS_PID% -ProjectPath "%KPR%"
echo.
echo PASS - out dir %OUT%
exit /b 0
:fail
if defined KVS_PID powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tests\_helpers\stop-owned-kvs.ps1" -ProcessId %KVS_PID% -ProjectPath "%KPR%"
echo.
echo FAIL - out dir %OUT%
exit /b 1
