param([string]$WorkRoot = '')

$ErrorActionPreference = 'Stop'

# Offline regression for run_kv_execution_plan.ps1 (-DryRun).
# Proves the plan parser, stage ordering, argument reconstruction and result
# schema without touching KV STUDIO.

$tool = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\scripts\workflow_tools\run_kv_execution_plan.ps1'))
if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "tool not found: $tool" }

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-plan-runner-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$projectPath = Join-Path $WorkRoot 'Fixture.kpr'
[IO.File]::WriteAllText($projectPath, 'fixture', (New-Object Text.UTF8Encoding($false)))

$planPath = Join-Path $WorkRoot 'execution_plan.json'
[ordered]@{
  plan_id = 'plan-runner-fixture'
  steps = @(
    [ordered]@{ name = 'import_structures'; arguments = @('-StructuresTsv', 'unused.tsv') },
    [ordered]@{ name = 'import_mnm_1'; arguments = @('-ModuleName', 'ST01') },
    [ordered]@{ name = 'set_fb_arguments_1'; arguments = @('-ModuleName', 'FB_Cylinder') },
    [ordered]@{ name = 'set_variables_1'; arguments = @('-ModuleName', 'ST01') }
  )
} | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $planPath -Encoding UTF8

$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}

$runRoot = Join-Path $WorkRoot 'run_all'
& $tool -PlanPath $planPath -ProjectPath $projectPath -RunRoot $runRoot -DryRun | Out-Null
$exit = $LASTEXITCODE
$reportPath = Join-Path $runRoot 'plan_run_result.json'
Add-Case 'dry run exits 0' ($exit -eq 0) "exit=$exit"
Add-Case 'report written' (Test-Path -LiteralPath $reportPath) $reportPath
if (Test-Path -LiteralPath $reportPath) {
  $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
  Add-Case 'report ok true' ([bool]$report.ok) "ok=$($report.ok)"
  Add-Case 'dry_run flag true' ([bool]$report.dry_run) "dry=$($report.dry_run)"
  Add-Case 'four steps executed' ([int]$report.step_count -eq 4) "steps=$($report.step_count)"
  Add-Case 'no failures' ([int]$report.failures.Count -eq 0) "failures=$(@($report.failures).Count)"
  $names = @($report.results | ForEach-Object { [string]$_.name })
  Add-Case 'stage order structures/imports/fb/variables' ((($names -join ',') -eq 'import_structures,import_mnm_1,set_fb_arguments_1,set_variables_1')) ($names -join ',')
  $logPath = Join-Path $runRoot 'plan_run.log'
  $logText = if (Test-Path -LiteralPath $logPath) { Get-Content -LiteralPath $logPath -Raw -Encoding UTF8 } else { '' }
  Add-Case 'log records dry-run commands' (($logText -match 'import_mnm_guarded\.ps1') -and ($logText -match 'dry-run')) 'log'
}

$onlyVars = Join-Path $WorkRoot 'run_vars'
& $tool -PlanPath $planPath -ProjectPath $projectPath -RunRoot $onlyVars -Stages variables -DryRun | Out-Null
$varsExit = $LASTEXITCODE
$varsReport = Get-Content -LiteralPath (Join-Path $onlyVars 'plan_run_result.json') -Raw -Encoding UTF8 | ConvertFrom-Json
Add-Case 'stage filter variables exits 0' ($varsExit -eq 0) "exit=$varsExit"
Add-Case 'stage filter leaves one step' ([int]$varsReport.step_count -eq 1) "steps=$($varsReport.step_count)"

$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'plan-runner'; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0
