param(
  [Parameter(Mandatory=$true)]
  [string]$ScaffoldRoot,

  [Parameter(Mandatory=$true)]
  [string]$SourceSnapshotManifestPath,

  [string]$SourceSnapshotGateResultPath = '',
  [string]$OutDir = '',
  [switch]$DeleteExistingModulesBeforeImport
)

$ErrorActionPreference = 'Stop'

function Resolve-PathFromBase([string]$BaseDir, [string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  return [IO.Path]::GetFullPath((Join-Path $BaseDir $Path))
}

function Resolve-ScaffoldPath([string]$RelativePath) {
  if ([string]::IsNullOrWhiteSpace($RelativePath)) { return '' }
  if ([IO.Path]::IsPathRooted($RelativePath)) { return [IO.Path]::GetFullPath($RelativePath) }
  return [IO.Path]::GetFullPath((Join-Path $ScaffoldRoot $RelativePath))
}

function Read-MnmText([string]$Path) {
  $bytes = [IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
    return [Text.Encoding]::Unicode.GetString($bytes)
  }
  if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
    return [Text.Encoding]::UTF8.GetString($bytes)
  }
  return [Text.Encoding]::Default.GetString($bytes)
}

function Get-MnmModuleName([string]$Path) {
  $text = Read-MnmText $Path
  foreach ($line in ($text -split "(`r`n|`n|`r)")) {
    $trimmed = ([string]$line).Trim()
    if ($trimmed -match '^;MODULE:(.+)$') {
      return $matches[1].Trim()
    }
  }
  return [IO.Path]::GetFileNameWithoutExtension($Path)
}

function Get-NameKey([string]$Name) {
  return ([string]$Name).Trim().ToUpperInvariant()
}

function Write-Result([object]$Payload) {
  if ($OutDir) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $path = Join-Path $OutDir 'mnm_import_plan_gate.json'
    $Payload | Add-Member -NotePropertyName result_path -NotePropertyValue $path -Force
    $Payload | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
  }
  return ''
}

function Stop-PlanGate([string]$ErrorCode, [string]$Message, [object]$Payload, [int]$ExitCode = 43) {
  $Payload.ok = $false
  $Payload.error_code = $ErrorCode
  $Payload.message = $Message
  $resultPath = Write-Result $Payload
  if ($resultPath) { $Payload | Add-Member -NotePropertyName result_path -NotePropertyValue $resultPath -Force }
  [Console]::Error.WriteLine('KV_MNM_IMPORT_PLAN_GATE_FAILED ' + (($Payload | ConvertTo-Json -Depth 10 -Compress)))
  exit $ExitCode
}

$ScaffoldRoot = [IO.Path]::GetFullPath($ScaffoldRoot)
if (-not (Test-Path -LiteralPath $ScaffoldRoot -PathType Container)) {
  throw "ScaffoldRoot not found: $ScaffoldRoot"
}

$SourceSnapshotManifestPath = [IO.Path]::GetFullPath($SourceSnapshotManifestPath)
if (-not (Test-Path -LiteralPath $SourceSnapshotManifestPath -PathType Leaf)) {
  throw "SourceSnapshotManifestPath not found: $SourceSnapshotManifestPath"
}

if ($OutDir) {
  $OutDir = [IO.Path]::GetFullPath($OutDir)
}

$manifestPath = Join-Path $ScaffoldRoot 'scaffold.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
  throw "scaffold.json not found: $manifestPath"
}

$scaffold = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
$snapshotManifest = Get-Content -Raw -LiteralPath $SourceSnapshotManifestPath -Encoding UTF8 | ConvertFrom-Json
$manifestDir = Split-Path -Parent $SourceSnapshotManifestPath

$sourceGate = $null
if ($SourceSnapshotGateResultPath) {
  $SourceSnapshotGateResultPath = [IO.Path]::GetFullPath($SourceSnapshotGateResultPath)
  if (-not (Test-Path -LiteralPath $SourceSnapshotGateResultPath -PathType Leaf)) {
    throw "SourceSnapshotGateResultPath not found: $SourceSnapshotGateResultPath"
  }
  $sourceGate = Get-Content -Raw -LiteralPath $SourceSnapshotGateResultPath -Encoding UTF8 | ConvertFrom-Json
}

$basePayload = [ordered]@{
  ok = $true
  error_code = ''
  operation = 'assert KV MNM import plan'
  scaffold_root = $ScaffoldRoot
  scaffold_manifest = $manifestPath
  source_snapshot_manifest = $SourceSnapshotManifestPath
  source_snapshot_gate_result_path = $SourceSnapshotGateResultPath
  snapshot_status = [string]$snapshotManifest.status
  snapshot_basis = [string]$snapshotManifest.snapshot.basis
  snapshot_project_fingerprint_hash = [string]$snapshotManifest.project_fingerprint.hash
  gate_project_fingerprint_hash = if ($sourceGate) { [string]$sourceGate.project_fingerprint.hash } else { '' }
  fingerprint_strategy = 'use_existing_snapshot_inventory_only_after assert_kv_existing_project_snapshot proves current project hash equals manifest hash'
  delete_existing_modules_before_import = [bool]$DeleteExistingModulesBeforeImport
  existing_snapshot_mnm_dir = ''
  incoming_modules = @()
  existing_modules = @()
  conflicts = @()
  incoming_duplicates = @()
  delete_required = $false
  message = ''
  remediation = @(
    'If conflicts exist, rerun the existing-project update runner with -DeleteExistingModulesBeforeImport.',
    'If the source snapshot fingerprint is stale, export current MNM and variable manifests first, then rerun the gate.',
    'Do not rely on the KV STUDIO duplicate-name modal as the conflict detector.'
  )
}

if ([int]$snapshotManifest.schema_version -ne 1) {
  Stop-PlanGate 'KV_SOURCE_SNAPSHOT_SCHEMA_UNSUPPORTED' 'Snapshot manifest must use schema_version=1.' ([pscustomobject]$basePayload)
}
if ([string]$snapshotManifest.status -ne 'ready') {
  Stop-PlanGate 'KV_SOURCE_SNAPSHOT_EXPORT_REQUIRED' 'Snapshot manifest is not ready. Export current project MNM and variables before planning import.' ([pscustomobject]$basePayload)
}
if ($sourceGate -and -not [bool]$sourceGate.ok) {
  Stop-PlanGate 'KV_SOURCE_SNAPSHOT_GATE_NOT_OK' 'Source snapshot gate result is not ok; import planning cannot trust snapshot inventory.' ([pscustomobject]$basePayload)
}
if ($sourceGate -and ([string]$sourceGate.project_fingerprint.hash -ne [string]$snapshotManifest.project_fingerprint.hash)) {
  Stop-PlanGate 'KV_SOURCE_SNAPSHOT_GATE_HASH_MISMATCH' 'Source snapshot gate fingerprint hash does not match source snapshot manifest hash.' ([pscustomobject]$basePayload)
}

$mnmDir = Resolve-PathFromBase $manifestDir ([string]$snapshotManifest.artifacts.mnm_dir)
$basePayload.existing_snapshot_mnm_dir = $mnmDir
if (-not (Test-Path -LiteralPath $mnmDir -PathType Container)) {
  Stop-PlanGate 'KV_SOURCE_SNAPSHOT_MNM_DIR_MISSING' "Snapshot MNM directory not found: $mnmDir" ([pscustomobject]$basePayload)
}

$existingModules = @()
foreach ($file in @(Get-ChildItem -LiteralPath $mnmDir -File -Filter '*.mnm' -Recurse -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '\\_kv_export_workspace\\' } |
  Sort-Object FullName)) {
  $moduleName = Get-MnmModuleName $file.FullName
  if (-not [string]::IsNullOrWhiteSpace($moduleName)) {
    $existingModules += [pscustomobject]@{
      module_name = $moduleName
      name_key = Get-NameKey $moduleName
      mnm_path = $file.FullName
      sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    }
  }
}
$basePayload.existing_modules = @($existingModules | ForEach-Object {
  [ordered]@{ module_name = $_.module_name; mnm_path = $_.mnm_path; sha256 = $_.sha256 }
})
if ($existingModules.Count -eq 0) {
  Stop-PlanGate 'KV_SOURCE_SNAPSHOT_MNM_EMPTY' "Snapshot MNM directory contains no import-planning inventory: $mnmDir" ([pscustomobject]$basePayload)
}

$incomingModules = @()
foreach ($entry in @($scaffold.mnm_files)) {
  $mnmPath = Resolve-ScaffoldPath ([string]$entry.path)
  if (-not (Test-Path -LiteralPath $mnmPath -PathType Leaf)) {
    Stop-PlanGate 'KV_SCAFFOLD_MNM_FILE_MISSING' "Incoming MNM file not found: $mnmPath" ([pscustomobject]$basePayload)
  }
  $declaredName = [string]$entry.module_name
  $headerName = Get-MnmModuleName $mnmPath
  $moduleName = if ($declaredName) { $declaredName } else { $headerName }
  $incomingModules += [pscustomobject]@{
    module_name = $moduleName
    header_module_name = $headerName
    name_key = Get-NameKey $moduleName
    mnm_path = $mnmPath
    module_type = if ($null -ne $entry.module_type -and [string]$entry.module_type -ne '') { [int]$entry.module_type } else { 0 }
    category = if ($entry.category) { [string]$entry.category } else { '' }
    sha256 = (Get-FileHash -LiteralPath $mnmPath -Algorithm SHA256).Hash.ToLowerInvariant()
  }
}
$basePayload.incoming_modules = @($incomingModules | ForEach-Object {
  [ordered]@{
    module_name = $_.module_name
    header_module_name = $_.header_module_name
    mnm_path = $_.mnm_path
    module_type = $_.module_type
    category = $_.category
    sha256 = $_.sha256
  }
})

$duplicateGroups = @($incomingModules | Group-Object name_key | Where-Object { $_.Count -gt 1 })
if ($duplicateGroups.Count -gt 0) {
  $basePayload.incoming_duplicates = @($duplicateGroups | ForEach-Object {
    [ordered]@{
      name_key = $_.Name
      module_names = @($_.Group | ForEach-Object { $_.module_name })
      mnm_paths = @($_.Group | ForEach-Object { $_.mnm_path })
    }
  })
  Stop-PlanGate 'KV_MNM_INCOMING_DUPLICATE_MODULE_NAME' 'Incoming scaffold contains duplicate MNM/module names; this cannot be made safe by pre-delete.' ([pscustomobject]$basePayload)
}

$existingByKey = @{}
foreach ($existing in $existingModules) {
  if (-not $existingByKey.ContainsKey($existing.name_key)) { $existingByKey[$existing.name_key] = @() }
  $existingByKey[$existing.name_key] += $existing
}

$conflicts = @()
foreach ($incoming in $incomingModules) {
  if ($existingByKey.ContainsKey($incoming.name_key)) {
    foreach ($existing in @($existingByKey[$incoming.name_key])) {
      $conflicts += [ordered]@{
        module_name = $incoming.module_name
        incoming_mnm_path = $incoming.mnm_path
        incoming_sha256 = $incoming.sha256
        existing_mnm_path = $existing.mnm_path
        existing_sha256 = $existing.sha256
        same_content_sha256 = ([string]$incoming.sha256 -eq [string]$existing.sha256)
        required_action = 'pre_delete_existing_module_before_import'
      }
    }
  }
}

$basePayload.conflicts = @($conflicts)
$basePayload.delete_required = ($conflicts.Count -gt 0)

if ($conflicts.Count -gt 0 -and -not $DeleteExistingModulesBeforeImport) {
  Stop-PlanGate 'KV_MNM_SAME_NAME_IMPORT_REQUIRES_PREDELETE' "Same-name MNM/module conflict detected before KV STUDIO import: $((@($conflicts | ForEach-Object { $_.module_name } | Select-Object -Unique)) -join ', ')" ([pscustomobject]$basePayload)
}

$basePayload.message = if ($conflicts.Count -gt 0) {
  'Same-name MNM/module conflicts are planned with mandatory pre-delete before import.'
} else {
  'No same-name MNM/module conflicts detected in the verified source snapshot.'
}

$payload = [pscustomobject]$basePayload
$resultPath = Write-Result $payload
if ($resultPath) { $payload | Add-Member -NotePropertyName result_path -NotePropertyValue $resultPath -Force }
$payload | ConvertTo-Json -Depth 10
