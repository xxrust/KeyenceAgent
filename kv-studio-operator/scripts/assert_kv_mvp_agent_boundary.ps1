param(
  [string]$ScriptsRoot = (Split-Path -Parent $PSCommandPath),
  [string]$MvpScriptsRoot = (Join-Path (Split-Path -Parent $PSCommandPath) 'mvp'),
  [string]$OutDir = '',
  [string[]]$ScriptNames = @(
    'run_kv_mvp_scaffold.ps1',
    'run_kv_mvp_repair_existing_project.ps1',
    'run_kv_mvp_repeat.ps1',
    'mvp/create_project_local_guarded.ps1',
    'mvp/import_mnm_guarded.ps1',
    'mvp/set_variables_guarded.ps1',
    'mvp/compile_and_copy_result_bounded.ps1',
    'mvp/copy_convert_result_from_tree_handle.ps1'
  )
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
  public_agent_entrypoints = @(
    'new_kv_mvp_scaffold.ps1',
    'new_kv_mvp_multi_mnm_scaffold.ps1',
    'validate_kv_mvp_scaffold.ps1',
    'run_kv_mvp_scaffold.ps1',
    'run_kv_mvp_repair_existing_project.ps1',
    'run_kv_mvp_repeat.ps1'
  )
  runner_owned_scripts = $ScriptNames
  checked_forbidden_interaction = @($forbiddenPatterns | ForEach-Object { $_.name })
  scripts_root = $ScriptsRoot
  mvp_scripts_root = $MvpScriptsRoot
}

if ($OutDir) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $contractPath = Join-Path $OutDir 'agent_boundary_contract.json'
  $contract['contract_path'] = $contractPath
  $contract | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $contractPath -Encoding UTF8
}

$contract | ConvertTo-Json -Depth 6
