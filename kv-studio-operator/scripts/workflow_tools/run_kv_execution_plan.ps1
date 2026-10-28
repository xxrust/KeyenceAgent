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
# Runs a scaffold execution plan through the guarded runner children.
#
# The plan step name decides the runner and the stage:
#   import_structures / repair_structures          -> mutate_structure_definitions_guarded.ps1
#   import_mnm_* / repair_mnm_*                    -> import_mnm_guarded.ps1
#   set_fb_arguments_* / repair_fb_arguments_*     -> set_fb_arguments_guarded.ps1
#   set_variables_* / repair_variables_*           -> set_variables_guarded.ps1
# Unknown step names, unsupported plan schemas and runner parameters the plan
# does not declare are rejected before any runner starts.
#
# Safety contract (same as the flat executor):
#   - one shared desktop mutex: Local\KeyenceAgent.KvStudio.UI
#   - a step's exit_code.txt is only trusted when this run wrote it
#   - execution stops at the first failing step
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw "KV_PLAN_MISSING: $PlanPath" }
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "KV_PROJECT_MISSING: $ProjectPath" }
if (-not $RunRoot) { $RunRoot = Join-Path (Split-Path -Parent $PlanPath) ('run_' + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
if (-not $LogPath) { $LogPath = Join-Path $RunRoot 'plan_run.log' }
New-Item -ItemType Directory -Force -Path $RunRoot | Out-Null

$runnerRoot = Join-Path (Split-Path -Parent $PSScriptRoot) 'runner_children'
if (-not (Test-Path -LiteralPath $runnerRoot)) { throw "KV_RUNNER_ROOT_MISSING: $runnerRoot" }

$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($plan.PSObject.Properties.Name -contains 'schema_version') {
  $schema = [int]$plan.schema_version
  if ($schema -ne 1) { throw "KV_PLAN_SCHEMA_UNSUPPORTED: $schema" }
}
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

function Get-StepSpec([string]$name) {
  if ($name -match '^(import|repair)_structures$') {
    return [pscustomobject]@{ runner = 'mutate_structure_definitions_guarded.ps1'; stage = 'structures' }
  }
  if ($name -match '^(import|repair)_mnm_') {
    return [pscustomobject]@{ runner = 'import_mnm_guarded.ps1'; stage = 'imports' }
  }
  if ($name -match '^(set|repair)_fb_arguments_') {
    return [pscustomobject]@{ runner = 'set_fb_arguments_guarded.ps1'; stage = 'fb_arguments' }
  }
  if ($name -match '^(set|repair)_variables_') {
    return [pscustomobject]@{ runner = 'set_variables_guarded.ps1'; stage = 'variables' }
  }
  throw "KV_PLAN_STEP_UNSUPPORTED: $name"
}

function Get-RunnerParameterNames([string]$path) {
  $tokens = $null
  $errors = $null
  $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
  if ($errors.Count -gt 0) { throw "KV_RUNNER_PARSE_ERROR: $path" }
  if (-not $ast.ParamBlock) { return @() }
  @($ast.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath })
}

# Validate the whole plan up front, including steps filtered out by -Stages.
$manifestPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'script_manifest.json'
$manifestRunners = @{}
if (Test-Path -LiteralPath $manifestPath) {
  $manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($prop in @($manifest.classes.PSObject.Properties)) {
    foreach ($entry in @($prop.Value)) {
      $manifestRunners[([string]$entry.path).Replace('\', '/')] = [string]$prop.Name
    }
  }
}
$prepared = New-Object System.Collections.Generic.List[object]
foreach ($step in $steps) {
  $name = [string]$step.name
  if (-not $name) { throw 'KV_PLAN_STEP_NAME_MISSING' }
  $spec = Get-StepSpec $name
  $runnerPath = Join-Path $runnerRoot $spec.runner
  if (-not (Test-Path -LiteralPath $runnerPath -PathType Leaf)) { throw "KV_RUNNER_MISSING: $runnerPath" }
  $manifestKey = 'runner_children/' + $spec.runner
  if ($manifestRunners.Count -gt 0 -and -not $manifestRunners.ContainsKey($manifestKey)) {
    throw "KV_RUNNER_NOT_IN_MANIFEST: $manifestKey"
  }
  $declared = @(Get-RunnerParameterNames $runnerPath)
  $map = ConvertTo-Arguments $step.arguments
  foreach ($key in @($map.Keys)) {
    if ($declared -notcontains $key -and $key -notin @('ProjectPath', 'OutDir')) {
      throw "KV_PLAN_ARGUMENT_UNSUPPORTED: step=$name runner=$($spec.runner) argument=$key"
    }
  }
  $prepared.Add([pscustomobject]@{ name = $name; stage = $spec.stage; runner = $spec.runner; runner_path = $runnerPath; arguments = $map })
}

$selected = @($prepared | Where-Object { $Stages -contains $_.stage })
if ($selected.Count -eq 0) { throw 'KV_PLAN_STAGE_EMPTY: no plan step matches the requested stages' }
$reportResults = New-Object System.Collections.Generic.List[object]
$stopped = $false
$skipped = New-Object System.Collections.Generic.List[string]

function Write-StepLog([string]$name, [string]$text) {
  Add-Content -LiteralPath $LogPath -Value ("STEP {0} {1}" -f $name, $text) -Encoding UTF8
}

function Invoke-PreparedStep($step, [int]$timeoutSeconds) {
  $map = @{}
  foreach ($key in $step.arguments.Keys) { $map[$key] = $step.arguments[$key] }
  $map['ProjectPath'] = $ProjectPath
  if ($step.name -match '^(set|repair)_variables_' -and $GlobalVariablesTsv) {
    $map['GlobalVariablesTsv'] = $GlobalVariablesTsv
  }
  $declared = @(Get-RunnerParameterNames $step.runner_path)
  if ($CreatedProjectResultPath) {
    if ($declared -contains 'CreatedProjectResultPath') {
      $map['CreatedProjectResultPath'] = $CreatedProjectResultPath
    } else {
      Write-StepLog $step.name 'CreatedProjectResultPath skipped: runner does not declare it'
    }
  }
  if (-not $map.ContainsKey('OutDir')) { $map['OutDir'] = Join-Path $RunRoot $step.name }
  $outDir = [string]$map['OutDir']
  New-Item -ItemType Directory -Force -Path $outDir | Out-Null
  $exitCodeFile = Join-Path $outDir 'exit_code.txt'
  if (Test-Path -LiteralPath $exitCodeFile) { Remove-Item -LiteralPath $exitCodeFile -Force }
  $argumentList = @()
  foreach ($key in $map.Keys) {
    $value = $map[$key]
    if ($value -is [bool]) { if ($value) { $argumentList += "-$key" } }
    else { $argumentList += @("-$key", [string]$value) }
  }
  if ($DryRun) {
    Write-StepLog $step.name ("dry-run {0} {1}" -f $step.runner, ($argumentList -join ' '))
    return 0
  }
  $started = Get-Date
  $stdout = Join-Path $outDir 'step_stdout.txt'
  $stderr = Join-Path $outDir 'step_stderr.txt'
  $process = Start-Process -FilePath 'powershell' -ArgumentList (@('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $step.runner_path) + $argumentList) -RedirectStandardOutput $stdout -RedirectStandardError $stderr -PassThru -WindowStyle Hidden
  $finished = $process.WaitForExit($timeoutSeconds * 1000)
  if (-not $finished) {
    try { Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue } catch {}
    Write-StepLog $step.name 'timeout'
    return 124
  }
  $process.Refresh()
  $processCode = [int]$process.ExitCode
  $code = $processCode
  if (Test-Path -LiteralPath $exitCodeFile) {
    $fresh = (Get-Item -LiteralPath $exitCodeFile).LastWriteTime -ge $started.AddSeconds(-2)
    if ($fresh) {
      $code = [int]((Get-Content -LiteralPath $exitCodeFile -Raw).Trim())
    } else {
      Write-StepLog $step.name 'stale exit_code.txt ignored'
    }
  }
  Write-StepLog $step.name ("exit={0} process_exit={1}" -f $code, $processCode)
  return $code
}

$mutex = $null
$mutexHeld = $false
if (-not $DryRun) {
  $mutex = New-Object System.Threading.Mutex($false, 'Local\KeyenceAgent.KvStudio.UI')
  if (-not $mutex.WaitOne(0)) { throw 'KV_UI_WORKFLOW_BUSY: another KV STUDIO workflow owns the desktop mutex' }
  $mutexHeld = $true
}
try {
  foreach ($step in $selected) {
    if ($stopped) { $skipped.Add($step.name); continue }
    $timeout = switch ($step.stage) { 'structures' { 1800 } 'imports' { 300 } 'fb_arguments' { 300 } default { 600 } }
    Write-StepLog $step.name ('start ' + (Get-Date -Format o))
    $code = Invoke-PreparedStep $step $timeout
    $reportResults.Add([pscustomobject]@{ stage = $step.stage; name = $step.name; runner = $step.runner; exit_code = $code })
    if ($code -ne 0) { $stopped = $true }
  }
} finally {
  if ($mutexHeld -and $mutex) {
    try { $mutex.ReleaseMutex() } catch {}
    $mutexHeld = $false
    try { $mutex.Dispose() } catch {}
  }
}

$failures = @($reportResults | Where-Object { $_.exit_code -ne 0 })
$report = [ordered]@{
  ok = ($failures.Count -eq 0)
  dry_run = [bool]$DryRun
  plan_path = $PlanPath
  project_path = $ProjectPath
  run_root = $RunRoot
  step_count = $selected.Count
  failures = @($failures | ForEach-Object { [pscustomobject]@{ name = $_.name; exit_code = $_.exit_code } })
  skipped_after_failure = @($skipped)
  results = $reportResults.ToArray()
  generated_at = (Get-Date).ToString('o')
}
$reportPath = Join-Path $RunRoot 'plan_run_result.json'
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host ("KV_PLAN_RUN: steps={0} failures={1} skipped={2} log={3}" -f $selected.Count, $failures.Count, $skipped.Count, $LogPath)
if ($failures.Count -gt 0) { exit 41 }
exit 0

