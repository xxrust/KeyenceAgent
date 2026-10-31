param(
  [string]$SnapshotRunPath = '',
  [switch]$Record,
  [string]$OutDir = ''
)
$ErrorActionPreference = 'Stop'
$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
if (-not $OutDir) { $OutDir = Join-Path $env:TEMP ('kv-live-acceptance-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') { $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail }) }
if (-not $SnapshotRunPath) {
  $runsRoot = Join-Path $skillRoot 'tests\kv-interface-regression\runs'
  $latest = Get-ChildItem -LiteralPath $runsRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^13_project_text_snapshot_' } | Sort-Object LastWriteTime -Descending | Select-Object -First 1
  if ($latest) { $SnapshotRunPath = $latest.FullName }
}
Add-Case 'snapshot run found' ([bool]$SnapshotRunPath -and (Test-Path -LiteralPath $SnapshotRunPath)) $SnapshotRunPath
$recordPath = Join-Path $skillRoot 'tests\live_acceptance\latest.json'
if ($Record -and $SnapshotRunPath) {
  $snapshot = Join-Path $SnapshotRunPath 'workflow\snapshot'
  $manifestPath = Join-Path $snapshot 'source_snapshot_manifest.json'
  $inventoryPath = Join-Path $snapshot 'text\project_inventory.json'
  if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
    $stages = @($manifest.workflow_status)
    $stageOk = @($stages | Where-Object { $_.ok }).Count
    $inventory = $null
    if (Test-Path -LiteralPath $inventoryPath -PathType Leaf) { $inventory = Get-Content -Raw -LiteralPath $inventoryPath -Encoding UTF8 | ConvertFrom-Json }
    $kvs = 'H:\Keyence\KVS12\KVS\Kvs.exe'
    $kvsVersion = if (Test-Path -LiteralPath $kvs) { (Get-Item -LiteralPath $kvs).VersionInfo.FileVersion } else { 'unknown' }
    $autoReady = $false; $manualReady = $false; $gaps = @()
    if ($inventory) {
      $autoReady = [bool]$inventory.clone_readiness.ready_for_full_1_to_1_import
      $manualReady = [bool]$inventory.clone_readiness.ready_for_manual_1_to_1_rebuild
      $gaps = @($inventory.clone_readiness.blocking_gaps | ForEach-Object { $_.id })
    }
    $recordData = [ordered]@{
      recorded_at = (Get-Date).ToString('o')
      run_dir = $SnapshotRunPath
      snapshot_status = [string]$manifest.status
      stage_ok = $stageOk
      stage_total = $stages.Count
      ready_for_full_1_to_1_import = $autoReady
      ready_for_manual_1_to_1_rebuild = $manualReady
      blocking_gaps = $gaps
      kvs_version = $kvsVersion
      os = [Environment]::OSVersion.VersionString
      pdo_nodes = 0
      eip_connections = 0
      eip_assignments = 0
    }
    $pdoIndex = Join-Path $snapshot 'project\配置\EtherCAT\pdo_index.json'
    if (Test-Path -LiteralPath $pdoIndex) { $recordData.pdo_nodes = [int](Get-Content -Raw -LiteralPath $pdoIndex -Encoding UTF8 | ConvertFrom-Json).node_count }
    $assignments = Join-Path $snapshot 'project\配置\EtherNetIP\assignments'
    if (Test-Path -LiteralPath $assignments) { $recordData.eip_assignments = @(Get-ChildItem -LiteralPath $assignments -Filter '*.json' -ErrorAction SilentlyContinue).Count }
    $connectionsPath = Join-Path $snapshot 'project\配置\EtherNetIP\connections.json'
    if (Test-Path -LiteralPath $connectionsPath) { $recordData.eip_connections = [int](Get-Content -Raw -LiteralPath $connectionsPath -Encoding UTF8 | ConvertFrom-Json).connection_count }
    New-Item -ItemType Directory -Force -Path (Split-Path -Parent $recordPath) | Out-Null
    $recordData | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $recordPath -Encoding UTF8
  }
}
$recordExists = Test-Path -LiteralPath $recordPath -PathType Leaf
Add-Case 'live acceptance record exists' $recordExists $recordPath
if ($recordExists) {
  $rec = Get-Content -Raw -LiteralPath $recordPath -Encoding UTF8 | ConvertFrom-Json
  Add-Case 'recorded snapshot was ready' ([string]$rec.snapshot_status -eq 'ready') $rec.snapshot_status
  Add-Case 'all recorded stages were ok' ([int]$rec.stage_ok -eq [int]$rec.stage_total) "$($rec.stage_ok)/$($rec.stage_total)"
  Add-Case 'record has KVS version and OS' (([string]$rec.kvs_version) -and ([string]$rec.os)) "$($rec.kvs_version) / $($rec.os)"
}
$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'live-acceptance'; record_path = $recordPath; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $OutDir }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0
