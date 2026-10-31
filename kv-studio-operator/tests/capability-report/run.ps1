param([string]$WorkRoot = '')
$ErrorActionPreference = 'Stop'
$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$generator = Join-Path $skillRoot 'scripts\workflow_tools\generate_kv_capability_report.ps1'
if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-capability-report-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') { $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail }) }
$runsRoot = Join-Path $skillRoot 'tests\kv-interface-regression\runs'
$latest = Get-ChildItem -LiteralPath $runsRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^13_project_text_snapshot_' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$snapshot = if ($latest) { Join-Path $latest.FullName 'workflow\snapshot' } else { '' }
$outPath = Join-Path $WorkRoot 'capability-status.md'
& powershell -NoProfile -ExecutionPolicy Bypass -File $generator -SnapshotPath $snapshot -OutPath $outPath | Out-Null
Add-Case 'generator exits 0' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
Add-Case 'report written' (Test-Path -LiteralPath $outPath) $outPath
if (Test-Path -LiteralPath $outPath) {
  $text = Get-Content -LiteralPath $outPath -Raw -Encoding UTF8
  Add-Case 'report has generated header' ($text.Contains('# KV Studio Operator capability status (generated)')) ''
  Add-Case 'report has assets section' ($text.Contains('## Assets')) ''
  Add-Case 'report has snapshot readiness section' ($text.Contains('## Snapshot readiness')) ''
  $ontology = Get-Content -Raw -LiteralPath (Join-Path $skillRoot 'assets\ontology.json') -Encoding UTF8 | ConvertFrom-Json
  $missing = @()
  foreach ($asset in @($ontology.assets.PSObject.Properties)) { if (-not $text.Contains("| $($asset.Name) |")) { $missing += $asset.Name } }
  Add-Case 'report lists every ontology asset' ($missing.Count -eq 0) ($missing -join ',')
}
$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'capability-report'; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0
