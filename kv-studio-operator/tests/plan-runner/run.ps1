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
    [ordered]@{ name = 'import_structures'; arguments = @('-PlanPath', 'unused-structures.json') },
    [ordered]@{ name = 'import_mnm_1'; arguments = @('-MnmPath', 'unused.mnm') },
    [ordered]@{ name = 'set_fb_arguments_1'; arguments = @('-FbModuleName', 'FB_Cylinder') },
    [ordered]@{ name = 'set_variables_1'; arguments = @('-LocalProgramName', 'ST01') }
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

# Main-only plan: no import_structures step must not be required.
$mainOnly = Join-Path $WorkRoot 'plan_main_only.json'
[ordered]@{
  plan_id = 'main-only'
  steps = @([ordered]@{ name = 'set_variables_main'; arguments = @('-LocalProgramName', 'Main') })
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $mainOnly -Encoding UTF8
$mainRoot = Join-Path $WorkRoot 'run_main_only'
& $tool -PlanPath $mainOnly -ProjectPath $projectPath -RunRoot $mainRoot -DryRun | Out-Null
$mainExit = $LASTEXITCODE
$mainReport = if (Test-Path (Join-Path $mainRoot 'plan_run_result.json')) { Get-Content -LiteralPath (Join-Path $mainRoot 'plan_run_result.json') -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
Add-Case 'main-only plan runs without import_structures' ($mainExit -eq 0 -and $mainReport -and [int]$mainReport.step_count -eq 1) "exit=$mainExit"

# Unknown step names are rejected instead of silently skipped.
$unknown = Join-Path $WorkRoot 'plan_unknown.json'
[ordered]@{ plan_id = 'unknown'; steps = @([ordered]@{ name = 'frobnicate_widget'; arguments = @() }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $unknown -Encoding UTF8
$unknownExit = 0
try { & $tool -PlanPath $unknown -ProjectPath $projectPath -RunRoot (Join-Path $WorkRoot 'run_unknown') -DryRun | Out-Null } catch { $unknownExit = 1 }
Add-Case 'unknown step rejected' ($unknownExit -ne 0) "exit=$unknownExit"

# Plan arguments the runner does not declare are rejected before execution.
$badArg = Join-Path $WorkRoot 'plan_bad_arg.json'
[ordered]@{ plan_id = 'bad-arg'; steps = @([ordered]@{ name = 'import_mnm_1'; arguments = @('-NoSuchParameter', 'x') }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $badArg -Encoding UTF8
$badArgExit = 0
try { & $tool -PlanPath $badArg -ProjectPath $projectPath -RunRoot (Join-Path $WorkRoot 'run_bad_arg') -DryRun | Out-Null } catch { $badArgExit = 1 }
Add-Case 'undeclared runner argument rejected' ($badArgExit -ne 0) "exit=$badArgExit"

# repair_* steps map to the same runners as import_*/set_* steps.
$repair = Join-Path $WorkRoot 'plan_repair.json'
[ordered]@{ plan_id = 'repair'; steps = @([ordered]@{ name = 'repair_mnm_1'; arguments = @('-MnmPath', 'unused.mnm') }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $repair -Encoding UTF8
& $tool -PlanPath $repair -ProjectPath $projectPath -RunRoot (Join-Path $WorkRoot 'run_repair') -DryRun | Out-Null
$repairExit = $LASTEXITCODE
$repairReport = if (Test-Path (Join-Path $WorkRoot 'run_repair\plan_run_result.json')) { Get-Content -LiteralPath (Join-Path $WorkRoot 'run_repair\plan_run_result.json') -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
Add-Case 'repair_* step accepted' ($repairExit -eq 0 -and $repairReport -and [int]$repairReport.step_count -eq 1) "exit=$repairExit"

# CreatedProjectResultPath is only forwarded to runners that declare it.
$bindRoot = Join-Path $WorkRoot 'run_binding'
& $tool -PlanPath $planPath -ProjectPath $projectPath -RunRoot $bindRoot -DryRun -CreatedProjectResultPath 'C:\tmp\created.json' | Out-Null
$bindExit = $LASTEXITCODE
$bindLog = if (Test-Path (Join-Path $bindRoot 'plan_run.log')) { Get-Content -LiteralPath (Join-Path $bindRoot 'plan_run.log') -Raw -Encoding UTF8 } else { '' }
Add-Case 'CreatedProjectResultPath forwarded only to declaring runner' ($bindExit -eq 0 -and $bindLog -match 'import_mnm_guarded\.ps1.*CreatedProjectResultPath' -and $bindLog -match 'set_fb_arguments.*CreatedProjectResultPath skipped') "exit=$bindExit"

$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'plan-runner'; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0



