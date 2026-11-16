<#
.SYNOPSIS
Export the KV Nano label table (标号) - the Nano equivalent of variables - to TSV files.

.DESCRIPTION
On KV Nano there is no "variable editor": the variables live in the 标号 (label) table that
opens when the project-tree node 标号 is activated. The dialog has two tabs:

  全局 (global)  - one table for the whole project
  局部 (local)   - one table per program, selected with the 选择程序(M) combo

The grid is owner-drawn: UIA exposes only the tab items and the program combo, so the rows are
read through the clipboard. Verified key route (given by the operator on 2026-11-17):

  Ctrl+Home            focus may not start at the top-left cell
  Ctrl+Shift+End       select the whole table
  Ctrl+C               copy as TSV
  Ctrl+Tab             switch to the 局部 tab (focus lands on 选择程序)
  Tab, Tab             move from the program combo into the grid
  Alt+M                focus the 选择程序 combo to switch program with Left/Right

This script uses the UIA handles for the tab items and for the program combo instead of the
Alt+M route, then follows the same keyboard sequence inside the grid.

.EXAMPLE
powershell -File export_nano_labels_guarded.ps1 -ProjectPath C:\kvrun\nano\纯48\纯48.kpr `
  -OutDir C:\kvrun\nano\labels_run -IncludeLocal
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ProjectPath,
  [Parameter(Mandatory = $true)][string]$OutDir,
  [switch]$IncludeLocal,
  [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

if (-not ('KvNanoLabelWin32' -as [type])) {
  Add-Type @'
using System;
using System.Text;
using System.Runtime.InteropServices;
public class KvNanoLabelWin32 {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc cb, IntPtr l);
  public delegate bool EnumWindowsProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, int dx, int dy, uint d, UIntPtr e);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
'@
}

$script:runStart = Get-Date
$script:logPath = Join-Path $OutDir 'run.log'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
function Log([string]$Message) {
  $entry = [ordered]@{ timestamp = (Get-Date).ToString('o'); message = $Message }
  [IO.File]::AppendAllText($script:logPath, (($entry | ConvertTo-Json -Compress) + [Environment]::NewLine), (New-Object Text.UTF8Encoding($false)))
}

function Get-KvsMainWindow([string]$projectPath) {
  $needle = [IO.Path]::GetFileNameWithoutExtension($projectPath)
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  while ((Get-Date) -lt $deadline) {
    foreach ($process in @(Get-Process Kvs -ErrorAction SilentlyContinue)) {
      if ($process.MainWindowHandle -ne 0 -and $process.MainWindowTitle -match [regex]::Escape($needle)) { return $process }
    }
    Start-Sleep -Milliseconds 500
  }
  throw "KV_NANO_LABELS_PROJECT_NOT_OPEN: $needle"
}

function Get-WindowByTitle([int]$ProcessId, [string]$Title) {
  $script:windowHits = @()
  [void][KvNanoLabelWin32]::EnumWindows({
    param($h, $l)
    $pid2 = 0
    [void][KvNanoLabelWin32]::GetWindowThreadProcessId($h, [ref]$pid2)
    if ($pid2 -eq $ProcessId -and [KvNanoLabelWin32]::IsWindowVisible($h)) {
      $sb = New-Object Text.StringBuilder 256
      [void][KvNanoLabelWin32]::GetWindowText($h, $sb, 256)
      if ($sb.ToString() -eq $Title) { $script:windowHits += $h }
    }
    return $true
  }, [IntPtr]::Zero)
  if (@($script:windowHits).Count -eq 0) { return [IntPtr]::Zero }
  return [IntPtr]$script:windowHits[0]
}

function Open-LabelDialog($Process) {
  $main = [Windows.Automation.AutomationElement]::FromHandle($Process.MainWindowHandle)
  $tree = $main.FindFirst([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::AutomationIdProperty), 'ProjectTreeView'))
  if (-not $tree) { throw 'KV_NANO_LABELS_TREE_MISSING' }
  $node = $null
  $nodeDeadline = (Get-Date).AddSeconds(10)
  do {
    foreach ($item in $tree.FindAll([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::ControlTypeProperty), ([Windows.Automation.ControlType]::TreeItem)))) {
      if ([string]$item.Current.Name -replace '\s', '' -eq '标号') { $node = $item; break }
    }
    if (-not $node) { Start-Sleep -Milliseconds 500 }
  } while (-not $node -and (Get-Date) -lt $nodeDeadline)
  if (-not $node) { throw 'KV_NANO_LABELS_NODE_MISSING' }
  # The dialog is not a desktop child, so it is opened by activating the node and then looked
  # up by its own top-level handle. Enter on the selected node is tried first (it is the
  # documented route), then a double click on the node rectangle as a fallback.
  $rect = $node.Current.BoundingRectangle
  [void][KvNanoLabelWin32]::SetForegroundWindow($Process.MainWindowHandle)
  Start-Sleep -Milliseconds 400
  $selection = $null
  if ($node.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selection)) { $selection.Select() }
  $node.SetFocus()
  Start-Sleep -Milliseconds 300
  [void][System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  $deadline = (Get-Date).AddSeconds(8)
  do {
    Start-Sleep -Milliseconds 400
    $hwnd = Get-WindowByTitle $Process.Id '编辑标号'
    if ($hwnd -ne [IntPtr]::Zero) { return $hwnd }
  } while ((Get-Date) -lt $deadline)

  Log 'Enter did not open the label dialog; double-clicking the node'
  [void][KvNanoLabelWin32]::SetCursorPos([int]($rect.X + 4), [int]($rect.Y + 6))
  Start-Sleep -Milliseconds 150
  [KvNanoLabelWin32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [KvNanoLabelWin32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 90
  [KvNanoLabelWin32]::mouse_event(0x0002, 0, 0, 0, [UIntPtr]::Zero)
  [KvNanoLabelWin32]::mouse_event(0x0004, 0, 0, 0, [UIntPtr]::Zero)
  $deadline = (Get-Date).AddSeconds(10)
  do {
    Start-Sleep -Milliseconds 400
    $hwnd = Get-WindowByTitle $Process.Id '编辑标号'
    if ($hwnd -ne [IntPtr]::Zero) { return $hwnd }
  } while ((Get-Date) -lt $deadline)
  throw 'KV_NANO_LABELS_DIALOG_TIMEOUT'
}

function Get-GridTable([IntPtr]$DialogHwnd) {
  [void][KvNanoLabelWin32]::SetForegroundWindow($DialogHwnd)
  Start-Sleep -Milliseconds 350
  [System.Windows.Forms.Clipboard]::Clear()
  Start-Sleep -Milliseconds 80
  [void][System.Windows.Forms.SendKeys]::SendWait('^{HOME}')
  Start-Sleep -Milliseconds 250
  [void][System.Windows.Forms.SendKeys]::SendWait('^+{END}')
  Start-Sleep -Milliseconds 350
  [void][System.Windows.Forms.SendKeys]::SendWait('^c')
  Start-Sleep -Milliseconds 600
  $text = [System.Windows.Forms.Clipboard]::GetText()
  if (-not $text) { throw 'KV_NANO_LABELS_CLIPBOARD_EMPTY' }
  $rows = New-Object System.Collections.Generic.List[object]
  foreach ($line in ($text -split "`r?`n")) {
    if (-not $line.Trim()) { continue }
    $fields = $line -split "`t"
    $rows.Add([ordered]@{
        label   = [string]$fields[0]
        datatype = if ($fields.Count -gt 1) { [string]$fields[1] } else { '' }
        device  = if ($fields.Count -gt 2) { [string]$fields[2] } else { '' }
        comment = if ($fields.Count -gt 3) { [string]$fields[3] } else { '' }
      })
  }
  if ($rows.Count -eq 0) { throw 'KV_NANO_LABELS_TABLE_EMPTY' }
  return $rows
}

function Write-Tsv([string]$Path, $Rows) {
  $lines = foreach ($row in $Rows) { (@($row.label, $row.datatype, $row.device, $row.comment) -join "`t") }
  [IO.File]::WriteAllText($Path, (($lines -join "`r`n") + "`r`n"), (New-Object Text.UTF8Encoding($false)))
}

$result = [ordered]@{ ok = $false; error_code = ''; message = ''; global_rows = 0; local_programs = @(); files = @() }
try {
  $process = Get-KvsMainWindow $ProjectPath
  Log ("project window: " + $process.MainWindowTitle + " pid=" + $process.Id)
  $dialogHwnd = Get-WindowByTitle $process.Id '编辑标号'
  if ($dialogHwnd -ne [IntPtr]::Zero) {
    # A dialog left open by an earlier run keeps the tree non-interactive; close it first.
    [void][KvNanoLabelWin32]::SetForegroundWindow($dialogHwnd)
    Start-Sleep -Milliseconds 300
    [void][System.Windows.Forms.SendKeys]::SendWait('{ESC}')
    Start-Sleep -Milliseconds 500
  }
  $dialogHwnd = Get-WindowByTitle $process.Id '编辑标号'
  if ($dialogHwnd -eq [IntPtr]::Zero) { $dialogHwnd = Open-LabelDialog $process }
  Log ("label dialog hwnd=" + $dialogHwnd.ToInt64())
  $dialog = [Windows.Automation.AutomationElement]::FromHandle($dialogHwnd)

  # ---- 全局 (global) -------------------------------------------------------
  $globalTab = $dialog.FindFirst([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::AutomationIdProperty), '_tabGlobal'))
  if ($globalTab) {
    $selection = $null
    if ($globalTab.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selection)) { $selection.Select(); Start-Sleep -Milliseconds 500 }
  }
  $globalRows = Get-GridTable $dialogHwnd
  $globalPath = Join-Path $OutDir 'labels_global.tsv'
  Write-Tsv $globalPath $globalRows
  $result.global_rows = $globalRows.Count
  $result.files += 'labels_global.tsv'
  Log ("global labels: " + $globalRows.Count)

  # ---- 局部 (local, one table per program) --------------------------------
  if ($IncludeLocal) {
    $localTab = $dialog.FindFirst([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::AutomationIdProperty), '_tabLocal'))
    if (-not $localTab) { throw 'KV_NANO_LABELS_LOCAL_TAB_MISSING' }
    $selection = $null
    if ($localTab.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selection)) { $selection.Select(); Start-Sleep -Milliseconds 600 }
    $combo = $dialog.FindFirst([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::AutomationIdProperty), '_comboBoxModule'))
    if (-not $combo) { throw 'KV_NANO_LABELS_PROGRAM_COMBO_MISSING' }
    $value = $null
    if (-not $combo.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern, [ref]$value)) { throw 'KV_NANO_LABELS_COMBO_VALUE_UNSUPPORTED' }

    $programs = @()
    $tree2 = [Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle).FindFirst([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::AutomationIdProperty), 'ProjectTreeView'))
    $marker = $null
    foreach ($item in $tree2.FindAll([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::ControlTypeProperty), ([Windows.Automation.ControlType]::TreeItem)))) {
      $name = [string]$item.Current.Name
      if ($name -match '^每次扫描执行型模块$') { $marker = $item; continue }
      if ($name -match '^(初始化模块|后备模块|宏|子程序型宏|自保持型宏|软元件初始值)$') { $marker = $null; continue }
      if ($marker -and $name) { $programs += $name }
    }
    $programs = @($programs | Select-Object -Unique)
    if ($programs.Count -eq 0) { throw 'KV_NANO_LABELS_PROGRAMS_MISSING' }
    Log ("local programs: " + ($programs -join ', '))

    # The program combo is switched with the keyboard route the operator verified: Alt+M puts
    # focus on 选择程序, Home returns to the first item, then Down moves by index. The combo
    # value is read back through UIA so the file is named after the program actually shown.
    for ($index = 0; $index -lt $programs.Count; $index++) {
      [void][KvNanoLabelWin32]::SetForegroundWindow($dialogHwnd)
      Start-Sleep -Milliseconds 300
      [void][System.Windows.Forms.SendKeys]::SendWait('%m')
      Start-Sleep -Milliseconds 350
      [void][System.Windows.Forms.SendKeys]::SendWait('^{HOME}')
      Start-Sleep -Milliseconds 200
      for ($step = 0; $step -lt $index; $step++) { [void][System.Windows.Forms.SendKeys]::SendWait('{DOWN}'); Start-Sleep -Milliseconds 120 }
      Start-Sleep -Milliseconds 500
      $program = [string]$value.Current.Value
      [void][System.Windows.Forms.SendKeys]::SendWait('{TAB}{TAB}')
      Start-Sleep -Milliseconds 350
      try { $rows = Get-GridTable $dialogHwnd } catch { Log ("local read failed for " + $program + ": " + $_.Exception.Message); continue }
      $rows = @($rows | Where-Object { $_.label.Trim() -or $_.datatype.Trim() -or $_.device.Trim() -or $_.comment.Trim() })
      $safeName = ($program -replace '[\\/:*?"<>|]', '_')
      if (-not $safeName) { $safeName = "program_$index" }
      $path = Join-Path $OutDir ("labels_local_{0}.tsv" -f $safeName)
      Write-Tsv $path $rows
      $result.local_programs += [ordered]@{ program = $program; rows = $rows.Count; file = (Split-Path $path -Leaf) }
      $result.files += (Split-Path $path -Leaf)
      Log ("local labels " + $program + " : " + $rows.Count)
      Start-Sleep -Milliseconds 200
    }
  }

  $result.ok = $true
}
catch {
  $result.error_code = $_.Exception.Message
  $result.message = $_.ScriptStackTrace
  Log ("ERROR " + $_.Exception.Message)
}

$resultPath = Join-Path $OutDir 'nano_labels_result.json'
[IO.File]::WriteAllText($resultPath, ($result | ConvertTo-Json -Depth 6), (New-Object Text.UTF8Encoding($false)))
$result | ConvertTo-Json -Depth 6
if (-not $result.ok) { exit 1 }
