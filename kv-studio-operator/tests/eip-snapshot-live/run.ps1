param(
  [string]$WorkRoot = '',
  [string]$SampleProjectPath = 'C:\kvrun\snapshot_sample\KVX样例程序_v100\KVX样例程序_v100.kpr',
  [string]$RestoreProjectPath = 'C:\kvrun\ec_test\KVXEcTest\KVXEcTest.kpr'
)

$ErrorActionPreference = 'Stop'

# Live regression for get_kv_eip_connection_snapshot.ps1.
# Opens the real sample project, opens EtherNet/IP settings and the NU-EP1
# Monitor Data 连接设定 dialog, runs the snapshot and asserts the parsed fields
# and assignment rows. Closes everything without saving the sample project.

$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $PSScriptRoot '..\_helpers\invoke_tool.ps1')
$wrapper = Join-Path $skillRoot 'scripts\workflow_tools\get_kv_eip_connection_snapshot.ps1'
$kvsExe = 'H:\Keyence\KVS12\KVS\Kvs.exe'

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-eip-live-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}
function Save-Result([bool]$Skipped = $false) {
  $failed = @($cases | Where-Object { -not $_.ok })
  $result = [ordered]@{ test = 'eip-snapshot-live'; skipped = $Skipped; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
  $result | ConvertTo-Json -Depth 3
  if ($failed.Count -gt 0) { exit 41 }
  exit 0
}

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class EipLive {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  public static List<string> Windows(int pid) {
    var res = new List<string>();
    EnumWindows((h, l) => { int p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) { var t = new StringBuilder(256); GetWindowText(h, t, 256); if (t.Length > 0) res.Add(h.ToInt64() + "|" + t.ToString()); } return true; }, IntPtr.Zero);
    return res;
  }
  public static long FindByTitle(int pid, string exactOrLike) {
    foreach (var row in Windows(pid)) { var parts = row.Split(new[] { '|' }, 2); if (parts[1] == exactOrLike) return long.Parse(parts[0]); }
    return 0;
  }
  public static long FindByContains(int pid, string needle) {
    foreach (var row in Windows(pid)) { var parts = row.Split(new[] { '|' }, 2); if (parts[1].Contains(needle)) return long.Parse(parts[0]); }
    return 0;
  }
  public static void DoubleClick(int x, int y) {
    SetCursorPos(x, y); System.Threading.Thread.Sleep(150);
    mouse_event(0x0002, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);
    System.Threading.Thread.Sleep(120);
    mouse_event(0x0002, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);
  }
  public static void Click(int x, int y) {
    SetCursorPos(x, y); System.Threading.Thread.Sleep(150);
    mouse_event(0x0002, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);
  }
}
"@

if (-not (Test-Path -LiteralPath $SampleProjectPath -PathType Leaf)) {
  Add-Case 'sample project exists' $true 'skipped: sample project not found'
  Save-Result $true
}
if (-not (Test-Path -LiteralPath $kvsExe -PathType Leaf)) {
  Add-Case 'KV STUDIO executable exists' $true 'skipped: Kvs.exe not found'
  Save-Result $true
}

# Always start from a clean single instance; the scratch project is saved.
Get-Process Kvs -ErrorAction SilentlyContinue | ForEach-Object { try { Stop-Process -Id $_.Id -Force } catch {} }
Start-Sleep -Seconds 3
Start-Process -FilePath $kvsExe -ArgumentList @(('"' + $SampleProjectPath + '"')) | Out-Null
$deadline = (Get-Date).AddSeconds(90)
$process = $null
do {
  Start-Sleep -Seconds 2
  $process = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
} while ((-not $process -or $process.MainWindowTitle -notlike '*KVX样例程序_v100*') -and (Get-Date) -lt $deadline)
Add-Case 'sample project opened' ($process -and $process.MainWindowTitle -like '*KVX样例程序_v100*') $process.MainWindowTitle
if (-not $process) { Save-Result $true }
Add-Case 'sample project is saved' ($process.MainWindowTitle -notmatch '\*') $process.MainWindowTitle

$main = [System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
function Get-TreeItem([string]$pattern) {
  $condition = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::TreeItem)
  foreach ($item in @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition))) {
    if ([string]$item.Current.Name -match $pattern) { return $item }
  }
  return $null
}
function Expand-Item($item) {
  if (-not $item) { return }
  $expand = $null
  if ($item.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$expand)) {
    if ($expand.Current.ExpandCollapseState -ne [System.Windows.Automation.ExpandCollapseState]::Expanded) { try { $expand.Expand(); Start-Sleep -Milliseconds 400 } catch {} }
  }
}
Expand-Item (Get-TreeItem '^单元配置$')
Start-Sleep -Milliseconds 300
Expand-Item (Get-TreeItem '^\[0\]')
Start-Sleep -Milliseconds 300

$eipNode = Get-TreeItem '^EtherNet/IP'
Add-Case 'EtherNet/IP tree node found' ($null -ne $eipNode) 'tree'
if (-not $eipNode) { Save-Result $false }
$scroll = $null
if ($eipNode.TryGetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern, [ref]$scroll)) { try { $scroll.ScrollIntoView() } catch {} }
Start-Sleep -Milliseconds 300
$rect = $eipNode.Current.BoundingRectangle
[EipLive]::SetForegroundWindow([IntPtr]$process.MainWindowHandle) | Out-Null
Start-Sleep -Milliseconds 300
# Selection + Enter is the reliable way to open the EtherNet/IP settings; a
# plain double-click on the tree row can be swallowed while the tree lacks focus.
$selection = $null
if ($eipNode.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selection)) { try { $selection.Select() } catch {} }
Start-Sleep -Milliseconds 400
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Start-Sleep -Milliseconds 800
if ([EipLive]::FindByContains($process.Id, 'EtherNet/IP') -eq 0) {
  [EipLive]::DoubleClick([int]($rect.Left + $rect.Width / 2), [int]($rect.Top + $rect.Height / 2))
}
$eipDeadline = (Get-Date).AddSeconds(15)
$eipHwnd = 0
do {
  Start-Sleep -Milliseconds 500
  $eipHwnd = [EipLive]::FindByContains($process.Id, 'EtherNet/IP 设定')
} while ($eipHwnd -eq 0 -and (Get-Date) -lt $eipDeadline)
Add-Case 'EtherNet/IP settings window opened' ($eipHwnd -ne 0) "hwnd=$eipHwnd"
if ($eipHwnd -eq 0) { Save-Result $false }

[void][EipLive]::MoveWindow([IntPtr]$eipHwnd, 0, 0, 1500, 900, $true)
Start-Sleep -Seconds 1
[EipLive]::SetForegroundWindow([IntPtr]$eipHwnd) | Out-Null
Start-Sleep -Milliseconds 600

# The device tree is an MFC custom control: click candidate rows of
# "1: NU-EP1 > Monitor Data (Input Only)" in the maximized layout.
$connectionHwnd = 0
foreach ($point in @(@(169, 206), @(169, 230), @(150, 206), @(200, 206))) {
  [EipLive]::DoubleClick($point[0], $point[1])
  Start-Sleep -Milliseconds 1500
  $connectionHwnd = [EipLive]::FindByContains($process.Id, '连接设定')
  if ($connectionHwnd -ne 0) { break }
}
Add-Case 'connection settings dialog opened' ($connectionHwnd -ne 0) "hwnd=$connectionHwnd"
if ($connectionHwnd -eq 0) { Save-Result $false }

$outDir = Join-Path $WorkRoot 'snapshot'
$exit = Invoke-TestTool -ScriptPath $wrapper -Arguments @('-ConnectionTitle', '连接设定', '-OutDir', $outDir)
Add-Case 'snapshot exits 0' ($exit -eq 0) "exit=$exit"
$reportPath = Join-Path $outDir '连接设定_1_NU_EP1.json'
$report = if (Test-Path -LiteralPath $reportPath) { Get-Content -LiteralPath $reportPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
Add-Case 'snapshot report ok' ([bool]($report -and $report.ok)) "ok=$($report.ok)"
Add-Case 'connection point is IN_100' ([string]($report.fields.in_connection_point) -eq 'IN_100') ([string]$report.fields.in_connection_point)
Add-Case 'data size is 64 words' ([string]($report.fields.in_data_size_words) -eq '64') ([string]$report.fields.in_data_size_words)
Add-Case 'at least 60 assignment rows' ([int]($report.assignment_row_count) -ge 60) "rows=$($report.assignment_row_count)"
$devices = @($report.assignment | ForEach-Object { [string]$_.device })
Add-Case 'assignment contains B00' ($devices -contains 'B00') 'B00'
Add-Case 'assignment contains B01' ($devices -contains 'B01') 'B01'
$named = @($report.assignment | Where-Object { $_.name })
Add-Case 'assignment keeps names' (@($named).Count -ge 5) "named=$(@($named).Count)"
Add-Case 'raw tsv written' ([bool]($report -and $report.raw_path -and (Test-Path -LiteralPath $report.raw_path))) ([string]$report.raw_path)

$remaining = @([EipLive]::Windows($process.Id) | Where-Object { $_ -match '连接设定|软元件分配设定' })
Add-Case 'snapshot closed its dialogs' ($remaining.Count -eq 0) ($remaining -join ';')

# Close the EtherNet/IP settings window and the sample project without saving.
$eipHwnd2 = [EipLive]::FindByContains($process.Id, 'EtherNet/IP 设定')
if ($eipHwnd2 -ne 0) {
  [EipLive]::SetForegroundWindow([IntPtr]$eipHwnd2) | Out-Null
  Start-Sleep -Milliseconds 400
  $eipElement = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$eipHwnd2)
  $cancel = $null
  $buttons = @($eipElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition -ArgumentList @([System.Windows.Automation.AutomationElement]::AutomationIdProperty, '23016'))))
  if ($buttons.Count -gt 0) { $cancel = $buttons[0] }
  if ($cancel) {
    $r = $cancel.Current.BoundingRectangle
    [EipLive]::Click([int]($r.Left + $r.Width / 2), [int]($r.Top + $r.Height / 2))
    Start-Sleep -Seconds 2
  }
}
Get-Process Kvs -ErrorAction SilentlyContinue | ForEach-Object { try { Stop-Process -Id $_.Id -Force } catch {} }
Start-Sleep -Seconds 2
$stillRunning = @(Get-Process Kvs -ErrorAction SilentlyContinue).Count
Add-Case 'KV STUDIO closed after sampling' ($stillRunning -eq 0) "instances=$stillRunning"

# Hand the scratch project back so later live suites can run.
if (Test-Path -LiteralPath $RestoreProjectPath -PathType Leaf) {
  Start-Process -FilePath $kvsExe -ArgumentList @(('"' + $RestoreProjectPath + '"')) | Out-Null
  $restoreDeadline = (Get-Date).AddSeconds(60)
  do {
    Start-Sleep -Seconds 2
    $restored = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
  } while ((-not $restored -or $restored.MainWindowTitle -notlike '*KVXEcTest*') -and (Get-Date) -lt $restoreDeadline)
  Add-Case 'scratch project restored' ($restored -and $restored.MainWindowTitle -like '*KVXEcTest*') $restored.MainWindowTitle
}

Save-Result $false


