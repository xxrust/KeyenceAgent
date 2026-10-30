param(
  [string]$ConnectionTitle = '连接设定',
  [string]$OutDir = 'C:\kvrun\eip\snapshots',
  [switch]$KeepDialogs
)
# Reads the currently open EtherNet/IP connection dialog (连接设定) and its
# 软元件分配 grid. KV STUDIO renders that grid as a VSFlexGrid ActiveX control
# without a UI Automation provider, so the grid is copied through the clipboard:
# click a grid cell, Ctrl+Home, Ctrl+Shift+End, Ctrl+C.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class EipWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  public static List<string> TopWindows(int pid) {
    var res = new List<string>();
    EnumWindows((h, l) => { int p; GetWindowThreadProcessId(h, out p); if (p == pid) { var t = new StringBuilder(256); GetWindowText(h, t, 256); if (t.Length > 0) res.Add(h.ToInt64() + "|" + t.ToString()); } return true; }, IntPtr.Zero);
    return res;
  }
  public static List<string> Children(long parent) {
    var res = new List<string>();
    EnumChildWindows(new IntPtr(parent), (h, l) => { var c = new StringBuilder(256); GetClassName(h, c, 256); res.Add(h.ToInt64() + "|" + c.ToString()); return true; }, IntPtr.Zero);
    return res;
  }
  public static string RectOf(long h) { RECT r; if (!GetWindowRect(new IntPtr(h), out r)) return ""; return r.L + "," + r.T + "," + (r.R - r.L) + "," + (r.B - r.T); }
  public static void ClickCenter(long h) { RECT r; if (!GetWindowRect(new IntPtr(h), out r)) return; int x = (r.L + r.R) / 2; int y = (r.T + r.B) / 2; SetCursorPos(x, y); System.Threading.Thread.Sleep(120); mouse_event(0x0002, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(0x0004, 0, 0, 0, IntPtr.Zero); }
  public static void Close(long h) { PostMessage(new IntPtr(h), 0x0010, IntPtr.Zero, IntPtr.Zero); }
}
"@

$process = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
if (-not $process) { throw 'KV_PROCESS_NOT_RUNNING' }
$pidK = $process.Id

function Find-Window([string]$needle) {
  foreach ($row in ([EipWin]::TopWindows($pidK))) {
    $parts = $row -split '\|', 2
    if ($parts[1] -like "*$needle*") { return [pscustomobject]@{ hwnd = [long]$parts[0]; title = $parts[1] } }
  }
  return $null
}

function Get-FieldMap($element) {
  $ids = @{
    '1872' = 'connection_name'; '1874' = 'in_connection_type'; '1875' = 'in_connection_point'
    '1763' = 'in_data_size_words'; '1940' = 'in_send_trigger'; '1687' = 'in_rpi_ms'
    '1764' = 'out_data_size_words'; '2134' = 'out_rpi_ms'
  }
  $map = [ordered]@{}
  $all = $element.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  for ($i = 0; $i -lt $all.Count; $i++) {
    $aid = [string]$all.Item($i).Current.AutomationId
    if ($ids.ContainsKey($aid) -and -not $map.Contains($ids[$aid])) { $map[$ids[$aid]] = [string]$all.Item($i).Current.Name }
  }
  return $map
}

function Copy-AssignmentGrid([long]$dialogHwnd) {
  $grid = $null
  foreach ($row in ([EipWin]::Children($dialogHwnd))) {
    $parts = $row -split '\|', 2
    if ($parts[1] -like 'VSFlexGrid*') { $grid = [long]$parts[0]; break }
  }
  if (-not $grid) { throw 'KV_EIP_ASSIGNMENT_GRID_NOT_FOUND' }
  [void][EipWin]::SetForegroundWindow([IntPtr]$dialogHwnd)
  Start-Sleep -Milliseconds 300
  [EipWin]::ClickCenter($grid)
  Start-Sleep -Milliseconds 300
  [System.Windows.Forms.SendKeys]::SendWait('^{HOME}')
  Start-Sleep -Milliseconds 200
  [System.Windows.Forms.SendKeys]::SendWait('^+{END}')
  Start-Sleep -Milliseconds 250
  [System.Windows.Forms.SendKeys]::SendWait('^c')
  Start-Sleep -Milliseconds 700
  return [System.Windows.Forms.Clipboard]::GetText()
}

$conn = Find-Window $ConnectionTitle
if (-not $conn) { throw "KV_EIP_CONNECTION_DIALOG_NOT_FOUND: $ConnectionTitle" }
$connElement = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$conn.hwnd)
$fields = Get-FieldMap $connElement

$assignButton = $null
$all = $connElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
for ($i = 0; $i -lt $all.Count; $i++) { if ([string]$all.Item($i).Current.AutomationId -eq '1600') { $assignButton = $all.Item($i); break } }
if (-not $assignButton) { throw 'KV_EIP_ASSIGNMENT_BUTTON_NOT_FOUND' }
$r = $assignButton.Current.BoundingRectangle
[void][EipWin]::SetForegroundWindow([IntPtr]$conn.hwnd)
Start-Sleep -Milliseconds 300
[EipWin]::ClickCenter($assignButton.Current.NativeWindowHandle)
Start-Sleep -Milliseconds 200
if ($r.Width -le 0) { throw 'KV_EIP_ASSIGNMENT_BUTTON_BOUNDS_INVALID' }
[EipWin]::SetCursorPos([int]($r.Left + $r.Width / 2), [int]($r.Top + $r.Height / 2))
Start-Sleep -Milliseconds 200
[EipWin]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Milliseconds 60
[EipWin]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
Start-Sleep -Seconds 3

$assign = Find-Window '软元件分配设定'
if (-not $assign) { throw 'KV_EIP_ASSIGNMENT_DIALOG_NOT_FOUND' }
$raw = Copy-AssignmentGrid $assign.hwnd
$rows = New-Object System.Collections.Generic.List[object]
foreach ($line in ($raw -split "`r?`n")) {
  if (-not $line.Trim()) { continue }
  $cells = $line -split "`t"
  $rows.Add([pscustomobject]@{ device = $cells[0]; name = if ($cells.Count -gt 1) { $cells[1] } else { '' } })
}

if (-not $KeepDialogs) {
  [EipWin]::Close($assign.hwnd)
  Start-Sleep -Milliseconds 600
  [EipWin]::Close($conn.hwnd)
  Start-Sleep -Milliseconds 400
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$connName = [string]$fields.connection_name
$safe = ((($conn.title + '_' + $connName).Trim('_')) -replace '[^\w\u4e00-\u9fff]+', '_')
$rawPath = Join-Path $OutDir ($safe + '.tsv')
[IO.File]::WriteAllText($rawPath, $raw, (New-Object Text.UTF8Encoding($false)))
$report = [ordered]@{
  ok = ($rows.Count -gt 0)
  connection_dialog = $conn.title
  fields = $fields
  assignment_row_count = $rows.Count
  assignment = $rows.ToArray()
  raw_path = $rawPath
  generated_at = (Get-Date).ToString('o')
}
$jsonPath = Join-Path $OutDir ($safe + '.json')
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $jsonPath -Encoding UTF8
$report | ConvertTo-Json -Depth 4
Write-Host "KV_EIP_SNAPSHOT: rows=$($rows.Count) json=$jsonPath"
if ($rows.Count -eq 0) { exit 41 }
exit 0
