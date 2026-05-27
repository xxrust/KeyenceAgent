param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [Parameter(Mandatory=$true)]
  [string]$GlobalVariablesTsv,

  [Parameter(Mandatory=$true)]
  [string]$LocalVariablesTsv,

  [string]$LocalProgramName = 'TrafficLight_MVP',

  [switch]$SkipGlobal,
  [switch]$KeepVariableEditorOpen,

  [string]$ChecklistPath = '',

  [string]$OutDir = ('E:\personal_project\rust_plc\out\traffic_light_min_loop_20260525\validation\set_variables_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$checklistGuard = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'assert_kv_operation_checklist.ps1'
if (-not (Test-Path -LiteralPath $checklistGuard)) { throw "Checklist guard script not found: $checklistGuard" }
& $checklistGuard -ChecklistPath $ChecklistPath -SearchRoots @($OutDir, $ProjectPath, $GlobalVariablesTsv, $LocalVariablesTsv) -OperationName 'set KV STUDIO variables' | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KvSetVarWin32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern short GetKeyState(int nVirtKey);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, int dwFlags, int dwExtraInfo);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
}
"@

function Log([string]$Message) {
  Add-Content -LiteralPath (Join-Path $OutDir 'run.log') -Value ((Get-Date -Format s) + ' ' + $Message) -Encoding UTF8
}

function Get-VisibleKvsProcess {
  Get-Process Kvs -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Sort-Object StartTime -Descending |
    Select-Object -First 1
}

function Get-ForegroundTitle {
  $hwnd = [KvSetVarWin32]::GetForegroundWindow()
  $builder = New-Object System.Text.StringBuilder 512
  [void][KvSetVarWin32]::GetWindowText($hwnd, $builder, $builder.Capacity)
  [pscustomobject]@{ Hwnd = $hwnd; Title = $builder.ToString() }
}

function Send-VkTap([byte]$Vk) {
  [KvSetVarWin32]::keybd_event($Vk, 0, 0, 0)
  Start-Sleep -Milliseconds 35
  [KvSetVarWin32]::keybd_event($Vk, 0, 2, 0)
  Start-Sleep -Milliseconds 70
}

function Send-AltLetter([byte]$Vk) {
  [KvSetVarWin32]::keybd_event(0x12, 0, 0, 0)
  Start-Sleep -Milliseconds 35
  [KvSetVarWin32]::keybd_event($Vk, 0, 0, 0)
  Start-Sleep -Milliseconds 35
  [KvSetVarWin32]::keybd_event($Vk, 0, 2, 0)
  Start-Sleep -Milliseconds 35
  [KvSetVarWin32]::keybd_event(0x12, 0, 2, 0)
  Start-Sleep -Milliseconds 100
}

function Test-CapsLockOn {
  (([KvSetVarWin32]::GetKeyState(0x14) -band 1) -ne 0)
}

function Set-CapsLockState([bool]$Enabled) {
  $current = Test-CapsLockOn
  Log "CapsLock before accelerator normalization=$current"
  if ($current -ne $Enabled) {
    Send-VkTap 0x14
    Start-Sleep -Milliseconds 80
  }
  $after = Test-CapsLockOn
  Log "CapsLock after accelerator normalization=$after"
  if ($after -ne $Enabled) { throw "Failed to set CapsLock state to $Enabled" }
}

function Restore-KvForeground([System.Diagnostics.Process]$Process, [string]$ProjectNeedle, [string]$Action) {
  $shell = New-Object -ComObject WScript.Shell
  [KvSetVarWin32]::ShowWindow($Process.MainWindowHandle, 3) | Out-Null
  for ($i = 1; $i -le 10; $i++) {
    if ([KvSetVarWin32]::IsIconic($Process.MainWindowHandle)) {
      [KvSetVarWin32]::ShowWindow($Process.MainWindowHandle, 9) | Out-Null
    }
    [void]$shell.AppActivate($Process.Id)
    [KvSetVarWin32]::SetForegroundWindow($Process.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 100
    $fg = Get-ForegroundTitle
    Log "foreground ${Action}: try=$i title=$($fg.Title)"
    if ($fg.Title -like 'KV STUDIO*' -and $fg.Title -like "*$ProjectNeedle*" -and -not [KvSetVarWin32]::IsIconic($Process.MainWindowHandle)) {
      return
    }
  }
  throw "KV STUDIO not foreground for ${Action}."
}

function Get-Root {
  [System.Windows.Automation.AutomationElement]::RootElement
}

function Find-ByPidAid([int]$ProcessIdValue, [string]$AutomationId) {
  (Get-Root).FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.AndCondition(
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessIdValue)),
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $AutomationId))
    ))
  )
}

function Find-DescByAid($RootElement, [string]$AutomationId) {
  $RootElement.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $AutomationId))
  )
}

function Find-TabItemByName($TabControl, [string]$Name) {
  $items = $TabControl.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  for ($i = 0; $i -lt $items.Count; $i++) {
    $item = $items.Item($i)
    if ([string]$item.Current.Name -eq $Name -and [string]$item.Current.ControlType.ProgrammaticName -eq 'ControlType.TabItem') {
      return $item
    }
  }
  return $null
}

function Find-TabItemByAutomationId($TabControl, [string]$AutomationId) {
  $items = $TabControl.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  for ($i = 0; $i -lt $items.Count; $i++) {
    $item = $items.Item($i)
    if ([string]$item.Current.AutomationId -eq $AutomationId -and [string]$item.Current.ControlType.ProgrammaticName -eq 'ControlType.TabItem') {
      return $item
    }
  }
  return $null
}

function Find-TabItemByAutomationIdOrName($RootElement, [string]$AutomationId, [string[]]$FallbackNames) {
  $items = $RootElement.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  for ($i = 0; $i -lt $items.Count; $i++) {
    $item = $items.Item($i)
    if ([string]$item.Current.ControlType.ProgrammaticName -ne 'ControlType.TabItem') { continue }
    if ([string]$item.Current.AutomationId -eq $AutomationId) { return $item }
  }
  for ($i = 0; $i -lt $items.Count; $i++) {
    $item = $items.Item($i)
    if ([string]$item.Current.ControlType.ProgrammaticName -ne 'ControlType.TabItem') { continue }
    $name = [string]$item.Current.Name
    if ($FallbackNames -contains $name) { return $item }
  }
  return $null
}

function Write-VariableFormDump($Form, [string]$Name) {
  try {
    if (-not $Form) { return }
    function Convert-RectNumber($Value) {
      if ([double]::IsInfinity([double]$Value) -or [double]::IsNaN([double]$Value)) { return $null }
      return [int]$Value
    }
    $items = $Form.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    $rows = @()
    for ($i = 0; $i -lt $items.Count; $i++) {
      $item = $items.Item($i)
      $rect = $item.Current.BoundingRectangle
      $rows += [pscustomobject]@{
        idx = $i
        name = [string]$item.Current.Name
        automation_id = [string]$item.Current.AutomationId
        control_type = [string]$item.Current.ControlType.ProgrammaticName
        class_name = [string]$item.Current.ClassName
        is_offscreen = [bool]$item.Current.IsOffscreen
        is_enabled = [bool]$item.Current.IsEnabled
        x = Convert-RectNumber $rect.X
        y = Convert-RectNumber $rect.Y
        width = Convert-RectNumber $rect.Width
        height = Convert-RectNumber $rect.Height
      }
    }
    $path = Join-Path $OutDir $Name
    $rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $path -Encoding UTF8
    Log "wrote variable form UIA dump $Name items=$($items.Count)"
  } catch {
    Log "failed to write variable form UIA dump ${Name}: $($_.Exception.Message)"
  }
}

function Find-PagePaneByAutomationId($Form, [string]$AutomationId) {
  $items = $Form.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  for ($i = 0; $i -lt $items.Count; $i++) {
    $item = $items.Item($i)
    if ([string]$item.Current.AutomationId -eq $AutomationId -and [string]$item.Current.ControlType.ProgrammaticName -eq 'ControlType.Pane' -and -not $item.Current.IsOffscreen) {
      return $item
    }
  }
  return $null
}

function Find-VariablePagePane($Form, [string]$TabAid) {
  $aids = @($TabAid)
  if ($TabAid -eq '_tabPageGlobal') {
    $aids += @('_kvVariableGlobalControl')
  } elseif ($TabAid -eq '_tabPageLocal') {
    $aids += @('_kvVariableLocalControl')
  }
  foreach ($aid in $aids) {
    $page = Find-PagePaneByAutomationId $Form $aid
    if ($page) { return $page }
  }
  return $null
}

function Test-VariablePageSelected($Form, [string]$TabAid) {
  $page = Find-VariablePagePane $Form $TabAid
  if ($page) { return $true }
  if ($TabAid -eq '_tabPageGlobal') {
    return [bool](Find-DescByAid $Form '_labelGroupFilter')
  }
  if ($TabAid -eq '_tabPageLocal') {
    return [bool](Find-DescByAid $Form '_comboBoxModuleName')
  }
  return $false
}

function Invoke-Or-Select($Element, [string]$Label) {
  $patternObj = $null
  if ($Element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$patternObj)) {
    $patternObj.Select()
    Log "selected $Label by SelectionItemPattern"
    return
  }
  if ($Element.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$patternObj)) {
    $patternObj.Invoke()
    Log "invoked $Label by InvokePattern"
    return
  }
  throw "No safe select/invoke pattern for $Label"
}

function Select-VariableTabByAid($Form, [string]$TabAid, [string]$Label) {
  $deadline = (Get-Date).AddSeconds(6)
  $tab = $null
  $tabItem = $null
  $formForDump = $Form
  $globalName = -join ([char[]](0x5168,0x5C40))
  $localName = -join ([char[]](0x5C40,0x90E8))
  $fallbackNames = if ($TabAid -eq '_tabPageGlobal') { @($globalName) } elseif ($TabAid -eq '_tabPageLocal') { @($localName) } else { @() }
  do {
    $formForDump = Get-VariableForm $script:ProcessIdForVariables
    if ($formForDump) {
      if (Test-VariablePageSelected $formForDump $TabAid) {
        Log "verified $Label already selected"
        return $formForDump
      }
      $tab = Find-DescByAid $formForDump '_tabControl'
      if ($tab) {
        # In KV STUDIO's WinForms UIA tree, TabItems are descendants of the form,
        # but not reliably descendants of the SysTabControl32 element.
        $tabItem = Find-TabItemByAutomationIdOrName $formForDump $TabAid $fallbackNames
        if ($tabItem) { break }
      }
      [System.Windows.Forms.SendKeys]::SendWait('^{TAB}')
      Log "cycled variable editor tab by Ctrl+Tab while looking for $Label"
    }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  if (-not $tab) {
    Write-VariableFormDump $formForDump ("missing_tab_control_$($TabAid).json")
    throw 'Variable editor _tabControl missing.'
  }
  if (-not $tabItem) {
    if ($formForDump -and (Test-VariablePageSelected $formForDump $TabAid)) {
      Log "verified $Label selected after bounded Ctrl+Tab cycle"
      return $formForDump
    }
    Write-VariableFormDump $formForDump ("missing_tab_item_$($TabAid).json")
    throw "Variable tab item $TabAid for $Label was not found in KvVariableForm after bounded wait."
  }
  Invoke-Or-Select $tabItem $Label
  Start-Sleep -Milliseconds 250
  $form2 = Get-VariableForm $script:ProcessIdForVariables
  if (-not $form2) { throw "KvVariableForm disappeared after selecting $Label." }
  if (-not (Test-VariablePageSelected $form2 $TabAid)) { throw "Visible variable page for $TabAid / $Label was not found after tab selection." }
  Log "verified visible variable page for $TabAid / $Label"
  return $form2
}

function Select-LocalProgram($Form, [string]$ProgramName) {
  $combo = Find-DescByAid $Form '_comboBoxModuleName'
  if (-not $combo) { throw 'Local variable program combo _comboBoxModuleName missing.' }
  $valueObj = $null
  $current = $combo.Current.Name
  if ($combo.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$valueObj)) {
    $current = $valueObj.Current.Value
  }
  Log "local program combo current value=$current"
  if ($current -eq $ProgramName) { return }

  $expandObj = $null
  if (-not $combo.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$expandObj)) {
    throw 'Local variable program combo does not expose ExpandCollapsePattern.'
  }
  $expandObj.Expand()
  Start-Sleep -Milliseconds 250

  $form2 = Get-VariableForm $script:ProcessIdForVariables
  $items = $form2.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $target = $null
  for ($i = 0; $i -lt $items.Count; $i++) {
    $item = $items.Item($i)
    if ([string]$item.Current.Name -eq $ProgramName -and [string]$item.Current.ControlType.ProgrammaticName -eq 'ControlType.ListItem') {
      $target = $item
      break
    }
  }
  if (-not $target) { throw "Local variable target program $ProgramName was not found in combo list." }
  Invoke-Or-Select $target "local program $ProgramName"
  Start-Sleep -Milliseconds 250

  $form3 = Get-VariableForm $script:ProcessIdForVariables
  $combo2 = Find-DescByAid $form3 '_comboBoxModuleName'
  $actual = $combo2.Current.Name
  $valueObj2 = $null
  if ($combo2.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$valueObj2)) {
    $actual = $valueObj2.Current.Value
  }
  if ($actual -ne $ProgramName) { throw "Local program selection verification failed. expected=$ProgramName actual=$actual" }
  Log "verified local program selection=$ProgramName"
}

function Get-VariableForm([int]$ProcessIdValue) {
  Find-ByPidAid $ProcessIdValue 'KvVariableForm'
}

function Ensure-VariableEditorOpen([System.Diagnostics.Process]$Process, [string]$ProjectNeedle) {
  $form = Get-VariableForm $Process.Id
  if ($form) { return $form }
  Restore-KvForeground $Process $ProjectNeedle 'open variable editor'
  Send-AltLetter 0x56
  Log 'sent Alt+V'
  Send-VkTap 0x4C
  Log 'sent L after Alt+V'
  Start-Sleep -Milliseconds 700
  $form = Get-VariableForm $Process.Id
  if (-not $form) { throw 'KvVariableForm did not open after Alt+V,L.' }
  return $form
}

function Assert-NoDirectInputFast([int]$ProcessIdValue, [string]$Stage) {
  $direct = Find-ByPidAid $ProcessIdValue '1265'
  if ($direct) { throw "DirectInput/1265 detected at $Stage" }
  Log "no DirectInput/1265 at $Stage"
}

function Convert-GlobalRows([string]$Path) {
  $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::Default)
  $rows = $text | ConvertFrom-Csv -Delimiter "`t"
  $lines = foreach ($row in $rows) {
    if ($row.scope -ne 'global') { continue }
    if ($row.status -eq 'display_name') { continue }
    @(
      $row.name
      $row.data_type
    ) -join "`t"
    continue
    @(
      $row.name
      $row.data_type
      $row.device
      ''
      'False'
      'False'
      '闈炲叕寮€'
      'False'
      $row.comment
    ) -join "`t"
  }
  ($lines -join "`r`n") + "`r`n"
}

function Convert-LocalRows([string]$Path) {
  $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::Default)
  $rows = $text | ConvertFrom-Csv -Delimiter "`t"
  $lines = foreach ($row in $rows) {
    if ($row.scope -ne 'local') { continue }
    if ($row.status -eq 'display_name') { continue }
    @(
      $row.name
      $row.data_type
    ) -join "`t"
    continue
    @(
      $row.name
      $row.data_type
      ''
      'False'
      'False'
      'False'
      $row.comment
    ) -join "`t"
  }
  ($lines -join "`r`n") + "`r`n"
}

function Get-DefinedVariableRows([string]$Path, [string]$Scope) {
  $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::Default)
  @($text | ConvertFrom-Csv -Delimiter "`t" | Where-Object {
    $_.scope -eq $Scope -and $_.status -ne 'display_name'
  })
}

function Assert-TextContainsNames([string]$Text, [string[]]$Names, [string]$Label) {
  $missing = @($Names | Where-Object { -not $Text.Contains($_) })
  if ($missing.Count -gt 0) {
    throw "$Label text is missing expected decoded names: $($missing -join ', ')"
  }
  Log "$Label decoded-name guard passed: $($Names -join ',')"
}

function Assert-NoKvsModal([int]$ProcessIdValue, [string]$Stage) {
  $root = Get-Root
  $items = $root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessIdValue))
  )
  for ($i = 0; $i -lt $items.Count; $i++) {
    $item = $items.Item($i)
    if ([string]$item.Current.ControlType.ProgrammaticName -eq 'ControlType.Window' -and
        [string]$item.Current.ClassName -eq '#32770' -and
        [string]$item.Current.Name -eq 'KV STUDIO') {
      Write-VariableFormDump (Get-VariableForm $ProcessIdValue) ("modal_at_$($Stage).json")
      $text = [System.Text.StringBuilder]::new()
      $children = $item.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
      for ($j = 0; $j -lt $children.Count; $j++) {
        $name = [string]$children.Item($j).Current.Name
        if ($name) { [void]$text.Append($name + "`n") }
      }
      Set-Content -LiteralPath (Join-Path $OutDir "modal_text_$($Stage).txt") -Value $text.ToString() -Encoding UTF8
      throw "KV STUDIO modal dialog detected at $Stage. text=$($text.ToString().Trim())"
    }
  }
}

function Escape-SendKeysText([string]$Text) {
  $escaped = $Text
  foreach ($ch in @('{','}','[',']','(',')','+','^','%','~')) {
    $escaped = $escaped.Replace($ch, "{$ch}")
  }
  $escaped
}

function Focus-VariableGridArea($Form, [string]$PageAid, [string]$Label) {
  $grid = Find-DescByAid $Form '_grid'
  if ($grid) {
    $grid.SetFocus()
    $rect = $grid.Current.BoundingRectangle
    if ($rect.Width -lt 300 -or $rect.Height -lt 120) { throw "Variable grid _grid has invalid bounds for $Label." }
    $xOffset = if ($Label -like 'global*') { 110 } else { 70 }
    $x = [int]($rect.X + $xOffset)
    $y = [int]($rect.Y + 30)
    [KvSetVarWin32]::SetCursorPos($x, $y) | Out-Null
    Start-Sleep -Milliseconds 60
    [KvSetVarWin32]::mouse_event(0x0002, 0, 0, 0, 0)
    Start-Sleep -Milliseconds 40
    [KvSetVarWin32]::mouse_event(0x0004, 0, 0, 0, 0)
    Log "focused $Label by verified _grid cell click x=$x y=$y"
    Start-Sleep -Milliseconds 100
    return
  }
  $page = Find-VariablePagePane $Form $PageAid
  if (-not $page) { throw "Variable page $PageAid missing for $Label grid focus." }
  $page.SetFocus()
  $rect = $page.Current.BoundingRectangle
  if ($rect.Width -lt 300 -or $rect.Height -lt 180) { throw "Variable page $PageAid has invalid grid bounds for $Label." }
  $x = [int]($rect.X + 32)
  $y = [int]($rect.Y + 86)
  [KvSetVarWin32]::SetCursorPos($x, $y) | Out-Null
  Start-Sleep -Milliseconds 60
  [KvSetVarWin32]::mouse_event(0x0002, 0, 0, 0, 0)
  Start-Sleep -Milliseconds 40
  [KvSetVarWin32]::mouse_event(0x0004, 0, 0, 0, 0)
  Log "focused $Label by verified variable page grid coordinate x=$x y=$y page=$PageAid"
  Start-Sleep -Milliseconds 100
}

function Paste-IntoVerifiedGrid($Form, [string]$PageAid, [string]$Text, [string]$Label) {
  $grid = Find-DescByAid $Form '_grid'
  if (-not $grid) { Log "Variable grid _grid not exposed for $Label; using verified page focus path." }
  Focus-VariableGridArea $Form $PageAid $Label
  [System.Windows.Forms.Clipboard]::SetText($Text)
  [System.Windows.Forms.SendKeys]::SendWait('^v')
  Log "pasted $Label text length=$($Text.Length) into verified variable grid"
  Start-Sleep -Milliseconds 700
}

function Paste-GlobalVariablesByFirstNameTab($Form, [string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { throw 'No global variable paste text was generated.' }
  $formNow = Get-VariableForm $script:ProcessIdForVariables
  if (-not $formNow) { throw 'KvVariableForm missing before global paste.' }
  if (-not (Test-VariablePageSelected $formNow '_tabPageGlobal')) { throw 'Global variable page is not selected before paste.' }

  Focus-VariableGridArea $formNow '_tabPageGlobal' 'global variables'
  [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
  Start-Sleep -Milliseconds 150
  Log 'sent Tab to select first global variable name cell'
  Assert-NoKvsModal $script:ProcessIdForVariables 'global after Tab'
  if (-not (Get-VariableForm $script:ProcessIdForVariables)) { throw 'KvVariableForm disappeared after global Tab.' }

  [System.Windows.Forms.Clipboard]::SetText($Text)
  [System.Windows.Forms.SendKeys]::SendWait('^v')
  Start-Sleep -Milliseconds 900
  Log "pasted global variables from first name cell text length=$($Text.Length)"
  Assert-NoKvsModal $script:ProcessIdForVariables 'global after paste'
  if (-not (Get-VariableForm $script:ProcessIdForVariables)) { throw 'KvVariableForm disappeared after global paste.' }
}

function Paste-LocalVariablesByTabPgDn($Form, [string]$Text, [string]$ProgramName) {
  if ([string]::IsNullOrWhiteSpace($Text)) { throw 'No local variable paste text was generated.' }
  $formNow = Get-VariableForm $script:ProcessIdForVariables
  if (-not $formNow) { throw 'KvVariableForm missing before local Tab/PgDn paste.' }
  if (-not (Test-VariablePageSelected $formNow '_tabPageLocal')) { throw 'Local variable page is not selected before Tab/PgDn paste.' }
  Select-LocalProgram $formNow $ProgramName
  $formNow = Get-VariableForm $script:ProcessIdForVariables
  if (-not $formNow) { throw 'KvVariableForm missing after selecting local program.' }
  $combo = Find-DescByAid $formNow '_comboBoxModuleName'
  if (-not $combo) { throw 'Local variable program combo missing before Tab/PgDn paste.' }
  $combo.SetFocus()
  Log "focused local program combo before user-specified Tab/PgDn route program=$ProgramName"

  [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
  Start-Sleep -Milliseconds 150
  Log 'sent Tab to select first local variable name cell'
  Assert-NoKvsModal $script:ProcessIdForVariables 'local after Tab'
  if (-not (Get-VariableForm $script:ProcessIdForVariables)) { throw 'KvVariableForm disappeared after local Tab.' }

  [System.Windows.Forms.SendKeys]::SendWait('{PGDN}')
  Start-Sleep -Milliseconds 250
  Log 'sent PgDn to move to last local variable row'
  Assert-NoKvsModal $script:ProcessIdForVariables 'local after PgDn'
  if (-not (Get-VariableForm $script:ProcessIdForVariables)) { throw 'KvVariableForm disappeared after local PgDn.' }

  [System.Windows.Forms.Clipboard]::SetText($Text)
  [System.Windows.Forms.SendKeys]::SendWait('^v')
  Start-Sleep -Milliseconds 800
  Log "pasted local variables by Tab/PgDn route text length=$($Text.Length)"
  Assert-NoKvsModal $script:ProcessIdForVariables 'local after paste'
  if (-not (Get-VariableForm $script:ProcessIdForVariables)) { throw 'KvVariableForm disappeared after local paste.' }
}

function Enter-VariablesCellByCell($Form, [string]$PageAid, [object[]]$Rows, [string[]]$Columns, [string]$Label) {
  if ($Rows.Count -eq 0) { throw "No variable rows to enter for $Label." }
  Focus-VariableGridArea $Form $PageAid $Label
  if ($PageAid -eq '_tabPageGlobal') {
    [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
    Start-Sleep -Milliseconds 120
    Log "moved global variable focus from group name to variable name by Tab"
  }
  for ($r = 0; $r -lt $Rows.Count; $r++) {
    $row = $Rows[$r]
    for ($c = 0; $c -lt $Columns.Count; $c++) {
      $column = $Columns[$c]
      $value = [string]$row.$column
      if ($value.Length -gt 0) {
        [System.Windows.Forms.SendKeys]::SendWait((Escape-SendKeysText $value))
        Start-Sleep -Milliseconds 60
      }
      if ($c -lt ($Columns.Count - 1)) {
        [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
        Start-Sleep -Milliseconds 70
      }
    }
    if ($PageAid -eq '_tabPageGlobal') {
      [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
      Start-Sleep -Milliseconds 80
      [System.Windows.Forms.SendKeys]::SendWait('{HOME}')
      Start-Sleep -Milliseconds 80
      [System.Windows.Forms.SendKeys]::SendWait('{DOWN}')
      Start-Sleep -Milliseconds 80
      [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
      Start-Sleep -Milliseconds 120
    } else {
      [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
      Start-Sleep -Milliseconds 120
    }
    Assert-NoKvsModal $script:ProcessIdForVariables "$Label row $($r + 1)"
    Log "entered $Label row $($r + 1): $($row.name)"
  }
}

function Save-Shot([string]$Name) {
  $bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = New-Object Drawing.Bitmap $bounds.Width, $bounds.Height
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
  $bitmap.Save((Join-Path $OutDir $Name))
  $graphics.Dispose()
  $bitmap.Dispose()
  Log "screenshot $Name"
}

function Save-Project([System.Diagnostics.Process]$Process, [string]$ProjectNeedle) {
  Restore-KvForeground $Process $ProjectNeedle 'Ctrl+S after variable paste'
  [System.Windows.Forms.SendKeys]::SendWait('^s')
  Log 'sent Ctrl+S after variable paste'
  Start-Sleep -Seconds 2
}

function Close-VariableEditor([int]$ProcessIdValue) {
  $form = Get-VariableForm $ProcessIdValue
  if (-not $form) { return }
  $patternObj = $null
  if ($form.TryGetCurrentPattern([System.Windows.Automation.WindowPattern]::Pattern, [ref]$patternObj)) {
    $patternObj.Close()
    Start-Sleep -Milliseconds 700
    Log 'closed variable editor by WindowPattern'
    return
  }
  throw 'KvVariableForm does not expose WindowPattern for close.'
}

function Test-ProjectHasNames([string]$ProjectRoot, [string[]]$Names) {
  $matches = @{}
  foreach ($name in $Names) { $matches[$name] = @() }
  $files = Get-ChildItem -LiteralPath $ProjectRoot -File -Recurse -ErrorAction SilentlyContinue
  foreach ($file in $files) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $unicode = [Text.Encoding]::Unicode.GetString($bytes)
    $ansi = [Text.Encoding]::Default.GetString($bytes)
    foreach ($name in $Names) {
      if ($unicode.Contains($name) -or $ansi.Contains($name)) {
        $matches[$name] += $file.FullName
      }
    }
  }
  $missing = @($Names | Where-Object { $matches[$_].Count -eq 0 })
  [pscustomobject]@{
    Ok = ($missing.Count -eq 0)
    Missing = $missing
    Matches = $matches
  }
}

try {
  Log 'start set variables'
  Log "ProjectPath=$ProjectPath"
  if (-not (Test-Path -LiteralPath $ProjectPath)) { throw "ProjectPath not found: $ProjectPath" }
  if (-not (Test-Path -LiteralPath $GlobalVariablesTsv)) { throw "GlobalVariablesTsv not found: $GlobalVariablesTsv" }
  if (-not (Test-Path -LiteralPath $LocalVariablesTsv)) { throw "LocalVariablesTsv not found: $LocalVariablesTsv" }

  $projectNeedle = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  $projectRoot = Split-Path -Parent $ProjectPath
  $process = Get-VisibleKvsProcess
  if (-not $process) { throw 'No visible KV STUDIO process.' }
  $script:ProcessIdForVariables = $process.Id
  Restore-KvForeground $process $projectNeedle 'set variables start'
  Set-CapsLockState $true
  Assert-NoDirectInputFast $process.Id 'before variable editing'

  $globalText = Convert-GlobalRows $GlobalVariablesTsv
  $localText = Convert-LocalRows $LocalVariablesTsv
  $globalRows = Get-DefinedVariableRows $GlobalVariablesTsv 'global'
  $localRows = Get-DefinedVariableRows $LocalVariablesTsv 'local'
  $definedGlobalNames = @($globalRows | ForEach-Object { [string]$_.name } | Where-Object { $_ })
  $definedLocalNames = @($localRows | ForEach-Object { [string]$_.name } | Where-Object { $_ })
  Log "decoded executable global variable rows=$($definedGlobalNames.Count): $($definedGlobalNames -join ',')"
  Log "decoded executable local variable rows=$($definedLocalNames.Count): $($definedLocalNames -join ',')"
  Set-Content -LiteralPath (Join-Path $OutDir 'global_paste.tsv') -Value $globalText -Encoding UTF8
  Set-Content -LiteralPath (Join-Path $OutDir 'local_paste.tsv') -Value $localText -Encoding UTF8

  $form = Ensure-VariableEditorOpen $process $projectNeedle
  Set-CapsLockState $false
  if ($SkipGlobal) {
    Log 'skipping global variable entry by parameter'
  } elseif ($globalRows.Count -gt 0) {
    $form = Select-VariableTabByAid $form '_tabPageGlobal' 'global tab'
    Paste-GlobalVariablesByFirstNameTab $form $globalText
    Save-Shot '01_after_global_paste.png'
  } else {
    Log 'no executable global variables to enter'
  }

  $form = Get-VariableForm $process.Id
  $form = Select-VariableTabByAid $form '_tabPageLocal' 'local tab'
  Select-LocalProgram $form $LocalProgramName
  $form = Get-VariableForm $process.Id
  if ($KeepVariableEditorOpen) {
    Save-Shot '00_before_local_repaste.png'
  }
  Paste-LocalVariablesByTabPgDn $form $localText $LocalProgramName
  Save-Shot '02_after_local_paste.png'

  Save-Project $process $projectNeedle
  Save-Shot '03_after_save.png'
  Assert-NoKvsModal $process.Id 'after variable save'
  if (-not (Get-VariableForm $process.Id)) { throw 'KvVariableForm disappeared after variable save.' }

  $requiredNames = @($definedGlobalNames + $definedLocalNames | Where-Object { $_ } | Select-Object -Unique)
  $fileScan = Test-ProjectHasNames $projectRoot $requiredNames
  if (-not $fileScan.Ok) {
    throw "Variable definition verification failed after save. Missing names: $($fileScan.Missing -join ', ')"
  }
  $validation = [pscustomobject]@{
    Ok = $true
    Basis = 'variable editor route completed without modal; required executable variable names were found in same-run saved project files'
    RequiredNames = $requiredNames
    VariableDefinitionCheckOk = $fileScan.Ok
    LocalPasteRoute = "local tab -> $LocalProgramName -> Tab -> PgDn -> Ctrl+V"
    ScreenshotAfterLocalPaste = (Join-Path $OutDir '02_after_local_paste.png')
    ProjectFileScan = $fileScan
  }
  $validation | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutDir 'variable_persistence_validation.json') -Encoding UTF8

  [pscustomobject]@{
    Ok = $true
    ProjectPath = $ProjectPath
    ProjectRoot = $projectRoot
    RequiredNames = $requiredNames
    VariableDefinitionCheckOk = $fileScan.Ok
  } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'set_variables_result.json') -Encoding UTF8
  Log 'done set variables'
} catch {
  Log ('ERROR ' + $_.Exception.ToString())
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  exit 1
}
