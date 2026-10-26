param([string]$WorkRoot = '')

$ErrorActionPreference = 'Stop'

# Offline regression for verify_kv_variable_usage.ps1.
# Proves the preflight: declared symbols pass, an undeclared symbol fails, and a
# device+initial_value conflict fails, all before any KV STUDIO input.

$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $PSScriptRoot '..\_helpers\invoke_tool.ps1')
$tool = Join-Path $skillRoot 'scripts\workflow_tools\verify_kv_variable_usage.ps1'

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-variable-usage-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}
function New-Scaffold([string]$Name, [string]$GlobalsTsv, [string]$MnmText) {
  $root = Join-Path $WorkRoot $Name
  $moduleDir = Join-Path $root 'modules\Main'
  New-Item -ItemType Directory -Force -Path $moduleDir | Out-Null
  [ordered]@{
    variables = [ordered]@{
      allowed_custom_data_types = @()
      sets = @([ordered]@{ module_name = 'Main'; global_tsv = 'globals.tsv'; local_tsv = '' })
    }
    mnm_files = @([ordered]@{ path = 'modules/Main/Main.mnm' })
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $root 'scaffold.json') -Encoding UTF8
  [IO.File]::WriteAllText((Join-Path $root 'globals.tsv'), $GlobalsTsv, (New-Object Text.UTF8Encoding($false)))
  [IO.File]::WriteAllText((Join-Path $moduleDir 'Main.mnm'), $MnmText, [Text.Encoding]::Unicode)
  return $root
}

$cleanGlobals = @(
  "name`tdata_type`tdevice`tinitial_value`tstatus",
  "DeclaredVar`tINT`t`t`tok"
) -join "`r`n"
$cleanRoot = New-Scaffold 'clean' $cleanGlobals ('LD DeclaredVar' + "`r`n" + 'OUT DeclaredVar')
$cleanExit = Invoke-TestTool -ScriptPath $tool -Arguments @('-ScaffoldRoot', $cleanRoot, '-OutDir', (Join-Path $cleanRoot 'check'))
$cleanReportPath = Join-Path $cleanRoot 'check\variable_usage_report.json'
$cleanReport = if (Test-Path -LiteralPath $cleanReportPath) { Get-Content -LiteralPath $cleanReportPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
Add-Case 'clean scaffold exits 0' ($cleanExit -eq 0) "exit=$cleanExit"
Add-Case 'clean scaffold ok' ([bool]($cleanReport -and $cleanReport.ok)) "ok=$($cleanReport.ok)"
Add-Case 'clean scaffold declares one global' ([int]$cleanReport.declared_globals -eq 1) "globals=$($cleanReport.declared_globals)"
Add-Case 'clean scaffold has no unresolved symbols' (@($cleanReport.unresolved_symbols).Count -eq 0) (@($cleanReport.unresolved_symbols | ForEach-Object { $_.name }) -join ',')

$missingGlobals = @(
  "name`tdata_type`tdevice`tinitial_value`tstatus",
  "DeclaredVar`tINT`t`t`tok"
) -join "`r`n"
$missingRoot = New-Scaffold 'missing' $missingGlobals ('LD DeclaredVar' + "`r`n" + 'OUT MissingVar')
$missingExit = Invoke-TestTool -ScriptPath $tool -Arguments @('-ScaffoldRoot', $missingRoot, '-OutDir', (Join-Path $missingRoot 'check'))
$missingReportPath = Join-Path $missingRoot 'check\variable_usage_report.json'
$missingReport = if (Test-Path -LiteralPath $missingReportPath) { Get-Content -LiteralPath $missingReportPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
Add-Case 'undeclared symbol exits non-zero' ($missingExit -ne 0) "exit=$missingExit"
Add-Case 'undeclared symbol reported' ([bool]($missingReport -and (@($missingReport.unresolved_symbols | ForEach-Object { $_.name }) -contains 'MissingVar'))) (@($missingReport.unresolved_symbols | ForEach-Object { $_.name }) -join ',')

$conflictGlobals = @(
  "name`tdata_type`tdevice`tinitial_value`tstatus",
  "R_Flag`tBOOL`tR100`tTRUE`tok"
) -join "`r`n"
$conflictRoot = New-Scaffold 'conflict' $conflictGlobals 'LD R_Flag'
$conflictExit = Invoke-TestTool -ScriptPath $tool -Arguments @('-ScaffoldRoot', $conflictRoot, '-OutDir', (Join-Path $conflictRoot 'check'))
$conflictReportPath = Join-Path $conflictRoot 'check\variable_usage_report.json'
$conflictReport = if (Test-Path -LiteralPath $conflictReportPath) { Get-Content -LiteralPath $conflictReportPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
Add-Case 'device+initial_value exits non-zero' ($conflictExit -ne 0) "exit=$conflictExit"
Add-Case 'device+initial_value conflict reported' ([bool]($conflictReport -and @($conflictReport.device_initial_conflicts).Count -eq 1)) (@($conflictReport.device_initial_conflicts | ForEach-Object { $_.name }) -join ',')

$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'variable-usage'; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0

