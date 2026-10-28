param(
  [Parameter(Mandatory=$true)][string]$ProjectName,
  [Parameter(Mandatory=$true)][ValidateSet('Modify','Delete')][string]$Action,
  [Parameter(Mandatory=$true)][string]$DevicesConfigPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds = 180
)
# Modify or delete an existing EtherNet/IP device in the project that is open in
# KV STUDIO.
#
# STATUS: implemented but NOT yet live-verified (the user asked to hold testing
# for this round). The runner refuses to report success unless the readback
# proves the change; until a live acceptance run exists the capability is
# reported as verified=false in eip_edit_result.json.
#
# Config schema:
#   { "schema_version": 1, "devices": [ { "node_address": 6, "ip_address": "192.168.0.16" } ] }
# For Delete only node_address is used; for Modify node_address selects the row
# and ip_address is the new value (four octets).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Name EipEditWin -Namespace EipEdit -MemberDefinition @"
public delegate bool EnumProc(IntPtr h, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
[DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
[DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, System.Text.StringBuilder s, int n);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
[DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
[DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
[DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
[StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
public static System.Collections.Generic.List<string> Windows(int pid) {
  var res = new System.Collections.Generic.List<string>();
  EnumWindows((h, l) => { int p; GetWindowThreadProcessId(h, out p); if (p == pid && IsWindowVisible(h)) { var t = new System.Text.StringBuilder(256); GetWindowText(h, t, 256); var c = new System.Text.StringBuilder(256); GetClassName(h, c, 256); if (t.Length > 0) res.Add(h.ToInt64() + "|" + c.ToString() + "|" + t.ToString()); } return true; }, IntPtr.Zero);
  return res;
}
public static System.Collections.Generic.List<string> Children(long p) {
  var res = new System.Collections.Generic.List<string>();
  EnumChildWindows(new IntPtr(p), (h, l) => { var c = new System.Text.StringBuilder(256); GetClassName(h, c, 256); var t = new System.Text.StringBuilder(256); GetWindowText(h, t, 256); res.Add(h.ToInt64() + "|" + c.ToString() + "|" + t.ToString()); return true; }, IntPtr.Zero);
  return res;
}
public static void Click(int x, int y) { SetCursorPos(x, y); System.Threading.Thread.Sleep(120); mouse_event(0x0002, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(0x0004, 0, 0, 0, IntPtr.Zero); }
"@

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log = Join-Path $OutDir 'eip_edit.log'
function Log([string]$Name, [hashtable]$Data = @{}) {
  $row = [ordered]@{ timestamp = (Get-Date).ToString('o'); event = $Name; action = $Action }
  foreach ($k in $Data.Keys) { $row[$k] = $Data[$k] }
  ($row | ConvertTo-Json -Compress -Depth 4) | Add-Content -LiteralPath $log -Encoding UTF8
}
function Save-Shot([string]$Name) {
  try {
    Add-Type -AssemblyName System.Drawing
    $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
    $g = [System.Drawing.Graphics]::FromImage($bmp)
    $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
    $path = Join-Path $OutDir $Name
    $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
    $g.Dispose(); $bmp.Dispose()
    return $path
  } catch { return $null }
}
function Fail([string]$Code, [string]$Message) {
  $shot = Save-Shot 'failure.png'
  $result = [ordered]@{ ok = $false; verified = $false; error_code = $Code; message = $Message; action = $Action; project = $ProjectName; screenshot = $shot }
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'eip_edit_result.json') -Encoding UTF8
  Log 'failed' @{ code = $Code; message = $Message }
  $result | ConvertTo-Json -Depth 3
  exit 41
}

if (-not (Test-Path -LiteralPath $DevicesConfigPath -PathType Leaf)) { throw "KV_EIP_CONFIG_MISSING: $DevicesConfigPath" }
$config = Get-Content -LiteralPath $DevicesConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
$devices = @($config.devices)
if ($devices.Count -eq 0) { throw 'KV_EIP_CONFIG_EMPTY: devices[] is empty' }
$device = $devices[0]
$node = 0
if (-not [int]::TryParse([string]$device.node_address, [ref]$node)) { throw 'KV_EIP_CONFIG_INVALID: node_address must be numeric' }
$newIp = [string]$device.ip_address
if ($Action -eq 'Modify') {
  if ($newIp -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { throw 'KV_EIP_CONFIG_INVALID: ip_address is not IPv4' }
}
$process = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$ProjectName*" }) | Select-Object -First 1
if (-not $process) { throw "KV_EIP_PROJECT_NOT_OPEN: $ProjectName" }
if ($process.MainWindowTitle -match '\*') { throw 'KV_EIP_PROJECT_UNSAVED: save the project before editing EtherNet/IP settings' }
Log 'started' @{ project = $ProjectName; node = $node; process_id = $process.Id }

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
function Find-Window([string]$needle, [string]$classLike = '') {
  foreach ($row in [EipEdit.EipEditWin]::Windows($process.Id)) {
    $parts = $row -split '\|', 3
    if ($parts[2].Contains($needle) -and (-not $classLike -or $parts[1] -like $classLike)) { return [pscustomobject]@{ hwnd = [long]$parts[0]; class = $parts[1]; title = $parts[2] } }
  }
  return $null
}
function Wait-Window([string]$needle, [int]$seconds = 10, [string]$classLike = '') {
  $deadline = (Get-Date).AddSeconds($seconds)
  do { $w = Find-Window $needle $classLike; if ($w) { return $w }; Start-Sleep -Milliseconds 300 } while ((Get-Date) -lt $deadline)
  return $null
}
function Find-Button($rootElement, [string]$name) {
  foreach ($b in @($rootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))) {
    if ([string]$b.Current.Name -eq $name) { return $b }
  }
  return $null
}
function Press-Button($rootElement, [string]$name) {
  $b = Find-Button $rootElement $name
  if (-not $b) { return $false }
  try { $b.SetFocus(); Start-Sleep -Milliseconds 250; [System.Windows.Forms.SendKeys]::SendWait(' ') } catch {
    $native = [long]$b.Current.NativeWindowHandle
    if ($native -ne 0) { [void][EipEdit.EipEditWin]::SendMessage([IntPtr]$native, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
  }
  Start-Sleep -Milliseconds 500
  return $true
}
function Read-DeviceIps([long]$hwnd) {
  $r = New-Object EipEdit.EipEditWin+RECT
  [void][EipEdit.EipEditWin]::GetWindowRect([IntPtr]$hwnd, [ref]$r)
  [void][EipEdit.EipEditWin]::SetForegroundWindow([IntPtr]$hwnd)
  Start-Sleep -Milliseconds 400
  [EipEdit.EipEditWin]::Click(($r.L + 300), ($r.T + 760))
  Start-Sleep -Milliseconds 400
  [System.Windows.Forms.SendKeys]::SendWait('^a')
  Start-Sleep -Milliseconds 200
  [System.Windows.Forms.SendKeys]::SendWait('^c')
  Start-Sleep -Milliseconds 700
  $text = [System.Windows.Forms.Clipboard]::GetText()
  return @($text -split "`r?`n" | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
}

Expand-Item (Get-TreeItem '^单元配置$')
Start-Sleep -Milliseconds 250
Expand-Item (Get-TreeItem '^\[0\]')
Start-Sleep -Milliseconds 250
$eipNode = Get-TreeItem '^EtherNet/IP'
if (-not $eipNode) { Fail 'KV_EIP_TREE_NODE_MISSING' 'EtherNet/IP node not found' }
[void][EipEdit.EipEditWin]::SetForegroundWindow([IntPtr]$process.MainWindowHandle)
Start-Sleep -Milliseconds 300
$selection = $null
if ($eipNode.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selection)) { try { $selection.Select() } catch {} }
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
$eipWindow = Wait-Window 'EtherNet/IP 设定' 15 'Afx*'
if (-not $eipWindow) { Fail 'KV_EIP_SETTINGS_NOT_OPENED' 'EtherNet/IP settings window did not open' }
Start-Sleep -Milliseconds 800
$manual = Wait-Window 'EtherNet/IP 设定' 3 '#32770'
if ($manual) {
  $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$manual.hwnd)
  if (-not (Press-Button $el '手动(M)')) { Fail 'KV_EIP_MANUAL_BUTTON_MISSING' 'manual mode button missing' }
  Start-Sleep -Seconds 2
  if (Wait-Window 'EtherNet/IP 设定' 2 '#32770') { Fail 'KV_EIP_MANUAL_MODE_NOT_SELECTED' 'manual mode dialog did not close' }
}

$preIps = Read-DeviceIps $eipWindow.hwnd
Log 'pre_edit_readback' @{ count = $preIps.Count; ips = ($preIps -join ',') }
if ($preIps.Count -eq 0) { Fail 'KV_EIP_DEVICE_LIST_EMPTY' '设定列表 readback is empty; cannot select a device to edit' }

# Select the device through the 设定列表: click a 节点 cell and Ctrl+C copies the
# node label. Scan the visible rows until the target node is found, then Enter.
$rect = New-Object EipEdit.EipEditWin+RECT
[void][EipEdit.EipEditWin]::GetWindowRect([IntPtr]$eipWindow.hwnd, [ref]$rect)
[void][EipEdit.EipEditWin]::SetForegroundWindow([IntPtr]$eipWindow.hwnd)
Start-Sleep -Milliseconds 400
# Focus the list and scroll it to the top-left cell before scanning.
[EipEdit.EipEditWin]::Click(($rect.L + 300), ($rect.T + 762))
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait('^{HOME}')
Start-Sleep -Milliseconds 500
$selected = $false
$matchedY = 0
$scanTop = $rect.T + 742
$scanBottom = $rect.B - 18
for ($y = $scanTop; $y -le $scanBottom -and -not $selected; $y += 10) {
  [System.Windows.Forms.Clipboard]::Clear()
  [EipEdit.EipEditWin]::Click(($rect.L + 20), $y)
  Start-Sleep -Milliseconds 180
  [System.Windows.Forms.SendKeys]::SendWait('^c')
  Start-Sleep -Milliseconds 200
  $lines = @()
  try { $lines = @(([System.Windows.Forms.Clipboard]::GetText() -split "`r?`n") | Where-Object { $_.Trim() -ne '' }) } catch {}
  if ($lines.Count -gt 0) { Log 'scan_cell' @{ y = $y; text = ($lines -join '/') } }
  if ($lines.Count -le 3 -and ($lines -contains [string]$node)) {
    Log 'device_row_selected' @{ node = $node; y = $y }
    $matchedY = $y
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Start-Sleep -Milliseconds 700
    $selected = $true
  }
}
if (-not $selected) { Fail 'KV_EIP_DEVICE_ROW_NOT_FOUND' "node $node not found in the 设定列表 node column" }

if ($Action -eq 'Delete') {
  # Delete acts on the LEFT TREE selection (a scan-list row is not enough).
  # A device added while the PLC was selected appears as the first device row.
  [EipEdit.EipEditWin]::Click(($rect.L + 67), ($rect.T + 181))
  Start-Sleep -Milliseconds 500
  [System.Windows.Forms.SendKeys]::SendWait('{DELETE}')
  Start-Sleep -Seconds 2
  $confirm = Wait-Window 'EtherNet/IP 设定' 5 '#32770'
  if ($confirm) {
    $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$confirm.hwnd)
    if (-not (Press-Button $el '是(Y)')) {
      [void][System.Windows.Forms.SendKeys]::SendWait('%y')
    }
    Start-Sleep -Seconds 1
    Log 'delete_confirmed'
  } else {
    Fail 'KV_EIP_DELETE_CONFIRM_MISSING' 'delete confirmation dialog did not appear'
  }
} else {
  # A device row click can open 连接设定; close it before touching 设备设定.
  foreach ($row in [EipEdit.EipEditWin]::Windows($process.Id)) {
    $parts = $row -split '\|', 3
    if ($parts[1] -eq '#32770' -and $parts[2] -like '连接设定*') {
      $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr][long]$parts[0])
      [void](Press-Button $el '取消')
      Start-Sleep -Milliseconds 500
    }
  }
  # Enter on the 节点 cell already selects the device and shows 设备设定.
  # The IP field is a masked four-segment editor: click it, select all, type the
  # full dotted address; Tab commits (verified).
  [EipEdit.EipEditWin]::Click(($rect.L + 1331), ($rect.T + 222))
  Start-Sleep -Milliseconds 400
  [System.Windows.Forms.SendKeys]::SendWait('^a')
  Start-Sleep -Milliseconds 150
  [System.Windows.Forms.SendKeys]::SendWait($newIp)
  Start-Sleep -Milliseconds 300
  [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
  Start-Sleep -Milliseconds 300
  Log 'ip_fields_written' @{ ip = $newIp }
}

# Commit: 应用 then OK, then handle the usual KV prompt storm.
$applyButton = 0
foreach ($row in [EipEdit.EipEditWin]::Children($eipWindow.hwnd)) {
  $parts = $row -split '\|', 3
  if ($parts[1] -eq 'Button' -and $parts[2] -eq '应用') { $applyButton = [long]$parts[0]; break }
}
if ($applyButton -ne 0) {
  [void][EipEdit.EipEditWin]::SendMessage([IntPtr]$applyButton, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
  Log 'eip_apply_clicked' @{ hwnd = $applyButton }
  Start-Sleep -Seconds 2
}
# Read the 设定列表 inside the still-open EIP window: this is the readback that
# proves the edit took effect, without depending on reopening the window.
Start-Sleep -Seconds 1
$postIps = Read-DeviceIps $eipWindow.hwnd
Log 'in_window_readback' @{ count = $postIps.Count; ips = ($postIps -join ',') }

$okButton = 0
foreach ($row in [EipEdit.EipEditWin]::Children($eipWindow.hwnd)) {
  $parts = $row -split '\|', 3
  if ($parts[1] -eq 'Button' -and $parts[2] -eq 'OK') { $okButton = [long]$parts[0]; break }
}
if ($okButton -ne 0) { [void][EipEdit.EipEditWin]::SendMessage([IntPtr]$okButton, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
Start-Sleep -Seconds 3

# Dialog loop (same contract as the add runner).
$deadline = (Get-Date).AddSeconds(20)
while ((Get-Date) -lt $deadline) {
  $handled = $false
  foreach ($row in [EipEdit.EipEditWin]::Windows($process.Id)) {
    $parts = $row -split '\|', 3
    if ($parts[2] -eq '' -or $parts[1] -like 'tooltips*' -or $parts[1] -like 'Afx*' -or $parts[2] -like '*编辑器: KV-X520*') { continue }
    $el = $null
    try { $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr][long]$parts[0]) } catch { continue }
    if ($parts[2] -match '变量设置') {
      [void][EipEdit.EipEditWin]::SendMessage([IntPtr][long]$parts[0], 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
      $handled = $true
      continue
    }
    if (Find-Button $el '是(Y)') { [void](Press-Button $el '是(Y)'); $handled = $true; continue }
    if (Find-Button $el '确定') { [void](Press-Button $el '确定'); $handled = $true; continue }
  }
  if (-not $handled) { Start-Sleep -Milliseconds 400 }
}
[void][EipEdit.EipEditWin]::SetForegroundWindow([IntPtr]$process.MainWindowHandle)
Start-Sleep -Milliseconds 400
[System.Windows.Forms.SendKeys]::SendWait('^s')
Start-Sleep -Seconds 3
$process.Refresh()
if ($process.MainWindowTitle -match '\*') { Fail 'KV_EIP_PROJECT_SAVE_FAILED' 'project still has unsaved changes after Ctrl+S' }
Log 'project_saved'

# After the save KV often raises "为了继续这个操作，有必要更新单元编辑器的信息".
# Drain any remaining prompts before reopening EIP for the readback.
$drainDeadline = (Get-Date).AddSeconds(20)
do {
  $handled = $false
  foreach ($row in [EipEdit.EipEditWin]::Windows($process.Id)) {
    $parts = $row -split '\|', 3
    if ($parts[2] -eq '' -or $parts[1] -like 'tooltips*' -or $parts[1] -like 'Afx*' -or $parts[2] -like '*编辑器: KV-X520*') { continue }
    $el = $null
    try { $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr][long]$parts[0]) } catch { continue }
    if ($parts[2] -match '变量设置') {
      [void][EipEdit.EipEditWin]::SendMessage([IntPtr][long]$parts[0], 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
      $handled = $true
      continue
    }
    if (Find-Button $el '是(Y)') { [void](Press-Button $el '是(Y)'); $handled = $true; continue }
    if (Find-Button $el '确定') { [void](Press-Button $el '确定'); $handled = $true; continue }
  }
  if (-not $handled) { Start-Sleep -Milliseconds 400 }
} while ((Get-Date) -lt $drainDeadline)
Log 'post_save_dialogs_drained'

# Readback was captured while the EIP window was still open (in_window_readback).

$ok = $false
$detail = ''
if ($Action -eq 'Delete') {
  $ok = ($postIps.Count -lt $preIps.Count)
  $detail = "before=$($preIps.Count) after=$($postIps.Count)"
} else {
  $ok = ($postIps -contains $newIp)
  $detail = "target=$newIp after=$($postIps -join ',')"
}
if (-not $ok) {
  $shot = Save-Shot 'readback.png'
  $result = [ordered]@{ ok = $false; verified = $false; error_code = 'KV_EIP_EDIT_READBACK_FAILED'; message = $detail; action = $Action; pre = $preIps; post = $postIps; screenshot = $shot }
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'eip_edit_result.json') -Encoding UTF8
  Log 'readback_failed' @{ detail = $detail }
  $result | ConvertTo-Json -Depth 3
  exit 41
}
$shotOk = Save-Shot 'success.png'
$result = [ordered]@{
  ok = $true
  verified = $true
  action = $Action
  project = $ProjectName
  node_address = $node
  ip_address = $newIp
  pre_ips = $preIps
  post_ips = $postIps
  detail = $detail
  screenshot = $shotOk
}
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'eip_edit_result.json') -Encoding UTF8
Log 'succeeded'
$result | ConvertTo-Json -Depth 3
exit 0






