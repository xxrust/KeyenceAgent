param(
  [Parameter(Mandatory=$true)][string]$MappingPath,
  [string]$OutDir = ''
)
# Renames KV STUDIO axes through the verified "..." property dialog route:
#   1. expand 运动设定 > 轴设定 and select the axis tree item;
#   2. click the axis page button _buttonEditAxisProperty ("...");
#   3. in the modal 属性 dialog set the second edit (轴名称) via WM_SETTEXT;
#   4. click OK (BM_CLICK) and verify the tree text changed.
# The page's inline 轴名称 field is read-only, and UIA Invoke on the "..." button
# blocks on the modal dialog, so plain mouse clicks plus Win32 messages are used.
# Mapping file: one "axis_index<TAB>new_name" per line (# comments allowed).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class AxisWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, string l);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  public static List<string> TopWindows(int pid) {
    var res = new List<string>();
    EnumWindows((h, l) => { int p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) { var t = new StringBuilder(256); GetWindowText(h, t, 256); var c = new StringBuilder(256); GetClassName(h, c, 256); if (t.Length > 0) res.Add(h.ToInt64() + "|" + c.ToString() + "|" + t.ToString()); } return true; }, IntPtr.Zero);
    return res;
  }
  public static List<string> Children(long parent) {
    var res = new List<string>();
    EnumChildWindows(new IntPtr(parent), (h, l) => { var c = new StringBuilder(256); GetClassName(h, c, 256); var t = new StringBuilder(256); GetWindowText(h, t, 256); res.Add(h.ToInt64() + "|" + c.ToString() + "|" + t.ToString()); return true; }, IntPtr.Zero);
    return res;
  }
  public static void Click(IntPtr hwnd) {
    RECT r; if (!GetWindowRect(hwnd, out r)) return;
    SetCursorPos((r.L + r.R) / 2, (r.T + r.B) / 2);
    System.Threading.Thread.Sleep(120);
    mouse_event(0x0002, 0, 0, 0, IntPtr.Zero);
    System.Threading.Thread.Sleep(60);
    mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);
  }
}
"@

if (-not (Test-Path -LiteralPath $MappingPath -PathType Leaf)) { throw "KV_AXIS_MAPPING_MISSING: $MappingPath" }
if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $MappingPath) 'axis_rename' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$mapping = New-Object System.Collections.Generic.List[object]
foreach ($line in (Get-Content -LiteralPath $MappingPath -Encoding UTF8)) {
  if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { continue }
  $cells = $line -split "`t"
  if ($cells.Count -lt 2) { continue }
  if ($cells[0].Trim() -notmatch '^\d+$') { continue }
  $mapping.Add([pscustomobject]@{ index = [int]$cells[0].Trim(); name = $cells[1].Trim() })
}
if ($mapping.Count -eq 0) { throw 'KV_AXIS_MAPPING_EMPTY' }

$process = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
if (-not $process) { throw 'KV_PROCESS_NOT_RUNNING' }
$root = [System.Windows.Automation.AutomationElement]::RootElement
$pidCondition = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
  [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $process.Id)
$windowCondition = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
  [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
$mainCondition = New-Object System.Windows.Automation.AndCondition -ArgumentList @($pidCondition, $windowCondition)
$main = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $mainCondition)
if (-not $main) { throw 'KV_MAIN_WINDOW_NOT_FOUND' }

function Find-AxisItem([int]$index) {
  $condition = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::TreeItem)
  foreach ($item in @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition))) {
    $text = [string]$item.Current.Name
    if ($text -match ('^轴{0}:' -f $index)) { return [pscustomobject]@{ element = $item; text = $text } }
  }
  return $null
}
function Expand-AxisTree {
  $condition = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::TreeItem)
  foreach ($item in @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition))) {
    $name = [string]$item.Current.Name
    if ($name -eq '运动设定' -or $name -eq '轴设定') {
      $expand = $null
      if ($item.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$expand)) {
        if ($expand.Current.ExpandCollapseState -ne [System.Windows.Automation.ExpandCollapseState]::Expanded) { try { $expand.Expand() } catch {} }
      }
    }
  }
  Start-Sleep -Milliseconds 400
}
function Find-PropertyButton {
  $condition = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
    [System.Windows.Automation.AutomationElement]::AutomationIdProperty, '_buttonEditAxisProperty')
  return $main.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}
function Find-AxisDialog([int]$timeoutMs = 4000) {
  $deadline = (Get-Date).AddMilliseconds($timeoutMs)
  do {
    foreach ($row in [AxisWin]::TopWindows($process.Id)) {
      $parts = $row -split '\|', 3
      if ($parts[2] -eq '属性') { return [pscustomobject]@{ hwnd = [long]$parts[0]; class = $parts[1]; title = $parts[2] } }
    }
    Start-Sleep -Milliseconds 150
  } while ((Get-Date) -lt $deadline)
  return $null
}
function Close-AxisDialog([long]$dialogHwnd) {
  foreach ($row in [AxisWin]::Children($dialogHwnd)) {
    $parts = $row -split '\|', 3
    if ($parts[2] -eq '取消') { [void][AxisWin]::SendMessage([IntPtr][long]$parts[0], 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero); return }
  }
}
function Set-AxisDialogName([long]$dialogHwnd, [string]$name) {
  $edits = @()
  foreach ($row in [AxisWin]::Children($dialogHwnd)) {
    $parts = $row -split '\|', 3
    if ($parts[1] -match 'WindowsForms10\.Edit') { $edits += [long]$parts[0] }
  }
  if ($edits.Count -lt 2) { throw "KV_AXIS_DIALOG_EDITS_MISSING: found $($edits.Count)" }
  $nameEdit = $edits[1]
  [void][AxisWin]::SendMessage([IntPtr]$nameEdit, 0x000C, [IntPtr]::Zero, $name)
  Start-Sleep -Milliseconds 250
  $ok = $null
  foreach ($row in [AxisWin]::Children($dialogHwnd)) {
    $parts = $row -split '\|', 3
    if ($parts[2] -eq 'OK') { $ok = [long]$parts[0]; break }
  }
  if (-not $ok) { throw 'KV_AXIS_DIALOG_OK_MISSING' }
  [void][AxisWin]::SendMessage([IntPtr]$ok, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
  return $nameEdit
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($entry in $mapping) {
  $index = $entry.index
  $newName = $entry.name
  Expand-AxisTree
  $found = Find-AxisItem $index
  if (-not $found) { $results.Add([pscustomobject]@{ index = $index; name = $newName; ok = $false; reason = 'axis_item_missing' }); continue }
  [AxisWin]::SetForegroundWindow([IntPtr]$process.MainWindowHandle) | Out-Null
  Start-Sleep -Milliseconds 300
  $scroll = $null
  if ($found.element.TryGetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern, [ref]$scroll)) { try { $scroll.ScrollIntoView() } catch {} }
  $sel = $null
  if ($found.element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$sel)) { try { $sel.Select() } catch {} }
  Start-Sleep -Milliseconds 700
  $button = Find-PropertyButton
  if (-not $button) { $results.Add([pscustomobject]@{ index = $index; name = $newName; ok = $false; reason = 'property_button_missing' }); continue }
  [AxisWin]::Click([IntPtr]$button.Current.NativeWindowHandle)
  $dialog = Find-AxisDialog
  if (-not $dialog) { $results.Add([pscustomobject]@{ index = $index; name = $newName; ok = $false; reason = 'axis_dialog_missing' }); continue }
  try {
    [void](Set-AxisDialogName $dialog.hwnd $newName)
  } catch {
    try { Close-AxisDialog $dialog.hwnd } catch {}
    $results.Add([pscustomobject]@{ index = $index; name = $newName; ok = $false; reason = $_.Exception.Message })
    continue
  }
  Start-Sleep -Milliseconds 900
  $check = Find-AxisItem $index
  $treeText = if ($check) { [string]$check.text } else { '' }
  if ($check -and ($treeText -match [regex]::Escape($newName))) {
    $results.Add([pscustomobject]@{ index = $index; name = $newName; ok = $true; reason = ''; tree_text = $treeText })
  } else {
    $results.Add([pscustomobject]@{ index = $index; name = $newName; ok = $false; reason = ('tree_not_updated:' + $treeText) })
  }
}

$failed = @($results | Where-Object { -not $_.ok })
$report = [ordered]@{
  ok = ($failed.Count -eq 0)
  mapping_path = $MappingPath
  total = $results.Count
  renamed = @($results | Where-Object { $_.ok }).Count
  failed = @($failed | ForEach-Object { [pscustomobject]@{ index = $_.index; name = $_.name; reason = $_.reason } })
  results = $results.ToArray()
  generated_at = (Get-Date).ToString('o')
}
$reportPath = Join-Path $OutDir 'axis_rename_result.json'
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 4
Write-Host ("KV_AXIS_RENAME: renamed={0}/{1} failed={2} report={3}" -f $report.renamed, $report.total, $failed.Count, $reportPath)
if ($failed.Count -gt 0) { exit 41 }
exit 0
