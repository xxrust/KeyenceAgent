param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectName,
  [Parameter(Mandatory=$true)]
  [string]$DeviceNamePattern,
  [string]$NodeAddress = '1',
  [Parameter(Mandatory=$true)]
  [string]$IpAddress,
  [string]$VariableNamePrefix = '',
  [string[]]$VariableNames = @(),
  [int]$MaxScanSteps = 700,
  [string]$OutDir = '',
  [switch]$KeepWindowOpen
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $OutDir = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'kv-studio-operator') 'kv_network_config_runs'
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms

if (-not ('KvEthernetIpWin32' -as [type])) {
  Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class KvEthernetIpWin32 {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr hDlg, int nIDDlgItem);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, string lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
"@
}

$BM_CLICK = 0x00F5
$WM_SETTEXT = 0x000C
$IPM_SETADDRESS = 0x0400 + 101

$NameUnitConfiguration = -join ([char[]](0x5355,0x5143,0x914D,0x7F6E))
$NameCpuUnit = '[0]  KV-X310'
$NameManual = -join ([char[]](0x624B,0x52A8))
$NameCancel = -join ([char[]](0x53D6,0x6D88))
$NameAdapterInitialSetting = -join ([char[]](0x9002,0x914D,0x5668,0x521D,0x59CB,0x8BBE,0x5B9A))
$NameNodeAddress = -join ([char[]](0x8282,0x70B9,0x5730,0x5740))
$NameIpAddress = 'IP' + (-join ([char[]](0x5730,0x5740)))
$NameOkCn = -join ([char[]](0x786E,0x5B9A))
$NameVariable = -join ([char[]](0x53D8,0x91CF))
$NameUnitEditor = (-join ([char[]](0x5355,0x5143,0x7F16,0x8F91,0x5668))) + '*'

function New-EvidencePath {
  param([string]$Name)
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
  Join-Path $OutDir ("{0}_{1}.json" -f $stamp, $Name)
}

function Write-JsonFile {
  param([string]$Path, $Value)
  $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Get-KvsProcess {
  $process = Get-Process Kvs -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$ProjectName*" } |
    Select-Object -First 1
  if (-not $process) { throw "KV STUDIO process with project '$ProjectName' was not found." }
  $process
}

function Get-VisibleTopWindows {
  $rows = New-Object System.Collections.ArrayList
  $callback = [KvEthernetIpWin32+EnumWindowsProc]{
    param($handle, $lParam)
    if ([KvEthernetIpWin32]::IsWindowVisible($handle)) {
      $titleBuilder = New-Object System.Text.StringBuilder 512
      $classBuilder = New-Object System.Text.StringBuilder 256
      [void][KvEthernetIpWin32]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity)
      [void][KvEthernetIpWin32]::GetClassName($handle, $classBuilder, $classBuilder.Capacity)
      $procIdValue = [uint32]0
      [void][KvEthernetIpWin32]::GetWindowThreadProcessId($handle, [ref]$procIdValue)
      $processName = ''
      try { $processName = (Get-Process -Id ([int]$procIdValue) -ErrorAction Stop).ProcessName } catch {}
      $title = $titleBuilder.ToString()
      $className = $classBuilder.ToString()
      if ($title -or $className -match 'WindowsForms|#32770|Afx') {
        [void]$rows.Add([pscustomobject]@{
          hwnd = $handle.ToInt64()
          process_id = [int]$procIdValue
          process_name = $processName
          title = $title
          class_name = $className
        })
      }
    }
    return $true
  }
  [void][KvEthernetIpWin32]::EnumWindows($callback, [IntPtr]::Zero)
  @($rows)
}

function Get-KvRelevantWindows {
  $process = Get-KvsProcess
  Get-VisibleTopWindows | Where-Object {
    $_.process_id -eq $process.Id -and (
      $_.title -like 'KV STUDIO*' -or
      $_.title -like $NameUnitEditor -or
      $_.title -like '*EtherNet/IP*' -or
      $_.title -like "*$NameAdapterInitialSetting*" -or
      $_.class_name -eq '#32770'
    )
  } | Sort-Object title, hwnd
}

function Get-ElementFromHwnd {
  param([long]$Hwnd)
  $element = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
  if (-not $element) { throw "AutomationElement.FromHandle failed for $Hwnd." }
  $element
}

function Get-MainWindowElement {
  $process = Get-KvsProcess
  Get-ElementFromHwnd -Hwnd $process.MainWindowHandle
}

function Get-ElementRows {
  param(
    [Windows.Automation.AutomationElement]$Root,
    [int]$Limit = 500
  )
  $all = $Root.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
  $rows = @()
  for ($i = 0; $i -lt $all.Count -and $rows.Count -lt $Limit; $i++) {
    $e = $all.Item($i)
    $name = ''
    $aid = ''
    $type = ''
    $className = ''
    $nativeHwnd = 0
    try { $name = $e.Current.Name } catch {}
    try { $aid = $e.Current.AutomationId } catch {}
    try { $type = $e.Current.ControlType.ProgrammaticName } catch {}
    try { $className = $e.Current.ClassName } catch {}
    try { $nativeHwnd = $e.Current.NativeWindowHandle } catch {}
    if ($name -or $aid -or $className) {
      $rows += [pscustomobject]@{
        index = $i
        name = $name
        automation_id = $aid
        control_type = $type
        class_name = $className
        native_hwnd = $nativeHwnd
        enabled = $e.Current.IsEnabled
        focusable = $e.Current.IsKeyboardFocusable
        rect = $e.Current.BoundingRectangle.ToString()
      }
    }
  }
  $rows
}

function Get-ChildWindowRows {
  param([long]$ParentHwnd)
  $rows = New-Object System.Collections.ArrayList
  $callback = [KvEthernetIpWin32+EnumWindowsProc]{
    param($handle, $lParam)
    $titleBuilder = New-Object System.Text.StringBuilder 512
    $classBuilder = New-Object System.Text.StringBuilder 256
    [void][KvEthernetIpWin32]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity)
    [void][KvEthernetIpWin32]::GetClassName($handle, $classBuilder, $classBuilder.Capacity)
    [void]$rows.Add([pscustomobject]@{
      hwnd = $handle.ToInt64()
      parent = ([KvEthernetIpWin32]::GetParent($handle)).ToInt64()
      visible = [KvEthernetIpWin32]::IsWindowVisible($handle)
      enabled = [KvEthernetIpWin32]::IsWindowEnabled($handle)
      title = $titleBuilder.ToString()
      class_name = $classBuilder.ToString()
    })
    return $true
  }
  [void][KvEthernetIpWin32]::EnumChildWindows([IntPtr]$ParentHwnd, $callback, [IntPtr]::Zero)
  @($rows)
}

function Invoke-ChildButtonByTitle {
  param(
    [long]$ParentHwnd,
    [string]$Title
  )
  $button = Get-ChildWindowRows -ParentHwnd $ParentHwnd |
    Where-Object { $_.visible -and $_.enabled -and $_.class_name -eq 'Button' -and $_.title -eq $Title } |
    Select-Object -First 1
  if (-not $button) { return $null }
  [void][KvEthernetIpWin32]::PostMessage([IntPtr]$button.hwnd, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 700
  [pscustomobject]@{ title = $button.title; hwnd = $button.hwnd; method = 'PostMessage_BM_CLICK' }
}

function Find-Descendant {
  param(
    [Windows.Automation.AutomationElement]$Root,
    [scriptblock]$Predicate
  )
  $all = $Root.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
  for ($i = 0; $i -lt $all.Count; $i++) {
    $e = $all.Item($i)
    if (& $Predicate $e) { return $e }
  }
  $null
}

function Find-DescendantByAutomationId {
  param(
    [Windows.Automation.AutomationElement]$Root,
    [string]$AutomationId
  )
  Find-Descendant -Root $Root -Predicate {
    param($e)
    try { $e.Current.AutomationId -eq $AutomationId } catch { $false }
  }
}

function Find-TreeItem {
  param(
    [string]$Exact = '',
    [string]$Contains = ''
  )
  $window = Get-MainWindowElement
  Find-Descendant -Root $window -Predicate {
    param($e)
    try {
      if ($e.Current.ControlType.ProgrammaticName -ne 'ControlType.TreeItem') { return $false }
      $name = $e.Current.Name
      if ($Exact -and $name -eq $Exact) { return $true }
      if ($Contains -and $name.Contains($Contains)) { return $true }
      $false
    } catch {
      $false
    }
  }
}

function Expand-TreeItem {
  param(
    [Windows.Automation.AutomationElement]$Item,
    [string]$Label
  )
  if (-not $Item) { throw "Tree item '$Label' was not found." }
  $pattern = $null
  if ($Item.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern, [ref]$pattern)) {
    try { $pattern.ScrollIntoView() } catch {}
  }
  $pattern = $null
  if ($Item.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
    try { $pattern.Select(); Start-Sleep -Milliseconds 120 } catch {}
  }
  $pattern = $null
  if (-not $Item.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$pattern)) {
    return 'NoExpandCollapsePattern'
  }
  if ($pattern.Current.ExpandCollapseState -ne [Windows.Automation.ExpandCollapseState]::Expanded) {
    $pattern.Expand()
    Start-Sleep -Milliseconds 400
  }
  $pattern.Current.ExpandCollapseState.ToString()
}

function Ensure-UnitTreeExpanded {
  $unit = Find-TreeItem -Exact $NameUnitConfiguration
  $unitState = Expand-TreeItem -Item $unit -Label 'unit configuration'
  $cpu = Find-TreeItem -Exact $NameCpuUnit
  if (-not $cpu) { $cpu = Find-TreeItem -Contains 'KV-X310' }
  $cpuState = Expand-TreeItem -Item $cpu -Label 'CPU unit'
  [pscustomobject]@{ unit_state = $unitState; cpu_state = $cpuState }
}

function Set-ForegroundWindowByHwnd {
  param([long]$Hwnd)
  if ([KvEthernetIpWin32]::IsIconic([IntPtr]$Hwnd)) {
    [KvEthernetIpWin32]::ShowWindow([IntPtr]$Hwnd, 9) | Out-Null
  }
  [KvEthernetIpWin32]::SetForegroundWindow([IntPtr]$Hwnd) | Out-Null
  Start-Sleep -Milliseconds 250
}

function Activate-TreeNodeByKeyboard {
  param(
    [Windows.Automation.AutomationElement]$Node,
    [string]$Label
  )
  if (-not $Node) { throw "Tree node '$Label' was not found." }
  $process = Get-KvsProcess
  Set-ForegroundWindowByHwnd -Hwnd $process.MainWindowHandle
  $pattern = $null
  if ($Node.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern, [ref]$pattern)) {
    try { $pattern.ScrollIntoView() } catch {}
  }
  $pattern = $null
  if ($Node.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
    try { $pattern.Select(); Start-Sleep -Milliseconds 150 } catch {}
  }
  $Node.SetFocus()
  Start-Sleep -Milliseconds 120
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Start-Sleep -Milliseconds 900
}

function Wait-WindowTitleLike {
  param(
    [string[]]$TitleParts,
    [int]$TimeoutMs = 5000
  )
  $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
  do {
    $windows = Get-KvRelevantWindows
    foreach ($window in $windows) {
      foreach ($part in $TitleParts) {
        if ($window.title -like "*$part*") { return $window }
      }
    }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  $null
}

function Invoke-ButtonByNamePart {
  param(
    [Windows.Automation.AutomationElement]$Root,
    [string]$NamePart,
    [long]$OwnerHwnd = 0
  )
  $button = Find-Descendant -Root $Root -Predicate {
    param($e)
    try {
      $isButton = (
        $e.Current.ControlType.ProgrammaticName -eq 'ControlType.Button' -or
        $e.Current.ClassName -eq 'Button'
      )
      $isButton -and $e.Current.IsEnabled -and $e.Current.Name -like "*$NamePart*"
    } catch {
      $false
    }
  }
  if (-not $button) { return $null }
  $pattern = $null
  if ($button.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
    $pattern.Invoke()
    Start-Sleep -Milliseconds 700
    return [pscustomobject]@{ name = $button.Current.Name; method = 'InvokePattern'; automation_id = $button.Current.AutomationId }
  }
  $nativeHwnd = 0
  try { $nativeHwnd = [int]$button.Current.NativeWindowHandle } catch {}
  if ($nativeHwnd -ne 0) {
    [void][KvEthernetIpWin32]::SendMessage([IntPtr]$nativeHwnd, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 700
    return [pscustomobject]@{ name = $button.Current.Name; method = 'BM_CLICK_native_hwnd'; automation_id = $button.Current.AutomationId; hwnd = $nativeHwnd }
  }
  $automationIdNumber = 0
  if ($OwnerHwnd -ne 0 -and [int]::TryParse([string]$button.Current.AutomationId, [ref]$automationIdNumber)) {
    $childHwnd = [KvEthernetIpWin32]::GetDlgItem([IntPtr]$OwnerHwnd, $automationIdNumber)
    if ($childHwnd -ne [IntPtr]::Zero) {
      [void][KvEthernetIpWin32]::SendMessage($childHwnd, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
      Start-Sleep -Milliseconds 700
      return [pscustomobject]@{ name = $button.Current.Name; method = 'BM_CLICK_GetDlgItem'; automation_id = $button.Current.AutomationId; hwnd = $childHwnd.ToInt64() }
    }
  }
  $null
}

function Close-NetworkWindows {
  $closed = @()
  $windows = @(Get-KvRelevantWindows | Where-Object {
    $_.title -like '*EtherNet/IP*' -or $_.title -like "*$NameAdapterInitialSetting*"
  })
  foreach ($window in $windows) {
    $element = Get-ElementFromHwnd -Hwnd $window.hwnd
    $cancel = Invoke-ButtonByNamePart -Root $element -NamePart $NameCancel -OwnerHwnd $window.hwnd
    if ($cancel) {
      $closed += [pscustomobject]@{ title = $window.title; hwnd = $window.hwnd; method = 'cancel_button'; button = $cancel }
    }
  }
  $closed
}

function Open-EtherNetIpSetting {
  $beforeWindows = @(Get-KvRelevantWindows)
  $existing = Wait-WindowTitleLike -TitleParts @('EtherNet/IP') -TimeoutMs 500
  if ($existing -and $existing.title -like '*EtherNet/IP*') {
    return [pscustomobject]@{
      reused_existing = $true
      before_windows = $beforeWindows
      tree_state = $null
      opened_window = $existing
      manual_button = $null
    }
  }

  $treeState = Ensure-UnitTreeExpanded
  $node = Find-TreeItem -Contains 'EtherNet/IP'
  if (-not $node) { throw 'EtherNet/IP node was not found under unit configuration.' }
  $nodeName = $node.Current.Name
  Activate-TreeNodeByKeyboard -Node $node -Label 'EtherNet/IP'
  $prompt = Wait-WindowTitleLike -TitleParts @('EtherNet/IP') -TimeoutMs 6000
  if (-not $prompt) { throw 'EtherNet/IP prompt/setting window did not appear.' }
  $promptElement = Get-ElementFromHwnd -Hwnd $prompt.hwnd
  $manual = Invoke-ButtonByNamePart -Root $promptElement -NamePart $NameManual -OwnerHwnd $prompt.hwnd
  Start-Sleep -Milliseconds 1200
  $setting = Wait-WindowTitleLike -TitleParts @('EtherNet/IP') -TimeoutMs 4000
  if (-not $setting) { throw 'EtherNet/IP setting window did not appear after manual setting.' }
  [pscustomobject]@{
    reused_existing = $false
    before_windows = $beforeWindows
    tree_state = $treeState
    node_name = $nodeName
    prompt_window = $prompt
    manual_button = $manual
    opened_window = $setting
  }
}

function Get-EtherNetWindowRow {
  $windowRow = Wait-WindowTitleLike -TitleParts @('EtherNet/IP') -TimeoutMs 2500
  if (-not $windowRow) { throw 'EtherNet/IP setting window was not found.' }
  $windowRow
}

function Get-DeviceListCurrentDetail {
  param([Windows.Automation.AutomationElement]$WindowElement)
  $nameElement = Find-DescendantByAutomationId -Root $WindowElement -AutomationId '698'
  $descriptionElement = Find-DescendantByAutomationId -Root $WindowElement -AutomationId '697'
  $gridElement = Find-DescendantByAutomationId -Root $WindowElement -AutomationId '604331864'
  $name = ''
  $description = ''
  $gridClass = ''
  $gridHwnd = 0
  if ($nameElement) { try { $name = $nameElement.Current.Name } catch {} }
  if ($descriptionElement) { try { $description = $descriptionElement.Current.Name } catch {} }
  if ($gridElement) {
    try { $gridClass = $gridElement.Current.ClassName } catch {}
    try { $gridHwnd = $gridElement.Current.NativeWindowHandle } catch {}
  }
  [pscustomobject]@{
    device_name = $name
    description = $description
    grid_class = $gridClass
    grid_hwnd = $gridHwnd
  }
}

function Test-DeviceMatches {
  param($Detail)
  if ($DeviceNamePattern.Contains('*') -or $DeviceNamePattern.Contains('?')) {
    $text = (($Detail.device_name, $Detail.description) -join ' ')
    return $text -like $DeviceNamePattern
  }

  foreach ($candidate in @($Detail.device_name, $Detail.description)) {
    if (-not $candidate) { continue }
    if ($candidate -eq $DeviceNamePattern) { return $true }
    if ($candidate.StartsWith($DeviceNamePattern, [System.StringComparison]::OrdinalIgnoreCase)) {
      if ($candidate.Length -eq $DeviceNamePattern.Length) { return $true }
      $next = $candidate.Substring($DeviceNamePattern.Length, 1)
      if ($next -match '[\s\[\]\(\)_\-/]') { return $true }
    }
  }
  return $false
}

function Select-EtherNetDevice {
  $windowRow = Get-EtherNetWindowRow
  $windowElement = Get-ElementFromHwnd -Hwnd $windowRow.hwnd
  Set-ForegroundWindowByHwnd -Hwnd $windowRow.hwnd
  [System.Windows.Forms.SendKeys]::SendWait('%1')
  Start-Sleep -Milliseconds 500
  [System.Windows.Forms.SendKeys]::SendWait('^{HOME}')
  Start-Sleep -Milliseconds 200
  [System.Windows.Forms.SendKeys]::SendWait('{HOME}')
  Start-Sleep -Milliseconds 400

  $records = @()
  $found = $false
  $foundAt = -1
  for ($i = 0; $i -le $MaxScanSteps; $i++) {
    $detail = Get-DeviceListCurrentDetail -WindowElement $windowElement
    $record = [pscustomobject]@{
      step_index = $i
      device_name = $detail.device_name
      description = $detail.description
      grid_class = $detail.grid_class
      grid_hwnd = $detail.grid_hwnd
      matched = (Test-DeviceMatches -Detail $detail)
    }
    $records += $record
    if ($record.matched) {
      $found = $true
      $foundAt = $i
      break
    }
    [System.Windows.Forms.SendKeys]::SendWait('{DOWN}')
    Start-Sleep -Milliseconds 45
  }
  if (-not $found) {
    throw "Device '$DeviceNamePattern' was not found in EtherNet/IP device list after $MaxScanSteps scan steps."
  }

  $selectedBeforeEnter = Get-DeviceListCurrentDetail -WindowElement $windowElement
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Start-Sleep -Milliseconds 1400

  [pscustomobject]@{
    target_pattern = $DeviceNamePattern
    found_at = $foundAt
    selected_before_enter = $selectedBeforeEnter
    records_tail = @($records | Select-Object -Last 40)
    records_count = $records.Count
    window = $windowRow
  }
}

function Get-AdapterInitialDialogRow {
  $process = Get-KvsProcess
  Get-VisibleTopWindows | Where-Object {
    $_.process_id -eq $process.Id -and $_.title -like "*$NameAdapterInitialSetting*"
  } | Select-Object -First 1
}

function Get-AdapterInitialEvidence {
  param($DialogRow)
  if (-not $DialogRow) { return $null }
  $element = Get-ElementFromHwnd -Hwnd $DialogRow.hwnd
  $elements = @(Get-ElementRows -Root $element -Limit 400)
  $node = $elements | Where-Object { $_.automation_id -eq '1998' -and $_.class_name -eq 'Edit' } | Select-Object -First 1
  $ip = $elements | Where-Object { $_.automation_id -eq '1996' -and $_.class_name -eq 'SysIPAddress32' } | Select-Object -First 1
  $ok = $elements | Where-Object { $_.automation_id -eq '1' -and $_.class_name -eq 'Button' } | Select-Object -First 1
  [pscustomobject]@{
    window = $DialogRow
    node_edit = $node
    ip_control = $ip
    ok_button = $ok
    field_matches = @($elements | Where-Object {
      $_.automation_id -in @('1998','1996','1','2') -or
      $_.name -like "*$NameNodeAddress*" -or
      $_.name -like "*$NameIpAddress*" -or
      $_.name -like '*IP*'
    })
  }
}

function ConvertTo-IpAddressParam {
  param([string]$Address)
  $parts = @($Address -split '\.' | ForEach-Object { [int]$_ })
  if ($parts.Count -ne 4) { throw "Invalid IPv4 address '$Address'." }
  foreach ($part in $parts) {
    if ($part -lt 0 -or $part -gt 255) { throw "Invalid IPv4 octet '$part' in '$Address'." }
  }
  [IntPtr](($parts[0] -shl 24) -bor ($parts[1] -shl 16) -bor ($parts[2] -shl 8) -bor $parts[3])
}

function Set-AdapterInitialValues {
  $dialog = $null
  $deadline = (Get-Date).AddMilliseconds(5000)
  do {
    $dialog = Get-AdapterInitialDialogRow
    if ($dialog) { break }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  if (-not $dialog) { throw 'Adapter initial setting dialog was not found after selecting device.' }

  $before = Get-AdapterInitialEvidence -DialogRow $dialog
  $nodeHwnd = [KvEthernetIpWin32]::GetDlgItem([IntPtr]$dialog.hwnd, 1998)
  $ipHwnd = [KvEthernetIpWin32]::GetDlgItem([IntPtr]$dialog.hwnd, 1996)
  if ($nodeHwnd -eq [IntPtr]::Zero) { throw 'Node address edit control 1998 was not found.' }
  if ($ipHwnd -eq [IntPtr]::Zero) { throw 'IP address control 1996 was not found.' }

  [void][KvEthernetIpWin32]::SendMessage($nodeHwnd, $WM_SETTEXT, [IntPtr]::Zero, $NodeAddress)
  [void][KvEthernetIpWin32]::SendMessage($ipHwnd, $IPM_SETADDRESS, [IntPtr]::Zero, (ConvertTo-IpAddressParam -Address $IpAddress))
  Start-Sleep -Milliseconds 500

  $after = Get-AdapterInitialEvidence -DialogRow $dialog
  $afterNode = ''
  $afterIp = ''
  if ($after.node_edit) { $afterNode = $after.node_edit.name }
  if ($after.ip_control) { $afterIp = $after.ip_control.name }
  if ($afterNode -ne $NodeAddress -or $afterIp -ne $IpAddress) {
    throw "Adapter values were not verified after set. node='$afterNode', ip='$afterIp'."
  }

  [pscustomobject]@{
    requested_node_address = $NodeAddress
    requested_ip_address = $IpAddress
    before = $before
    after = $after
    dialog = $dialog
  }
}

function Confirm-AdapterInitialDialog {
  $dialog = Get-AdapterInitialDialogRow
  if (-not $dialog) { throw 'Adapter initial setting dialog was not found before OK.' }
  $before = Get-AdapterInitialEvidence -DialogRow $dialog
  $okHwnd = [KvEthernetIpWin32]::GetDlgItem([IntPtr]$dialog.hwnd, 1)
  if ($okHwnd -eq [IntPtr]::Zero) { throw 'Adapter OK button was not found.' }
  [void][KvEthernetIpWin32]::SendMessage($okHwnd, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 1400
  $afterDialog = Get-AdapterInitialDialogRow
  [pscustomobject]@{
    before = $before
    after_dialog = $afterDialog
    ok = (-not [bool]$afterDialog)
    windows_after = @(Get-KvRelevantWindows)
  }
}

function Confirm-EtherNetMainWindow {
  if ($KeepWindowOpen) {
    return [pscustomobject]@{ skipped = $true; reason = 'KeepWindowOpen was specified.' }
  }
  $windowRow = Get-EtherNetWindowRow
  $element = Get-ElementFromHwnd -Hwnd $windowRow.hwnd
  $beforeDevice = Get-DeviceListCurrentDetail -WindowElement $element
  $okButton = Invoke-ButtonByNamePart -Root $element -NamePart 'OK' -OwnerHwnd $windowRow.hwnd
  if (-not $okButton) { throw 'EtherNet/IP main OK button was not found.' }
  Start-Sleep -Milliseconds 1500
  $afterWindows = @(Get-KvRelevantWindows)
  $stillOpen = @($afterWindows | Where-Object { $_.title -like '*EtherNet/IP*' })
  [pscustomobject]@{
    target_window = $windowRow
    before_device = $beforeDevice
    ok_button = $okButton
    after_windows = $afterWindows
    still_open = $stillOpen
    ok = ($stillOpen.Count -eq 0)
  }
}

function Wait-TopWindow {
  param(
    [scriptblock]$Predicate,
    [int]$TimeoutMs = 10000
  )
  $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
  do {
    foreach ($window in @(Get-KvRelevantWindows)) {
      if (& $Predicate $window) { return $window }
    }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  $null
}

function Get-UnitEditorWindowRow {
  Wait-TopWindow -TimeoutMs 8000 -Predicate {
    param($window)
    $window.title -like $NameUnitEditor -and $window.class_name -like 'Afx:*'
  }
}

function Invoke-UnitEditorOk {
  $unitEditor = Get-UnitEditorWindowRow
  if (-not $unitEditor) {
    throw 'Unit editor window was not found after EtherNet/IP main OK.'
  }
  $children = @(Get-ChildWindowRows -ParentHwnd $unitEditor.hwnd)
  $ok = $children |
    Where-Object { $_.visible -and $_.enabled -and $_.class_name -eq 'Button' -and $_.title -eq 'OK' } |
    Select-Object -First 1
  if (-not $ok) {
    throw 'Unit editor OK button was not found.'
  }
  [void][KvEthernetIpWin32]::PostMessage([IntPtr]$ok.hwnd, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 800
  [pscustomobject]@{
    window = $unitEditor
    ok_button = $ok
    method = 'PostMessage_BM_CLICK'
  }
}

function Wait-KvStudioMessageDialog {
  param([int]$TimeoutMs = 15000)
  Wait-TopWindow -TimeoutMs $TimeoutMs -Predicate {
    param($window)
    if ($window.title -ne 'KV STUDIO' -or $window.class_name -ne '#32770') { return $false }
    $children = @(Get-ChildWindowRows -ParentHwnd $window.hwnd)
    return [bool]($children | Where-Object { $_.visible -and $_.class_name -eq 'Button' -and $_.title -eq $NameOkCn } | Select-Object -First 1)
  }
}

function Confirm-KvStudioMessageDialog {
  param([string]$Phase)
  $dialog = Wait-KvStudioMessageDialog -TimeoutMs 20000
  if (-not $dialog) {
    throw "KV STUDIO message dialog was not found for phase '$Phase'."
  }
  $children = @(Get-ChildWindowRows -ParentHwnd $dialog.hwnd)
  $text = @($children | Where-Object { $_.class_name -eq 'Static' -and $_.title } | ForEach-Object { $_.title })
  $button = Invoke-ChildButtonByTitle -ParentHwnd $dialog.hwnd -Title $NameOkCn
  if (-not $button) {
    throw "KV STUDIO message dialog OK button could not be clicked for phase '$Phase'."
  }
  [pscustomobject]@{
    phase = $Phase
    dialog = $dialog
    text = $text
    ok_button = $button
  }
}

function Get-EtherNetVariableDialogRow {
  Wait-TopWindow -TimeoutMs 12000 -Predicate {
    param($window)
    $window.title -like '*EtherNet/IP*' -and $window.title -like "*$NameVariable*"
  }
}

function Get-DefaultVariableNames {
  if ($VariableNames -and $VariableNames.Count -gt 0) { return @($VariableNames) }
  $prefix = $VariableNamePrefix
  if (-not $prefix) {
    $nodeNumber = 0
    if ([int]::TryParse($NodeAddress, [ref]$nodeNumber)) {
      $prefix = 'eip_n{0:000}' -f $nodeNumber
    } else {
      $safeNode = ($NodeAddress -replace '[^A-Za-z0-9_]', '_').Trim('_')
      if (-not $safeNode) { $safeNode = 'node' }
      $prefix = "eip_$safeNode"
    }
  }
  $prefix = ($prefix -replace '[^A-Za-z0-9_]', '_').Trim('_')
  if (-not $prefix) { $prefix = 'eip_node' }
  @("${prefix}_in100", "${prefix}_out101")
}

function Set-EtherNetVariableDialogNames {
  $dialog = Get-EtherNetVariableDialogRow
  if (-not $dialog) {
    return [pscustomobject]@{ skipped = $true; reason = 'EtherNet/IP variable setting dialog did not appear.' }
  }
  $children = @(Get-ChildWindowRows -ParentHwnd $dialog.hwnd)
  $grid = $children |
    Where-Object { $_.visible -and $_.class_name -like 'WindowsForms10.Window.*' } |
    Select-Object -First 1
  $okButton = $children |
    Where-Object { $_.visible -and $_.class_name -like 'WindowsForms10.Button*' -and $_.title -eq 'OK' } |
    Select-Object -First 1
  if (-not $grid) { throw 'EtherNet/IP variable setting grid was not found.' }
  if (-not $okButton) { throw 'EtherNet/IP variable setting OK button was not found.' }

  $names = @(Get-DefaultVariableNames)
  if ($names.Count -lt 1) { throw 'No variable names were provided or generated.' }
  Set-ForegroundWindowByHwnd -Hwnd $dialog.hwnd
  [void][KvEthernetIpWin32]::SetFocus([IntPtr]$grid.hwnd)
  Start-Sleep -Milliseconds 200
  [System.Windows.Forms.SendKeys]::SendWait('^{HOME}')
  Start-Sleep -Milliseconds 120
  [System.Windows.Forms.SendKeys]::SendWait('{HOME}')
  Start-Sleep -Milliseconds 120
  [System.Windows.Forms.SendKeys]::SendWait('{RIGHT}{RIGHT}{RIGHT}{RIGHT}{RIGHT}')
  Start-Sleep -Milliseconds 120

  $typed = @()
  for ($i = 0; $i -lt $names.Count; $i++) {
    $name = ($names[$i] -replace '[^A-Za-z0-9_]', '_').Trim('_')
    if (-not $name) { throw "Variable name at index $i is empty after sanitization." }
    if ($name[0] -match '[0-9]') { $name = "v_$name" }
    [System.Windows.Forms.SendKeys]::SendWait($name)
    Start-Sleep -Milliseconds 120
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Start-Sleep -Milliseconds 160
    $typed += $name
    if ($i -lt ($names.Count - 1)) {
      [System.Windows.Forms.SendKeys]::SendWait('{DOWN}')
      Start-Sleep -Milliseconds 120
    }
  }

  if (-not [KvEthernetIpWin32]::IsWindowEnabled([IntPtr]$okButton.hwnd)) {
    throw 'EtherNet/IP variable setting OK button is still disabled after typing variable names.'
  }
  [void][KvEthernetIpWin32]::PostMessage([IntPtr]$okButton.hwnd, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 1000

  [pscustomobject]@{
    skipped = $false
    dialog = $dialog
    grid = $grid
    ok_button = $okButton
    typed_variable_names = $typed
  }
}

function Complete-UnitEditorEtherNetApply {
  if ($KeepWindowOpen) {
    return [pscustomobject]@{ skipped = $true; reason = 'KeepWindowOpen was specified.' }
  }
  $beforeWindows = @(Get-KvRelevantWindows)
  $unitOk = Invoke-UnitEditorOk
  $deviceUpdatedDialog = Confirm-KvStudioMessageDialog -Phase 'ethernet_device_updated'
  $variableDialog = Set-EtherNetVariableDialogNames
  $variablesRegisteredDialog = $null
  if (-not $variableDialog.skipped) {
    $variablesRegisteredDialog = Confirm-KvStudioMessageDialog -Phase 'ethernet_variables_registered'
  }
  Start-Sleep -Milliseconds 1500
  $afterWindows = @(Get-KvRelevantWindows)
  $remainingVariableDialogs = @($afterWindows | Where-Object { $_.title -like '*EtherNet/IP*' -and $_.title -like "*$NameVariable*" })
  $remainingKvDialogs = @($afterWindows | Where-Object { $_.title -eq 'KV STUDIO' -and $_.class_name -eq '#32770' })
  [pscustomobject]@{
    skipped = $false
    before_windows = $beforeWindows
    unit_editor_ok = $unitOk
    device_updated_dialog = $deviceUpdatedDialog
    variable_dialog = $variableDialog
    variables_registered_dialog = $variablesRegisteredDialog
    after_windows = $afterWindows
    remaining_variable_dialogs = $remainingVariableDialogs
    remaining_kv_dialogs = $remainingKvDialogs
    ok = ($remainingVariableDialogs.Count -eq 0 -and $remainingKvDialogs.Count -eq 0)
  }
}

$evidencePath = New-EvidencePath -Name 'configure_kv_ethernet_ip_device'
$result = [ordered]@{
  ok = $false
  script = 'configure_kv_ethernet_ip_device.ps1'
  project_name = $ProjectName
  requested_device_name_pattern = $DeviceNamePattern
  requested_node_address = $NodeAddress
  requested_ip_address = $IpAddress
  started_at = (Get-Date).ToString('o')
  phases = [ordered]@{}
  evidence_path = $evidencePath
}

try {
  $result.phases.before_windows = @(Get-KvRelevantWindows)
  $result.phases.closed_windows = @(Close-NetworkWindows)
  $result.phases.open_ethernet = Open-EtherNetIpSetting
  $result.phases.select_device = Select-EtherNetDevice
  $result.phases.set_adapter_values = Set-AdapterInitialValues
  $result.phases.adapter_ok = Confirm-AdapterInitialDialog
  if (-not $result.phases.adapter_ok.ok) {
    throw 'Adapter initial dialog did not close after OK.'
  }
  $result.phases.main_ok = Confirm-EtherNetMainWindow
  if (-not $KeepWindowOpen -and -not $result.phases.main_ok.ok) {
    throw 'EtherNet/IP setting window did not close after main OK.'
  }
  $result.phases.unit_editor_apply = Complete-UnitEditorEtherNetApply
  if (-not $KeepWindowOpen -and -not $result.phases.unit_editor_apply.ok) {
    throw 'Unit editor EtherNet/IP apply did not complete cleanly.'
  }
  $result.ok = $true
} catch {
  $result.error = $_.Exception.Message
  $result.windows_on_error = @(Get-KvRelevantWindows)
  Write-JsonFile -Path $evidencePath -Value $result
  Write-Error "configure_kv_ethernet_ip_device failed; evidence: $evidencePath; error: $($_.Exception.Message)"
  exit 61
}

$result.finished_at = (Get-Date).ToString('o')
Write-JsonFile -Path $evidencePath -Value $result
Write-Host "OK: configured EtherNet/IP device '$DeviceNamePattern' node=$NodeAddress ip=$IpAddress evidence=$evidencePath"
