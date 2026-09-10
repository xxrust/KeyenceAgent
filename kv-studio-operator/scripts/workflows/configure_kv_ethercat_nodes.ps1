param(
  [string]$ProjectName = '',
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$NodesConfigPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds = 600,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
if (-not (Test-Path -LiteralPath $NodesConfigPath -PathType Leaf)) { throw "KV_NODES_CONFIG_MISSING: $NodesConfigPath" }
if (-not $ProjectName) { $ProjectName=[IO.Path]::GetFileNameWithoutExtension($ProjectPath) }
$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'configure_ethercat_nodes' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
Add-KvWorkflowStep -Plan $plan -Name 'configure_nodes' -Script 'runner_children/configure_ethercat_nodes_guarded.ps1' -OutDir $plan.run_root -Parameters @{ProjectName=$ProjectName;ProjectPath=$plan.project_path;NodesConfigPath=[IO.Path]::GetFullPath($NodesConfigPath);OutDir=$plan.run_root}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
