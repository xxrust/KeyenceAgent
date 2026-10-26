param([string]$WorkRoot = '')

$ErrorActionPreference = 'Stop'

# Static contract regression for the 2026-10-26 EtherCAT regression:
# - the double-click must be one approved atomic guard action;
# - guard checkpoints and failures must take screenshots;
# - the dialog whitelist must include titled WinForms windows;
# - dialog matching must use title + body, and the main window is excluded by HWND.

$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $PSScriptRoot '..\_helpers\invoke_tool.ps1')
$guardPath = Join-Path $skillRoot 'scripts\guards\kv_ui_guard.ps1'
$runnerPath = Join-Path $skillRoot 'scripts\runner_children\configure_ethercat_nodes_guarded.ps1'
$manifestPath = Join-Path $skillRoot 'scripts\script_manifest.json'

foreach ($path in @($guardPath, $runnerPath, $manifestPath)) {
  if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "missing contract file: $path" }
}

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-guard-contract-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}

$guardText = Get-Content -LiteralPath $guardPath -Raw -Encoding UTF8
$runnerText = Get-Content -LiteralPath $runnerPath -Raw -Encoding UTF8
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

Add-Case 'double-click guard function exists' ($guardText -match 'function Invoke-KvGuardedDoubleClick') 'kv_ui_guard.ps1'
Add-Case 'double-click clicks twice inside one action' (($guardText -match 'for \(\$click = 0; \$click -lt 2; \$click\+\+\)') -and ($guardText -match 'Start-Sleep -Milliseconds 60')) 'loop'
Add-Case 'double-click registered as approved atomic action' (@($manifest.ui_atomic_actions.approved) -contains 'Invoke-KvGuardedDoubleClick') (@($manifest.ui_atomic_actions.approved) -join ',')
Add-Case 'runner uses the atomic double-click' (($runnerText -match 'Invoke-KvGuardedDoubleClick') -and ($runnerText -notmatch "activate filtered EtherCAT device click 1")) 'runner'
Add-Case 'checkpoint writer saves a screenshot' (($guardText -match 'Save-KvUiGuardScreenshot -CheckpointPath \$path') -and ($guardText -match '\$evidenceList \+= \$screenshot')) 'checkpoint'
Add-Case 'guard failure saves a screenshot' ($guardText -match "999_failure_") 'stop'
Add-Case 'winforms dialogs are whitelisted' ($runnerText -match "class_name -like 'WindowsForms\*' -and -not \[string\]::IsNullOrWhiteSpace") 'whitelist'
Add-Case 'dialog match includes the window title' ($runnerText -match '\$text = \(\[string\]\$dialogRow\[0\]\.title') 'title+body'
Add-Case 'main window excluded by hwnd' ($runnerText -match '\$_.hwnd -ne \$mainHandle') 'hwnd'
Add-Case 'batch-axis done dialog is handled' ($runnerText -match '批量登录已经完成') 'branch'
Add-Case 'atomic timeout captures screenshot' ($runnerText -match 'atomic_timeout_failure\.png') 'timeout evidence'

$usageGate = Join-Path $skillRoot 'scripts\gates\assert_kv_mvp_ui_guard_usage.ps1'
$gateOut = Join-Path $WorkRoot 'ui_guard_usage'
$gateExit = Invoke-TestTool -ScriptPath $usageGate -Arguments @('-OutDir', $gateOut)
$gateResultPath = Join-Path $gateOut 'ui_guard_usage_result.json'
$gateOk = $false
if (Test-Path -LiteralPath $gateResultPath) {
  $gateResult = Get-Content -LiteralPath $gateResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $gateOk = [bool]$gateResult.ok
}
Add-Case 'ui guard usage gate passes' (($gateExit -eq 0) -and $gateOk) "exit=$gateExit ok=$gateOk"

$boundaryGate = Join-Path $skillRoot 'scripts\gates\assert_kv_mvp_agent_boundary.ps1'
$boundaryOut = Join-Path $WorkRoot 'agent_boundary'
$boundaryExit = Invoke-TestTool -ScriptPath $boundaryGate -Arguments @('-OutDir', $boundaryOut)
Add-Case 'agent boundary gate passes' ($boundaryExit -eq 0) "exit=$boundaryExit"

$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'ethercat-guard-contract'; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0

