<#
.SYNOPSIS
  Join the KV STUDIO device comment list with exported program bodies (MNM).

.DESCRIPTION
  Non-UI, read-only post-processing. The MNM program bodies are never modified:
  they are read, their device references are counted, and the join is written to
  separate, agent-friendly artifacts under -OutDir:

    comments.tsv            device, comment columns, area, comment class
    usage.tsv               device, comment, class, referencing modules, count
    coverage.json           counts, gap lists, input hashes (staleness evidence)
    program_annotations.md  per-line listing with the device comments appended

  Device references are extracted from ladder mnemonics and embedded ST lines.
  Lines starting with ';' inside a body are ST code and count as usage; BOOKMARK
  labels are not code and are ignored. Timers/counters (T/C) are counted but are
  never reported as documentation gaps.

.EXAMPLE
  powershell -NoProfile -ExecutionPolicy Bypass -File annotate_kv_program_with_comments_core.ps1 `
    -CommentsPath .\comments\device_comments.csv -MnmPath .\snapshot\raw\mnm_export -OutDir .\out
#>
param(
  [Parameter(Mandatory=$true)][string]$CommentsPath,
  [Parameter(Mandatory=$true)][string]$MnmPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string[]]$ModuleFilter = @(),
  [switch]$IncludeLibraryBodies
)

$ErrorActionPreference = 'Stop'
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$utf8 = New-Object System.Text.UTF8Encoding($false)

# Device areas, classification terms and the device token pattern come from a
# UTF-8 terms file so this script stays ASCII-only: PowerShell 5.1 decodes a
# BOM-less script as ANSI, and Chinese literals inside it would corrupt the
# syntax.  B/W are hexadecimal in KV STUDIO; the rest are decimal.  Leading
# zeros are stripped but the base is never reinterpreted, so W012/W12 and
# MR013/MR13 each collapse to one key without changing meaning.
$termsPath = Join-Path (Split-Path -Parent $PSCommandPath) 'annotate_kv_program_with_comments.terms.json'
if (-not (Test-Path -LiteralPath $termsPath -PathType Leaf)) { throw "KV_COMMENTS_TERMS_MISSING: $termsPath" }
$terms = Get-Content -Raw -LiteralPath $termsPath -Encoding UTF8 | ConvertFrom-Json
$script:HexAreas = @($terms.hexAreas)
$script:DocumentableAreas = @($terms.documentableAreas)
$script:NonDocumentableAreas = @($terms.nonDocumentableAreas)
$script:SystemAreas = @($terms.systemAreas)
$script:DevicePattern = [string]$terms.devicePattern
$script:ProfilePattern = [string]$terms.profilePattern
$script:SystemCommentPattern = [string]$terms.systemCommentPattern
$script:ProgramBodyPattern = [string]$terms.programBodyPattern
$script:LibraryBodyPattern = [string]$terms.libraryBodyPattern

function Write-Utf8([string]$Name, [string]$Text) {
  [IO.File]::WriteAllText((Join-Path $OutDir $Name), $Text, $utf8)
}
function Get-FileSha([string]$Path) {
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Read-KvText([string]$Path) {
  # KV STUDIO writes ANSI (CP936) CSV and UTF-16LE MNM; both are detected here.
  $bytes = [IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { return [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) }
  $nul = 0
  for ($i = 1; $i -lt [Math]::Min($bytes.Length, 4096); $i += 2) { if ($bytes[$i] -eq 0) { $nul++ } }
  if ($nul -gt ([Math]::Min($bytes.Length, 4096) / 8)) { return [Text.Encoding]::Unicode.GetString($bytes) }
  try { return (New-Object System.Text.UTF8Encoding($false, $true)).GetString($bytes) } catch { }
  return [Text.Encoding]::GetEncoding(936).GetString($bytes)
}
function Get-DeviceArea([string]$Device) {
  $prefix = ($Device -replace '[0-9].*$', '')
  return $prefix.ToUpperInvariant()
}
function Get-DeviceKey([string]$Device) {
  # Canonical join key: drop any bit/type suffix first (a comment table can spell a
  # word device as DM10090.0 while the program body writes DM10090), then strip
  # leading zeros while keeping the base.
  $Device = ($Device -replace '\.[A-Za-z0-9]+$', '')
  if ($Device -notmatch '^([A-Za-z]+)0*([0-9A-Fa-f]+)$') { return $Device.ToUpperInvariant() }
  $prefix = $Matches[1].ToUpperInvariant()
  $digits = $Matches[2].ToUpperInvariant()
  if ($digits.Length -gt 1) { $digits = $digits.TrimStart('0'); if (-not $digits) { $digits = '0' } }
  return ($prefix + $digits)
}
function Get-CommentClass([string]$Text, [string]$Area) {
  if ($Text -match $script:ProfilePattern) { return 'profile' }
  if ($Text -match $script:SystemCommentPattern) { return 'system' }
  if ($script:SystemAreas -contains $Area) { return 'system' }
  return 'handwritten'
}
function Get-LineDevices([string]$Line) {
  $keys = New-Object System.Collections.Generic.List[string]
  if ($Line -match '^\s*BOOKMARK') { return $keys }
  foreach ($m in [regex]::Matches($Line, $script:DevicePattern)) {
    $key = Get-DeviceKey $m.Value
    if (-not $keys.Contains($key)) { $keys.Add($key) | Out-Null }
  }
  return $keys
}
function Get-BodyKind([string]$Name, [string]$Path) {
  # The exporter encodes the module class in the file name; library FB bodies are
  # vendor internals whose uncommented devices are not the user's documentation gap.
  $probe = $Name + '|' + $Path
  if ($probe -match $script:LibraryBodyPattern) { return 'library' }
  if ($probe -match $script:ProgramBodyPattern) { return 'program' }
  return 'unknown'
}

# ---------------------------------------------------------------- inputs
if (-not (Test-Path -LiteralPath $CommentsPath -PathType Leaf)) { throw "KV_COMMENTS_INPUT_MISSING: $CommentsPath" }
if (-not (Test-Path -LiteralPath $MnmPath)) { throw "KV_COMMENTS_MNM_INPUT_MISSING: $MnmPath" }
$mnmFiles = if ((Get-Item -LiteralPath $MnmPath).PSIsContainer) {
  @(Get-ChildItem -LiteralPath $MnmPath -Filter '*.mnm' -File -Recurse | Sort-Object Name)
} else {
  @(Get-Item -LiteralPath $MnmPath)
}
if ($mnmFiles.Count -eq 0) { throw "KV_COMMENTS_MNM_INPUT_EMPTY: $MnmPath" }

# ---------------------------------------------------------------- comments
$commentRows = [ordered]@{}
$blankCommentRows = 0
$commentRowCount = 0
$commentText = Read-KvText $CommentsPath
$lines = $commentText -split "`r?`n"
foreach ($line in $lines) {
  if ([string]::IsNullOrWhiteSpace($line)) { continue }
  $cells = $line -split ','
  if ($cells.Count -lt 3) { continue }
  $device = $cells[0].Trim()
  if (-not $device -or $device -notmatch '^[A-Za-z]+\d') { continue }   # skip the comment-table header row
  $comment = ''
  for ($i = 2; $i -lt [Math]::Min($cells.Count, 10); $i++) {
    if ($cells[$i].Trim()) { $comment = $cells[$i].Trim(); break }
  }
  $key = Get-DeviceKey $device
  if (-not $comment) {
    # KV STUDIO exports commented devices only; a blank row is not an annotation,
    # so it is counted separately instead of entering the coverage numbers.
    $blankCommentRows++
    continue
  }
  $commentRowCount++
  if (-not $commentRows.Contains($key)) {
    $area = Get-DeviceArea $device
    $commentRows[$key] = [pscustomobject]@{
      device = $device
      key = $key
      area = $area
      comment = $comment
      class = (Get-CommentClass $comment $area)
    }
  }
}

# ---------------------------------------------------------------- program bodies
$usage = [ordered]@{}
$programBodyCount = 0
$libraryBodyCount = 0
$unknownBodyCount = 0
$annotationLines = New-Object System.Collections.Generic.List[string]
$annotationLines.Add('# Program bodies annotated with device comments')
$annotationLines.Add('')
$annotationLines.Add('Source: ``' + (Split-Path -Leaf $CommentsPath) + '`` (device comments) and ' + $mnmFiles.Count + ' MNM file(s).')
$annotationLines.Add('The MNM files are not modified; this listing is a derived view. Devices without a comment are marked.')
$annotationLines.Add('')
$bodyEvidence = New-Object System.Collections.Generic.List[object]
foreach ($file in $mnmFiles) {
  $moduleName = [IO.Path]::GetFileNameWithoutExtension($file.Name)
  $body = Read-KvText $file.FullName
  $headerModule = $moduleName
  if ($body -match '(?m)^;MODULE:(.+)$') { $headerModule = $Matches[1].Trim() }
  # Callers know module names from the program tree (Main, Axis_FB), not the export
  # file name, so the filter accepts either spelling.
  if ($ModuleFilter.Count -and ($ModuleFilter -notcontains $moduleName) -and ($ModuleFilter -notcontains $headerModule)) { continue }
  $bodyKind = Get-BodyKind $file.Name $file.FullName
  $bodyEvidence.Add([pscustomobject]@{ file = $file.Name; module = $headerModule; kind = $bodyKind; sha256 = (Get-FileSha $file.FullName) }) | Out-Null
  if ($bodyKind -eq 'library') { $libraryBodyCount++ } elseif ($bodyKind -eq 'program') { $programBodyCount++ } else { $unknownBodyCount++ }
  $annotationLines.Add('## ' + $headerModule + '  (`' + $file.Name + '`, ' + $bodyKind + ' body)')
  $annotationLines.Add('')
  $annotationLines.Add('```text')
  foreach ($raw in ($body -split "`r?`n")) {
    $keys = Get-LineDevices $raw
    if ($keys.Count -eq 0) { $annotationLines.Add($raw); continue }
    $parts = New-Object System.Collections.Generic.List[string]
    foreach ($key in $keys) {
      if (-not $usage.Contains($key)) {
        $row = $commentRows[$key]
        $usage[$key] = [pscustomobject]@{
          key = $key
          device = $(if ($row) { $row.device } else { $key })
          area = (Get-DeviceArea $key)
          comment = $(if ($row) { $row.comment } else { '' })
          class = $(if ($row) { $row.class } else { 'unannotated' })
          modules = (New-Object System.Collections.Generic.List[string])
          kinds = (New-Object System.Collections.Generic.List[string])
          references = 0
          program_refs = 0
          library_refs = 0
        }
      }
      $usage[$key].references++
      if ($bodyKind -eq 'library') { $usage[$key].library_refs++ } else { $usage[$key].program_refs++ }
      if (-not $usage[$key].modules.Contains($headerModule)) { $usage[$key].modules.Add($headerModule) | Out-Null }
      if (-not $usage[$key].kinds.Contains($bodyKind)) { $usage[$key].kinds.Add($bodyKind) | Out-Null }
      $label = if ($commentRows.Contains($key) -and $commentRows[$key].comment) { $commentRows[$key].comment } else { 'no comment' }
      $parts.Add(($key + '=' + $label)) | Out-Null
    }
    $pad = if ($raw.Length -lt 46) { ' ' * (46 - $raw.Length) } else { ' ' }
    $annotationLines.Add($raw + $pad + '; ' + ($parts -join '  '))
  }
  $annotationLines.Add('```')
  $annotationLines.Add('')
}

# ---------------------------------------------------------------- outputs
$commentsOut = New-Object System.Collections.Generic.List[string]
$commentsOut.Add("device`tkey`tarea`tclass`tcomment")
foreach ($key in ($commentRows.Keys | Sort-Object)) {
  $row = $commentRows[$key]
  $commentsOut.Add(($row.device + "`t" + $row.key + "`t" + $row.area + "`t" + $row.class + "`t" + $row.comment))
}
Write-Utf8 'comments.tsv' ($commentsOut -join "`n")

$usageOut = New-Object System.Collections.Generic.List[string]
$usageOut.Add("device`tarea`tclass`tused_in`tcomment`tmodules`tprogram_refs`tlibrary_refs`treferences`tstatus")
foreach ($key in ($usage.Keys | Sort-Object)) {
  $u = $usage[$key]
  $status = if ($u.class -eq 'unannotated') { 'used_unannotated' } else { 'used_annotated' }
  $usageOut.Add(($u.device + "`t" + $u.area + "`t" + $u.class + "`t" + (($u.kinds) -join '+') + "`t" + $u.comment + "`t" + (($u.modules) -join ';') + "`t" + $u.program_refs + "`t" + $u.library_refs + "`t" + $u.references + "`t" + $status))
}
Write-Utf8 'usage.tsv' ($usageOut -join "`n")

# Coverage scope: by default only the user's program bodies count, because the
# exported library FB bodies are vendor internals (their devices are not the
# user's documentation gap).  Bodies whose file name does not identify a class are
# treated as user bodies and reported as 'unknown'.  -IncludeLibraryBodies widens
# the scope to every exported body.
$inScope = $(if ($IncludeLibraryBodies -or ($programBodyCount + $unknownBodyCount) -eq 0) { 'all' } else { 'program' })
# The exporter can name bodies in ways the patterns do not recognise; the old code
# silently counted those as program bodies.  Say so instead.
$classificationWarning = $(if ($unknownBodyCount -gt 0) { "module_kind_unresolved: $unknownBodyCount of $(($programBodyCount + $unknownBodyCount + $libraryBodyCount)) bodies matched neither the program nor the library naming pattern; scope is reported as unverified" } else { '' })
if ($unknownBodyCount -gt 0) { $inScope = $inScope + '(unverified)' }
$documentable = @($usage.Keys | Where-Object { ($script:DocumentableAreas -contains (Get-DeviceArea $_)) -and ($inScope -eq 'all' -or $usage[$_].program_refs -gt 0) })
$usedAnnotated = @($documentable | Where-Object { $usage[$_].class -ne 'unannotated' })
$usedUnannotated = @($documentable | Where-Object { $usage[$_].class -eq 'unannotated' })
$annotatedUnused = @($commentRows.Keys | Where-Object { -not $usage.Contains($_) -and ($script:DocumentableAreas -contains $commentRows[$_].area) })
$handwrittenUnused = @($annotatedUnused | Where-Object { $commentRows[$_].class -eq 'handwritten' })
$timersUsed = @($usage.Keys | Where-Object { $script:NonDocumentableAreas -contains (Get-DeviceArea $_) })

$byArea = [ordered]@{}
foreach ($area in ($documentable | ForEach-Object { Get-DeviceArea $_ } | Sort-Object -Unique)) {
  $inArea = @($documentable | Where-Object { (Get-DeviceArea $_) -eq $area })
  $byArea[$area] = [ordered]@{
    referenced = $inArea.Count
    annotated = @($inArea | Where-Object { $usage[$_].class -ne 'unannotated' }).Count
    unannotated = @($inArea | Where-Object { $usage[$_].class -eq 'unannotated' }).Count
  }
}

# Every collection is materialised before the summary is assembled: PowerShell's
# array binder cannot unify heterogeneous values inside a literal, and an
# ordered dictionary of mixed scalars/collections triggers that path.
$bodyList = [object[]]$bodyEvidence.ToArray()
$usedUnannotatedList = [string[]]@($usedUnannotated | Sort-Object)
$handwrittenUnusedList = [string[]]@($handwrittenUnused | Sort-Object)
$handwrittenCount = [int]@($commentRows.Keys | Where-Object { $commentRows[$_].class -eq 'handwritten' }).Count
$systemCount = [int]@($commentRows.Keys | Where-Object { $commentRows[$_].class -eq 'system' }).Count
$profileCount = [int]@($commentRows.Keys | Where-Object { $commentRows[$_].class -eq 'profile' }).Count
$commentsPathResolved = (Resolve-Path -LiteralPath $CommentsPath).Path
$commentsSha = (Get-FileSha $CommentsPath)

$coverage = [ordered]@{}
$coverage['ok'] = $true
$coverage['generated_at'] = (Get-Date).ToString('o')
$coverage['scope'] = $inScope
$coverage['classification_warning'] = $classificationWarning
$coverage['scope_note'] = 'program = user program bodies (plus bodies whose name identifies no class); all = program plus exported library FB bodies.'
$coverage['body_counts'] = [ordered]@{ program = $programBodyCount; unknown = $unknownBodyCount; library = $libraryBodyCount }
$coverage['comments_source'] = [ordered]@{ path = $commentsPathResolved; sha256 = $commentsSha; entries = [int]$commentRows.Count }
$coverage['program_bodies'] = $bodyList
$coverage['summary'] = [ordered]@{
  referenced_documentable = [int]$documentable.Count
  used_annotated = [int]$usedAnnotated.Count
  used_unannotated = [int]$usedUnannotated.Count
  annotated_unused = [int]$annotatedUnused.Count
  annotated_unused_handwritten = [int]$handwrittenUnused.Count
  timers_or_counters_referenced = [int]$timersUsed.Count
  comment_entries_total = [int]$commentRows.Count
  comment_rows_total = [int]$commentRowCount
  comment_rows_merged_by_device = [int]($commentRowCount - $commentRows.Count)
  device_rows_without_comment = [int]$blankCommentRows
  comment_entries_by_class = [ordered]@{ handwritten = $handwrittenCount; system = $systemCount; profile = $profileCount }
}
$coverage['by_area'] = $byArea
$coverage['used_unannotated'] = $usedUnannotatedList
$coverage['annotated_unused_handwritten'] = $handwrittenUnusedList
$coverage['annotated_unused_total'] = [int]$annotatedUnused.Count
$coverage['fold_hint'] = 'CM/CR/W/B/ZF and unit system comments dominate the comment table; expand only MR and user DM for review. coverage.json always carries every entry.'
$coverageJson = $coverage | ConvertTo-Json -Depth 8
[IO.File]::WriteAllText((Join-Path $OutDir 'coverage.json'), $coverageJson, $utf8)

Write-Utf8 'program_annotations.md' ($annotationLines -join "`n")

$summary = [ordered]@{
  ok = $true
  out_dir = $OutDir
  comments_entries = $commentRows.Count
  mnm_files = $bodyEvidence.Count
  referenced_documentable = $documentable.Count
  used_annotated = $usedAnnotated.Count
  used_unannotated = $usedUnannotated.Count
  annotated_unused = $annotatedUnused.Count
  artifacts = [ordered]@{
    comments = (Join-Path $OutDir 'comments.tsv')
    usage = (Join-Path $OutDir 'usage.tsv')
    coverage = (Join-Path $OutDir 'coverage.json')
    annotations = (Join-Path $OutDir 'program_annotations.md')
  }
}
$summary | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'annotate_result.json') -Encoding UTF8
$summary | ConvertTo-Json -Depth 6
