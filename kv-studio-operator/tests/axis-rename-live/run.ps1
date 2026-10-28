param(
  [string]$WorkRoot = '',
  [string]$ProjectPath = 'C:\kvrun\ec_test\KVXEcTest\KVXEcTest.kpr',
  [int]$AxisIndex = 1,
  [string]$OriginalName = 'Axis_1',
  [string]$TempName = 'Axis_1_test'
)

$ErrorActionPreference = 'Stop'

# Live regression for rename_kv_axes.ps1 on the scratch project:
# rename axis 1 to a temp name, verify the tree text, then restore the name.
# Skips (exit 0) when KV STUDIO or the scratch project is unavailable/unsaved.

$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $PSScriptRoot '..\_helpers\invoke_tool.ps1')
$wrapper = Join-Path $skillRoot 'scripts\workflow_tools\rename_kv_axes.ps1'

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-axis-live-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}
function Save-Result([bool]$Skipped = $false) {
  $failed = @($cases | Where-Object { -not $_.ok })
  $result = [ordered]@{ test = 'axis-rename-live'; skipped = $Skipped; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
  $result | ConvertTo-Json -Depth 3
  if ($failed.Count -gt 0) { exit 41 }
  exit 0
}

if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
  Add-Case 'scratch project exists' $true 'skipped: project not found'
  Save-Result $true
}

$projectNeedle = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
function Find-ProjectProcess {
  @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$projectNeedle*" }) | Select-Object -First 1
}
$process = Find-ProjectProcess
if (-not $process) {
  Start-Process -FilePath 'H:\Keyence\KVS12\KVS\Kvs.exe' -ArgumentList @(('"' + $ProjectPath + '"')) | Out-Null
  $deadline = (Get-Date).AddSeconds(90)
  do {
    Start-Sleep -Seconds 2
    $process = Find-ProjectProcess
  } while (-not $process -and (Get-Date) -lt $deadline)
}
Add-Case 'KV STUDIO is running' ($null -ne $process) 'process'
if (-not $process) { Save-Result $true }
Add-Case 'project window is the scratch project' ($process.MainWindowTitle -like '*KVXEcTest*') $process.MainWindowTitle
Add-Case 'project is saved (no unsaved marker)' ($process.MainWindowTitle -notmatch '\*') $process.MainWindowTitle
if ($process.MainWindowTitle -match '\*') { Save-Result $true }

$tempMap = Join-Path $WorkRoot 'temp.tsv'
[IO.File]::WriteAllText($tempMap, ("{0}`t{1}" -f $AxisIndex, $TempName), (New-Object Text.UTF8Encoding($false)))
$tempOut = Join-Path $WorkRoot 'rename_temp'
$tempExit = Invoke-TestTool -ScriptPath $wrapper -Arguments @('-MappingPath', $tempMap, '-OutDir', $tempOut)
$tempReportPath = Join-Path $tempOut 'axis_rename_result.json'
$tempReport = if (Test-Path -LiteralPath $tempReportPath) { Get-Content -LiteralPath $tempReportPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
Add-Case 'temp rename exits 0' ($tempExit -eq 0) "exit=$tempExit"
Add-Case 'temp rename ok' ([bool]($tempReport -and $tempReport.ok)) "ok=$($tempReport.ok)"
$tempTreeText = if ($tempReport -and @($tempReport.results).Count -gt 0) { [string]@($tempReport.results)[0].tree_text } else { '' }
Add-Case 'tree text contains temp name' ($tempTreeText -match [regex]::Escape($TempName)) $tempTreeText

$restoreMap = Join-Path $WorkRoot 'restore.tsv'
[IO.File]::WriteAllText($restoreMap, ("{0}`t{1}" -f $AxisIndex, $OriginalName), (New-Object Text.UTF8Encoding($false)))
$restoreOut = Join-Path $WorkRoot 'rename_restore'
$restoreExit = Invoke-TestTool -ScriptPath $wrapper -Arguments @('-MappingPath', $restoreMap, '-OutDir', $restoreOut)
$restoreReportPath = Join-Path $restoreOut 'axis_rename_result.json'
$restoreReport = if (Test-Path -LiteralPath $restoreReportPath) { Get-Content -LiteralPath $restoreReportPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
Add-Case 'restore exits 0' ($restoreExit -eq 0) "exit=$restoreExit"
Add-Case 'restore ok' ([bool]($restoreReport -and $restoreReport.ok)) "ok=$($restoreReport.ok)"
$restoreTreeText = if ($restoreReport -and @($restoreReport.results).Count -gt 0) { [string]@($restoreReport.results)[0].tree_text } else { '' }
Add-Case 'tree text restored' ($restoreTreeText -match [regex]::Escape($OriginalName)) $restoreTreeText

# Persist the restored name so later suites start from a saved project.
Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class AxisTestWin{[DllImport("user32.dll")]public static extern bool SetForegroundWindow(IntPtr h);}'
Add-Type -AssemblyName System.Windows.Forms
$current = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
if ($current) {
  [void][AxisTestWin]::SetForegroundWindow($current.MainWindowHandle)
  Start-Sleep -Milliseconds 400
  [System.Windows.Forms.SendKeys]::SendWait('^s')
  Start-Sleep -Seconds 4
  $current.Refresh()
  Add-Case 'project saved after restore' ($current.MainWindowTitle -notmatch '\*') $current.MainWindowTitle
}

Save-Result $false




