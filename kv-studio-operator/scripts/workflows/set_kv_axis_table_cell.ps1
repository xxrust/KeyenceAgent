param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$RowIndex = 0,
  [int]$Column = 1,
  [string]$Value = '',
  [int]$TimeoutSeconds = 300,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'set_axis_table_cell' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
Add-KvWorkflowStep -Plan $plan -Name 'set_cell' -Script 'runner_children/set_axis_table_cell_guarded.ps1' -OutDir $plan.run_root -Parameters @{OutDir=$plan.run_root;RowIndex=$RowIndex;Column=$Column;Value=$Value}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly