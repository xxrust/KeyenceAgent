# Unit test for the non-UI device comment / program body join.
# Deterministic: it uses the synthetic fixture under 22_annotate_program_comments
# and never opens KV STUDIO.  Every assertion is structural so the test file stays
# ASCII-only (PowerShell 5.1 decodes BOM-less scripts as ANSI).
$ErrorActionPreference = 'Stop'
$script:checks = 0
$script:failures = New-Object System.Collections.Generic.List[string]
function Assert-True([bool]$Condition, [string]$Name) {
  $script:checks++
  if (-not $Condition) { $script:failures.Add($Name) | Out-Null }
}
function Assert-Equal($Expected, $Actual, [string]$Name) {
  $script:checks++
  if ("$Expected" -ne "$Actual") { $script:failures.Add("$Name (expected '$Expected', got '$Actual')") | Out-Null }
}
function Get-Sha([string]$Path) { return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant() }

$testDir = Split-Path -Parent $PSCommandPath
$repoRoot = Split-Path -Parent $testDir
$tool = Join-Path $repoRoot 'kv-studio-operator\scripts\annotate_kv_program_with_comments_core.ps1'
$fixture = Join-Path $repoRoot 'kv-studio-operator\tests\kv-interface-regression\22_annotate_program_comments\fixtures\JoinSample'
Assert-True (Test-Path -LiteralPath $tool -PathType Leaf) 'tool script exists'
Assert-True (Test-Path -LiteralPath $fixture -PathType Container) 'fixture directory exists'

# work on a copy so the committed fixture can be compared afterwards
$work = Join-Path ([IO.Path]::GetTempPath()) ('kv_comment_join_test_' + [guid]::NewGuid().ToString('N').Substring(0, 8))
$inputDir = Join-Path $work 'input'
New-Item -ItemType Directory -Force -Path $inputDir | Out-Null
Copy-Item -Path (Join-Path $fixture '*') -Destination $inputDir -Recurse -Force
$commentsPath = Join-Path $inputDir 'comments.csv'
$mnmNames = @(Get-ChildItem -LiteralPath $inputDir -Filter '*.mnm' -File | ForEach-Object { $_.Name })
Assert-True (Test-Path -LiteralPath $commentsPath -PathType Leaf) 'fixture comment table copied'
Assert-Equal 2 $mnmNames.Count 'fixture program bodies copied'
$beforeHashes = @{}
foreach ($file in @(Get-ChildItem -LiteralPath $inputDir -File)) { $beforeHashes[$file.Name] = Get-Sha $file.FullName }

$outDir = Join-Path $work 'out'
& $tool -CommentsPath $commentsPath -MnmPath $inputDir -OutDir $outDir | Out-Null

# --- inputs must stay untouched: the MNM program bodies are never modified
foreach ($name in $beforeHashes.Keys) {
  Assert-Equal $beforeHashes[$name] (Get-Sha (Join-Path $inputDir $name)) "input unchanged: $name"
}
$newInputs = @(Get-ChildItem -LiteralPath $inputDir -File | Where-Object { $beforeHashes.Keys -notcontains $_.Name })
Assert-Equal 0 $newInputs.Count 'no file was added to the input directory'

# --- artifacts
foreach ($name in @('comments.tsv', 'usage.tsv', 'coverage.json', 'program_annotations.md', 'annotate_result.json')) {
  Assert-True (Test-Path -LiteralPath (Join-Path $outDir $name) -PathType Leaf) "artifact written: $name"
}
$coverage = Get-Content -Raw -LiteralPath (Join-Path $outDir 'coverage.json') -Encoding UTF8 | ConvertFrom-Json
$summary = $coverage.summary

# --- coverage numbers (program scope by default)
Assert-Equal 'program' $coverage.scope 'scope defaults to program bodies'
Assert-Equal 1 $coverage.body_counts.program 'one program body classified'
Assert-Equal 1 $coverage.body_counts.library 'one library body classified'
Assert-Equal 5 $summary.referenced_documentable 'referenced documentable devices'
Assert-Equal 4 $summary.used_annotated 'referenced devices with a comment'
Assert-Equal 1 $summary.used_unannotated 'referenced devices without a comment'
Assert-Equal 5 $summary.annotated_unused 'commented devices no body references'
Assert-Equal 2 $summary.annotated_unused_handwritten 'handwritten subset of annotated-unused'
Assert-Equal 9 $summary.comment_entries_total 'comment entries parsed'
Assert-Equal 1 $summary.device_rows_without_comment 'blank comment rows counted separately'
Assert-Equal 1 $summary.timers_or_counters_referenced 'timer reference counted'
Assert-Equal 4 $summary.comment_entries_by_class.handwritten 'handwritten comment entries'
Assert-Equal 2 $summary.comment_entries_by_class.system 'system comment entries'
Assert-Equal 3 $summary.comment_entries_by_class.profile 'profile comment entries'

# --- gap lists: the timer is counted but never reported as a documentation gap
Assert-Equal 'MR106' ($coverage.used_unannotated -join ',') 'unannotated gap list'
Assert-Equal 'DM860,MR9999' ($coverage.annotated_unused_handwritten -join ',') 'handwritten annotated-unused list'
Assert-Equal 1 $coverage.by_area.MR.unannotated 'MR gap count'
Assert-Equal 2 $coverage.by_area.MR.annotated 'MR annotated count'

# --- staleness evidence
Assert-Equal (Get-Sha $commentsPath) $coverage.comments_source.sha256 'comments source hash recorded'
Assert-Equal 2 @($coverage.program_bodies).Count 'both bodies recorded as evidence'
$kinds = @($coverage.program_bodies | ForEach-Object { $_.kind } | Sort-Object)
Assert-Equal 'library,program' ($kinds -join ',') 'body kinds recorded'
foreach ($body in $coverage.program_bodies) { Assert-Equal (Get-Sha (Join-Path $inputDir $body.file)) $body.sha256 "body hash recorded: $($body.file)" }

# --- device key normalisation, original spelling preserved
$commentsRows = @(Import-Csv -LiteralPath (Join-Path $outDir 'comments.tsv') -Delimiter "`t" -Encoding UTF8)
$mr13 = @($commentsRows | Where-Object { $_.key -eq 'MR13' })
Assert-Equal 1 $mr13.Count 'padded MR0013 joins as MR13'
Assert-Equal 'MR0013' $mr13[0].device 'original device spelling preserved'
Assert-Equal 'handwritten' $mr13[0].class 'axis comment classified handwritten'
$w12 = @($commentsRows | Where-Object { $_.key -eq 'W12' })
Assert-Equal 1 $w12.Count 'hex area W012 joins as W12'
$dm80 = @($commentsRows | Where-Object { $_.key -eq 'DM80' })
Assert-Equal 'handwritten' $dm80[0].class 'measurement comment is not a system comment'
$cm = @($commentsRows | Where-Object { $_.key -eq 'CM7201' })
Assert-Equal 'system' $cm[0].class 'system area comment classified system'

# --- usage table
$usageRows = @(Import-Csv -LiteralPath (Join-Path $outDir 'usage.tsv') -Delimiter "`t" -Encoding UTF8)
$t20 = @($usageRows | Where-Object { $_.device -eq 'T20' })
Assert-Equal 1 $t20.Count 'timer usage recorded'
Assert-Equal 'program' $t20[0].used_in 'timer attributed to the program body'
$dm5000 = @($usageRows | Where-Object { $_.device -eq 'DM5000' })
Assert-Equal 'library' $dm5000[0].used_in 'library-only device marked as library'
Assert-Equal 0 $dm5000[0].program_refs 'library-only device has no program reference'
$mr13 = @($usageRows | Where-Object { $_.device -eq 'MR0013' })
Assert-Equal 1 $mr13.Count 'padded device row present in usage table'
Assert-Equal 2 $mr13[0].references 'duplicate references counted'
Assert-Equal 'program' $mr13[0].used_in 'program body attribution'

# --- annotated listing
$listingLines = Get-Content -LiteralPath (Join-Path $outDir 'program_annotations.md') -Encoding UTF8
$listing = $listingLines -join "`n"
Assert-True ($listing -match 'LD MR13\s+; MR13=') 'listing annotates a ladder line'
Assert-Equal 0 @($listingLines | Where-Object { $_ -match '^BOOKMARK\s*;' }).Count 'bookmark marker is not annotated'
$labelLines = @($listingLines | Where-Object { $_ -match '^;MODULE:' })
Assert-Equal 2 $labelLines.Count 'module header lines kept verbatim'
Assert-True ($listing -match 'MR106:=TRUE;\s+; MR106=') 'embedded ST line counts as usage'

# --- library bodies can be included explicitly
$outAll = Join-Path $work 'out-all'
& $tool -CommentsPath $commentsPath -MnmPath $inputDir -OutDir $outAll -IncludeLibraryBodies | Out-Null
$coverageAll = Get-Content -Raw -LiteralPath (Join-Path $outAll 'coverage.json') -Encoding UTF8 | ConvertFrom-Json
Assert-Equal 'all' $coverageAll.scope 'library scope switch'
Assert-Equal 6 $coverageAll.summary.referenced_documentable 'library device counted in all scope'
Assert-Equal 'DM5000,MR106' ($coverageAll.used_unannotated -join ',') 'all-scope gap list'

# --- module filter selects a single body by module name
$outFiltered = Join-Path $work 'out-filtered'
& $tool -CommentsPath $commentsPath -MnmPath $inputDir -OutDir $outFiltered -ModuleFilter 'Sample_lib' | Out-Null
$coverageFiltered = Get-Content -Raw -LiteralPath (Join-Path $outFiltered 'coverage.json') -Encoding UTF8 | ConvertFrom-Json
Assert-Equal 0 $coverageFiltered.body_counts.program 'module filter excluded the program body'
Assert-Equal 1 $coverageFiltered.body_counts.library 'module filter kept the library body'
Assert-Equal 1 $coverageFiltered.summary.referenced_documentable 'filtered coverage only sees the library body'

# --- missing input is rejected
$rejected = $false
try { & $tool -CommentsPath (Join-Path $work 'missing.csv') -MnmPath $inputDir -OutDir (Join-Path $work 'out-missing') | Out-Null } catch { $rejected = $true }
Assert-True $rejected 'missing comment table is rejected'

Remove-Item -LiteralPath $work -Recurse -Force -ErrorAction SilentlyContinue

$result = [ordered]@{
  ok = ($script:failures.Count -eq 0)
  checks = $script:checks
  failures = @($script:failures)
  component = 'kv_comment_join'
}
$result | ConvertTo-Json -Depth 6
if ($script:failures.Count -gt 0) { exit 1 }
exit 0
