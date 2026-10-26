param([string]$WorkRoot = '')

$ErrorActionPreference = 'Stop'

# Offline contract for the EtherNet/IP write path:
# - script, workflow and bat exist and are wired together;
# - the workflow validates device configs before any UI work (PlanOnly);
# - the runner declares the adapter blocker instead of claiming a false success.

$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $PSScriptRoot '..\_helpers\invoke_tool.ps1')
$runner = Join-Path $skillRoot 'scripts\runner_children\configure_eip_devices_guarded.ps1'
$workflow = Join-Path $skillRoot 'scripts\workflows\configure_kv_eip_devices.ps1'
$bat = Join-Path $skillRoot 'configure_kv_eip_devices.bat'

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-eip-write-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}

Add-Case 'runner child exists' (Test-Path -LiteralPath $runner) $runner
Add-Case 'workflow exists' (Test-Path -LiteralPath $workflow) $workflow
Add-Case 'bat launcher exists' (Test-Path -LiteralPath $bat) $bat
$batText = if (Test-Path -LiteralPath $bat) { Get-Content -LiteralPath $bat -Raw -Encoding ASCII } else { '' }
Add-Case 'bat calls the workflow' ($batText -match 'scripts\\workflows\\configure_kv_eip_devices\.ps1') 'bat'
$runnerText = if (Test-Path -LiteralPath $runner) { Get-Content -LiteralPath $runner -Raw -Encoding UTF8 } else { '' }
Add-Case 'runner has adapter blocker code' ($runnerText -match 'KV_EIP_COMMUNICATION_ADAPTER_REQUIRED') 'runner'
Add-Case 'runner has preflight mode' ($runnerText -match 'PreflightOnly') 'runner'
Add-Case 'runner never fakes success' ($runnerText -match 'KV_EIP_DEVICE_ADD_UNVERIFIED') 'runner'

$projectPath = Join-Path $WorkRoot 'Fixture.kpr'
[IO.File]::WriteAllText($projectPath, 'fixture', (New-Object Text.UTF8Encoding($false)))

$validConfig = Join-Path $WorkRoot 'devices_valid.json'
[ordered]@{
  schema_version = 1
  devices = @([ordered]@{ model = 'NU-EP1'; node_address = 1; ip_address = '192.168.0.1' })
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $validConfig -Encoding UTF8

$planExit = Invoke-TestTool -ScriptPath $workflow -Arguments @('-ProjectPath', $projectPath, '-DevicesConfigPath', $validConfig, '-OutDir', (Join-Path $WorkRoot 'plan_valid'), '-PlanOnly')
Add-Case 'valid config PlanOnly exits 0' ($planExit -eq 0) "exit=$planExit"
$planPath = Join-Path $WorkRoot 'plan_valid\execution_plan.json'
Add-Case 'plan written' (Test-Path -LiteralPath $planPath) $planPath
if (Test-Path -LiteralPath $planPath) {
  $plan = Get-Content -LiteralPath $planPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $stepNames = @($plan.steps | ForEach-Object { [string]$_.name })
  Add-Case 'plan contains configure_eip_devices' ($stepNames -contains 'configure_eip_devices') ($stepNames -join ',')
}

$dupConfig = Join-Path $WorkRoot 'devices_duplicate.json'
[ordered]@{
  schema_version = 1
  devices = @(
    [ordered]@{ model = 'NU-EP1'; node_address = 1; ip_address = '192.168.0.1' },
    [ordered]@{ model = 'DL-EP1'; node_address = 1; ip_address = '192.168.0.3' }
  )
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $dupConfig -Encoding UTF8
$dupExit = Invoke-TestTool -ScriptPath $workflow -Arguments @('-ProjectPath', $projectPath, '-DevicesConfigPath', $dupConfig, '-OutDir', (Join-Path $WorkRoot 'plan_dup'), '-PlanOnly')
Add-Case 'duplicate node rejected before UI' ($dupExit -ne 0) "exit=$dupExit"

$badIpConfig = Join-Path $WorkRoot 'devices_bad_ip.json'
[ordered]@{
  schema_version = 1
  devices = @([ordered]@{ model = 'NU-EP1'; node_address = 2; ip_address = 'not-an-ip' })
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $badIpConfig -Encoding UTF8
$badIpExit = Invoke-TestTool -ScriptPath $workflow -Arguments @('-ProjectPath', $projectPath, '-DevicesConfigPath', $badIpConfig, '-OutDir', (Join-Path $WorkRoot 'plan_badip'), '-PlanOnly')
Add-Case 'invalid ip rejected before UI' ($badIpExit -ne 0) "exit=$badIpExit"

$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'eip-write-contract'; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0
