param(
  [string]$ConnectionTitle = '连接设定',
  [string]$OutDir = 'C:\kvrun\eip\snapshots',
  [switch]$KeepDialogs
)
# Thin wrapper: the UI steps live in runner_children/snapshot_eip_connection_guarded.ps1.
$ErrorActionPreference = 'Stop'
$runner = Join-Path (Split-Path -Parent $PSScriptRoot) 'runner_children\snapshot_eip_connection_guarded.ps1'
if (-not (Test-Path -LiteralPath $runner)) { throw "KV_RUNNER_MISSING: $runner" }
$argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner, '-ConnectionTitle', $ConnectionTitle, '-OutDir', $OutDir)
if ($KeepDialogs) { $argumentList += '-KeepDialogs' }
$process = Start-Process -FilePath 'powershell' -ArgumentList $argumentList -Wait -PassThru -WindowStyle Hidden
exit $process.ExitCode
