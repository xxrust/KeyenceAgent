param([string]$WorkRoot = '', [string]$SampleProjectPath = 'C:\kvrun\snapshot_sample\KVX样例程序_v100\KVX样例程序_v100.kpr')

$ErrorActionPreference = 'Stop'

# Regression for the fabricated-expansion-unit bug in export_kv_project_inventory.ps1.
# Uses the real sample project when present: expansion units must be 0 (the three
# KV-EC01 items are EtherCAT slave nodes 4/5/6, not units). Skips when the sample
# is not on this machine.

$tool = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\scripts\export_kv_project_inventory.ps1'))
. (Join-Path $PSScriptRoot '..\_helpers\invoke_tool.ps1')
if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw "tool not found: $tool" }

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-inventory-expansion-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}

if (-not (Test-Path -LiteralPath $SampleProjectPath -PathType Leaf)) {
  Add-Case 'sample project available' $true 'skipped: sample project not found'
  $result = [ordered]@{ test = 'inventory-expansion'; skipped = $true; passed = 1; failed = 0; cases = $cases.ToArray(); work_root = $WorkRoot }
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
  $result | ConvertTo-Json -Depth 3
  exit 0
}

$outDir = Join-Path $WorkRoot 'inventory'
$exit = Invoke-TestTool -ScriptPath $tool -Arguments @('-ProjectPath', $SampleProjectPath, '-OutDir', $outDir)
$reportPath = Join-Path $outDir 'project_inventory.json'
Add-Case 'inventory exits 0' ($exit -eq 0) "exit=$exit"
Add-Case 'inventory written' (Test-Path -LiteralPath $reportPath) $reportPath
if (Test-Path -LiteralPath $reportPath) {
  $report = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $expansion = @($report.topology.expansion_units)
  Add-Case 'no fabricated expansion units' ($expansion.Count -eq 0) "count=$($expansion.Count)"
  $nodes = @($report.topology.ethercat.nodes)
  Add-Case '32 EtherCAT nodes' ($nodes.Count -eq 32) "count=$($nodes.Count)"
  $ec01 = @($nodes | Where-Object { [string]$_.device_name -eq 'KV-EC01' } | ForEach-Object { [int]$_.node })
  Add-Case 'KV-EC01 stays at EtherCAT nodes 4/5/6' ((($ec01 -join ',') -eq '4,5,6')) ($ec01 -join ',')
  Add-Case 'CPU slot 0 model KV-X520' (([int]$report.topology.cpu.slot -eq 0) -and ([string]$report.topology.cpu.model -eq 'KV-X520')) "$($report.topology.cpu.slot)/$($report.topology.cpu.model)"
}

  $taxonomyGate = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\scripts\gates\assert_kv_asset_taxonomy.ps1'))
  & powershell -NoProfile -ExecutionPolicy Bypass -File $taxonomyGate -InventoryPath $reportPath -OutDir (Join-Path $WorkRoot 'taxonomy') | Out-Null
  Add-Case 'taxonomy gate accepts the real inventory' ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"
  $badStatusPath = Join-Path $WorkRoot 'inventory_bad_status.json'
  $badStatus = Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $badStatus.asset_status.plc_expansion_units = 'missing'
  $badStatus | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $badStatusPath -Encoding UTF8
  & powershell -NoProfile -ExecutionPolicy Bypass -File $taxonomyGate -InventoryPath $badStatusPath -OutDir (Join-Path $WorkRoot 'taxonomy_bad_status') | Out-Null
  Add-Case 'taxonomy rejects 0 units with status missing' ($LASTEXITCODE -eq 41) "exit=$LASTEXITCODE"
  $badModelsPath = Join-Path $WorkRoot 'models_bad.json'
  $badModels = Get-Content -LiteralPath (Join-Path $PSScriptRoot '..\..\assets\models.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $badModels.models.'KV-EC01'.asset_class = 'cpu_expansion_unit'
  $badModels | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $badModelsPath -Encoding UTF8
  & powershell -NoProfile -ExecutionPolicy Bypass -File $taxonomyGate -InventoryPath $reportPath -ModelsPath $badModelsPath -OutDir (Join-Path $WorkRoot 'taxonomy_bad_model') | Out-Null
  Add-Case 'taxonomy rejects KV-EC01 as a CPU expansion unit' ($LASTEXITCODE -eq 41) "exit=$LASTEXITCODE"
$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'inventory-expansion'; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0


