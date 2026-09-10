# Shared declaration focus and argument-copy adapter. Requires initialized kv_ui_guard.
Add-Type -AssemblyName System.Windows.Forms
if(-not ('KvFbSnapshotNative' -as [type])){Add-Type @'
using System;using System.Runtime.InteropServices;
public class KvFbSnapshotNative {
 [DllImport("user32.dll")]public static extern uint GetClipboardSequenceNumber();
 [DllImport("user32.dll")]public static extern IntPtr GetWindow(IntPtr hwnd,uint cmd);
 [DllImport("user32.dll")]public static extern bool IsWindowVisible(IntPtr hwnd);
}
'@}
function Assert-KvFbNoPopup([IntPtr]$MainHwnd){
 $popup=[KvFbSnapshotNative]::GetWindow($MainHwnd,6)
 if($popup -ne [IntPtr]::Zero -and $popup -ne $MainHwnd -and [KvFbSnapshotNative]::IsWindowVisible($popup)){
  Write-KvUiGuardRunLog -Event 'fb_snapshot_blocked_popup' -Data @{main_hwnd=$MainHwnd.ToInt64();popup_hwnd=$popup.ToInt64();error_code='KV_MODAL_PRESENT'}
  throw 'KV_MODAL_PRESENT'
 }
}
function Find-KvFbElement($Root,[string]$Id){
 $Root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,$Id)))
}
function Assert-KvFbGridFocus($Pane,$Grid){
 if(-not $Pane -or $Pane.Current.AutomationId -notin @('_tabFBMacroParam','FuncBlockParamVariableControl') -or $Pane.Current.IsOffscreen){throw 'KV_FB_ARGUMENT_PANE_IDENTITY_MISMATCH'}
 $f=[Windows.Automation.AutomationElement]::FocusedElement
 if(-not $f -or -not $f.Equals($Grid) -or $f.Current.ProcessId -ne $Pane.Current.ProcessId){throw 'KV_FB_GRID_FOCUS_LOST'}
 $e=$f;$owned=$false
 for($i=0;$e -and $i -le 5;$i++){if($e.Equals($Pane)){$owned=$true;break};$e=[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($e)}
 if(-not $owned){throw 'KV_FB_GRID_OWNER_MISMATCH'}
 if($f.Current.AutomationId -eq '_grid'){return}
 if($f.Current.ControlType -ne [Windows.Automation.ControlType]::Pane -or -not (Find-KvFbElement $f '_hScrollBar')){throw 'KV_FB_GRID_SIGNATURE_MISMATCH'}
}
function Get-KvFbDeclarationFocus([int]$ProcessIdValue) {
 $focus=[Windows.Automation.AutomationElement]::FocusedElement
 $element=$focus
 for($depth=0;$element -and $depth -le 5;$depth++){
  if($element.Current.ProcessId -ne $ProcessIdValue){break}
  $id=[string]$element.Current.AutomationId
  $table=if($id -in @('FuncBlockParamVariableControl','_tabFBMacroParam')){'arguments'}elseif($id -in @('KvVariableLocalControl','_tabLocal')){'locals'}else{''}
  if($table){return [pscustomobject]@{table=$table;pane=$element;focus=$focus;is_grid=($focus.Current.AutomationId -eq '_grid')}}
  $element=[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($element)
 }
 throw 'KV_FB_CURRENT_TABLE_UNKNOWN'
}
function Focus-KvFbArgumentGrid([IntPtr]$MainHwnd,[string]$ProjectNeedle) {
 $watch=[Diagnostics.Stopwatch]::StartNew()
 $processIdValue=[Windows.Automation.AutomationElement]::FromHandle($MainHwnd).Current.ProcessId
 Assert-KvFbNoPopup $MainHwnd
 # Alt+L opens the remembered declaration tab; resolve its owner afterwards.
 Invoke-KvGuardedAltVk -TargetHwnd $MainHwnd -Step 'FB declarations Alt L' -Vk 0x4C -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -SleepMs 120
 $state=Get-KvFbDeclarationFocus $processIdValue
 $initialTable=$state.table
 $count=if($state.table -eq 'locals'){1}elseif($state.is_grid){0}else{2}
 Write-KvUiGuardRunLog -Event 'fb_declaration_route' -Data @{initial_table=$initialTable;focus_id=$state.focus.Current.AutomationId;ctrl_tab_count=$count}
 for($i=1;$i -le $count;$i++){
  $expectedFocus=$state.focus
  $oracle={if(-not [Windows.Automation.AutomationElement]::FocusedElement.Equals($expectedFocus)){throw 'KV_FB_GRID_FOCUS_LOST'}}
  Invoke-KvGuardedCtrlChord -TargetHwnd $MainHwnd -Step "FB declarations Ctrl Tab $i of $count" -Vk 0x09 -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -SleepMs 120 -FocusOracle $oracle
  $state=Get-KvFbDeclarationFocus $processIdValue
  $expectedTable=if($initialTable -eq 'arguments' -and $i -eq 1){'locals'}else{'arguments'}
  Write-KvUiGuardRunLog -Event 'fb_declaration_transition' -Data @{index=$i;table=$state.table;focus_id=$state.focus.Current.AutomationId}
  if($state.table -ne $expectedTable){throw 'KV_FB_DECLARATION_TRANSITION_MISMATCH'}
 }
 if($state.table -ne 'arguments'){throw 'KV_FB_ARGUMENT_TABLE_NOT_ACTIVE'}
 Assert-KvFbGridFocus $state.pane $state.focus
 Complete-KvUiGuardAtomicAction -Stopwatch $watch -Step 'focus FB argument grid' -Action 'Alt L then state-dependent Ctrl Tab' -TargetHwnd $MainHwnd -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*"|Out-Null
 return $state
}
function Copy-KvFbArgumentPane($Pane,[IntPtr]$MainHwnd,[string]$ProjectNeedle,[string]$OutDir,[switch]$AlreadyFocused){
 $watch=[Diagnostics.Stopwatch]::StartNew()
 if($AlreadyFocused){
  $grid=[Windows.Automation.AutomationElement]::FocusedElement
 } else {
  $state=Focus-KvFbArgumentGrid $MainHwnd $ProjectNeedle
  $Pane=$state.pane
  $grid=$state.focus
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
 if([KvFbSnapshotNative]::GetClipboardSequenceNumber() -eq $seq){throw 'KV_FB_SNAPSHOT_EMPTY_OR_CLIPBOARD_STALE'}
 # The trailing blank insertion row is not a persisted argument.
 $rows=@($text -split '\r?\n'|Where-Object {$_.Trim()})
 $names=@{}
 foreach($line in $rows){$c=$line.Split("`t");if($c.Count -lt 8 -or -not $c[0] -or $c[1] -notin @('IN','OUT','IN-OUT','UNIT') -or -not $c[3] -or $names.ContainsKey($c[0])){throw 'KV_FB_SNAPSHOT_SCHEMA_MISMATCH'};$names[$c[0]]=$true}
 $path=Join-Path $OutDir 'fb_arguments_raw.tsv'
 [IO.File]::WriteAllText($path,$text,[Text.Encoding]::UTF8)
 Complete-KvUiGuardAtomicAction -Stopwatch $watch -Step 'FB argument focus and copy' -Action 'verified filter to grid and fresh full-column copy' -TargetHwnd $MainHwnd -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*"|Out-Null
 return [pscustomobject]@{raw_path=$path;row_count=$rows.Count;focus_verified=$true;clipboard_fresh=$true;elapsed_ms=$watch.ElapsedMilliseconds}
}
