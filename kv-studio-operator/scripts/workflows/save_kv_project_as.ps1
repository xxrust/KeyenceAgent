param(
  [Parameter(Mandatory=$true)][string]$SourceProjectPath,
  [Parameter(Mandatory=$true)][string]$DestinationDirectory,
  [Parameter(Mandatory=$true)][string]$DestinationProjectName,
  [string]$Comment = '',
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds = 30,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'save_kv_project_as' -ProjectPath ([IO.Path]::GetFullPath($SourceProjectPath)) -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds -ResultName 'save_as_workflow_result.json'
$dest=Join-Path $plan.artifact_root 'save_as'
Add-KvWorkflowStep -Plan $plan -Name 'save_as' -Script 'runner_children/save_as_project_guarded.ps1' -Class 'runner_child_approved' -OutDir $dest -Parameters @{SourceProjectPath=$plan.project_path;DestinationDirectory=[IO.Path]::GetFullPath($DestinationDirectory);DestinationProjectName=$DestinationProjectName;Comment=$Comment;OutDir=$dest;TimeoutSeconds=$TimeoutSeconds}
$plan.result_path=Join-Path $OutDir 'save_as_workflow_result.json'
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
