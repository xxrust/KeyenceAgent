param(
  [string]$InventoryPath = '',
  [string]$ModelsPath = '',
  [string]$OutDir = ''
)
# Taxonomy gate: models are instances, not asset classes. It rejects
# KV-EC01-style misclassification (EtherCAT slave filed as CPU expansion unit)
# and status claims that contradict the inventory counts.
$ErrorActionPreference = 'Stop'
$scriptsRoot = Split-Path -Parent $PSScriptRoot
$skillRoot = Split-Path -Parent $scriptsRoot
if (-not $ModelsPath) { $ModelsPath = Join-Path $skillRoot 'assets\models.json' }
if (-not $OutDir) { $OutDir = Join-Path $env:TEMP ('kv_asset_taxonomy_' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$errors = New-Object System.Collections.Generic.List[object]
function Add-Error([string]$Code, [string]$Id, [string]$Message) { $errors.Add([pscustomobject]@{ code = $Code; id = $Id; message = $Message }) }
if (-not (Test-Path -LiteralPath $ModelsPath -PathType Leaf)) { throw "KV_MODELS_REGISTRY_MISSING: $ModelsPath" }
$registry = Get-Content -Raw -LiteralPath $ModelsPath -Encoding UTF8 | ConvertFrom-Json
$allowed = @($registry.allowed_classes)
$models = @{}
foreach ($entry in @($registry.models.PSObject.Properties)) { $models[$entry.Name] = $entry.Value }
foreach ($entry in $models.Keys) {
  $class = [string]$models[$entry].asset_class
  if ($allowed -notcontains $class) { Add-Error 'KV_MODEL_CLASS_INVALID' $entry "asset_class '$class' is not allowed" }
}
if ($models.ContainsKey('KV-EC01') -and [string]$models['KV-EC01'].asset_class -ne 'ethercat_slave') {
  Add-Error 'KV_KNOWN_MODEL_MISCLASSIFIED' 'KV-EC01' 'KV-EC01 is an EtherCAT slave and must not be filed as a CPU expansion unit'
}
$inventory = $null
if ($InventoryPath -and (Test-Path -LiteralPath $InventoryPath -PathType Leaf)) {
  $inventory = Get-Content -Raw -LiteralPath $InventoryPath -Encoding UTF8 | ConvertFrom-Json
} elseif ($InventoryPath) {
  Add-Error 'KV_INVENTORY_MISSING' $InventoryPath 'inventory path does not exist'
}
if ($inventory) {
  $units = @($inventory.topology.expansion_units)
  $unitStatus = [string]$inventory.asset_status.plc_expansion_units
  if ($units.Count -eq 0 -and $unitStatus -notin @('none_present', 'none', '')) {
    Add-Error 'KV_EXPANSION_STATUS_MISMATCH' 'plc_expansion_units' "inventory has 0 expansion units but status is '$unitStatus'; expected none_present"
  }
  if ($units.Count -gt 0 -and $unitStatus -notin @('captured', 'ui_read_complete')) {
    Add-Error 'KV_EXPANSION_STATUS_MISMATCH' 'plc_expansion_units' "inventory has $($units.Count) expansion units but status is '$unitStatus'; expected captured"
  }
  foreach ($node in @($inventory.topology.ethercat.nodes)) {
    $model = [string]$node.device_name
    if (-not $model) { continue }
    if (-not $models.ContainsKey($model)) { Add-Error 'KV_MODEL_UNCLASSIFIED' $model 'EtherCAT node model is not in assets/models.json'; continue }
    if ([string]$models[$model].asset_class -ne 'ethercat_slave') {
      Add-Error 'KV_MODEL_CLASS_CONFLICT' $model ("model class is '" + $models[$model].asset_class + "' but it appears as an EtherCAT node")
    }
  }
  foreach ($device in @($inventory.topology.ethernet_ip.devices)) {
    $model = [string]$device.node_name
    if (-not $model) { continue }
    if ($models.ContainsKey($model) -and [string]$models[$model].asset_class -ne 'eip_node') {
      Add-Error 'KV_MODEL_CLASS_CONFLICT' $model ("model class is '" + $models[$model].asset_class + "' but it appears as an EtherNet/IP device")
    }
  }
  foreach ($gap in @($inventory.clone_readiness.blocking_gaps)) {
    $gapId = [string]$gap.id
    if (-not $gapId) { continue }
    if ($gapId -eq 'plc_expansion_units' -and @($inventory.topology.expansion_units).Count -eq 0) {
      Add-Error 'KV_GAP_CONTRADICTS_INVENTORY' $gapId 'blocking gap says expansion units are missing but the topology has none'
    }
    if ($gapId -eq 'ethercat_pdo' -and [string]$inventory.asset_status.ethercat_pdo -eq 'ui_read_complete') {
      Add-Error 'KV_GAP_CONTRADICTS_INVENTORY' $gapId 'blocking gap says PDO is missing but status is ui_read_complete'
    }
    if ($gapId -eq 'ethercat_device_parameters' -and [string]$inventory.asset_status.ethercat_device_parameters -eq 'structured') {
      Add-Error 'KV_GAP_CONTRADICTS_INVENTORY' $gapId 'blocking gap says parameters are unstructured but status is structured'
    }
  }
}
$report = [ordered]@{
  ok = ($errors.Count -eq 0)
  models_path = $ModelsPath
  inventory_path = $InventoryPath
  model_count = $models.Count
  error_count = $errors.Count
  errors = $errors.ToArray()
}
$reportPath = Join-Path $OutDir 'asset_taxonomy_result.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 5
if ($errors.Count -gt 0) { exit 41 }
exit 0
