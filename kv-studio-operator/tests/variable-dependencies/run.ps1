param([string]$WorkRoot = '')

$ErrorActionPreference = 'Stop'

# Offline regression for plan_kv_variable_dependencies.ps1.
# Synthetic variables TSV + axis set prove that missing types and missing axes
# are blocked before any KV STUDIO write, while scalars and arrays are ready.

$tool = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\scripts\workflow_tools\plan_kv_variable_dependencies.ps1'))
if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "tool not found: $tool" }

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-var-deps-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$tsvPath = Join-Path $WorkRoot 'variables.tsv'
$lines = @(
  "name`tscope`towner_program`tdata_type`tdevice`tgroup`tstatus",
  "ReadyInt`tglobal`tMain`tINT`tDM0`t`tok",
  "BlockedAxis`tglobal`tMain`tINT`t_MC_Axis[2]`t`tok",
  "BlockedType`tglobal`tMain`tMysteryType`tDM10`t`tok",
  "ArrayReady`tglobal`tMain`tARRAY[1..3] OF INT`tDM20`t`tok"
) -join "`r`n"
[IO.File]::WriteAllText($tsvPath, $lines, (New-Object Text.UTF8Encoding($false)))

$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}

$outDir = Join-Path $WorkRoot 'deps'
& $tool -VariablesTsv $tsvPath -AxisIndexes 1 -OutDir $outDir | Out-Null
$exit = $LASTEXITCODE
$report = Get-Content -LiteralPath (Join-Path $outDir 'variable_dependency_report.json') -Raw -Encoding UTF8 | ConvertFrom-Json

Add-Case 'tool exits 0 without -RequireReady' ($exit -eq 0) "exit=$exit"
Add-Case 'total 4 variables' ([int]$report.total -eq 4) "total=$($report.total)"
Add-Case 'ready count 2' ([int]$report.ready_count -eq 2) "ready=$($report.ready_count)"
Add-Case 'blocked count 2' ([int]$report.blocked_count -eq 2) "blocked=$($report.blocked_count)"
$blockedNames = @($report.blocked | ForEach-Object { [string]$_.name })
Add-Case 'blocked set = BlockedAxis, BlockedType' ((($blockedNames -contains 'BlockedAxis') -and ($blockedNames -contains 'BlockedType'))) ($blockedNames -join ',')
$axisMissing = @($report.blocked | Where-Object { $_.name -eq 'BlockedAxis' } | ForEach-Object { @($_.missing) })
Add-Case 'BlockedAxis missing_axis:2' ($axisMissing -contains 'missing_axis:2') ($axisMissing -join ',')
$typeMissing = @($report.blocked | Where-Object { $_.name -eq 'BlockedType' } | ForEach-Object { @($_.missing) })
Add-Case 'BlockedType missing_type:MysteryType' ($typeMissing -contains 'missing_type:MysteryType') ($typeMissing -join ',')
Add-Case 'required axes contains 2' (@($report.required_axes) -contains 2) (@($report.required_axes) -join ',')

& $tool -VariablesTsv $tsvPath -AxisIndexes 1 -OutDir (Join-Path $WorkRoot 'deps_gate') -RequireReady | Out-Null
$gateExit = $LASTEXITCODE
Add-Case '-RequireReady exits 41 when blocked' ($gateExit -eq 41) "exit=$gateExit"

$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'variable-dependencies'; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0
