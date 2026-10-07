param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$ChecklistPath='',
  [string]$CreatedProjectResultPath='',
  [int]$TimeoutSeconds=90,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'compile_project' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
$compileOut=Join-Path $plan.artifact_root 'compile'
$copyOut=Join-Path $plan.artifact_root 'compile_result'
Add-KvWorkflowStep -Plan $plan -Name 'compile' -Script 'runner_children/compile_and_copy_result_bounded.ps1' -OutDir $compileOut -Parameters @{ProjectPath=$plan.project_path;CreatedProjectResultPath=$CreatedProjectResultPath;OutDir=$compileOut;ChecklistPath=$ChecklistPath;ConvertAction='CtrlF9';WaitSeconds=40}
Add-KvWorkflowStep -Plan $plan -Name 'copy_compile_result' -Script 'runner_children/copy_convert_result_from_tree_handle.ps1' -OutDir $copyOut -Parameters @{ProjectNeedle=$plan.project_name;ProjectPath=$plan.project_path;CreatedProjectResultPath=$CreatedProjectResultPath;OutDir=$copyOut;ChecklistPath=$ChecklistPath;MaxLookupMs=8000}
$plan.require_compile_result=$true
$plan.compile_result_path=Join-Path $copyOut 'compile_result_copied.txt'
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
