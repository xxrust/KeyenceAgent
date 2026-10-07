param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds = 120,
  [switch]$PlanOnly,
  [switch]$KeepVariableEditorOpen
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')

$plan = New-KvWorkflowPlan -ScriptsRoot $root -Operation 'snapshot_global_variables_all_groups' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds -ResultName 'global_groups_workflow_result.json'
$dest = Join-Path $plan.artifact_root 'global_variables_all_groups'
$parameters = @{
  ProjectPath = $plan.project_path
  OutDir = $dest
  SkillRoot = $root
  KeepVariableEditorOpen = [bool]$KeepVariableEditorOpen
}
Add-KvWorkflowStep -Plan $plan -Name 'global_variables_all_groups' -Script 'runner_children/snapshot_global_variables_all_groups_guarded.ps1' -OutDir $dest -Parameters $parameters
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
