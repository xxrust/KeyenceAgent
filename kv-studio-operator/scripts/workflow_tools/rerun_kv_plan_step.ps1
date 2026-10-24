param(
  [Parameter(Mandatory=$true)][string]$PlanPath,
  [Parameter(Mandatory=$true)][string]$StepName,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds = 600
)
$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
$root = Split-Path -Parent $scriptDir
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')

if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw "KV_RERUN_PLAN_MISSING: $PlanPath" }
$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
$step = @($plan.steps | Where-Object { [string]$_.name -eq $StepName })
if ($step.Count -ne 1) { throw "KV_RERUN_STEP_NOT_FOUND: $StepName (matches=$($step.Count))" }
$step = $step[0]
$classes = @($step.classes | ForEach-Object { [string]$_ })
$scriptPath = Resolve-KvStudioOperatorScriptPath -ScriptRoot $root -Name ([string]$step.script_name) -Classes $classes
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$argsList = @($step.arguments | ForEach-Object { [string]$_ })
# Redirect the step's own -OutDir to the verification directory so a replay never
# overwrites the original run's evidence.
$outIndex = [Array]::IndexOf($argsList, '-OutDir')
if ($outIndex -ge 0 -and ($outIndex + 1) -lt $argsList.Count) { $argsList[$outIndex + 1] = $OutDir }
$stdoutPath = Join-Path $OutDir 'step_stdout.txt'
$stderrPath = Join-Path $OutDir 'step_stderr.txt'
$watch = [Diagnostics.Stopwatch]::StartNew()
$proc = Start-Process -FilePath 'powershell' -ArgumentList (@('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath) + $argsList) -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath -PassThru -WindowStyle Hidden
$timedOut = $false
if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
  $timedOut = $true
  try { Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue } catch {}
}
$proc.Refresh()
$exitCode = if ($timedOut) { -2 } else { [int]$proc.ExitCode }
$watch.Stop()

# Collect the contract files declared for this script, plus a failure screenshot.
$contractFiles = @()
try {
  $manifest = Get-Content -LiteralPath (Join-Path $root 'script_manifest.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $contract = $manifest.step_result_contracts.([string]$step.script_name)
  if (-not $contract) {
    $leaf = [IO.Path]::GetFileName([string]$step.script_name)
    foreach ($entry in $manifest.step_result_contracts.PSObject.Properties) {
      if ([IO.Path]::GetFileName($entry.Name) -eq $leaf) { $contract = $entry.Value; break }
    }
  }
  if ($contract -and $contract.files) { $contractFiles = @($contract.files | ForEach-Object { [string]$_ }) }
} catch {}
$present = @()
foreach ($file in $contractFiles) {
  $candidate = Join-Path $OutDir $file
  if (Test-Path -LiteralPath $candidate -PathType Leaf) { $present += $candidate }
}
$screenshot = Join-Path $OutDir 'failure.png'
if ($exitCode -ne 0 -and -not (Test-Path -LiteralPath $screenshot -PathType Leaf)) {
  try { & (Join-Path $root 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'failure.png' | Out-Null } catch {}
}
if (-not (Test-Path -LiteralPath $screenshot -PathType Leaf)) { $screenshot = '' }

$result = [ordered]@{
  ok = ($exitCode -eq 0)
  step = [string]$step.name
  script = $scriptPath
  classes = $classes
  arguments = $argsList
  exit_code = $exitCode
  timed_out = $timedOut
  elapsed_seconds = [math]::Round($watch.Elapsed.TotalSeconds, 3)
  stdout_path = $stdoutPath
  stderr_path = $stderrPath
  contract_files = $present
  failure_screenshot_path = $screenshot
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'rerun_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 4
exit $exitCode
