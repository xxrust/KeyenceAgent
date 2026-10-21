param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$AxisLabel = '轴1:Axis_1',
  [string]$MachineType = '',
  [double]$Pitch = 25,
  [int]$StepTimeoutSeconds = 3,
  [int]$TimeoutSeconds = 300,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'set_axis_pitch' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
$p=@{OutDir=$plan.run_root;AxisLabel=$AxisLabel;Pitch=$Pitch;StepTimeoutSeconds=$StepTimeoutSeconds}
if ($MachineType) { $p['MachineType'] = $MachineType }
Add-KvWorkflowStep -Plan $plan -Name 'set_pitch' -Script 'runner_children/set_axis_pitch_guarded.ps1' -OutDir $plan.run_root -Parameters $p
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
