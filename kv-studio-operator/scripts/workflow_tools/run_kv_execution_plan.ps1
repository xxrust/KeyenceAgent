param(
  [Parameter(Mandatory=$true)][string]$PlanPath,
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [string]$RunRoot = '',
  [string]$GlobalVariablesTsv = '',
  [string]$CreatedProjectResultPath = '',
  [string]$LogPath = '',
  [string[]]$Stages = @('structures', 'imports', 'fb_arguments', 'variables'),
  [switch]$DryRun
)
# Runs the scaffold execution plan (structures -> MNM imports -> FB arguments ->
# module variables) through the guarded runner children. Each step is executed
# with its plan arguments, a per-step OutDir and exit_code.txt handling.
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw "KV_PLAN_MISSING: $PlanPath" }
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "KV_PROJECT_MISSING: $ProjectPath" }
if (-not $RunRoot) { $RunRoot = Join-Path (Split-Path -Parent $PlanPath) ('run_' + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
if (-not $LogPath) { $LogPath = Join-Path $RunRoot 'plan_run.log' }
New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

$runnerRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'runner_children'
if (-not (Test-Path -LiteralPath $runnerRoot)) { throw "KV_RUNNER_ROOT_MISSING: $runnerRoot" }

$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
$steps = @($plan.steps)
if ($steps.Count -eq 0) { throw 'KV_PLAN_EMPTY' }

function ConvertTo-Arguments([object]$arguments) {
  $map = @{}
  $list = @($arguments)
  for ($k = 0; $k -lt $list.Count; $k++) {
    $token = [string]$list[$k]
    if (-not $token.StartsWith('-')) { continue }
    $name = $token.TrimStart('-')
    if (($k + 1) -lt $list.Count -and -not ([string]$list[$k + 1]).StartsWith('-')) {
      $map[$name] = [string]$list[$k + 1]
      $k++
    } else {
      $map[$name] = $true
    }
  }
  return $map
}
function Invoke-PlanStep([string]$stepName, [string]$runner, [hashtable]$overrides, [int]$timeoutSeconds) {
  $step = @($steps | Where-Object { $_.name -eq $stepName })[0]
  if (-not $step) { throw "KV_PLAN_STEP_NOT_FOUND: $stepName" }
  $map = ConvertTo-Arguments $step.arguments
  foreach ($key in $overrides.Keys) { $map[$key] = $overrides[$key] }
  $map['ProjectPath'] = $ProjectPath
  $map.Remove('CreatedProjectResultPath')
  if ($CreatedProjectResultPath -and ($runner -in @('import_mnm_guarded.ps1', 'set_variables_guarded.ps1', 'set_fb_arguments_guarded.ps1'))) {
    $map['CreatedProjectResultPath'] = $CreatedProjectResultPath
  }
  if (-not $map.ContainsKey('OutDir')) { $map['OutDir'] = Join-Path $RunRoot $stepName }
  $outDir = [string]$map['OutDir']
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $argumentList = @()
  foreach ($key in $map.Keys) {
    $value = $map[$key]
    if ($value -is [bool]) { if ($value) { $argumentList += "-$key" } }
    else { $argumentList += @("-$key", [string]$value) }
  }
  $runnerPath = Join-Path $runnerRoot $runner
  if (-not (Test-Path -LiteralPath $runnerPath)) { throw "KV_RUNNER_MISSING: $runnerPath" }
  Add-Content -LiteralPath $LogPath -Value ("STEP {0} start {1}" -f $stepName, (Get-Date -Format o)) -Encoding UTF8
  if ($DryRun) {
    Add-Content -LiteralPath $LogPath -Value ("STEP {0} dry-run {1} {2}" -f $stepName, $runner, ($argumentList -join ' ')) -Encoding UTF8
    return 0
  }
  $stdout = Join-Path $outDir 'step_stdout.txt'
  $stderr = Join-Path $outDir 'step_stderr.txt'
  $process = Start-Process -FilePath 'powershell' -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runnerPath) + $argumentList) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
  $finished = $process.WaitForExit($timeoutSeconds * 1000)
  if (-not $finished) {
    try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}
    Add-Content -LiteralPath $LogPath -Value ("STEP {0} timeout" -f $stepName) -Encoding UTF8
    return 124
  }
  $exitCodeFile = Join-Path $outDir 'exit_code.txt'
  $code = if (Test-Path $exitCodeFile) { [int]((Get-Content $exitCodeFile -Raw).Trim()) } else { $process.Refresh(); [int]$process.ExitCode }
  Add-Content -LiteralPath $LogPath -Value ("STEP {0} exit={1}" -f $stepName, $code) -Encoding UTF8
  return $code
}

$results = New-Object System.Collections.Generic.List[object]
$stageOrder = @('structures', 'imports', 'fb_arguments', 'variables')
foreach ($stage in $stageOrder) {
  if ($Stages -notcontains $stage) { continue }
  if ($stage -eq 'structures') {
    $results.Add([pscustomobject]@{ stage = $stage; name = 'import_structures'; exit_code = (Invoke-PlanStep 'import_structures' 'mutate_structure_definitions_guarded.ps1' @{} 1800) })
  }
  if ($stage -eq 'imports') {
    foreach ($name in @($steps | Where-Object { $_.name -like 'import_mnm_*' } | ForEach-Object { $_.name })) {
      $results.Add([pscustomobject]@{ stage = $stage; name = $name; exit_code = (Invoke-PlanStep $name 'import_mnm_guarded.ps1' @{} 300) })
    }
  }
  if ($stage -eq 'fb_arguments') {
    foreach ($name in @($steps | Where-Object { $_.name -like 'set_fb_arguments_*' } | ForEach-Object { $_.name })) {
      $results.Add([pscustomobject]@{ stage = $stage; name = $name; exit_code = (Invoke-PlanStep $name 'set_fb_arguments_guarded.ps1' @{} 300) })
    }
  }
  if ($stage -eq 'variables') {
    foreach ($name in @($steps | Where-Object { $_.name -like 'set_variables_*' } | ForEach-Object { $_.name })) {
      $overrides = @{}
      if ($GlobalVariablesTsv) { $overrides['GlobalVariablesTsv'] = $GlobalVariablesTsv }
      if ($name -ne 'set_variables_FB_Cylinder') { $overrides['SkipGlobal'] = $true }
      $results.Add([pscustomobject]@{ stage = $stage; name = $name; exit_code = (Invoke-PlanStep $name 'set_variables_guarded.ps1' $overrides 600) })
    }
  }
}

$failures = @($results | Where-Object { $_.exit_code -ne 0 })
$report = [ordered]@{
  ok = ($failures.Count -eq 0)
  dry_run = [bool]$DryRun
  plan_path = $PlanPath
  project_path = $ProjectPath
  run_root = $RunRoot
  step_count = $results.Count
  failures = @($failures | ForEach-Object { [pscustomobject]@{ name = $_.name; exit_code = $_.exit_code } })
  results = $results.ToArray()
  generated_at = (Get-Date).ToString('o')
}
$reportPath = Join-Path $RunRoot 'plan_run_result.json'
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host ("KV_PLAN_RUN: steps={0} failures={1} log={2}" -f $results.Count, $failures.Count, $LogPath)
if ($failures.Count -gt 0) { exit 41 }
exit 0
