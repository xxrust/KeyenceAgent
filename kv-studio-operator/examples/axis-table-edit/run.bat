@echo off
setlocal enabledelayedexpansion
rem ==========================================================
rem  Axis control table cell edit example
rem  Default (no args) : self-contained test, two cases
rem                      negative = no KVS -> KV_TABLE_NO_KVS
rem                      positive = fixture project + row 39 -> 1500
rem  -Interactive      : legacy manual flow (list, ask, edit)
rem ==========================================================
if /I "%~1"=="-Interactive" goto interactive

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0run.ps1" %*
exit /b %errorlevel%

:interactive
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
