param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [Parameter(Mandatory=$true)]
  [string]$FbModuleName,

  [Parameter(Mandatory=$true)]
  [string]$ArgumentsTsv,

  [string]$ChecklistPath = '',

  [Parameter(Mandatory=$true)]
  [string]$OutDir
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$script:LastErrorCode = ''
$script:LastErrorStep = ''
$script:LastErrorEvidence = @()

$sharedUiGuard = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'guards\kv_ui_guard.ps1'
if (-not (Test-Path -LiteralPath $sharedUiGuard)) { throw "Shared KV UI guard script not found: $sharedUiGuard" }
. $sharedUiGuard
Initialize-KvUiGuard -OutDir $OutDir -CheckpointSubdir 'fb_arg_ui'

$operatorScriptRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$variableDefinitionLib = Join-Path $operatorScriptRoot 'kv_variable_definition_lib.ps1'
if (-not (Test-Path -LiteralPath $variableDefinitionLib)) { throw "KV variable definition library not found: $variableDefinitionLib" }
. $variableDefinitionLib

$checklistGuard = Join-Path $operatorScriptRoot 'assert_kv_operation_checklist.ps1'
if (-not (Test-Path -LiteralPath $checklistGuard)) { throw "Checklist guard script not found: $checklistGuard" }
$global:LASTEXITCODE = 0
& $checklistGuard -ChecklistPath $ChecklistPath -SearchRoots @($OutDir, $ProjectPath, $ArgumentsTsv) -OperationName 'set KV STUDIO function-block arguments' | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Log([string]$Message) {
  $line = (Get-Date -Format s) + ' ' + $Message + [Environment]::NewLine
  [IO.File]::AppendAllText((Join-Path $OutDir 'run.log'), $line, [Text.Encoding]::UTF8)
}

function New-Utf16Text([int[]]$CodePoints) {
  -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Fail-Step([string]$ErrorCode, [string]$Step, [string]$Message, [string[]]$Evidence = @()) {
  $script:LastErrorCode = $ErrorCode
  $script:LastErrorStep = $Step
  $script:LastErrorEvidence = @($Evidence | Where-Object { $_ })
  throw "[$ErrorCode] $Message"
}

function Get-VisibleKvsProcess([string]$ProjectNeedle, [int]$WaitSeconds = 10) {
  $deadline = (Get-Date).AddSeconds($WaitSeconds)
  do {
    $process = Get-Process Kvs -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowTitle -like "*$ProjectNeedle*" } |
      Sort-Object StartTime -Descending |
      Select-Object -First 1
    if ($process) { return $process }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Restore-KvForeground([System.Diagnostics.Process]$Process, [string]$ProjectNeedle, [string]$Step) {
  for ($i = 1; $i -le 10; $i++) {
    [void](Invoke-KvUiGuardForceForeground -TargetHwnd ([IntPtr]$Process.MainWindowHandle))
    $snapshot = Get-KvForegroundSnapshot
    if ($snapshot.title -like 'KV STUDIO*' -and $snapshot.title -like "*$ProjectNeedle*" -and -not [KvSharedUiGuardWin32]::IsIconic($Process.MainWindowHandle)) { return }
  }
  Fail-Step 'KV_FOCUS_LOST' $Step "KV STUDIO target project is not foreground after 10 attempts. title=$($snapshot.title)" @()
}

function Find-DescByAid($RootElement, [string]$AutomationId) {
  $RootElement.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $AutomationId))
  )
}

function Test-FiniteRect($Rect) {
  if ($null -eq $Rect) { return $false }
  foreach ($value in @($Rect.X, $Rect.Y, $Rect.Width, $Rect.Height)) {
    if ([double]::IsNaN([double]$value) -or [double]::IsInfinity([double]$value)) { return $false }
  }
  return $true
}

function ConvertTo-SafeInt([double]$Value) {
  if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) { return 0 }
  if ($Value -gt [int]::MaxValue) { return [int]::MaxValue }
  if ($Value -lt [int]::MinValue) { return [int]::MinValue }
  return [int]$Value
}

function FindProjectModuleTreeItem([int]$ProcessIdValue, [string]$ModuleName) {
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $tree = $root.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.AndCondition(
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessIdValue)),
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'ProjectTreeView'))
    ))
  )
  if (-not $tree) { return $null }
  $items = $tree.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::TreeItem))
  )
  for ($i = 0; $i -lt $items.Count; $i++) {
    $item = $items.Item($i)
    $name = [string]$item.Current.Name
    if ($name -eq $ModuleName -or
        $name -match ('^' + [regex]::Escape($ModuleName) + '\s+\[\d+\]$') -or
        $name.StartsWith($ModuleName + ':', [System.StringComparison]::Ordinal) -or
        $name.StartsWith($ModuleName + [char]0xFF1A, [System.StringComparison]::Ordinal)) {
      return $item
    }
  }
  return $null
}

function Convert-UiaPointToPhysicalScreen([int]$ProcessIdValue, [double]$X, [double]$Y) {
  $screen = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $window = $root.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.AndCondition(
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessIdValue)),
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window))
    ))
  )
  if (-not $window) { return [pscustomobject]@{ x = [int]$X; y = [int]$Y; scale = 1.0 } }
  $rect = $window.Current.BoundingRectangle
  $scaleX = if ($rect.Width -gt $screen.Width -and $rect.Width -gt 0) { [double]$screen.Width / [double]$rect.Width } else { 1.0 }
  $scaleY = if ($rect.Height -gt $screen.Height -and $rect.Height -gt 0) { [double]$screen.Height / [double]$rect.Height } else { 1.0 }
  [pscustomobject]@{
    x = [int][math]::Round($X * $scaleX)
    y = [int][math]::Round($Y * $scaleY)
    scale = [math]::Min($scaleX, $scaleY)
  }
}

function Bring-ProjectTreeItemIntoView($Item, [int]$ProcessIdValue) {
  if (-not $Item) { return }
  try {
    $scrollItem = $null
    if ($Item.TryGetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern, [ref]$scrollItem)) {
      $scrollItem.ScrollIntoView()
    }
  } catch {}
  try {
    $tree = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessIdValue)),
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'ProjectTreeView'))
      ))
    )
    $scroll = $null
    if ($tree -and $tree.TryGetCurrentPattern([System.Windows.Automation.ScrollPattern]::Pattern, [ref]$scroll)) {
      for ($n = 0; $n -lt 12; $n++) {
        $r = $Item.Current.BoundingRectangle
        if ($r.Y -ge 0 -and ($r.Y + $r.Height) -le [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Bottom) { break }
        $scroll.Scroll([System.Windows.Automation.ScrollAmount]::NoAmount, [System.Windows.Automation.ScrollAmount]::LargeIncrement)
        Start-Sleep -Milliseconds 100
      }
    }
  } catch {}
}

function Move-FocusToProjectTreeItemByArrows($Tree, $TargetItem, [IntPtr]$MainHwnd, [string]$ProjectNeedle, [string]$ModuleName) {
  $items = @($Tree.FindAll([System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::TreeItem))))
  if (-not $items.Count) { return $false }
  $screenBottom = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Bottom
  $visible = @($items | Where-Object {
    $r = $_.Current.BoundingRectangle
    -not $_.Current.IsOffscreen -and $r.Height -ge 10 -and $r.Width -ge 10 -and $r.Y -ge 0 -and ($r.Y + $r.Height) -le $screenBottom
  })
  if (-not $visible.Count) { return $false }
  $targetIndex = -1
  for ($ti = 0; $ti -lt $items.Count; $ti++) {
    if ([string]$items[$ti].Current.Name -eq [string]$TargetItem.Current.Name) { $targetIndex = $ti; break }
  }
  if ($targetIndex -lt 0) { return $false }
  $start = $visible | Sort-Object { $_.Current.BoundingRectangle.Y } -Descending | Select-Object -First 1
  $startIndex = -1
  for ($si = 0; $si -lt $items.Count; $si++) {
    if ($items[$si].Current.Name -eq $start.Current.Name) { $startIndex = $si; break }
  }
  if ($startIndex -lt 0) { return $false }
  $sr = $start.Current.BoundingRectangle
  try {
    Invoke-KvGuardedMouseClick -TargetHwnd $MainHwnd -Step "focus visible FB tree neighbor" -X ([int]($sr.X + [math]::Min(100, $sr.Width / 2))) -Y ([int]($sr.Y + $sr.Height / 2)) -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -SleepMs 100
  } catch { try { $start.SetFocus() } catch { return $false } }
  Start-Sleep -Milliseconds 150
  $directionVk = if ($targetIndex -ge $startIndex) { 0x28 } else { 0x26 }
  $remaining = [math]::Min(240, [math]::Abs($targetIndex - $startIndex) + 8)
  for ($i = 0; $i -lt $remaining; $i++) {
    $currentTarget = FindProjectModuleTreeItem ([int]$Tree.Current.ProcessId) $ModuleName
    if ($currentTarget) {
      $tr = $currentTarget.Current.BoundingRectangle
      if (-not $currentTarget.Current.IsOffscreen -and $tr.Y -ge 0 -and ($tr.Y + $tr.Height) -le ($screenBottom - 30) -and $tr.Height -ge 10) {
        try { $currentTarget.SetFocus() } catch {}
        return $true
      }
    }
    $focused = [System.Windows.Automation.AutomationElement]::FocusedElement
    $name = if ($focused) { [string]$focused.Current.Name } else { '' }
    if ($name -eq $ModuleName -or $name.StartsWith($ModuleName + ':', [System.StringComparison]::Ordinal) -or $name.StartsWith($ModuleName + [char]0xFF1A, [System.StringComparison]::Ordinal)) {
      return $true
    }
    Invoke-KvGuardedVkTap -TargetHwnd $MainHwnd -Step "navigate FB tree arrow $($i + 1) $ModuleName" -Vk $directionVk -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -SleepMs 55
  }
  return $false
}

function Write-ProcessWindowDump([int]$ProcessIdValue, [string]$FileName) {
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $items = $root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessIdValue))
  )
  $rows = @()
  for ($i = 0; $i -lt $items.Count -and $i -lt 1200; $i++) {
    $item = $items.Item($i)
    $rect = $item.Current.BoundingRectangle
    $rows += [pscustomobject]@{
      idx = $i
      name = [string]$item.Current.Name
      automation_id = [string]$item.Current.AutomationId
      control_type = [string]$item.Current.ControlType.ProgrammaticName
      class_name = [string]$item.Current.ClassName
      hwnd = [int64]$item.Current.NativeWindowHandle
      is_offscreen = [bool]$item.Current.IsOffscreen
      x = ConvertTo-SafeInt $rect.X
      y = ConvertTo-SafeInt $rect.Y
      width = ConvertTo-SafeInt $rect.Width
      height = ConvertTo-SafeInt $rect.Height
    }
  }
  $path = Join-Path $OutDir $FileName
  $rows | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Get-UiaElementValueText($Element) {
  if (-not $Element) { return '' }
  try {
    $pattern = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
      return [string]$pattern.Current.Value
    }
  } catch {}
  return ''
}

function Write-ElementDescendantDump($Element, [string]$FileName) {
  $items = $Element.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $rows = @()
  $rootRect = $Element.Current.BoundingRectangle
  $rows += [pscustomobject]@{
    idx = -1
    name = [string]$Element.Current.Name
    automation_id = [string]$Element.Current.AutomationId
    control_type = [string]$Element.Current.ControlType.ProgrammaticName
    class_name = [string]$Element.Current.ClassName
    value = Get-UiaElementValueText $Element
    hwnd = [int64]$Element.Current.NativeWindowHandle
    is_keyboard_focusable = [bool]$Element.Current.IsKeyboardFocusable
    has_keyboard_focus = [bool]$Element.Current.HasKeyboardFocus
    is_offscreen = [bool]$Element.Current.IsOffscreen
    x = ConvertTo-SafeInt $rootRect.X
    y = ConvertTo-SafeInt $rootRect.Y
    width = ConvertTo-SafeInt $rootRect.Width
    height = ConvertTo-SafeInt $rootRect.Height
  }
  for ($i = 0; $i -lt $items.Count -and $i -lt 1200; $i++) {
    $item = $items.Item($i)
    $rect = $item.Current.BoundingRectangle
    $rows += [pscustomobject]@{
      idx = $i
      name = [string]$item.Current.Name
      automation_id = [string]$item.Current.AutomationId
      control_type = [string]$item.Current.ControlType.ProgrammaticName
      class_name = [string]$item.Current.ClassName
      value = Get-UiaElementValueText $item
      hwnd = [int64]$item.Current.NativeWindowHandle
      is_keyboard_focusable = [bool]$item.Current.IsKeyboardFocusable
      has_keyboard_focus = [bool]$item.Current.HasKeyboardFocus
      is_offscreen = [bool]$item.Current.IsOffscreen
      x = ConvertTo-SafeInt $rect.X
      y = ConvertTo-SafeInt $rect.Y
      width = ConvertTo-SafeInt $rect.Width
      height = ConvertTo-SafeInt $rect.Height
    }
  }
  $path = Join-Path $OutDir $FileName
  $rows | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Assert-FbArgumentFormTarget($Form, [string]$FbName) {
  $combo = Find-DescByAid $Form '_comboBoxFuncBlock'
  if (-not $combo) {
    $dump = Write-ElementDescendantDump $Form 'fb_argument_form_missing_fb_combo.json'
    Fail-Step 'KV_FB_ARGUMENT_FB_COMBO_MISSING' 'verify FB argument form target' 'Function-block argument form does not expose _comboBoxFuncBlock.' @($dump)
  }
  $value = (Get-UiaElementValueText $combo).Trim()
  if (-not $value) {
    $dump = Write-ElementDescendantDump $Form 'fb_argument_form_empty_fb_combo.json'
    Fail-Step 'KV_FB_ARGUMENT_FB_COMBO_EMPTY' 'verify FB argument form target' "Function-block argument form did not expose a selected FB name before paste. expected=$FbName" @($dump)
  }
  if ($value -ne $FbName) {
    $dump = Write-ElementDescendantDump $Form 'fb_argument_form_wrong_fb_combo.json'
    Fail-Step 'KV_FB_ARGUMENT_FB_COMBO_MISMATCH' 'verify FB argument form target' "Function-block argument form target mismatch. expected=$FbName actual=$value" @($dump)
  }
}

function Find-FbArgumentSurface([int]$ProcessIdValue) {
  # KV STUDIO 12 hosts the FB self-variable editor inside the main editor
  # window.  It is not a top-level dialog, so do not treat absence of a
  # separate window as absence of the argument table.
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $surface = $root.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.AndCondition(
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessIdValue)),
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'FuncBlockParamVariableControl'))
    ))
  )
  if (-not $surface -or $surface.Current.IsOffscreen) { return $null }
  $grid = Find-DescByAid $surface '_grid'
  if (-not $grid -or $grid.Current.IsOffscreen) { return $null }
  return $surface
}

function Wait-FbArgumentSurface([int]$ProcessIdValue, [int]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $surface = Find-FbArgumentSurface $ProcessIdValue
    if ($surface) { return $surface }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Assert-FbArgumentSurfaceTarget($Surface, [int]$ProcessIdValue, [IntPtr]$MainHwnd, [string]$FbName) {
  if (-not $Surface) { Fail-Step 'KV_FB_ARGUMENT_SURFACE_MISSING' 'verify embedded FB argument target' 'Embedded function-block argument surface is missing.' @() }
  $grid = Find-DescByAid $Surface '_grid'
  if (-not $grid) {
    $dump = Write-ElementDescendantDump $Surface 'fb_argument_surface_missing_grid.json'
    Fail-Step 'KV_FB_ARGUMENT_GRID_MISSING' 'verify embedded FB argument target' 'Embedded function-block argument surface does not expose _grid.' @($dump)
  }
  $tabNeedle = New-Utf16Text @(0x81EA,0x53D8,0x91CF)
  # The tab item is a sibling of FuncBlockParamVariableControl in KV STUDIO's
  # UIA tree, rather than a descendant of it.  Verify it in the same target
  # process; do not weaken this to a global name lookup.
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $selfVariableTab = $root.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.AndCondition(
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessIdValue)),
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $tabNeedle)),
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::TabItem))
    ))
  )
  if (-not $selfVariableTab) {
    $dump = Write-ElementDescendantDump $Surface 'fb_argument_surface_missing_self_variable_tab.json'
    Fail-Step 'KV_FB_ARGUMENT_TAB_MISSING' 'verify embedded FB argument target' 'Embedded function-block editor does not expose its self-variable tab.' @($dump)
  }
  # The FB was selected in ProjectTreeView immediately before the command that
  # exposed this surface.  Keep the main project window as the sole input
  # owner: an embedded pane has no foreground window of its own.
  if ($MainHwnd -eq [IntPtr]::Zero) { Fail-Step 'KV_TARGET_WINDOW_MISSING' 'verify embedded FB argument target' "Target KV STUDIO window is missing for $FbName." @() }
}

function Get-TopLevelWindowsForProcess([int]$ProcessIdValue) {
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $windows = $root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.AndCondition(
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessIdValue)),
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window))
    ))
  )
  $result = [System.Collections.Generic.List[object]]::new()
  for ($i = 0; $i -lt $windows.Count; $i++) { $result.Add($windows.Item($i)) }
  @($result)
}

function Get-ElementTextLines($Element) {
  $children = $Element.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $lines = [System.Collections.Generic.List[string]]::new()
  if ($Element.Current.Name) { $lines.Add([string]$Element.Current.Name) }
  for ($i = 0; $i -lt $children.Count; $i++) {
    $name = [string]$children.Item($i).Current.Name
    if ($name) { $lines.Add($name) }
  }
  @($lines)
}

function Get-KvsModalErrorCode([string]$Text) {
  $pasteDataErrorNeedle = New-Utf16Text @(0x7C98,0x8D34,0x6570,0x636E,0x4E2D,0x5B58,0x5728,0x9519,0x8BEF)
  $pasteSkippedNeedle = New-Utf16Text @(0x5DF2,0x8DF3,0x8FC7,0x90E8,0x5206,0x6570,0x636E,0x7C98,0x8D34)
  $variableNameChangedNeedle = New-Utf16Text @(0x53D8,0x91CF,0x540D,0x88AB,0x66F4,0x6539)
  $overwriteNeedle = New-Utf16Text @(0x8981,0x8986,0x76D6,0x5417)
  if ($Text -like "*$pasteDataErrorNeedle*" -or $Text -like "*$pasteSkippedNeedle*") { return 'KV_FB_ARGUMENT_PASTE_DATA_ERROR' }
  if ($Text -like "*$variableNameChangedNeedle*" -or $Text -like "*$overwriteNeedle*") { return 'KV_FB_ARGUMENT_OVERWRITE_CONFIRMATION' }
  return 'KV_MODAL_PRESENT'
}

function Find-KvsModal([int]$ProcessIdValue) {
  foreach ($window in (Get-TopLevelWindowsForProcess $ProcessIdValue)) {
    $className = [string]$window.Current.ClassName
    $windowName = [string]$window.Current.Name
    $automationId = [string]$window.Current.AutomationId
    if (($className -eq '#32770' -and $windowName -eq 'KV STUDIO') -or $automationId -eq 'PasteConfirmationForm') {
      return $window
    }
  }
  return $null
}

function Write-KvsModalText($Modal, [string]$Stage) {
  $text = (Get-ElementTextLines $Modal) -join "`n"
  $safe = $Stage -replace '[^A-Za-z0-9_.-]+', '_'
  $textPath = Join-Path $OutDir "modal_text_$safe.txt"
  Set-Content -LiteralPath $textPath -Value $text -Encoding UTF8
  [pscustomobject]@{
    text = $text
    path = $textPath
    code = Get-KvsModalErrorCode $text
    hwnd = [IntPtr]$Modal.Current.NativeWindowHandle
  }
}

function Assert-NoKvsModal([int]$ProcessIdValue, [string]$Stage) {
  $modal = Find-KvsModal $ProcessIdValue
  if ($modal) {
    $info = Write-KvsModalText $modal $Stage
    Fail-Step ([string]$info.code) $Stage "KV STUDIO modal dialog detected. text=$($info.text)" @([string]$info.path)
  }
}

function ConvertTo-FbArgumentCheckboxPasteValue($Value) {
  $text = ([string]$Value).Trim()
  if ($text -match '^(?i:true|1|yes|on)$') { return 'True' }
  return ''
}

function Find-FbArgumentForm([int]$ProcessIdValue, [string]$ModuleName) {
  $selfVariableNeedle = New-Utf16Text @(0x81EA,0x53D8,0x91CF)
  $variableNeedle = New-Utf16Text @(0x53D8,0x91CF)
  foreach ($window in (Get-TopLevelWindowsForProcess $ProcessIdValue)) {
    $name = [string]$window.Current.Name
    $aid = [string]$window.Current.AutomationId
    if (($name -like "*$selfVariableNeedle*" -or $name -like "*$variableNeedle*") -and $name -notlike 'KV STUDIO*') { return $window }
    if ($aid -match '(?i)(argument|jik|variable|var)' -and $name -notlike 'KV STUDIO*') { return $window }
    if ($name -like '*自变量*' -or $name -like "*$ModuleName*" -and $name -notlike 'KV STUDIO*') { return $window }
  }
  return $null
}

function Wait-FbArgumentForm([int]$ProcessIdValue, [string]$ModuleName, [int]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $form = Find-FbArgumentForm $ProcessIdValue $ModuleName
    if ($form) { return $form }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Assert-FbArgumentFormForeground($Form, [string]$Step) {
  if (-not $Form) { Fail-Step 'KV_FB_ARGUMENT_FORM_MISSING' $Step 'Function-block argument form is missing.' @() }
  $targetHwnd = [IntPtr]$Form.Current.NativeWindowHandle
  if ($targetHwnd -eq [IntPtr]::Zero) { Fail-Step 'KV_FB_ARGUMENT_FORM_MISSING' $Step 'Function-block argument form has no native HWND.' @() }
  if ([KvSharedUiGuardWin32]::IsIconic($targetHwnd)) {
    [KvSharedUiGuardWin32]::ShowWindow($targetHwnd, 9) | Out-Null
  }
  [KvSharedUiGuardWin32]::SetForegroundWindow($targetHwnd) | Out-Null
  Start-Sleep -Milliseconds 160
  $snapshot = Get-KvForegroundSnapshot
  if ($snapshot.hwnd -ne $targetHwnd.ToInt64()) {
    Fail-Step 'KV_FOCUS_LOST' $Step "Function-block argument form is not foreground. title=$($snapshot.title) process=$($snapshot.process_name)" @()
  }
}

function Convert-FbArgumentRowsToPasteText([string]$Path, [string]$ExpectedOwner) {
  $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::Default)
  $rows = @($text | ConvertFrom-Csv -Delimiter "`t" | Where-Object { $_.status -ne 'display_name' -and $_.argument_name })
  if ($rows.Count -eq 0) { Fail-Step 'KV_FB_ARGUMENTS_EMPTY' 'preflight FB arguments' "No executable FB argument rows in $Path" @($Path) }
  $errors = [System.Collections.Generic.List[object]]::new()
  $allowedKinds = @('IN','OUT','IN-OUT')
  foreach ($row in $rows) {
    $name = ([string]$row.argument_name).Trim()
    $kind = ([string]$row.argument_kind).Trim().ToUpperInvariant()
    $dataType = ([string]$row.data_type).Trim()
    if ([string]$row.owner_program -ne $ExpectedOwner) {
      $errors.Add([pscustomobject]@{ code='KV_FB_ARGUMENT_OWNER_MISMATCH'; argument_name=$name; message="owner_program must be $ExpectedOwner" })
    }
    if (-not $name) {
      $errors.Add([pscustomobject]@{ code='KV_FB_ARGUMENT_NAME_MISSING'; argument_name=$name; message='argument_name is required' })
    }
    if (Test-KvSoftDeviceLikeVariableName $name) {
      $errors.Add([pscustomobject]@{ code='KV_FB_ARGUMENT_NAME_SOFT_DEVICE_CONFLICT'; argument_name=$name; message='argument name looks like a KV soft-device name' })
    }
    if ($allowedKinds -notcontains $kind) {
      $errors.Add([pscustomobject]@{ code='KV_FB_ARGUMENT_KIND_INVALID'; argument_name=$name; argument_kind=$kind; message='argument_kind must be IN, OUT, or IN-OUT' })
    }
    if (-not (Test-KvVariableDataType $dataType)) {
      $errors.Add([pscustomobject]@{ code='KV_FB_ARGUMENT_DATA_TYPE_UNSUPPORTED'; argument_name=$name; data_type=$dataType; message='data_type is outside supported KEYENCE type grammar' })
    }
  }
  if ($errors.Count -gt 0) {
    $evidencePath = Join-Path $OutDir 'fb_argument_definition_errors.json'
    $errors | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
    Fail-Step ([string]$errors[0].code) 'preflight FB arguments' ([string]$errors[0].message) @($Path, $evidencePath)
  }

  $lines = foreach ($row in $rows) {
    $constant = [string]$row.constant
    if (-not $constant) { $constant = 'False' }
    $retain = [string]$row.retain
    if (-not $retain) { $retain = 'False' }
    $hidden = [string]$row.hidden
    if (-not $hidden) { $hidden = 'False' }
    @(
      [string]$row.argument_name
      ([string]$row.argument_kind).Trim().ToUpperInvariant()
      $constant
      [string]$row.data_type
      [string]$row.default_value
      $retain
      $hidden
      [string]$row.comment1
      [string]$row.comment2
      [string]$row.comment3
      [string]$row.comment4
      [string]$row.comment5
      [string]$row.comment6
      [string]$row.comment7
      [string]$row.comment8
    ) -join "`t"
  }
  [pscustomobject]@{
    rows = $rows
    text = (($lines -join "`r`n") + "`r`n")
  }
}

function Get-ClipboardTextAfterCopy([string]$Sentinel, [int]$Seconds = 4) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    Start-Sleep -Milliseconds 200
    try {
      $text = [Windows.Forms.Clipboard]::GetText()
      if ($text -and $text -ne $Sentinel) { return $text }
    } catch {
      Log "clipboard read retry after FB argument copy: $($_.Exception.Message)"
    }
  } while ((Get-Date) -lt $deadline)
  return ''
}

function Test-FbArgumentPasteVisible([IntPtr]$FormHwnd, [string]$ProjectNeedle, [object[]]$ExpectedRows, [string]$FbName, [string]$AttemptName) {
  $sentinel = '__KV_FB_ARGUMENT_COPY_SENTINEL__'
  Invoke-KvGuardedClipboardSetText -TargetHwnd $FormHwnd -Step "FB arguments copy sentinel $AttemptName $FbName" -Text $sentinel -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*"
  Invoke-KvGuardedSendKeys -TargetHwnd $FormHwnd -Step "FB arguments Ctrl+A verify $AttemptName $FbName" -Keys '^a' -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -Action 'Ctrl+A selects embedded FB argument table for copy verification' -SleepMs 200
  Invoke-KvGuardedSendKeys -TargetHwnd $FormHwnd -Step "FB arguments Ctrl+C verify $AttemptName $FbName" -Keys '^c' -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -Action 'Ctrl+C copies embedded FB argument table for paste verification' -SleepMs 300
  $copied = Get-ClipboardTextAfterCopy $sentinel 5
  $copyPath = Join-Path $OutDir ("fb_arguments_copied_after_paste_$AttemptName.txt")
  Set-Content -LiteralPath $copyPath -Value $copied -Encoding UTF8
  $missing = @()
  $mismatch = @()
  $copiedByName = @{}
  foreach ($line in @($copied -split "\r?\n" | Where-Object { $_ -ne '' })) {
    $cells = $line.Split("`t", [System.StringSplitOptions]::None)
    if ($cells.Count -gt 0 -and $cells[0]) {
      $copiedByName[[string]$cells[0]] = $cells
    }
  }
  foreach ($row in @($ExpectedRows)) {
    $name = [string]$row.argument_name
    if (-not $name) { continue }
    if (-not $copiedByName.ContainsKey($name)) {
      $missing += $name
      continue
    }
    $cells = [string[]]$copiedByName[$name]
    $expectedKind = ([string]$row.argument_kind).Trim().ToUpperInvariant()
    $expectedType = ([string]$row.data_type).Trim()
    $actualKind = if ($cells.Count -gt 1) { [string]$cells[1] } else { '' }
    $actualType = if ($cells.Count -gt 3) { [string]$cells[3] } else { '' }
    if ($actualKind -ne $expectedKind -or $actualType -ne $expectedType) {
      $mismatch += "$name(kind=$actualKind expected=$expectedKind,type=$actualType expected=$expectedType)"
    }
  }
  [pscustomobject]@{
    ok = ($missing.Count -eq 0 -and $mismatch.Count -eq 0)
    copy_path = $copyPath
    missing = $missing
    mismatch = $mismatch
  }
}

function Focus-FbArgumentGrid($Surface, [IntPtr]$MainHwnd, [string]$ProjectNeedle, [string]$Label) {
  $grid = Find-DescByAid $Surface '_grid'
  if (-not $grid) {
    $dump = Write-ElementDescendantDump $Surface 'fb_argument_grid_focus_failed.json'
    Fail-Step 'KV_FB_ARGUMENT_GRID_MISSING' $Label 'Could not find the embedded FB argument grid before paste.' @($dump)
  }
  $rect = $grid.Current.BoundingRectangle
  if (-not (Test-FiniteRect $rect) -or $rect.Width -lt 140 -or $rect.Height -lt 60) {
    $dump = Write-ElementDescendantDump $Surface 'fb_argument_grid_invalid_bounds.json'
    Fail-Step 'KV_FB_ARGUMENT_GRID_BOUNDS_INVALID' $Label 'Embedded FB argument grid has invalid bounds before paste.' @($dump)
  }
  # First editable column is the argument name.  Return to the first row and
  # then step downward beyond any practical argument-table length.  Navigation
  # stops at the one blank append row; unlike Ctrl+End this uses KV's actual
  # row navigation semantics and cannot overwrite an existing row.
  $x = [int]($rect.X + 105)
  $y = [int]($rect.Y + 31)
  Invoke-KvGuardedMouseClick -TargetHwnd $MainHwnd -Step "$Label name-column cell click" -X $x -Y $y -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -SleepMs 160
  Invoke-KvGuardedSendKeys -TargetHwnd $MainHwnd -Step "$Label Ctrl+Home first argument" -Keys '^{HOME}' -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -Action 'Ctrl+Home returns the embedded FB argument grid to row one and the argument-name column' -SleepMs 140
  Invoke-KvGuardedSendKeys -TargetHwnd $MainHwnd -Step "$Label move to blank append row" -Keys '{DOWN 200}' -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -Action 'Down moves past existing FB argument rows and stops at the blank append row' -SleepMs 220
  Invoke-KvGuardedSendKeys -TargetHwnd $MainHwnd -Step "$Label Home name column" -Keys '{HOME}' -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -Action 'Home confirms the embedded FB argument grid is at its argument-name column' -SleepMs 140
}

function Invoke-FbArgumentPasteAttempt($Form, [IntPtr]$MainHwnd, [string]$ProjectNeedle, [string]$AttemptName, [string]$PasteText, [object[]]$ExpectedRows, [string]$FbName, [switch]$FocusGridFirst) {
  $formHwnd = $MainHwnd
  if ($FocusGridFirst) {
    Focus-FbArgumentGrid $Form $MainHwnd $ProjectNeedle "FB arguments $AttemptName $FbName"
  }
  Invoke-KvGuardedClipboardPaste -TargetHwnd $formHwnd -Step "FB arguments $AttemptName Ctrl+V $FbName" -Text $PasteText -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -SleepMs 500
  $modal = Find-KvsModal $process.Id
  if ($modal) {
    $modalInfo = Write-KvsModalText $modal "after FB argument $AttemptName paste"
    if ([string]$modalInfo.code -eq 'KV_FB_ARGUMENT_PASTE_DATA_ERROR') {
      Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd ([IntPtr]$modalInfo.hwnd) -Step "dismiss FB argument paste data error $FbName" -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO' -SuccessTitleLike @('*自变量*','*变量*') -Action 'Enter dismisses paste-data-error modal so the runner can copy partial table state' -SleepMs 400
      Assert-KvUiForegroundHwnd -ExpectedHwnd $formHwnd -Step "FB arguments partial-copy foreground $FbName" -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -AllowSingleRecovery | Out-Null
      $partial = Test-FbArgumentPasteVisible $formHwnd $ProjectNeedle $ExpectedRows $FbName ($AttemptName + '_partial_after_data_error')
      return [pscustomobject]@{
        ok = $false
        paste_data_error = $true
        modal_text_path = [string]$modalInfo.path
        copy_path = [string]$partial.copy_path
        missing = @($partial.missing)
        mismatch = @($partial.mismatch)
      }
    }
    Fail-Step ([string]$modalInfo.code) "after FB argument $AttemptName paste" "KV STUDIO modal dialog detected. text=$($modalInfo.text)" @([string]$modalInfo.path)
  }
  return (Test-FbArgumentPasteVisible $formHwnd $ProjectNeedle $ExpectedRows $FbName $AttemptName)
}

try {
  Log 'start set FB arguments'
  $ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
  $ArgumentsTsv = [IO.Path]::GetFullPath($ArgumentsTsv)
  if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "ProjectPath not found: $ProjectPath" }
  if (-not (Test-Path -LiteralPath $ArgumentsTsv -PathType Leaf)) { throw "ArgumentsTsv not found: $ArgumentsTsv" }
  $projectNeedle = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  $pastePayload = Convert-FbArgumentRowsToPasteText $ArgumentsTsv $FbModuleName
  $pastePath = Join-Path $OutDir 'fb_arguments_paste.tsv'
  [IO.File]::WriteAllText($pastePath, $pastePayload.text, [Text.Encoding]::Default)

  $process = Get-VisibleKvsProcess $projectNeedle 10
  if (-not $process) { Fail-Step 'KV_PROJECT_PROCESS_NOT_FOUND' 'find target KV STUDIO project' "No visible KV STUDIO process matched project needle '$projectNeedle'. Refusing to operate another project window." @() }
  Restore-KvForeground $process $projectNeedle 'set FB arguments start'
  Assert-NoKvsModal $process.Id 'before FB argument route'

  $item = FindProjectModuleTreeItem $process.Id $FbModuleName
  if (-not $item) {
    $dumpPath = Write-ProcessWindowDump $process.Id 'missing_fb_module_tree_item.json'
    Fail-Step 'KV_FB_MODULE_TREE_ITEM_MISSING' 'select FB module' "Function-block tree item was not found: $FbModuleName" @($dumpPath)
  }
  Bring-ProjectTreeItemIntoView $item $process.Id
  $itemRectAfterScroll = $item.Current.BoundingRectangle
  $treeForArrow = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.AndCondition(
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $process.Id)),
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'ProjectTreeView'))
    ))
  )
  $screenBottom = [System.Windows.Forms.Screen]::PrimaryScreen.WorkingArea.Bottom
  if ($itemRectAfterScroll.Y -lt 0 -or ($itemRectAfterScroll.Y + $itemRectAfterScroll.Height) -gt ($screenBottom - 30)) {
    if (-not (Move-FocusToProjectTreeItemByArrows $treeForArrow $item ([IntPtr]$process.MainWindowHandle) $projectNeedle $FbModuleName)) {
      $dumpPath = Write-ProcessWindowDump $process.Id 'fb_tree_arrow_navigation_failed.json'
      Fail-Step 'KV_FB_MODULE_TREE_NAVIGATION_FAILED' 'navigate to FB module' "Could not reach FB module '$FbModuleName' using tree arrow navigation." @($dumpPath)
    }
    $item = FindProjectModuleTreeItem $process.Id $FbModuleName
    if (-not $item) { Fail-Step 'KV_FB_MODULE_TREE_ITEM_MISSING' 'select FB module' "Function-block tree item disappeared while navigating: $FbModuleName" @() }
  } else {
    try { $item.SetFocus() } catch {}
  }
  # Re-read the virtualized row after navigation and invoke the context menu
  # from the selected tree item.  The tree may expose logical coordinates
  # larger than the physical desktop (DPI scaling); keyboard invocation avoids
  # sending a click outside the desktop while still honoring the user's
  # near-node + arrow navigation route.
  $rect = $item.Current.BoundingRectangle
  if ($rect.Y -lt 0 -or ($rect.Y + $rect.Height) -gt ($screenBottom + 200)) {
    $dumpPath = Write-ProcessWindowDump $process.Id 'fb_tree_target_still_out_of_view.json'
    Fail-Step 'KV_FB_MODULE_TREE_NAVIGATION_FAILED' 'navigate to FB module' "FB module '$FbModuleName' remained outside the reachable tree after arrow navigation." @($dumpPath)
  }
  try {
    $selectPattern = $null
    if ($item.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selectPattern)) { $selectPattern.Select() }
  } catch {}
  try { $item.SetFocus() } catch {}
  Start-Sleep -Milliseconds 180
  $rect = $item.Current.BoundingRectangle
  if ($rect.Width -lt 10 -or $rect.Height -lt 10) { Fail-Step 'KV_FB_MODULE_TREE_ITEM_BOUNDS_INVALID' 'select FB module' "Function-block tree item has invalid bounds: $FbModuleName" @() }
  if ($rect.Y -ge 0 -and $rect.Height -ge 10 -and $rect.Width -ge 10) {
    $physical = Convert-UiaPointToPhysicalScreen $process.Id ($rect.X + [math]::Min(100, [math]::Max(12, $rect.Width / 2))) ($rect.Y + ($rect.Height / 2))
    Invoke-KvGuardedMouseRightClick -TargetHwnd $process.MainWindowHandle -Step "FB module context menu $FbModuleName" -X $physical.x -Y $physical.y -ExpectedTitleLike "KV STUDIO*$projectNeedle*" -SleepMs 250
  } else {
    Invoke-KvGuardedSendKeys -TargetHwnd $process.MainWindowHandle -Step "FB module context menu $FbModuleName" -Keys '+{F10}' -ExpectedTitleLike "KV STUDIO*$projectNeedle*" -Action 'Shift+F10 opens the selected FB module context menu' -SleepMs 250
  }

  $fg = Get-KvForegroundSnapshot
  $menuTarget = if ([string]$fg.class_name -eq '#32768') { [IntPtr]$fg.hwnd } else { $process.MainWindowHandle }
  $menuTitle = if ([string]$fg.class_name -eq '#32768') { '*' } else { "KV STUDIO*$projectNeedle*" }
  Write-ProcessWindowDump $process.Id 'fb_context_menu_before_open_argument_table.json' | Out-Null
  Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $menuTarget -Step "open FB argument table by Z $FbModuleName" -Keys 'z' -ExpectedTitleLike $menuTitle -SuccessTitleLike @('*自变量*','*变量*',"KV STUDIO*$projectNeedle*") -Action 'press Z on FB context menu to open self-variable table' -SleepMs 900
  Start-Sleep -Milliseconds 500
  Assert-NoKvsModal $process.Id 'after FB argument table open'

  $form = Wait-FbArgumentSurface $process.Id 8
  if (-not $form) {
    $dumpPath = Write-ProcessWindowDump $process.Id 'missing_fb_argument_surface_after_z.json'
    Fail-Step 'KV_FB_ARGUMENT_SURFACE_MISSING' 'open FB argument table' "Embedded function-block argument surface did not appear after right-click Z for $FbModuleName." @($dumpPath)
  }
  $formDumpPath = Write-ElementDescendantDump $form 'fb_argument_surface_uia_before_paste.json'
  Assert-FbArgumentSurfaceTarget $form $process.Id ([IntPtr]$process.MainWindowHandle) $FbModuleName
  Start-Sleep -Milliseconds 700

  $attempts = [System.Collections.Generic.List[object]]::new()
  $visible = Invoke-FbArgumentPasteAttempt $form ([IntPtr]$process.MainWindowHandle) $projectNeedle 'embedded_grid_append_row' $pastePayload.text $pastePayload.rows $FbModuleName -FocusGridFirst
  $attempts.Add($visible)
  if (-not $visible.ok) {
    $evidence = @($formDumpPath)
    foreach ($attempt in @($attempts)) { if ($attempt.copy_path) { $evidence += [string]$attempt.copy_path } }
    Fail-Step 'KV_FB_ARGUMENT_PASTE_NOT_VISIBLE' 'verify FB argument paste' "FB argument paste was not visible in copyback. missing=$($visible.missing -join ','); mismatch=$($visible.mismatch -join ',')" $evidence
  }

  $formHwnd = [IntPtr]$process.MainWindowHandle
  Invoke-KvGuardedSendKeys -TargetHwnd $formHwnd -Step "save after FB arguments Ctrl+S $FbModuleName" -Keys '^s' -ExpectedTitleLike "KV STUDIO*$projectNeedle*" -Action 'Ctrl+S saves project after verified embedded FB argument paste' -SleepMs 500
  Assert-NoKvsModal $process.Id 'after FB argument save'

  [pscustomobject]@{
    ok = $true
    project_path = $ProjectPath
    fb_module_name = $FbModuleName
    arguments_tsv = $ArgumentsTsv
    paste_tsv = $pastePath
    uia_before_paste = $formDumpPath
    copyback_path = $visible.copy_path
    paste_attempts = @($attempts)
    argument_names = @($pastePayload.rows | ForEach-Object { [string]$_.argument_name })
    route = 'project tree select FB -> guarded right click -> Z -> embedded FuncBlockParamVariableControl/_grid -> Ctrl+Home then Down to blank append row -> Home name column -> Ctrl+V -> copyback verify -> Ctrl+S'
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'set_fb_arguments_result.json') -Encoding UTF8
  '0' | Set-Content -LiteralPath (Join-Path $OutDir 'exit_code.txt') -Encoding ASCII
  Log 'done set FB arguments'
} catch {
  Log ('ERROR ' + $_.Exception.ToString())
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  $errorCode = if ($script:LastErrorCode) { $script:LastErrorCode } else { 'KV_FB_ARGUMENT_STEP_FAILED' }
  $currentStep = if ($script:LastErrorStep) { $script:LastErrorStep } else { 'set_fb_arguments' }
  [pscustomobject]@{
    ok = $false
    error_code = $errorCode
    operation = 'set KV STUDIO function-block arguments'
    current_step = $currentStep
    message = $_.Exception.Message
    evidence = @($script:LastErrorEvidence + @((Join-Path $OutDir 'fail.txt')) | Where-Object { $_ })
    remediation = @(
      'Inspect same-run UIA dumps and modal_text files under this OutDir.',
      'If right-click Z does not expose FuncBlockParamVariableControl/_grid, inspect the target project UIA dump before changing the route.',
      'If KV reports paste data error, stop and repair arguments.tsv generation before any compile attempt.'
    )
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'set_fb_arguments_result.json') -Encoding UTF8
  '1' | Set-Content -LiteralPath (Join-Path $OutDir 'exit_code.txt') -Encoding ASCII
  exit 1
}
