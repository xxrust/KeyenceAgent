param([string]$WorkRoot = '')
$ErrorActionPreference = 'Stop'
$helper = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..\scripts\workflow_tools\compute_kv_clone_readiness.ps1'))
if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-clone-readiness-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') { $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail }) }
function New-Inventory([hashtable]$Status, [int]$ExpansionCount) {
  [pscustomobject]@{
    asset_status = [pscustomobject]$Status
    topology = [pscustomobject]@{
      expansion_units = if ($ExpansionCount -gt 0) { @(1..$ExpansionCount | ForEach-Object { [pscustomobject]@{ slot = $_ } }) } else { @() }
    }
  }
}
$complete = @{
  program_fb = 'complete'; variables = 'complete'; data_types = 'complete'
  ethercat_pdo = 'ui_read_complete'; ethercat_device_parameters = 'structured'
  ethernet_ip = 'ui_read_complete'; eip_connection = 'ui_read_complete'
  motion_axes = 'ui_dump_complete'; axis_parameters = 'ui_dump_complete'
  motion_axis_groups = 'ui_dump_complete'; motion_point_parameters = 'ui_dump_complete'
  motion_common_settings = 'ui_dump_complete'; plc_expansion_units = 'none_present'
}
$ready = & $helper -Inventory (New-Inventory $complete 0)
Add-Case 'complete inventory is ready' ([bool]$ready.ready_for_full_1_to_1_import -and @($ready.blocking_gaps).Count -eq 0) "gaps=$(@($ready.blocking_gaps).Count)"
$screenshot = $complete.Clone(); $screenshot['ethercat_device_parameters'] = 'screenshot_only'
$params = & $helper -Inventory (New-Inventory $screenshot 0)
$ids = @($params.blocking_gaps | ForEach-Object { $_.id })
Add-Case 'screenshot-only parameters block readiness' ((-not $params.ready_for_full_1_to_1_import) -and ($ids -contains 'ethercat_device_parameters')) ($ids -join ',')
Add-Case 'screenshot-only parameters still allow manual rebuild' ([bool]$params.ready_for_manual_1_to_1_rebuild) ''
$withUnits = $complete.Clone(); $withUnits['plc_expansion_units'] = 'captured'
$unitsOk = & $helper -Inventory (New-Inventory $withUnits 2)
Add-Case 'captured expansion units do not block' ([bool]$unitsOk.ready_for_full_1_to_1_import) "gaps=$(@($unitsOk.blocking_gaps).Count)"
$noUnitsBad = $complete.Clone(); $noUnitsBad['plc_expansion_units'] = 'missing'
$noUnits = & $helper -Inventory (New-Inventory $noUnitsBad 0)
Add-Case 'zero units never emits an expansion gap' (-not (@($noUnits.blocking_gaps | ForEach-Object { $_.id }) -contains 'plc_expansion_units')) ''
$partialPdo = $complete.Clone(); $partialPdo['ethercat_pdo'] = 'partial'
$pdo = & $helper -Inventory (New-Inventory $partialPdo 0)
Add-Case 'partial PDO blocks readiness' (@($pdo.blocking_gaps | ForEach-Object { $_.id }) -contains 'ethercat_pdo') ''
$eipPartial = $complete.Clone(); $eipPartial['eip_connection'] = 'partial'; $eipPartial['ethernet_ip'] = 'ui_read_complete'
$eip = & $helper -Inventory (New-Inventory $eipPartial 0)
Add-Case 'EIP assignment missing blocks readiness' (@($eip.blocking_gaps | ForEach-Object { $_.id }) -contains 'eip_connection') ''
$baseMissing = $complete.Clone(); $baseMissing['program_fb'] = 'missing'
$base = & $helper -Inventory (New-Inventory $baseMissing 0)
Add-Case 'missing program/FB blocks readiness' (@($base.blocking_gaps | ForEach-Object { $_.id }) -contains 'program_fb') ''
$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'clone-readiness'; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0
