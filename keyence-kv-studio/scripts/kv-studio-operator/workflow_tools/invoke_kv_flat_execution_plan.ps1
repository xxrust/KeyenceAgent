param(
  [Parameter(Mandatory=$true)]
  [string]$PlanPath,

  [int]$TimeoutSeconds = 0
)

$ErrorActionPreference = 'Stop'
$toolScriptDir = Split-Path -Parent $PSCommandPath
$resolver = Join-Path (Split-Path -Parent $toolScriptDir) 'Resolve-KvStudioOperatorScript.ps1'
if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) { throw "Script resolver not found: $resolver" }
. $resolver
$scriptRoot = Get-KvStudioOperatorScriptsRoot -StartPath $PSCommandPath
$start = Get-Date
$script:currentStep = 'init'
$script:lastFailure = $null
$script:flatSteps = [System.Collections.Generic.List[object]]::new()

function New-Cn([int[]]$CodePoints) {
  -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Get-ElapsedSeconds {
  [math]::Round(((Get-Date) - $start).TotalSeconds, 3)
}

function Assert-TimeBudget([string]$Stage) {
  $elapsed = ((Get-Date) - $start).TotalSeconds
  if ($elapsed -gt $TimeoutSeconds) {
    throw "KV flat workflow time budget exceeded at ${Stage}: $([math]::Round($elapsed, 3))s > ${TimeoutSeconds}s"
  }
}

function Get-ArgumentValue([object[]]$Arguments, [string]$Name) {
  for ($i = 0; $i -lt $Arguments.Count; $i++) {
    if ([string]$Arguments[$i] -eq $Name -and ($i + 1) -lt $Arguments.Count) { return [string]$Arguments[$i + 1] }
  }
  return ''
}

function Read-JsonFileIfPossible([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try { return (Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-StepResultFile([string]$OutDir) {
  if (-not $OutDir -or -not (Test-Path -LiteralPath $OutDir -PathType Container)) { return $null }
  Get-ChildItem -LiteralPath $OutDir -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '*result.json' -or $_.Name -like '*gate.json' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Clear-StaleStepArtifacts([string]$OutDir) {
  if (-not $OutDir) { return }
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  foreach ($name in @('fail.txt','exit_code.txt','timeout_result.json','runner_child_stdout.txt','runner_child_stderr.txt','step_stdout.txt','step_stderr.txt')) {
    $path = Join-Path $OutDir $name
    if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path -Force }
  }
}

function Get-StepFailureSummary([object]$Step, [int]$ExitCode) {
  $outDir = [string]$Step.out_dir
  $summary = [ordered]@{
    step = [string]$Step.name
    exit_code = $ExitCode
    out_dir = $outDir
    error_code = ''
    child_result_path = ''
    checkpoint_path = ''
    fail_text_path = ''
    evidence = @()
    message = ''
  }
  if (-not $outDir -or -not (Test-Path -LiteralPath $outDir -PathType Container)) { return [pscustomobject]$summary }
  $resultFile = Get-StepResultFile $outDir
  if ($resultFile) {
    $summary.child_result_path = $resultFile.FullName
    $summary.evidence += $resultFile.FullName
    $child = Read-JsonFileIfPossible $resultFile.FullName
    if ($child) {
      if ($child.error_code) { $summary.error_code = [string]$child.error_code }
      if ($child.current_step) { $summary.child_current_step = [string]$child.current_step }
      if ($child.message) { $summary.message = [string]$child.message }
      if ($child.evidence) { $summary.evidence += @($child.evidence | ForEach-Object { [string]$_ }) }
    }
  }
  $checkpoint = Get-ChildItem -LiteralPath $outDir -File -Filter '*failed.json' -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($checkpoint) {
    $summary.checkpoint_path = $checkpoint.FullName
    $summary.evidence += $checkpoint.FullName
  }
  $failText = Join-Path $outDir 'fail.txt'
  if (Test-Path -LiteralPath $failText -PathType Leaf) {
    $summary.fail_text_path = $failText
    $summary.evidence += $failText
    if (-not $summary.message) {
      try { $summary.message = ([IO.File]::ReadAllText($failText, [Text.Encoding]::UTF8)).Trim() } catch {}
    }
  }
  foreach ($stderrPath in @((Join-Path $outDir 'runner_child_stderr.txt'), (Join-Path $outDir 'step_stderr.txt'))) {
    if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
      $stderrItem = Get-Item -LiteralPath $stderrPath
      if ($stderrItem.Length -gt 0) {
        $summary.evidence += $stderrPath
        if (-not $summary.message) {
          try { $summary.message = ([IO.File]::ReadAllText($stderrPath, [Text.Encoding]::UTF8)).Trim() } catch {}
        }
      }
    }
  }
  if (-not $summary.error_code) { $summary.error_code = 'KV_FLAT_WORKFLOW_STEP_FAILED' }
  $summary.evidence = @($summary.evidence | Where-Object { $_ } | Select-Object -Unique)
  [pscustomobject]$summary
}

function Test-StepResultOk([string]$OutDir) {
  if (-not $OutDir -or -not (Test-Path -LiteralPath $OutDir -PathType Container)) { return $true }
  if (Test-Path -LiteralPath (Join-Path $OutDir 'fail.txt') -PathType Leaf) { return $false }
  $resultFile = Get-StepResultFile $OutDir
  if (-not $resultFile) { return $true }
  $child = Read-JsonFileIfPossible $resultFile.FullName
  if ($null -eq $child -or $null -eq $child.ok) { return $true }
  return ([bool]$child.ok)
}

function Stop-ProcessTree([int]$ProcessIdValue) {
  $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessIdValue" -ErrorAction SilentlyContinue)
  foreach ($child in $children) { Stop-ProcessTree ([int]$child.ProcessId) }
  $process = Get-Process -Id $ProcessIdValue -ErrorAction SilentlyContinue
  if ($process) { Stop-Process -Id $ProcessIdValue -Force -ErrorAction SilentlyContinue }
}

function Get-StepTimeoutSeconds([object]$Step) {
  $remaining = [math]::Max(1, [int]($TimeoutSeconds - ((Get-Date) - $start).TotalSeconds))
  $waitValue = Get-ArgumentValue @($Step.arguments) '-WaitSeconds'
  if ($waitValue -match '^\d+$') { return [math]::Min($remaining, ([int]$waitValue + 30)) }
  $explicit = [string]$Step.timeout_seconds
  if ($explicit -match '^\d+$') { return [math]::Min($remaining, [int]$explicit) }
  return $remaining
}

function Invoke-FlatWorkflowStep([object]$Step) {
  Assert-TimeBudget "before $($Step.name)"
  $script:currentStep = [string]$Step.name
  $classes = @($Step.classes | ForEach-Object { [string]$_ } | Where-Object { $_ })
  $scriptPath = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scriptRoot -Name ([string]$Step.script_name) -Classes $classes
  $outDir = [string]$Step.out_dir
  if ($outDir) { Clear-StaleStepArtifacts $outDir }
  $stdoutPath = if ($outDir) { Join-Path $outDir 'step_stdout.txt' } else { Join-Path ([IO.Path]::GetTempPath()) "$($Step.name)_stdout.txt" }
  $stderrPath = if ($outDir) { Join-Path $outDir 'step_stderr.txt' } else { Join-Path ([IO.Path]::GetTempPath()) "$($Step.name)_stderr.txt" }
  $arguments = @($Step.arguments | ForEach-Object { [string]$_ })
  $command = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) + $arguments
  $stepStart = Get-Date
  $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $command -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
  $stepTimeoutSeconds = Get-StepTimeoutSeconds $Step
  $deadline = (Get-Date).AddSeconds($stepTimeoutSeconds)
  $timedOut = $false
  while (-not $process.HasExited) {
    Start-Sleep -Milliseconds 250
    if ((Get-Date) -ge $deadline) {
      $timedOut = $true
      Stop-ProcessTree $process.Id
      break
    }
  }
  if ($timedOut) {
    $elapsed = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 3)
    if ($outDir) {
      [ordered]@{
        ok = $false
        error_code = 'KV_FLAT_WORKFLOW_STEP_TIMEOUT'
        step = [string]$Step.name
        script = $scriptPath
        elapsed_seconds = $elapsed
        step_timeout_seconds = $stepTimeoutSeconds
        stdout_path = $stdoutPath
        stderr_path = $stderrPath
        message = "Flat workflow child step timed out and its process tree was terminated: $($Step.name)"
      } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $outDir 'timeout_result.json') -Encoding UTF8
      "Flat workflow child step timed out: $($Step.name)" | Set-Content -LiteralPath (Join-Path $outDir 'fail.txt') -Encoding UTF8
    }
    $script:flatSteps.Add([pscustomobject]@{
      name = [string]$Step.name
      script = $scriptPath
      exit_code = -2
      elapsed_seconds = $elapsed
      timeout = $true
      step_timeout_seconds = $stepTimeoutSeconds
      stdout_path = $stdoutPath
      stderr_path = $stderrPath
      out_dir = $outDir
    })
    $script:lastFailure = Get-StepFailureSummary $Step -2
    $script:lastFailure.error_code = 'KV_FLAT_WORKFLOW_STEP_TIMEOUT'
    throw "Flat workflow step timed out: $($Step.name)"
  }
  $process.WaitForExit()
  $exit = [int]$process.ExitCode
  $childExitCodePath = if ($outDir) { Join-Path $outDir 'exit_code.txt' } else { '' }
  if ($childExitCodePath -and (Test-Path -LiteralPath $childExitCodePath -PathType Leaf)) {
    $childExitCodeText = ([IO.File]::ReadAllText($childExitCodePath, [Text.Encoding]::ASCII)).Trim()
    if ($childExitCodeText -match '^-?\d+$') { $exit = [int]$childExitCodeText }
  }
  if ($exit -eq 0 -and -not (Test-StepResultOk $outDir)) { $exit = 1 }
  if ($exit -eq 0 -and (Test-Path -LiteralPath $stderrPath -PathType Leaf) -and (Get-Item -LiteralPath $stderrPath).Length -gt 0) {
    $exit = 1
    if ($outDir) { 'Child step wrote to stderr; treating this as a failed guarded step.' | Set-Content -LiteralPath (Join-Path $outDir 'fail.txt') -Encoding UTF8 }
  }
  $elapsed = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 3)
  $script:flatSteps.Add([pscustomobject]@{
    name = [string]$Step.name
    kind = [string]$Step.kind
    script = $scriptPath
    exit_code = $exit
    elapsed_seconds = $elapsed
    stdout_path = $stdoutPath
    stderr_path = $stderrPath
    out_dir = $outDir
  })
  if ($exit -ne 0) {
    $script:lastFailure = Get-StepFailureSummary $Step $exit
    throw "Flat workflow step failed: $($Step.name) exit_code=$exit"
  }
  Assert-TimeBudget "after $($Step.name)"
}

function Write-FlatWorkflowResult([object]$Plan, [string]$ResolvedPlanPath, [bool]$Ok, [string]$Status, [string]$Message = '') {
  $compileResultPath = [string]$Plan.compile_result_path
  $compileText = ''
  if (Test-Path -LiteralPath $compileResultPath -PathType Leaf) {
    $compileText = [IO.File]::ReadAllText($compileResultPath, [Text.Encoding]::UTF8)
  }
  $okNeedle = (New-Cn @(0x8F6C,0x6362,0x7ED3,0x679C)) + ' OK'
  $ngNeedle = (New-Cn @(0x8F6C,0x6362,0x7ED3,0x679C)) + ' NG'
  $agentBoundaryPath = Join-Path (Join-Path ([string]$Plan.artifact_root) 'agent_boundary') 'agent_boundary_contract.json'
  if (-not (Test-Path -LiteralPath $agentBoundaryPath -PathType Leaf)) { $agentBoundaryPath = '' }
  [ordered]@{
    ok = $Ok
    status = $Status
    message = $Message
    elapsed_seconds = Get-ElapsedSeconds
    timeout_seconds = $TimeoutSeconds
    current_step = $script:currentStep
    operation = [string]$Plan.operation
    scaffold_root = [string]$Plan.scaffold_root
    scaffold_manifest = [string]$Plan.scaffold_manifest
    project_name = [string]$Plan.project_name
    cpu_model = [string]$Plan.cpu_model
    project_path = [string]$Plan.project_path
    checklist_path = [string]$Plan.checklist_path
    source_snapshot_manifest = [string]$Plan.source_snapshot_manifest
    delete_existing_modules_before_import = [bool]$Plan.delete_existing_modules_before_import
    execution_plan_path = $ResolvedPlanPath
    workflow_execution_mode = 'flat_manifest_steps'
    workflow_executor = 'workflow_tools/invoke_kv_flat_execution_plan.ps1'
    agent_boundary_contract_path = $agentBoundaryPath
    mnm_files = @($Plan.mnm_files)
    merged_global_variables_tsv = [string]$Plan.merged_global_variables_tsv
    variable_sets = @($Plan.variable_sets)
    compile_result_path = $compileResultPath
    compile_result_contains_ok = ($compileText.Contains($okNeedle))
    compile_result_contains_ng = ($compileText.Contains($ngNeedle))
    compile_result_length = $compileText.Length
    error_code = if ($script:lastFailure -and $script:lastFailure.error_code) { [string]$script:lastFailure.error_code } elseif (-not $Ok) { 'KV_FLAT_WORKFLOW_FAILED' } else { '' }
    failure = $script:lastFailure
    steps = @($script:flatSteps)
  } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath ([string]$Plan.result_path) -Encoding UTF8
}

$PlanPath = [IO.Path]::GetFullPath($PlanPath)
if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw "Execution plan not found: $PlanPath" }

$plan = $null
try {
  $plan = Get-Content -Raw -LiteralPath $PlanPath -Encoding UTF8 | ConvertFrom-Json
  if (-not $plan.ok) { throw "Execution plan is not ok: $PlanPath" }
  if ($TimeoutSeconds -le 0) {
    if ($plan.timeout_seconds) { $TimeoutSeconds = [int]$plan.timeout_seconds } else { $TimeoutSeconds = 600 }
  }

  foreach ($step in @($plan.steps)) {
    Invoke-FlatWorkflowStep $step
  }

  $compileResultPath = [string]$plan.compile_result_path
  if (-not (Test-Path -LiteralPath $compileResultPath -PathType Leaf)) {
    throw "Copied compile result file is missing: $compileResultPath"
  }
  $copyText = [IO.File]::ReadAllText($compileResultPath, [Text.Encoding]::UTF8)
  $okNeedle = (New-Cn @(0x8F6C,0x6362,0x7ED3,0x679C)) + ' OK'
  if (-not $copyText.Contains($okNeedle)) {
    throw 'Copied compile result does not contain the OK conversion result.'
  }
  Write-FlatWorkflowResult $plan $PlanPath $true 'pass' ''
  exit 0
} catch {
  if ($plan -and $plan.result_path) {
    Write-FlatWorkflowResult $plan $PlanPath $false 'fail' $_.Exception.ToString()
  }
  exit 1
}
