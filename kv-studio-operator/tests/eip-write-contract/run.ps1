param([string]$WorkRoot = '')

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

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

Add-Case 'runner rejects manual-mode failure' ($runnerText -match 'KV_EIP_MANUAL_MODE_NOT_SELECTED') 'runner'
Add-Case 'runner has preflight mode' ($runnerText -match 'PreflightOnly') 'runner'

Add-Case 'runner scans the catalog for the model' ($runnerText -match 'KV_EIP_MODEL_NOT_IN_CATALOG') 'runner'
Add-Case 'runner handles KV update prompts' ($runnerText -match 'Handle-EipDialogs') 'runner'
Add-Case 'runner proves the write by readback' ($runnerText -match 'pre_write_readback' -and $runnerText -match 'KV_EIP_READBACK_FAILED') 'runner'

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

$batchConfig = Join-Path $WorkRoot 'devices_batch.json'
[ordered]@{
  schema_version = 1
  devices = @(
    [ordered]@{ model = 'NU-EP1'; node_address = 1; ip_address = '192.168.0.1' },
    [ordered]@{ model = 'DL-EP1'; node_address = 2; ip_address = '192.168.0.2' }
  )
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $batchConfig -Encoding UTF8
$batchExit = Invoke-TestTool -ScriptPath $workflow -Arguments @('-ProjectPath', $projectPath, '-DevicesConfigPath', $batchConfig, '-OutDir', (Join-Path $WorkRoot 'plan_batch'), '-PlanOnly')
Add-Case 'multi-device batch rejected before UI' ($batchExit -ne 0) "exit=$batchExit"


# --- Modify / Delete contract (live-verified 2026-10-28) ---
$editRunner = Join-Path $skillRoot 'scripts\runner_children\edit_eip_devices_guarded.ps1'
$deleteBat = Join-Path $skillRoot 'delete_kv_eip_device.bat'
$modifyBat = Join-Path $skillRoot 'modify_kv_eip_device.bat'
Add-Case 'edit runner exists' (Test-Path -LiteralPath $editRunner) $editRunner
Add-Case 'delete bat exists' (Test-Path -LiteralPath $deleteBat) $deleteBat
Add-Case 'modify bat exists' (Test-Path -LiteralPath $modifyBat) $modifyBat
$deleteBatText = if (Test-Path $deleteBat) { Get-Content -LiteralPath $deleteBat -Raw -Encoding ASCII } else { '' }
$modifyBatText = if (Test-Path $modifyBat) { Get-Content -LiteralPath $modifyBat -Raw -Encoding ASCII } else { '' }
Add-Case 'delete bat routes Action Delete' ($deleteBatText -match '-Action Delete') 'bat'
Add-Case 'modify bat routes Action Modify' ($modifyBatText -match '-Action Modify') 'bat'
$editText = if (Test-Path $editRunner) { Get-Content -LiteralPath $editRunner -Raw -Encoding UTF8 } else { '' }
Add-Case 'edit runner proves readback' ($editText -match 'KV_EIP_EDIT_READBACK_FAILED') 'runner'
Add-Case 'edit runner marks verified flag' ($editText -match 'verified = \$false') 'runner'
Add-Case 'workflow validates Action set' ((Get-Content -LiteralPath $workflow -Raw -Encoding UTF8) -match "ValidateSet\('Add','Modify','Delete'\)") 'workflow'

$delConfig = Join-Path $WorkRoot 'devices_delete.json'
[ordered]@{ schema_version = 1; devices = @([ordered]@{ node_address = 6 }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $delConfig -Encoding UTF8
$delExit = Invoke-TestTool -ScriptPath $workflow -Arguments @('-ProjectPath', $projectPath, '-DevicesConfigPath', $delConfig, '-OutDir', (Join-Path $WorkRoot 'plan_delete'), '-Action', 'Delete', '-PlanOnly')
Add-Case 'delete PlanOnly exits 0' ($delExit -eq 0) "exit=$delExit"

$modConfig = Join-Path $WorkRoot 'devices_modify.json'
[ordered]@{ schema_version = 1; devices = @([ordered]@{ node_address = 6; ip_address = '192.168.0.16' }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $modConfig -Encoding UTF8
$modExit = Invoke-TestTool -ScriptPath $workflow -Arguments @('-ProjectPath', $projectPath, '-DevicesConfigPath', $modConfig, '-OutDir', (Join-Path $WorkRoot 'plan_modify'), '-Action', 'Modify', '-PlanOnly')
Add-Case 'modify PlanOnly exits 0' ($modExit -eq 0) "exit=$modExit"

$modBad = Join-Path $WorkRoot 'devices_modify_noip.json'
[ordered]@{ schema_version = 1; devices = @([ordered]@{ node_address = 6 }) } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $modBad -Encoding UTF8
$modBadExit = Invoke-TestTool -ScriptPath $workflow -Arguments @('-ProjectPath', $projectPath, '-DevicesConfigPath', $modBad, '-OutDir', (Join-Path $WorkRoot 'plan_modify_bad'), '-Action', 'Modify', '-PlanOnly')
Add-Case 'modify without ip rejected' ($modBadExit -ne 0) "exit=$modBadExit"

$modPreflightExit = Invoke-TestTool -ScriptPath $workflow -Arguments @('-ProjectPath', $projectPath, '-DevicesConfigPath', $modConfig, '-OutDir', (Join-Path $WorkRoot 'plan_modify_preflight'), '-Action', 'Modify', '-PreflightOnly')
Add-Case 'modify + PreflightOnly rejected' ($modPreflightExit -ne 0) "exit=$modPreflightExit"

# A deliberate failing case proves the harness counts failures instead of
# reporting a false green. Enabled by KV_EIP_CONTRACT_SELFTEST=1.
Add-Case 'selftest deliberate failure' ($env:KV_EIP_CONTRACT_SELFTEST -ne '1') 'set KV_EIP_CONTRACT_SELFTEST=1 to invert this case'

$failed = @($cases | Where-Object { -not $_.ok })
$passed = @($cases | Where-Object { $_.ok })
$result = [ordered]@{ test = 'eip-write-contract'; passed = $passed.Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0 -or ($passed.Count + $failed.Count) -ne $cases.Count) { exit 41 }
exit 0


