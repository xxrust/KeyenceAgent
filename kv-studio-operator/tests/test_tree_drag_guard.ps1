param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
class DragTestAutomation {
  static [object]$Target
  static [object] FromHandle([IntPtr]$handle){return [DragTestAutomation]::Target}
}
class DragTestControlType {static [string]$TreeItem='TreeItem'}
class DragTestKeyboard {static [int]$ModifierKeys=0}
class DragTestTreeWalker {static [object]$ControlViewWalker}
class DragTestWin32 {
  static [int]$CursorCalls=0
  static [int]$FailCursorAt=0
  static [int]$ForegroundCalls=0
  static [int]$LoseFocusAt=0
  static [int]$Down=0
  static [int]$Up=0
  static [bool] SetCursorPos([int]$x,[int]$y){[DragTestWin32]::CursorCalls++;return [DragTestWin32]::CursorCalls -ne [DragTestWin32]::FailCursorAt}
  static [IntPtr] GetForegroundWindow(){[DragTestWin32]::ForegroundCalls++;if([DragTestWin32]::ForegroundCalls -eq [DragTestWin32]::LoseFocusAt){return [IntPtr]99};return [IntPtr]1}
  static [void] mouse_event([int]$flags,[int]$x,[int]$y,[int]$data,[int]$extra){if($flags -eq 2){[DragTestWin32]::Down++};if($flags -eq 4){[DragTestWin32]::Up++}}
}
function New-Rect([double]$x=0,[double]$y=0,[double]$w=300,[double]$h=400){
  $r=[pscustomobject]@{Left=$x;Top=$y;Width=$w;Height=$h}
  $r|Add-Member -MemberType ScriptMethod -Name Contains -Value {param([double]$x,[double]$y) return $x -ge $this.Left -and $y -ge $this.Top -and $x -le $this.Left+$this.Width -and $y -le $this.Top+$this.Height}
  return $r
}
function New-Node([int]$Id,[string]$Aid,[long]$Hwnd,[object]$Parent,[object]$Rect){
  $n=[pscustomobject]@{Id=$Id;Parent=$Parent;Current=[pscustomobject]@{ProcessId=12;ControlType='TreeItem';IsOffscreen=$false;IsEnabled=$true;AutomationId=$Aid;NativeWindowHandle=$Hwnd;BoundingRectangle=$Rect;Name="node$Id"}}
  $n|Add-Member -MemberType ScriptMethod -Name GetRuntimeId -Value {return @($this.Id)}
  return $n
}
$walker=[pscustomobject]@{}
$walker|Add-Member -MemberType ScriptMethod -Name GetParent -Value {param($n)return $n.Parent}
[DragTestTreeWalker]::ControlViewWalker=$walker
function Assert-KvUiForegroundHwnd {param($ExpectedHwnd,$Step,$ExpectedTitleLike,[switch]$AllowSingleRecovery)return @{hwnd=1}}
function Write-KvUiGuardCheckpoint {param($Step,$Status,$Action,$Expected,$Before,$After,$Evidence,$Message)return 'mock-checkpoint'}
function Complete-KvUiGuardAtomicAction {param($Stopwatch,$Step,$Action,$TargetHwnd,$ExpectedTitleLike)}
function Start-Sleep {param($Milliseconds)}
$tokens=$null;$errors=$null
$path=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts/guards/kv_ui_guard.ps1'
$ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Guard parse failed'}
$definition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Invoke-KvGuardedTreeItemDrag'},$true)
$text=$definition.Extent.Text.Replace('[Windows.Automation.AutomationElement]','[DragTestAutomation]').Replace('[Windows.Automation.ControlType]','[DragTestControlType]').Replace('[Windows.Automation.TreeWalker]','[DragTestTreeWalker]').Replace('[KvSharedUiGuardWin32]','[DragTestWin32]').Replace('[Windows.Forms.Control]','[DragTestKeyboard]')
. ([scriptblock]::Create($text))
$cases=@(
  @{name='valid';code=''},@{name='different_pid';code='KV_TREE_DRAG_TARGET_INVALID'},
  @{name='same_item';code='KV_TREE_DRAG_SAME_TARGET'},@{name='descendant';code='KV_TREE_DRAG_DESCENDANT_TARGET'},
  @{name='different_tree';code='KV_TREE_DRAG_DIFFERENT_TREE'},@{name='other_window';code='KV_TREE_DRAG_WINDOW_MISMATCH'},
  @{name='outside_rect';code='KV_TREE_DRAG_POINT_OUTSIDE_TREE'},@{name='nan_rect';code='KV_TREE_DRAG_RECT_INVALID'},
  @{name='cursor_failed_before_down';code='KV_TREE_DRAG_CURSOR_FAILED'},@{name='cursor_failed_mid_drag';code='KV_TREE_DRAG_CURSOR_FAILED'},
  @{name='focus_lost_mid_drag';code='KV_TREE_DRAG_FOCUS_LOST'},
  @{name='ctrl_pressed';code='KV_TREE_DRAG_MODIFIER_PRESSED'},@{name='shift_pressed';code='KV_TREE_DRAG_MODIFIER_PRESSED'},@{name='alt_pressed';code='KV_TREE_DRAG_MODIFIER_PRESSED'}
)
$results=@()
foreach($case in $cases){
  [DragTestWin32]::CursorCalls=0;[DragTestWin32]::FailCursorAt=0;[DragTestWin32]::ForegroundCalls=0;[DragTestWin32]::LoseFocusAt=0;[DragTestWin32]::Down=0;[DragTestWin32]::Up=0
  [DragTestKeyboard]::ModifierKeys=0
  $window=New-Node 1 'Main' 1 $null (New-Rect)
  $tree=New-Node 2 'ProjectTreeView' 2 $window (New-Rect)
  $source=New-Node 3 '' 0 $tree (New-Rect 10 10 60 20)
  $destination=New-Node 4 '' 0 $tree (New-Rect 10 60 80 20)
  [DragTestAutomation]::Target=$window
  switch($case.name){
    'different_pid'{$destination.Current.ProcessId=99}
    'same_item'{$destination=$source}
    'descendant'{$destination.Parent=$source}
    'different_tree'{$destination.Parent=New-Node 5 'ProjectTreeView' 5 $window (New-Rect)}
    'other_window'{$tree.Parent=New-Node 8 'Main' 8 $null (New-Rect)}
    'outside_rect'{$destination.Current.BoundingRectangle=New-Rect 1000 1000 80 20}
    'nan_rect'{$destination.Current.BoundingRectangle.Left=[double]::NaN}
    'cursor_failed_before_down'{[DragTestWin32]::FailCursorAt=1}
    'cursor_failed_mid_drag'{[DragTestWin32]::FailCursorAt=3}
    'focus_lost_mid_drag'{[DragTestWin32]::LoseFocusAt=3}
    'ctrl_pressed'{[DragTestKeyboard]::ModifierKeys=131072}
    'shift_pressed'{[DragTestKeyboard]::ModifierKeys=65536}
    'alt_pressed'{[DragTestKeyboard]::ModifierKeys=262144}
  }
  $caught=''
  try{Invoke-KvGuardedTreeItemDrag -TargetHwnd ([IntPtr]1) -Source $source -Destination $destination}catch{$caught=$_.Exception.Message}
  if(($case.code -and -not $caught.StartsWith($case.code)) -or (-not $case.code -and $caught)){throw "$($case.name) expected $($case.code), got $caught"}
  if([DragTestWin32]::Down -ne [DragTestWin32]::Up){throw "Mouse button not released: $($case.name)"}
  if($case.name -notin @('valid','cursor_failed_mid_drag','focus_lost_mid_drag') -and [DragTestWin32]::Down){throw "Rejected target received mouse input: $($case.name)"}
  $results+=@{name=$case.name;ok=$true;mouse_down=[DragTestWin32]::Down;mouse_up=[DragTestWin32]::Up}
}
New-Item -ItemType Directory -Force -Path $OutDir|Out-Null
@{ok=$true;ui_started=$false;input_operations='mocked';tests=$results}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($results.Count) mocked drag-guard tests."
