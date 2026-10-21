@echo off
setlocal
rem ==========================================================
rem  Axis registration example (verified 2026-10-20)
rem  0-axis project -> insert 2 EtherCAT slaves -> batch axis
rem  registration + coordinate wizard (pitch 20/40) -> save
rem  Verdict: axes=2 / slaves=2
rem ==========================================================
set "HERE=%~dp0"
set "KVS=H:\Keyence\KVS12\KVS\Kvs.exe"
set "REPO=H:\KeyenceAgent\kv-studio-operator"
set "WORK=%TEMP%\kv-axis-demo-%RANDOM%"
set "KPR=%WORK%\QA_BlankProject.kpr"

echo [1/4] prepare project copy: %WORK%
mkdir "%WORK%" 2>nul
xcopy "%HERE%fixtures\QA_BlankProject" "%WORK%" /E /I /Q /Y >nul
copy "%HERE%nodes.json" "%WORK%\nodes.json" >nul
rem pitfall: a stale layout file hides the project tree -> delete it
del "%WORK%\DocumentWindowInfo.xml" >nul 2>nul

echo [2/4] start KV STUDIO (fresh instance)
taskkill /IM Kvs.exe /F >nul 2>nul
powershell -NoProfile -Command "Start-Sleep -Seconds 4"
start "" "%KVS%" "%KPR%"
powershell -NoProfile -Command "Start-Sleep -Seconds 18"

echo [3/4] insert EtherCAT slaves (existing route, unchanged)
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\scripts\workflows\configure_kv_ethercat_nodes.ps1" -ProjectPath "%KPR%" -NodesConfigPath "%WORK%\nodes.json" -OutDir "%WORK%\step1" -TimeoutSeconds 600
echo    route exit=%ERRORLEVEL% (not a verdict)

echo [4/4] axis registration finish (verified script: dialogs + wizard + save)
powershell -NoProfile -ExecutionPolicy Bypass -File "%REPO%\scripts\runner_children\complete_axis_registration_guarded.ps1" -OutDir "%WORK%\step2" -PitchCsv "20,40" -StepTimeoutSec 3
echo    finish exit=%ERRORLEVEL% (not a verdict)

echo verdict:
powershell -NoProfile -ExecutionPolicy Bypass -File "%HERE%verify.ps1" -WorkDir "%WORK%"
set "RC=%ERRORLEVEL%"
echo work dir: %WORK%
taskkill /IM Kvs.exe /F >nul 2>nul
endlocal & exit /b %RC%