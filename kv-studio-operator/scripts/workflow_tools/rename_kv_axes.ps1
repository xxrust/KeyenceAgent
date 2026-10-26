param(
  [Parameter(Mandatory=$true)][string]$MappingPath,
  [string]$OutDir = ''
)
# Thin wrapper: the UI steps live in runner_children/rename_axes_guarded.ps1.
$ErrorActionPreference = 'Stop'
$runner = Join-Path (Split-Path -Parent $PSScriptRoot) 'runner_children\rename_axes_guarded.ps1'
if (-not (Test-Path -LiteralPath $runner)) { throw "KV_RUNNER_MISSING: $runner" }
$argumentList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $runner, '-MappingPath', $MappingPath)
if ($OutDir) { $argumentList += @('-OutDir', $OutDir) }
$process = Start-Process -FilePath 'powershell' -ArgumentList $argumentList -Wait -PassThru -WindowStyle Hidden
exit $process.ExitCode
