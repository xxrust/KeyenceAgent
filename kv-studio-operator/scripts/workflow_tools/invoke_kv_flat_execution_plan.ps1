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
. (Join-Path $toolScriptDir 'kv_step_evidence.ps1')
$scriptRoot = Get-KvStudioOperatorScriptsRoot -StartPath $PSCommandPath
$start = Get-Date
$script:currentStep = 'init'
$script:lastFailure = $null
$script:flatSteps = [System.Collections.Generic.List[object]]::new()
$script:unifiedRunLog = ''
$script:runId = [guid]::NewGuid().ToString('N')
$script:preparedSteps = @{}
$script:codeFingerprint = $null
$script:uiMutex = $null
$script:uiMutexHeld = $false

function Write-WorkflowLog([string]$Type, [hashtable]$Data = @{}) {
  if (-not $script:unifiedRunLog) { return }
  $entry = [ordered]@{timestamp=(Get-Date).ToString('o');run_id=$script:runId;type=$Type;step=$script:currentStep}
  foreach ($key in $Data.Keys) { $entry[$key]=$Data[$key] }
  [IO.File]::AppendAllText($script:unifiedRunLog,(($entry | ConvertTo-Json -Compress -Depth 8)+[Environment]::NewLine),[Text.Encoding]::UTF8)
}

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
  $prepared = $script:preparedSteps[[string]$Step.name]
  $resultFile = if ($prepared) { Get-Item -LiteralPath (Join-Path $outDir $prepared.contract.files[0]) -ErrorAction SilentlyContinue } else { $null }
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
  $prepared = $script:preparedSteps[[string]$Step.name]
  $scriptPath = $prepared.path
  $outDir = [string]$Step.out_dir
  Move-KvPreviousStepEvidence $outDir $prepared.contract $script:runId
  $stdoutPath = if ($outDir) { Join-Path $outDir 'step_stdout.txt' } else { Join-Path ([IO.Path]::GetTempPath()) "$($Step.name)_stdout.txt" }
  $stderrPath = if ($outDir) { Join-Path $outDir 'step_stderr.txt' } else { Join-Path ([IO.Path]::GetTempPath()) "$($Step.name)_stderr.txt" }
  $arguments = @($Step.arguments | ForEach-Object { [string]$_ })
  # KV STUDIO's WinForms grids, clipboard and SendKeys paths require an STA
  # apartment.  Running every flat child in STA keeps the UI runner children
  # on the same execution contract as the published workflow/harness entry
  # points; non-UI gates remain compatible with STA.
  $command = @('-STA', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) + $arguments
  $commandLine = ($command | ForEach-Object { ConvertTo-KvProcessArgument ([string]$_) }) -join ' '
  if ($Step.parameters) {
    # Typed JSON avoids flattening arrays or booleans into command-line strings.
    $requestPath = Join-Path $outDir 'step_request.json'
    @{script_path=$scriptPath;parameters=$Step.parameters} | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $requestPath -Encoding UTF8
    $requestLiteral = "'" + $requestPath.Replace("'","''") + "'"
    $invoke = '$ErrorActionPreference="Stop"; $ProgressPreference="SilentlyContinue"; try { $r=Get-Content -LiteralPath ' + $requestLiteral + ' -Raw -Encoding UTF8 | ConvertFrom-Json; $p=@{}; foreach($v in $r.parameters.PSObject.Properties){$p[$v.Name]=$v.Value}; & $r.script_path @p; if(-not $?){exit 1}; exit 0 } catch { [Console]::Error.WriteLine($_.Exception.ToString()); exit 1 }'
    $commandLine = '-STA -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($invoke))
    $arguments=@($Step.parameters.PSObject.Properties | ForEach-Object { $_.Value })
  }
  $inputs = @(Get-KvInputFingerprints $arguments)
  $stepStart = Get-Date
  Write-WorkflowLog 'step_started' @{script=$scriptPath;out_dir=$outDir;input_fingerprints=$inputs;expected_results=$prepared.contract.files;code_sha256=$script:codeFingerprint.sha256}
  $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $commandLine -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
  # Cache the handle before polling: .NET can otherwise lose ExitCode when the
  # process exits before WaitForExit on Windows PowerShell.
  $null = $process.Handle
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
    Write-WorkflowLog 'step_failed' @{error_code='KV_FLAT_WORKFLOW_STEP_TIMEOUT';elapsed_seconds=$elapsed}
    throw "Flat workflow step timed out: $($Step.name)"
  }
  $process.WaitForExit()
  if ($null -eq $process.ExitCode) { throw 'KV_CHILD_EXIT_CODE_UNAVAILABLE' }
  $exit = [int]$process.ExitCode
  $childExitCodePath = if ($outDir) { Join-Path $outDir 'exit_code.txt' } else { '' }
  if ($childExitCodePath -and (Test-Path -LiteralPath $childExitCodePath -PathType Leaf)) {
    $childExitCodeText = ([IO.File]::ReadAllText($childExitCodePath, [Text.Encoding]::ASCII)).Trim()
    if ($exit -eq 0 -and $childExitCodeText -match '^-?\d+$' -and [int]$childExitCodeText -ne 0) { $exit = [int]$childExitCodeText }
  }
  $evidence = @()
  $evidenceError = ''
  if ($exit -eq 0) {
    try { $evidence = @(Test-KvStepEvidence $outDir $prepared.contract $stepStart.ToUniversalTime()) }
    catch { $exit=1; $evidenceError=$_.Exception.Message }
  }
  if ($exit -eq 0 -and (Test-Path -LiteralPath $stderrPath -PathType Leaf) -and (Get-Item -LiteralPath $stderrPath).Length -gt 0) {
    $exit = 1
    if ($outDir) { 'Child step wrote to stderr; treating this as a failed guarded step.' | Set-Content -LiteralPath (Join-Path $outDir 'fail.txt') -Encoding UTF8 }
  }
  $elapsed = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 3)
  [ordered]@{
    run_id=$script:runId;step=$Step.name;ok=($exit -eq 0);exit_code=$exit;started_utc=$stepStart.ToUniversalTime().ToString('o')
    script=$scriptPath;arguments=$arguments;parameters=$Step.parameters;inputs=$inputs;code_sha256=$script:codeFingerprint.sha256
    artifacts=$evidence;evidence_error=$evidenceError;elapsed_seconds=$elapsed
  } | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $outDir 'step_receipt.json') -Encoding UTF8
  Write-WorkflowLog $(if ($exit -eq 0) {'step_succeeded'} else {'step_failed'}) @{exit_code=$exit;elapsed_seconds=$elapsed;out_dir=$outDir}
  $script:flatSteps.Add([pscustomobject]@{
    name = [string]$Step.name
    kind = [string]$Step.kind
    script = $scriptPath
    exit_code = $exit
    elapsed_seconds = $elapsed
    stdout_path = $stdoutPath
    stderr_path = $stderrPath
    out_dir = $outDir
    receipt_path = Join-Path $outDir 'step_receipt.json'
    artifacts = $evidence
  })
  if ($exit -ne 0) {
    $script:lastFailure = Get-StepFailureSummary $Step $exit
    if ($evidenceError) {
      $script:lastFailure.message=$evidenceError
      $script:lastFailure.error_code=($evidenceError -split ':',2)[0]
    }
    throw "Flat workflow step failed: $($Step.name) exit_code=$exit"
  }
  Assert-TimeBudget "after $($Step.name)"
}

function Write-FlatWorkflowResult([object]$Plan, [string]$ResolvedPlanPath, [bool]$Ok, [string]$Status, [string]$Message = '') {
  $compileResultPath = [string]$Plan.compile_result_path
  $compileAcceptanceRequired = $true
  if ($null -ne $Plan.require_compile_result) { $compileAcceptanceRequired = [bool]$Plan.require_compile_result }
  $compileText = ''
  if ($compileResultPath -and (Test-Path -LiteralPath $compileResultPath -PathType Leaf)) {
    $compileText = [IO.File]::ReadAllText($compileResultPath, [Text.Encoding]::UTF8)
  }
  $okNeedle = (New-Cn @(0x8F6C,0x6362,0x7ED3,0x679C)) + ' OK'
  $ngNeedle = (New-Cn @(0x8F6C,0x6362,0x7ED3,0x679C)) + ' NG'
  $agentBoundaryPath = Join-Path (Join-Path ([string]$Plan.artifact_root) 'agent_boundary') 'agent_boundary_contract.json'
  if (-not (Test-Path -LiteralPath $agentBoundaryPath -PathType Leaf)) { $agentBoundaryPath = '' }
  [ordered]@{
    ok = $Ok
    run_id = $script:runId
    code_fingerprint_path = Join-Path ([string]$Plan.run_root) 'code_fingerprint.json'
    code_sha256 = if ($script:codeFingerprint) { $script:codeFingerprint.sha256 } else { '' }
    execution_plan_sha256 = (Get-FileHash -LiteralPath $ResolvedPlanPath -Algorithm SHA256).Hash
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
    compile_acceptance_required = $compileAcceptanceRequired
    compile_result_contains_ok = ($compileText.Contains($okNeedle))
    compile_result_contains_ng = ($compileText.Contains($ngNeedle))
    compile_result_length = $compileText.Length
    error_code = if ($script:lastFailure -and $script:lastFailure.error_code) { [string]$script:lastFailure.error_code } elseif (-not $Ok) { 'KV_FLAT_WORKFLOW_FAILED' } else { '' }
    failure = $script:lastFailure
    steps = @($script:flatSteps)
    run_log_path = $script:unifiedRunLog
  } | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath ([string]$Plan.result_path) -Encoding UTF8
}

$PlanPath = [IO.Path]::GetFullPath($PlanPath)
if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw "Execution plan not found: $PlanPath" }

$plan = $null
try {
  $plan = Get-Content -Raw -LiteralPath $PlanPath -Encoding UTF8 | ConvertFrom-Json
  if ($plan.ok -isnot [bool] -or -not $plan.ok) { throw "Execution plan is not ok: $PlanPath" }
  if (-not $plan.run_root) { throw 'KV_PLAN_RUN_ROOT_REQUIRED' }
  New-Item -ItemType Directory -Force -Path ([string]$plan.run_root) | Out-Null
  $script:unifiedRunLog = Join-Path ([string]$plan.run_root) 'run.log'
  $env:KV_WORKFLOW_RUN_LOG = $script:unifiedRunLog
  $env:KV_WORKFLOW_RUN_ID = $script:runId
  Write-WorkflowLog 'workflow_started' @{plan_path=$PlanPath;project_path=$plan.project_path}
  # KV STUDIO is a single interactive desktop resource.  Serialize every
  # flat workflow process before any runner child can touch the UI.  A named
  # mutex is process-wide, so concurrent agents fail immediately instead of
  # interleaving focus and clipboard operations.
  $script:uiMutex = New-Object System.Threading.Mutex($false, 'Local\KeyenceAgent.KvStudio.UI')
  if (-not $script:uiMutex.WaitOne(0)) {
    Write-WorkflowLog 'workflow_rejected' @{error_code='KV_UI_WORKFLOW_BUSY';message='Another KV STUDIO workflow currently owns the desktop mutex.'}
    throw 'KV_UI_WORKFLOW_BUSY: another KV STUDIO workflow is already running.'
  }
  $script:uiMutexHeld = $true
  Write-WorkflowLog 'ui_mutex_acquired' @{mutex='Local\\KeyenceAgent.KvStudio.UI'}
  if ($TimeoutSeconds -le 0) {
    if ($plan.timeout_seconds) { $TimeoutSeconds = [int]$plan.timeout_seconds } else { $TimeoutSeconds = 600 }
  }

  $manifest = Get-KvStudioOperatorScriptManifest -ScriptRoot $scriptRoot
  $allowedClasses = @('runner_child_approved','workflow_tool','gate','customer_scaffold_tool','customer_non_ui_tool')
  $outputPaths = @{}
  foreach ($step in @($plan.steps)) {
    if (-not $step.name -or $script:preparedSteps.ContainsKey([string]$step.name)) { throw 'KV_PLAN_STEP_NAME_INVALID' }
    $classes = @($step.classes | Where-Object { $_ -in $allowedClasses })
    if ($classes.Count -eq 0 -or $classes.Count -ne @($step.classes).Count) { throw "KV_PLAN_STEP_CLASS_INVALID: $($step.name)" }
    $path = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scriptRoot -Name ([string]$step.script_name) -Classes $classes
    if (-not $step.out_dir) { throw "KV_PLAN_STEP_OUT_DIR_REQUIRED: $($step.name)" }
    $step.out_dir = [IO.Path]::GetFullPath([string]$step.out_dir)
    if ($outputPaths.ContainsKey($step.out_dir)) { throw "KV_PLAN_STEP_OUT_DIR_DUPLICATE: $($step.out_dir)" }
    $outputPaths[$step.out_dir]=$true
    $relative = $path.Substring($scriptRoot.TrimEnd('\','/').Length+1).Replace('\','/')
    if ($step.parameters -and $step.arguments) { throw "KV_PLAN_STEP_ARGUMENTS_AMBIGUOUS: $($step.name)" }
    $contractArguments=@($step.arguments)
    if ($step.parameters) { $contractArguments=@($step.parameters.PSObject.Properties | Where-Object { $_.Value -eq $true } | ForEach-Object { '-'+$_.Name }) }
    $contract = Get-KvStepContract $manifest $relative $contractArguments
    $script:preparedSteps[[string]$step.name]=@{path=$path;contract=$contract}
  }
  if ($script:preparedSteps.Count -eq 0) { throw 'KV_PLAN_STEPS_REQUIRED' }
  $script:codeFingerprint = Get-KvCodeFingerprint $scriptRoot
  $script:codeFingerprint | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path ([string]$plan.run_root) 'code_fingerprint.json') -Encoding UTF8
  Write-WorkflowLog 'plan_validated' @{step_count=$script:preparedSteps.Count;code_sha256=$script:codeFingerprint.sha256}
  $env:KV_WORKFLOW_VALIDATED_PLAN=$PlanPath
  $env:KV_WORKFLOW_PLAN_SHA256=(Get-FileHash -LiteralPath $PlanPath -Algorithm SHA256).Hash
  foreach ($step in @($plan.steps)) {
    Invoke-FlatWorkflowStep $step
  }

  $compileAcceptanceRequired = $true
  if ($null -ne $plan.require_compile_result) { $compileAcceptanceRequired = [bool]$plan.require_compile_result }
  if ($compileAcceptanceRequired) {
    $compileResultPath = [string]$plan.compile_result_path
    if (-not (Test-Path -LiteralPath $compileResultPath -PathType Leaf)) {
      throw "Copied compile result file is missing: $compileResultPath"
    }
    $copyText = [IO.File]::ReadAllText($compileResultPath, [Text.Encoding]::UTF8)
    $okNeedle = (New-Cn @(0x8F6C,0x6362,0x7ED3,0x679C)) + ' OK'
    $ngNeedle = (New-Cn @(0x8F6C,0x6362,0x7ED3,0x679C)) + ' NG'
    $compileEvidence = @($script:flatSteps | ForEach-Object { $_.artifacts } | Where-Object { $_.path -eq $compileResultPath })
    if ($compileEvidence.Count -ne 1 -or (Get-FileHash -LiteralPath $compileResultPath -Algorithm SHA256).Hash -ne $compileEvidence[0].sha256) { throw 'KV_COMPILE_RESULT_NOT_FROM_CURRENT_RUN' }
    if (-not $copyText.Contains($okNeedle) -or $copyText.Contains($ngNeedle)) {
      throw 'Copied compile result does not contain the OK conversion result.'
    }
  }
  Write-FlatWorkflowResult $plan $PlanPath $true 'pass' ''
  Write-WorkflowLog 'workflow_succeeded' @{result_path=$plan.result_path;elapsed_seconds=(Get-ElapsedSeconds)}
  exit 0
} catch {
  Write-WorkflowLog 'workflow_failed' @{message=$_.Exception.Message;elapsed_seconds=(Get-ElapsedSeconds)}
  if ($plan -and $plan.result_path) {
    Write-FlatWorkflowResult $plan $PlanPath $false 'fail' $_.Exception.ToString()
  }
  exit 1
} finally {
  if ($script:uiMutexHeld -and $script:uiMutex) {
    try { $script:uiMutex.ReleaseMutex() } catch {}
    $script:uiMutexHeld = $false
    try { $script:uiMutex.Dispose() } catch {}
  }
}
