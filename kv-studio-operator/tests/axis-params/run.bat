@echo off
setlocal
rem ============================================================
rem  TEST: batch axis parameter write (axis 4, three params, top-down)
rem  PASS = axis_param_batch.json ok:true AND diff_cells == 3
rem ============================================================
set "REPO=H:\KeyenceAgent\kv-studio-operator"
set "KVS=H:\Keyence\KVS12\KVS\Kvs.exe"
set "FIX=%~dp0fixtures\KVX????_v100"
set "OUT=C:\kvrun\axisparams-%RANDOM%"
echo [1/6] copy fixture to %OUT%
if not exist "C:\kvrun" mkdir "C:\kvrun"
robocopy "%FIX%" "%OUT%\KVX????_v100" /E /NFL /NDL /NJH /NJS >nul
del /q "%OUT%\KVX????_v100\DocumentWindowInfo.xml" 2>nul
echo [2/6] kill KVS and open the copy
taskkill /IM Kvs.exe /F >nul 2>nul
powershell -NoProfile -Command "Start-Sleep -Seconds 5"
start "" "%KVS%" "%OUT%\KVX????_v100\KVX????_v100.kpr"
powershell -NoProfile -Command "Start-Sleep -Seconds 20"
echo [3/6] apply the batch plan
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\scripts\runner_children\axis_parameters_guarded.ps1" -Mode Apply -PlanPath "%~dp0plan.json" -OutDir "%OUT%\apply"
if errorlevel 1 goto fail
echo [4/6] verify result json
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify.ps1" -OutDir "%OUT%"
if errorlevel 1 goto fail
echo [5/6] read back one parameter by name
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\scripts\runner_children\axis_parameters_guarded.ps1" -Mode Read -Axis 4 -Param "JOG????" -OutDir "%OUT%\readback" > "%OUT%\readback.log" 2>&1
if errorlevel 1 goto fail
findstr /C:"66" "%OUT%\readback.log" >nul
if errorlevel 1 goto fail
echo [6/6] done
taskkill /IM Kvs.exe /F >nul 2>nul
echo.
echo PASS - out dir %OUT%
exit /b 0
:fail
taskkill /IM Kvs.exe /F >nul 2>nul
echo.
echo FAIL - out dir %OUT%
exit /b 1
