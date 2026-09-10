param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$PlanPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds = 600,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw "KV_STRUCTURE_PLAN_MISSING: $PlanPath" }
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'mutate_structure_definitions' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
Add-KvWorkflowStep -Plan $plan -Name 'mutate_structures' -Script 'runner_children/mutate_structure_definitions_guarded.ps1' -OutDir $plan.run_root -Parameters @{ProjectPath=$plan.project_path;PlanPath=[IO.Path]::GetFullPath($PlanPath);OutDir=$plan.run_root}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
