param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [Parameter(Mandatory=$true)]
  [string]$WorkspaceRoot,

  [string]$TaskId = ('kv_update_' + (Get-Date -Format 'yyyyMMdd_HHmmss')),
  [string]$SeedScaffoldRoot = '',
  [ValidateSet('None','SameRunSkillBaseline','ControlledScaffoldSnapshot')]
  [string]$SeedTrust = 'None',
  [switch]$ForceNewSnapshot
)

$ErrorActionPreference = 'Stop'

function Get-ProjectRoot([string]$KprPath) {
  return [IO.Path]::GetFullPath((Split-Path -Parent $KprPath))
}

function Get-DirectoryFingerprint([string]$Root) {
  if (-not (Test-Path -LiteralPath $Root -PathType Container)) {
    throw "Project root not found: $Root"
  }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  try {
    $files = @(Get-ChildItem -LiteralPath $Root -File -Recurse -Force |
      Where-Object { $_.FullName -notmatch '\\\.git\\' } |
      Sort-Object FullName)
    $fileEntries = @()
    foreach ($file in $files) {
      $relative = $file.FullName.Substring($Root.Length).TrimStart('\','/')
      $fileHash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
      $line = "$relative`t$($file.Length)`t$fileHash`n"
      $bytes = [Text.Encoding]::UTF8.GetBytes($line)
      [void]$sha.TransformBlock($bytes, 0, $bytes.Length, $bytes, 0)
      $fileEntries += [pscustomobject]@{
        path = $relative
        length = $file.Length
        sha256 = $fileHash
      }
    }
    [void]$sha.TransformFinalBlock([byte[]]::new(0), 0, 0)
    $hash = -join ($sha.Hash | ForEach-Object { $_.ToString('x2') })
    return [pscustomobject]@{
      algorithm = 'sha256-of-relative-path-length-file-sha256'
      root = $Root
      hash = $hash
      file_count = $files.Count
      files = $fileEntries
    }
  } finally {
    $sha.Dispose()
  }
}

function Copy-IfPresent([string]$Source, [string]$Destination) {
  if (Test-Path -LiteralPath $Source) {
    New-Item -ItemType Directory -Force -Path $Destination | Out-Null
    Get-ChildItem -LiteralPath $Source -Force | ForEach-Object {
      Copy-Item -LiteralPath $_.FullName -Destination $Destination -Recurse -Force
    }
    return $true
  }
  return $false
}

function Copy-FileToDirectory([string]$SourceFile, [string]$DestinationDirectory) {
  [IO.Directory]::CreateDirectory($DestinationDirectory) | Out-Null
  $destinationFile = Join-Path $DestinationDirectory ([IO.Path]::GetFileName($SourceFile))
  [IO.File]::Copy($SourceFile, $destinationFile, $true)
}

function Copy-SeedScaffoldArtifactsFromManifest([string]$SeedRoot, [string]$MnmDestination, [string]$VariablesDestination) {
  $manifestPath = Join-Path $SeedRoot 'scaffold.json'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
    return [pscustomobject]@{ mnm_count = 0; variable_count = 0 }
  }
  $manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
  $mnmCount = 0
  $variableCount = 0
  foreach ($entry in @($manifest.mnm_files)) {
    $moduleName = if ($entry.module_name) { [string]$entry.module_name } else { [IO.Path]::GetFileNameWithoutExtension([string]$entry.path) }
    $safeModuleName = $moduleName -replace '[\\/:*?"<>|]+', '_'
    if ($entry.path) {
      $sourceMnm = Join-Path $SeedRoot ([string]$entry.path)
      if (Test-Path -LiteralPath $sourceMnm -PathType Leaf) {
        $targetDir = Join-Path $MnmDestination $safeModuleName
        Copy-FileToDirectory $sourceMnm $targetDir
        $mnmCount++
      }
    }
    $variablePaths = @()
    if ($entry.variables) {
      if ($entry.variables.global_tsv) { $variablePaths += [string]$entry.variables.global_tsv }
      if ($entry.variables.local_tsv) { $variablePaths += [string]$entry.variables.local_tsv }
    }
    if ($entry.arguments -and $entry.arguments.tsv) {
      $variablePaths += [string]$entry.arguments.tsv
    }
    foreach ($relativeVariablePath in @($variablePaths | Where-Object { $_ } | Select-Object -Unique)) {
      $sourceVariable = Join-Path $SeedRoot $relativeVariablePath
      if (Test-Path -LiteralPath $sourceVariable -PathType Leaf) {
        $targetDir = Join-Path $VariablesDestination $safeModuleName
        Copy-FileToDirectory $sourceVariable $targetDir
        $variableCount++
      }
    }
  }
  return [pscustomobject]@{ mnm_count = $mnmCount; variable_count = $variableCount }
}

function ConvertTo-RelativePath([string]$Base, [string]$Path) {
  $baseUri = [Uri](([IO.Path]::GetFullPath($Base).TrimEnd('\') + '\'))
  $pathUri = [Uri]([IO.Path]::GetFullPath($Path))
  return [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($pathUri).ToString()).Replace('/', '\')
}

$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
  throw "ProjectPath not found: $ProjectPath"
}

$WorkspaceRoot = [IO.Path]::GetFullPath($WorkspaceRoot)
$taskRoot = Join-Path $WorkspaceRoot $TaskId
$architectureDir = Join-Path $taskRoot 'architecture'
$snapshotRoot = Join-Path $taskRoot 'source_snapshot'
$workDir = Join-Path $taskRoot 'work'
$validationDir = Join-Path $taskRoot 'validation'
$manifestPath = Join-Path $taskRoot 'source_snapshot_manifest.json'

$projectRoot = Get-ProjectRoot $ProjectPath
$fingerprint = Get-DirectoryFingerprint $projectRoot

if (-not $ForceNewSnapshot -and (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  try {
    $existing = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
    if ([string]$existing.project_fingerprint.hash -eq $fingerprint.hash -and [string]$existing.status -eq 'ready') {
      [pscustomobject]@{
        ok = $true
        reused = $true
        task_root = $taskRoot
        project_path = $ProjectPath
        project_fingerprint = $fingerprint
        source_snapshot_manifest = $manifestPath
        message = 'Existing parsed snapshot reused because the current project fingerprint matches.'
      } | ConvertTo-Json -Depth 8
      exit 0
    }
  } catch {
    Write-Warning "Existing manifest could not be reused: $($_.Exception.Message)"
  }
}

$timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$snapshotDir = Join-Path $snapshotRoot ($timestamp + '_' + $fingerprint.hash.Substring(0, 12))
$mnmDir = Join-Path $snapshotDir 'mnm'
$variablesDir = Join-Path $snapshotDir 'variables'
$inventoryDir = Join-Path $snapshotDir 'inventory'
$evidenceDir = Join-Path $snapshotDir 'evidence'
New-Item -ItemType Directory -Force -Path $taskRoot, $architectureDir, $snapshotDir, $mnmDir, $variablesDir, $inventoryDir, $evidenceDir, $workDir, $validationDir | Out-Null

$seededMnm = $false
$seededVariables = $false
if ($SeedScaffoldRoot) {
  $SeedScaffoldRoot = [IO.Path]::GetFullPath($SeedScaffoldRoot)
  $seededMnm = Copy-IfPresent (Join-Path $SeedScaffoldRoot 'mnm') $mnmDir
  $seededVariables = Copy-IfPresent (Join-Path $SeedScaffoldRoot 'variables') $variablesDir
  $manifestSeed = Copy-SeedScaffoldArtifactsFromManifest $SeedScaffoldRoot $mnmDir $variablesDir
  if ($manifestSeed.mnm_count -gt 0) { $seededMnm = $true }
  if ($manifestSeed.variable_count -gt 0) { $seededVariables = $true }
  foreach ($name in @('scaffold.json', 'scaffold.model.json', 'TASK.md', 'VERSION.md', 'CHECKLIST.md')) {
    $source = Join-Path $SeedScaffoldRoot $name
    if (Test-Path -LiteralPath $source -PathType Leaf) {
      Copy-Item -LiteralPath $source -Destination (Join-Path $inventoryDir ('seed_' + $name)) -Force
    }
  }
}

$projectIdentityPath = Join-Path $inventoryDir 'project_identity.json'
[ordered]@{
  project_path = $ProjectPath
  project_root = $projectRoot
  captured_at = (Get-Date).ToString('s')
  fingerprint = $fingerprint
  seed_scaffold_root = $SeedScaffoldRoot
} | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $projectIdentityPath -Encoding UTF8

$architecturePath = Join-Path $architectureDir 'update_context.json'
$architecture = [ordered]@{
  schema_version = 1
  project = [ordered]@{
    path = $ProjectPath
    root = $projectRoot
    fingerprint_hash = $fingerprint.hash
  }
  update_intent = [ordered]@{
    summary = ''
    acceptance = @()
    risk_notes = @()
  }
  source_snapshot = [ordered]@{
    manifest = 'source_snapshot_manifest.json'
    current_snapshot = ConvertTo-RelativePath $taskRoot $snapshotDir
  }
  extension_points = [ordered]@{
    modules = @()
    variables = @()
    io_map = @()
    units = @()
    labels = @()
    comments = @()
    fb_instances = @()
    data_types = @()
    safety = @()
    acceptance = @()
    extra_config = [ordered]@{}
  }
}
$architecture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $architecturePath -Encoding UTF8

$mnmCount = @(Get-ChildItem -LiteralPath $mnmDir -File -Filter '*.mnm' -Recurse -ErrorAction SilentlyContinue).Count
$variableCount = @(Get-ChildItem -LiteralPath $variablesDir -File -Recurse -ErrorAction SilentlyContinue |
  Where-Object { $_.Extension -in @('.tsv', '.csv', '.json') }).Count
$trustedSeed = ($SeedTrust -eq 'SameRunSkillBaseline' -or $SeedTrust -eq 'ControlledScaffoldSnapshot')
$status = if ($mnmCount -gt 0 -and $variableCount -gt 0 -and $trustedSeed) { 'ready' } else { 'export_required' }
$errorCode = if ($status -eq 'ready') { '' } else { 'KV_SOURCE_SNAPSHOT_EXPORT_REQUIRED' }

$manifest = [ordered]@{
  schema_version = 1
  status = $status
  task_id = $TaskId
  created_at = (Get-Date).ToString('s')
  project = [ordered]@{
    path = $ProjectPath
    root = $projectRoot
  }
  project_fingerprint = $fingerprint
  snapshot = [ordered]@{
    path = ConvertTo-RelativePath $taskRoot $snapshotDir
    basis = if ($SeedTrust -eq 'SameRunSkillBaseline') {
      'same_run_skill_baseline_seed_bound_to_current_project_fingerprint'
    } elseif ($SeedTrust -eq 'ControlledScaffoldSnapshot') {
      'controlled_scaffold_snapshot_bound_to_current_project_fingerprint'
    } elseif ($SeedScaffoldRoot) {
      'seed_files_present_but_not_trusted_as_current_project_export'
    } else {
      'fresh_export_required'
    }
    seed_trust = $SeedTrust
  }
  artifacts = [ordered]@{
    mnm_dir = ConvertTo-RelativePath $taskRoot $mnmDir
    variables_dir = ConvertTo-RelativePath $taskRoot $variablesDir
    inventory_dir = ConvertTo-RelativePath $taskRoot $inventoryDir
    evidence_dir = ConvertTo-RelativePath $taskRoot $evidenceDir
  }
  architecture = [ordered]@{
    path = ConvertTo-RelativePath $taskRoot $architecturePath
    format = 'open_json_extension_points'
  }
  required_when_status_export_required = @(
    'Export current project MNM files into artifacts.mnm_dir.',
    'Export or reconstruct current global/local/FB variable manifests into artifacts.variables_dir.',
    'Record program tree, unit/device map, and project identity evidence into artifacts.inventory_dir.',
    'Set status=ready only after the exported artifacts represent the current project fingerprint.'
  )
}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath -Encoding UTF8

$workspaceNote = @"
# KV Existing Project Update Workspace

Project: `$ProjectPath`
Task: `$TaskId`

## Gate

`assert_kv_existing_project_snapshot.ps1` must pass before any script opens KV STUDIO for an existing-project update.

If `source_snapshot_manifest.json.status` is `export_required`, export current MNM and variable manifests from the exact project first. Set the manifest to `ready` only when those files describe the project fingerprint recorded in the manifest.

## Open Architecture File

Edit `architecture/update_context.json` for task intent and future configuration categories. Keep new configuration under `extension_points` instead of inventing fixed top-level files for each new feature.
"@
$workspaceNote | Set-Content -LiteralPath (Join-Path $taskRoot 'WORKSPACE.md') -Encoding UTF8

$ok = ($status -eq 'ready')
$result = [ordered]@{
  ok = $ok
  error_code = $errorCode
  reused = $false
  status = $status
  task_root = $taskRoot
  project_path = $ProjectPath
  project_fingerprint = $fingerprint
  source_snapshot_manifest = $manifestPath
  architecture_path = $architecturePath
  seeded_from_scaffold = [bool]$SeedScaffoldRoot
  seed_trust = $SeedTrust
  mnm_count = $mnmCount
  variable_manifest_count = $variableCount
  message = if ($ok) {
    'Snapshot workspace is ready and bound to the current project fingerprint.'
  } else {
    'KV_SOURCE_SNAPSHOT_EXPORT_REQUIRED: snapshot workspace created, but current MNM and variable exports are required before updating this project.'
  }
}
$result | ConvertTo-Json -Depth 8
if (-not $ok) { exit 42 }
