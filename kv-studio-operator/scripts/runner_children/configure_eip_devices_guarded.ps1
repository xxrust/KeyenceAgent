param(
  [Parameter(Mandatory=$true)][string]$ProjectName,
  [string]$ProjectPath = '',
  [string]$DevicesConfigPath = '',
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds = 180,
  [switch]$PreflightOnly,
  [switch]$ReadConfigurationOnly,
  [string]$ConfigurationOutPath = ''
)
# Writes an EtherNet/IP device into the project that is currently open in
# KV STUDIO. Verified flow (2026-10-26):
#   open 单元配置 > [0] > EtherNet/IP -> 手动 config -> 设备列表
#   -> catalog row scan until the model detail matches -> Enter
#   -> 适配器初始设定 (node/IP defaults) -> OK
#   -> main 设定信息被更改 -> 是(Y) -> update unit editor -> 确定
#   -> variable creation prompt -> 确定 -> variable names -> save project
#   -> reopen EIP and read the 设定列表 grid back to prove the device exists.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -Name EipWinWrite -Namespace EipWrite -MemberDefinition @"
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
[DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, string l);
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
public static string StaticText(long p) {
  var sb = new System.Text.StringBuilder();
  EnumChildWindows(new IntPtr(p), (h, l) => { var c = new System.Text.StringBuilder(256); GetClassName(h, c, 256); if (c.ToString().Contains("Static")) { var t = new System.Text.StringBuilder(512); GetWindowText(h, t, 512); if (t.Length > 0) sb.Append(t.ToString()).Append("|"); } return true; }, IntPtr.Zero);
  return sb.ToString();
}
public static void Click(int x, int y) { SetCursorPos(x, y); System.Threading.Thread.Sleep(120); mouse_event(0x0002, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(60); mouse_event(0x0004, 0, 0, 0, IntPtr.Zero); }
public static void ClickCenter(long h) { RECT r; if (GetWindowRect(new IntPtr(h), out r)) Click((r.L + r.R) / 2, (r.T + r.B) / 2); }
"@

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$log = Join-Path $OutDir 'eip_write.log'
function Log([string]$Name, [hashtable]$Data = @{}) {
  $row = [ordered]@{ timestamp = (Get-Date).ToString('o'); event = $Name }
  foreach ($k in $Data.Keys) { $row[$k] = $Data[$k] }
  ($row | ConvertTo-Json -Compress -Depth 4) | Add-Content -LiteralPath $log -Encoding UTF8
}
# Guarded input: registered with ui_guard_required; every SendKeys goes through
# the shared guard and must target the foreground KV STUDIO window.
Add-Type -TypeDefinition 'using System; using System.Runtime.InteropServices; public class EipFgWin2 { [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow(); }' -ErrorAction SilentlyContinue
$script:EipGuardRoot = Split-Path -Parent $PSScriptRoot
. (Join-Path $script:EipGuardRoot 'guards\kv_ui_guard.ps1')
Initialize-KvUiGuard -OutDir (Join-Path $OutDir 'guard') | Out-Null
$script:EipKeyStep = 0
function Send-KvKeys([string]$Keys, [string]$Step = '', [IntPtr]$Target = [IntPtr]::Zero, [string]$Title = '') {
  $script:EipKeyStep++
  if (-not $Step) { $Step = "eip key $script:EipKeyStep" }
  if ($Target -eq [IntPtr]::Zero) { $Target = [EipFgWin2]::GetForegroundWindow() }
  Invoke-KvGuardedSendKeysScoped -TargetHwnd $Target -Step $Step -Keys $Keys -ExpectedTitleLike $Title -OwnerProcessId $process.Id -SleepMs 120
}
function Save-Shot([string]$Name) {
  try {
    Add-Type -AssemblyName System.Drawing
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
function Fail([string]$Code, [string]$Message) {
  $shot = Save-Shot 'failure.png'
  $result = [ordered]@{ ok = $false; error_code = $Code; message = $Message; project = $ProjectName; screenshot = $shot }
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'eip_write_result.json') -Encoding UTF8
  Log 'failed' @{ code = $Code; message = $Message }
  $result | ConvertTo-Json -Depth 3
  exit 41
}

$devices = @()
if (-not $ReadConfigurationOnly) {
  if (-not $DevicesConfigPath) { throw 'KV_EIP_CONFIG_REQUIRED: DevicesConfigPath is required unless -ReadConfigurationOnly' }
  if (-not (Test-Path -LiteralPath $DevicesConfigPath -PathType Leaf)) { throw "KV_EIP_CONFIG_MISSING: $DevicesConfigPath" }
  $config = Get-Content -LiteralPath $DevicesConfigPath -Raw -Encoding UTF8 | ConvertFrom-Json
  $devices = @($config.devices)
  if ($devices.Count -eq 0) { throw 'KV_EIP_CONFIG_EMPTY: devices[] is empty' }
  foreach ($d in $devices) { if (-not $d.model) { throw 'KV_EIP_CONFIG_INVALID: device.model is required' } }
}
$device = $devices[0]
$candidates = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$ProjectName*" })
if ($candidates.Count -eq 0) { throw "KV_EIP_PROJECT_NOT_OPEN: $ProjectName" }
if ($candidates.Count -gt 1) { throw "KV_EIP_PROJECT_AMBIGUOUS: $($candidates.Count) KV STUDIO windows match '$ProjectName'" }
$process = $candidates[0]
if ($ProjectPath) {
  $cmdLine = ([string](Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)" -ErrorAction SilentlyContinue).CommandLine)
  if (-not $cmdLine -or $cmdLine -notlike "*$ProjectPath*") {
    throw "KV_EIP_PROJECT_PATH_MISMATCH: pid=$($process.Id) title='$($process.MainWindowTitle)' expected='$ProjectPath'"
  }
}
if ($process.MainWindowTitle -match '\*') { throw 'KV_EIP_PROJECT_UNSAVED: save the project before writing EtherNet/IP settings' }
Log 'started' @{ project = $ProjectName; model = [string]$device.model; process_id = $process.Id }

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
  foreach ($row in [EipWrite.EipWinWrite]::Windows($process.Id)) {
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
function Find-ChildButton([long]$hwnd, [string]$text) {
  foreach ($row in [EipWrite.EipWinWrite]::Children($hwnd)) {
    $parts = $row -split '\|', 3
    if ($parts[1] -eq 'Button' -and $parts[2] -eq $text) { return [long]$parts[0] }
  }
  return 0
}
function Handle-EipDialogs([int]$seconds = 20) {
  # After the EIP window is closed KV may show, in any order: the save-changes
  # prompt (是/否/取消), the unit-editor refresh prompt, the variable creation
  # prompt and the WinForms variable-name dialog. Handle whatever appears.
  $deadline = (Get-Date).AddSeconds($seconds)
  $handled = 0
  while ((Get-Date) -lt $deadline) {
    $sawDialog = $false
    foreach ($row in [EipWrite.EipWinWrite]::Windows($process.Id)) {
      $parts = $row -split '\|', 3
      if ($parts[2] -eq '' -or $parts[1] -like 'tooltips*' -or $parts[1] -like 'Afx*' -or $parts[2] -like '*编辑器: KV-X520*') { continue }
      $sawDialog = $true
      $el = $null
      try { $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr][long]$parts[0]) } catch { Start-Sleep -Milliseconds 300; continue }
      if (-not $el) { continue }
      if ($parts[2] -match '变量设置') {
        # Variable names are optional for the device write; close the dialog and
        # keep the device configuration.
        [void][EipWrite.EipWinWrite]::SendMessage([IntPtr][long]$parts[0], 0x0010, [IntPtr]::Zero, [IntPtr]::Zero)
        Log 'variable_dialog_closed' @{ hwnd = $parts[0] }
        $handled++
        Start-Sleep -Milliseconds 600
        continue
      }
      $yes = Find-Button $el '是(Y)'
      if ($yes) {
        try { [void](Press-Button $el '是(Y)'); Log 'dialog_yes' @{ title = $parts[2] }; $handled++ } catch {}
        Start-Sleep -Milliseconds 500
        continue
      }
      $ok = Find-Button $el '确定'
      if ($ok) {
        try { [void](Press-Button $el '确定'); Log 'dialog_ok' @{ title = $parts[2] }; $handled++ } catch {}
        Start-Sleep -Milliseconds 500
        continue
      }
    }
    if (-not $sawDialog) { Start-Sleep -Milliseconds 400 }
  }
  return $handled
}
function Press-Button($rootElement, [string]$name) {
  # KV prompts are WinForms inside #32770 shells; BM_CLICK is ignored there, so
  # focus the button and press Space (verified on 确定/是(Y)/手动(M)).
  $b = Find-Button $rootElement $name
  if (-not $b) { return $false }
  $pressed = $false
  try { $b.SetFocus(); Start-Sleep -Milliseconds 250; Send-KvKeys -Keys ' ' -Step 'eip key'; $pressed = $true } catch {}
  if (-not $pressed) {
    $native = [long]$b.Current.NativeWindowHandle
    if ($native -ne 0) { [void][EipWrite.EipWinWrite]::SendMessage([IntPtr]$native, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
  }
  Start-Sleep -Seconds 1
  return $true
}

Expand-Item (Get-TreeItem '^单元配置$')
Start-Sleep -Milliseconds 250
Expand-Item (Get-TreeItem '^\[0\]')
Start-Sleep -Milliseconds 250
$eipNode = Get-TreeItem '^EtherNet/IP'
if (-not $eipNode) { Fail 'KV_EIP_TREE_NODE_MISSING' 'EtherNet/IP node not found in the project tree' }
[void][EipWrite.EipWinWrite]::SetForegroundWindow([IntPtr]$process.MainWindowHandle)
Start-Sleep -Milliseconds 300
$selection = $null
if ($eipNode.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selection)) { try { $selection.Select() } catch {} }
Start-Sleep -Milliseconds 300
Send-KvKeys -Keys '{ENTER}' -Step 'eip key'
$eipWindow = Wait-Window 'EtherNet/IP 设定' 15 'Afx*'
if (-not $eipWindow) { Fail 'KV_EIP_SETTINGS_NOT_OPENED' 'EtherNet/IP settings window did not open' }
Log 'settings_opened' @{ hwnd = $eipWindow.hwnd }
Start-Sleep -Milliseconds 800

# First-run prompt: manual configuration.
$manual = Wait-Window 'EtherNet/IP 设定' 3 '#32770'
if ($manual) {
  $el = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$manual.hwnd)
  if (-not (Press-Button $el '手动(M)')) { Fail 'KV_EIP_MANUAL_BUTTON_MISSING' 'manual mode button not found' }
  Start-Sleep -Seconds 2
  if (Wait-Window 'EtherNet/IP 设定' 2 '#32770') { Fail 'KV_EIP_MANUAL_MODE_NOT_SELECTED' 'manual mode dialog did not close' }
  Log 'manual_mode_selected'
}
if ($ReadConfigurationOnly) {
  $gridRect = New-Object EipWrite.EipWinWrite+RECT
  [void][EipWrite.EipWinWrite]::GetWindowRect([IntPtr]$eipWindow.hwnd, [ref]$gridRect)
  [void][EipWrite.EipWinWrite]::SetForegroundWindow([IntPtr]$eipWindow.hwnd)
  Start-Sleep -Milliseconds 500
  # Click the 设定列表 grid itself (VSFlexGrid8N); fixed offsets miss it when the
  # window is not at the remembered position.
  $grids = @([EipWrite.EipWinWrite]::Children([long]$eipWindow.hwnd) | Where-Object { $_ -like '*|VSFlexGrid8N|*' })
  if ($grids.Count -gt 0) {
    $gridHwnd = [long](($grids[0] -split '\|')[0])
    [EipWrite.EipWinWrite]::ClickCenter($gridHwnd)
  } else {
    [EipWrite.EipWinWrite]::Click(($gridRect.L + 300), ($gridRect.T + 780))
  }
  Start-Sleep -Milliseconds 400
  if ([EipFgWin2]::GetForegroundWindow() -ne [IntPtr]$eipWindow.hwnd) {
    [void][EipWrite.EipWinWrite]::SetForegroundWindow([IntPtr]$eipWindow.hwnd)
    Start-Sleep -Milliseconds 400
    if ($grids.Count -gt 0) { [EipWrite.EipWinWrite]::ClickCenter($gridHwnd) } else { [EipWrite.EipWinWrite]::Click(($gridRect.L + 300), ($gridRect.T + 780)) }
    Start-Sleep -Milliseconds 400
  }
  Send-KvKeys -Keys '^{HOME}' -Step 'eip read configuration first cell'
  Start-Sleep -Milliseconds 250
  Send-KvKeys -Keys '^+{END}' -Step 'eip read configuration select table'
  Start-Sleep -Milliseconds 250
  Send-KvKeys -Keys '^c' -Step 'eip read configuration copy'
  Start-Sleep -Milliseconds 800
  $readText = [System.Windows.Forms.Clipboard]::GetText()
  $lines = @($readText -split "`r?`n" | Where-Object { $_.Trim() })
  $ips = @($lines | Where-Object { $_ -match '\b\d{1,3}(\.\d{1,3}){3}\b' } | ForEach-Object { [regex]::Match($_, '\b\d{1,3}(\.\d{1,3}){3}\b').Value } | Select-Object -Unique)
  # Columns: 节点 / 节点名称 / IP地址 / 连接名称 / RPI(IN) / RPI(OUT) / 超时 / 刷新优先权
  $connections = @()
  foreach ($line in $lines) {
    $cells = $line -split "`t"
    if ($cells.Count -lt 4) { continue }
    if ($cells[2] -notmatch '^\d{1,3}(\.\d{1,3}){3}$') { continue }
    $connections += [pscustomobject]@{
      node = $cells[0].Trim()
      node_name = $cells[1].Trim()
      ip_address = $cells[2].Trim()
      connection_name = $cells[3].Trim()
      rpi_in_ms = if ($cells.Count -gt 4) { $cells[4].Trim() } else { '' }
      rpi_out_ms = if ($cells.Count -gt 5) { $cells[5].Trim() } else { '' }
      timeout = if ($cells.Count -gt 6) { $cells[6].Trim() } else { '' }
      priority = if ($cells.Count -gt 7) { $cells[7].Trim() } else { '' }
    }
  }
  $closeEl = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$eipWindow.hwnd)
  $cancel = Find-Button $closeEl '取消'
  if ($cancel) {
    $native = [long]$cancel.Current.NativeWindowHandle
    if ($native -ne 0) { [void][EipWrite.EipWinWrite]::SendMessage([IntPtr]$native, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) } else { $cancel.SetFocus(); Send-KvKeys -Keys ' ' -Step 'eip read configuration cancel' }
  }
  Start-Sleep -Seconds 1
  # Opening the EIP window also restores 单元编辑器; close it so the next snapshot
  # stage does not abort on a modal window.
  for ($i = 0; $i -lt 3; $i++) {
    $editor = Wait-Window '单元编辑器' 2 'Afx*'
    if (-not $editor) { break }
    $editorEl = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$editor.hwnd)
    if (-not (Press-Button $editorEl '取消')) { break }
    Start-Sleep -Milliseconds 800
  }
  $readResult = [ordered]@{
    ok = ($lines.Count -gt 0)
    project = $ProjectName
    project_path = $ProjectPath
    row_count = $lines.Count
    ip_count = $ips.Count
    ips = $ips
    connection_count = $connections.Count
    connections = $connections
    rows = $lines
    raw_table = $readText.Trim()
    screenshot = (Save-Shot 'eip_configuration.png')
  }
  $outPath = if ($ConfigurationOutPath) { [IO.Path]::GetFullPath($ConfigurationOutPath) } else { Join-Path $OutDir 'eip_configuration.json' }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $outPath) | Out-Null
  $readResult | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $outPath -Encoding UTF8
  Log 'read_configuration_done' @{ rows = $lines.Count; ips = $ips.Count; path = $outPath }
  $readResult | ConvertTo-Json -Depth 4
  if ($readResult.ok) { exit 0 }
  exit 41
}
if ($PreflightOnly) {
  $shot = Save-Shot 'preflight.png'
  $result = [ordered]@{ ok = $true; preflight_only = $true; project = $ProjectName; devices = $devices.Count; screenshot = $shot; note = 'EIP settings opened and manual mode selected; device writing not attempted' }
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'eip_write_result.json') -Encoding UTF8
  Log 'preflight_done'
  $result | ConvertTo-Json -Depth 3
  exit 0
}

# Pre-write readback: capture the 设定列表 IP column before adding the device.
$preRect = New-Object EipWrite.EipWinWrite+RECT
[void][EipWrite.EipWinWrite]::GetWindowRect([IntPtr]$eipWindow.hwnd, [ref]$preRect)
[void][EipWrite.EipWinWrite]::SetForegroundWindow([IntPtr]$eipWindow.hwnd)
Start-Sleep -Milliseconds 500
[EipWrite.EipWinWrite]::Click(($preRect.L + 300), ($preRect.T + 760))
Start-Sleep -Milliseconds 400
Send-KvKeys -Keys '^a' -Step 'eip key'
Start-Sleep -Milliseconds 250
Send-KvKeys -Keys '^c' -Step 'eip key'
Start-Sleep -Milliseconds 800
$preText = [System.Windows.Forms.Clipboard]::GetText()
$preIps = @($preText -split "`r?`n" | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
Log 'pre_write_readback' @{ count = $preIps.Count; ips = ($preIps -join ',') }

$rect = New-Object EipWrite.EipWinWrite+RECT
[void][EipWrite.EipWinWrite]::GetWindowRect([IntPtr]$eipWindow.hwnd, [ref]$rect)
function WindowPoint([int]$dx, [int]$dy) { return @(($rect.L + $dx), ($rect.T + $dy)) }
[void][EipWrite.EipWinWrite]::SetForegroundWindow([IntPtr]$eipWindow.hwnd)
Start-Sleep -Milliseconds 500
# 设备列表 tab (Alt+1) then focus the catalog grid at its top.
Send-KvKeys -Keys '%1' -Step 'eip key'
Start-Sleep -Seconds 1
$p = WindowPoint 1300 350
[EipWrite.EipWinWrite]::Click($p[0], $p[1])
Start-Sleep -Milliseconds 300
Send-KvKeys -Keys '^{HOME}' -Step 'eip key'
Start-Sleep -Milliseconds 500

$model = [string]$device.model
$found = $false
for ($i = 0; $i -lt 300; $i++) {
  $statics = [EipWrite.EipWinWrite]::StaticText($eipWindow.hwnd)
  if ($statics -match [regex]::Escape($model)) { $found = $true; break }
  Send-KvKeys -Keys '{DOWN}' -Step 'eip key'
  Start-Sleep -Milliseconds 35
}
if (-not $found) { Fail 'KV_EIP_MODEL_NOT_IN_CATALOG' ("catalog scan did not find model " + $model) }
Log 'catalog_selected' @{ model = $model; steps = $i }
Send-KvKeys -Keys '{ENTER}' -Step 'eip key'
$adapter = Wait-Window '适配器初始设定' 10 '#32770'
if (-not $adapter) { Fail 'KV_EIP_ADAPTER_DIALOG_MISSING' '适配器初始设定 dialog did not appear' }
$adapterEl = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$adapter.hwnd)
$adapterValues = @()
$editCondition = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
  [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
foreach ($edit in @($adapterEl.FindAll([System.Windows.Automation.TreeScope]::Descendants, $editCondition))) {
  try {
    $vp = $edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $value = [string]$vp.Current.Value
    if ($value) { $adapterValues += $value }
  } catch {}
}
$assignedNode = if ($adapterValues.Count -gt 0) { $adapterValues[0] } else { [string]$device.node_address }
$octets = @($adapterValues | Where-Object { $_ -match '^\d{1,3}$' })
$assignedIp = if ($octets.Count -ge 4) { (($octets[($octets.Count - 4)..($octets.Count - 1)]) -join '.') } else { [string]$device.ip_address }
if (-not (Press-Button $adapterEl 'OK')) { Fail 'KV_EIP_ADAPTER_OK_MISSING' 'adapter dialog OK button missing' }
Start-Sleep -Seconds 2
Log 'adapter_initial_settings_confirmed' @{ node = $assignedNode; ip = $assignedIp; requested_node = [string]$device.node_address; requested_ip = [string]$device.ip_address; values = ($adapterValues -join ',') }

# Close the EIP settings window; KV then shows its update prompts in any order.
$okButton = Find-ChildButton $eipWindow.hwnd 'OK'
if ($okButton -ne 0) {
  [void][EipWrite.EipWinWrite]::SendMessage([IntPtr]$okButton, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
  Log 'eip_ok_clicked' @{ hwnd = $okButton }
} else {
  $pt = WindowPoint 1290 880
  [EipWrite.EipWinWrite]::Click($pt[0], $pt[1])
  Log 'eip_ok_coordinate_fallback'
}
$handled = Handle-EipDialogs 20
Log 'dialogs_after_ok' @{ handled = $handled }


# Save the project.
[void][EipWrite.EipWinWrite]::SetForegroundWindow([IntPtr]$process.MainWindowHandle)
Start-Sleep -Milliseconds 500
Send-KvKeys -Keys '^s' -Step 'eip key'
Start-Sleep -Seconds 4
Start-Sleep -Seconds 2
$handledSave = Handle-EipDialogs 15
Log 'dialogs_after_save' @{ handled = $handledSave }
$process.Refresh()
if ($process.MainWindowTitle -match '\*') { Fail 'KV_EIP_PROJECT_SAVE_FAILED' 'project still has unsaved changes after Ctrl+S' }
Log 'project_saved'

# Readback: reopen EIP and copy the 设定列表 grid; it must contain the device IP.
$eipNode = Get-TreeItem '^EtherNet/IP'
if (-not $eipNode) { Fail 'KV_EIP_READBACK_TREE_MISSING' 'EtherNet/IP node missing before readback' }
$selection = $null
if ($eipNode.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selection)) { try { $selection.Select() } catch {} }
Start-Sleep -Milliseconds 300
Send-KvKeys -Keys '{ENTER}' -Step 'eip key'
$readWindow = Wait-Window 'EtherNet/IP 设定' 15 'Afx*'
if (-not $readWindow) { Fail 'KV_EIP_READBACK_NOT_OPENED' 'EIP settings did not reopen for readback' }
Start-Sleep -Seconds 1
$rect2 = New-Object EipWrite.EipWinWrite+RECT
[void][EipWrite.EipWinWrite]::GetWindowRect([IntPtr]$readWindow.hwnd, [ref]$rect2)
[EipWrite.EipWinWrite]::Click(($rect2.L + 300), ($rect2.T + 760))
Start-Sleep -Milliseconds 400
Send-KvKeys -Keys '^a' -Step 'eip key'
Start-Sleep -Milliseconds 250
Send-KvKeys -Keys '^c' -Step 'eip key'
Start-Sleep -Milliseconds 800
$readText = [System.Windows.Forms.Clipboard]::GetText()
$postIps = @($readText -split "`r?`n" | Where-Object { $_ -match '^\d{1,3}(\.\d{1,3}){3}$' })
$newIps = @($postIps | Where-Object { $preIps -notcontains $_ })
$ipOk = ($newIps.Count -gt 0)
if (-not $ipOk) {
  $shot = Save-Shot 'readback.png'
  $result = [ordered]@{ ok = $false; error_code = 'KV_EIP_READBACK_FAILED'; message = '设定列表 did not gain a new device IP after the write'; clipboard = $readText; pre_ips = ($preIps -join ','); screenshot = $shot }
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'eip_write_result.json') -Encoding UTF8
  Log 'readback_failed' @{ clipboard = $readText; pre_ips = ($preIps -join ',') }
  $result | ConvertTo-Json -Depth 3
  exit 41
}
$ip = ($newIps -join ',')
Log 'readback_ok' @{ clipboard = $readText }
$closeEl = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$readWindow.hwnd)
$cancel = Find-Button $closeEl '取消'
if ($cancel) { $native = [long]$cancel.Current.NativeWindowHandle; if ($native -ne 0) { [void][EipWrite.EipWinWrite]::SendMessage([IntPtr]$native, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) } else { $cancel.SetFocus(); Send-KvKeys -Keys ' ' -Step 'eip key' } }
Start-Sleep -Seconds 1
$shot = Save-Shot 'success.png'
$result = [ordered]@{
  ok = $true
  project = $ProjectName
  model = [string]$device.model
  ip_address = $ip
  readback = $readText.Trim()
  screenshot = $shot
}
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'eip_write_result.json') -Encoding UTF8
Log 'succeeded'
$result | ConvertTo-Json -Depth 3
exit 0



