param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string[]]$Models,
  [string]$OutDir = '',
  [int]$PerModuleBudgetSeconds = 10
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $scriptRoot 'guards\kv_ui_guard.ps1')
Add-Type -AssemblyName System.Windows.Forms
if ([string]::IsNullOrWhiteSpace($OutDir)) { $OutDir = Join-Path ([IO.Path]::GetTempPath()) ('kv_expansion_' + (Get-Date -Format 'yyyyMMdd_HHmmss')) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Initialize-KvUiGuard -OutDir $OutDir -CheckpointSubdir 'ui_guard'

if (-not ('KvExpansionGuardedWin32' -as [type])) {
Add-Type @'
using System; using System.Text; using System.Runtime.InteropServices;
public static class KvExpansionGuardedWin32 {
 public delegate bool CB(IntPtr h, IntPtr p);
 [StructLayout(LayoutKind.Sequential)] public struct RECT { public int left, top, right, bottom; }
 [DllImport("user32.dll")] public static extern bool EnumWindows(CB c, IntPtr p);
 [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr h, CB c, IntPtr p);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
 [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
 [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
 [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint p);
 [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
 [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int m, IntPtr w, IntPtr l);
 [DllImport("user32.dll")] public static extern int GetSystemMetrics(int n);
 [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
 [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
 [DllImport("gdi32.dll")] public static extern int GetDeviceCaps(IntPtr dc, int index);
 public const int BM_CLICK = 0x00F5;
 public const int LVM_FIRST = 0x1000, LVM_GETITEMCOUNT = LVM_FIRST + 4;
}
'@
}

$UnitEditorNeedle = -join (@(0x5355,0x5143,0x7F16,0x8F91,0x5668) | ForEach-Object {[char]$_})
$CpuPattern = '^\[0\]\s+KV-'
$projectLeaf = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
$unitSetPath = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($ProjectPath))) 'UnitSet.ue2'

function Write-Result($Value) { $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutDir 'result.json') -Encoding UTF8 }
function Test-ModelPersisted([string]$Model) {
  if(-not (Test-Path -LiteralPath $unitSetPath -PathType Leaf)){return $false}
  $matches=@(rg -a -o -N ('(?i)'+[regex]::Escape($Model)+'\*?') $unitSetPath 2>$null | Sort-Object -Unique)
  return ($matches -match ('^'+[regex]::Escape($Model)+'\*?$')).Count -gt 0
}
function Get-Scale {
  $dc=[KvExpansionGuardedWin32]::GetDC([IntPtr]::Zero)
  try { return [double][KvExpansionGuardedWin32]::GetDeviceCaps($dc,118) / [double][KvExpansionGuardedWin32]::GetSystemMetrics(0) }
  finally { [void][KvExpansionGuardedWin32]::ReleaseDC([IntPtr]::Zero,$dc) }
}
function Get-KvsMain {
  $p=Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$projectLeaf*"} | Select-Object -First 1
  if(-not $p){ throw "KV_PROJECT_NOT_OPEN: open '$ProjectPath' in KV STUDIO before running this workflow." }; return $p
}
function Find-UnitEditor([int]$ProcessId) {
  $script:found=[IntPtr]::Zero
  $cb=[KvExpansionGuardedWin32+CB]{param($h,$l);$s=[Text.StringBuilder]::new(512);[void][KvExpansionGuardedWin32]::GetWindowText($h,$s,512);$windowPid=[uint32]0;[void][KvExpansionGuardedWin32]::GetWindowThreadProcessId($h,[ref]$windowPid);if($windowPid -eq $ProcessId -and $s.ToString().Contains($UnitEditorNeedle)){$script:found=$h;return $false};$true}
  [void][KvExpansionGuardedWin32]::EnumWindows($cb,[IntPtr]::Zero); return $script:found
}
function Get-Child([IntPtr]$Parent,[string]$Class,[int]$Id,[switch]$VisibleOnly) {
  $script:found=[IntPtr]::Zero
  $cb=[KvExpansionGuardedWin32+CB]{param($h,$l);$s=[Text.StringBuilder]::new(128);[void][KvExpansionGuardedWin32]::GetClassName($h,$s,128);if(((-not $Class) -or $s.ToString() -eq $Class) -and [KvExpansionGuardedWin32]::GetDlgCtrlID($h)-eq $Id -and ((-not $VisibleOnly) -or [KvExpansionGuardedWin32]::IsWindowVisible($h))){$script:found=$h;return $false};$true}
  [void][KvExpansionGuardedWin32]::EnumChildWindows($Parent,$cb,[IntPtr]::Zero); return $script:found
}
function Get-ChildText([IntPtr]$Parent,[int]$Id) { $h=Get-Child $Parent 'Static' $Id -VisibleOnly; if($h -eq [IntPtr]::Zero){return ''};$s=[Text.StringBuilder]::new(512);[void][KvExpansionGuardedWin32]::GetWindowText($h,$s,$s.Capacity);return $s.ToString() }
function Click-Relative([IntPtr]$Target,[IntPtr]$RectHwnd,[int]$Dx,[int]$Dy,[string]$Step) {
  $r=New-Object KvExpansionGuardedWin32+RECT;[void][KvExpansionGuardedWin32]::GetWindowRect($RectHwnd,[ref]$r);$scale=Get-Scale
  Invoke-KvGuardedMouseClick -TargetHwnd $Target -Step $Step -X ([int](($r.left+$Dx)*$scale)) -Y ([int](($r.top+$Dy)*$scale)) -ExpectedTitleLike ('*'+$UnitEditorNeedle+'*') -SleepMs 140
}
function Wait-VisibleChild([IntPtr]$Editor,[string]$Class,[int]$Id,[int]$Ms=2000) {
  $deadline=(Get-Date).AddMilliseconds($Ms);do{$h=Get-Child $Editor $Class $Id -VisibleOnly;if($h -ne [IntPtr]::Zero){return $h};Start-Sleep -Milliseconds 50}while((Get-Date)-lt$deadline);return [IntPtr]::Zero
}
function Open-UnitEditor([System.Diagnostics.Process]$Process) {
  $existing=Find-UnitEditor $Process.Id;if($existing -ne [IntPtr]::Zero){return $existing}
  $main=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Process.MainWindowHandle)
  $items=$main.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::TreeItem)))
  $cpu=$null;for($i=0;$i-lt$items.Count;$i++){if($items.Item($i).Current.Name -match $CpuPattern){$cpu=$items.Item($i);break}}
  if(-not $cpu){throw 'KV_CPU_TREE_ITEM_NOT_FOUND'}
  if(-not(Invoke-KvUiGuardForceForeground -TargetHwnd ([IntPtr]$Process.MainWindowHandle))){throw 'KV_MAIN_FOREGROUND_RESTORE_FAILED'}
  $sel=$null;if($cpu.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$sel)){$sel.Select()};$cpu.SetFocus()
  Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd ([IntPtr]$Process.MainWindowHandle) -Step 'open unit editor from CPU tree item' -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO*' -SuccessTitleLike @('*'+$UnitEditorNeedle+'*') -Action 'open unit editor' -SleepMs 650
  $deadline=(Get-Date).AddSeconds(5);do{$e=Find-UnitEditor $Process.Id;if($e-ne[IntPtr]::Zero){return $e};Start-Sleep -Milliseconds 60}while((Get-Date)-lt$deadline);throw 'KV_UNIT_EDITOR_OPEN_TIMEOUT'
}
function Set-FlatCatalog([IntPtr]$Editor) {
  $tab=Get-Child $Editor '' 501 -VisibleOnly
  if($tab -eq [IntPtr]::Zero){ throw 'KV_UNIT_CATALOG_TAB_NOT_FOUND' }
  # The catalog tab remains present even while an existing-unit page is shown.
  # Its first tab position is stable for this editor; resolve the tab HWND and
  # scale its screen rectangle rather than relying on the editor window size.
  Click-Relative $Editor $tab 43 12 'select unit catalog tab'
  $toolbar=Get-Child $Editor 'ToolbarWindow32' 59392 -VisibleOnly
  if($toolbar-eq[IntPtr]::Zero){throw 'KV_UNIT_CATALOG_TOOLBAR_NOT_FOUND'}
  foreach($offset in @(12,38,64,90)){ Click-Relative $Editor $toolbar $offset 12 "select flat catalog presentation x$offset" }
  $grid=Wait-VisibleChild $Editor 'SysListView32' 568 1800;if($grid-eq[IntPtr]::Zero){throw 'KV_FLAT_UNIT_CATALOG_NOT_VISIBLE'};return $grid
}
function Find-CatalogRow([IntPtr]$Editor,[IntPtr]$Grid,[string]$Model) {
  # The catalog is an owner-data list: native/UIA item text is unavailable.
  # Use the supported keyboard selection path and treat static 698 as the oracle.
  Click-Relative $Editor $Grid 200 20 'focus flat catalog for dynamic model lookup'
  $count=[KvExpansionGuardedWin32]::SendMessage($Grid,[KvExpansionGuardedWin32]::LVM_GETITEMCOUNT,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()
  if($count -le 0 -or $count -gt 4096){$count=256}
  for($i=0;$i -lt $count;$i++) {
    $keys = if($i -eq 0){'^{HOME}'}else{'^{HOME}'+('{DOWN}' * $i)}
    Invoke-KvGuardedSendKeys -TargetHwnd $Editor -Step ("lookup catalog row $i for $Model") -Keys $keys -ExpectedTitleLike ('*'+$UnitEditorNeedle+'*') -Action 'select catalog row by guarded keyboard navigation' -SleepMs 35
    $actual=Get-ChildText $Editor 698
    if($actual -like ($Model+'*')) { return [pscustomobject]@{row=$i;actual=$actual;count=$count} }
  }
  throw "KV_MODEL_NOT_FOUND_IN_CATALOG: '$Model' (catalog_count=$count)"
}
function Add-One([IntPtr]$Editor,[string]$Model) {
  $sw=[Diagnostics.Stopwatch]::StartNew();$grid=Set-FlatCatalog $Editor
  $lookup=Find-CatalogRow $Editor $grid $Model; $row=$lookup.row
  if((Get-ChildText $Editor 698) -notlike "$Model*"){throw "KV_CATALOG_MODEL_ORACLE_FAILED: expected $Model, selected '$(Get-ChildText $Editor 698)'"}
  Invoke-KvGuardedSendKeys -TargetHwnd $Editor -Step "insert $Model selected catalog row" -Keys '{ENTER}' -ExpectedTitleLike ('*'+$UnitEditorNeedle+'*') -Action 'insert dynamically resolved catalog row' -SleepMs 220
  $elapsed=[math]::Round($sw.Elapsed.TotalSeconds,3)
  if($elapsed -ge $PerModuleBudgetSeconds){throw "KV_EXPANSION_UNIT_TIMEOUT: $Model took $elapsed seconds (budget $PerModuleBudgetSeconds)."}
  return [pscustomobject]@{model=$Model;elapsed_seconds=$elapsed;catalog_oracle=$Model;catalog_row=$row;catalog_count=$lookup.count;flat_catalog_control_id=568}
}

try {
  if(-not(Test-Path -LiteralPath $ProjectPath -PathType Leaf)){throw "KV_PROJECT_MISSING:$ProjectPath"}
  $process=Get-KvsMain
  $beforeLength=(Get-Item -LiteralPath $unitSetPath).Length
  $actions=@();$missing=@()
  foreach($model in $Models){
    if(Test-ModelPersisted $model){$actions += [pscustomobject]@{model=$model;status='already_present';elapsed_seconds=0}}
    else{$missing += $model}
  }
  if($missing.Count -gt 0){
    $editor=Open-UnitEditor $process
    foreach($model in $missing){$actions += Add-One $editor $model}
  }
  else {$editor=Find-UnitEditor $process.Id}
  if($missing.Count -eq 0){
    $persisted=@($Models|ForEach-Object {$_+'*'})
    $result=[ordered]@{ok=$true;project_path=[IO.Path]::GetFullPath($ProjectPath);models=$Models;actions=$actions;unitset_path=$unitSetPath;unitset_length_before=$beforeLength;unitset_length_after=$beforeLength;persisted_models=$persisted;clean_end_state=(Get-KvForegroundSnapshot)}
    Write-Result $result; $result | ConvertTo-Json -Depth 12; return
  }
  $ok=Get-Child $editor 'Button' 23017
  if($ok-eq[IntPtr]::Zero){throw 'KV_UNIT_EDITOR_OK_BUTTON_NOT_FOUND'}
  # Direct control invocation is permitted because the button identity is resolved first; no global input is used.
  [void][KvExpansionGuardedWin32]::SendMessage($ok,[KvExpansionGuardedWin32]::BM_CLICK,[IntPtr]::Zero,[IntPtr]::Zero)
  $modelPattern='(?i)'+(($Models|ForEach-Object {[regex]::Escape($_)}) -join '|')+'\*?'
  $deadline=(Get-Date).AddSeconds(8);do{Start-Sleep -Milliseconds 100;$matchCount=@(rg -a -o -N $modelPattern $unitSetPath | Sort-Object -Unique).Count}while($matchCount -lt $Models.Count -and (Get-Date)-lt$deadline)
  $persisted=@(rg -a -o -N ('(?i)'+(($Models|ForEach-Object {[regex]::Escape($_)}) -join '|')+'\*?') $unitSetPath | Sort-Object -Unique)
  foreach($model in $Models){if(-not($persisted -match ('^'+[regex]::Escape($model)+'\*?$'))){throw "KV_UNITSET_PERSISTENCE_FAILED:$model"}}
  if(-not(Invoke-KvUiGuardForceForeground -TargetHwnd ([IntPtr]$process.MainWindowHandle))){throw 'KV_MAIN_FOREGROUND_RESTORE_FAILED_AFTER_COMMIT'}
  Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$process.MainWindowHandle) -Step 'save project after unit configuration' -Keys '^s' -ExpectedTitleLike 'KV STUDIO*' -Action 'save committed unit layout' -SleepMs 500
  $result=[ordered]@{ok=$true;project_path=[IO.Path]::GetFullPath($ProjectPath);models=$Models;actions=$actions;unitset_path=$unitSetPath;unitset_length_before=$beforeLength;unitset_length_after=(Get-Item $unitSetPath).Length;persisted_models=$persisted;clean_end_state=(Get-KvForegroundSnapshot)}
  Write-Result $result; $result | ConvertTo-Json -Depth 12
} catch { $failure=[ordered]@{ok=$false;error_code=if($_.Exception.Message -match '^KV_[A-Z0-9_:-]+'){($_.Exception.Message -split ':')[0]}else{'KV_EXPANSION_UNIT_CONFIGURATION_FAILED'};message=$_.Exception.Message;project_path=$ProjectPath;evidence_dir=$OutDir;foreground=(Get-KvForegroundSnapshot)}; $failure|ConvertTo-Json -Depth 10|Set-Content (Join-Path $OutDir 'failure.json') -Encoding UTF8; throw }
