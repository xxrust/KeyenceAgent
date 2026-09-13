param(
  [string]$OutRoot = '',
  [switch]$IncludeDisabled,
  [switch]$PlanOnly,
  [switch]$ContinueOnFailure
)
$ErrorActionPreference = 'Stop'
$testRoot = Split-Path -Parent $PSCommandPath
$runner = Join-Path $testRoot 'run-workflow-test.ps1'
if (-not $OutRoot) { $OutRoot = Join-Path $testRoot 'runs' }
$summaries = [System.Collections.Generic.List[object]]::new()
foreach ($scenarioPath in @(Get-ChildItem -LiteralPath $testRoot -Directory | Sort-Object Name | ForEach-Object { Join-Path $_.FullName 'scenario.json' } | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf })) {
  $scenario = Get-Content -Raw -LiteralPath $scenarioPath -Encoding UTF8 | ConvertFrom-Json
  if ($scenario.enabled -eq $false -and -not $IncludeDisabled) { continue }
  $args = @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',$runner,'-ScenarioPath',$scenarioPath,'-OutRoot',$OutRoot)
  if ($PlanOnly) { $args += '-PlanOnly' }
  & powershell @args
  $exit = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }
  $summaries.Add([ordered]@{scenario=$scenario.name;path=$scenarioPath;exit_code=$exit})
  if ($exit -ne 0 -and -not $ContinueOnFailure) { break }
}
$summaryPath = Join-Path ([IO.Path]::GetFullPath($OutRoot)) 'run_all_summary.json'
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $summaryPath) | Out-Null
$summaries | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $summaryPath -Encoding UTF8
$summaries | ConvertTo-Json -Depth 8
if (@($summaries | Where-Object { $_.exit_code -ne 0 }).Count -eq 0) { exit 0 } else { exit 1 }
