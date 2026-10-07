param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string[]]$StructureName = @(),
  [int]$TimeoutSeconds = 600,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
# The public PowerShell boundary commonly receives a comma-separated value
# from BAT/JSON launchers. Normalize it once so callers can request one or
# more structures without relying on repeated array-parameter syntax.
$StructureName = @($StructureName | ForEach-Object {
  ([string]$_ -split ',' | ForEach-Object { $_.Trim() })
} | Where-Object { $_ })
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'export_structure_definitions' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
Add-KvWorkflowStep -Plan $plan -Name 'export_structures' -Script 'runner_children/export_structure_definitions_guarded.ps1' -OutDir $plan.run_root -Parameters @{ProjectPath=$plan.project_path;OutDir=$plan.run_root;StructureName=$StructureName}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
