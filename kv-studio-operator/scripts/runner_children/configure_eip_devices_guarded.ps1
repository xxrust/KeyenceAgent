param(
  [Parameter(Mandatory=$true)][string]$ProjectName,
  [Parameter(Mandatory=$true)][string]$DevicesConfigPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds = 120,
  [switch]$PreflightOnly
)
# Writes EtherNet/IP devices into the project that is currently open in
# KV STUDIO. Verified steps so far:
#   - open 单元配置 > [0] > EtherNet/IP (select + Enter)
#   - answer the first-run 手动/自动配置 dialog with 手动(M)
#   - add a catalog device (search tab + double-click)
# The device add currently stops at KV_EIP_COMMUNICATION_ADAPTER_REQUIRED on a
# project without a 通信适配器; that code is deliberate so the next iteration
# can implement the adapter step instead of silently claiming success.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class EipWriteWin {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool MoveWindow(IntPtr h, int x, int y, int w, int ht, bool repaint);
  public static List<string> Windows(int pid) {
    var res = new List<string>();
    EnumWindows((h, l) => { int p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) { var t = new StringBuilder(256); GetWindowText(h, t, 256); var c = new StringBuilder(256); GetClassName(h, c, 256); if (t.Length > 0) res.Add(h.ToInt64() + "|" + c.ToString() + "|" + t.ToString()); } return true; }, IntPtr.Zero);
    return res;
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

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log = Join-Path $OutDir 'eip_write.log'
function Log([string]$Name, [hashtable]$Data = @{}) {
  $row = [ordered]@{ timestamp = (Get-Date).ToString('o'); event = $Name }
  foreach ($k in $Data.Keys) { $row[$k] = $Data[$k] }
  ($row | ConvertTo-Json -Compress -Depth 4) | Add-Content -LiteralPath $log -Encoding UTF8
}
function Save-Shot([string]$Name) {
  try {
    Add-Type -AssemblyName System.Drawing
    Add-Type -AssemblyName System.Windows.Forms
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap($bounds.Width, $bounds.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($bounds.Location, [System.Drawing.Point]::Empty, $bounds.Size)
    $path = Join-Path $OutDir $Name
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    return $path
  } catch { return $null }
}

if (-not (Test-Path -LiteralPath $DevicesConfigPath -PathType Leaf)) { throw "KV_EIP_CONFIG_MISSING: $DevicesConfigPath" }
$config = Get-Content -LiteralPath $DevicesConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$devices = @($config.devices)
if ($devices.Count -eq 0) { throw 'KV_EIP_CONFIG_EMPTY: devices[] is empty' }
foreach ($d in $devices) {
  if (-not $d.model) { throw 'KV_EIP_CONFIG_INVALID: device.model is required' }
}
$process = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$ProjectName*" }) | Select-Object -First 1
if (-not $process) { throw "KV_EIP_PROJECT_NOT_OPEN: $ProjectName" }
if ($process.MainWindowTitle -match '\*') { throw 'KV_EIP_PROJECT_UNSAVED: save the project before writing EtherNet/IP settings' }
Log 'started' @{ project = $ProjectName; devices = $devices.Count; process_id = $process.Id }

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
    if ($expand.Current.ExpandCollapseState -ne [System.Windows.Automation.ExpandCollapseState]::Expanded) { try { $expand.Expand(); Start-Sleep -Milliseconds 350 } catch {} }
  }
}
function Find-Window([string]$needle) {
  foreach ($row in [EipWriteWin]::Windows($process.Id)) {
    $parts = $row -split '\|', 3
    if ($parts[2].Contains($needle)) { return [pscustomobject]@{ hwnd = [long]$parts[0]; class = $parts[1]; title = $parts[2] } }
  }
  return $null
}
function Find-Button($rootElement, [string]$name) {
  # KV dialogs expose their buttons as Pane or Button depending on the dialog;
  # match by name and let the caller choose BM_CLICK vs a mouse click.
  foreach ($b in @($rootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))) {
    if ([string]$b.Current.Name -eq $name) { return $b }
  }
  return $null
}

Expand-Item (Get-TreeItem '^单元配置$')
Start-Sleep -Milliseconds 250
Expand-Item (Get-TreeItem '^\[0\]')
Start-Sleep -Milliseconds 250
$eipNode = Get-TreeItem '^EtherNet/IP'
if (-not $eipNode) { throw 'KV_EIP_TREE_NODE_MISSING' }
[void][EipWriteWin]::SetForegroundWindow([IntPtr]$process.MainWindowHandle)
Start-Sleep -Milliseconds 300
$selection = $null
if ($eipNode.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selection)) { try { $selection.Select() } catch {} }
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
$deadline = (Get-Date).AddSeconds(15)
$eipWindow = $null
do {
  Start-Sleep -Milliseconds 500
  $eipWindow = Find-Window 'EtherNet/IP 设定'
} while (-not $eipWindow -and (Get-Date) -lt $deadline)
if (-not $eipWindow) { throw 'KV_EIP_SETTINGS_NOT_OPENED' }
Log 'settings_opened' @{ hwnd = $eipWindow.hwnd }
[void][EipWriteWin]::MoveWindow([IntPtr]$eipWindow.hwnd, 0, 0, 1500, 900, $true)
Start-Sleep -Milliseconds 800
[void][EipWriteWin]::SetForegroundWindow([IntPtr]$eipWindow.hwnd)
Start-Sleep -Milliseconds 500
function Find-ManualDialog {
  foreach ($row in [EipWriteWin]::Windows($process.Id)) {
    $parts = $row -split '\|', 3
    if ($parts[2] -eq 'EtherNet/IP 设定' -and $parts[1] -eq '#32770') { return [pscustomobject]@{ hwnd = [long]$parts[0] } }
  }
  return $null
}
# First-run dialog: choose manual device configuration. The dialog can take a
# few seconds to appear after the settings window is shown.
$manualDeadline = (Get-Date).AddSeconds(12)
$manualSelected = $false
do {
  $manualDialog = Find-ManualDialog
  if ($manualDialog) {
    $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$manualDialog.hwnd)
    $manual = Find-Button $el '手动(M)'
    if ($manual) {
      $r = $manual.Current.BoundingRectangle
      $native = [long]$manual.Current.NativeWindowHandle
      if ($native -ne 0) {
        Add-Type -TypeDefinition 'using System;using System.Runtime.InteropServices;public class EipMsg{[DllImport("user32.dll")]public static extern IntPtr SendMessage(IntPtr h,uint m,IntPtr w,IntPtr l);}' -ErrorAction SilentlyContinue
        [void][EipMsg]::SendMessage([IntPtr]$native, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
      } else {
        [EipWriteWin]::Click([int]($r.Left + $r.Width / 2), [int]($r.Top + $r.Height / 2))
      }
      Start-Sleep -Seconds 2
      Log 'manual_mode_clicked'
    }
  }
  $manualSelected = -not ($null -ne (Find-ManualDialog))
  if (-not $manualSelected) { Start-Sleep -Milliseconds 500 }
} while (-not $manualSelected -and (Get-Date) -lt $manualDeadline)
if (-not $manualSelected) { throw 'KV_EIP_MANUAL_MODE_NOT_SELECTED' }
Log 'manual_mode_ready'

if ($PreflightOnly) {
  $shot = Save-Shot 'preflight.png'
  $result = [ordered]@{ ok = $true; preflight_only = $true; project = $ProjectName; devices = $devices.Count; screenshot = $shot; note = 'EIP settings opened and manual mode selected; device writing not attempted' }
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'eip_write_result.json') -Encoding UTF8
  Log 'preflight_done'
  $result | ConvertTo-Json -Depth 3
  exit 0
}

# Device add for the first configured device. The catalog is a VSFlexGrid, so
# the search tab is used to filter to the model, then the first result row is
# activated by a double click.
$device = $devices[0]
$tabs = $null
$condition = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
  [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::TabItem)
$tabItems = @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition))
$searchTab = $null
foreach ($t in $tabItems) { if ([string]$t.Current.Name -like '*设备查找*') { $searchTab = $t } }
if (-not $searchTab) { throw 'KV_EIP_SEARCH_TAB_MISSING' }
$selTab = $null
if ($searchTab.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selTab)) { try { $selTab.Select() } catch {} }
Start-Sleep -Milliseconds 600
$editCondition = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
  [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
$searchEdit = $null
foreach ($e in @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $editCondition))) {
  $r = $e.Current.BoundingRectangle
  if ($r.Width -gt 100 -and $r.Top -gt 60 -and $r.Top -lt 220) { $searchEdit = $e; break }
}
if (-not $searchEdit) { throw 'KV_EIP_SEARCH_EDIT_MISSING' }
$setValue = $null
if ($searchEdit.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$setValue)) {
  try { $setValue.SetValue([string]$device.model) } catch {}
}
Start-Sleep -Milliseconds 400

$searchButton = $null
foreach ($b in @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition -ArgumentList @([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Button))))) {
  $n = [string]$b.Current.Name
  if ($n -eq '查找' -or $n -eq '检索' -or $n -eq '设备查找') { $searchButton = $b; break }
}
if ($searchButton) {
  $r = $searchButton.Current.BoundingRectangle
  [EipWriteWin]::Click([int]($r.Left + $r.Width / 2), [int]($r.Top + $r.Height / 2))
  Start-Sleep -Seconds 2
}

# Activate the first result row (right panel list area under the search box).
[EipWriteWin]::DoubleClick(1380, 330)
Start-Sleep -Seconds 2

$adapterDialog = $null
foreach ($row in [EipWriteWin]::Windows($process.Id)) {
  $parts = $row -split '\|', 3
  if ($parts[1] -eq '#32770') {
    try {
      $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr][long]$parts[0])
      $texts = @($el.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition) | ForEach-Object { [string]$_.Current.Name })
      if (($texts -join ' ') -match '通信适配器') { $adapterDialog = $parts[0] }
    } catch {}
  }
}
if ($adapterDialog) {
  $shot = Save-Shot 'communication_adapter_required.png'
  $result = [ordered]@{
    ok = $false
    error_code = 'KV_EIP_COMMUNICATION_ADAPTER_REQUIRED'
    message = 'KV STUDIO requires a 通信适配器 before an EtherNet/IP device can be added; configure it in the EIP CPU/通信 settings, then rerun.'
    project = $ProjectName
    device = $device
    screenshot = $shot
  }
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'eip_write_result.json') -Encoding UTF8
  Log 'adapter_required'
  $result | ConvertTo-Json -Depth 3
  exit 42
}

throw 'KV_EIP_DEVICE_ADD_UNVERIFIED: the catalog activation path did not reach a verified device row; extend the runner before claiming a write.'

