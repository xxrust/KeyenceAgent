param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [Parameter(Mandatory=$true)]
  [string]$SnapshotManifestPath,

  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'

function Write-Result([object]$Payload) {
  if ($OutDir) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $path = Join-Path $OutDir 'existing_project_snapshot_gate.json'
    $Payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
  }
  return ''
}

function Stop-Gate([string]$ErrorCode, [string]$Message, [string[]]$Evidence = @(), [int]$ExitCode = 42) {
  $payload = [ordered]@{
    ok = $false
    error_code = $ErrorCode
    operation = 'assert KV existing project source snapshot'
    project_path = $ProjectPath
    snapshot_manifest_path = $SnapshotManifestPath
    message = $Message
    evidence = $Evidence
    remediation = @(
      'Open the exact current .kpr in KV STUDIO and export MNM plus variable manifests into a task source_snapshot directory.',
      'Run new_kv_existing_project_update_workspace.ps1 again, or update the manifest after the fresh export.',
      'Do not run existing-project repair/update until this gate reports ok=true.'
    )
  }
  $resultPath = Write-Result $payload
  if ($resultPath) { $payload.evidence = @($Evidence + $resultPath) }
  [Console]::Error.WriteLine('KV_EXISTING_PROJECT_SNAPSHOT_GATE_FAILED ' + (($payload | ConvertTo-Json -Depth 8 -Compress)))
  exit $ExitCode
}

function Resolve-ManifestPath([string]$BaseDir, [string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  return [IO.Path]::GetFullPath((Join-Path $BaseDir $Path))
}

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

$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
  Stop-Gate 'KV_EXISTING_PROJECT_PATH_MISSING' "ProjectPath not found: $ProjectPath"
}

$SnapshotManifestPath = [IO.Path]::GetFullPath($SnapshotManifestPath)
if (-not (Test-Path -LiteralPath $SnapshotManifestPath -PathType Leaf)) {
  Stop-Gate 'KV_SOURCE_SNAPSHOT_MANIFEST_MISSING' "Snapshot manifest not found: $SnapshotManifestPath"
}

$manifestDir = Split-Path -Parent $SnapshotManifestPath
try {
  $manifest = Get-Content -Raw -LiteralPath $SnapshotManifestPath -Encoding UTF8 | ConvertFrom-Json
} catch {
  Stop-Gate 'KV_SOURCE_SNAPSHOT_MANIFEST_INVALID_JSON' "Snapshot manifest is not valid JSON: $($_.Exception.Message)" @($SnapshotManifestPath)
}

if ([int]$manifest.schema_version -ne 1) {
  Stop-Gate 'KV_SOURCE_SNAPSHOT_SCHEMA_UNSUPPORTED' 'Snapshot manifest must use schema_version=1.' @($SnapshotManifestPath)
}

$status = [string]$manifest.status
if ($status -ne 'ready') {
  Stop-Gate 'KV_SOURCE_SNAPSHOT_NOT_READY' "Snapshot status must be ready before updating an existing project. status=$status" @($SnapshotManifestPath)
}

$projectRoot = Get-ProjectRoot $ProjectPath
$currentFingerprint = Get-DirectoryFingerprint $projectRoot
$expectedHash = [string]$manifest.project_fingerprint.hash
if (-not $expectedHash) {
  Stop-Gate 'KV_SOURCE_SNAPSHOT_FINGERPRINT_MISSING' 'Snapshot manifest missing project_fingerprint.hash.' @($SnapshotManifestPath)
}
if ($currentFingerprint.hash -ne $expectedHash) {
  $fingerprintPath = ''
  if ($OutDir) {
    New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
    $fingerprintPath = Join-Path $OutDir 'current_project_fingerprint.json'
    $currentFingerprint | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $fingerprintPath -Encoding UTF8
  }
  Stop-Gate 'KV_SOURCE_SNAPSHOT_STALE' "Current project fingerprint differs from the parsed source snapshot. expected=$expectedHash actual=$($currentFingerprint.hash)" @($SnapshotManifestPath, $fingerprintPath)
}

$snapshotPath = Resolve-ManifestPath $manifestDir ([string]$manifest.snapshot.path)
if (-not $snapshotPath -or -not (Test-Path -LiteralPath $snapshotPath -PathType Container)) {
  Stop-Gate 'KV_SOURCE_SNAPSHOT_PATH_MISSING' "Snapshot directory not found: $snapshotPath" @($SnapshotManifestPath)
}

$mnmDir = Resolve-ManifestPath $manifestDir ([string]$manifest.artifacts.mnm_dir)
$variablesDir = Resolve-ManifestPath $manifestDir ([string]$manifest.artifacts.variables_dir)
$inventoryDir = Resolve-ManifestPath $manifestDir ([string]$manifest.artifacts.inventory_dir)
$architecturePath = Resolve-ManifestPath $manifestDir ([string]$manifest.architecture.path)

if (-not (Test-Path -LiteralPath $mnmDir -PathType Container)) {
  Stop-Gate 'KV_SOURCE_SNAPSHOT_MNM_DIR_MISSING' "MNM snapshot directory not found: $mnmDir" @($SnapshotManifestPath)
}
if (-not (Test-Path -LiteralPath $variablesDir -PathType Container)) {
  Stop-Gate 'KV_SOURCE_SNAPSHOT_VARIABLE_DIR_MISSING' "Variable snapshot directory not found: $variablesDir" @($SnapshotManifestPath)
}
if (-not (Test-Path -LiteralPath $inventoryDir -PathType Container)) {
  Stop-Gate 'KV_SOURCE_SNAPSHOT_INVENTORY_DIR_MISSING' "Inventory snapshot directory not found: $inventoryDir" @($SnapshotManifestPath)
}
if (-not (Test-Path -LiteralPath $architecturePath -PathType Leaf)) {
  Stop-Gate 'KV_UPDATE_ARCHITECTURE_FILE_MISSING' "Open architecture file not found: $architecturePath" @($SnapshotManifestPath)
}

$mnmFiles = @(Get-ChildItem -LiteralPath $mnmDir -File -Filter '*.mnm' -Recurse -ErrorAction SilentlyContinue |
  Where-Object { $_.FullName -notmatch '\\_kv_export_workspace\\' } |
  Sort-Object FullName)
if ($mnmFiles.Count -eq 0) {
  Stop-Gate 'KV_SOURCE_SNAPSHOT_MNM_EMPTY' "Snapshot must contain at least one exported or verified MNM file: $mnmDir" @($SnapshotManifestPath)
}

$variableFiles = @(Get-ChildItem -LiteralPath $variablesDir -File -Recurse -ErrorAction SilentlyContinue |
  Where-Object { $_.Extension -in @('.tsv', '.csv', '.json') })
if ($variableFiles.Count -eq 0) {
  Stop-Gate 'KV_SOURCE_SNAPSHOT_VARIABLES_EMPTY' "Snapshot must contain exported or verified variable manifests: $variablesDir" @($SnapshotManifestPath)
}
$stubVariableFiles = @($variableFiles | Where-Object {
  $_.Name -match '(?i)stub|placeholder|dummy' -or
  ((Get-Content -Raw -LiteralPath $_.FullName -ErrorAction SilentlyContinue) -match '(?i)stub|placeholder|dummy|CodexLocalProbe')
})
if ($stubVariableFiles.Count -gt 0) {
  Stop-Gate 'KV_SOURCE_SNAPSHOT_VARIABLES_STUB' "Snapshot variable evidence contains stub/placeholder/dummy files and cannot prove the current project variables: $($stubVariableFiles.FullName -join ', ')" @($SnapshotManifestPath, @($stubVariableFiles | ForEach-Object { $_.FullName }))
}

$inventoryFiles = @(Get-ChildItem -LiteralPath $inventoryDir -File -Recurse -ErrorAction SilentlyContinue)
if ($inventoryFiles.Count -eq 0) {
  Stop-Gate 'KV_SOURCE_SNAPSHOT_INVENTORY_EMPTY' "Snapshot must contain project inventory evidence: $inventoryDir" @($SnapshotManifestPath)
}

try {
  $architecture = Get-Content -Raw -LiteralPath $architecturePath -Encoding UTF8 | ConvertFrom-Json
} catch {
  Stop-Gate 'KV_UPDATE_ARCHITECTURE_INVALID_JSON' "Architecture file is not valid JSON: $($_.Exception.Message)" @($architecturePath)
}
if (-not $architecture.extension_points) {
  Stop-Gate 'KV_UPDATE_ARCHITECTURE_NOT_OPEN' 'Architecture file must contain extension_points for future configuration categories.' @($architecturePath)
}

$payload = [ordered]@{
  ok = $true
  operation = 'assert KV existing project source snapshot'
  project_path = $ProjectPath
  project_root = $projectRoot
  snapshot_manifest_path = $SnapshotManifestPath
  snapshot_path = $snapshotPath
  project_fingerprint = $currentFingerprint
  mnm_count = $mnmFiles.Count
  variable_manifest_count = $variableFiles.Count
  inventory_file_count = $inventoryFiles.Count
  architecture_path = $architecturePath
}
$resultPath = Write-Result $payload
if ($resultPath) { $payload.result_path = $resultPath }
$payload | ConvertTo-Json -Depth 8
