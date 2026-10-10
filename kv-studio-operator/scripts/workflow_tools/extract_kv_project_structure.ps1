param(
  [Parameter(Mandatory=$true)][string]$SnapshotRoot,
  [Parameter(Mandatory=$true)][string]$OutPath,
  [string]$PatternMapPath = '',
  [string]$ProjectSourcePath = ''
)
$ErrorActionPreference = 'Stop'
# -SnapshotRoot must be the directory that directly contains text\ and project\.
# Say so here instead of letting callers guess the level from a downstream error.
$snapshotRootPath = [IO.Path]::GetFullPath($SnapshotRoot)
if (-not (Test-Path -LiteralPath (Join-Path $snapshotRootPath 'text') -PathType Container) -or -not (Test-Path -LiteralPath (Join-Path $snapshotRootPath 'project') -PathType Container)) {
  throw "KV_SNAPSHOT_ROOT_LEVEL_WRONG: -SnapshotRoot must be the directory that directly contains 'text' and 'project'. Received: $SnapshotRoot . Example: <work>\snapshot-run\snapshot (the level holding text, project, raw and architecture)."
}

# Extracts the structural shape of a project from a read-only semantic snapshot, so a
# project can be compared against the house standard without touching KV STUDIO.
$snapshotRoot = [IO.Path]::GetFullPath($SnapshotRoot)
$manifestPath = Join-Path $snapshotRoot 'source_snapshot_manifest.json'
$inventoryPath = Join-Path $snapshotRoot 'text\project_inventory.json'
foreach ($p in @($manifestPath, $inventoryPath)) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "KV_STRUCTURE_INPUT_MISSING: $p" }
}
if (-not $PatternMapPath) {
  $PatternMapPath = Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'references\project-standard.patterns.json'
}
if (-not (Test-Path -LiteralPath $PatternMapPath -PathType Leaf)) { throw "KV_STRUCTURE_PATTERNS_MISSING: $PatternMapPath" }

$manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
$inventory = Get-Content -Raw -LiteralPath $inventoryPath -Encoding UTF8 | ConvertFrom-Json
$patterns = Get-Content -Raw -LiteralPath $PatternMapPath -Encoding UTF8 | ConvertFrom-Json

function Get-Bucket([string]$Name, [object]$Buckets) {
  foreach ($b in $Buckets) {
    if ($Name -match [string]$b.pattern) { return [string]$b.bucket }
  }
  return 'other'
}

$programs = New-Object System.Collections.Generic.List[object]
$bucketCounts = [ordered]@{}
foreach ($m in @($inventory.program_modules)) {
  $bucket = Get-Bucket ([string]$m.module_name) $patterns.buckets
  if (-not $bucketCounts.Contains($bucket)) { $bucketCounts[$bucket] = 0 }
  $bucketCounts[$bucket]++
  $programs.Add([pscustomobject]@{
      name = [string]$m.module_name
      category = [string]$m.category
      execution_order = $m.execution_order
      bucket = $bucket
      tree_path = @($m.tree_path)
    }) | Out-Null
}

$fbNames = @($inventory.official_or_library_names_from_tree | Where-Object { $_ -notmatch '^_' })
$systemTypeNamesInTree = @($inventory.official_or_library_names_from_tree | Where-Object { $_ -match '^_' })
$fbNameSourceNote = 'official_or_library_names_from_tree mixes FB names with system data type names: function_blocks keeps the non-underscore entries, system_type_names_in_tree keeps the underscore ones, and neither list contains the built-in motion FBs that programs call (see resolve_kv_symbols invocations)'
$userTypes = @(@($inventory.data_types) | Where-Object { $_.path_text -notmatch '\(System\)' } | ForEach-Object { [string]$_.name })
# System types were previously filtered out of the extractor, which hid the most
# important semantic layer of a motion project (_MC_POINT_PARAM, _MC_AXIS_*, _EC_*).
# They are now reported explicitly, together with what the type routes do NOT export.
$systemTypes = @(@($inventory.data_types) | Where-Object { $_.path_text -match '\(System\)' } | ForEach-Object { [string]$_.name })

# Motion settings live in the project's WsTreeEnv.xml and are not materialized by any
# snapshot route, so a bare not_found would be a false statement about the project.
$motionStatus = 'unknown_route_not_populated'
$motionAxes = New-Object System.Collections.Generic.List[string]
$motionEvidence = New-Object System.Collections.Generic.List[string]
$motionChecked = New-Object System.Collections.Generic.List[string]
$motionChecked.Add('inventory.topology.motion') | Out-Null
if ($inventory.topology.motion.status) { $motionChecked.Add('inventory.topology.motion.status=' + [string]$inventory.topology.motion.status) | Out-Null }
$motionChecked.Add('snapshot_project_tree_entities') | Out-Null
if ($ProjectSourcePath -and (Test-Path -LiteralPath $ProjectSourcePath -PathType Container)) {
  $wsTree = Join-Path $ProjectSourcePath 'WsTreeEnv.xml'
  if (Test-Path -LiteralPath $wsTree -PathType Leaf) {
    $motionChecked.Add('project_ws_tree_env') | Out-Null
    $xml = Get-Content -Raw -LiteralPath $wsTree -Encoding UTF8
    if ($xml -match [string]$patterns.motion.treeRootPattern) {
      $motionStatus = 'tree_summary_extracted'
      $motionEvidence.Add('WsTreeEnv.xml') | Out-Null
      foreach ($m in [regex]::Matches($xml, [string]$patterns.motion.axisPattern)) {
        if (-not $motionAxes.Contains($m.Groups[1].Value)) { $motionAxes.Add($m.Groups[1].Value) | Out-Null }
      }
    }
  } else {
    $motionChecked.Add('project_ws_tree_env_missing') | Out-Null
  }
} else {
  $motionChecked.Add('project_source_path_not_supplied') | Out-Null
}$structure = [ordered]@{
  schema_version = 1
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  source = [ordered]@{
    snapshot_root = $snapshotRoot
    project_path = [string]$manifest.project.path
    project_fingerprint = [string]$manifest.project.fingerprint.hash
    snapshot_status = [string]$manifest.status
    pattern_map = [IO.Path]::GetFullPath($PatternMapPath)
  }
  hardware = [ordered]@{
    cpu = [string]$inventory.topology.cpu.model
    expansion_units = @($inventory.topology.expansion_units | ForEach-Object { [string]$_.device_name })
    ethercat_nodes = @($inventory.topology.ethercat.nodes | ForEach-Object { [string]$_.device_name })
    ethernet_ip_devices = @($inventory.topology.ethernet_ip.devices | ForEach-Object { [string]$_.device_name })
    ethernet_ip_relay_start = [string]$inventory.topology.ethernet_ip.relay_start
    ethernet_ip_dm_start = [string]$inventory.topology.ethernet_ip.dm_start
    motion_status = $motionStatus
    motion = [ordered]@{
      status = $motionStatus
      axes = [string[]]$motionAxes.ToArray()
      evidence = [string[]]$motionEvidence.ToArray()
      checked_sources = [string[]]$motionChecked.ToArray()
      note = 'snapshot routes do not materialize the motion subtree; pass -ProjectSourcePath to read WsTreeEnv.xml'
    }
  }
  programs = $programs.ToArray()
  program_count = $programs.Count
  function_blocks = $fbNames
  system_type_names_in_tree = $systemTypeNamesInTree
  fb_name_source_note = $fbNameSourceNote
  user_data_types = $userTypes
  system_data_types = $systemTypes
  data_type_counts = [ordered]@{ user = $userTypes.Count; system = $systemTypes.Count }
  data_type_notes = 'structure_definitions.json exports user-defined types only; system type member lists (for example _MC_POINT_PARAM fields) are not exported by that route and must come from the manual or from program usage'
  stations = @($programs | Where-Object { $_.bucket -eq 'station' } | ForEach-Object { $_.name })
  naming_buckets = $bucketCounts
  notes = @(
    'Buckets come from references/project-standard.patterns.json; other means the name matches no house convention.',
    'This file is derived evidence, not the standard itself; the standard is references/project-standard.json.'
  )
}
$json = $structure | ConvertTo-Json -Depth 10
$parent = Split-Path -Parent ([IO.Path]::GetFullPath($OutPath))
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
[IO.File]::WriteAllText([IO.Path]::GetFullPath($OutPath), $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Output $json
