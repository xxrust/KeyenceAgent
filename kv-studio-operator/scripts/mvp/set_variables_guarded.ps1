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
  [switch]$AuditPersistence,
  [switch]$AuditProjectTextScan,
  [switch]$AuditScreenshots,

  [string]$ChecklistPath = '',

  [string]$OutDir = ('E:\personal_project\rust_plc\out\traffic_light_min_loop_20260525\validation\set_variables_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$script:CheckpointDir = Join-Path $OutDir 'checkpoints'
New-Item -ItemType Directory -Force -Path $script:CheckpointDir | Out-Null
$script:CheckpointSeq = 0
$script:LastErrorCode = ''
$script:LastErrorStep = ''
$script:LastErrorEvidence = @()

$sharedUiGuard = Join-Path (Split-Path -Parent $PSCommandPath) 'kv_ui_guard.ps1'
if (-not (Test-Path -LiteralPath $sharedUiGuard)) { throw "Shared KV UI guard script not found: $sharedUiGuard" }
. $sharedUiGuard
Initialize-KvUiGuard -OutDir $OutDir -CheckpointSubdir 'shared_ui_guard_checkpoints'

$checklistGuard = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'assert_kv_operation_checklist.ps1'
if (-not (Test-Path -LiteralPath $checklistGuard)) { throw "Checklist guard script not found: $checklistGuard" }
$global:LASTEXITCODE = 0
& $checklistGuard -ChecklistPath $ChecklistPath -SearchRoots @($OutDir, $ProjectPath, $GlobalVariablesTsv, $LocalVariablesTsv) -OperationName 'set KV STUDIO variables' | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

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
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  public delegate bool EnumWindowProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowProc lpEnumFunc, IntPtr lParam);
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

function Get-ForegroundSnapshot {
  $hwnd = [KvSetVarWin32]::GetForegroundWindow()
  $titleBuilder = New-Object System.Text.StringBuilder 512
  $classBuilder = New-Object System.Text.StringBuilder 256
  [void][KvSetVarWin32]::GetWindowText($hwnd, $titleBuilder, $titleBuilder.Capacity)
  [void][KvSetVarWin32]::GetClassName($hwnd, $classBuilder, $classBuilder.Capacity)
  $pidValue = [uint32]0
  [void][KvSetVarWin32]::GetWindowThreadProcessId($hwnd, [ref]$pidValue)
  $processName = ''
  if ($pidValue -gt 0) {
    try { $processName = (Get-Process -Id ([int]$pidValue) -ErrorAction Stop).ProcessName } catch { $processName = '' }
  }
  [pscustomobject]@{
    hwnd = $hwnd.ToInt64()
    title = $titleBuilder.ToString()
    class_name = $classBuilder.ToString()
    process_id = [int]$pidValue
    process_name = $processName
  }
}

function Get-VariableFormSnapshot($Form) {
  if (-not $Form) { return $null }
  $rect = $Form.Current.BoundingRectangle
  [pscustomobject]@{
    hwnd = ([IntPtr]$Form.Current.NativeWindowHandle).ToInt64()
    title = [string]$Form.Current.Name
    automation_id = [string]$Form.Current.AutomationId
    control_type = [string]$Form.Current.ControlType.ProgrammaticName
    class_name = [string]$Form.Current.ClassName
    process_id = [int]$Form.Current.ProcessId
    is_enabled = [bool]$Form.Current.IsEnabled
    is_offscreen = [bool]$Form.Current.IsOffscreen
    bounds = [pscustomobject]@{
      x = [int]$rect.X
      y = [int]$rect.Y
      width = [int]$rect.Width
      height = [int]$rect.Height
    }
  }
}

function Convert-SafeFileName([string]$Value) {
  $safe = $Value -replace '[^A-Za-z0-9_.-]+', '_'
  if ([string]::IsNullOrWhiteSpace($safe)) { return 'step' }
  return $safe.Trim('_')
}

function Write-StepCheckpoint(
  [string]$Step,
  [string]$Status,
  [string]$Action,
  $Form,
  $Before,
  $After,
  [string]$ErrorCode = '',
  [string]$Message = '',
  [string[]]$Evidence = @()
) {
  $script:CheckpointSeq += 1
  $fileName = ('{0:D3}_{1}_{2}.json' -f $script:CheckpointSeq, (Convert-SafeFileName $Step), (Convert-SafeFileName $Status))
  $path = Join-Path $script:CheckpointDir $fileName
  $payload = [ordered]@{
    timestamp = (Get-Date).ToString('o')
    step = $Step
    status = $Status
    action = $Action
    expected_window = 'KV STUDIO variable editor KvVariableForm'
    target = Get-VariableFormSnapshot $Form
    foreground_before = $Before
    foreground_after = $After
    error_code = $ErrorCode
    message = $Message
    evidence = $Evidence
  }
  $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
  Log "checkpoint $Status step=$Step path=$path code=$ErrorCode"
  return $path
}

function Classify-ForegroundMismatch($Snapshot, [IntPtr]$TargetHwnd) {
  if (-not $Snapshot) { return 'KV_FOCUS_LOST' }
  if ($Snapshot.hwnd -eq $TargetHwnd.ToInt64()) { return '' }
  $name = [string]$Snapshot.process_name
  $title = [string]$Snapshot.title
  if ($name -match '^(powershell|pwsh|WindowsTerminal|cmd|conhost)$') { return 'KV_FOCUS_LOST_TERMINAL' }
  if ($title -eq 'KV STUDIO' -or $title -like 'KV STUDIO*') { return 'KV_VARIABLE_FORM_NOT_FOREGROUND' }
  if ($Snapshot.class_name -eq '#32770') { return 'KV_MODAL_PRESENT' }
  return 'KV_FOCUS_LOST'
}

function Fail-Guard([string]$ErrorCode, [string]$Step, [string]$Message, [string[]]$Evidence = @()) {
  $script:LastErrorCode = $ErrorCode
  $script:LastErrorStep = $Step
  $script:LastErrorEvidence = $Evidence
  throw "[$ErrorCode] $Message"
}

function Send-VkTap([byte]$Vk, [IntPtr]$TargetHwnd, [string]$ExpectedTitleLike, [string]$Step) {
  Invoke-KvGuardedVkTap -TargetHwnd $TargetHwnd -Step $Step -Vk $Vk -ExpectedTitleLike $ExpectedTitleLike -SleepMs 70
}

function Send-AltLetter([byte]$Vk, [IntPtr]$TargetHwnd, [string]$ExpectedTitleLike, [string]$Step) {
  Invoke-KvGuardedAltVk -TargetHwnd $TargetHwnd -Step $Step -Vk $Vk -ExpectedTitleLike $ExpectedTitleLike -SleepMs 100
}

function Test-CapsLockOn {
  (([KvSetVarWin32]::GetKeyState(0x14) -band 1) -ne 0)
}

function Set-CapsLockState([bool]$Enabled, [IntPtr]$TargetHwnd, [string]$ExpectedTitleLike, [string]$StepPrefix) {
  $current = Test-CapsLockOn
  Log "CapsLock before accelerator normalization=$current"
  if ($current -ne $Enabled) {
    Send-VkTap 0x14 $TargetHwnd $ExpectedTitleLike "$StepPrefix CapsLock"
    Start-Sleep -Milliseconds 80
  }
  $after = Test-CapsLockOn
  Log "CapsLock after accelerator normalization=$after"
  if ($after -ne $Enabled) { throw "Failed to set CapsLock state to $Enabled" }
}

function Restore-KvForeground([System.Diagnostics.Process]$Process, [string]$ProjectNeedle, [string]$Action) {
  [KvSetVarWin32]::ShowWindow($Process.MainWindowHandle, 3) | Out-Null
  for ($i = 1; $i -le 10; $i++) {
    if ([KvSetVarWin32]::IsIconic($Process.MainWindowHandle)) {
      [KvSetVarWin32]::ShowWindow($Process.MainWindowHandle, 9) | Out-Null
    }
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

function Get-TopLevelWindowElementsForProcess([int]$ProcessIdValue) {
  $handles = [System.Collections.Generic.List[IntPtr]]::new()
  [KvSetVarWin32]::EnumWindows({
    param([IntPtr]$hwnd, [IntPtr]$lparam)
    $pidValue = [uint32]0
    [void][KvSetVarWin32]::GetWindowThreadProcessId($hwnd, [ref]$pidValue)
    if ([int]$pidValue -eq $ProcessIdValue) { $handles.Add($hwnd) }
    return $true
  }, [IntPtr]::Zero) | Out-Null

  $elements = [System.Collections.Generic.List[object]]::new()
  foreach ($hwnd in $handles) {
    try {
      $element = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
      if ($element) { $elements.Add($element) }
    } catch {}
  }
  @($elements)
}

function Find-ByPidAid([int]$ProcessIdValue, [string]$AutomationId) {
  $condition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::AutomationIdProperty,
    $AutomationId
  )
  foreach ($window in (Get-TopLevelWindowElementsForProcess $ProcessIdValue)) {
    if ([string]$window.Current.AutomationId -eq $AutomationId) { return $window }
    $found = $window.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
    if ($found) { return $found }
  }
  return $null
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
      $formForDump = Invoke-GuardedVariableKeyAction $formForDump "cycle variable tab for $Label" '^{TAB}' "Ctrl+Tab while looking for $Label" 250
      Log "cycled variable editor tab by guarded Ctrl+Tab while looking for $Label"
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

function Wait-VariableForm([int]$ProcessIdValue, [int]$Seconds = 6) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $form = Get-VariableForm $ProcessIdValue
    if ($form) { return $form }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Bring-VariableFormForeground($Form, [string]$Label) {
  if (-not $Form) { throw "KvVariableForm missing before foreground restore for $Label." }
  $hwnd = [IntPtr]$Form.Current.NativeWindowHandle
  if ($hwnd -eq [IntPtr]::Zero) { throw "KvVariableForm has no native window handle before $Label." }
  [KvSetVarWin32]::ShowWindow($hwnd, 3) | Out-Null
  [KvSetVarWin32]::SetForegroundWindow($hwnd) | Out-Null
  Start-Sleep -Milliseconds 180
  $fg = Get-ForegroundTitle
  Log "foreground variable form ${Label}: hwnd=$($fg.Hwnd) title=$($fg.Title)"
  if ($fg.Title -notlike '*变量编辑*') {
    throw "KvVariableForm is not foreground before $Label. title=$($fg.Title)"
  }
}

function Assert-VariableFormForeground($Form, [string]$Step, [switch]$AllowSingleRecovery) {
  if (-not $Form) {
    $path = Write-StepCheckpoint $Step 'failed' 'assert variable form exists' $null (Get-ForegroundSnapshot) $null 'KV_VARIABLE_FORM_NOT_FOREGROUND' 'KvVariableForm is missing before guarded input.' @()
    Fail-Guard 'KV_VARIABLE_FORM_NOT_FOREGROUND' $Step 'KvVariableForm is missing before guarded input.' @($path)
  }
  $targetHwnd = [IntPtr]$Form.Current.NativeWindowHandle
  if ($targetHwnd -eq [IntPtr]::Zero) {
    $path = Write-StepCheckpoint $Step 'failed' 'assert variable form hwnd' $Form (Get-ForegroundSnapshot) $null 'KV_VARIABLE_FORM_NOT_FOREGROUND' 'KvVariableForm has no native window handle.' @()
    Fail-Guard 'KV_VARIABLE_FORM_NOT_FOREGROUND' $Step 'KvVariableForm has no native window handle.' @($path)
  }

  $before = Get-ForegroundSnapshot
  if ($before.hwnd -eq $targetHwnd.ToInt64()) { return $before }

  if ($AllowSingleRecovery) {
    $recoveryPath = Write-StepCheckpoint $Step 'recovery_before' 'restore variable editor foreground once' $Form $before $null (Classify-ForegroundMismatch $before $targetHwnd) 'Foreground was not KvVariableForm; attempting one controlled recovery.' @()
    [KvSetVarWin32]::ShowWindow($targetHwnd, 3) | Out-Null
    [KvSetVarWin32]::SetForegroundWindow($targetHwnd) | Out-Null
    Start-Sleep -Milliseconds 180
    $afterRecovery = Get-ForegroundSnapshot
    if ($afterRecovery.hwnd -eq $targetHwnd.ToInt64()) {
      Write-StepCheckpoint $Step 'recovery_after' 'restore variable editor foreground once' $Form $before $afterRecovery '' 'Foreground recovery succeeded.' @($recoveryPath) | Out-Null
      return $afterRecovery
    }
    $code = Classify-ForegroundMismatch $afterRecovery $targetHwnd
    $failurePath = Write-StepCheckpoint $Step 'failed' 'assert variable editor foreground' $Form $before $afterRecovery $code 'Foreground recovery failed; guarded keyboard/mouse input was not sent.' @($recoveryPath)
    Fail-Guard $code $Step "Foreground is not KvVariableForm after recovery. hwnd=$($afterRecovery.hwnd) title=$($afterRecovery.title) process=$($afterRecovery.process_name)" @($recoveryPath, $failurePath)
  }

  $code = Classify-ForegroundMismatch $before $targetHwnd
  $path = Write-StepCheckpoint $Step 'failed' 'assert variable editor foreground' $Form $before $null $code 'Foreground is not KvVariableForm and recovery was disabled.' @()
  Fail-Guard $code $Step "Foreground is not KvVariableForm. hwnd=$($before.hwnd) title=$($before.title) process=$($before.process_name)" @($path)
}

function Invoke-GuardedVariableKeyAction($Form, [string]$Step, [string]$Keys, [string]$Description, [int]$SleepMs = 150) {
  $before = Assert-VariableFormForeground $Form $Step -AllowSingleRecovery
  $beforePath = Write-StepCheckpoint $Step 'before' $Description $Form $before $null '' 'Precondition passed; target variable editor owns foreground.' @()
  Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$Form.Current.NativeWindowHandle) -Step $Step -Keys $Keys -ExpectedTitleLike '*变量编辑*' -Action $Description -SleepMs $SleepMs
  $formAfter = Wait-VariableForm $script:ProcessIdForVariables 6
  if (-not $formAfter) {
    $after = Get-ForegroundSnapshot
    $failurePath = Write-StepCheckpoint $Step 'failed' $Description $Form $before $after 'KV_VARIABLE_FORM_NOT_FOREGROUND' 'KvVariableForm disappeared after guarded key action.' @($beforePath)
    Fail-Guard 'KV_VARIABLE_FORM_NOT_FOREGROUND' $Step 'KvVariableForm disappeared after guarded key action.' @($beforePath, $failurePath)
  }
  Assert-NoKvsModal $script:ProcessIdForVariables "$Step after key action"
  $after = Assert-VariableFormForeground $formAfter "$Step postcondition" -AllowSingleRecovery
  Write-StepCheckpoint $Step 'after' $Description $formAfter $before $after '' 'Postcondition passed; variable editor still owns foreground.' @($beforePath) | Out-Null
  return $formAfter
}

function Invoke-GuardedVariablePaste($Form, [string]$Step, [string]$Text, [string]$Description, [int]$SleepMs = 800) {
  if ([string]::IsNullOrWhiteSpace($Text)) {
    Fail-Guard 'KV_VARIABLE_CHECKPOINT_FAILED' $Step 'Paste text is empty; guarded paste refused before touching clipboard.' @()
  }
  Invoke-KvGuardedClipboardPaste -TargetHwnd ([IntPtr]$Form.Current.NativeWindowHandle) -Step $Step -Text $Text -ExpectedTitleLike '*变量编辑*' -SleepMs $SleepMs
  return (Wait-VariableForm $script:ProcessIdForVariables 6)
}

function Invoke-GuardedKvMainKeyAction([System.Diagnostics.Process]$Process, [string]$ProjectNeedle, [string]$Step, [string]$Keys, [string]$Description, [int]$SleepMs = 500) {
  Restore-KvForeground $Process $ProjectNeedle $Step
  $before = Get-ForegroundSnapshot
  $beforePath = Write-StepCheckpoint $Step 'before' $Description $null $before $null '' 'Precondition passed; KV STUDIO main window owns foreground.' @()
  if ($before.title -notlike 'KV STUDIO*' -or $before.title -notlike "*$ProjectNeedle*") {
    $path = Write-StepCheckpoint $Step 'failed' $Description $null $before $null 'KV_FOCUS_LOST' 'KV STUDIO main window is not foreground before guarded key action.' @($beforePath)
    Fail-Guard 'KV_FOCUS_LOST' $Step "KV STUDIO main window is not foreground before guarded key action. title=$($before.title)" @($beforePath, $path)
  }
  Invoke-KvGuardedSendKeys -TargetHwnd $Process.MainWindowHandle -Step $Step -Keys $Keys -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -Action $Description -SleepMs $SleepMs
  $after = Get-ForegroundSnapshot
  Write-StepCheckpoint $Step 'after' $Description $null $before $after '' 'Guarded KV STUDIO main key action completed.' @($beforePath) | Out-Null
}

function Ensure-VariableEditorOpen([System.Diagnostics.Process]$Process, [string]$ProjectNeedle) {
  $form = Get-VariableForm $Process.Id
  if ($form) { return $form }
  Restore-KvForeground $Process $ProjectNeedle 'open variable editor'
  Send-AltLetter 0x56 $Process.MainWindowHandle "KV STUDIO*$ProjectNeedle*" 'open variable editor Alt+V'
  Log 'sent Alt+V'
  Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $Process.MainWindowHandle -Step 'open variable editor L' -Keys 'l' -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -SuccessTitleLike '*变量编辑*' -Action 'L opens the variable editor from the View menu' -SleepMs 700
  Log 'sent L after Alt+V'
  Start-Sleep -Milliseconds 700
  $form = Get-VariableForm $Process.Id
  if (-not $form) { throw 'KvVariableForm did not open after Alt+V,L.' }
  return $form
}

function Assert-NoDirectInputFast([int]$ProcessIdValue, [string]$Stage) {
  $watch = [Diagnostics.Stopwatch]::StartNew()
  $direct = Find-ByPidAid $ProcessIdValue '1265'
  $watch.Stop()
  Log "DirectInput/1265 scoped probe elapsed_ms=$($watch.ElapsedMilliseconds) stage=$Stage"
  if ($direct) { throw "DirectInput/1265 detected at $Stage" }
  Log "no DirectInput/1265 at $Stage"
}

function Assert-NoKvsModalFast([int]$ProcessIdValue, [string]$Stage) {
  foreach ($window in (Get-TopLevelWindowElementsForProcess $ProcessIdValue)) {
    if ([string]$window.Current.ClassName -eq '#32770' -and [string]$window.Current.Name -eq 'KV STUDIO') {
      Fail-Guard 'KV_MODAL_PRESENT' $Stage "KV STUDIO modal dialog detected at $Stage." @()
    }
  }
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
  if (-not $AuditPersistence) {
    Assert-NoKvsModalFast $ProcessIdValue $Stage
    return
  }
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
      $dumpName = "modal_at_$($Stage).json"
      Write-VariableFormDump (Get-VariableForm $ProcessIdValue) $dumpName
      $text = [System.Text.StringBuilder]::new()
      $children = $item.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
      for ($j = 0; $j -lt $children.Count; $j++) {
        $name = [string]$children.Item($j).Current.Name
        if ($name) { [void]$text.Append($name + "`n") }
      }
      $textPath = Join-Path $OutDir "modal_text_$($Stage).txt"
      Set-Content -LiteralPath $textPath -Value $text.ToString() -Encoding UTF8
      Fail-Guard 'KV_MODAL_PRESENT' $Stage "KV STUDIO modal dialog detected. text=$($text.ToString().Trim())" @((Join-Path $OutDir $dumpName), $textPath)
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
  $focusStep = "$Label grid focus"
  $before = Assert-VariableFormForeground $Form $focusStep -AllowSingleRecovery
  $grid = Find-DescByAid $Form '_grid'
  if ($grid) {
    $grid.SetFocus()
    $rect = $grid.Current.BoundingRectangle
    if ($rect.Width -lt 300 -or $rect.Height -lt 120) { throw "Variable grid _grid has invalid bounds for $Label." }
    $xOffset = if ($Label -like 'global*') { 110 } else { 70 }
    $x = [int]($rect.X + $xOffset)
    $y = [int]($rect.Y + 30)
    Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$Form.Current.NativeWindowHandle) -Step "$focusStep grid click" -X $x -Y $y -ExpectedTitleLike '*变量编辑*' -SleepMs 100
    Log "focused $Label by verified _grid cell click x=$x y=$y"
    $after = Assert-VariableFormForeground $Form "$focusStep postcondition" -AllowSingleRecovery
    Write-StepCheckpoint $focusStep 'after' "UIA SetFocus plus verified grid mouse click x=$x y=$y" $Form $before $after '' 'Variable grid focus completed.' @() | Out-Null
    return
  }
  $page = Find-VariablePagePane $Form $PageAid
  if (-not $page) { throw "Variable page $PageAid missing for $Label grid focus." }
  $page.SetFocus()
  $rect = $page.Current.BoundingRectangle
  if ($rect.Width -lt 300 -or $rect.Height -lt 180) { throw "Variable page $PageAid has invalid grid bounds for $Label." }
  $x = [int]($rect.X + 32)
  $y = [int]($rect.Y + 86)
  Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$Form.Current.NativeWindowHandle) -Step "$focusStep page click" -X $x -Y $y -ExpectedTitleLike '*变量编辑*' -SleepMs 100
  Log "focused $Label by verified variable page grid coordinate x=$x y=$y page=$PageAid"
  $after = Assert-VariableFormForeground $Form "$focusStep postcondition" -AllowSingleRecovery
  Write-StepCheckpoint $focusStep 'after' "UIA SetFocus plus verified page mouse click x=$x y=$y" $Form $before $after '' 'Variable page focus completed.' @() | Out-Null
}

function Paste-IntoVerifiedGrid($Form, [string]$PageAid, [string]$Text, [string]$Label) {
  $grid = Find-DescByAid $Form '_grid'
  if (-not $grid) { Log "Variable grid _grid not exposed for $Label; using verified page focus path." }
  Focus-VariableGridArea $Form $PageAid $Label
  Invoke-GuardedVariablePaste $Form "$Label verified grid paste" $Text "Ctrl+V into verified variable grid for $Label" 700 | Out-Null
  Log "pasted $Label text length=$($Text.Length) into verified variable grid"
}

function Get-ClipboardTextAfterCopy([string]$Sentinel, [int]$Seconds = 4) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    Start-Sleep -Milliseconds 200
    try {
      $text = [Windows.Forms.Clipboard]::GetText()
      if ($text -and $text -ne $Sentinel) { return $text }
    } catch {
      Log "clipboard read retry after copy: $($_.Exception.Message)"
    }
  } while ((Get-Date) -lt $deadline)
  return ''
}

function Copy-VariableGridText($Form, [string]$PageAid, [string]$Label) {
  $sentinel = '__KV_VARIABLE_GRID_COPY_SENTINEL__'
  Invoke-KvGuardedClipboardSetText -TargetHwnd ([IntPtr]$Form.Current.NativeWindowHandle) -Step "$Label sentinel clipboard set" -Text $sentinel -ExpectedTitleLike '*变量编辑*'
  Focus-VariableGridArea $Form $PageAid $Label
  $formNow = Wait-VariableForm $script:ProcessIdForVariables 6
  $formNow = Invoke-GuardedVariableKeyAction $formNow "$Label Ctrl+A" '^a' "Ctrl+A selects $Label variable grid text" 200
  $formNow = Invoke-GuardedVariableKeyAction $formNow "$Label Ctrl+C" '^c' "Ctrl+C copies $Label variable grid text" 300
  $text = Get-ClipboardTextAfterCopy $sentinel 5
  if ([string]::IsNullOrWhiteSpace($text)) {
    Fail-Guard 'KV_VARIABLE_GRID_COPY_EMPTY' "$Label copy verification" "Variable grid copy returned empty text for $Label." @()
  }
  Log "copied $Label grid text length=$($text.Length)"
  return $text
}

function Assert-NamesInCopiedText([string]$Text, [string[]]$Names, [string]$Label, [string]$EvidencePath) {
  $missing = @($Names | Where-Object { $_ -and -not $Text.Contains($_) })
  if ($missing.Count -gt 0) {
    Fail-Guard 'KV_LOCAL_VARIABLE_REOPEN_VERIFICATION_FAILED' "$Label copied-text verification" "$Label copied text is missing expected variable name(s): $($missing -join ', ')" @($EvidencePath)
  }
  Log "$Label copied-text verification passed: $($Names -join ',')"
}

function Paste-GlobalVariablesByFirstNameTab($Form, [string]$Text) {
  if ([string]::IsNullOrWhiteSpace($Text)) { throw 'No global variable paste text was generated.' }
  $formNow = Get-VariableForm $script:ProcessIdForVariables
  if (-not $formNow) { throw 'KvVariableForm missing before global paste.' }
  if (-not (Test-VariablePageSelected $formNow '_tabPageGlobal')) { throw 'Global variable page is not selected before paste.' }

  Focus-VariableGridArea $formNow '_tabPageGlobal' 'global variables'
  $formNow = Wait-VariableForm $script:ProcessIdForVariables 6
  $formNow = Invoke-GuardedVariableKeyAction $formNow 'global first-name Tab' '{TAB}' 'Tab to select first global variable name cell' 150
  Log 'sent guarded Tab to select first global variable name cell'

  $formNow = Invoke-GuardedVariablePaste $formNow 'global variables Ctrl+V' $Text 'Ctrl+V global variables from first name cell' 300
  Log "pasted global variables from first name cell text length=$($Text.Length)"
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
  Assert-VariableFormForeground $formNow 'local program combo focus' -AllowSingleRecovery | Out-Null
  $combo.SetFocus()
  Log "focused local program combo before user-specified Tab/PgDn route program=$ProgramName"

  $formNow = Invoke-GuardedVariableKeyAction $formNow 'local first-name Tab' '{TAB}' 'Tab to select first local variable name cell' 150
  Log 'sent guarded Tab to select first local variable name cell'

  $formNow = Invoke-GuardedVariableKeyAction $formNow 'local last-row PgDn' '{PGDN}' 'PgDn to move to last local variable row' 250
  Log 'sent guarded PgDn to move to last local variable row'

  $formNow = Invoke-GuardedVariablePaste $formNow 'local variables Ctrl+V' $Text 'Ctrl+V local variables by Tab/PgDn route' 300
  Log "pasted local variables by Tab/PgDn route text length=$($Text.Length)"
}

function Enter-VariablesCellByCell($Form, [string]$PageAid, [object[]]$Rows, [string[]]$Columns, [string]$Label) {
  Fail-Guard 'KV_UNSAFE_ROUTE_DISABLED' "$Label cell-by-cell entry" 'Cell-by-cell SendKeys route is disabled. Use guarded paste route with foreground checkpoints.' @()
}

function Save-Shot([string]$Name) {
  if (-not $AuditScreenshots) {
    Log "skipped screenshot $Name because AuditScreenshots is disabled"
    return
  }
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
  Invoke-GuardedKvMainKeyAction $Process $ProjectNeedle 'save project after variables' '^s' 'Ctrl+S after variable paste' 300
  Log 'sent Ctrl+S after variable paste'
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
  Set-CapsLockState $true $process.MainWindowHandle "KV STUDIO*$projectNeedle*" 'set variables start'
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
  Set-CapsLockState $false ([IntPtr]$form.Current.NativeWindowHandle) '*变量编辑*' 'variable editor opened'
  if ($SkipGlobal) {
    Log 'skipping global variable entry by parameter'
  } elseif ($globalRows.Count -gt 0) {
    $form = Select-VariableTabByAid $form '_tabPageGlobal' 'global tab'
    Paste-GlobalVariablesByFirstNameTab $form $globalText
    Save-Shot '01_after_global_paste.png'
  } else {
    Log 'no executable global variables to enter'
  }

  if ($localRows.Count -gt 0) {
    $form = Get-VariableForm $process.Id
    $form = Select-VariableTabByAid $form '_tabPageLocal' 'local tab'
    Select-LocalProgram $form $LocalProgramName
    $form = Get-VariableForm $process.Id
    if ($KeepVariableEditorOpen) {
      Save-Shot '00_before_local_repaste.png'
    }
    Paste-LocalVariablesByTabPgDn $form $localText $LocalProgramName
    Save-Shot '02_after_local_paste.png'
  } else {
    Log 'no executable local variables to enter'
  }

  Save-Project $process $projectNeedle
  Save-Shot '03_after_save.png'
  Assert-NoKvsModal $process.Id 'after variable save'
  if (-not (Wait-VariableForm $process.Id 1)) { throw 'KvVariableForm disappeared after variable save.' }
  if ($AuditPersistence -and -not $KeepVariableEditorOpen) {
    Close-VariableEditor $process.Id
    Start-Sleep -Milliseconds 700
    if (Wait-VariableForm $process.Id 2) { throw 'KvVariableForm remained open after close request before persistence verification.' }
    Save-Project $process $projectNeedle
    Save-Shot '04_after_variable_editor_close_and_save.png'
    Assert-NoKvsModal $process.Id 'after variable editor close and save'
  } else {
    Log 'keeping variable editor open by parameter; persistence verification will scan with editor still open'
  }

  $localReopenClipboardPath = ''
  $localReopenClipboardText = ''
  if ($AuditPersistence -and $localRows.Count -gt 0) {
    $verifyForm = Ensure-VariableEditorOpen $process $projectNeedle
    Set-CapsLockState $false ([IntPtr]$verifyForm.Current.NativeWindowHandle) '*变量编辑*' 'local reopen verification'
    $verifyForm = Select-VariableTabByAid $verifyForm '_tabPageLocal' 'local tab reopen verification'
    Select-LocalProgram $verifyForm $LocalProgramName
    $verifyForm = Get-VariableForm $process.Id
    $localReopenClipboardText = Copy-VariableGridText $verifyForm '_tabPageLocal' 'local variables reopen verification'
    $localReopenClipboardPath = Join-Path $OutDir 'local_variables_reopen_clipboard.txt'
    Set-Content -LiteralPath $localReopenClipboardPath -Value $localReopenClipboardText -Encoding UTF8
    Assert-NamesInCopiedText $localReopenClipboardText $definedLocalNames 'local variables after close/reopen' $localReopenClipboardPath
    Save-Shot '05_after_local_reopen_verification.png'
    if (-not $KeepVariableEditorOpen) {
      Close-VariableEditor $process.Id
      Start-Sleep -Milliseconds 500
      Save-Project $process $projectNeedle
    }
  }

  $globalFileScan = [pscustomobject]@{
    Ok = $true
    Missing = @()
    Matches = @{}
    Skipped = (-not $AuditProjectTextScan)
  }
  if ($AuditProjectTextScan) {
    $globalFileScan = Test-ProjectHasNames $projectRoot $definedGlobalNames
  }
  if (-not $globalFileScan.Ok) {
    $scanPath = Join-Path $OutDir 'variable_persistence_failed_scan.json'
    $globalFileScan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $scanPath -Encoding UTF8
    Fail-Guard 'KV_GLOBAL_VARIABLE_PASTE_NOT_PERSISTED' 'variable persistence verification' "Global variable definition verification failed after save. Missing names: $($globalFileScan.Missing -join ', ')" @($scanPath)
  }
  $requiredNames = @($definedGlobalNames + $definedLocalNames | Where-Object { $_ } | Select-Object -Unique)
  $validation = [pscustomobject]@{
    Ok = $true
    Basis = if ($AuditPersistence) { 'variable editor route completed without modal; local executable names were verified by closing/reopening the variable editor, selecting the same program, copying the local grid text, and matching expected names' } else { 'fast variable editor route completed without modal; variable correctness is completed by the later compile gate unless audit flags are enabled' }
    RequiredNames = $requiredNames
    GlobalNames = $definedGlobalNames
    LocalNames = $definedLocalNames
    GlobalVariableFileScanOk = $globalFileScan.Ok
    LocalVariableValidationBasis = if ($AuditPersistence) { 'guarded close/reopen/copy verification from the KV STUDIO local-variable grid' } else { 'fast mode: local persistence is deferred to compile gate unless AuditPersistence is enabled' }
    LocalReopenClipboardPath = $localReopenClipboardPath
    LocalReopenClipboardContainsExpectedNames = if ($AuditPersistence -and $localRows.Count -gt 0) { $true } else { $null }
    LocalPasteRoute = if ($localRows.Count -gt 0) { "local tab -> $LocalProgramName -> Tab -> PgDn -> Ctrl+V" } else { 'skipped: no executable local variables' }
    ScreenshotAfterLocalPaste = if ($localRows.Count -gt 0) { (Join-Path $OutDir '02_after_local_paste.png') } else { '' }
    ProjectFileScan = $globalFileScan
  }
  $validation | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutDir 'variable_persistence_validation.json') -Encoding UTF8

  [pscustomobject]@{
    Ok = $true
    ProjectPath = $ProjectPath
    ProjectRoot = $projectRoot
    RequiredNames = $requiredNames
    VariableDefinitionCheckOk = $true
    GlobalVariableFileScanOk = $globalFileScan.Ok
    AuditPersistence = [bool]$AuditPersistence
    AuditProjectTextScan = [bool]$AuditProjectTextScan
  } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'set_variables_result.json') -Encoding UTF8
  Log 'done set variables'
} catch {
  Log ('ERROR ' + $_.Exception.ToString())
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  $errorCode = if ($script:LastErrorCode) { $script:LastErrorCode } else { 'KV_VARIABLE_STEP_FAILED' }
  $currentStep = if ($script:LastErrorStep) { $script:LastErrorStep } else { 'set_variables' }
  [pscustomobject]@{
    ok = $false
    error_code = $errorCode
    operation = 'set KV STUDIO variables'
    current_step = $currentStep
    message = $_.Exception.Message
    evidence = @($script:LastErrorEvidence + @((Join-Path $OutDir 'fail.txt')) | Where-Object { $_ })
    remediation = @(
      'Do not send any keyboard input until the checkpoint foreground_before.hwnd equals the KvVariableForm target hwnd.',
      'Inspect checkpoints under artifacts/set_variables/checkpoints to identify the foreground owner.',
      'If foreground recovery failed, close interfering modal/window or restart from the previous safe harness checkpoint.'
    )
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'set_variables_result.json') -Encoding UTF8
  exit 1
}
