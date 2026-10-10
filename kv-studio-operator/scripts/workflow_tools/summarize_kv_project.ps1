param(
  [Parameter(Mandatory=$true)][string]$SnapshotRoot,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$LabelsPath = ''
)
$ErrorActionPreference = 'Stop'
# -SnapshotRoot must be the directory that directly contains text\ and project\.
# Say so here instead of letting callers guess the level from a downstream error.
$snapshotRootPath = [IO.Path]::GetFullPath($SnapshotRoot)
if (-not (Test-Path -LiteralPath (Join-Path $snapshotRootPath 'text') -PathType Container) -or -not (Test-Path -LiteralPath (Join-Path $snapshotRootPath 'project') -PathType Container)) {
  throw "KV_SNAPSHOT_ROOT_LEVEL_WRONG: -SnapshotRoot must be the directory that directly contains 'text' and 'project'. Received: $SnapshotRoot . Example: <work>\snapshot-run\snapshot (the level holding text, project, raw and architecture)."
}
$snapshotRoot = [IO.Path]::GetFullPath($SnapshotRoot)
$outRoot = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
$skillRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
if (-not $LabelsPath) { $LabelsPath = Join-Path $skillRoot 'references\project-summary.labels.json' }
if (-not (Test-Path -LiteralPath $LabelsPath -PathType Leaf)) { throw "KV_SUMMARY_LABELS_MISSING: $LabelsPath" }
$labels = Get-Content -Raw -LiteralPath $LabelsPath -Encoding UTF8 | ConvertFrom-Json

# Reuse the structure extractor so the summary and the standard share one definition
# of buckets, stations and module shape.
$structurePath = Join-Path $outRoot 'structure.json'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'extract_kv_project_structure.ps1') `
  -SnapshotRoot $snapshotRoot -OutPath $structurePath | Out-Null
if (-not (Test-Path -LiteralPath $structurePath -PathType Leaf)) { throw 'KV_SUMMARY_STRUCTURE_FAILED' }
$structure = Get-Content -Raw -LiteralPath $structurePath -Encoding UTF8 | ConvertFrom-Json
$manifest = Get-Content -Raw -LiteralPath (Join-Path $snapshotRoot 'source_snapshot_manifest.json') -Encoding UTF8 | ConvertFrom-Json

# Optional layers: the comment/coverage layer and the annotated usage table.
$coverage = $null
$coveragePath = Join-Path $snapshotRoot 'text\comments\coverage.json'
if (Test-Path -LiteralPath $coveragePath -PathType Leaf) { try { $coverage = Get-Content -Raw -LiteralPath $coveragePath -Encoding UTF8 | ConvertFrom-Json } catch { } }
$externalWriters = @()
if ($coverage) { $externalWriters = @($coverage.annotated_unused_handwritten) }

# Resolve the Modbus data area from the program bodies instead of pointing at another file.
$modbusInfo = [ordered]@{
  status = 'not_found'; fb = ''; instance = ''; data_area = ''; arguments = @()
  reason = 'no ModbusTCPClient_* invocation found in the snapshot bodies'
}
$modbusMnmDir = Join-Path $snapshotRoot 'text\mnm'
foreach ($mbFile in @(Get-ChildItem -LiteralPath $modbusMnmDir -Filter '*.mnm' -File -Recurse -ErrorAction SilentlyContinue)) {
  $mbBytes = [IO.File]::ReadAllBytes($mbFile.FullName)
  $mbText = if ($mbBytes.Length -ge 2 -and $mbBytes[0] -eq 0xFF -and $mbBytes[1] -eq 0xFE) { [Text.Encoding]::Unicode.GetString($mbBytes, 2, $mbBytes.Length - 2) } else { [Text.Encoding]::GetEncoding(936).GetString($mbBytes) }
  foreach ($mbMatch in [regex]::Matches($mbText, '(?m)^(FBEXEC|FBEAND)\s+(ModbusTCPClient_\w+)\s+(\S+)\s*(.*)$')) {
    $fbArgs = @($mbMatch.Groups[4].Value -split '\s+' | Where-Object { $_ })
    $dmArg = @($fbArgs | Where-Object { $_ -match '^DM\d+$' } | Select-Object -First 1)
    if ($dmArg.Count -eq 0) {
      # keep the first invocation as a fallback, but prefer one that carries the data area
      if ($modbusInfo.status -eq 'not_found') {
        $modbusInfo.status = 'resolved_without_data_area'
        $modbusInfo.fb = $mbMatch.Groups[2].Value
        $modbusInfo.instance = $mbMatch.Groups[3].Value
        $modbusInfo.arguments = $fbArgs
        $modbusInfo.reason = 'no DM data area argument found in any ModbusTCPClient_* invocation'
      }
      continue
    }
    $modbusInfo.status = 'resolved'
    $modbusInfo.fb = $mbMatch.Groups[2].Value
    $modbusInfo.instance = $mbMatch.Groups[3].Value
    $modbusInfo.data_area = $dmArg[0]
    $modbusInfo.arguments = $fbArgs
    $modbusInfo.reason = ''
    break
  }
}
$interfaces = [ordered]@{
  external_writer_candidates = $externalWriters
  external_writer_count = $externalWriters.Count
  unit_io_relay_start = [string]$structure.hardware.ethernet_ip_relay_start
  unit_io_dm_start = [string]$structure.hardware.ethernet_ip_dm_start
  modbus_area = $modbusInfo.data_area
  modbus = $modbusInfo
}
$gaps = [ordered]@{
  unannotated_referenced = $(if ($coverage) { [int]$coverage.summary.used_unannotated } else { $null })
  comment_rows_total = $(if ($coverage) { [int]$coverage.summary.comment_rows_total } else { $null })
  comment_devices_total = $(if ($coverage) { [int]$coverage.summary.comment_entries_total } else { $null })
  station_partition = $(if (@($structure.stations).Count -eq 0) { 'none' } else { 'present' })
  naming_other_count = [int]$structure.naming_buckets.other
}

$summary = [ordered]@{
  schema_version = 1
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  source = [ordered]@{ snapshot_root = $snapshotRoot; structure_path = $structurePath; coverage_path = $(if ($coverage) { $coveragePath } else { '' }) }
  identity = [ordered]@{ project = [string]$manifest.project.path; fingerprint = [string]$manifest.project.fingerprint.hash; snapshot_status = [string]$manifest.status }
  hardware = $structure.hardware
  stations = @($structure.stations)
  programs = @($structure.programs)
  function_blocks = @($structure.function_blocks)
  user_data_types = @($structure.user_data_types)
  naming_buckets = $structure.naming_buckets
  interfaces = $interfaces
  gaps = $gaps
  notes = @($labels.notes)
}
[IO.File]::WriteAllText((Join-Path $outRoot 'project_summary.json'), ($summary | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))

# Human-readable report built from the labels file plus derived data only.
$L = $labels.fields
$S = $labels.sections
$md = New-Object System.Collections.Generic.List[string]
$md.Add('# ' + $labels.title)
$md.Add('')
$md.Add('## ' + $S.identity)
$md.Add('')
$md.Add('- ' + $L.project + ': `' + $summary.identity.project + '`')
$md.Add('- ' + $L.fingerprint + ': `' + $summary.identity.fingerprint + '`')
$md.Add('- ' + $L.snapshot_status + ': ' + $summary.identity.snapshot_status)
$md.Add('')
$md.Add('## ' + $S.hardware)
$md.Add('')
$md.Add('- ' + $L.cpu + ': ' + $summary.hardware.cpu)
$md.Add('- ' + $L.expansion_units + ': ' + $(if (@($summary.hardware.expansion_units).Count) { @($summary.hardware.expansion_units) -join ', ' } else { $L.empty_note }))
$md.Add('- ' + $L.ethercat + ': ' + $(if (@($summary.hardware.ethercat_nodes).Count) { (@($summary.hardware.ethercat_nodes) | Select-Object -Unique) -join ', ' } else { $L.empty_note }))
$md.Add('- ' + $L.ethernet_ip + ': ' + $(if (@($summary.hardware.ethernet_ip_devices).Count) { @($summary.hardware.ethernet_ip_devices) -join ', ' } else { $L.empty_note }))
if ($summary.hardware.ethernet_ip_relay_start) { $md.Add('- ' + $L.ethernet_ip_area + ': ' + $summary.hardware.ethernet_ip_relay_start + ' / ' + $summary.hardware.ethernet_ip_dm_start) }
$md.Add('- ' + $L.motion + ': ' + $summary.hardware.motion_status)
$md.Add('')
$md.Add('## ' + $S.stations)
$md.Add('')
$md.Add('- ' + $L.station_count + ': ' + @($summary.stations).Count)
if (@($summary.stations).Count) { $md.Add('- ' + $L.station_list + ': ' + (@($summary.stations) -join ', ')) } else { $md.Add('- ' + $L.no_stations) }
$md.Add('- ' + $L.bucket_counts + ': ' + (($summary.naming_buckets.PSObject.Properties | ForEach-Object { $_.Name + '=' + $_.Value }) -join ', '))
$md.Add('')
$md.Add('## ' + $S.modules)
$md.Add('')
$md.Add('| ' + $L.module + ' | ' + $L.category + ' | ' + $L.order + ' | ' + $L.bucket + ' |')
$md.Add('| --- | --- | --- | --- |')
foreach ($p in @($summary.programs | Sort-Object execution_order)) { $md.Add('| ' + $p.name + ' | ' + $p.category + ' | ' + $p.execution_order + ' | ' + $p.bucket + ' |') }
$md.Add('')
$md.Add('- ' + $L.functions + ' (' + @($summary.function_blocks).Count + '): ' + $(if (@($summary.function_blocks).Count) { @($summary.function_blocks) -join ', ' } else { $L.empty_note }))
$md.Add('- ' + $L.user_types + ' (' + @($summary.user_data_types).Count + '): ' + $(if (@($summary.user_data_types).Count) { @($summary.user_data_types) -join ', ' } else { $L.empty_note }))
$md.Add('')
$md.Add('## ' + $S.interfaces)
$md.Add('')
$md.Add('- ' + $L.external_writers + ' (' + $summary.interfaces.external_writer_count + '): ' + $(if ($summary.interfaces.external_writer_count) { (@($summary.interfaces.external_writer_candidates) -join ' ') } else { $L.empty_note }))
if ($summary.interfaces.unit_io_relay_start) { $md.Add('- ' + $L.unit_io + ': ' + $summary.interfaces.unit_io_relay_start + ' / ' + $summary.interfaces.unit_io_dm_start) }
$md.Add('')
$md.Add('## ' + $S.gaps)
$md.Add('')
$md.Add('- ' + $L.unannotated + ': ' + $(if ($null -ne $summary.gaps.unannotated_referenced) { $summary.gaps.unannotated_referenced } else { 'not_available' }))
$md.Add('- ' + $L.comment_rows + ': ' + $(if ($null -ne $summary.gaps.comment_rows_total) { $summary.gaps.comment_rows_total } else { 'not_available' }))
$md.Add('- ' + $L.comment_devices + ': ' + $(if ($null -ne $summary.gaps.comment_devices_total) { $summary.gaps.comment_devices_total } else { 'not_available' }))
$md.Add('- ' + $L.station_count + ': ' + @($summary.stations).Count + ' (' + $summary.gaps.station_partition + ')')
$md.Add('- ' + $L.bucket_counts + ' other=' + $summary.gaps.naming_other_count)
$md.Add('')
$md.Add('## ' + $S.standard)
$md.Add('')
$md.Add($L.standard_deviations)
$md.Add('')
[IO.File]::WriteAllText((Join-Path $outRoot ($labels.title + '.md')), ($md -join "`r`n"), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ($summary | ConvertTo-Json -Depth 10)
