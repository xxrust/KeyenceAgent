param(
  [Parameter(Mandatory=$true)]
  [string]$ScaffoldRoot,

  [string]$OutRoot = 'C:\Users\Public\KVSkillPractice\mvp_repeat_runs',
  [string]$ProjectNamePrefix = '',
  [string]$KvsExe = '',
  [string]$ConfigPath = '',
  [string]$ChecklistPath = '',
  [int]$TimeoutSeconds = 600,
  [switch]$AuditVariablePersistence,
  [ValidateSet('Full','NameType')]
  [string]$LocalPasteFormat = 'NameType',
  [int]$RequiredConsecutivePasses = 3,
  [int]$MaxAttempts = 6,
  [int]$StopAfterSameFailureCount = 3
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSCommandPath
$runner = Join-Path $scriptRoot 'run_kv_mvp_scaffold.ps1'
if (-not (Test-Path -LiteralPath $runner -PathType Leaf)) { throw "Runner not found: $runner" }
$configLoader = Join-Path $scriptRoot 'Import-KvStudioOperatorConfig.ps1'
if (Test-Path -LiteralPath $configLoader -PathType Leaf) {
  $operatorConfig = & $configLoader -ConfigPath $ConfigPath -ScriptRoot $scriptRoot
  if ($operatorConfig.found) {
    if (-not $PSBoundParameters.ContainsKey('KvsExe') -and $operatorConfig.kvs_exe) { $KvsExe = [string]$operatorConfig.kvs_exe }
    if (-not $PSBoundParameters.ContainsKey('OutRoot') -and $operatorConfig.repeat_out_root) { $OutRoot = [string]$operatorConfig.repeat_out_root }
    if (-not $PSBoundParameters.ContainsKey('TimeoutSeconds') -and $null -ne $operatorConfig.timeout_seconds) { $TimeoutSeconds = [int]$operatorConfig.timeout_seconds }
    if (-not $PSBoundParameters.ContainsKey('LocalPasteFormat') -and $operatorConfig.local_paste_format) { $LocalPasteFormat = [string]$operatorConfig.local_paste_format }
  }
}

$ScaffoldRoot = [IO.Path]::GetFullPath($ScaffoldRoot)
$OutRoot = [IO.Path]::GetFullPath($OutRoot)
New-Item -ItemType Directory -Force -Path $OutRoot | Out-Null

$manifestPath = Join-Path $ScaffoldRoot 'scaffold.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "scaffold.json not found: $manifestPath" }
$manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
if (-not $ProjectNamePrefix) { $ProjectNamePrefix = [string]$manifest.project.name }
if (-not $ProjectNamePrefix) { $ProjectNamePrefix = 'KvMvpRepeat' }

$attempts = @()
$consecutive = 0
$failureCounts = @{}
$startedAt = Get-Date

function Stop-ProcessTree([int]$ProcessIdValue) {
  $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessIdValue" -ErrorAction SilentlyContinue)
  foreach ($child in $children) {
    Stop-ProcessTree ([int]$child.ProcessId)
  }
  $process = Get-Process -Id $ProcessIdValue -ErrorAction SilentlyContinue
  if ($process) {
    Stop-Process -Id $ProcessIdValue -Force -ErrorAction SilentlyContinue
  }
}

for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
  $attemptName = ('{0}_R{1:D2}' -f $ProjectNamePrefix, $attempt)
  $attemptOutRoot = Join-Path $OutRoot ('attempt_{0:D2}' -f $attempt)
  New-Item -ItemType Directory -Force -Path $attemptOutRoot | Out-Null

  $args = @(
    '-NoProfile',
    '-ExecutionPolicy', 'Bypass',
    '-File', $runner,
    '-ScaffoldRoot', $ScaffoldRoot,
    '-OutRoot', $attemptOutRoot,
    '-ProjectName', $attemptName,
    '-TimeoutSeconds', ([string]$TimeoutSeconds)
  )
  if ($ConfigPath) { $args += @('-ConfigPath', $ConfigPath) }
  if ($KvsExe) { $args += @('-KvsExe', $KvsExe) }
  if ($ChecklistPath) { $args += @('-ChecklistPath', $ChecklistPath) }
  if ($AuditVariablePersistence) { $args += '-AuditVariablePersistence' }
  $args += @('-LocalPasteFormat', $LocalPasteFormat)

  $attemptStart = Get-Date
  $stdoutPath = Join-Path $attemptOutRoot 'runner_stdout.txt'
  $stderrPath = Join-Path $attemptOutRoot 'runner_stderr.txt'
  $attemptTimeoutSeconds = [math]::Max(1, $TimeoutSeconds + 15)
  $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $args -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
  $deadline = (Get-Date).AddSeconds($attemptTimeoutSeconds)
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
    $exitCode = -2
    [ordered]@{
      ok = $false
      error_code = 'KV_MVP_REPEAT_ATTEMPT_TIMEOUT'
      attempt = $attempt
      project_name = $attemptName
      elapsed_seconds = [math]::Round(((Get-Date) - $attemptStart).TotalSeconds, 3)
      attempt_timeout_seconds = $attemptTimeoutSeconds
      runner_timeout_seconds = $TimeoutSeconds
      stdout_path = $stdoutPath
      stderr_path = $stderrPath
      message = 'Repeat attempt timed out; runner process tree was terminated.'
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $attemptOutRoot 'timeout_result.json') -Encoding UTF8
  } else {
    $process.WaitForExit()
    $exitCode = [int]$process.ExitCode
  }
  $elapsed = [math]::Round(((Get-Date) - $attemptStart).TotalSeconds, 3)

  $resultPath = Join-Path (Join-Path $attemptOutRoot $attemptName) 'mvp_result.json'
  $result = $null
  if (Test-Path -LiteralPath $resultPath -PathType Leaf) {
    try { $result = Get-Content -Raw -LiteralPath $resultPath -Encoding UTF8 | ConvertFrom-Json } catch { $result = $null }
  }
  $compilePath = if ($result) { [string]$result.compile_result_path } else { '' }
  $setVariableValidation = Join-Path (Join-Path (Join-Path $attemptOutRoot $attemptName) 'artifacts') 'set_variables\variable_persistence_validation.json'
  $pass = (
    $exitCode -eq 0 -and
    $result -and
    [bool]$result.ok -and
    [bool]$result.compile_result_contains_ok -and
    $compilePath -and
    (Test-Path -LiteralPath $compilePath -PathType Leaf) -and
    (Test-Path -LiteralPath $setVariableValidation -PathType Leaf)
  )

  if ($pass) { $consecutive++ } else { $consecutive = 0 }
  $failureSignature = ''
  $sameFailureCount = 0
  if (-not $pass) {
    $failureSignature = @(
      if ($timedOut) { 'repeat_attempt' } elseif ($result -and $result.current_step) { [string]$result.current_step } else { 'unknown_step' }
      if ($timedOut) { 'KV_MVP_REPEAT_ATTEMPT_TIMEOUT' } elseif ($result -and $result.error_code) { [string]$result.error_code } else { 'unknown_error' }
    ) -join ':'
    if (-not $failureCounts.ContainsKey($failureSignature)) { $failureCounts[$failureSignature] = 0 }
    $failureCounts[$failureSignature] = [int]$failureCounts[$failureSignature] + 1
    $sameFailureCount = [int]$failureCounts[$failureSignature]
  }

  $attempts += [pscustomobject]@{
    attempt = $attempt
    project_name = $attemptName
    exit_code = $exitCode
    pass = [bool]$pass
    consecutive_after_attempt = $consecutive
    elapsed_seconds = $elapsed
    timed_out = [bool]$timedOut
    attempt_timeout_seconds = $attemptTimeoutSeconds
    stdout_path = $stdoutPath
    stderr_path = $stderrPath
    timeout_result_path = if ($timedOut) { Join-Path $attemptOutRoot 'timeout_result.json' } else { '' }
    result_path = $resultPath
    error_code = if ($timedOut) { 'KV_MVP_REPEAT_ATTEMPT_TIMEOUT' } elseif ($result -and $result.error_code) { [string]$result.error_code } else { '' }
    current_step = if ($timedOut) { 'repeat_attempt' } elseif ($result -and $result.current_step) { [string]$result.current_step } else { '' }
    compile_result_path = $compilePath
    set_variable_validation_path = $setVariableValidation
    failure_signature = $failureSignature
    same_failure_count = $sameFailureCount
  }

  $partial = [ordered]@{
    ok = ($consecutive -ge $RequiredConsecutivePasses)
    status = if ($consecutive -ge $RequiredConsecutivePasses) { 'pass' } else { 'running_or_failed' }
    required_consecutive_passes = $RequiredConsecutivePasses
    max_attempts = $MaxAttempts
    consecutive_passes = $consecutive
    attempts_completed = $attempt
    stop_after_same_failure_count = $StopAfterSameFailureCount
    scaffold_root = $ScaffoldRoot
    out_root = $OutRoot
    attempts = $attempts
  }
  $partial | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutRoot 'repeat_result.json') -Encoding UTF8

  if ($consecutive -ge $RequiredConsecutivePasses) { break }
  if ($StopAfterSameFailureCount -gt 0 -and $failureSignature -and $sameFailureCount -ge $StopAfterSameFailureCount) { break }
}

$ok = ($consecutive -ge $RequiredConsecutivePasses)
$final = [ordered]@{
  ok = $ok
  status = if ($ok) { 'pass' } else { 'fail' }
  required_consecutive_passes = $RequiredConsecutivePasses
  max_attempts = $MaxAttempts
  consecutive_passes = $consecutive
  attempts_completed = $attempts.Count
  stop_after_same_failure_count = $StopAfterSameFailureCount
  stopped_on_repeated_failure = @($attempts | Where-Object { $_.same_failure_count -ge $StopAfterSameFailureCount }).Count -gt 0
  elapsed_seconds = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
  scaffold_root = $ScaffoldRoot
  out_root = $OutRoot
  attempts = $attempts
}
$resultPath = Join-Path $OutRoot 'repeat_result.json'
$final | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
$final | ConvertTo-Json -Depth 8
if ($ok) { exit 0 }
exit 1
