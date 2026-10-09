<#
.SYNOPSIS
  Report whether KV STUDIO is installed on this machine, and where.

.DESCRIPTION
  Read-only, non-UI entry point for other agents. It delegates to
  keyence-plc-programmer/scripts/resolve_kvstudio_local.ps1, which layers
  explicit override, cache, operator config, registry, Start Menu shortcuts
  and bounded search roots, and validates every hit as a real Kvs.exe.

  Always prints one JSON object on stdout:
    installed         true/false
    kvs_exe           absolute path to Kvs.exe when installed
    working_directory directory that contains Kvs.exe
    version           file version of Kvs.exe
    source            which layer produced the hit
    cached            true when the result came from the local cache
    elapsed_ms        resolution time

  Exit codes: 0 installed, 2 not installed, 3 resolver script not found.

  -Probe prints only the Kvs.exe path (nothing when absent) and returns
  exit code 0 or 1, for a cheap boolean check.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File get_kvstudio_install.ps1
  powershell -NoProfile -ExecutionPolicy Bypass -File get_kvstudio_install.ps1 -Probe
#>
param(
  [switch]$Probe,
  [switch]$Refresh,
  [string]$KvsExe = ''
)

$ErrorActionPreference = 'Stop'

function Get-ResolverPath {
  $skillRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
  $skillsRoot = Split-Path -Parent $skillRoot
  $candidates = New-Object System.Collections.Generic.List[string]
  if ($env:KEYENCE_SKILLS_ROOT) {
    $candidates.Add((Join-Path $env:KEYENCE_SKILLS_ROOT 'keyence-plc-programmer\scripts\resolve_kvstudio_local.ps1')) | Out-Null
  }
  $candidates.Add((Join-Path $skillsRoot 'keyence-plc-programmer\scripts\resolve_kvstudio_local.ps1')) | Out-Null
  foreach ($profileRoot in @('.dsh', '.codex')) {
    $candidates.Add((Join-Path $env:USERPROFILE (Join-Path $profileRoot 'skills\keyence-plc-programmer\scripts\resolve_kvstudio_local.ps1'))) | Out-Null
  }
  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate -PathType Leaf)) { return $candidate }
  }
  return ''
}

function Write-Payload([object]$Payload, [int]$ExitCode) {
  $Payload | ConvertTo-Json -Depth 6
  exit $ExitCode
}

$resolver = Get-ResolverPath
if (-not $resolver) {
  Write-Payload ([ordered]@{
    ok = $false
    installed = $false
    error_code = 'KV_RESOLVER_NOT_FOUND'
    message = 'resolve_kvstudio_local.ps1 was not found next to the keyence-plc-programmer skill.'
  }) 3
}

$arguments = @()
if ($Probe) { $arguments += '-Probe' }
if ($Refresh) { $arguments += '-SkipCache' }
if (-not [string]::IsNullOrWhiteSpace($KvsExe)) { $arguments += @('-KvsExe', $KvsExe) }

if ($Probe) {
  # stdout carries the path, stderr carries diagnostics; keep them apart.
  $probeOutput = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resolver @arguments)
  $probeExit = $LASTEXITCODE
  if ($probeExit -ne 0) { exit 1 }
  $path = ($probeOutput | Where-Object { $_ -and ([string]$_).Trim() } | Select-Object -First 1)
  if ($path) { [Console]::Out.WriteLine(([string]$path).Trim()) }
  exit 0
}

$stdout = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resolver @arguments 2>&1)
$exitCode = $LASTEXITCODE
$text = @($stdout | ForEach-Object { [string]$_ })

$resolved = $null
try { $resolved = ($text -join [Environment]::NewLine | ConvertFrom-Json) } catch { $resolved = $null }

if ($exitCode -ne 0 -or -not $resolved -or -not $resolved.KvsExe) {
  Write-Payload ([ordered]@{
    ok = $false
    installed = $false
    error_code = 'KV_NOT_INSTALLED'
    resolver_path = $resolver
    checked = @($text | Select-Object -First 5)
  }) 2
}

Write-Payload ([ordered]@{
  ok = $true
  installed = $true
  kvs_exe = [string]$resolved.KvsExe
  working_directory = [string]$resolved.WorkingDirectory
  version = [string]$resolved.Version
  source = [string]$resolved.Source
  cached = [bool]$resolved.Cached
  elapsed_ms = [int]$resolved.ElapsedMs
  resolver_path = $resolver
  capacity_check = 'kv-studio-operator get_kvstudio_install.ps1'
}) 0
