@echo off
setlocal
rem ============================================================
rem  TEST: batch axis parameter write (axis 4, three params, top-down)
rem  PASS = axis_param_batch.json ok:true AND diff_cells == 3
rem ============================================================
for %%I in ("%~dp0..\..") do set "REPO=%%~fI"
set "FIX=%~dp0fixtures\QA_BlankProject"
set "OUT=%TEMP%\axisparams-%RANDOM%"
set "KPR=%OUT%\QA_BlankProject\QA_BlankProject.kpr"
set "KVS_PID="
echo [1/6] copy fixture to %OUT%
robocopy "%FIX%" "%OUT%\QA_BlankProject" /E /NFL /NDL /NJH /NJS >nul
if errorlevel 8 goto fail
del /q "%OUT%\QA_BlankProject\DocumentWindowInfo.xml" 2>nul
echo [2/6] start KV STUDIO with the copy
for /f %%P in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tests\_helpers\start-owned-kvs.ps1" -ProjectPath "%KPR%"') do set "KVS_PID=%%P"
if not defined KVS_PID goto fail
powershell -NoProfile -Command "Start-Sleep -Seconds 20"
echo [3/6] apply the batch plan
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\scripts\runner_children\axis_parameters_guarded.ps1" -Mode Apply -PlanPath "%~dp0plan.json" -OutDir "%OUT%\apply"
if errorlevel 1 goto fail
echo [4/6] verify result json
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0verify.ps1" -OutDir "%OUT%"
if errorlevel 1 goto fail
echo [5/6] read back one parameter by name
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\scripts\runner_children\axis_parameters_guarded.ps1" -Mode Read -Axis 2 -Param jog_high_speed -OutDir "%OUT%\readback" > "%OUT%\readback.log" 2>&1
if errorlevel 1 goto fail
findstr /C:"66" "%OUT%\readback.log" >nul
if errorlevel 1 goto fail
echo [6/6] done
if defined KVS_PID powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tests\_helpers\stop-owned-kvs.ps1" -ProcessId %KVS_PID% -ProjectPath "%KPR%"
echo.
echo PASS - out dir %OUT%
exit /b 0
:fail
if defined KVS_PID powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tests\_helpers\stop-owned-kvs.ps1" -ProcessId %KVS_PID% -ProjectPath "%KPR%"
echo.
echo FAIL - out dir %OUT%
exit /b 1
