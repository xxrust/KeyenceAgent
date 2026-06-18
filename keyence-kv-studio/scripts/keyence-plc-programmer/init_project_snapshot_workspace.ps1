param(
  [Parameter(Mandatory=$true)][string]$TaskRoot,
  [string]$TaskName = 'keyence-task',
  [string]$ProjectPath = '',
  [switch]$NoGit
)

$ErrorActionPreference = 'Stop'
$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$root = Join-Path $TaskRoot $TaskName
$snapshot = Join-Path $root "source_snapshot\$timestamp"
$paths = @(
  $root,
  (Join-Path $snapshot 'mnm'),
  (Join-Path $snapshot 'variables'),
  (Join-Path $snapshot 'inventory'),
  (Join-Path $snapshot 'evidence'),
  (Join-Path $root 'work'),
  (Join-Path $root 'validation')
)
foreach($p in $paths){ New-Item -ItemType Directory -Force -Path $p | Out-Null }

$manifest = [ordered]@{
  task_name = $TaskName
  project_path = $ProjectPath
  created_at = (Get-Date).ToString('s')
  snapshot_path = $snapshot
  required_export_artifacts = @(
    'mnm/*.mnm for all relevant programs, FBs, and modules',
    'variables/global_variables.csv or equivalent',
    'variables/local_variables.csv or equivalent',
    'variables/fb_instances.csv or equivalent',
    'inventory/program_tree.*',
    'inventory/unit_device_map.*',
    'evidence/export_report.md',
    'validation/compile_report.md after import/compile'
  )
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root 'source_snapshot_manifest.json') -Encoding UTF8

$readme = @"
# KEYENCE PLC Task Workspace

Project: `$ProjectPath`
Created: $timestamp

## Required workflow

1. Open the exact source `.kpr` in KV STUDIO.
2. Export fresh MNM for all relevant programs/FBs/modules into `source_snapshot/$timestamp/mnm/`.
3. Export or reconstruct variables into `source_snapshot/$timestamp/variables/`.
4. Save module tree, unit/device map, labels/comments, and export evidence into `source_snapshot/$timestamp/inventory/` and `source_snapshot/$timestamp/evidence/`.
5. Commit or record this baseline before editing.
6. Put generated or edited source into `work/`.
7. Put compile/import/export evidence into `validation/`.

Do not use stale MNM files as current source unless this snapshot proves they were freshly exported in this task.
"@
$readme | Set-Content -LiteralPath (Join-Path $root 'README.md') -Encoding UTF8

if(-not $NoGit){
  $git = Get-Command git -ErrorAction SilentlyContinue
  if($git){
    Push-Location $root
    try{
      if(-not (Test-Path '.git')){ git init | Out-Null }
      git add README.md source_snapshot_manifest.json | Out-Null
      git commit -m "Initialize KEYENCE PLC task workspace" | Out-Null
    } catch {
      Write-Warning "Git init/add/commit did not fully complete: $($_.Exception.Message)"
    } finally {
      Pop-Location
    }
  } else {
    Write-Warning 'git is not available; workspace created without git history.'
  }
}

[pscustomobject]@{
  Root = $root
  Snapshot = $snapshot
  Manifest = (Join-Path $root 'source_snapshot_manifest.json')
} | ConvertTo-Json -Depth 4
