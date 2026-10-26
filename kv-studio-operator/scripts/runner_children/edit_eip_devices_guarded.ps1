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

# The scan-list tree lists devices in descending node order (observed: 6,5,...).
# Click the row for the requested node using the window rect and fixed offsets.
$rect = New-Object EipEdit.EipEditWin+RECT
[void][EipEdit.EipEditWin]::GetWindowRect([IntPtr]$eipWindow.hwnd, [ref]$rect)
$maxNode = $preIps.Count
$rowIndex = [Math]::Max(0, $maxNode - $node)
$rowY = $rect.T + 160 + ($rowIndex * 24)
[void][EipEdit.EipEditWin]::SetForegroundWindow([IntPtr]$eipWindow.hwnd)
Start-Sleep -Milliseconds 400
[EipEdit.EipEditWin]::Click(($rect.L + 150), $rowY)
Start-Sleep -Milliseconds 500
Log 'device_row_clicked' @{ node = $node; row = $rowIndex; y = $rowY }

if ($Action -eq 'Delete') {
  [System.Windows.Forms.SendKeys]::SendWait('{DELETE}')
  Start-Sleep -Seconds 2
  $confirm = Wait-Window 'EtherNet/IP 设定' 5 '#32770'
  if ($confirm) {
    $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$confirm.hwnd)
    if (-not (Press-Button $el '是(Y)')) { [void](Press-Button $el '确定') }
    Start-Sleep -Seconds 1
    Log 'delete_confirmed'
  }
} else {
  # 设备设定 tab: edit the IP octets that currently match the old value.
  [System.Windows.Forms.SendKeys]::SendWait('%2')
  Start-Sleep -Seconds 1
  $octets = $newIp -split '\.'
  $edits = @([EipEdit.EipEditWin]::Children($eipWindow.hwnd) | Where-Object { $_ -match '\|Edit\|' })
  $ipEdits = @($edits | Where-Object {
    $parts = $_ -split '\|', 3
    $parts[2] -match '^\d{1,3}$'
  })
  if ($ipEdits.Count -lt 4) { Fail 'KV_EIP_IP_FIELDS_NOT_FOUND' "expected 4 IP edits on 设备设定, found $($ipEdits.Count)" }
  $target = @($ipEdits[($ipEdits.Count - 4)..($ipEdits.Count - 1)])
  for ($k = 0; $k -lt 4; $k++) {
    $h = [long](($target[$k] -split '\|')[0])
    [void][EipEdit.EipEditWin]::SetForegroundWindow([IntPtr]$h)
    Start-Sleep -Milliseconds 200
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Start-Sleep -Milliseconds 100
    [System.Windows.Forms.Clipboard]::SetText($octets[$k])
    Start-Sleep -Milliseconds 100
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 150
    [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
    Start-Sleep -Milliseconds 200
  }
  Log 'ip_fields_written' @{ ip = $newIp }
}

# Commit: 应用 then OK, then handle the usual KV prompt storm.
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
Start-Sleep -Seconds 1
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

# Readback: reopen EIP and compare the IP set.
$eipNode = Get-TreeItem '^EtherNet/IP'
if (-not $eipNode) { Fail 'KV_EIP_READBACK_TREE_MISSING' 'EtherNet/IP node missing before readback' }
if ($eipNode.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selection)) { try { $selection.Select() } catch {} }
Start-Sleep -Milliseconds 300
[System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
$readWindow = Wait-Window 'EtherNet/IP 设定' 15 'Afx*'
if (-not $readWindow) { Fail 'KV_EIP_READBACK_NOT_OPENED' 'EIP settings did not reopen' }
$postIps = Read-DeviceIps $readWindow.hwnd
Log 'post_edit_readback' @{ count = $postIps.Count; ips = ($postIps -join ',') }

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
