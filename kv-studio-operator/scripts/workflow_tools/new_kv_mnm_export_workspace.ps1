param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [Parameter(Mandatory=$true)]
  [string]$ExportDir,

  [Parameter(Mandatory=$true)]
  [string]$OutDir,

  [string]$WorkRoot = '',
  [switch]$AllowWorkRootOutsideExportDir
)

$ErrorActionPreference = 'Stop'

try {
  $ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
  $ExportDir = [IO.Path]::GetFullPath($ExportDir)
  $OutDir = [IO.Path]::GetFullPath($OutDir)
  if (-not $WorkRoot) { $WorkRoot = Join-Path $ExportDir '_kv_export_workspace' }
  $WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
  New-Item -ItemType Directory -Force -Path $ExportDir, $OutDir, $WorkRoot | Out-Null

  if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "ProjectPath not found: $ProjectPath" }
  $exportRootWithSep = $ExportDir.TrimEnd('\') + '\'
  if (-not $AllowWorkRootOutsideExportDir -and -not ($WorkRoot.TrimEnd('\') + '\').StartsWith($exportRootWithSep, [StringComparison]::OrdinalIgnoreCase)) {
    throw "WorkRoot must be inside ExportDir so KV STUDIO's actual export path remains in the caller file framework. WorkRoot=$WorkRoot ExportDir=$ExportDir"
  }

  $sourceDir = [IO.Path]::GetFullPath((Split-Path -Parent $ProjectPath))
  $projectFileName = Split-Path -Leaf $ProjectPath
  $projectDirName = Split-Path -Leaf $sourceDir
  $runRoot = Join-Path $WorkRoot ('run_' + (Get-Date -Format 'yyyyMMdd_HHmmss_ffff'))
  $projectCopyParent = Join-Path $runRoot 'project'
  $coreOutDir = Join-Path $runRoot 'ui_export'
  New-Item -ItemType Directory -Force -Path $projectCopyParent, $coreOutDir | Out-Null

  Copy-Item -LiteralPath $sourceDir -Destination $projectCopyParent -Recurse -Force
  $projectCopyDir = [IO.Path]::GetFullPath((Join-Path $projectCopyParent $projectDirName))
  $runRootFull = [IO.Path]::GetFullPath($runRoot)
  if (-not $projectCopyDir.StartsWith($runRootFull, [StringComparison]::OrdinalIgnoreCase)) {
    throw "Project copy escaped run root: $projectCopyDir"
  }
  Get-ChildItem -LiteralPath $projectCopyDir -Filter '*.mnm' -File -ErrorAction SilentlyContinue | Remove-Item -Force

  $projectCopyPath = Join-Path $projectCopyDir $projectFileName
  if (-not (Test-Path -LiteralPath $projectCopyPath -PathType Leaf)) { throw "Copied project not found: $projectCopyPath" }

  $plan = [ordered]@{
    ok = $true
    operation = 'prepare KV MNM export workspace'
    project_path = $ProjectPath
    export_dir = $ExportDir
    out_dir = $OutDir
    work_root = $WorkRoot
    run_root = $runRoot
    project_copy_path = $projectCopyPath
    project_copy_dir = $projectCopyDir
    actual_kv_export_dir = $projectCopyDir
    core_out_dir = $coreOutDir
    core_result_path = Join-Path $coreOutDir 'browse_folder_export_result.json'
    result_path = Join-Path $OutDir 'export_workspace_plan.json'
  }
  $plan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $plan.result_path -Encoding UTF8
  $plan | ConvertTo-Json -Depth 6
  exit 0
} catch {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  [ordered]@{
    ok = $false
    error_code = 'KV_MNM_EXPORT_WORKSPACE_FAILED'
    operation = 'prepare KV MNM export workspace'
    project_path = $ProjectPath
    export_dir = $ExportDir
    out_dir = $OutDir
    work_root = $WorkRoot
    message = $_.Exception.ToString()
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'export_workspace_result.json') -Encoding UTF8
  exit 1
}
