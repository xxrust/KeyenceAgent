@echo off
setlocal
rem ==========================================================
rem  Axis registration example (verified 2026-10-20)
rem  0-axis project -> insert 2 EtherCAT slaves -> batch axis
rem  registration + coordinate wizard (pitch 20/40) -> save
rem  Verdict: axes=2 / slaves=2
rem ==========================================================
set "HERE=%~dp0"
for %%I in ("%HERE%..\..") do set "REPO=%%~fI"
set "WORK=%TEMP%\kv-axis-demo-%RANDOM%"
set "KPR=%WORK%\QA_BlankProject.kpr"
set "KVS_PID="

echo [1/4] prepare project copy: %WORK%
mkdir "%WORK%" 2>nul
xcopy "%HERE%fixtures\QA_BlankProject" "%WORK%" /E /I /Q /Y >nul
copy "%HERE%nodes.json" "%WORK%\nodes.json" >nul
rem pitfall: a stale layout file hides the project tree -> delete it
del "%WORK%\DocumentWindowInfo.xml" >nul 2>nul

echo [2/4] start KV STUDIO (fresh instance)
for /f %%P in ('powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tests\_helpers\start-owned-kvs.ps1" -ProjectPath "%KPR%"') do set "KVS_PID=%%P"
if not defined KVS_PID goto fail
powershell -NoProfile -Command "Start-Sleep -Seconds 18"

echo [3/4] insert EtherCAT slaves (existing route, unchanged)
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\scripts\workflows\configure_kv_ethercat_nodes.ps1" -ProjectPath "%KPR%" -NodesConfigPath "%WORK%\nodes.json" -OutDir "%WORK%\step1" -TimeoutSeconds 600
if errorlevel 1 goto fail

echo [4/4] axis registration finish (verified script: dialogs + wizard + save)
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\scripts\runner_children\complete_axis_registration_guarded.ps1" -OutDir "%WORK%\step2" -PitchCsv "20,40" -StepTimeoutSec 3
if errorlevel 1 goto fail

echo verdict:
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%verify.ps1" -WorkDir "%WORK%"
set "RC=%ERRORLEVEL%"
echo work dir: %WORK%
if defined KVS_PID powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tests\_helpers\stop-owned-kvs.ps1" -ProcessId %KVS_PID% -ProjectPath "%KPR%"
endlocal & exit /b %RC%

:fail
set "RC=1"
if defined KVS_PID powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%REPO%\tests\_helpers\stop-owned-kvs.ps1" -ProcessId %KVS_PID% -ProjectPath "%KPR%"
echo FAILED - check %WORK%
endlocal & exit /b %RC%
