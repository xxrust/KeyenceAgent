param(
  [string]$RepoRoot = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)),
  [string]$CodexSkillsRoot = (Join-Path $env:USERPROFILE '.codex\skills'),
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$CodexSkillsRoot = [IO.Path]::GetFullPath($CodexSkillsRoot)
if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $localRoot = if ($env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $env:USERPROFILE 'AppData\Local' }
  $OutDir = Join-Path $localRoot ('KeyenceAgent\Artifacts\repository-check\' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$steps = [System.Collections.Generic.List[object]]::new()
$startedAt = Get-Date

function Invoke-PowerShellStep([string]$Name, [string]$ScriptPath, [string[]]$Arguments) {
  $stepDir = Join-Path $OutDir $Name
  New-Item -ItemType Directory -Force -Path $stepDir | Out-Null
  $logPath = Join-Path $stepDir 'output.txt'
  $stepStarted = Get-Date
  $output = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $ScriptPath @Arguments 2>&1
  $exitCode = $LASTEXITCODE
  @($output | ForEach-Object { [string]$_ }) | Set-Content -LiteralPath $logPath -Encoding UTF8
  $entry = [pscustomobject]@{
    name = $Name
    ok = ($exitCode -eq 0)
    exit_code = $exitCode
    elapsed_seconds = [math]::Round(((Get-Date) - $stepStarted).TotalSeconds, 3)
    evidence = $logPath
  }
  $steps.Add($entry)
  $entry
}

$linkScript = Join-Path $RepoRoot 'scripts\assert_keyence_dev_links.ps1'
$boundaryGate = Join-Path $RepoRoot 'kv-studio-operator\scripts\gates\assert_kv_mvp_agent_boundary.ps1'
$uiGuardGate = Join-Path $RepoRoot 'kv-studio-operator\scripts\gates\assert_kv_mvp_ui_guard_usage.ps1'

$linkStep = Invoke-PowerShellStep 'dev_links' $linkScript @(
  '-RepoRoot', $RepoRoot,
  '-CodexSkillsRoot', $CodexSkillsRoot,
  '-OutDir', (Join-Path $OutDir 'dev_links\result')
)
if (-not $linkStep.ok) { $failedStep = $linkStep.name }

if (-not $failedStep) {
  $boundaryStep = Invoke-PowerShellStep 'agent_boundary_gate' $boundaryGate @(
    '-OutDir', (Join-Path $OutDir 'agent_boundary_gate\result')
  )
  if (-not $boundaryStep.ok) { $failedStep = $boundaryStep.name }
}

if (-not $failedStep) {
  $uiStep = Invoke-PowerShellStep 'ui_guard_gate' $uiGuardGate @(
    '-OutDir', (Join-Path $OutDir 'ui_guard_gate\result')
  )
  if (-not $uiStep.ok) { $failedStep = $uiStep.name }
}

if (-not $failedStep) {
  $stepStarted = Get-Date
  $previousErrorActionPreference = $ErrorActionPreference
  $ErrorActionPreference = 'Continue'
  $gitOutput = & git -C $RepoRoot diff --check 2>&1
  $gitExitCode = $LASTEXITCODE
  $ErrorActionPreference = $previousErrorActionPreference
  $gitLog = Join-Path $OutDir 'git_diff_check.txt'
  $gitText = @($gitOutput | ForEach-Object { [string]$_ }) -join [Environment]::NewLine
  [IO.File]::WriteAllText($gitLog, $gitText, [Text.Encoding]::UTF8)
  $gitStep = [pscustomobject]@{
    name = 'git_diff_check'
    ok = ($gitExitCode -eq 0)
    exit_code = $gitExitCode
    elapsed_seconds = [math]::Round(((Get-Date) - $stepStarted).TotalSeconds, 3)
    evidence = $gitLog
  }
  $steps.Add($gitStep)
  if (-not $gitStep.ok) { $failedStep = $gitStep.name }
}

$payload = [ordered]@{
  ok = [string]::IsNullOrWhiteSpace($failedStep)
  error_code = if ($failedStep) { 'KEYENCE_REPOSITORY_CHECK_FAILED' } else { '' }
  operation = 'test KeyenceAgent repository and live Codex links'
  current_step = if ($failedStep) { $failedStep } else { 'complete' }
  repo_root = $RepoRoot
  codex_skills_root = $CodexSkillsRoot
  git_head = (& git -C $RepoRoot rev-parse HEAD 2>$null)
  elapsed_seconds = [math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
  steps = @($steps)
}
$resultPath = Join-Path $OutDir 'result.json'
$payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8
$payload['result_path'] = $resultPath
$payload | ConvertTo-Json -Depth 8
if (-not $payload.ok) { exit 61 }
