param(
  [Parameter(Mandatory = $true)][string]$ProjectPath
)

$ErrorActionPreference = 'Stop'
$project = [IO.Path]::GetFullPath($ProjectPath)
if (-not (Test-Path -LiteralPath $project -PathType Leaf)) { throw "KV_PROJECT_NOT_FOUND: $project" }

$existing = @(Get-Process -Name Kvs -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0) {
  throw "KV_STUDIO_BUSY: close existing KV STUDIO sessions before running this test."
}

$operatorRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$resolveScript = Join-Path $PSScriptRoot 'resolve-kvs-exe.ps1'
$kvsExe = @(& powershell.exe -NoProfile -ExecutionPolicy Bypass -File $resolveScript -OperatorRoot $operatorRoot | Where-Object { $_ -and ([string]$_).Trim() } | Select-Object -First 1)
if ($LASTEXITCODE -ne 0 -or $kvsExe.Count -eq 0) { throw 'KV_STUDIO_NOT_FOUND: resolve-kvs-exe.ps1 could not resolve Kvs.exe.' }

$process = Start-Process -FilePath ([string]$kvsExe[0]).Trim() -ArgumentList ('"' + $project + '"') -PassThru
Start-Sleep -Seconds 2
$process.Refresh()
if ($process.HasExited) { throw "KV_STUDIO_START_FAILED: process $($process.Id) exited during startup." }
[Console]::Out.WriteLine($process.Id)
