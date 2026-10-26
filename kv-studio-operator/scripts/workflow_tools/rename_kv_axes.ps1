param(
  [Parameter(Mandatory=$true)][string]$MappingPath,
  [string]$OutDir = ''
)
# Renames KV STUDIO axes through the axis settings page:
#   select the axis under 运动设定 > 轴设定, the page shows 轴No.(N) and 轴名称(M),
#   replace the name edit, commit with Tab, then verify the tree text changed.
# Mapping file: one "axis_index<TAB>new_name" per line (# comments allowed).
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class AxisWin {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
}
"@

if (-not (Test-Path -LiteralPath $MappingPath -PathType Leaf)) { throw "KV_AXIS_MAPPING_MISSING: $MappingPath" }
if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $MappingPath) 'axis_rename' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$mapping = New-Object System.Collections.Generic.List[object]
foreach ($line in (Get-Content -LiteralPath $MappingPath -Encoding UTF8)) {
  if (-not $line.Trim() -or $line.TrimStart().StartsWith('#')) { continue }
  $cells = $line -split "`t"
  if ($cells.Count -lt 2) { continue }
  if ($cells[0].Trim() -notmatch '^\d+$') { continue }
  $mapping.Add([pscustomobject]@{ index = [int]$cells[0].Trim(); name = $cells[1].Trim() })
}
if ($mapping.Count -eq 0) { throw 'KV_AXIS_MAPPING_EMPTY' }

$process = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
if (-not $process) { throw 'KV_PROCESS_NOT_RUNNING' }
$root = [System.Windows.Automation.AutomationElement]::RootElement
$pidCondition = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
  [System.Windows.Automation.AutomationElement]::ProcessIdProperty, $process.Id)
$windowCondition = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
  [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Window)
$mainCondition = New-Object System.Windows.Automation.AndCondition -ArgumentList @($pidCondition, $windowCondition)
$main = $root.FindFirst([System.Windows.Automation.TreeScope]::Children, $mainCondition)
if (-not $main) { throw 'KV_MAIN_WINDOW_NOT_FOUND' }

function Find-AxisItem([int]$index) {
  $condition = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::TreeItem)
  foreach ($item in @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition))) {
    $text = [string]$item.Current.Name
    if ($text -match ('^轴{0}:' -f $index)) { return [pscustomobject]@{ element = $item; text = $text } }
  }
  return $null
}
function Click-Rect($rect) {
  [AxisWin]::SetCursorPos([int]($rect.Left + $rect.Width / 2), [int]($rect.Top + $rect.Height / 2)) | Out-Null
  Start-Sleep -Milliseconds 120
  [AxisWin]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
  Start-Sleep -Milliseconds 60
  [AxisWin]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
}
function Get-EditValue($edit) {
  try { return [string]$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).Current.Value } catch { return '' }
}
function Find-NameEdit([int]$index, [string]$currentName) {
  $condition = New-Object System.Windows.Automation.PropertyCondition -ArgumentList @(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::Edit)
  $edits = @($main.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition) | Where-Object { $_.Current.BoundingRectangle.Width -gt 0 })
  $pageMatches = $false
  $nameEdit = $null
  foreach ($edit in $edits) {
    $value = Get-EditValue $edit
    if ($value -eq [string]$index) { $pageMatches = $true }
    if ($value -eq $currentName) { $nameEdit = $edit }
  }
  if ($pageMatches -and $nameEdit) { return $nameEdit }
  return $null
}

$results = New-Object System.Collections.Generic.List[object]
foreach ($entry in $mapping) {
  $index = $entry.index
  $newName = $entry.name
  $found = Find-AxisItem $index
  if (-not $found) { $results.Add([pscustomobject]@{ index = $index; name = $newName; ok = $false; reason = 'axis_item_missing' }); continue }
  $oldName = ($found.text -split ':', 2)[1]
  [AxisWin]::SetForegroundWindow([IntPtr]$process.MainWindowHandle) | Out-Null
  Start-Sleep -Milliseconds 400
  $scroll = $null
  if ($found.element.TryGetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern, [ref]$scroll)) { try { $scroll.ScrollIntoView() } catch {} }
  $sel = $null
  if ($found.element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$sel)) { try { $sel.Select() } catch {} }
  Start-Sleep -Milliseconds 900
  $edit = Find-NameEdit $index $oldName
  if (-not $edit) {
    Click-Rect $found.element.Current.BoundingRectangle
    Start-Sleep -Milliseconds 150
    Click-Rect $found.element.Current.BoundingRectangle
    Start-Sleep -Milliseconds 1500
    $edit = Find-NameEdit $index $oldName
  }
  if (-not $edit) { $results.Add([pscustomobject]@{ index = $index; name = $newName; ok = $false; reason = 'name_edit_missing' }); continue }
  Click-Rect $edit.Current.BoundingRectangle
  Start-Sleep -Milliseconds 250
  [System.Windows.Forms.SendKeys]::SendWait('^a')
  Start-Sleep -Milliseconds 120
  [System.Windows.Forms.Clipboard]::SetText($newName)
  Start-Sleep -Milliseconds 120
  [System.Windows.Forms.SendKeys]::SendWait('^v')
  Start-Sleep -Milliseconds 300
  [System.Windows.Forms.SendKeys]::SendWait('{TAB}')
  Start-Sleep -Milliseconds 700
  $value = Get-EditValue $edit
  if ($value -ne $newName) {
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Start-Sleep -Milliseconds 600
    $value = Get-EditValue $edit
  }
  $check = Find-AxisItem $index
  $treeText = if ($check) { [string]$check.text } else { '' }
  if ($value -eq $newName -and $check -and ($treeText -match [regex]::Escape($newName))) {
    $results.Add([pscustomobject]@{ index = $index; name = $newName; ok = $true; reason = ''; tree_text = $treeText })
  } else {
    $reason = 'verify_failed:value=' + $value + ';tree=' + $treeText
    $results.Add([pscustomobject]@{ index = $index; name = $newName; ok = $false; reason = $reason })
  }
}

$failed = @($results | Where-Object { -not $_.ok })
$report = [ordered]@{
  ok = ($failed.Count -eq 0)
  mapping_path = $MappingPath
  total = $results.Count
  renamed = @($results | Where-Object { $_.ok }).Count
  failed = @($failed | ForEach-Object { [pscustomobject]@{ index = $_.index; name = $_.name; reason = $_.reason } })
  results = $results.ToArray()
  generated_at = (Get-Date).ToString('o')
}
$reportPath = Join-Path $OutDir 'axis_rename_result.json'
$report | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 4
Write-Host ("KV_AXIS_RENAME: renamed={0}/{1} failed={2} report={3}" -f $report.renamed, $report.total, $failed.Count, $reportPath)
if ($failed.Count -gt 0) { exit 41 }
exit 0
