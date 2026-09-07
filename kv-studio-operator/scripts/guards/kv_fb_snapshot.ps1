# Shared read-only argument-grid adapter. Requires initialized kv_ui_guard.
Add-Type -AssemblyName System.Windows.Forms
if(-not ('KvFbSnapshotNative' -as [type])){Add-Type @'
using System;using System.Runtime.InteropServices;
public class KvFbSnapshotNative {
 [DllImport("user32.dll")]public static extern uint GetClipboardSequenceNumber();
}
'@}
function Find-KvFbElement($Root,[string]$Id){
 $Root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,$Id)))
}
function Get-KvFbFocusAncestor([string]$Id,[int]$ProcessIdValue){
 $e=[Windows.Automation.AutomationElement]::FocusedElement
 for($i=0;$e -and $i -lt 18;$i++){
  if($e.Current.ProcessId -ne $ProcessIdValue){return $null}
  if($e.Current.AutomationId -eq $Id){return $e}
  $e=[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($e)
 }
 return $null
}
function Select-KvFbArgumentPane($Editor,[int]$ProcessIdValue){
 $surfaces=@($Editor.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'FuncBlockParamVariableControl')))|Where-Object {-not $_.Current.IsOffscreen -and $_.Current.ProcessId -eq $ProcessIdValue})
 if($surfaces.Count -gt 1){throw 'KV_FB_ARGUMENT_PANE_AMBIGUOUS'}
 if($surfaces.Count -eq 1){
  if(-not (Find-KvFbElement $surfaces[0] '_grid') -or -not (Find-KvFbElement $surfaces[0] '_usageFilterComboBox')){throw 'KV_FB_ARGUMENT_SURFACE_SIGNATURE_MISMATCH'}
  Write-KvUiGuardRunLog -Event 'fb_argument_pane_selected' -Data @{editor_hwnd=$Editor.Current.NativeWindowHandle;pane_hwnd=$surfaces[0].Current.NativeWindowHandle;pane_id='FuncBlockParamVariableControl';process_id=$ProcessIdValue}
  return $surfaces[0]
 }
 $matches=@($Editor.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'_tabFBMacroParam'))))
 $tabs=@($matches|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::TabItem -and -not $_.Current.IsOffscreen -and $_.Current.ProcessId -eq $ProcessIdValue})
 if($tabs.Count -ne 1){
  $all=@($Editor.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition))
  Write-KvUiGuardRunLog -Event 'fb_argument_tab_diagnostic' -Data @{editor_hwnd=$Editor.Current.NativeWindowHandle;matches_count=$matches.Count;tab_count=$tabs.Count;controls=@($all|ForEach-Object {@{id=$_.Current.AutomationId;type=$_.Current.ControlType.ProgrammaticName;name=$_.Current.Name;off=$_.Current.IsOffscreen}})}
  throw 'KV_FB_ARGUMENT_TAB_AMBIGUOUS'
 }
 $selection=$tabs[0].GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)
 if(-not $selection.Current.IsSelected){$selection.Select()}
 if(-not $selection.Current.IsSelected){throw 'KV_FB_ARGUMENT_TAB_NOT_SELECTED'}
 $panes=@($matches|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::Pane -and -not $_.Current.IsOffscreen -and $_.Current.ProcessId -eq $ProcessIdValue})
 if($panes.Count -ne 1){throw 'KV_FB_ARGUMENT_PANE_AMBIGUOUS'}
 Write-KvUiGuardRunLog -Event 'fb_argument_pane_selected' -Data @{editor_hwnd=$Editor.Current.NativeWindowHandle;pane_hwnd=$panes[0].Current.NativeWindowHandle;process_id=$ProcessIdValue}
 return $panes[0]
}
function Assert-KvFbGridFocus($Pane,$Grid){
 if(-not $Pane -or $Pane.Current.AutomationId -notin @('_tabFBMacroParam','FuncBlockParamVariableControl') -or $Pane.Current.IsOffscreen){throw 'KV_FB_ARGUMENT_PANE_IDENTITY_MISMATCH'}
 $f=[Windows.Automation.AutomationElement]::FocusedElement
 if(-not $f -or -not $f.Equals($Grid) -or $f.Current.ProcessId -ne $Pane.Current.ProcessId){throw 'KV_FB_GRID_FOCUS_LOST'}
 $e=$f;$owned=$false
 for($i=0;$e -and $i -lt 8;$i++){if($e.Equals($Pane)){$owned=$true;break};$e=[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($e)}
 if(-not $owned){throw 'KV_FB_GRID_OWNER_MISMATCH'}
 if($f.Current.AutomationId -eq '_grid'){return}
 if($f.Current.ControlType -ne [Windows.Automation.ControlType]::Pane -or -not (Find-KvFbElement $f '_hScrollBar')){throw 'KV_FB_GRID_SIGNATURE_MISMATCH'}
}
function Copy-KvFbArgumentPane($Pane,[IntPtr]$MainHwnd,[string]$ProjectNeedle,[string]$OutDir){
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $filter=Find-KvFbElement $Pane '_usageFilterComboBox'
 if(-not $filter -or $Pane.Current.IsOffscreen){throw 'KV_FB_ARGUMENT_FILTER_MISSING'}
 Assert-KvUiForegroundHwnd -ExpectedHwnd $MainHwnd -Step 'FB copy foreground before focus' -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -AllowSingleRecovery|Out-Null
 Invoke-KvGuardedAltVk -TargetHwnd $MainHwnd -Step 'FB copy Alt L' -Vk 0x4C -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -SleepMs 120
 $afterAlt=[Windows.Automation.AutomationElement]::FocusedElement
 # A scrollbar alone also matches the ladder editor. Direct-grid acceptance
 # requires argument-pane ancestry, not merely a grid-like shape.
 $directGrid=$false
 try { Assert-KvFbGridFocus $Pane $afterAlt; $directGrid=$true } catch {}
 if($directGrid){
   $grid=$afterAlt
   Write-KvUiGuardRunLog -Event 'control_focus_verified' -Data @{step='FB grid direct focus after Alt L';hwnd=$grid.Current.NativeWindowHandle;automation_id=$grid.Current.AutomationId;route='AltL-direct-grid'}
 } else {
 $assertFilter={if(-not [Windows.Automation.AutomationElement]::FocusedElement.Equals($filter)){throw 'KV_FB_FILTER_FOCUS_MISMATCH'}}
 & $assertFilter
 Write-KvUiGuardRunLog -Event 'control_focus_verified' -Data @{step='FB usage filter';hwnd=$filter.Current.NativeWindowHandle;automation_id=$filter.Current.AutomationId}
 Invoke-KvGuardedShiftTab -TargetHwnd $MainHwnd -Step 'FB copy Shift Tab from verified filter' -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -FocusOracle $assertFilter
 $grid=[Windows.Automation.AutomationElement]::FocusedElement
 Assert-KvFbGridFocus $Pane $grid
 }
 Assert-KvFbGridFocus $Pane $grid
 $focus=@{grid_hwnd=$grid.Current.NativeWindowHandle;grid_id=$grid.Current.AutomationId;pane_hwnd=$Pane.Current.NativeWindowHandle;pane_id=$Pane.Current.AutomationId;owner_verified=$true}
 $focus|ConvertTo-Json|Set-Content (Join-Path $OutDir 'fb_grid_focus.json') -Encoding UTF8
 Write-KvUiGuardRunLog -Event 'control_focus_verified' -Data $focus
 $oracle={Assert-KvFbGridFocus $Pane $grid}
 Invoke-KvGuardedCtrlChord -TargetHwnd $MainHwnd -Step 'FB copy select all' -Vk 0x41 -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -SleepMs 120 -FocusOracle $oracle
 $seq=[KvFbSnapshotNative]::GetClipboardSequenceNumber()
 Invoke-KvGuardedCtrlChord -TargetHwnd $MainHwnd -Step 'FB copy selected arguments' -Vk 0x43 -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -SleepMs 120 -FocusOracle $oracle
 & $oracle
 $text=''
 for($i=0;$i -lt 10;$i++){if([KvFbSnapshotNative]::GetClipboardSequenceNumber() -ne $seq){$text=[Windows.Forms.Clipboard]::GetText();break};Start-Sleep -Milliseconds 50}
 if([string]::IsNullOrWhiteSpace($text)){throw 'KV_FB_SNAPSHOT_EMPTY_OR_CLIPBOARD_STALE'}
 $rows=@($text -split '\r?\n'|Where-Object {$_})
 $names=@{}
 foreach($line in $rows){$c=$line.Split("`t");if($c.Count -lt 8 -or -not $c[0] -or $c[1] -notin @('IN','OUT','IN-OUT','UNIT') -or -not $c[3] -or $names.ContainsKey($c[0])){throw 'KV_FB_SNAPSHOT_SCHEMA_MISMATCH'};$names[$c[0]]=$true}
 $path=Join-Path $OutDir 'fb_arguments_raw.tsv'
 [IO.File]::WriteAllText($path,$text,[Text.Encoding]::UTF8)
 Complete-KvUiGuardAtomicAction -Stopwatch $watch -Step 'FB argument focus and copy' -Action 'verified filter to grid and fresh full-column copy' -TargetHwnd $MainHwnd -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*"|Out-Null
 return [pscustomobject]@{raw_path=$path;row_count=$rows.Count;focus_verified=$true;clipboard_fresh=$true;elapsed_ms=$watch.ElapsedMilliseconds}
}
