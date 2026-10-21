@echo off
setlocal enabledelayedexpansion
rem ==========================================================
rem  Axis control table cell edit (verified 2026-10-20)
rem  Read : click table + Ctrl+A + Ctrl+C  -> TSV on clipboard
rem  Write: click cell + F2 + Ctrl+A + type + Enter
rem  Row Y : y = gridTop + 82 + (RowIndex-1)*17.7   (row index is
rem          the same index printed by the list step below)
rem ==========================================================
set "HERE=%~dp0"
set "REPO=H:\KeyenceAgent\kv-studio-operator"
set "OUT=%TEMP%\kv-table-edit-%RANDOM%"
set "SCRIPT=%REPO%\scripts\runner_children\set_axis_table_cell_guarded.ps1"

echo [1/3] List rows of the axis control table
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -OutDir "%OUT%" -ListOnly
if errorlevel 1 goto fail

echo.
echo [2/3] Enter the row index to edit (see list above), column (1=Axis1, 2=Axis2) and new value
set /p ROW=row index: 
set /p COL=column [1]: 
if "%COL%"=="" set "COL=1"
set /p VAL=new value: 
if "%VAL%"=="" goto fail

echo [3/3] Edit row %ROW% col %COL% -> %VAL% (screenshot + diff + save)
powershell -NoProfile -ExecutionPolicy Bypass -File "%SCRIPT%" -OutDir "%OUT%\edit" -RowIndex %ROW% -Column %COL% -Value "%VAL%"
if errorlevel 1 goto fail

echo.
echo Result: %OUT%\edit\table_edit_result.json
echo Screenshots: %OUT%\edit\b1_before.png b2_after_typing.png b3_after_read.png b4_saved.png
endlocal
exit /b 0

:fail
echo FAILED - check %OUT%
endlocal
exit /b 1