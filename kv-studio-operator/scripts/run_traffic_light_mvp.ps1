param(
  [string]$OutRoot = 'C:\Users\Public\KVSkillPractice\mvp_runs',
  [string]$ProjectName = ('TrafficLightMVP_' + (Get-Date -Format 'yyyyMMdd_HHmmss')),
  [string]$CpuModel = 'KV-X310',
  [string]$KvsExe = '',
  [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSCommandPath
$scaffoldRoot = Join-Path (Join-Path $OutRoot '_scaffolds') $ProjectName
$newScaffold = Join-Path $scriptRoot 'new_kv_mvp_scaffold.ps1'
$runScaffold = Join-Path $scriptRoot 'run_kv_mvp_scaffold.ps1'

if (-not (Test-Path -LiteralPath $newScaffold)) {
  throw "Scaffold generator not found: $newScaffold"
}
if (-not (Test-Path -LiteralPath $runScaffold)) {
  throw "Scaffold runner not found: $runScaffold"
}

& powershell -NoProfile -ExecutionPolicy Bypass -File $newScaffold `
  -ScaffoldRoot $scaffoldRoot `
  -ProjectName $ProjectName `
  -CpuModel $CpuModel `
  -ModuleName 'TrafficLight_MVP' `
  -Template 'TrafficLight' `
  -TaskSummary 'Traffic-light MVP compatibility scaffold.' | Out-Host
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$runnerArgs = @(
  '-ScaffoldRoot', $scaffoldRoot,
  '-OutRoot', $OutRoot,
  '-ProjectName', $ProjectName,
  '-CpuModel', $CpuModel,
  '-TimeoutSeconds', [string]$TimeoutSeconds
)
if ($KvsExe) { $runnerArgs += @('-KvsExe', $KvsExe) }

& powershell -NoProfile -ExecutionPolicy Bypass -File $runScaffold @runnerArgs
exit $LASTEXITCODE
