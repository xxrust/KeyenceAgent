param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$PitchCsv = '',
  [int]$StepTimeoutSeconds = 3,
  [int]$TimeoutSeconds = 300,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'complete_axis_registration' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
Add-KvWorkflowStep -Plan $plan -Name 'complete_registration' -Script 'runner_children/complete_axis_registration_guarded.ps1' -OutDir $plan.run_root -Parameters @{ProjectPath=$plan.project_path;OutDir=$plan.run_root;PitchCsv=$PitchCsv;StepTimeoutSeconds=$StepTimeoutSeconds}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly