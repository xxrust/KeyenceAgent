param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$CreatedProjectResultPath='',
  [int]$TimeoutSeconds=180,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'export_project_mnm' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
$dest=Join-Path $plan.artifact_root 'export'
Add-KvWorkflowStep -Plan $plan -Name 'export' -Script 'runner_children/export_mnm_browse_default_folder_guarded.ps1' -OutDir $dest -Parameters @{ProjectPath=$plan.project_path;ExportDir=(Split-Path -Parent $plan.project_path);CreatedProjectResultPath=$CreatedProjectResultPath;OutDir=$dest;RestartKvs=$false;TimeoutSeconds=90}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
