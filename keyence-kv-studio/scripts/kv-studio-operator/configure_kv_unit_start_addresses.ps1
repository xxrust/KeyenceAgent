param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectName,
  [Parameter(Mandatory=$true)]
  [string]$UnitName,
  [int]$Slot = -1,
  [Parameter(Mandatory=$true)]
  [int]$FirstDm,
  [Parameter(Mandatory=$true)]
  [int]$FirstRelay,
  [string]$ProjectPath = '',
  [int]$MaxDurationSeconds = 60,
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
if ([string]::IsNullOrWhiteSpace($OutDir)) {
  $OutDir = Join-Path (Join-Path ([IO.Path]::GetTempPath()) 'kv-studio-operator') 'kv_unit_address_runs'
}
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms

if (-not ('KvUnitAddressWin32' -as [type])) {
  Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class KvUnitAddressWin32 {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr hWnd);
}
"@
}

$BM_CLICK = 0x00F5
$WM_CLOSE = 0x0010
$NameUnitEditor = (-join ([char[]](0x5355,0x5143,0x7F16,0x8F91,0x5668))) + '*'
$NameConfirm = -join ([char[]](0x786E,0x5B9A))
$NameConvertResult = -join ([char[]](0x8F6C,0x6362,0x7ED3,0x679C))
$LabelFirstDm = -join ([char[]](0x9996,0x0020,0x0044,0x004D,0x0020,0x7F16,0x53F7))
$LabelRelayPrefix = -join ([char[]](0x9996,0x7EE7,0x7535,0x5668,0x7F16,0x53F7))

function New-EvidencePath([string]$Name) {
  Join-Path $OutDir ("{0}_{1}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), $Name)
}

function Write-JsonFile([string]$Path, $Value) {
  $Value | ConvertTo-Json -Depth 18 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Assert-TimeBudget([Diagnostics.Stopwatch]$Stopwatch, [string]$Step) {
  if ($Stopwatch.Elapsed.TotalSeconds -gt $MaxDurationSeconds) {
    throw "KV_UNIT_ADDRESS_TIMEOUT: step '$Step' exceeded MaxDurationSeconds=$MaxDurationSeconds elapsed=$([math]::Round($Stopwatch.Elapsed.TotalSeconds, 3))"
  }
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
  $callback = [KvUnitAddressWin32+EnumWindowsProc]{
    param($handle, $lParam)
    if ([KvUnitAddressWin32]::IsWindowVisible($handle)) {
      $titleBuilder = [Text.StringBuilder]::new(512)
      $classBuilder = [Text.StringBuilder]::new(256)
      [void][KvUnitAddressWin32]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity)
      [void][KvUnitAddressWin32]::GetClassName($handle, $classBuilder, $classBuilder.Capacity)
      $procIdValue = [uint32]0
      [void][KvUnitAddressWin32]::GetWindowThreadProcessId($handle, [ref]$procIdValue)
      [void]$rows.Add([pscustomobject]@{
        hwnd = $handle.ToInt64()
        process_id = [int]$procIdValue
        title = $titleBuilder.ToString()
        class_name = $classBuilder.ToString()
      })
    }
    return $true
  }
  [void][KvUnitAddressWin32]::EnumWindows($callback, [IntPtr]::Zero)
  @($rows)
}

function Get-KvRelevantWindows {
  $process = Get-KvsProcess
  Get-VisibleTopWindows | Where-Object {
    $_.process_id -eq $process.Id -and (
      $_.title -like 'KV STUDIO*' -or
      $_.title -like $NameUnitEditor -or
      $_.class_name -eq '#32770'
    )
  } | Sort-Object title, hwnd
}

function Wait-TopWindow([scriptblock]$Predicate, [int]$TimeoutMs = 8000) {
  $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
  do {
    foreach ($window in @(Get-KvRelevantWindows)) {
      if (& $Predicate $window) { return $window }
    }
    Start-Sleep -Milliseconds 160
  } while ((Get-Date) -lt $deadline)
  $null
}

function Close-StaleConvertResultDialogs {
  $closed = @()
  foreach ($window in @(Get-KvRelevantWindows | Where-Object { $_.title -eq $NameConvertResult })) {
    [void][KvUnitAddressWin32]::PostMessage([IntPtr]$window.hwnd, $WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
    $closed += $window
    Start-Sleep -Milliseconds 300
  }
  $closed
}

function Get-ElementFromHwnd([long]$Hwnd) {
  $element = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
  if (-not $element) { throw "AutomationElement.FromHandle failed for $Hwnd." }
  $element
}

function Get-MainWindowElement {
  $process = Get-KvsProcess
  Get-ElementFromHwnd -Hwnd $process.MainWindowHandle
}

function Find-Descendant {
  param(
    [Windows.Automation.AutomationElement]$Root,
    [scriptblock]$Predicate
  )
  $all = $Root.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
  for ($i = 0; $i -lt $all.Count; $i++) {
    $element = $all.Item($i)
    if (& $Predicate $element) { return $element }
  }
  $null
}

function Find-TreeItemInMain {
  param([string]$UnitName, [int]$Slot)
  $main = Get-MainWindowElement
  Find-Descendant -Root $main -Predicate {
    param($element)
    try {
      if ($element.Current.ControlType.ProgrammaticName -ne 'ControlType.TreeItem') { return $false }
      $name = $element.Current.Name
      if (-not $name.Contains($UnitName)) { return $false }
      if ($Slot -ge 0 -and -not $name.TrimStart().StartsWith("[$Slot]")) { return $false }
      $true
    } catch {
      $false
    }
  }
}

function Set-ForegroundWindowByHwnd([long]$Hwnd) {
  if ([KvUnitAddressWin32]::IsIconic([IntPtr]$Hwnd)) {
    [void][KvUnitAddressWin32]::ShowWindow([IntPtr]$Hwnd, 9)
  }
  [void][KvUnitAddressWin32]::SetForegroundWindow([IntPtr]$Hwnd)
  Start-Sleep -Milliseconds 180
}

function Send-EnterToElement([Windows.Automation.AutomationElement]$Element) {
  $pattern = $null
  if ($Element.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern, [ref]$pattern)) {
    try { $pattern.ScrollIntoView() } catch {}
  }
  $pattern = $null
  if ($Element.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
    try { $pattern.Select(); Start-Sleep -Milliseconds 100 } catch {}
  }
  $Element.SetFocus()
  Start-Sleep -Milliseconds 120
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Start-Sleep -Milliseconds 800
}

function Open-UnitEditorFromTargetUnit {
  param([Diagnostics.Stopwatch]$Stopwatch)
  $existing = Wait-TopWindow -TimeoutMs 500 -Predicate { param($w) $w.title -like $NameUnitEditor -and $w.class_name -like 'Afx:*' }
  if ($existing) {
    throw 'KV_UNIT_ADDRESS_EDITOR_ALREADY_OPEN: close the existing unit editor before running the target-unit direct route.'
  }
  $item = Find-TreeItemInMain -UnitName $UnitName -Slot $Slot
  if (-not $item) { throw "KV_UNIT_ADDRESS_TARGET_NOT_FOUND: unit '$UnitName' slot=$Slot was not found in the project tree." }
  $itemName = $item.Current.Name
  Set-ForegroundWindowByHwnd -Hwnd (Get-KvsProcess).MainWindowHandle
  Send-EnterToElement -Element $item
  Assert-TimeBudget -Stopwatch $Stopwatch -Step 'wait unit editor'
  $editor = Wait-TopWindow -TimeoutMs 8000 -Predicate { param($w) $w.title -like $NameUnitEditor -and $w.class_name -like 'Afx:*' }
  if (-not $editor) { throw "KV_UNIT_ADDRESS_EDITOR_NOT_OPENED: pressing Enter on '$itemName' did not open the unit editor." }
  [pscustomobject]@{ reused_existing = $false; tree_item = $itemName; window = $editor }
}

function Get-DescendantByAutomationId {
  param([Windows.Automation.AutomationElement]$Root, [string]$AutomationId)
  Find-Descendant -Root $Root -Predicate {
    param($element)
    try { $element.Current.AutomationId -eq $AutomationId } catch { $false }
  }
}

function Get-ElementText([Windows.Automation.AutomationElement]$Element) {
  if (-not $Element) { return '' }
  $valuePattern = $null
  if ($Element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern, [ref]$valuePattern)) {
    try { return [string]$valuePattern.Current.Value } catch {}
  }
  try { return [string]$Element.Current.Name } catch {}
  ''
}

function Get-CurrentSettingRow {
  param([Windows.Automation.AutomationElement]$EditorElement)
  $target = Get-DescendantByAutomationId -Root $EditorElement -AutomationId '703'
  $label = Get-DescendantByAutomationId -Root $EditorElement -AutomationId '502'
  $value = Get-DescendantByAutomationId -Root $EditorElement -AutomationId '500'
  $descLabel = Get-DescendantByAutomationId -Root $EditorElement -AutomationId '698'
  $desc = Get-DescendantByAutomationId -Root $EditorElement -AutomationId '697'
  [pscustomobject]@{
    target = Get-ElementText -Element $target
    label = Get-ElementText -Element $label
    value = Get-ElementText -Element $value
    value_has_focus = $(if ($value) { try { $value.Current.HasKeyboardFocus } catch { $false } } else { $false })
    description_label = Get-ElementText -Element $descLabel
    description = Get-ElementText -Element $desc
  }
}

function Assert-TargetSelected {
  param($Row)
  if (-not $Row.target.Contains($UnitName)) {
    throw "KV_UNIT_ADDRESS_TARGET_DRIFT: expected selected unit '$UnitName', got '$($Row.target)'."
  }
  if ($Slot -ge 0 -and -not $Row.target.TrimStart().StartsWith("[$Slot]")) {
    throw "KV_UNIT_ADDRESS_SLOT_DRIFT: expected slot [$Slot], got '$($Row.target)'."
  }
}

function Enter-CurrentValueCell {
  param([Windows.Automation.AutomationElement]$EditorElement)
  $row = Get-CurrentSettingRow -EditorElement $EditorElement
  Assert-TargetSelected -Row $row
  if ($row.value_has_focus) { return $row }
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Start-Sleep -Milliseconds 260
  $row = Get-CurrentSettingRow -EditorElement $EditorElement
  Assert-TargetSelected -Row $row
  if (-not $row.value_has_focus) {
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Start-Sleep -Milliseconds 260
    $row = Get-CurrentSettingRow -EditorElement $EditorElement
    Assert-TargetSelected -Row $row
  }
  if (-not $row.value_has_focus) { throw "KV_UNIT_ADDRESS_VALUE_CELL_NOT_FOCUSED: label='$($row.label)' value='$($row.value)'." }
  $row
}

function Type-CurrentValue([string]$ValueText) {
  [System.Windows.Forms.SendKeys]::SendWait('^a')
  Start-Sleep -Milliseconds 70
  [System.Windows.Forms.SendKeys]::SendWait($ValueText)
  Start-Sleep -Milliseconds 90
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Start-Sleep -Milliseconds 320
}

function Move-ToSettingLabel {
  param(
    [Windows.Automation.AutomationElement]$EditorElement,
    [scriptblock]$Predicate,
    [int]$MaxSteps = 80
  )
  for ($i = 0; $i -le $MaxSteps; $i++) {
    $row = Get-CurrentSettingRow -EditorElement $EditorElement
    Assert-TargetSelected -Row $row
    if (& $Predicate $row) {
      return [pscustomobject]@{ row = $row; steps = $i }
    }
    [System.Windows.Forms.SendKeys]::SendWait('{DOWN}')
    Start-Sleep -Milliseconds 130
  }
  throw 'KV_UNIT_ADDRESS_SETTING_ROW_NOT_FOUND'
}

function Invoke-ChildButtonByTitle {
  param([long]$ParentHwnd, [string[]]$Titles)
  $rows = New-Object System.Collections.ArrayList
  $callback = [KvUnitAddressWin32+EnumWindowsProc]{
    param($handle, $lParam)
    $titleBuilder = [Text.StringBuilder]::new(512)
    $classBuilder = [Text.StringBuilder]::new(256)
    [void][KvUnitAddressWin32]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity)
    [void][KvUnitAddressWin32]::GetClassName($handle, $classBuilder, $classBuilder.Capacity)
    [void]$rows.Add([pscustomobject]@{
      hwnd = $handle.ToInt64()
      id = [KvUnitAddressWin32]::GetDlgCtrlID($handle)
      visible = [KvUnitAddressWin32]::IsWindowVisible($handle)
      enabled = [KvUnitAddressWin32]::IsWindowEnabled($handle)
      title = $titleBuilder.ToString()
      class_name = $classBuilder.ToString()
    })
    return $true
  }
  [void][KvUnitAddressWin32]::EnumChildWindows([IntPtr]$ParentHwnd, $callback, [IntPtr]::Zero)
  $buttons = @($rows | Where-Object { $_.visible -and $_.enabled -and $_.class_name -eq 'Button' })
  foreach ($title in $Titles) {
    $button = $buttons | Where-Object { $_.title -eq $title } | Select-Object -First 1
    if ($button) {
      [void][KvUnitAddressWin32]::PostMessage([IntPtr]$button.hwnd, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
      Start-Sleep -Milliseconds 750
      return [pscustomobject]@{ title = $button.title; hwnd = $button.hwnd; method = 'PostMessage_BM_CLICK' }
    }
  }
  $null
}

function Handle-KvMessageDialogs {
  param([int]$TimeoutMs = 5000)
  $handled = @()
  $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
  do {
    $dialog = @(Get-KvRelevantWindows | Where-Object { $_.class_name -eq '#32770' } | Select-Object -First 1)
    if ($dialog.Count -eq 0) {
      Start-Sleep -Milliseconds 160
      continue
    }
    $button = Invoke-ChildButtonByTitle -ParentHwnd $dialog[0].hwnd -Titles @($NameConfirm, 'OK', '是(Y)', 'Yes')
    if (-not $button) { break }
    $handled += [pscustomobject]@{ dialog = $dialog[0]; button = $button }
    Start-Sleep -Milliseconds 500
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

function Get-WsTreeUnitEntries {
  param([string]$ProjectDir)
  $path = Join-Path $ProjectDir 'WsTreeEnv.xml'
  if (-not (Test-Path -LiteralPath $path)) { return @() }
  $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $path
  $entries = @()
  $regex = [regex]'<value\.first>\[(?<slot>\d+)\]\s+(?<unit>\S+)\s+(?<relay>R\d+|-+)\s+(?<dm>DM\d+|-+)</value\.first>'
  foreach ($match in $regex.Matches($content)) {
    $entries += [pscustomobject]@{
      slot = [int]$match.Groups['slot'].Value
      unit = $match.Groups['unit'].Value
      relay_start = $match.Groups['relay'].Value
      dm_start = $match.Groups['dm'].Value
      matches_requested_unit = ($match.Groups['unit'].Value -eq $UnitName -and ($Slot -lt 0 -or [int]$match.Groups['slot'].Value -eq $Slot))
      source = $path
    }
  }
  $entries
}

function Get-ProjectAddressEvidence {
  if (-not $ProjectPath) { return [pscustomobject]@{ skipped = $true; reason = 'ProjectPath not provided.' } }
  $projectDir = Split-Path -Parent $ProjectPath
  [pscustomobject]@{
    skipped = $false
    project_dir = $projectDir
    unit_tree_entries = @(Get-WsTreeUnitEntries -ProjectDir $projectDir)
  }
}

function Get-RequestedEntry($Evidence) {
  if ($Evidence.skipped) { return $null }
  @($Evidence.unit_tree_entries | Where-Object { $_.matches_requested_unit } | Select-Object -First 1)
}

function Convert-RelayToChannel([int]$Relay) {
  if ($Relay % 100 -ne 0) { throw "KV_UNIT_ADDRESS_RELAY_NOT_CHANNEL_ALIGNED: FirstRelay=$Relay must map to a channel value, e.g. R1000 -> 10." }
  [int]($Relay / 100)
}

$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$evidencePath = New-EvidencePath 'configure_kv_unit_start_addresses'
$result = [ordered]@{
  ok = $false
  script = 'configure_kv_unit_start_addresses.ps1'
  project_name = $ProjectName
  project_path = $ProjectPath
  unit_name = $UnitName
  slot = $Slot
  first_dm = $FirstDm
  first_relay = $FirstRelay
  relay_channel_value = $null
  started_at = (Get-Date).ToString('o')
  max_duration_seconds = $MaxDurationSeconds
  phases = [ordered]@{}
  evidence_path = $evidencePath
}

try {
  if ($FirstDm -lt 0) { throw 'FirstDm must be >= 0.' }
  if ($FirstRelay -lt 0) { throw 'FirstRelay must be >= 0.' }
  $relayChannel = Convert-RelayToChannel -Relay $FirstRelay
  $result.relay_channel_value = $relayChannel
  $result.phases.closed_stale_convert_results = @(Close-StaleConvertResultDialogs)
  $result.phases.before_project_evidence = Get-ProjectAddressEvidence

  Assert-TimeBudget -Stopwatch $stopwatch -Step 'open target unit editor'
  $open = Open-UnitEditorFromTargetUnit -Stopwatch $stopwatch
  $result.phases.open_unit_editor = $open
  $editorElement = Get-ElementFromHwnd -Hwnd $open.window.hwnd
  Set-ForegroundWindowByHwnd -Hwnd $open.window.hwnd
  [System.Windows.Forms.SendKeys]::SendWait('%2')
  Start-Sleep -Milliseconds 180
  $initial = Get-CurrentSettingRow -EditorElement $editorElement
  Assert-TargetSelected -Row $initial
  $result.phases.initial_row = $initial

  Assert-TimeBudget -Stopwatch $stopwatch -Step 'edit first DM'
  $dmFocus = Enter-CurrentValueCell -EditorElement $editorElement
  if ($dmFocus.label -ne $LabelFirstDm) {
    throw "KV_UNIT_ADDRESS_UNEXPECTED_DM_ROW: expected '$LabelFirstDm', got '$($dmFocus.label)'."
  }
  Type-CurrentValue -ValueText ([string]$FirstDm)
  $afterDm = Get-CurrentSettingRow -EditorElement $editorElement
  Assert-TargetSelected -Row $afterDm
  $result.phases.after_dm_edit = $afterDm

  Assert-TimeBudget -Stopwatch $stopwatch -Step 'edit first relay'
  $relayMove = Move-ToSettingLabel -EditorElement $editorElement -Predicate {
    param($row)
    $row.label.StartsWith($LabelRelayPrefix, [StringComparison]::Ordinal)
  }
  $result.phases.relay_row = $relayMove
  $relayFocus = Enter-CurrentValueCell -EditorElement $editorElement
  if (-not $relayFocus.label.StartsWith($LabelRelayPrefix, [StringComparison]::Ordinal)) {
    throw "KV_UNIT_ADDRESS_UNEXPECTED_RELAY_ROW: got '$($relayFocus.label)'."
  }
  Type-CurrentValue -ValueText ([string]$relayChannel)
  $afterRelay = Get-CurrentSettingRow -EditorElement $editorElement
  Assert-TargetSelected -Row $afterRelay
  $result.phases.after_relay_edit = $afterRelay

  Assert-TimeBudget -Stopwatch $stopwatch -Step 'unit editor OK and save'
  $ok = Invoke-ChildButtonByTitle -ParentHwnd $open.window.hwnd -Titles @('OK')
  if (-not $ok) { throw 'KV_UNIT_ADDRESS_OK_BUTTON_NOT_FOUND' }
  $result.phases.unit_editor_ok = $ok
  $result.phases.message_dialogs = @(Handle-KvMessageDialogs)
  $result.phases.saved_title = Save-Project
  $result.phases.after_project_evidence = Get-ProjectAddressEvidence
  $entry = Get-RequestedEntry -Evidence $result.phases.after_project_evidence
  $result.phases.matched_entry = $entry

  if ($ProjectPath) {
    if (-not $entry) { throw 'KV_UNIT_ADDRESS_EVIDENCE_ENTRY_MISSING' }
    $expectedDm = "DM$FirstDm"
    $expectedRelay = "R$FirstRelay"
    if ($entry.dm_start -ne $expectedDm -or $entry.relay_start -ne $expectedRelay) {
      throw "KV_UNIT_ADDRESS_VERIFY_FAILED: expected $expectedRelay $expectedDm, got $($entry.relay_start) $($entry.dm_start)."
    }
  }

  $result.elapsed_seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
  if ($result.elapsed_seconds -gt $MaxDurationSeconds) {
    throw "KV_UNIT_ADDRESS_TIMEOUT: elapsed=$($result.elapsed_seconds) MaxDurationSeconds=$MaxDurationSeconds"
  }
  $result.ok = $true
} catch {
  $result.elapsed_seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
  $result.error = $_.Exception.Message
  Write-JsonFile -Path $evidencePath -Value $result
  Write-Error "configure_kv_unit_start_addresses failed; evidence: $evidencePath; error: $($_.Exception.Message)"
  exit 64
}

$result.finished_at = (Get-Date).ToString('o')
Write-JsonFile -Path $evidencePath -Value $result
Write-Host "OK: configured unit '$UnitName' slot=$Slot relay=R$FirstRelay dm=DM$FirstDm elapsed=$($result.elapsed_seconds)s evidence=$evidencePath"
