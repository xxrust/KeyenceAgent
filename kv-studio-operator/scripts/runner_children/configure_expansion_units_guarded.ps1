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
function Log([string]$Event,[hashtable]$Data=@{}) {
  Write-KvUiGuardRunLog -Event $Event -Data $Data
}
Log 'workflow_started' @{ project_path = [IO.Path]::GetFullPath($ProjectPath); models = @($Models); per_module_budget_seconds = $PerModuleBudgetSeconds }

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
$UnitConfigurationNeedle = -join (@(0x5355,0x5143,0x914D,0x7F6E) | ForEach-Object {[char]$_})
$CpuPattern = '^\[0\]\s+KV-'
$projectLeaf = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
$unitSetPath = Join-Path (Split-Path -Parent ([IO.Path]::GetFullPath($ProjectPath))) 'UnitSet.ue2'

function Normalize-Models {
  $normalized=@()
  foreach($item in @($Models)) {
    foreach($part in ([string]$item -split ',')) {
      $name=$part.Trim()
      if($name){$normalized += ($name -replace '\*$','')}
    }
  }
  if($normalized.Count -eq 0){throw 'KV_MODELS_EMPTY'}
  $script:Models=$normalized
}

function Write-Result($Value) { $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutDir 'result.json') -Encoding UTF8 }
function Get-PersistedModelMatches([string[]]$RequestedModels) {
  if(-not (Test-Path -LiteralPath $unitSetPath -PathType Leaf)){return @()}
  $bytes=[IO.File]::ReadAllBytes($unitSetPath)
  $views=@(
    [Text.Encoding]::GetEncoding(28591).GetString($bytes),
    [Text.Encoding]::Unicode.GetString($bytes),
    [Text.Encoding]::BigEndianUnicode.GetString($bytes)
  )
  $matches=@()
  foreach($model in $RequestedModels) {
    $pattern='(?i)(?<![A-Z0-9_-])'+[regex]::Escape($model)+'\*?(?![A-Z0-9_-])'
    foreach($view in $views) {
      $match=[regex]::Match($view,$pattern)
      if($match.Success){$matches += $match.Value;break}
    }
  }
  return @($matches | Sort-Object -Unique)
}
function Test-ModelPersisted([string]$Model) {
  $matches=@(Get-PersistedModelMatches -RequestedModels @($Model))
  return ($matches -match ('^'+[regex]::Escape($Model)+'\*?$')).Count -gt 0
}
function Get-Scale {
  $dc=[KvExpansionGuardedWin32]::GetDC([IntPtr]::Zero)
  try { return [double][KvExpansionGuardedWin32]::GetDeviceCaps($dc,118) / [double][KvExpansionGuardedWin32]::GetSystemMetrics(0) }
  finally { [void][KvExpansionGuardedWin32]::ReleaseDC([IntPtr]::Zero,$dc) }
}
function Get-KvsMain {
  $matches=@(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$projectLeaf*"})
  if($matches.Count -eq 0){ throw "KV_PROJECT_NOT_OPEN: open '$ProjectPath' in KV STUDIO before running this workflow." }
  if($matches.Count -gt 1){ throw "KV_PROJECT_WINDOW_AMBIGUOUS: found $($matches.Count) visible Kvs windows matching '$projectLeaf'; close duplicate project instances before running." }
  return $matches[0]
}
function Find-UnitEditor([int]$ProcessId) {
  $script:found=[IntPtr]::Zero
  $cb=[KvExpansionGuardedWin32+CB]{param($h,$l);$s=[Text.StringBuilder]::new(512);[void][KvExpansionGuardedWin32]::GetWindowText($h,$s,512);$windowPid=[uint32]0;[void][KvExpansionGuardedWin32]::GetWindowThreadProcessId($h,[ref]$windowPid);if($windowPid -eq $ProcessId -and [KvExpansionGuardedWin32]::IsWindowVisible($h) -and $s.ToString().Contains($UnitEditorNeedle)){$script:found=$h;return $false};$true}
  [void][KvExpansionGuardedWin32]::EnumWindows($cb,[IntPtr]::Zero); return $script:found
}
function Get-Child([IntPtr]$Parent,[string]$Class,[int]$Id,[switch]$VisibleOnly) {
  $script:found=[IntPtr]::Zero
  $cb=[KvExpansionGuardedWin32+CB]{param($h,$l);$s=[Text.StringBuilder]::new(128);[void][KvExpansionGuardedWin32]::GetClassName($h,$s,128);if(((-not $Class) -or $s.ToString() -eq $Class) -and [KvExpansionGuardedWin32]::GetDlgCtrlID($h)-eq $Id -and ((-not $VisibleOnly) -or [KvExpansionGuardedWin32]::IsWindowVisible($h))){$script:found=$h;return $false};$true}
  [void][KvExpansionGuardedWin32]::EnumChildWindows($Parent,$cb,[IntPtr]::Zero); return $script:found
}
function Get-ChildText([IntPtr]$Parent,[int]$Id) { $h=Get-Child $Parent 'Static' $Id -VisibleOnly; if($h -eq [IntPtr]::Zero){return ''};$s=[Text.StringBuilder]::new(512);[void][KvExpansionGuardedWin32]::GetWindowText($h,$s,$s.Capacity);return $s.ToString() }
function Get-VisibleDialogMessage([IntPtr]$Editor) {
  $dialogs=@();$cb=[KvExpansionGuardedWin32+CB]{param($h,$l);$s=[Text.StringBuilder]::new(128);[void][KvExpansionGuardedWin32]::GetClassName($h,$s,128);if($s.ToString() -eq '#32770' -and [KvExpansionGuardedWin32]::IsWindowVisible($h)){$script:dialogs += $h};$true};[void][KvExpansionGuardedWin32]::EnumChildWindows($Editor,$cb,[IntPtr]::Zero)
  foreach($d in $dialogs){$m=Get-ChildText $d 65535;if($m){return $m}};return ''
}
function Click-Relative([IntPtr]$Target,[IntPtr]$RectHwnd,[int]$Dx,[int]$Dy,[string]$Step) {
  $r=New-Object KvExpansionGuardedWin32+RECT;[void][KvExpansionGuardedWin32]::GetWindowRect($RectHwnd,[ref]$r);$scale=Get-Scale
  Invoke-KvGuardedMouseClick -TargetHwnd $Target -Step $Step -X ([int](($r.left+$Dx)*$scale)) -Y ([int](($r.top+$Dy)*$scale)) -ExpectedTitleLike ('*'+$UnitEditorNeedle+'*') -SleepMs 140
}
function Wait-VisibleChild([IntPtr]$Editor,[string]$Class,[int]$Id,[int]$Ms=2000) {
  $deadline=(Get-Date).AddMilliseconds($Ms);do{$h=Get-Child $Editor $Class $Id -VisibleOnly;if($h -ne [IntPtr]::Zero){return $h};Start-Sleep -Milliseconds 50}while((Get-Date)-lt$deadline);return [IntPtr]::Zero
}
function Open-UnitEditor([System.Diagnostics.Process]$Process) {
  Log 'step_started' @{ step = 'open unit editor'; process_id = $Process.Id; main_hwnd = $Process.MainWindowHandle.ToInt64() }
  $existing=Find-UnitEditor $Process.Id;if($existing -ne [IntPtr]::Zero){return $existing}
  $main=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Process.MainWindowHandle)
  $items=$main.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::TreeItem)))
  $unitConfiguration=$null;for($i=0;$i-lt$items.Count;$i++){if($items.Item($i).Current.Name -eq $UnitConfigurationNeedle){$unitConfiguration=$items.Item($i);break}}
  if(-not $unitConfiguration){throw 'KV_UNIT_CONFIGURATION_TREE_ITEM_NOT_FOUND'}
  $expand=$null
  if($unitConfiguration.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$expand) -and $expand.Current.ExpandCollapseState -ne [Windows.Automation.ExpandCollapseState]::Expanded){$expand.Expand();Start-Sleep -Milliseconds 250}
  $items=$main.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::TreeItem)))
  $cpu=$null;for($i=0;$i-lt$items.Count;$i++){if($items.Item($i).Current.Name -match $CpuPattern){$cpu=$items.Item($i);break}}
  if(-not $cpu){throw 'KV_CPU_TREE_ITEM_NOT_FOUND'}
  $scroll=$null;if($cpu.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern,[ref]$scroll)){try{$scroll.ScrollIntoView()}catch{}}
  $select=$null;if($cpu.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$select)){try{$select.Select()}catch{}}
  $rect=$cpu.Current.BoundingRectangle
  if($cpu.Current.IsOffscreen -or [double]::IsInfinity($rect.X) -or $rect.Width -le 10 -or $rect.Height -le 10){throw 'KV_CPU_TREE_ITEM_BOUNDS_INVALID'}
  $x=[int][math]::Round($rect.X+($rect.Width/2));$y=[int][math]::Round($rect.Y+($rect.Height/2))
  Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd ([IntPtr]$Process.MainWindowHandle) -Step 'activate CPU unit configuration click 1' -X $x -Y $y -SuccessProcessId $Process.Id -SleepMs 60
  Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd ([IntPtr]$Process.MainWindowHandle) -Step 'activate CPU unit configuration click 2' -X $x -Y $y -SuccessProcessId $Process.Id -SleepMs 180
  Log 'guarded_tree_item_double_click' @{ step='open unit editor'; item_name=$cpu.Current.Name; x=$x; y=$y; process_id=$Process.Id }
  $deadline=(Get-Date).AddSeconds(5);do{$e=Find-UnitEditor $Process.Id;if($e-ne[IntPtr]::Zero){Log 'step_succeeded' @{ step='open unit editor'; editor_hwnd=$e.ToInt64() }; return $e};Start-Sleep -Milliseconds 60}while((Get-Date)-lt$deadline);Log 'step_failed' @{ step='open unit editor'; error_code='KV_UNIT_EDITOR_OPEN_TIMEOUT' }; throw 'KV_UNIT_EDITOR_OPEN_TIMEOUT'
}
function Set-FlatCatalog([IntPtr]$Editor) {
  # If the selectable catalog is already active, preserve that state; this is
  # common when the same editor is reused for several requested modules.
  $existing=Get-Child $Editor 'SysListView32' 568 -VisibleOnly
  if($existing-ne[IntPtr]::Zero){return $existing}
  $tab=Get-Child $Editor '' 501 -VisibleOnly
  if($tab -eq [IntPtr]::Zero){ throw 'KV_UNIT_CATALOG_TAB_NOT_FOUND' }
  # The catalog tab remains present even while an existing-unit page is shown.
  # Its first tab position is stable for this editor; resolve the tab HWND and
  # scale its screen rectangle rather than relying on the editor window size.
  Click-Relative $Editor $tab 43 12 'select unit catalog tab'
  $toolbar=Get-Child $Editor 'ToolbarWindow32' 59392 -VisibleOnly
  if($toolbar-eq[IntPtr]::Zero){throw 'KV_UNIT_CATALOG_TOOLBAR_NOT_FOUND'}
  foreach($offset in @(12,38,64,90)){ Click-Relative $Editor $toolbar $offset 12 "select flat catalog presentation x$offset" }
  $grid=Wait-VisibleChild $Editor 'SysListView32' 568 1800
  if($grid-eq[IntPtr]::Zero){
    # Some KV STUDIO builds expose the same flat owner-data catalog as id 566
    # after the tab has been activated; accept it only when visible.
    $grid=Wait-VisibleChild $Editor 'SysListView32' 566 800
  }
  if($grid-eq[IntPtr]::Zero){throw 'KV_FLAT_UNIT_CATALOG_NOT_VISIBLE'};return $grid
}
function Find-CatalogRow([IntPtr]$Editor,[IntPtr]$Grid,[string]$Model) {
  # The catalog is an owner-data list: native/UIA item text is unavailable.
  # Use the supported keyboard selection path and treat static 698 as the oracle.
  Click-Relative $Editor $Grid 200 20 'focus flat catalog for dynamic model lookup'
  $count=[KvExpansionGuardedWin32]::SendMessage($Grid,[KvExpansionGuardedWin32]::LVM_GETITEMCOUNT,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()
  if($count -le 0 -or $count -gt 4096){$count=256}
  # Establish the first row once, then advance sequentially.  Repeating
  # Ctrl+Home for every candidate made late catalog entries unnecessarily
  # slow (and could exceed the per-module budget on large catalogs).
  Invoke-KvGuardedSendKeys -TargetHwnd $Editor -Step "start catalog scan for $Model" -Keys '^{HOME}' -ExpectedTitleLike ('*'+$UnitEditorNeedle+'*') -Action 'position catalog scan at first row' -SleepMs 35
  for($i=0;$i -lt $count;$i++) {
    $actual=Get-ChildText $Editor 698
    if($actual -like ($Model+'*')) { return [pscustomobject]@{row=$i;actual=$actual;count=$count} }
    if($i -lt ($count-1)) {
      Invoke-KvGuardedSendKeys -TargetHwnd $Editor -Step ("advance catalog scan to row $($i+1) for $Model") -Keys '{DOWN}' -ExpectedTitleLike ('*'+$UnitEditorNeedle+'*') -Action 'advance catalog scan by one row' -SleepMs 35
    }
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
  Normalize-Models
  Log 'step_succeeded' @{ step='normalize models'; models=@($Models) }
  if(-not(Test-Path -LiteralPath $ProjectPath -PathType Leaf)){throw "KV_PROJECT_MISSING:$ProjectPath"}
  $process=Get-KvsMain
  Log 'precondition_passed' @{ step='resolve project window'; process_id=$process.Id; main_hwnd=$process.MainWindowHandle.ToInt64(); title=$process.MainWindowTitle }
  $beforeLength=(Get-Item -LiteralPath $unitSetPath).Length
  $actions=@();$missing=@()
  foreach($model in $Models){
    if(Test-ModelPersisted $model){$actions += [pscustomobject]@{model=$model;status='already_present';elapsed_seconds=0}}
    else{$missing += $model}
  }
  if($missing.Count -gt 0){
    Log 'step_started' @{ step='configure requested modules'; missing=@($missing) }
    $editor=Open-UnitEditor $process
    foreach($model in $missing){$actions += Add-One $editor $model}
  }
  else {$editor=Find-UnitEditor $process.Id}
  if($missing.Count -eq 0){
    $persisted=@($Models|ForEach-Object {$_+'*'})
    $result=[ordered]@{ok=$true;project_path=[IO.Path]::GetFullPath($ProjectPath);models=$Models;actions=$actions;unitset_path=$unitSetPath;unitset_length_before=$beforeLength;unitset_length_after=$beforeLength;persisted_models=$persisted;clean_end_state=(Get-KvForegroundSnapshot)}
    Write-Result $result; Log 'workflow_succeeded' @{ project_path=[IO.Path]::GetFullPath($ProjectPath); models=@($Models); persisted_models=@($persisted) }; $result | ConvertTo-Json -Depth 12; return
  }
  $ok=Get-Child $editor 'Button' 23017
  if($ok-eq[IntPtr]::Zero){throw 'KV_UNIT_EDITOR_OK_BUTTON_NOT_FOUND'}
  # Direct control invocation is permitted because the button identity is resolved first; no global input is used.
  [void][KvExpansionGuardedWin32]::SendMessage($ok,[KvExpansionGuardedWin32]::BM_CLICK,[IntPtr]::Zero,[IntPtr]::Zero)
  # A duplicate/invalid address can produce a modal “relay/DM/address error”.
  # Surface it as a stable workflow failure instead of leaving the dialog open.
  $modalDeadline=(Get-Date).AddSeconds(2); do {
    $msg=Get-VisibleDialogMessage $editor
    if($msg -match '地址中有错误|继电器|DM'){throw "KV_UNIT_ADDRESS_CONFLICT: $msg"}
    Start-Sleep -Milliseconds 80
  } while((Get-Date)-lt$modalDeadline)
  $deadline=(Get-Date).AddSeconds(8);do{Start-Sleep -Milliseconds 100;$matchCount=@(Get-PersistedModelMatches -RequestedModels $Models).Count}while($matchCount -lt $Models.Count -and (Get-Date)-lt$deadline)
  $persisted=@(Get-PersistedModelMatches -RequestedModels $Models)
  foreach($model in $Models){if(-not($persisted -match ('^'+[regex]::Escape($model)+'\*?$'))){throw "KV_UNITSET_PERSISTENCE_FAILED:$model"}}
  Assert-KvUiForegroundHwnd -ExpectedHwnd ([IntPtr]$process.MainWindowHandle) -Step 'verify main foreground after unit configuration commit' -ExpectedTitleLike 'KV STUDIO*' | Out-Null
  Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$process.MainWindowHandle) -Step 'save project after unit configuration' -Keys '^s' -ExpectedTitleLike 'KV STUDIO*' -Action 'save committed unit layout' -SleepMs 500
  $result=[ordered]@{ok=$true;project_path=[IO.Path]::GetFullPath($ProjectPath);models=$Models;actions=$actions;unitset_path=$unitSetPath;unitset_length_before=$beforeLength;unitset_length_after=(Get-Item $unitSetPath).Length;persisted_models=$persisted;clean_end_state=(Get-KvForegroundSnapshot)}
  Write-Result $result; $result | ConvertTo-Json -Depth 12
  Log 'workflow_succeeded' @{ project_path=[IO.Path]::GetFullPath($ProjectPath); models=@($Models); persisted_models=@($persisted) }
} catch { $code=if($_.Exception.Message -match '^KV_[A-Z0-9_:-]+'){($_.Exception.Message -split ':')[0]}else{'KV_EXPANSION_UNIT_CONFIGURATION_FAILED'}; Log 'workflow_failed' @{ error_code=$code; message=$_.Exception.Message; foreground=(Get-KvForegroundSnapshot) }; $failure=[ordered]@{ok=$false;error_code=$code;message=$_.Exception.Message;project_path=$ProjectPath;evidence_dir=$OutDir;foreground=(Get-KvForegroundSnapshot)}; $failure|ConvertTo-Json -Depth 10|Set-Content (Join-Path $OutDir 'failure.json') -Encoding UTF8; throw }
