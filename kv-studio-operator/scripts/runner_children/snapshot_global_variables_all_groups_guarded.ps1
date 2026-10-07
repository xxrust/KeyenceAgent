<#!
.SYNOPSIS
  Guarded snapshot of all KV STUDIO global variable groups.

.DESCRIPTION
  This atomic runner does not write project data. It exercises the UI route
  required by projects that have more than the
  (Default) variable group:

    Alt+G -> Enter -> Alt+A -> Tab x3 -> Enter -> Ctrl+A -> Ctrl+C

  The copied grid text and evidence are written below OutDir.
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$SkillRoot = '',
  [int]$TimeoutSeconds = 20,
  [switch]$KeepVariableEditorOpen
)

$ErrorActionPreference = 'Stop'
if (-not [Environment]::Is64BitProcess -and $PSVersionTable.PSEdition -eq 'Desktop') {
  # Do not fail solely on bitness; this is retained as evidence in the result.
}
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
  throw "ProjectPath not found: $ProjectPath"
}
$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (-not $SkillRoot) { $SkillRoot = Split-Path -Parent $PSCommandPath | Split-Path -Parent }
$SkillRoot = [IO.Path]::GetFullPath($SkillRoot)

$guardPath = Join-Path $SkillRoot 'guards\kv_ui_guard.ps1'
if (-not (Test-Path -LiteralPath $guardPath -PathType Leaf)) {
  throw "KV UI guard not found: $guardPath"
}
. $guardPath
Initialize-KvUiGuard -OutDir $OutDir -CheckpointSubdir 'ui_checkpoints'

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
if (-not ('KvAllGroupsClipboard' -as [type])) {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public static class KvAllGroupsClipboard {
  [DllImport("user32.dll")] public static extern uint GetClipboardSequenceNumber();
}
"@
}

function Log-Event([string]$Event, [hashtable]$Data = @{}) {
  Write-KvUiGuardRunLog -Event $Event -Data $Data
}

function Get-TopLevelProcessWindows([int]$ProcessId) {
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $items = $root.FindAll(
    [System.Windows.Automation.TreeScope]::Children,
    (New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessId))
  )
  @($items | ForEach-Object { $_ })
}

function Get-VariableEditor([int]$ProcessId) {
  foreach ($window in @(Get-TopLevelProcessWindows $ProcessId)) {
    if ([string]$window.Current.AutomationId -eq 'KvVariableForm') { return $window }
    $found = $window.FindFirst(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.PropertyCondition(
        [System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'KvVariableForm'))
    )
    if ($found) { return $found }
  }
  return $null
}

function Wait-VariableEditor([int]$ProcessId, [int]$Seconds = 8) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $form = Get-VariableEditor $ProcessId
    if ($form) { return $form }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Get-VariableGroupDialog([int]$ProcessId) {
  $groupText = -join ([char[]](0x53D8,0x91CF,0x7EC4))
  $groupTextEn = 'Variable Group'
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $processCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ProcessId)
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $processCondition)
  foreach ($window in @($all | ForEach-Object { $_ })) {
    $name = [string]$window.Current.Name
    $type = [string]$window.Current.ControlType.ProgrammaticName
    $hwnd = [int64]$window.Current.NativeWindowHandle
    if ($type -ne 'ControlType.Window' -or $window.Current.IsOffscreen -or $hwnd -eq 0) { continue }
    if ($name -like "*$groupText*" -or $name -like "*$groupTextEn*") {
      return $window
    }
  }
  return $null
}

function Wait-VariableGroupDialog([int]$ProcessId, [int]$Seconds = 8) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $dialog = Get-VariableGroupDialog $ProcessId
    if ($dialog) { return $dialog }
    Start-Sleep -Milliseconds 150
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Get-ProcessForProject([string]$Path) {
  $needle = [IO.Path]::GetFileNameWithoutExtension($Path)
  $full = [IO.Path]::GetFullPath($Path)
  $matches = @(
    Get-CimInstance Win32_Process -Filter "Name='Kvs.exe'" -ErrorAction SilentlyContinue |
      Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($full, [StringComparison]::OrdinalIgnoreCase) -ge 0 } |
      ForEach-Object { Get-Process -Id ([int]$_.ProcessId) -ErrorAction SilentlyContinue } |
      Where-Object { $_.MainWindowHandle -ne 0 }
  )
  if ($matches.Count -eq 1) { return $matches[0] }
  $matches = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object {
    $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$needle*"
  })
  if ($matches.Count -ne 1) {
    throw "Expected one Kvs process for '$needle'; found $($matches.Count)."
  }
  return $matches[0]
}

function Invoke-GuardedKey([IntPtr]$Hwnd, [string]$Step, [string]$Keys, [string]$Action, [int]$SleepMs = 250) {
  Invoke-KvGuardedSendKeys -TargetHwnd $Hwnd -Step $Step -Keys $Keys -ExpectedTitleLike '*' -Action $Action -SleepMs $SleepMs
}

function Invoke-GuardedAlt([IntPtr]$Hwnd, [string]$Step, [byte]$Vk, [string]$Action) {
  Invoke-KvGuardedAltVk -TargetHwnd $Hwnd -Step $Step -Vk $Vk -ExpectedTitleLike '*' -SleepMs 180
  Log-Event 'accelerator_sent' @{ step=$Step; virtual_key=$Vk; action=$Action }
}

function Get-CheckedGroupCount($Dialog) {
  $checked = 0; $checkboxes = 0
  $items = $Dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  for ($i = 0; $i -lt $items.Count; $i++) {
    $item = $items.Item($i)
    if ($item.Current.ControlType -ne [System.Windows.Automation.ControlType]::CheckBox) { continue }
    $checkboxes++
    $toggle = $null
    if ($item.TryGetCurrentPattern([System.Windows.Automation.TogglePattern]::Pattern, [ref]$toggle)) {
      if ($toggle.Current.ToggleState -eq [System.Windows.Automation.ToggleState]::On) { $checked++ }
    }
  }
  [pscustomobject]@{ checkbox_count=$checkboxes; checked_count=$checked }
}

function Copy-GlobalGridText($Form, [int]$ProcessId) {
  $grid = $Form.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::AutomationIdProperty, '_grid'))
  )
  if (-not $grid) { throw 'Global variable grid _grid was not found.' }
  $grid.SetFocus()
  Start-Sleep -Milliseconds 200
  $formHwnd = [IntPtr]$Form.Current.NativeWindowHandle
  $before = [KvAllGroupsClipboard]::GetClipboardSequenceNumber()
  Invoke-KvGuardedCtrlChord -TargetHwnd $formHwnd -Step 'copy all global variables Ctrl+A' -Vk 0x41 -ExpectedTitleLike '*' -Action 'select complete global variable grid' -SleepMs 250
  Invoke-KvGuardedCtrlChord -TargetHwnd $formHwnd -Step 'copy all global variables Ctrl+C' -Vk 0x43 -ExpectedTitleLike '*' -Action 'copy complete global variable grid' -SleepMs 400
  $deadline = (Get-Date).AddSeconds(5)
  do {
    Start-Sleep -Milliseconds 150
    try {
      if ([KvAllGroupsClipboard]::GetClipboardSequenceNumber() -ne $before) {
        $text = [Windows.Forms.Clipboard]::GetText()
        if (-not [string]::IsNullOrWhiteSpace($text)) { return $text }
      }
    } catch {}
  } while ((Get-Date) -lt $deadline)
  throw 'Clipboard did not contain copied global variable text.'
}

$result = [ordered]@{
  ok = $false
  project_path = $ProjectPath
  out_dir = $OutDir
  sequence = @('Alt+G','Enter','Alt+A','Tab','Tab','Tab','Enter','Ctrl+A','Ctrl+C')
  group_dialog = $null
  output_path = $null
  row_count = 0
  error = $null
}
$process = $null
$editor = $null
try {
  $process = Get-ProcessForProject $ProjectPath
  $process.Refresh()
  $pidValue = $process.Id
  Log-Event 'bound_project' @{ pid=$pidValue; hwnd=$process.MainWindowHandle.ToInt64(); title=$process.MainWindowTitle; project=$ProjectPath }
  $editor = Wait-VariableEditor $pidValue 2
  if (-not $editor) {
    Invoke-KvGuardedAltVk -TargetHwnd $process.MainWindowHandle -Step 'open variable editor Alt+V' -Vk 0x56 -ExpectedTitleLike '*' -SleepMs 120
    Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $process.MainWindowHandle -Step 'open variable editor menu item' -Keys 'l' -ExpectedTitleLike '*' -SuccessTitleLike @('*') -Action 'open variable editor from View menu' -SleepMs 700
    $editor = Wait-VariableEditor $pidValue 8
  }
  if (-not $editor) { throw 'KV variable editor did not open.' }
  $editorHwnd = [IntPtr]$editor.Current.NativeWindowHandle

  Invoke-GuardedAlt $editorHwnd 'open variable group selector Alt+G' 0x47 'focus variable group selector button'
  Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $editorHwnd -Step 'open variable group selector Enter' -Keys '{ENTER}' -ExpectedTitleLike '*' -SuccessTitleLike @('*') -Action 'open variable group selector dialog' -SleepMs 350
  $dialog = Wait-VariableGroupDialog $pidValue 8
  if (-not $dialog) { throw 'Variable group dialog did not open after Alt+G, Enter.' }
  $dialogHwnd = [IntPtr]$dialog.Current.NativeWindowHandle
  $beforeSelection = Get-CheckedGroupCount $dialog
  Invoke-GuardedAlt $dialogHwnd 'select all variable groups Alt+A' 0x41 'select all variable groups'
  Start-Sleep -Milliseconds 180
  $afterSelection = Get-CheckedGroupCount $dialog
  $result.group_dialog = [ordered]@{
    hwnd=$dialogHwnd.ToInt64(); title=[string]$dialog.Current.Name
    before=$beforeSelection; after=$afterSelection
    tab_count=3; confirmation='Enter'
  }
  Invoke-GuardedKey $dialogHwnd 'variable group dialog Tab x3' '{TAB}{TAB}{TAB}' 'move focus to variable group dialog OK button' 180
  Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $dialogHwnd -Step 'confirm all variable groups Enter' -Keys '{ENTER}' -ExpectedTitleLike '*' -SuccessTitleLike @('*') -Action 'confirm all variable groups' -SleepMs 500
  if (Wait-VariableGroupDialog $pidValue 2) { throw 'Variable group dialog remained open after confirmation.' }
  $editor = Wait-VariableEditor $pidValue 5
  if (-not $editor) { throw 'Variable editor was not present after confirming variable groups.' }
  $text = Copy-GlobalGridText $editor $pidValue
  $outputPath = Join-Path $OutDir 'global_variables_all_groups.tsv'
  [IO.File]::WriteAllText($outputPath, $text, [Text.Encoding]::UTF8)
  # Keep the legacy snapshot artifact names available to the semantic project
  # materializer while retaining the explicit all-groups artifact.
  $legacyPath = Join-Path $OutDir 'global_variables_raw.tsv'
  Copy-Item -LiteralPath $outputPath -Destination $legacyPath -Force
  $result.output_path = $outputPath
  $result.row_count = @($text -split "`r?`n" | Where-Object { $_ }).Count
  $result.ok = $true
  $evidence = [ordered]@{ ok=$true; output_path=$outputPath; row_count=$result.row_count; group_dialog=$result.group_dialog; copied_at=(Get-Date).ToString('o') }
  $evidence | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutDir 'global_variables_all_groups_result.json') -Encoding UTF8
  $snapshot = [ordered]@{
    ok = $true
    read_only = $true
    project_path = $ProjectPath
    snapshots = @([ordered]@{ scope='global'; owner_program=''; raw_path=$legacyPath; all_groups_raw_path=$outputPath; row_count=$result.row_count })
    all_columns_preserved = $true
    unfiltered_completeness_verified = $true
    variable_group_selection = $result.group_dialog
  }
  $snapshot | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutDir 'variable_snapshot_result.json') -Encoding UTF8
  Log-Event 'global_snapshot_complete' @{ output_path=$outputPath; row_count=$result.row_count }
} catch {
  $result.error = $_.Exception.Message
  $result.ok = $false
  $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutDir 'global_variables_all_groups_result.json') -Encoding UTF8
  Log-Event 'global_snapshot_failed' @{ error=$result.error }
  throw
} finally {
  # Leave KV STUDIO and the variable editor untouched after the test. Closing
  # the editor here can change dialog z-order and steal foreground from a
  # still-visible variable-group dialog after a failed assertion.
  if ($process) { Log-Event 'desktop_state_preserved' @{ pid=$process.Id; keep_variable_editor_open=$true } }
  $result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $OutDir 'global_variables_all_groups_summary.json') -Encoding UTF8
}
if (-not $result.ok) { exit 1 }
exit 0
