param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$ExportDir,
  [string]$OutDir = '',
  [string]$WorkRoot = '',
  [string]$KvsExe = '',
  [switch]$AllowOverwrite,
  [switch]$AllowWorkRootOutsideExportDir,
  [switch]$NoRestartKvs,
  [int]$TimeoutSeconds = 120,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
$ExportDir=[IO.Path]::GetFullPath($ExportDir)
if (-not $OutDir) { $OutDir=Join-Path $ExportDir ('_export_'+[guid]::NewGuid().ToString('N')) }
if (-not $WorkRoot) { $WorkRoot=Join-Path $ExportDir '_kv_export_workspace' }
$WorkRoot=[IO.Path]::GetFullPath($WorkRoot)
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'export_mnm_project_copy' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
$copyRun=Join-Path $WorkRoot ('run_'+[guid]::NewGuid().ToString('N'))
$sourceDir=Split-Path -Parent $plan.project_path
$copyDir=Join-Path (Join-Path $copyRun 'project') (Split-Path -Leaf $sourceDir)
$copyPath=Join-Path $copyDir (Split-Path -Leaf $plan.project_path)
$prepareOut=Join-Path $plan.artifact_root 'export_workspace'
$coreOut=Join-Path $copyRun 'ui_export'
Add-KvWorkflowStep -Plan $plan -Name 'prepare_export' -Script 'workflow_tools/new_kv_mnm_export_workspace.ps1' -Class workflow_tool -OutDir $prepareOut -Parameters @{ProjectPath=$plan.project_path;ExportDir=$ExportDir;OutDir=$prepareOut;WorkRoot=$WorkRoot;RunRoot=$copyRun;AllowWorkRootOutsideExportDir=[bool]$AllowWorkRootOutsideExportDir}
$coreParams=@{ProjectPath=$copyPath;ExportDir=$copyDir;OutDir=$coreOut;TimeoutSeconds=$TimeoutSeconds;RestartKvs=(-not $NoRestartKvs)}
if ($KvsExe) { $coreParams.KvsExe=$KvsExe }
Add-KvWorkflowStep -Plan $plan -Name 'export_mnm' -Script 'runner_children/export_mnm_browse_default_folder_guarded.ps1' -OutDir $coreOut -Parameters $coreParams
Add-KvWorkflowStep -Plan $plan -Name 'collect_export' -Script 'workflow_tools/collect_kv_mnm_export_workspace.ps1' -Class workflow_tool -OutDir $plan.run_root -Parameters @{PlanPath=(Join-Path $prepareOut 'export_workspace_plan.json');OutDir=$plan.run_root;AllowOverwrite=[bool]$AllowOverwrite}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
