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

$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$ExportDir = [IO.Path]::GetFullPath($ExportDir)
if (-not $OutDir) { $OutDir = Join-Path $ExportDir ('_export_mnm_project_copy_' + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
$OutDir = [IO.Path]::GetFullPath($OutDir)

$prepareTool = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scriptRoot -Name 'new_kv_mnm_export_workspace.ps1' -Classes @('workflow_tool')
$collectTool = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scriptRoot -Name 'collect_kv_mnm_export_workspace.ps1' -Classes @('workflow_tool')
$core = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scriptRoot -Name 'export_mnm_browse_default_folder_guarded.ps1' -Classes @('runner_child_approved')

$prepareArgs = @(
  '-NoProfile','-ExecutionPolicy','Bypass','-File',$prepareTool,
  '-ProjectPath',$ProjectPath,
  '-ExportDir',$ExportDir,
  '-OutDir',$OutDir
)
if ($WorkRoot) { $prepareArgs += @('-WorkRoot',$WorkRoot) }
if ($AllowWorkRootOutsideExportDir) { $prepareArgs += '-AllowWorkRootOutsideExportDir' }

& powershell @prepareArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$planPath = Join-Path $OutDir 'export_workspace_plan.json'
if (-not (Test-Path -LiteralPath $planPath -PathType Leaf)) { throw "Export workspace plan was not created: $planPath" }
$plan = Get-Content -Raw -LiteralPath $planPath -Encoding UTF8 | ConvertFrom-Json

$coreArgs = @(
  '-NoProfile','-ExecutionPolicy','Bypass','-File',$core,
  '-ProjectPath',([string]$plan.project_copy_path),
  '-ExportDir',([string]$plan.project_copy_dir),
  '-OutDir',([string]$plan.core_out_dir),
  '-TimeoutSeconds',([string]$TimeoutSeconds)
)
if ($KvsExe) { $coreArgs += @('-KvsExe',$KvsExe) }
if (-not $NoRestartKvs) { $coreArgs += '-RestartKvs' }
& powershell @coreArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$collectArgs = @(
  '-NoProfile','-ExecutionPolicy','Bypass','-File',$collectTool,
  '-PlanPath',$planPath
)
if ($AllowOverwrite) { $collectArgs += '-AllowOverwrite' }
& powershell @collectArgs
exit $LASTEXITCODE
