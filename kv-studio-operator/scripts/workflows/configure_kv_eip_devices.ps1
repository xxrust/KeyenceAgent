param(
  [string]$ProjectName = '',
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$DevicesConfigPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds = 600,
  [switch]$PreflightOnly,
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_workflow_plan.ps1')
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "KV_EIP_PROJECT_MISSING: $ProjectPath" }
if (-not (Test-Path -LiteralPath $DevicesConfigPath -PathType Leaf)) { throw "KV_EIP_CONFIG_MISSING: $DevicesConfigPath" }
if (-not $ProjectName) { $ProjectName=[IO.Path]::GetFileNameWithoutExtension($ProjectPath) }

# Validate the device config before any plan is created so bad input never
# reaches KV STUDIO.
$config = Get-Content -LiteralPath $DevicesConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$devices = @($config.devices)
if ($devices.Count -eq 0) { throw 'KV_EIP_CONFIG_EMPTY: devices[] is empty' }
$seen = @{}
foreach ($d in $devices) {
  if (-not $d.model) { throw 'KV_EIP_CONFIG_INVALID: device.model is required' }
  $addr = [string]$d.node_address
  if ($addr) {
    if ($addr -notmatch '^\d+$') { throw "KV_EIP_CONFIG_INVALID: node_address must be numeric: $addr" }
    if ($seen.ContainsKey([int]$addr)) { throw "KV_EIP_CONFIG_DUPLICATE_NODE: $addr" }
    $seen[[int]$addr] = $true
  }
  $ip = [string]$d.ip_address
  if ($ip -and ($ip -notmatch '^\d{1,3}(\.\d{1,3}){3}$')) { throw "KV_EIP_CONFIG_INVALID: ip_address is not IPv4: $ip" }
}

$plan=New-KvWorkflowPlan -ScriptsRoot $root -Operation 'configure_ethernet_ip_devices' -ProjectPath $ProjectPath -OutDir $OutDir -TimeoutSeconds $TimeoutSeconds
Add-KvWorkflowStep -Plan $plan -Name 'configure_eip_devices' -Script 'runner_children/configure_eip_devices_guarded.ps1' -OutDir $plan.run_root -Parameters @{ProjectName=$ProjectName;DevicesConfigPath=[IO.Path]::GetFullPath($DevicesConfigPath);OutDir=$plan.run_root;TimeoutSeconds=$TimeoutSeconds;PreflightOnly=[bool]$PreflightOnly}
Submit-KvWorkflowPlan -Plan $plan -ScriptsRoot $root -PlanOnly:$PlanOnly

