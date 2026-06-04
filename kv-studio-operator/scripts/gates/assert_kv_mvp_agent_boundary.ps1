param(
  [string]$ScriptsRoot = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)),
  [string]$MvpScriptsRoot = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'runner_children'),
  [string]$ManifestPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'script_manifest.json'),
  [string]$OutDir = '',
  [string[]]$ScriptNames = @()
)

$ErrorActionPreference = 'Stop'

function Stop-AgentBoundaryCheck([string]$ErrorCode, [string]$Message, [object[]]$Findings, [int]$ExitCode) {
  $evidence = @()
  if ($OutDir) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $path = Join-Path $OutDir 'kv_agent_boundary_findings.json'
    $Findings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
    $evidence += $path
  }
  $payload = [ordered]@{
    ok = $false
    error_code = $ErrorCode
    operation = 'assert KV MVP agent boundary'
    message = $Message
    evidence = $evidence
    finding_count = @($Findings).Count
    findings = @($Findings | Select-Object -First 25)
    remediation = @(
      'Keep agent reasoning before KV STUDIO opens and after the runner exits.',
      'Remove interactive prompts and manual pause points from runner-owned KV STUDIO scripts.',
      'Encode required decisions as scaffold files, preflight gates, or deterministic runner checks.'
    )
  }
  [Console]::Error.WriteLine('KV_AGENT_BOUNDARY_VIOLATION ' + (($payload | ConvertTo-Json -Depth 8 -Compress)))
  exit $ExitCode
}

$ScriptsRoot = [IO.Path]::GetFullPath($ScriptsRoot)
$MvpScriptsRoot = [IO.Path]::GetFullPath($MvpScriptsRoot)
$ManifestPath = [IO.Path]::GetFullPath($ManifestPath)
$manifest = $null
$publicAgentEntrypoints = @(
  'new_kv_mvp_scaffold.ps1',
  'new_kv_mvp_multi_mnm_scaffold.ps1',
  'validate_kv_mvp_scaffold.ps1',
  'assert_kv_mnm_import_plan.ps1',
  'run_kv_mvp_scaffold.ps1',
  'run_kv_mvp_repair_existing_project.ps1',
  'run_kv_mvp_repeat.ps1'
)

if ($ScriptNames.Count -eq 0) {
  if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Script manifest is required: $ManifestPath"
  }
  $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  $publicAgentEntrypoints = @(
    @($manifest.classes.customer_scaffold_tool | ForEach-Object { $_.path })
    @($manifest.classes.customer_workflow | ForEach-Object { $_.path })
    @($manifest.classes.gate | ForEach-Object { $_.path })
  )
  $ScriptNames = @(
    @($manifest.classes.customer_workflow | ForEach-Object { $_.path })
    @($manifest.classes.runner_child_approved | ForEach-Object { $_.path })
    @($manifest.classes.runner_child_pending | ForEach-Object { $_.path })
  )
}

$forbiddenPatterns = @(
  @{ name = 'ReadHost'; regex = '\bRead-Host\b' },
  @{ name = 'PauseCommand'; regex = '^\s*pause\s*$' },
  @{ name = 'PromptForChoice'; regex = '\.PromptForChoice\(' },
  @{ name = 'OutGridView'; regex = '\bOut-GridView\b' },
  @{ name = 'DebuggerBreak'; regex = '\[System\.Diagnostics\.Debugger\]::Break\(' }
)

$findings = @()
foreach ($name in $ScriptNames) {
  $path = [IO.Path]::GetFullPath((Join-Path $ScriptsRoot $name))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    $findings += [pscustomobject]@{
      file = $path
      line = 0
      pattern = 'MissingScript'
      text = 'Required runner-owned script is missing.'
    }
    continue
  }
  $lines = Get-Content -LiteralPath $path
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = [string]$lines[$i]
    if ($line -match '^\s*#') { continue }
    foreach ($pattern in $forbiddenPatterns) {
      if ($line -match $pattern.regex) {
        $findings += [pscustomobject]@{
          file = $path
          line = $i + 1
          pattern = $pattern.name
          text = $line.Trim()
        }
      }
    }
  }
}

if ($findings.Count -gt 0) {
  Stop-AgentBoundaryCheck `
    -ErrorCode 'KV_AGENT_BOUNDARY_VIOLATION' `
    -Message 'KV MVP runner-owned scripts contain interactive agent/manual decision points.' `
    -Findings $findings `
    -ExitCode 33
}

$contract = [ordered]@{
  ok = $true
  operation = 'assert KV MVP agent boundary'
  agent_allowed_phases = @(
    'prepare_scaffold_before_kv_studio_opens',
    'verify_same_run_artifacts_after_runner_exits'
  )
  script_owned_phase = 'from first KV STUDIO launch through compile result copy'
  public_agent_entrypoints = $publicAgentEntrypoints
  runner_owned_scripts = $ScriptNames
  checked_forbidden_interaction = @($forbiddenPatterns | ForEach-Object { $_.name })
  scripts_root = $ScriptsRoot
  mvp_scripts_root = $MvpScriptsRoot
  manifest_path = $ManifestPath
}

if ($OutDir) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $contractPath = Join-Path $OutDir 'agent_boundary_contract.json'
  $contract['contract_path'] = $contractPath
  $contract | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $contractPath -Encoding UTF8
}

$contract | ConvertTo-Json -Depth 6
