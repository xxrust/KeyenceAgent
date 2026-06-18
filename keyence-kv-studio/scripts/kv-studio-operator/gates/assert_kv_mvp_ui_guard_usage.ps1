param(
  [string]$ScriptsRoot = (Split-Path -Parent (Split-Path -Parent $PSCommandPath)),
  [string]$ManifestPath = (Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'script_manifest.json'),
  [string]$OutDir = '',
  [string[]]$ScriptNames = @()
)

$ErrorActionPreference = 'Stop'

function Stop-GuardUsageCheck([string]$ErrorCode, [string]$Message, [object[]]$Findings, [int]$ExitCode) {
  $evidence = @()
  if ($OutDir) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $path = Join-Path $OutDir 'kv_ui_guard_usage_findings.json'
    $Findings | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
    $evidence += $path
  }
  $payload = [ordered]@{
    ok = $false
    error_code = $ErrorCode
    operation = 'assert KV MVP UI guard usage'
    message = $Message
    evidence = $evidence
    finding_count = @($Findings).Count
    findings = @($Findings | Select-Object -First 25)
    remediation = @(
      'Move global UI input into scripts/guards/kv_ui_guard.ps1 guarded action functions.',
      'Replace raw SendKeys/keybd_event/mouse_event/SetCursorPos/clipboard paste paths in MVP child scripts.',
      'Do not run KV STUDIO while this check reports violations.'
    )
  }
  [Console]::Error.WriteLine('KV_UI_GUARD_STATIC_VIOLATION ' + (($payload | ConvertTo-Json -Depth 8 -Compress)))
  exit $ExitCode
}

$ScriptsRoot = [IO.Path]::GetFullPath($ScriptsRoot)
$ManifestPath = [IO.Path]::GetFullPath($ManifestPath)

if ($ScriptNames.Count -eq 0) {
  if (-not (Test-Path -LiteralPath $ManifestPath -PathType Leaf)) {
    throw "Script manifest is required: $ManifestPath"
  }
  $manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
  $ScriptNames = @(
    @($manifest.classes.runner_child_approved | Where-Object { $_.ui_guard_required } | ForEach-Object { $_.path })
    @($manifest.classes.runner_child_pending | Where-Object { $_.ui_guard_required } | ForEach-Object { $_.path })
  ) | ForEach-Object {
    $_
  }
}
$allowedFiles = @(
  [IO.Path]::GetFullPath((Join-Path $ScriptsRoot 'guards\kv_ui_guard.ps1')),
  [IO.Path]::GetFullPath($PSCommandPath)
)

$patterns = @(
  @{ name = 'SendKeys'; regex = '\[System\.Windows\.Forms\.SendKeys\]::SendWait|\[Windows\.Forms\.SendKeys\]::SendWait' },
  @{ name = 'keybd_event'; regex = '::keybd_event\(' },
  @{ name = 'mouse_event'; regex = '::mouse_event\(' },
  @{ name = 'SetCursorPos'; regex = '::SetCursorPos\(' },
  @{ name = 'ClipboardSetText'; regex = '\[System\.Windows\.Forms\.Clipboard\]::SetText|\[Windows\.Forms\.Clipboard\]::SetText' },
  @{ name = 'AppActivate'; regex = '\.AppActivate\(' }
)

$findings = @()
foreach ($name in $ScriptNames) {
  $path = [IO.Path]::GetFullPath((Join-Path $ScriptsRoot $name))
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
    $findings += [pscustomobject]@{
      file = $path
      line = 0
      pattern = 'MissingScript'
      text = 'Required MVP child script is missing.'
    }
    continue
  }
  if ($allowedFiles -contains $path) { continue }
  $lines = Get-Content -LiteralPath $path
  for ($i = 0; $i -lt $lines.Count; $i++) {
    $line = [string]$lines[$i]
    if ($line -match '^\s*#') { continue }
    foreach ($pattern in $patterns) {
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
  Stop-GuardUsageCheck `
    -ErrorCode 'KV_UI_GUARD_STATIC_VIOLATION' `
    -Message 'KV MVP child scripts still contain raw global UI input outside scripts/guards/kv_ui_guard.ps1.' `
    -Findings $findings `
    -ExitCode 32
}

[pscustomobject]@{
  ok = $true
  operation = 'assert KV MVP UI guard usage'
  scripts_root = $ScriptsRoot
  manifest_path = $ManifestPath
  checked_scripts = $ScriptNames
} | ConvertTo-Json -Depth 4
