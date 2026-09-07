param([Parameter(Mandatory=$true)][string]$OutDir,[string]$FbModuleName='FB_Cylinder',[switch]$OpenSelected)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force $OutDir|Out-Null
$env:KV_WORKFLOW_RUN_LOG=Join-Path $OutDir 'run.log'
. (Join-Path $PSScriptRoot '..\guards\kv_ui_guard.ps1')
Initialize-KvUiGuard -OutDir $OutDir
Add-Type -AssemblyName UIAutomationClient
$ps=@(Get-Process Kvs | Where-Object {$_.MainWindowHandle -ne 0})
if($ps.Count -ne 1){throw 'KV_PROJECT_WINDOW_AMBIGUOUS'}
$p=$ps[0]
$root=[Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
function Snap([string]$label){
 $chain=@();$f=[Windows.Automation.AutomationElement]::FocusedElement
 for($i=0;$f -and $i -lt 18;$i++){
  $chain+=@{id=$f.Current.AutomationId;name=$f.Current.Name;type=$f.Current.ControlType.ProgrammaticName;hwnd=$f.Current.NativeWindowHandle;pid=$f.Current.ProcessId}
  $f=[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($f)
 }
 $record=@{label=$label;chain=$chain}
 $record|ConvertTo-Json -Depth 5|Set-Content (Join-Path $OutDir ($label+'.json')) -Encoding UTF8
 Write-KvUiGuardRunLog -Event 'focus_observation' -Data $record
}
Assert-KvUiForegroundHwnd -ExpectedHwnd $p.MainWindowHandle -Step 'focus experiment preflight' -ExpectedTitleLike '*KV STUDIO*' -AllowSingleRecovery|Out-Null
$tree=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'ProjectTreeView')))
$items=@($tree.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.Name -eq $FbModuleName -or $_.Current.Name.StartsWith($FbModuleName+':')})
if($items.Count -ne 1){throw 'KV_FB_TREE_ITEM_AMBIGUOUS'}
$item=$items[0];$item.SetFocus()
$sel=$item.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern);$sel.Select()
if(-not $sel.Current.IsSelected){throw 'KV_FB_TREE_SELECTION_FAILED'}
Snap 'selected_tree'
if($OpenSelected){
 Invoke-KvGuardedVkTap -TargetHwnd $p.MainWindowHandle -Step 'activate selected FB with Enter' -Vk 0x0D -ExpectedTitleLike '*KV STUDIO*' -SleepMs 200
 Snap 'after_enter'
}
Invoke-KvGuardedAltVk -TargetHwnd $p.MainWindowHandle -Step 'probe Alt L focus transition' -Vk 0x4C -ExpectedTitleLike '*KV STUDIO*' -SleepMs 150
Snap 'after_alt_l'
Invoke-KvGuardedShiftTab -TargetHwnd $p.MainWindowHandle -Step 'probe Shift Tab focus transition' -ExpectedTitleLike '*KV STUDIO*'
Snap 'after_shift_tab'
Invoke-KvGuardedCtrlChord -TargetHwnd $p.MainWindowHandle -Step 'probe Ctrl Tab focus transition' -Vk 0x09 -ExpectedTitleLike '*KV STUDIO*' -SleepMs 150
Snap 'after_ctrl_tab'
