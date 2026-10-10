param(
  [Parameter(Mandatory=$true)][string]$SnapshotRoot,
  [Parameter(Mandatory=$true)][string]$OutPath,
  [string]$PatternMapPath = ''
)
$ErrorActionPreference = 'Stop'

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
$userTypes = @(@($inventory.data_types) | Where-Object { $_.path_text -notmatch '\(System\)' } | ForEach-Object { [string]$_.name })

$structure = [ordered]@{
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
    motion_status = [string]$inventory.topology.motion.status
  }
  programs = $programs.ToArray()
  program_count = $programs.Count
  function_blocks = $fbNames
  user_data_types = $userTypes
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
