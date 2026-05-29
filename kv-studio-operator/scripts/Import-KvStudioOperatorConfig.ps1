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
$candidatePaths += (Join-Path $skillRoot 'config\kv-studio-operator.local.json')

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

return [pscustomobject]@{
  found = $true
  path = $resolvedPath
  kvs_exe = Expand-ConfigPathValue ([string]$config.kvs_exe)
  work_root = Expand-ConfigPathValue ([string]$config.work_root)
  mvp_out_root = Expand-ConfigPathValue ([string]$config.mvp_out_root)
  repair_out_root = Expand-ConfigPathValue ([string]$config.repair_out_root)
  repeat_out_root = Expand-ConfigPathValue ([string]$config.repeat_out_root)
  admin_credential_path = Expand-ConfigPathValue ([string]$config.admin_credential_path)
  htmlhelp_root = Expand-ConfigPathValue ([string]$config.htmlhelp_root)
  wiki_root = Expand-ConfigPathValue ([string]$config.wiki_root)
  wiki_cleaned_db = Expand-ConfigPathValue ([string]$config.wiki_cleaned_db)
  wiki_fixed_db = Expand-ConfigPathValue ([string]$config.wiki_fixed_db)
  wiki_query_script = Expand-ConfigPathValue ([string]$config.wiki_query_script)
  timeout_seconds = if ($null -ne $config.timeout_seconds -and [string]$config.timeout_seconds -ne '') { [int]$config.timeout_seconds } else { $null }
  local_paste_format = if ($config.local_paste_format) { [string]$config.local_paste_format } else { '' }
}
