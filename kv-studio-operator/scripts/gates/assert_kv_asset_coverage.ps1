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
$writeCapabilities = @($ontology.write_capabilities.PSObject.Properties)
$writeRecipes = @($ontology.write_acceptance_recipes.PSObject.Properties)
$assetIds = @($assets | ForEach-Object { $_.Name })
$stageIds = @($stages | ForEach-Object { $_.Name })
$capabilityIds = @($capabilities | ForEach-Object { $_.Name })
$writeCapabilityIds = @($writeCapabilities | ForEach-Object { $_.Name })
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
  $portableEvidence = @($value.evidence | Where-Object { $_ -and $_ -notlike 'local:*' })
  if ($portableEvidence.Count -eq 0) { Add-Error 'KV_CAPABILITY_EVIDENCE_NOT_PORTABLE' $id 'at least one repo-relative evidence item is required (prefix machine-local artifacts with local:)' }
  foreach ($assetRef in @($value.assets)) {
    if ($assetIds -notcontains [string]$assetRef) { Add-Error 'KV_CAPABILITY_ASSET_UNKNOWN' $id "asset '$assetRef' is not declared" }
  }
}

# Write routes are cross-checked against the runtime manifest. The ontology may
# describe an approved internal runner, but cannot promote a missing or pending
# script to a published write capability.
$manifestPath = Join-Path $scriptsRoot 'script_manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  Add-Error 'KV_WRITE_MANIFEST_MISSING' 'script_manifest.json' "manifest not found: $manifestPath"
} else {
  $manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
  $manifestEntries = @{}
  foreach ($class in @($manifest.classes.PSObject.Properties)) {
    foreach ($entry in @($class.Value)) {
      if ($entry.path) { $manifestEntries[([string]$entry.path).Replace('\\', '/')] = [string]$entry.status }
    }
  }
  foreach ($writeCapability in $writeCapabilities) {
    $id = $writeCapability.Name
    $value = $writeCapability.Value
    $scriptRelative = ([string]$value.script).Replace('\\', '/')
    if (-not $scriptRelative -or -not $manifestEntries.ContainsKey($scriptRelative)) {
      Add-Error 'KV_WRITE_SCRIPT_UNPUBLISHED' $id "script is not declared in manifest: $scriptRelative"
    } else {
      $manifestStatus = $manifestEntries[$scriptRelative]
      $declaredStatus = if ($value.validation_status) { [string]$value.validation_status } else { 'published' }
      if ($manifestStatus -notin @('published', 'approved') -or $manifestStatus -ne $declaredStatus) {
        Add-Error 'KV_WRITE_STATUS_MISMATCH' $id "ontology status '$declaredStatus' does not match manifest status '$manifestStatus'"
      }
      if ($manifestStatus -eq 'approved' -and -not [string]$value.validation_scope) {
        Add-Error 'KV_WRITE_APPROVED_SCOPE_MISSING' $id 'approved non-customer route must disclose its validation scope'
      }
    }
    if (-not (Test-Path -LiteralPath (Join-Path $scriptsRoot $scriptRelative) -PathType Leaf)) {
      Add-Error 'KV_WRITE_SCRIPT_MISSING' $id "script not found: $scriptRelative"
    }
    if (@($value.assets).Count -eq 0) { Add-Error 'KV_WRITE_ASSETS_MISSING' $id 'write capability must declare target assets' }
    if (@($value.inputs | Where-Object { $_ }).Count -eq 0) { Add-Error 'KV_WRITE_INPUTS_MISSING' $id 'write capability must declare its input contract' }
    if (@($value.outputs | Where-Object { $_ }).Count -eq 0) { Add-Error 'KV_WRITE_OUTPUTS_MISSING' $id 'write capability must declare its output evidence' }
    foreach ($assetRef in @($value.assets)) {
      if ($assetIds -notcontains [string]$assetRef) { Add-Error 'KV_WRITE_ASSET_UNKNOWN' $id "asset '$assetRef' is not declared" }
    }
    if (@($value.evidence | Where-Object { $_ }).Count -eq 0) { Add-Error 'KV_WRITE_EVIDENCE_MISSING' $id 'repository evidence is required' }
    foreach ($evidence in @($value.evidence | Where-Object { $_ })) {
      $evidencePath = Join-Path $skillRoot ([string]$evidence)
      if ([IO.Path]::IsPathRooted([string]$evidence) -or -not (Test-Path -LiteralPath $evidencePath)) {
        Add-Error 'KV_WRITE_EVIDENCE_NOT_PORTABLE' $id "evidence must resolve inside the repository: $evidence"
      }
    }
    foreach ($dependency in @($value.depends_on)) {
      if ($dependency -and $writeCapabilityIds -notcontains [string]$dependency) {
        Add-Error 'KV_WRITE_DEPENDENCY_UNKNOWN' $id "depends_on '$dependency' is not a write capability"
      }
    }
  }

  # Kahn's algorithm catches cycles in the write dependency graph.
  $indegree = @{}
  $dependents = @{}
  foreach ($id in $writeCapabilityIds) { $indegree[$id] = 0; $dependents[$id] = @() }
  foreach ($writeCapability in $writeCapabilities) {
    $id = $writeCapability.Name
    foreach ($dependency in @($writeCapability.Value.depends_on)) {
      if ($dependency -and $writeCapabilityIds -contains [string]$dependency) {
        $indegree[$id] = [int]$indegree[$id] + 1
        $dependents[[string]$dependency] += $id
      }
    }
  }
  $ready = New-Object System.Collections.Generic.Queue[string]
  foreach ($id in $writeCapabilityIds) { if ($indegree[$id] -eq 0) { $ready.Enqueue($id) } }
  $visited = 0
  while ($ready.Count -gt 0) {
    $current = $ready.Dequeue(); $visited++
    foreach ($dependent in $dependents[$current]) {
      $indegree[$dependent] = [int]$indegree[$dependent] - 1
      if ($indegree[$dependent] -eq 0) { $ready.Enqueue([string]$dependent) }
    }
  }
  if ($visited -ne $writeCapabilityIds.Count) { Add-Error 'KV_WRITE_DEPENDENCY_CYCLE' 'write_capabilities' 'write dependency graph contains a cycle' }
}

foreach ($recipe in $writeRecipes) {
  $id = $recipe.Name
  $scenarioRelative = [string]$recipe.Value.scenario
  $scenarioPath = Join-Path $skillRoot $scenarioRelative
  if ([IO.Path]::IsPathRooted($scenarioRelative) -or -not (Test-Path -LiteralPath $scenarioPath -PathType Leaf)) {
    Add-Error 'KV_WRITE_RECIPE_SCENARIO_MISSING' $id "scenario must be a repository file: $scenarioRelative"
  }
  if (@($recipe.Value.required_evidence | Where-Object { $_ }).Count -eq 0) { Add-Error 'KV_WRITE_RECIPE_EVIDENCE_MISSING' $id 'required_evidence must describe acceptance outputs' }
  foreach ($requiredCapability in @($recipe.Value.required_capabilities)) {
    if ($writeCapabilityIds -notcontains [string]$requiredCapability) { Add-Error 'KV_WRITE_RECIPE_CAPABILITY_UNKNOWN' $id "required capability '$requiredCapability' is not declared" }
  }
  if (@($recipe.Value.evidence | Where-Object { $_ }).Count -eq 0) { Add-Error 'KV_WRITE_RECIPE_EVIDENCE_MISSING' $id 'repository acceptance evidence is required' }
  foreach ($evidence in @($recipe.Value.evidence | Where-Object { $_ })) {
    $evidencePath = Join-Path $skillRoot ([string]$evidence)
    if ([IO.Path]::IsPathRooted([string]$evidence) -or -not (Test-Path -LiteralPath $evidencePath -PathType Leaf)) {
      Add-Error 'KV_WRITE_RECIPE_EVIDENCE_NOT_PORTABLE' $id "acceptance evidence must be a repository file: $evidence"
    }
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
# Cross-check status against capabilities so "snapshot missing" can never be
# recorded as "capability missing" again:
#   wired / wired_limited -> must have a capability covering the asset
#   not_wired             -> must have a capability (only the stage is missing)
#   missing_route         -> must have NO capability (otherwise it is not_wired)
$capabilitiesByAsset = @{}
foreach ($capability in $capabilities) {
  foreach ($assetRef in @($capability.Value.assets)) {
    if (-not $capabilitiesByAsset.ContainsKey([string]$assetRef)) { $capabilitiesByAsset[[string]$assetRef] = @() }
    $capabilitiesByAsset[[string]$assetRef] += $capability.Name
  }
}
foreach ($asset in $assets) {
  $id = $asset.Name
  $status = [string]$asset.Value.snapshot_status
  $cover = @($capabilitiesByAsset[$id] | Where-Object { $_ })
  if ($status -in @('wired', 'wired_limited') -and $cover.Count -eq 0) {
    Add-Error 'KV_ASSET_WIRED_WITHOUT_CAPABILITY' $id 'wired asset has no capability that produces it'
  }
  if ($status -eq 'not_wired' -and $cover.Count -eq 0) {
    Add-Error 'KV_ASSET_NOT_WIRED_WITHOUT_CAPABILITY' $id 'not_wired means the capability exists; add it or use missing_route'
  }
  if ($status -eq 'missing_route' -and $cover.Count -gt 0) {
    Add-Error 'KV_ASSET_MISSING_ROUTE_WITH_CAPABILITY' $id ("capability already covers this asset: " + ($cover -join ', ') + '; use not_wired instead of claiming no route')
  }
}
$report = [ordered]@{
  ok = ($errors.Count -eq 0)
  ontology_path = $OntologyPath
  asset_count = $assetIds.Count
  stage_count = $stageIds.Count
  capability_count = $capabilityIds.Count
  write_capability_count = $writeCapabilityIds.Count
  write_recipe_count = $writeRecipes.Count
  relation_count = @($ontology.relations).Count
  error_count = $errors.Count
  errors = $errors.ToArray()
}
$reportPath = Join-Path $OutDir 'asset_coverage_result.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 4
if ($errors.Count -gt 0) { exit 41 }
exit 0
