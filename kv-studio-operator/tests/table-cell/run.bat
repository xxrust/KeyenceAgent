@echo off
setlocal
rem ============================================================
rem  TEST: axis control table cell edit (object based, row 39 -> 1500)
rem  PASS = result json ok:true AND exactly one row changed at 39
rem ============================================================
for %%I in ("%~dp0..\..") do set "REPO=%%~fI"
set "FIX=%~dp0fixtures\QA_BlankProject"
set "OUT=%TEMP%\kv-test-cell-%RANDOM%"
set "KPR=%OUT%\QA_BlankProject\QA_BlankProject.kpr"
set "KVS_PID="
echo [1/5] copy fixture to %OUT%
robocopy "%FIX%" "%OUT%\QA_BlankProject" /E /NFL /NDL /NJH /NJS >nul
del /q "%OUT%\QA_BlankProject\DocumentWindowInfo.xml" 2>nul
echo [2/5] start KV STUDIO with the copy
for /f %%P in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tests\_helpers\start-owned-kvs.ps1" -ProjectPath "%KPR%"') do set "KVS_PID=%%P"
if not defined KVS_PID goto fail
powershell -NoProfile -Command "Start-Sleep -Seconds 20"
echo [3/5] navigate to axis1 - axis control settings
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0open-table.ps1"
if errorlevel 1 goto fail
echo [4/5] edit row 39 col 1 -> 1500
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\scripts\runner_children\set_axis_table_cell_guarded.ps1" -OutDir "%OUT%\cell" -RowIndex 39 -Column 1 -Value 1500
if errorlevel 1 goto fail
echo [5/5] verify result json
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify.ps1" -OutDir "%OUT%" -Stage result
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
