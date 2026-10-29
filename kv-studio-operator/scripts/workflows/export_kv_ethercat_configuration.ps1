param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$ProjectName = '',
  [int]$TimeoutSeconds = 300,
  [switch]$PlanOnly
)
# Read-only export of the EtherCAT network: master settings plus every slave's
# address / product / vendor / revision from 设备设定 -> 节点设定.
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "KV_PROJECT_FILE_MISSING: $ProjectPath" }
if (-not $ProjectName) { $ProjectName = [IO.Path]::GetFileNameWithoutExtension($ProjectPath) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$plan = New-KvWorkflowPlan -ScriptsRoot $root -Operation 'export_ethercat_configuration' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds -ResultName 'ethercat_configuration_result.json'
$configurationPath = Join-Path $plan.run_root 'ethercat_configuration.json'
Add-KvWorkflowStep -Plan $plan -Name 'read_configuration' -Script 'runner_children/configure_ethercat_nodes_guarded.ps1' -OutDir $plan.run_root -Parameters @{
  ProjectName = $ProjectName
  ProjectPath = $plan.project_path
  OutDir = $plan.run_root
  ReadConfigurationOnly = $true
  ConfigurationOutPath = $configurationPath
}
$exitCode = 0
try {
  Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly
} catch {
  $exitCode = 1
}
$configuration = $null
if (Test-Path -LiteralPath $configurationPath -PathType Leaf) {
  try { $configuration = Get-Content -Raw -LiteralPath $configurationPath -Encoding UTF8 | ConvertFrom-Json } catch {}
  $publicConfiguration = Join-Path $OutDir 'ethercat_configuration.json'
  if ([IO.Path]::GetFullPath($publicConfiguration) -ne [IO.Path]::GetFullPath($configurationPath)) { Copy-Item -LiteralPath $configurationPath -Destination $publicConfiguration -Force }
}
$nodes = @()
$master = $null
$nodeCount = 0
if ($configuration -and $configuration.configuration) {
  $nodes = @($configuration.configuration.nodes)
  $master = $configuration.configuration.master_settings
  $nodeCount = if ($configuration.configuration.node_count) { [int]$configuration.configuration.node_count } else { @($nodes).Count }
}
$result = [ordered]@{
  ok = ($exitCode -eq 0 -and $configuration -and $configuration.ok -eq $true)
  planned = [bool]$PlanOnly
  project_path = $ProjectPath
  project_name = $ProjectName
  configuration_path = (Join-Path $OutDir 'ethercat_configuration.json')
  node_count = $nodeCount
  master_settings = $master
  nodes = $nodes
  source_result = $configurationPath
}
$resultPath = Join-Path $OutDir 'ethercat_configuration_result.json'
$result | ConvertTo-Json -Depth 14 | Set-Content -LiteralPath $resultPath -Encoding UTF8
$result | ConvertTo-Json -Depth 6
if ($PlanOnly -or $result.ok) { exit 0 }
exit 1
