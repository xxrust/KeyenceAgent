param([string]$OutRoot='', [switch]$PlanOnly, [switch]$KeepProjectOpen)
$runner = Join-Path (Split-Path -Parent $PSScriptRoot) 'run-workflow-test.ps1'
$runArguments = @('-ScenarioPath', (Join-Path $PSScriptRoot 'scenario.json'))
if ($OutRoot) { $runArguments += @('-OutRoot', $OutRoot) }
if ($PlanOnly) { $runArguments += '-PlanOnly' }
if ($KeepProjectOpen) { $runArguments += '-KeepProjectOpen' }
& powershell -STA -NoProfile -ExecutionPolicy Bypass -File $runner @runArguments
exit $LASTEXITCODE
