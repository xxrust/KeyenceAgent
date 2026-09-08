<#
.SYNOPSIS
  Read-only extraction of user structure members through the KV STUDIO structure editor.
.DESCRIPTION
  Research/probe entry point. It never edits or saves the project. Each requested
  structure is opened from ProjectTreeView and its visible member/type/comment
  columns are copied as a block. KVS12's grid copies one column at a time, so the
  columns are joined by row in the emitted JSON.
#>
param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string[]]$StructureName = @()
)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$runLog=Join-Path $OutDir 'run.log'; $env:KV_WORKFLOW_RUN_LOG=$runLog
function Log([string]$Type,[hashtable]$Data=@{}) { $o=[ordered]@{timestamp=(Get-Date).ToString('o');type=$Type}; foreach($k in $Data.Keys){$o[$k]=$Data[$k]}; (ConvertTo-Json $o -Compress)|Add-Content -LiteralPath $runLog -Encoding UTF8 }
Add-Type -AssemblyName System.Windows.Forms
$scriptRoot=Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $scriptRoot 'guards\kv_ui_guard.ps1')
Initialize-KvUiGuard -OutDir $OutDir
$script:MainHwnd=[IntPtr]::Zero; $script:ExpectedTitle='KV STUDIO*'
function ClipboardFullGrid([int]$X,[int]$Y,[string]$Name){
  $sw=[Diagnostics.Stopwatch]::StartNew()
  Invoke-KvGuardedMouseClick -TargetHwnd $script:MainHwnd -Step "focus structure grid $Name" -X $X -Y $Y -ExpectedTitleLike $script:ExpectedTitle -SleepMs 80
  Invoke-KvGuardedSendKeys -TargetHwnd $script:MainHwnd -Step "exit structure cell edit $Name" -Keys '{ESC}' -ExpectedTitleLike $script:ExpectedTitle -SleepMs 40
  Invoke-KvGuardedSendKeys -TargetHwnd $script:MainHwnd -Step "select full structure grid $Name" -Keys '^{HOME}^+{END}' -ExpectedTitleLike $script:ExpectedTitle -SleepMs 80
  Invoke-KvGuardedSendKeys -TargetHwnd $script:MainHwnd -Step "copy full structure grid $Name" -Keys '^c' -ExpectedTitleLike $script:ExpectedTitle -SleepMs 160
  $text=[Windows.Forms.Clipboard]::GetText(); Set-Content -LiteralPath (Join-Path $OutDir ("grid_$Name.tsv")) -Value $text -Encoding UTF8
  Log 'grid_copied' @{name=$Name;elapsed_ms=$sw.ElapsedMilliseconds;chars=$text.Length}
  if($sw.ElapsedMilliseconds -ge 10000){throw "KV_UI_ATOMIC_STEP_TIMEOUT: copy full structure grid $Name"}
  return @($text -split "`r?`n" | Where-Object {$_ -and $_.Trim()})
}
function FindWindow([string]$Needle){
  $ps=@(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$Needle*"})
  if($ps.Count -eq 0){$ps=@(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object {$_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like '*KVX*'})}
  if($ps.Count -ne 1){throw "KV_PROJECT_WINDOW_AMBIGUOUS: expected one KVS window for $Needle, got $($ps.Count)"}; return $ps[0]
}
function Desc($Root,[string]$Aid){$Root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,$Aid)))}
function ExpandDataTypeTree($Tree){
  $typeRootName=-join([char[]](0x6570,0x636E,0x7C7B,0x578B))
  $items=$Tree.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::TreeItem)))
  $rootItem=@($items|Where-Object {$_.Current.Name -eq $typeRootName}|Select-Object -First 1)
  if(-not $rootItem){throw 'KV_STRUCTURE_TYPE_ROOT_MISSING'}
  $sw=[Diagnostics.Stopwatch]::StartNew(); $expanded=0
  for($pass=0;$pass -lt 5;$pass++){
    $changed=$false
    $candidates=@($rootItem)+@($rootItem.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::TreeItem))))
    foreach($item in $candidates){
      try{$ep=$null;if($item.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$ep) -and $ep.Current.ExpandCollapseState -eq [Windows.Automation.ExpandCollapseState]::Collapsed){$ep.Expand();$expanded++;$changed=$true;Start-Sleep -Milliseconds 40}}catch{}
      if($sw.ElapsedMilliseconds -ge 9000){break}
    }
    if(-not $changed -or $sw.ElapsedMilliseconds -ge 9000){break}
  }
  Log 'data_type_tree_expanded' @{elapsed_ms=$sw.ElapsedMilliseconds;expanded=$expanded}
  if($sw.ElapsedMilliseconds -ge 10000){throw 'KV_UI_ATOMIC_STEP_TIMEOUT: expand data type tree'}
}
function OpenStructure($Tree,[string]$Name){
  $all=$Tree.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::TreeItem)))
  $item=@($all|Where-Object {$_.Current.Name -eq $Name -or $_.Current.Name.StartsWith($Name+':',[StringComparison]::Ordinal)})|Select-Object -First 1
  if(-not $item){ExpandDataTypeTree $Tree;$all=$Tree.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::TreeItem)));$item=@($all|Where-Object {$_.Current.Name -eq $Name -or $_.Current.Name.StartsWith($Name+':',[StringComparison]::Ordinal)}|Select-Object -First 1)}
  if(-not $item){throw "KV_STRUCTURE_NOT_FOUND: $Name"}
  try{$s=$null;if($item.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern,[ref]$s)){$s.ScrollIntoView()}}catch{}
  Assert-KvUiForegroundHwnd -ExpectedHwnd $script:MainHwnd -Step "select structure tree item $Name" -ExpectedTitleLike $script:ExpectedTitle -AllowSingleRecovery | Out-Null
  $sel=$null;if($item.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$sel)){$sel.Select()}
  Start-Sleep -Milliseconds 120
  $inv=$null;if($item.TryGetCurrentPattern([Windows.Automation.InvokePattern]::Pattern,[ref]$inv)){$inv.Invoke()}else{Invoke-KvGuardedSendKeys -TargetHwnd $script:MainHwnd -Step "open structure $Name" -Keys '{ENTER}' -ExpectedTitleLike $script:ExpectedTitle -SleepMs 100}
  Log 'structure_open_requested' @{name=$Name}
}
function GetUserDataTypeNames($Tree){
  ExpandDataTypeTree $Tree
  $typeRootName=-join([char[]](0x6570,0x636E,0x7C7B,0x578B));$systemName='(System)'
  $items=$Tree.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::TreeItem)))
  $walker=[Windows.Automation.TreeWalker]::ControlViewWalker;$names=@()
  foreach($item in $items){
    $ep=$null;if($item.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern,[ref]$ep)){continue}
    $underTypes=$false;$underSystem=$false;$parent=$walker.GetParent($item);$guard=0
    while($parent -and $guard++ -lt 20){$pn=[string]$parent.Current.Name;if($pn -eq $systemName){$underSystem=$true};if($pn -eq $typeRootName){$underTypes=$true;break};$parent=$walker.GetParent($parent)}
    if(-not $underTypes -or $underSystem){continue}
    $name=([string]$item.Current.Name -split ':',2)[0].Trim();if($name){$names+=$name}
  }
  return @($names|Sort-Object -Unique)
}
function WaitEditor([int]$ProcessIdValue){$deadline=(Get-Date).AddSeconds(5);do{$root=[Windows.Automation.AutomationElement]::RootElement;$s=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.AndCondition((New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty,$ProcessIdValue)),(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'_pnlMain')))));if($s){return $s};Start-Sleep -Milliseconds 100}while((Get-Date)-lt $deadline);throw 'KV_STRUCTURE_EDITOR_TIMEOUT'}
function AssertStructureTab([int]$ProcessIdValue,[string]$Name){
  $deadline=(Get-Date).AddSeconds(3); do {
    $root=[Windows.Automation.AutomationElement]::RootElement
    $tabs=$root.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.AndCondition((New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty,$ProcessIdValue)),(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::TabItem)))))
    $tab=@($tabs|Where-Object {$_.Current.Name -match ('(?:' + [char]0x7ED3 + [char]0x6784 + [char]0x4F53 + '\[)?' + [regex]::Escape($Name)) -and -not $_.Current.IsOffscreen}|Select-Object -First 1)
    if($tab){try{$sp=$null;if($tab.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$sp) -and -not $sp.Current.IsSelected){$sp.Select()}}catch{};return $tab}
    Start-Sleep -Milliseconds 100
  } while((Get-Date)-lt $deadline)
  throw "KV_STRUCTURE_TAB_MISMATCH: expected $Name"
}
function ExtractOne($Tree,$ProcessIdValue,[string]$Name){
  OpenStructure $Tree $Name; $surface=WaitEditor $ProcessIdValue
  $detail=Desc $surface '_chkOffsetColVisible'
  if($detail){try{$tp=$null;if($detail.TryGetCurrentPattern([Windows.Automation.TogglePattern]::Pattern,[ref]$tp) -and $tp.Current.ToggleState -eq [Windows.Automation.ToggleState]::On){$tp.Toggle();Start-Sleep -Milliseconds 150;Log 'structure_detail_columns_hidden' @{name=$Name}}}catch{}}
  $panelRect=$surface.Current.BoundingRectangle
  if($panelRect.Width -lt 300 -or $panelRect.Height -lt 200){throw "KV_STRUCTURE_GRID_MISSING: $Name"}
  # The structure editor's grid is a native owner-drawn surface. Its first
  # data row starts ~19px below _pnlMain and the four visible columns are
  # fixed 200px tracks in KVS12; click creates the temporary Edit surface.
  $x0=[int]([math]::Round($panelRect.X+110));$y=[int]([math]::Round($panelRect.Y+28));
  $lines=@(ClipboardFullGrid $x0 $y $Name); $members=@(); $rowNo=0
  foreach($line in $lines){$fields=@($line -split "`t");if($fields.Count -lt 2){continue};$memberName=([string]$fields[0]).Trim([char]0xFEFF).Trim();$dataType=([string]$fields[1]).Trim();if(-not $memberName){continue};$comment1=if($fields.Count -gt 4){([string]$fields[4]).Trim()}else{''};$comment2=if($fields.Count -gt 5){([string]$fields[5]).Trim()}else{''};$rowNo++;$members += [ordered]@{name=$memberName;data_type=$dataType;comment_1=$comment1;comment_2=$comment2;row=$rowNo;raw_columns=$fields}}
  if($members.Count -eq 0 -or @($members|Where-Object {-not $_.name -or -not $_.data_type}).Count -gt 0){throw "KV_STRUCTURE_COPYBACK_INVALID: $Name"}
  Log 'structure_copyback_validated' @{name=$Name;member_count=$members.Count;nonempty_types=@($members|Where-Object {$_.data_type}|Measure-Object).Count}
  return [ordered]@{name=$Name;member_count=$members.Count;members=$members;source='KV STUDIO structure editor';columns=@('name','data_type','comment_1','comment_2')}
}
$needle=[IO.Path]::GetFileNameWithoutExtension($ProjectPath);$p=FindWindow $needle;$script:MainHwnd=[IntPtr]$p.MainWindowHandle;$root=[Windows.Automation.AutomationElement]::RootElement;Assert-KvUiForegroundHwnd -ExpectedHwnd $script:MainHwnd -Step 'structure extraction preflight' -ExpectedTitleLike $script:ExpectedTitle -AllowSingleRecovery|Out-Null;$tree=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.AndCondition((New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ProcessIdProperty,$p.Id)),(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'ProjectTreeView')))));if(-not $tree){throw 'KV_PROJECT_TREE_MISSING'}
if($StructureName.Count -eq 0){$StructureName=@(GetUserDataTypeNames $tree);Log 'user_data_types_discovered' @{count=$StructureName.Count;names=$StructureName}}
$defs=@(); foreach($name in $StructureName){$sw=[Diagnostics.Stopwatch]::StartNew();try{$defs+=ExtractOne $tree $p.Id $name;Log 'structure_extracted' @{name=$name;elapsed_ms=$sw.ElapsedMilliseconds}}catch{Log 'structure_extract_failed' @{name=$name;error=$_.Exception.Message};throw}}
$result=[ordered]@{ok=$true;project_path=$ProjectPath;structure_count=$defs.Count;structures=$defs;generated_at=(Get-Date).ToString('o')};$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $OutDir 'structure_definitions.json') -Encoding UTF8;Log 'workflow_finished' @{ok=$true;structure_count=$defs.Count}
