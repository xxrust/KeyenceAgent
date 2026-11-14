param(
  [Parameter(Mandatory=$true)][string]$PlanPath,
  [string]$OutDir = '',
  # A delivery gate requires every check by default. Diagnostic callers may opt
  # into partial reports, but those reports are never a successful gate.
  [switch]$AllowSkippedChecks,
  [Alias('Strict')][switch]$RequireAllChecks
)
# Offline integrity gate for an execution plan. Wires the three preflight tools
# that used to have no caller:
#   - get_kv_module_completion  (imports / FB arguments / variables receipts)
#   - plan_kv_variable_dependencies (type/device/FB readiness of the global TSV)
#   - verify_kv_variable_usage  (every MNM symbol is declared)
# No UI, no KV STUDIO. Exit 41 when any check fails.
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw "KV_PLAN_MISSING: $PlanPath" }
$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($PlanPath))) 'plan_integrity' }
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$scriptsRoot = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $scriptsRoot 'workflow_tools'
$checks = New-Object System.Collections.Generic.List[object]

function Add-Check([string]$Name, [string]$Status, [int]$ExitCode, [string]$ResultPath, [string]$Detail = '') {
  $checks.Add([pscustomobject]@{ name = $Name; status = $Status; exit_code = $ExitCode; result_path = $ResultPath; detail = $Detail })
}

function Invoke-OfflineTool([string]$ScriptName, [string[]]$Arguments, [string]$ResultName) {
  $scriptPath = Join-Path $toolRoot $ScriptName
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { return @{ exit = 41; result = ''; detail = "tool missing: $scriptPath" } }
  $stdoutPath = Join-Path $OutDir ("{0}.stdout.txt" -f $ResultName)
  $stderrPath = Join-Path $OutDir ("{0}.stderr.txt" -f $ResultName)
  $arguments = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) + $Arguments
  & powershell @arguments 1> $stdoutPath 2> $stderrPath
  $exit = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }
  $resultPath = Join-Path $OutDir $ResultName
  $detail = ''
  if (-not (Test-Path -LiteralPath $resultPath)) {
    $detail = ((Get-Content -LiteralPath $stderrPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) + ' ' + (Get-Content -LiteralPath $stdoutPath -Raw -Encoding UTF8 -ErrorAction SilentlyContinue)).Trim()
  }
  return @{ exit = $exit; result = $resultPath; detail = $detail }
}

$moduleOut = Join-Path $OutDir 'module_completion'
# -AllowEmptyPlan turns "plan with no modules" into a skipped check below instead of
# a hard error; a real module list must still prove itself (issue #3 R06).
$moduleArgs = @('-PlanPath', $PlanPath, '-OutDir', $moduleOut)
if ($AllowSkippedChecks) { $moduleArgs += '-AllowEmptyPlan' }
$module = Invoke-OfflineTool 'get_kv_module_completion.ps1' $moduleArgs 'module_completion.json'
$moduleResultPath = Join-Path $moduleOut 'module_completion.json'
# A tool that exits 0 without writing its report proves nothing (issue #3 R01).
$moduleStatus = if ($module.exit -ne 0 -or -not (Test-Path -LiteralPath $moduleResultPath -PathType Leaf)) { 'fail' } else { 'pass' }
if ($moduleStatus -eq 'pass') {
  $moduleReport = Get-Content -LiteralPath $moduleResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
  if ($moduleReport.empty_plan) {
    $moduleStatus = if ($AllowSkippedChecks) { 'skipped' } else { 'fail' }
    $module.detail = 'plan has no variable_sets: nothing to prove'
  }
}
Add-Check 'module_completion' $moduleStatus $module.exit $moduleResultPath $module.detail

$globalTsv = [string]$plan.merged_global_variables_tsv
if (-not $globalTsv) { $globalTsv = [string]$plan.runtime_global_variables_tsv }
if ($globalTsv -and (Test-Path -LiteralPath $globalTsv -PathType Leaf)) {
  $depOut = Join-Path $OutDir 'variable_dependencies'
  $depArgs = @('-VariablesTsv', $globalTsv, '-OutDir', $depOut, '-RequireReady')
  # Forward the structure/axis/FB context when the plan carries it, so custom types
  # are resolved instead of being reported as missing_type:* (issue #3 R01).
  $structureDefs = [string]$plan.structure_definitions_path
  if ($structureDefs -and (Test-Path -LiteralPath $structureDefs -PathType Leaf)) { $depArgs += @('-StructureDefinitionsPath', $structureDefs) }
  # A variable's _MC_Axis[n] device is a requirement, not proof that axis n is
  # configured. Only a planner-provided verified inventory may satisfy it.
  if ([bool]$plan.axis_context_verified) {
    foreach ($axisIndex in @($plan.axis_indexes)) { if ($null -ne $axisIndex -and [string]$axisIndex -ne '') { $depArgs += @('-AxisIndexes', [string]$axisIndex) } }
  }
  if ($plan.fb_types) {
    $depArgs += '-FbTypes'
    $depArgs += @($plan.fb_types | ForEach-Object { [string]$_ })
  }
  $dep = Invoke-OfflineTool 'plan_kv_variable_dependencies.ps1' $depArgs 'variable_dependencies.json'
  $depResultPath = Join-Path $depOut 'variable_dependency_report.json'
  $depStatus = 'fail'
  if ($dep.exit -eq 0 -and (Test-Path -LiteralPath $depResultPath -PathType Leaf)) {
    $depReport = Get-Content -LiteralPath $depResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $depStatus = if ($depReport.ok) { 'pass' } else { 'fail' }
    if (-not $depReport.ok) { $dep.detail = ("blocked_count={0}" -f $depReport.blocked_count) }
  }
  Add-Check 'variable_dependencies' $depStatus $dep.exit $depResultPath $dep.detail
} else {
  Add-Check 'variable_dependencies' 'skipped' 0 '' 'plan has no merged_global_variables_tsv'
}

$scaffoldRoot = [string]$plan.scaffold_root
if ($scaffoldRoot -and (Test-Path -LiteralPath $scaffoldRoot -PathType Container)) {
  $usageOut = Join-Path $OutDir 'variable_usage'
  $usage = Invoke-OfflineTool 'verify_kv_variable_usage.ps1' @('-ScaffoldRoot', $scaffoldRoot, '-OutDir', $usageOut) 'variable_usage.json'
  $usageResultPath = Join-Path $usageOut 'variable_usage_report.json'
  $usageStatus = if ($usage.exit -eq 0 -and (Test-Path -LiteralPath $usageResultPath -PathType Leaf)) { 'pass' } else { 'fail' }
  Add-Check 'variable_usage' $usageStatus $usage.exit $usageResultPath $usage.detail
} else {
  Add-Check 'variable_usage' 'skipped' 0 '' 'plan has no scaffold_root'
}

$failed = @($checks | Where-Object { $_.status -eq 'fail' })
$skipped = @($checks | Where-Object { $_.status -eq 'skipped' })
# A check that never ran is not a pass: with -RequireAllChecks a skipped check fails
# the gate (issue #3 R01).
$blocking = @($failed) + @($skipped | ForEach-Object { [pscustomobject]@{ name = $_.name; status = 'fail'; exit_code = 41; result_path = $_.result_path; detail = 'check did not run: ' + $_.detail } })
$report = [ordered]@{
  ok = ($blocking.Count -eq 0)
  plan_path = $PlanPath
  allow_skipped_checks = [bool]$AllowSkippedChecks
  checks = $checks.ToArray()
  failed_count = $failed.Count
  skipped_count = $skipped.Count
  generated_at = (Get-Date).ToString('o')
}
$reportPath = Join-Path $OutDir 'plan_integrity_result.json'
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 4
Write-Host ("KV_PLAN_INTEGRITY: ok={0} checks={1} failed={2} skipped={3} report={4}" -f $report.ok, $checks.Count, $failed.Count, $skipped.Count, $reportPath)
if ($blocking.Count -gt 0) { exit 41 }
exit 0
