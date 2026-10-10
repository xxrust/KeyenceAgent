param(
  [Parameter(Mandatory=$true)][string]$SnapshotRoot,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$StandardPath = '',
  [string]$PatternMapPath = ''
)
$ErrorActionPreference = 'Stop'
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
$json = $report | ConvertTo-Json -Depth 10
[IO.File]::WriteAllText((Join-Path $outRoot 'standard_report.json'), $json, (New-Object System.Text.UTF8Encoding($false)))
Write-Output $json
