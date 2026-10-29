param(
  [string]$OntologyPath = '',
  [string]$OutDir = ''
)
# Asset-coverage gate: the ontology is the single source of truth for "which
# assets exist, which capability produces them, which snapshot stage carries
# them". It fails when a wired asset has no stage, a stage has no producer, a
# capability points at a missing script, or a relation references an unknown id.
$ErrorActionPreference = 'Stop'
$scriptsRoot = Split-Path -Parent $PSScriptRoot
$skillRoot = Split-Path -Parent $scriptsRoot
if (-not $OntologyPath) { $OntologyPath = Join-Path $skillRoot 'assets\ontology.json' }
if (-not $OutDir) { $OutDir = Join-Path $env:TEMP ('kv_asset_coverage_' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$errors = New-Object System.Collections.Generic.List[object]
function Add-Error([string]$Code, [string]$Id, [string]$Message) {
  $errors.Add([pscustomobject]@{ code = $Code; id = $Id; message = $Message })
}
if (-not (Test-Path -LiteralPath $OntologyPath -PathType Leaf)) { throw "KV_ONTOLOGY_MISSING: $OntologyPath" }
$ontology = Get-Content -Raw -LiteralPath $OntologyPath -Encoding UTF8 | ConvertFrom-Json
$assets = @($ontology.assets.PSObject.Properties)
$stages = @($ontology.stages.PSObject.Properties)
$capabilities = @($ontology.capabilities.PSObject.Properties)
$assetIds = @($assets | ForEach-Object { $_.Name })
$stageIds = @($stages | ForEach-Object { $_.Name })
$capabilityIds = @($capabilities | ForEach-Object { $_.Name })
$statuses = @('wired', 'wired_limited', 'not_wired', 'missing_route')
foreach ($asset in $assets) {
  $id = $asset.Name
  $value = $asset.Value
  $status = [string]$value.snapshot_status
  if ($statuses -notcontains $status) { Add-Error 'KV_ASSET_STATUS_INVALID' $id "snapshot_status '$status' is not one of $($statuses -join ',')" }
  if ($status -in @('wired', 'wired_limited')) {
    if (-not [string]$value.snapshot_stage) { Add-Error 'KV_ASSET_STAGE_MISSING' $id 'wired asset has no snapshot_stage' }
    elseif ($stageIds -notcontains [string]$value.snapshot_stage) { Add-Error 'KV_ASSET_STAGE_UNKNOWN' $id "snapshot_stage '$($value.snapshot_stage)' is not declared in stages" }
    if (-not [string]$value.snapshot_artifact) { Add-Error 'KV_ASSET_ARTIFACT_MISSING' $id 'wired asset has no snapshot_artifact' }
  } else {
    if (-not [string]$value.missing_reason) { Add-Error 'KV_ASSET_MISSING_REASON' $id 'unwired asset must explain missing_reason' }
  }
  if (-not [string]$value.restore_strategy) { Add-Error 'KV_ASSET_RESTORE_STRATEGY' $id 'restore_strategy is required' }
  foreach ($dependency in @($value.depends_on)) {
    if ($dependency -and $assetIds -notcontains [string]$dependency) { Add-Error 'KV_ASSET_DEP_UNKNOWN' $id "depends_on '$dependency' is not an asset" }
  }
}
foreach ($stage in $stages) {
  $producer = [string]$stage.Value.producer
  if (-not $producer) { Add-Error 'KV_STAGE_PRODUCER_MISSING' $stage.Name 'stage has no producer' }
  elseif ($capabilityIds -notcontains $producer) { Add-Error 'KV_STAGE_PRODUCER_UNKNOWN' $stage.Name "producer '$producer' is not a capability" }
}
foreach ($capability in $capabilities) {
  $id = $capability.Name
  $value = $capability.Value
  $scriptPath = Join-Path $scriptsRoot ([string]$value.script)
  if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { Add-Error 'KV_CAPABILITY_SCRIPT_MISSING' $id "script not found: $($value.script)" }
  if (@($value.evidence | Where-Object { $_ }).Count -eq 0) { Add-Error 'KV_CAPABILITY_EVIDENCE_MISSING' $id 'evidence is required' }
  foreach ($assetRef in @($value.assets)) {
    if ($assetIds -notcontains [string]$assetRef) { Add-Error 'KV_CAPABILITY_ASSET_UNKNOWN' $id "asset '$assetRef' is not declared" }
  }
}
foreach ($relation in @($ontology.relations)) {
  foreach ($endpoint in @([string]$relation.from, [string]$relation.to)) {
    if ($endpoint -notmatch '^(asset|capability|stage):(.+)$') { Add-Error 'KV_RELATION_ENDPOINT_INVALID' $endpoint 'endpoint must be asset:/capability:/stage: id'; continue }
    $kind = $matches[1]; $id = $matches[2]
    $known = if ($kind -eq 'asset') { $assetIds } elseif ($kind -eq 'capability') { $capabilityIds } else { $stageIds }
    if ($known -notcontains $id) { Add-Error 'KV_RELATION_ENDPOINT_UNKNOWN' $endpoint "unknown $kind '$id'" }
  }
  if (-not [string]$relation.type) { Add-Error 'KV_RELATION_TYPE_MISSING' "$($relation.from)->$($relation.to)" 'relation type is required' }
}
$report = [ordered]@{
  ok = ($errors.Count -eq 0)
  ontology_path = $OntologyPath
  asset_count = $assetIds.Count
  stage_count = $stageIds.Count
  capability_count = $capabilityIds.Count
  relation_count = @($ontology.relations).Count
  error_count = $errors.Count
  errors = $errors.ToArray()
}
$reportPath = Join-Path $OutDir 'asset_coverage_result.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 4
if ($errors.Count -gt 0) { exit 41 }
exit 0
