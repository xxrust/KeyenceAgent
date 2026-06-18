param(
  [string]$ConfigPath = '',
  [string]$ScriptRoot = ''
)

$ErrorActionPreference = 'Stop'

function Expand-ConfigPathValue([string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return '' }
  return [Environment]::ExpandEnvironmentVariables($Value)
}

if ([string]::IsNullOrWhiteSpace($ScriptRoot)) {
  $ScriptRoot = Split-Path -Parent $PSCommandPath
}

$candidatePaths = @()
if (-not [string]::IsNullOrWhiteSpace($ConfigPath)) {
  $candidatePaths += $ConfigPath
}
if (-not [string]::IsNullOrWhiteSpace($env:KV_STUDIO_OPERATOR_CONFIG)) {
  $candidatePaths += $env:KV_STUDIO_OPERATOR_CONFIG
}
if (-not [string]::IsNullOrWhiteSpace($env:APPDATA)) {
  $candidatePaths += (Join-Path $env:APPDATA 'Codex\kv-studio-operator\config.json')
}
$skillRoot = Split-Path -Parent $ScriptRoot
$packageRoot = Split-Path -Parent $skillRoot
$candidatePaths += (Join-Path $ScriptRoot 'config\kv-studio-operator.local.json')
$candidatePaths += (Join-Path $skillRoot 'config\kv-studio-operator.local.json')
$candidatePaths += (Join-Path $packageRoot 'config\kv-studio-operator.local.json')

$resolvedPath = ''
foreach ($candidate in $candidatePaths) {
  if ([string]::IsNullOrWhiteSpace($candidate)) { continue }
  $expanded = Expand-ConfigPathValue $candidate
  if (Test-Path -LiteralPath $expanded -PathType Leaf) {
    $resolvedPath = [IO.Path]::GetFullPath($expanded)
    break
  }
}

if ([string]::IsNullOrWhiteSpace($resolvedPath)) {
  return [pscustomobject]@{
    found = $false
    path = ''
  }
}

$config = Get-Content -Raw -LiteralPath $resolvedPath -Encoding UTF8 | ConvertFrom-Json
$workRoot = Expand-ConfigPathValue ([string]$config.work_root)
$mvpOutRoot = Expand-ConfigPathValue ([string]$config.mvp_out_root)
$repairOutRoot = Expand-ConfigPathValue ([string]$config.repair_out_root)
$repeatOutRoot = Expand-ConfigPathValue ([string]$config.repeat_out_root)
if ([string]::IsNullOrWhiteSpace($mvpOutRoot) -and -not [string]::IsNullOrWhiteSpace($workRoot)) {
  $mvpOutRoot = Join-Path $workRoot 'mvp_runs'
}
if ([string]::IsNullOrWhiteSpace($repairOutRoot) -and -not [string]::IsNullOrWhiteSpace($workRoot)) {
  $repairOutRoot = Join-Path $workRoot 'mvp_repair_runs'
}
if ([string]::IsNullOrWhiteSpace($repeatOutRoot) -and -not [string]::IsNullOrWhiteSpace($workRoot)) {
  $repeatOutRoot = Join-Path $workRoot 'mvp_repeat_runs'
}

return [pscustomobject]@{
  found = $true
  path = $resolvedPath
  kvs_exe = Expand-ConfigPathValue ([string]$config.kvs_exe)
  work_root = $workRoot
  mvp_out_root = $mvpOutRoot
  repair_out_root = $repairOutRoot
  repeat_out_root = $repeatOutRoot
  admin_credential_path = Expand-ConfigPathValue ([string]$config.admin_credential_path)
  admin_user_default = if ($config.admin_user_default) { [string]$config.admin_user_default } else { '' }
  htmlhelp_root = Expand-ConfigPathValue ([string]$config.htmlhelp_root)
  wiki_root = Expand-ConfigPathValue ([string]$config.wiki_root)
  wiki_cleaned_db = Expand-ConfigPathValue ([string]$config.wiki_cleaned_db)
  wiki_fixed_db = Expand-ConfigPathValue ([string]$config.wiki_fixed_db)
  wiki_query_script = Expand-ConfigPathValue ([string]$config.wiki_query_script)
  timeout_seconds = if ($null -ne $config.timeout_seconds -and [string]$config.timeout_seconds -ne '') { [int]$config.timeout_seconds } else { $null }
  local_paste_format = if ($config.local_paste_format) { [string]$config.local_paste_format } else { '' }
}
