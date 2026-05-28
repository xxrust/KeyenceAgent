param(
  [Parameter(Mandatory=$true)]
  [string]$ScaffoldRoot,

  [string]$OutRoot = 'C:\Users\Public\KVSkillPractice\mvp_repeat_runs',
  [string]$ProjectNamePrefix = '',
  [string]$KvsExe = '',
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
  if ($KvsExe) { $args += @('-KvsExe', $KvsExe) }
  if ($ChecklistPath) { $args += @('-ChecklistPath', $ChecklistPath) }
  if ($AuditVariablePersistence) { $args += '-AuditVariablePersistence' }
  $args += @('-LocalPasteFormat', $LocalPasteFormat)

  $attemptStart = Get-Date
  & powershell @args
  $exitCode = $LASTEXITCODE
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
      if ($result -and $result.current_step) { [string]$result.current_step } else { 'unknown_step' }
      if ($result -and $result.error_code) { [string]$result.error_code } else { 'unknown_error' }
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
    result_path = $resultPath
    error_code = if ($result -and $result.error_code) { [string]$result.error_code } else { '' }
    current_step = if ($result -and $result.current_step) { [string]$result.current_step } else { '' }
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
