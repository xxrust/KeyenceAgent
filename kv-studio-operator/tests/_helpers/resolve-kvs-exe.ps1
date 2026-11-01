param(
  [string]$OperatorRoot = '',
  [switch]$AllowMissing
)

$ErrorActionPreference = 'Stop'
if (-not $OperatorRoot) { $OperatorRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..')) }
if ($env:KV_STUDIO_EXE) {
  if (-not (Test-Path -LiteralPath $env:KV_STUDIO_EXE -PathType Leaf)) { throw "KV_STUDIO_EXE does not exist: $env:KV_STUDIO_EXE" }
  Write-Output ([IO.Path]::GetFullPath($env:KV_STUDIO_EXE))
  exit 0
}
$resolver = Join-Path $OperatorRoot 'scripts\get_kvstudio_install.ps1'
$path = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resolver -Probe | Where-Object { $_ -and ([string]$_).Trim() } | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or $path.Count -eq 0) {
  if ($AllowMissing) { exit 0 }
  throw 'KV_STUDIO_NOT_FOUND: get_kvstudio_install.ps1 could not resolve Kvs.exe.'
}
Write-Output ([string]$path[0]).Trim()
