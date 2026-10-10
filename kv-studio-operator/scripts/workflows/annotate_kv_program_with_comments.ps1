param(
  [Parameter(Mandatory=$true)][string]$CommentsPath,
  [Parameter(Mandatory=$true)][string]$MnmPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string[]]$ModuleFilter = @(),
  [switch]$IncludeLibraryBodies,
  [switch]$PlanOnly
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$annotateScript = Join-Path $root 'annotate_kv_program_with_comments.ps1'
if (-not (Test-Path -LiteralPath $annotateScript -PathType Leaf)) { throw "Annotate script missing: $annotateScript" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if ($PlanOnly) {
  # Planning only validates the inputs and reports the intended artifacts; the join
  # itself is pure computation, so nothing is written in this mode.
  $inputOk = (Test-Path -LiteralPath $CommentsPath -PathType Leaf) -and (Test-Path -LiteralPath $MnmPath)
  $candidates = @(Get-ChildItem -LiteralPath $MnmPath -Filter '*.mnm' -File -Recurse -ErrorAction SilentlyContinue)
  $plan = [ordered]@{
    ok = [bool]$inputOk
    planned = $true
    status = $(if ($inputOk) { 'planned' } else { 'fail' })
    comments_path = $CommentsPath
    mnm_path = $MnmPath
    out_dir = $OutDir
    mnm_candidates = $candidates.Count
    mnm_files = @($candidates | ForEach-Object { $_.Name })
    include_library_bodies = [bool]$IncludeLibraryBodies
    steps = @(
      'read the device comment table',
      'extract and normalise device references from the MNM bodies',
      'classify comments and score coverage',
      'write comments.tsv, usage.tsv, coverage.json, program_annotations.md'
    )
  }
  $plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutDir 'workflow_result.json') -Encoding UTF8
  if ($plan.ok) { exit 0 }
  exit 1
}

$arguments = @('-CommentsPath', $CommentsPath, '-MnmPath', $MnmPath, '-OutDir', $OutDir)
if ($ModuleFilter.Count) { $arguments += @('-ModuleFilter') + @($ModuleFilter) }
if ($IncludeLibraryBodies) { $arguments += '-IncludeLibraryBodies' }

& powershell -NoProfile -ExecutionPolicy Bypass -File $annotateScript @arguments
$exit = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }

$coveragePath = Join-Path $OutDir 'coverage.json'
$coverage = $null
if (Test-Path -LiteralPath $coveragePath -PathType Leaf) {
  try { $coverage = Get-Content -Raw -LiteralPath $coveragePath -Encoding UTF8 | ConvertFrom-Json } catch {}
}
$summary = if ($coverage) { $coverage.summary } else { $null }
$result = [ordered]@{
  ok = ($exit -eq 0 -and $coverage -and $coverage.ok -eq $true)
  planned = $false
  status = $(if ($exit -eq 0 -and $coverage) { 'pass' } else { 'fail' })
  comments_path = $CommentsPath
  mnm_path = $MnmPath
  out_dir = $OutDir
  coverage_path = $coveragePath
  coverage_scope = $(if ($coverage) { [string]$coverage.scope } else { '' })
  referenced_documentable = $(if ($summary) { [int]$summary.referenced_documentable } else { 0 })
  used_annotated = $(if ($summary) { [int]$summary.used_annotated } else { 0 })
  used_unannotated = $(if ($summary) { [int]$summary.used_unannotated } else { 0 })
  annotated_unused = $(if ($summary) { [int]$summary.annotated_unused } else { 0 })
  comments_entries = $(if ($summary) { [int]$summary.comment_entries_total } else { 0 })
  artifacts = [ordered]@{
    comments = (Join-Path $OutDir 'comments.tsv')
    usage = (Join-Path $OutDir 'usage.tsv')
    coverage = $coveragePath
    annotations = (Join-Path $OutDir 'program_annotations.md')
  }
}
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutDir 'workflow_result.json') -Encoding UTF8
if ($result.ok) { exit 0 }
if ($exit -ne 0) { exit $exit }
exit 1
