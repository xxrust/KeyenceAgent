@echo off
setlocal
rem ============================================================
rem  TEST: axis control table cell edit (object based, row 39 -> 1500)
rem  PASS = result json ok:true AND exactly one row changed at 39
rem ============================================================
set "REPO=H:\KeyenceAgent\kv-studio-operator"
set "KVS=H:\Keyence\KVS12\KVS\Kvs.exe"
set "FIX=%~dp0fixtures\QA_BlankProject"
set "OUT=%TEMP%\kv-test-cell-%RANDOM%"
echo [1/5] copy fixture to %OUT%
robocopy "%FIX%" "%OUT%\QA_BlankProject" /E /NFL /NDL /NJH /NJS >nul
del /q "%OUT%\QA_BlankProject\DocumentWindowInfo.xml" 2>nul
echo [2/5] kill KVS and open the copy
taskkill /IM Kvs.exe /F >nul 2>nul
powershell -NoProfile -Command "Start-Sleep -Seconds 4"
start "" "%KVS%" "%OUT%\QA_BlankProject\QA_BlankProject.kpr"
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
taskkill /IM Kvs.exe /F >nul 2>nul
echo.
echo PASS - out dir %OUT%
exit /b 0
:fail
taskkill /IM Kvs.exe /F >nul 2>nul
echo.
echo FAIL - out dir %OUT%
exit /b 1