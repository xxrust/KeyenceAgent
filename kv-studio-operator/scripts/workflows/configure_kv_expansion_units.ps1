param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string[]]$Models,
  [string]$OutDir = '',
  [int]$PerModuleBudgetSeconds = 10,
  [int]$TimeoutSeconds = 120,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
if (-not $OutDir) { $OutDir=Join-Path ([IO.Path]::GetTempPath()) ('kv_expansion_'+[guid]::NewGuid().ToString('N')) }
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'configure_plc_expansion_units' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
Add-KvWorkflowStep -Plan $plan -Name 'configure_units' -Script 'runner_children/configure_expansion_units_guarded.ps1' -OutDir $plan.run_root -Parameters @{ProjectPath=$plan.project_path;Models=$Models;OutDir=$plan.run_root;PerModuleBudgetSeconds=$PerModuleBudgetSeconds}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
