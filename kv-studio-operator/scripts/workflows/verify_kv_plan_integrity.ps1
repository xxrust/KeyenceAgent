param(
  [Parameter(Mandatory=$true)][string]$PlanPath,
  [string]$OutDir = ''
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
$module = Invoke-OfflineTool 'get_kv_module_completion.ps1' @('-PlanPath', $PlanPath, '-OutDir', $moduleOut) 'module_completion.json'
$moduleResultPath = Join-Path $moduleOut 'module_completion.json'
Add-Check 'module_completion' $(if ($module.exit -eq 0) { 'pass' } else { 'fail' }) $module.exit $moduleResultPath $module.detail

$globalTsv = [string]$plan.merged_global_variables_tsv
if (-not $globalTsv) { $globalTsv = [string]$plan.runtime_global_variables_tsv }
if ($globalTsv -and (Test-Path -LiteralPath $globalTsv -PathType Leaf)) {
  $depOut = Join-Path $OutDir 'variable_dependencies'
  $dep = Invoke-OfflineTool 'plan_kv_variable_dependencies.ps1' @('-VariablesTsv', $globalTsv, '-OutDir', $depOut) 'variable_dependencies.json'
  $depResultPath = Join-Path $depOut 'variable_dependency_report.json'
  Add-Check 'variable_dependencies' $(if ($dep.exit -eq 0) { 'pass' } else { 'fail' }) $dep.exit $depResultPath $dep.detail
} else {
  Add-Check 'variable_dependencies' 'skipped' 0 '' 'plan has no merged_global_variables_tsv'
}

$scaffoldRoot = [string]$plan.scaffold_root
if ($scaffoldRoot -and (Test-Path -LiteralPath $scaffoldRoot -PathType Container)) {
  $usageOut = Join-Path $OutDir 'variable_usage'
  $usage = Invoke-OfflineTool 'verify_kv_variable_usage.ps1' @('-ScaffoldRoot', $scaffoldRoot, '-OutDir', $usageOut) 'variable_usage.json'
  $usageResultPath = Join-Path $usageOut 'variable_usage_report.json'
  Add-Check 'variable_usage' $(if ($usage.exit -eq 0) { 'pass' } else { 'fail' }) $usage.exit $usageResultPath $usage.detail
} else {
  Add-Check 'variable_usage' 'skipped' 0 '' 'plan has no scaffold_root'
}

$failed = @($checks | Where-Object { $_.status -eq 'fail' })
$report = [ordered]@{
  ok = ($failed.Count -eq 0)
  plan_path = $PlanPath
  checks = $checks.ToArray()
  failed_count = $failed.Count
  generated_at = (Get-Date).ToString('o')
}
$reportPath = Join-Path $OutDir 'plan_integrity_result.json'
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 4
Write-Host ("KV_PLAN_INTEGRITY: ok={0} checks={1} failed={2} report={3}" -f $report.ok, $checks.Count, $failed.Count, $reportPath)
if ($failed.Count -gt 0) { exit 41 }
exit 0
