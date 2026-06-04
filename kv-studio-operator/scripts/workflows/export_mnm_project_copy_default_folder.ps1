param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [Parameter(Mandatory=$true)]
  [string]$ExportDir,

  [string]$OutDir = '',
  [string]$WorkRoot = '',
  [string]$KvsExe = '',
  [switch]$AllowOverwrite,
  [switch]$AllowWorkRootOutsideExportDir,
  [switch]$NoRestartKvs,
  [int]$TimeoutSeconds = 120
)

$ErrorActionPreference = 'Stop'
$workflowScriptDir = Split-Path -Parent $PSCommandPath
$resolver = Join-Path (Split-Path -Parent $workflowScriptDir) 'Resolve-KvStudioOperatorScript.ps1'
if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) { throw "Script resolver not found: $resolver" }
. $resolver
$scriptRoot = Get-KvStudioOperatorScriptsRoot -StartPath $PSCommandPath

function Write-Result([bool]$Ok, [string]$Code, [string]$Message, [object[]]$MnmFiles = @(), [string]$CoreResultPath = '') {
  [ordered]@{
    ok = $Ok
    error_code = $Code
    operation = 'export MNM through project-copy default Browse Folder selection'
    project_path = $ProjectPath
    export_dir = $ExportDir
    out_dir = $OutDir
    work_root = $WorkRoot
    actual_kv_export_dir = $script:ActualKvExportDir
    core_result_path = $CoreResultPath
    message = $Message
    mnm_files = @($MnmFiles)
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutDir 'export_mnm_project_copy_result.json') -Encoding UTF8
}

try {
  $ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
  $ExportDir = [IO.Path]::GetFullPath($ExportDir)
  if (-not $OutDir) { $OutDir = Join-Path $ExportDir ('_export_mnm_project_copy_' + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
  $OutDir = [IO.Path]::GetFullPath($OutDir)
  if (-not $WorkRoot) { $WorkRoot = Join-Path $ExportDir '_kv_export_workspace' }
  $WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
  $exportRootWithSep = $ExportDir.TrimEnd('\') + '\'
  if (-not $AllowWorkRootOutsideExportDir -and -not ($WorkRoot.TrimEnd('\') + '\').StartsWith($exportRootWithSep, [StringComparison]::OrdinalIgnoreCase)) {
    throw "WorkRoot must be inside ExportDir so KV STUDIO's actual export path remains in the caller file framework. WorkRoot=$WorkRoot ExportDir=$ExportDir"
  }

  New-Item -ItemType Directory -Force -Path $ExportDir, $OutDir, $WorkRoot | Out-Null
  if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "ProjectPath not found: $ProjectPath" }

  $sourceDir = [IO.Path]::GetFullPath((Split-Path -Parent $ProjectPath))
  $projectFileName = Split-Path -Leaf $ProjectPath
  $projectDirName = Split-Path -Leaf $sourceDir
  $runRoot = Join-Path $WorkRoot ('run_' + (Get-Date -Format 'yyyyMMdd_HHmmss_ffff'))
  $projectCopyParent = Join-Path $runRoot 'project'
  New-Item -ItemType Directory -Force -Path $projectCopyParent | Out-Null

  Copy-Item -LiteralPath $sourceDir -Destination $projectCopyParent -Recurse -Force
  $projectCopyDir = [IO.Path]::GetFullPath((Join-Path $projectCopyParent $projectDirName))
  $runRootFull = [IO.Path]::GetFullPath($runRoot)
  if (-not $projectCopyDir.StartsWith($runRootFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Project copy escaped run root: $projectCopyDir"
  }
  Get-ChildItem -LiteralPath $projectCopyDir -Filter '*.mnm' -File -ErrorAction SilentlyContinue | Remove-Item -Force

  $projectCopyPath = Join-Path $projectCopyDir $projectFileName
  if (-not (Test-Path -LiteralPath $projectCopyPath -PathType Leaf)) { throw "Copied project not found: $projectCopyPath" }
  $script:ActualKvExportDir = $projectCopyDir

  $core = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scriptRoot -Name 'export_mnm_browse_default_folder_guarded.ps1' -Classes @('runner_child_approved')
  if (-not (Test-Path -LiteralPath $core -PathType Leaf)) { throw "Core export script not found: $core" }
  $coreOutDir = Join-Path $runRoot 'ui_export'

  $args = @(
    '-NoProfile','-ExecutionPolicy','Bypass','-File',$core,
    '-ProjectPath',$projectCopyPath,
    '-ExportDir',$projectCopyDir,
    '-OutDir',$coreOutDir,
    '-AcceptDefaultFolder',
    '-TimeoutSeconds',([string]$TimeoutSeconds)
  )
  if ($KvsExe) { $args += @('-KvsExe', $KvsExe) }
  if (-not $NoRestartKvs) { $args += '-RestartKvs' }
  & powershell @args
  $coreExit = $LASTEXITCODE
  $coreResultPath = Join-Path $coreOutDir 'browse_folder_export_result.json'
  if ($coreExit -ne 0) { throw "Core export failed with exit code $coreExit. Result: $coreResultPath" }
  if (-not (Test-Path -LiteralPath $coreResultPath -PathType Leaf)) { throw "Core result missing: $coreResultPath" }

  $coreResult = Get-Content -LiteralPath $coreResultPath -Raw | ConvertFrom-Json
  if (-not $coreResult.ok) { throw "Core result not ok: $($coreResult.error_code) $($coreResult.message)" }

  $copied = @()
  foreach ($file in @(Get-ChildItem -LiteralPath $projectCopyDir -Filter '*.mnm' -File -ErrorAction Stop)) {
    $target = Join-Path $ExportDir $file.Name
    if ((Test-Path -LiteralPath $target -PathType Leaf) -and -not $AllowOverwrite) {
      throw "Target MNM already exists; pass -AllowOverwrite or use an empty ExportDir: $target"
    }
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force:$AllowOverwrite
    $copied += Get-Item -LiteralPath $target | Select-Object FullName, Length, LastWriteTime
  }
  if ($copied.Count -eq 0) { throw "No MNM files copied to ExportDir: $ExportDir" }
  $copied | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'mnm_files.json') -Encoding UTF8
  Write-Result $true '' 'MNM export completed through project-copy default folder route.' $copied $coreResultPath
  exit 0
} catch {
  $message = $_.Exception.ToString()
  $code = 'KV_MNM_PROJECT_COPY_EXPORT_FAILED'
  if ($message -like '*Target MNM already exists*') { $code = 'KV_MNM_EXPORT_TARGET_EXISTS' }
  if ($message -like '*Core export failed*') { $code = 'KV_MNM_EXPORT_CORE_FAILED' }
  if ($message -like '*No MNM files copied*') { $code = 'KV_MNM_EXPORT_NO_FILES' }
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $message | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  Write-Result $false $code $message @() ''
  exit 1
}
