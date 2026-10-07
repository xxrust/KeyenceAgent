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
  $snapshot,
  (Join-Path $root 'work'),
  (Join-Path $root 'validation')
)
foreach($p in $paths){ New-Item -ItemType Directory -Force -Path $p | Out-Null }

$manifest = [ordered]@{
  schema_version = 2
  status = 'snapshot_required'
  task_name = $TaskName
  project_path = $ProjectPath
  created_at = (Get-Date).ToString('s')
  snapshot_output_root = $snapshot
  required_capability = 'read_only_project_text_snapshot'
  expected_manifest = (Join-Path $snapshot 'snapshot\source_snapshot_manifest.json')
  expected_semantic_project = (Join-Path $snapshot 'snapshot\project')
}
$manifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $root 'source_snapshot_manifest.json') -Encoding UTF8

$readme = @"
# KEYENCE PLC Task Workspace

Project: `$ProjectPath`
Created: $timestamp

## Required workflow

1. Open the exact source `.kpr` in KV STUDIO.
2. Resolve the operator capability `read_only_project_text_snapshot` from its manifest.
3. Run that published workflow with `-OutDir source_snapshot/$timestamp`.
4. Check `snapshot/source_snapshot_manifest.json`, then use `snapshot/project/` as the semantic source tree.
5. Resolve warnings or incomplete entities relevant to the task before editing.
6. Commit or record this baseline before editing.
7. Put generated or edited source into `work/` and compile/import/readback evidence into `validation/`.

Do not manually reconstruct a competing MNM/variables/inventory tree. Do not use stale files as current source unless the snapshot manifest binds them to this project fingerprint.
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
