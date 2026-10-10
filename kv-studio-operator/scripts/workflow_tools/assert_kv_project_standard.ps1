param(
  [Parameter(Mandatory=$true)][string]$SnapshotRoot,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$StandardPath = '',
  [string]$PatternMapPath = ''
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
if (-not $StandardPath) { $StandardPath = Join-Path $skillRoot 'references\project-standard.json' }
if (-not $PatternMapPath) { $PatternMapPath = Join-Path $skillRoot 'references\project-standard.patterns.json' }
foreach ($p in @($StandardPath, $PatternMapPath)) {
  if (-not (Test-Path -LiteralPath $p -PathType Leaf)) { throw "KV_STANDARD_INPUT_MISSING: $p" }
}
$standard = Get-Content -Raw -LiteralPath $StandardPath -Encoding UTF8 | ConvertFrom-Json
$patterns = Get-Content -Raw -LiteralPath $PatternMapPath -Encoding UTF8 | ConvertFrom-Json

$structurePath = Join-Path $outRoot 'structure.json'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'extract_kv_project_structure.ps1') `
  -SnapshotRoot $snapshotRoot -OutPath $structurePath -PatternMapPath $PatternMapPath | Out-Null
if (-not (Test-Path -LiteralPath $structurePath -PathType Leaf)) { throw 'KV_STANDARD_STRUCTURE_FAILED' }
$structure = Get-Content -Raw -LiteralPath $structurePath -Encoding UTF8 | ConvertFrom-Json

$coverage = $null
$coveragePath = Join-Path $snapshotRoot 'text\comments\coverage.json'
if (Test-Path -LiteralPath $coveragePath -PathType Leaf) { try { $coverage = Get-Content -Raw -LiteralPath $coveragePath -Encoding UTF8 | ConvertFrom-Json } catch { } }

# STD-06: one FB instance driven more than once per scan (or shared across axes).
$sharedInstances = New-Object System.Collections.Generic.List[object]
$mnmDir = Join-Path $snapshotRoot 'text\mnm'
if (Test-Path -LiteralPath $mnmDir -PathType Container) {
  foreach ($file in @(Get-ChildItem -LiteralPath $mnmDir -Filter '*.mnm' -File -Recurse)) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $text = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) } else { [Text.Encoding]::GetEncoding(936).GetString($bytes) }
    $counts = [ordered]@{}
    foreach ($m in [regex]::Matches($text, '(?m)^(FBEXEC|FBEAND)\s+(\S+)\s+(\S+)')) {
      $instance = $m.Groups[3].Value
      if (-not $counts.Contains($instance)) { $counts[$instance] = 0 }
      $counts[$instance]++
    }
    foreach ($k in $counts.Keys) {
      if ($counts[$k] -gt 1) {
        $sharedInstances.Add([pscustomobject]@{ module = $file.BaseName; instance = $k; calls = $counts[$k] }) | Out-Null
      }
    }
  }
}

$bucketCounts = $structure.naming_buckets
$programs = @($structure.programs)
$fbNamedPrograms = @($programs | Where-Object { $_.name -match '(?i)(^FB_|_FB$|^FB$)' -and $_.bucket -notin @('fb_prefixed','caller') } | ForEach-Object { $_.name })
$stationPrograms = @($structure.stations)
$platformBucket = 0
if ($bucketCounts.PSObject.Properties['platform']) { $platformBucket = [int]$bucketCounts.platform }
$flatTypes = @(@($structure.user_data_types) | Where-Object { $_ -notmatch '^(str|uni_)' })
$usedUnannotated = $(if ($coverage) { [int]$coverage.summary.used_unannotated } else { $null })

$checks = New-Object System.Collections.Generic.List[object]
$checks.Add([pscustomobject]@{
    id = 'STD-01'; severity = 'warn'; status = $(if ($fbNamedPrograms.Count) { 'deviation' } else { 'pass' })
    meaning = 'module name looks like a function block but it is a program'
    evidence = @($fbNamedPrograms)
  }) | Out-Null
$checks.Add([pscustomobject]@{
    id = 'STD-02'; severity = 'info'; status = $(if ($stationPrograms.Count) { 'pass' } else { 'deviation' })
    meaning = 'no ST##_* station partition'
    evidence = @($stationPrograms)
  }) | Out-Null
$checks.Add([pscustomobject]@{
    id = 'STD-03'; severity = 'info'; status = $(if ($platformBucket -gt 0) { 'pass' } else { 'deviation' })
    meaning = 'no platform programs (init/device state/alarm/HMI/IO)'
    evidence = @($platformBucket)
  }) | Out-Null
$checks.Add([pscustomobject]@{
    id = 'STD-04'; severity = 'warn'; status = $(if ($flatTypes.Count) { 'deviation' } else { 'pass' })
    meaning = 'user data types are not layered as str<domain>[Ctrl|Param|Status|IO] or uni_*'
    evidence = @($flatTypes)
  }) | Out-Null
$checks.Add([pscustomobject]@{
    id = 'STD-05'; severity = 'info'; status = $(if ($null -eq $usedUnannotated) { 'not_available' } elseif ($usedUnannotated -gt 0) { 'deviation' } else { 'pass' })
    meaning = 'referenced devices without a comment'
    evidence = @($usedUnannotated)
  }) | Out-Null
$checks.Add([pscustomobject]@{
    id = 'STD-06'; severity = 'warn'; status = $(if ($sharedInstances.Count) { 'deviation' } else { 'pass' })
    meaning = 'an FB instance is called more than once per scan'
    evidence = @($sharedInstances | ForEach-Object { $_.module + ':' + $_.instance + ' x' + $_.calls })
  }) | Out-Null

$deviations = @($checks | Where-Object { $_.status -eq 'deviation' })
$warnings = @($checks | Where-Object { $_.status -eq 'deviation' -and $_.severity -eq 'warn' })
# Enrich every check so a reader can tell severity, where the evidence came from, and
# how much of the conclusion depends on data this snapshot does not capture.
$stdMeta = @{
  'STD-01' = @{ src = 'snapshot: structure.json (program category)'; conf = 'partial_missing_locals'; human = 'programs with an FB-style name: ' + $(if ($fbNamedPrograms.Count) { $fbNamedPrograms -join ', ' } else { 'none' }) }
  'STD-02' = @{ src = 'snapshot: structure.json (station bucket)'; conf = 'confirmed'; human = 'station_programs=' + $stationPrograms.Count }
  'STD-03' = @{ src = 'snapshot: structure.json (platform bucket)'; conf = 'confirmed'; human = 'platform_programs=' + $platformBucket + ' (expected at least one of init/device-state/alarm/HMI/IO)' }
  'STD-04' = @{ src = 'snapshot: project_inventory.json data_types'; conf = 'confirmed'; human = 'unlayered user types: ' + $(if ($flatTypes.Count) { $flatTypes -join ', ' } else { 'none' }) }
  'STD-05' = @{ src = 'snapshot: text/comments/coverage.json'; conf = $(if ($null -eq $usedUnannotated) { 'not_available' } else { 'confirmed' }); human = 'used_unannotated=' + $(if ($null -eq $usedUnannotated) { 'n/a' } else { $usedUnannotated }) }
  'STD-06' = @{ src = 'snapshot: text/mnm bodies'; conf = 'confirmed'; human = 'shared instances: ' + $(if ($sharedInstances.Count) { (@($sharedInstances | ForEach-Object { $_.module + ':' + $_.instance + ' x' + $_.calls }) -join '; ') } else { 'none' }) }
}
foreach ($c in $checks) {
  $m = $stdMeta[$c.id]
  if ($m) {
    $c | Add-Member -NotePropertyName evidence_source -NotePropertyValue $m.src -Force
    $c | Add-Member -NotePropertyName confidence -NotePropertyValue $m.conf -Force
    $c | Add-Member -NotePropertyName evidence_human -NotePropertyValue $m.human -Force
  }
}
$bySeverity = [ordered]@{ warn = @($deviations | Where-Object { $_.severity -eq 'warn' }).Count; info = @($deviations | Where-Object { $_.severity -eq 'info' }).Count }
$report = [ordered]@{
  schema_version = 1
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  standard = [ordered]@{ path = $StandardPath; name = [string]$standard.name; status = [string]$standard.status; disclaimer = [string]$standard.disclaimer }
  source = [ordered]@{ snapshot_root = $snapshotRoot; structure_path = $structurePath; coverage_path = $(if ($coverage) { $coveragePath } else { '' }) }
  project = $structure.source.project_path
  verdict = $(if ($warnings.Count) { 'deviations_found' } elseif ($deviations.Count) { 'advisory_notes_only' } else { 'conforms' })
  deviation_count = $deviations.Count
  warning_count = $warnings.Count
  checks = $checks.ToArray()
  requires_user_decision = $true
  next_action = 'show this report and the project summary to the project owner and ask whether to restructure; never change the project without that answer'
}
$report['deviation_count_by_severity'] = $bySeverity
$json = $report | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText((Join-Path $outRoot 'standard_report.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Output $json
