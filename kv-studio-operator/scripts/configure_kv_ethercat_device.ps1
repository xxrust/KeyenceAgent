param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectName,
  [string[]]$DevicePath = @('KEYENCE CORPORATION','Servo Drives','SV3'),
  [string]$EsiPath = '',
  [string]$BatchAxisRegistration = 'No',
  [string]$OutDir = '',
  [switch]$KeepWindowOpen
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $OutDir = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'kv-studio-operator') 'kv_network_config_runs'
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms,System.Drawing

if (-not ('KvEtherCatWin32' -as [type])) {
  Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class KvEtherCatWin32 {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr hDlg, int nIDDlgItem);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
"@
}

$BM_CLICK = 0x00F5
$NameUnitConfiguration = -join ([char[]](0x5355,0x5143,0x914D,0x7F6E))
$NameCpuUnit = '[0]  KV-X310'
$NameManual = -join ([char[]](0x624B,0x52A8))
$NameCancel = -join ([char[]](0x53D6,0x6D88))
$NameConfirm = -join ([char[]](0x786E,0x5B9A))
$NameYes = (-join ([char[]](0x662F))) + '(Y)'
$NameNo = (-join ([char[]](0x5426))) + '(N)'
$NameEtherCat = 'EtherCAT'
$NameUnitEditor = (-join ([char[]](0x5355,0x5143,0x7F16,0x8F91,0x5668))) + '*'
$TextBatchAxisRegistration = -join ([char[]](0x6279,0x91CF,0x767B,0x5F55,0x8F74))

function New-EvidencePath {
  param([string]$Name)
  $stamp = Get-Date -Format 'yyyyMMdd_HHmmss_fff'
  Join-Path $OutDir ("{0}_{1}.json" -f $stamp, $Name)
}

function Write-JsonFile {
  param([string]$Path, $Value)
  $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Save-Screenshot {
  param([string]$Name)
  $path = Join-Path $OutDir $Name
  $bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = [Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
  $bitmap.Save($path)
  $graphics.Dispose()
  $bitmap.Dispose()
  $path
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
  $callback = [KvEtherCatWin32+EnumWindowsProc]{
    param($handle, $lParam)
    if ([KvEtherCatWin32]::IsWindowVisible($handle)) {
      $titleBuilder = [Text.StringBuilder]::new(512)
      $classBuilder = [Text.StringBuilder]::new(256)
      [void][KvEtherCatWin32]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity)
      [void][KvEtherCatWin32]::GetClassName($handle, $classBuilder, $classBuilder.Capacity)
      $procIdValue = [uint32]0
      [void][KvEtherCatWin32]::GetWindowThreadProcessId($handle, [ref]$procIdValue)
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
  [void][KvEtherCatWin32]::EnumWindows($callback, [IntPtr]::Zero)
  @($rows)
}

function Get-KvRelevantWindows {
  $process = Get-KvsProcess
  Get-VisibleTopWindows | Where-Object {
    $_.process_id -eq $process.Id -and (
      $_.title -like 'KV STUDIO*' -or
      $_.title -like $NameUnitEditor -or
      $_.title -like '*EtherCAT*' -or
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
  param([Windows.Automation.AutomationElement]$Root, [int]$Limit = 700)
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

function Find-Descendant {
  param([Windows.Automation.AutomationElement]$Root, [scriptblock]$Predicate)
  $all = $Root.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
  for ($i = 0; $i -lt $all.Count; $i++) {
    $e = $all.Item($i)
    if (& $Predicate $e) { return $e }
  }
  $null
}

function Find-TreeItemInMain {
  param([string]$Exact = '', [string]$Contains = '')
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
  param([Windows.Automation.AutomationElement]$Item, [string]$Label)
  if (-not $Item) { throw "Tree item '$Label' was not found." }
  $pattern = $null
  if ($Item.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern, [ref]$pattern)) {
    try { $pattern.ScrollIntoView() } catch {}
  }
  $pattern = $null
  if ($Item.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
    try { $pattern.Select(); Start-Sleep -Milliseconds 100 } catch {}
  }
  $pattern = $null
  if (-not $Item.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$pattern)) {
    return 'NoExpandCollapsePattern'
  }
  if ($pattern.Current.ExpandCollapseState -ne [Windows.Automation.ExpandCollapseState]::Expanded) {
    $pattern.Expand()
    Start-Sleep -Milliseconds 350
  }
  $pattern.Current.ExpandCollapseState.ToString()
}

function Ensure-UnitTreeExpanded {
  $unit = Find-TreeItemInMain -Exact $NameUnitConfiguration
  $unitState = Expand-TreeItem -Item $unit -Label 'unit configuration'
  $cpu = Find-TreeItemInMain -Exact $NameCpuUnit
  if (-not $cpu) { $cpu = Find-TreeItemInMain -Contains 'KV-X310' }
  $cpuState = Expand-TreeItem -Item $cpu -Label 'CPU unit'
  [pscustomobject]@{ unit_state = $unitState; cpu_state = $cpuState }
}

function Set-ForegroundWindowByHwnd {
  param([long]$Hwnd)
  if ([KvEtherCatWin32]::IsIconic([IntPtr]$Hwnd)) {
    [KvEtherCatWin32]::ShowWindow([IntPtr]$Hwnd, 9) | Out-Null
  }
  [KvEtherCatWin32]::SetForegroundWindow([IntPtr]$Hwnd) | Out-Null
  Start-Sleep -Milliseconds 250
}

function Send-EnterToElement {
  param([Windows.Automation.AutomationElement]$Element)
  $pattern = $null
  if ($Element.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern, [ref]$pattern)) {
    try { $pattern.ScrollIntoView() } catch {}
  }
  $pattern = $null
  if ($Element.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
    try { $pattern.Select(); Start-Sleep -Milliseconds 150 } catch {}
  }
  $Element.SetFocus()
  Start-Sleep -Milliseconds 150
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Start-Sleep -Milliseconds 900
}

function Wait-WindowTitleLike {
  param([string[]]$TitleParts, [int]$TimeoutMs = 5000)
  $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
  do {
    foreach ($window in @(Get-KvRelevantWindows)) {
      foreach ($part in $TitleParts) {
        if ($part -eq $NameEtherCat -and $window.title -like 'KV STUDIO*') { continue }
        if ($window.title -like "*$part*") { return $window }
      }
    }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  $null
}

function Invoke-ButtonByNamePart {
  param([Windows.Automation.AutomationElement]$Root, [string]$NamePart, [long]$OwnerHwnd = 0)
  $button = Find-Descendant -Root $Root -Predicate {
    param($e)
    try {
      $isButton = ($e.Current.ControlType.ProgrammaticName -eq 'ControlType.Button' -or $e.Current.ClassName -eq 'Button')
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
    [void][KvEtherCatWin32]::SendMessage([IntPtr]$nativeHwnd, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
    Start-Sleep -Milliseconds 700
    return [pscustomobject]@{ name = $button.Current.Name; method = 'BM_CLICK_native_hwnd'; automation_id = $button.Current.AutomationId; hwnd = $nativeHwnd }
  }
  $automationIdNumber = 0
  if ($OwnerHwnd -ne 0 -and [int]::TryParse([string]$button.Current.AutomationId, [ref]$automationIdNumber)) {
    $childHwnd = [KvEtherCatWin32]::GetDlgItem([IntPtr]$OwnerHwnd, $automationIdNumber)
    if ($childHwnd -ne [IntPtr]::Zero) {
      [void][KvEtherCatWin32]::SendMessage($childHwnd, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
      Start-Sleep -Milliseconds 700
      return [pscustomobject]@{ name = $button.Current.Name; method = 'BM_CLICK_GetDlgItem'; automation_id = $button.Current.AutomationId; hwnd = $childHwnd.ToInt64() }
    }
  }
  $null
}

function Open-EtherCatSetting {
  $existing = Wait-WindowTitleLike -TitleParts @($NameEtherCat) -TimeoutMs 500
  if ($existing -and $existing.title -like '*EtherCAT*') {
    return [pscustomobject]@{ reused_existing = $true; opened_window = $existing }
  }
  $treeState = Ensure-UnitTreeExpanded
  $node = Find-TreeItemInMain -Exact 'EtherCAT'
  if (-not $node) { $node = Find-TreeItemInMain -Contains 'EtherCAT' }
  if (-not $node) { throw 'EtherCAT node was not found under unit configuration.' }
  $process = Get-KvsProcess
  Set-ForegroundWindowByHwnd -Hwnd $process.MainWindowHandle
  Send-EnterToElement -Element $node
  $prompt = Wait-WindowTitleLike -TitleParts @($NameEtherCat) -TimeoutMs 6000
  if (-not $prompt) { throw 'EtherCAT prompt/setting window did not appear.' }
  $promptElement = Get-ElementFromHwnd -Hwnd $prompt.hwnd
  $manual = Invoke-ButtonByNamePart -Root $promptElement -NamePart $NameManual -OwnerHwnd $prompt.hwnd
  Start-Sleep -Milliseconds 1200
  $setting = Wait-WindowTitleLike -TitleParts @($NameEtherCat) -TimeoutMs 4000
  if (-not $setting) { throw 'EtherCAT setting window did not appear after manual setting.' }
  [pscustomobject]@{
    reused_existing = $false
    tree_state = $treeState
    node_name = $node.Current.Name
    prompt_window = $prompt
    manual_button = $manual
    opened_window = $setting
  }
}

function Get-EtherCatWindowRow {
  $row = Wait-WindowTitleLike -TitleParts @($NameEtherCat) -TimeoutMs 2500
  if (-not $row) { throw 'EtherCAT setting window was not found.' }
  $row
}

function Find-DeviceTreeItem {
  param([Windows.Automation.AutomationElement]$WindowElement, [string]$Name, [switch]$Leaf)
  Find-Descendant -Root $WindowElement -Predicate {
    param($e)
    try {
      if ($e.Current.ControlType.ProgrammaticName -ne 'ControlType.TreeItem') { return $false }
      $currentName = $e.Current.Name
      if ($Leaf) { return $currentName -like "$Name*" }
      return $currentName -eq $Name
    } catch {
      $false
    }
  }
}

function Select-EtherCatDeviceByPath {
  $windowRow = Get-EtherCatWindowRow
  $windowElement = Get-ElementFromHwnd -Hwnd $windowRow.hwnd
  Set-ForegroundWindowByHwnd -Hwnd $windowRow.hwnd
  $expanded = @()
  for ($i = 0; $i -lt ($DevicePath.Count - 1); $i++) {
    $name = [string]$DevicePath[$i]
    $item = Find-DeviceTreeItem -WindowElement $windowElement -Name $name
    if (-not $item) { throw "EtherCAT device path segment not found: $name" }
    $state = Expand-TreeItem -Item $item -Label $name
    $expanded += [pscustomobject]@{ name = $name; state = $state }
    Start-Sleep -Milliseconds 250
  }
  $leafName = [string]$DevicePath[$DevicePath.Count - 1]
  $leaf = Find-DeviceTreeItem -WindowElement $windowElement -Name $leafName -Leaf
  if (-not $leaf) { throw "EtherCAT device leaf not found: $leafName" }
  $beforeScreenshot = Save-Screenshot '01_before_device_enter.png'
  Send-EnterToElement -Element $leaf
  Start-Sleep -Milliseconds 900
  $afterScreenshot = Save-Screenshot '02_after_device_enter.png'
  [pscustomobject]@{
    window = $windowRow
    expanded = $expanded
    selected_leaf = $leaf.Current.Name
    before_screenshot = $beforeScreenshot
    after_screenshot = $afterScreenshot
    after_elements = @(Get-ElementRows -Root $windowElement -Limit 900 | Where-Object {
      $_.name -like "*$leafName*" -or
      $_.name -like '*项目的网络结构*' -or
      $_.name -like '*设备列表*' -or
      $_.automation_id -in @('_projectTree','_treeView','_lblProductName')
    })
  }
}

function Invoke-EtherCatMainOk {
  $windowRow = Get-EtherCatWindowRow
  $element = Get-ElementFromHwnd -Hwnd $windowRow.hwnd
  $before = @(Get-ElementRows -Root $element -Limit 900)
  $okButton = Invoke-ButtonByNamePart -Root $element -NamePart 'OK' -OwnerHwnd $windowRow.hwnd
  if (-not $okButton) { throw 'EtherCAT OK button was not found.' }
  Start-Sleep -Milliseconds 1500
  [pscustomobject]@{
    target_window = $windowRow
    ok_button = $okButton
    before_button_rows = @($before | Where-Object { $_.name -like '*OK*' -or $_.name -like "*$NameCancel*" -or $_.class_name -eq 'Button' })
    after_windows = @(Get-KvRelevantWindows)
  }
}

function Get-DialogText {
  param([Windows.Automation.AutomationElement]$Dialog)
  $rows = @(Get-ElementRows -Root $Dialog -Limit 120)
  ($rows | ForEach-Object { $_.name } | Where-Object { $_ }) -join ' '
}

function Invoke-DialogButton {
  param([Windows.Automation.AutomationElement]$Dialog, [string[]]$NameParts)
  foreach ($part in $NameParts) {
    $clicked = Invoke-ButtonByNamePart -Root $Dialog -NamePart $part -OwnerHwnd $Dialog.Current.NativeWindowHandle
    if ($clicked) { return $clicked }
  }
  $null
}

function Handle-PostOkDialogs {
  $handled = @()
  $deadline = (Get-Date).AddSeconds(10)
  do {
    $dialogRow = @(Get-KvRelevantWindows | Where-Object { $_.class_name -eq '#32770' -and $_.title -eq 'KV STUDIO' } | Select-Object -First 1)
    if ($dialogRow.Count -eq 0) {
      Start-Sleep -Milliseconds 200
      if ((Get-Date) -gt $deadline) { break }
      continue
    }
    $dialog = Get-ElementFromHwnd -Hwnd $dialogRow[0].hwnd
    $text = Get-DialogText -Dialog $dialog
    $button = $null
    if ($text -like '*Universal Library*' -or $text -like '*KEYENCE_SV3*') {
      $button = Invoke-DialogButton -Dialog $dialog -NameParts @($NameConfirm, 'OK')
    } elseif ($text -like "*$TextBatchAxisRegistration*") {
      if ($BatchAxisRegistration -eq 'Yes') {
        $button = Invoke-DialogButton -Dialog $dialog -NameParts @($NameYes, 'Yes')
      } else {
        $button = Invoke-DialogButton -Dialog $dialog -NameParts @($NameNo, 'No')
      }
    } else {
      $button = Invoke-DialogButton -Dialog $dialog -NameParts @($NameConfirm, 'OK')
    }
    if (-not $button) { throw "Post EtherCAT OK dialog could not be handled: $text" }
    $handled += [pscustomobject]@{
      hwnd = $dialogRow[0].hwnd
      text = $text
      button = $button
    }
    Start-Sleep -Milliseconds 1200
  } while ((Get-Date) -lt $deadline)
  $handled
}

function Save-Project {
  $process = Get-KvsProcess
  Set-ForegroundWindowByHwnd -Hwnd $process.MainWindowHandle
  [System.Windows.Forms.SendKeys]::SendWait('^s')
  Start-Sleep -Milliseconds 1200
  (Get-KvsProcess).MainWindowTitle
}

try {
  $normalizedDevicePath = @()
  foreach ($item in @($DevicePath)) {
    foreach ($part in ([string]$item -split ',')) {
      $trimmed = $part.Trim()
      if ($trimmed) { $normalizedDevicePath += $trimmed }
    }
  }
  $DevicePath = $normalizedDevicePath
  if ($DevicePath.Count -eq 0) { throw 'DevicePath must contain at least one tree item name.' }
  if (-not [string]::IsNullOrWhiteSpace($EsiPath)) {
    throw 'KV_ETHERCAT_ESI_REGISTRATION_UNSTABLE: ESI file registration is not accepted as a stable script route yet. Register the ESI file before running this device-add script, or continue route breakthrough in a disposable project.'
  }
  if ($BatchAxisRegistration -notin @('Yes','No')) { throw "BatchAxisRegistration must be Yes or No." }
  $beforeWindows = @(Get-KvRelevantWindows)
  $open = Open-EtherCatSetting
  $esiRegistration = $null
  $device = Select-EtherCatDeviceByPath
  $mainOk = $null
  $dialogs = @()
  $savedTitle = ''
  if (-not $KeepWindowOpen) {
    $mainOk = Invoke-EtherCatMainOk
    $dialogs = @(Handle-PostOkDialogs)
    $savedTitle = Save-Project
  }
  $afterWindows = @(Get-KvRelevantWindows)
  $result = [pscustomobject]@{
    ok = $true
    project_name = $ProjectName
    route = 'unit_configuration_ethercat_manual_device_tree_enter'
    device_path = $DevicePath
    esi_path = $EsiPath
    batch_axis_registration = $BatchAxisRegistration
    before_windows = $beforeWindows
    open = $open
    esi_registration = $esiRegistration
    device = $device
    main_ok = $mainOk
    post_ok_dialogs = $dialogs
    saved_title = $savedTitle
    after_windows = $afterWindows
    remaining_ethercat_windows = @($afterWindows | Where-Object { $_.title -like '*EtherCAT*' -and $_.title -notlike 'KV STUDIO*' })
    remaining_dialogs = @($afterWindows | Where-Object { $_.class_name -eq '#32770' })
  }
  if (-not $KeepWindowOpen -and ($result.remaining_ethercat_windows.Count -gt 0 -or $result.remaining_dialogs.Count -gt 0)) {
    $result.ok = $false
  }
  $path = New-EvidencePath 'configure_kv_ethercat_device'
  Write-JsonFile -Path $path -Value $result
  $result | Add-Member -NotePropertyName result_path -NotePropertyValue $path
  $result | ConvertTo-Json -Depth 16
  if (-not $result.ok) { exit 62 }
} catch {
  $path = New-EvidencePath 'configure_kv_ethercat_device_failed'
  $failure = [pscustomobject]@{
    ok = $false
    error = $_.Exception.ToString()
    project_name = $ProjectName
    device_path = $DevicePath
    windows = @(try { Get-KvRelevantWindows } catch { @() })
  }
  Write-JsonFile -Path $path -Value $failure
  $failure | ConvertTo-Json -Depth 10
  exit 1
}
