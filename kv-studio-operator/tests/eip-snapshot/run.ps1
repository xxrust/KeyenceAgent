param([string]$WorkRoot = '')

$ErrorActionPreference = 'Stop'

# Contract + error-path regression for the EtherNet/IP connection snapshot.
# The success path needs a live 连接设定 dialog, so this suite proves the pieces
# exist, are registered, and that a missing dialog fails fast instead of hanging.

$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $PSScriptRoot '..\_helpers\invoke_tool.ps1')
$wrapper = Join-Path $skillRoot 'scripts\workflow_tools\get_kv_eip_connection_snapshot.ps1'
$runner = Join-Path $skillRoot 'scripts\runner_children\snapshot_eip_connection_guarded.ps1'
$manifestPath = Join-Path $skillRoot 'scripts\script_manifest.json'
$reference = Join-Path $skillRoot 'references\eip-settings.md'

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-eip-snapshot-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}

Add-Case 'workflow wrapper exists' (Test-Path -LiteralPath $wrapper) $wrapper
Add-Case 'runner child exists' (Test-Path -LiteralPath $runner) $runner
Add-Case 'reference doc exists' (Test-Path -LiteralPath $reference) $reference

$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json
$tools = @($manifest.classes.workflow_tool | ForEach-Object { [string]$_.path })
$children = @($manifest.classes.runner_child_approved | ForEach-Object { [string]$_.path })
Add-Case 'wrapper registered in manifest' ($tools -contains 'workflow_tools/get_kv_eip_connection_snapshot.ps1') ($tools -join ',')
Add-Case 'runner child registered in manifest' ($children -contains 'runner_children/snapshot_eip_connection_guarded.ps1') 'runner_child_approved'

$referenceText = Get-Content -LiteralPath $reference -Raw -Encoding UTF8
Add-Case 'reference documents the copy gesture' (($referenceText -match 'Ctrl\+Shift\+End') -and ($referenceText -match 'Ctrl\+Home')) 'doc'
Add-Case 'reference documents the cleanup rule' ($referenceText -match '取消') 'doc'

$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$exit = Invoke-TestTool -ScriptPath $wrapper -Arguments @('-ConnectionTitle', '不存在的连接', '-OutDir', (Join-Path $WorkRoot 'missing_dialog'))
$stopwatch.Stop()
Add-Case 'missing dialog exits non-zero' ($exit -ne 0) "exit=$exit"
Add-Case 'missing dialog fails fast (<120s)' ($stopwatch.Elapsed.TotalSeconds -lt 120) ('{0:n1}s' -f $stopwatch.Elapsed.TotalSeconds)

$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'eip-snapshot'; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0
