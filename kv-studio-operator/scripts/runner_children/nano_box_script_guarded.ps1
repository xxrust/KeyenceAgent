param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [Parameter(Mandatory=$true)][ValidateSet('Inspect','InspectLabels','ReadLabels','WriteLabels','DeleteLabel','CreateScript','ReadScript','UpdateScript','DeleteScript','CreateAreaScript','ReadAreaScript','UpdateAreaScript','DeleteAreaScript','InsertLadder','ReadLadder','UpdateLadder','DeleteLadder','Save','Close','Reopen')][string]$Action,
  [ValidateSet('Global','Local')][string]$LabelScope='Global',
  [string]$ProgramName='Main',
  [ValidateRange(1,10000)][int]$Row=1,
  [string]$SourcePath='',
  [string]$ExpectedSourcePath='',
  [string]$Condition='CR2002',
  [string]$CreatedProjectResultPath='',
  [string]$ProgramContractPath='',
  [string]$InspectMenuName=''
)
$ErrorActionPreference='Stop'
$scriptsRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $scriptsRoot 'kv_window_binding.ps1')
. (Join-Path $scriptsRoot 'kv_tree_resolver.ps1')
. (Join-Path $scriptsRoot 'guards/kv_ui_guard.ps1')
. (Join-Path $scriptsRoot 'workflow_tools/kv_nano_label_contract.ps1')
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

function Normalize-Source([string]$Text) { return $Text.Replace("`r`n","`n").TrimEnd("`r","`n") }
function Normalize-Ladder([string]$Text) { return [regex]::Replace((Normalize-Source $Text),'\b((?:CR|MR|LR|R|DM))0+(\d+)\b','$1$2') }
function Read-Source([string]$Path) {
  if(-not $Path -or -not(Test-Path -LiteralPath $Path -PathType Leaf)){throw 'KV_NANO_SOURCE_FILE_REQUIRED'}
  $text=[IO.File]::ReadAllText([IO.Path]::GetFullPath($Path),[Text.UTF8Encoding]::new($false,$true))
  if([string]::IsNullOrWhiteSpace($text)){throw 'KV_NANO_EMPTY_SOURCE_REJECTED'}
  return (Normalize-Source $text)
}
function Find-Id($Parent,[string]$Id) {
  return $Parent.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,$Id)))
}
function Click-Named([string]$Name,[string]$Type='MenuItem',[IntPtr]$Window=$s.hwnd) {
  $element=[Windows.Automation.AutomationElement]::FromHandle($Window)
  $items=@($element.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,$Name))) |
    Where-Object {$_.Current.ControlType.ProgrammaticName -eq ('ControlType.'+$Type) -and $_.Current.IsEnabled -and -not $_.Current.IsOffscreen})
  if($items.Count -gt 1){$items=@($items|Where-Object {[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($_).Current.ControlType -ne [Windows.Automation.ControlType]::MenuBar})}
  if($items.Count -ne 1){throw "KV_NANO_COMMAND_UNIQUE_REQUIRED: $Name count=$($items.Count)"}
  $r=$items[0].Current.BoundingRectangle
  Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd $Window -Step ('Nano command '+$Name) -SuccessProcessId $s.process_id -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SleepMs 250
}
function Open-Menu([int]$Vk) {
  $name=if($Vk -eq 0x53){'ST/脚本(S)'}elseif($Vk -eq 0x45){'编辑(E)'}else{throw 'KV_NANO_MENU_NOT_REGISTERED'}
  $anchor=if($Vk -eq 0x53){'转换编辑方法(N)'}else{'删除行(Y)'}
  for($attempt=0;$attempt -lt 2;$attempt++){
    $menus=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,$name))) | Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::MenuItem -and [Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($_).Current.ControlType -eq [Windows.Automation.ControlType]::MenuBar})
    if($menus.Count -ne 1){throw 'KV_NANO_TOP_MENU_UNIQUE_REQUIRED'}
    $r=$menus[0].Current.BoundingRectangle
    Invoke-KvGuardedMouseClick -TargetHwnd $s.hwnd -Step ('open verified Nano menu '+$name) -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -ExpectedTitleLike 'KV STUDIO*' -SleepMs 200
    $deadline=(Get-Date).AddSeconds(2)
    do {
      $opened=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,$anchor))) | Where-Object {-not $_.Current.IsOffscreen})
      if($opened.Count -eq 1){return}
      Start-Sleep -Milliseconds 100
    }while((Get-Date) -lt $deadline)
  }
  throw ('KV_NANO_MENU_OPEN_NOT_CONFIRMED: '+$name)
}
function Select-Cell([int]$Column=1) {
  $ladder=Find-Id $root '_ladderSplitContainer'
  if(-not $ladder){throw 'KV_NANO_LADDER_EDITOR_REQUIRED'}
  $r=$ladder.Current.BoundingRectangle
  Invoke-KvGuardedMouseClick -TargetHwnd $s.hwnd -Step 'focus path bound Nano ladder' -X ([int]($r.X+90)) -Y ([int]($r.Y+65)) -ExpectedTitleLike 'KV STUDIO*' -SleepMs 100
  $focus=[Windows.Automation.AutomationElement]::FocusedElement;$proven=$false
  for($depth=0;$focus -and $depth -lt 12;$depth++){
    if(($focus.GetRuntimeId() -join ',') -eq ($ladder.GetRuntimeId() -join ',')){$proven=$true;break}
    $focus=[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($focus)
  }
  if(-not $proven){throw 'KV_NANO_LADDER_FOCUS_REQUIRED'}
  $keys='^{HOME}'
  if($Row -gt 1){$keys+='{DOWN '+($Row-1)+'}'}
  if($Column -gt 1){$keys+='{RIGHT '+($Column-1)+'}'}
  Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'select explicit folded ladder row and column' -Keys $keys -ExpectedTitleLike 'KV STUDIO*' -SleepMs 150
}
function Get-ScriptWindow {
  $fg=Get-KvForegroundSnapshot
  if($fg.process_id -ne $s.process_id -or $fg.title -ne 'ST/脚本编辑窗口' -or $fg.class_name -notlike 'WindowsForms10.Window*'){throw 'KV_NANO_SCRIPT_WINDOW_REQUIRED'}
  return [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
}
function Read-Script($Window,[string]$NewSource='') {
  $panes=@($Window.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::Pane -and $_.Current.BoundingRectangle.Height -gt 150})
  if($panes.Count -ne 1){throw 'KV_NANO_SCRIPT_TEXT_PANE_UNIQUE_REQUIRED'}
  $r=$panes[0].Current.BoundingRectangle;$h=[IntPtr]$Window.Current.NativeWindowHandle
  Invoke-KvGuardedMouseClick -TargetHwnd $h -Step 'focus verified script text pane' -X ([int]($r.X+15)) -Y ([int]($r.Y+15)) -ExpectedTitleLike 'ST/脚本编辑窗口'
  if([Windows.Automation.AutomationElement]::FocusedElement.Current.NativeWindowHandle -ne $panes[0].Current.NativeWindowHandle){throw 'KV_NANO_SCRIPT_SOURCE_FOCUS_REQUIRED'}
  if($NewSource){
    Invoke-KvGuardedSendKeys -TargetHwnd $h -Step 'select complete script source' -Keys '^{HOME}^+{END}' -ExpectedTitleLike 'ST/脚本编辑窗口'
    Invoke-KvGuardedClipboardPaste -TargetHwnd $h -Step 'replace verified script source' -Text $NewSource -ExpectedTitleLike 'ST/脚本编辑窗口'
  }
  $sentinel='KV_NANO_READ_PENDING_'+[guid]::NewGuid().ToString('N')
  Invoke-KvGuardedClipboardSetText -TargetHwnd $h -Step 'initialize fresh script read sentinel' -Text $sentinel -ExpectedTitleLike 'ST/脚本编辑窗口'
  Invoke-KvGuardedSendKeys -TargetHwnd $h -Step 'copy complete script source' -Keys '^{HOME}^+{END}^c' -ExpectedTitleLike 'ST/脚本编辑窗口'
  $text=[Windows.Forms.Clipboard]::GetText()
  if($text -eq $sentinel){throw 'KV_NANO_SCRIPT_READBACK_MISSING'}
  return (Normalize-Source $text)
}
function Close-Script($Window) { Click-Named '应用后关闭' 'Button' ([IntPtr]$Window.Current.NativeWindowHandle) }
function Open-Script {
  Select-Cell $(if($Action -like '*AreaScript'){1}else{5})
  Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $s.hwnd -Step 'open existing Nano script cell' -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO*' -SuccessTitleLike @('ST/脚本编辑窗口') -SleepMs 250
  return (Get-ScriptWindow)
}
function Save-Project {
  Click-Named '保存项目(Ctrl+S)' 'Button'
  $deadline=(Get-Date).AddSeconds(8)
  do {
    $title=[Windows.Automation.AutomationElement]::FromHandle($s.hwnd).Current.Name
    if($title -notmatch '\*\]$'){return}
    Start-Sleep -Milliseconds 200
  } while((Get-Date) -lt $deadline)
  throw 'KV_NANO_SAVE_NOT_SETTLED'
}
function Close-Project {
  $p=Get-Process -Id $s.process_id -ErrorAction Stop
  if($p.StartTime.ToUniversalTime().ToString('o') -ne $s.process_start_utc){throw 'KV_NANO_PROCESS_ID_REUSED'}
  Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $s.hwnd -Step 'close exact saved Nano test project' -Keys '%{F4}' -ExpectedTitleLike 'KV STUDIO*' -SuccessTitleLike @('*') -SleepMs 500
  if(-not $p.WaitForExit(8000)){throw 'KV_NANO_CLOSE_PROCESS_DID_NOT_EXIT'}
}
function Get-LadderDialog {
  $fg=Get-KvForegroundSnapshot
  if($fg.process_id -ne $s.process_id -or $fg.title -ne '编辑列表' -or $fg.class_name -ne '#32770'){throw 'KV_NANO_LADDER_LIST_REQUIRED'}
  $d=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
  $edit=Find-Id $d '1010'
  if(-not $edit -or $edit.Current.ClassName -ne 'Edit'){throw 'KV_NANO_LADDER_LIST_EDIT_REQUIRED'}
  return @{window=$d;edit=$edit;hwnd=[IntPtr]$fg.hwnd}
}
function Read-Ladder($Dialog) {
  if(-not ('KvNanoListText' -as [type])){
    Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class KvNanoListText {
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint msg,UIntPtr wparam,StringBuilder text,uint flags,uint timeout,out UIntPtr result);
  public static string Read(IntPtr hwnd) {
    var text=new StringBuilder(1048576); UIntPtr result;
    if(SendMessageTimeout(hwnd,13,new UIntPtr((uint)text.Capacity),text,2,2000,out result)==IntPtr.Zero) throw new InvalidOperationException("KV_NANO_LIST_READ_TIMEOUT");
    return text.ToString();
  }
}
'@
  }
  return (Normalize-Source ([KvNanoListText]::Read([IntPtr]$Dialog.edit.Current.NativeWindowHandle)))
}
function Cancel-Ladder($Dialog) {
  Invoke-KvGuardedSendKeysAllowTargetCloseToWindow -TargetHwnd $Dialog.hwnd -SuccessHwnd $s.hwnd -Step 'close read only mnemonic list' -Keys '{ESC}' -ExpectedTitleLike '编辑列表' -SleepMs 200
}
function Normalize-Labels([string]$Text) {
  $rows=@(foreach($line in ($Text -split '\r?\n')){
    if(-not $line.Trim()){continue}
    $fields=$line.Split([char]9)
    if($fields.Count -ne 4){throw 'KV_NANO_LABEL_FOUR_COLUMNS_REQUIRED'}
    $fields -join "`t"
  })
  return ($rows -join "`n")
}
function Focus-LabelGrid($Dialog) {
  $pane=Find-Id $Dialog $(if($LabelScope -eq 'Global'){'_tabGlobal'}else{'_tabLocal'})
  $candidates=@($pane.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::Pane -and $_.Current.BoundingRectangle.Width -gt 500 -and $_.Current.BoundingRectangle.Height -gt 80 -and -not $_.Current.IsOffscreen}|Sort-Object {$_.Current.BoundingRectangle.Width*$_.Current.BoundingRectangle.Height})
  if(-not $candidates.Count){throw 'KV_NANO_LABEL_GRID_REQUIRED'}
  $r=$candidates[0].Current.BoundingRectangle
  Invoke-KvGuardedMouseClick -TargetHwnd $labelHwnd -Step 'focus Nano label grid below column headers' -X ([int]($r.X+20)) -Y ([int]($r.Y+25)) -ExpectedTitleLike '编辑标号'
}
function Read-Labels($Dialog) {
  # Reuse the committed exporter's Ctrl+Home / Ctrl+Shift+End / Ctrl+C route.
  Focus-LabelGrid $Dialog
  $sentinel='KV_LABEL_COPY_PENDING_'+[guid]::NewGuid().ToString('N')
  Invoke-KvGuardedClipboardSetText -TargetHwnd $labelHwnd -Step 'initialize fresh label copy sentinel' -Text $sentinel -ExpectedTitleLike '编辑标号'
  Invoke-KvGuardedSendKeys -TargetHwnd $labelHwnd -Step 'move to first Nano label cell' -Keys '^{HOME}' -ExpectedTitleLike '编辑标号' -SleepMs 250
  Invoke-KvGuardedSendKeys -TargetHwnd $labelHwnd -Step 'select complete Nano label table' -Keys '^+{END}' -ExpectedTitleLike '编辑标号' -SleepMs 350
  Invoke-KvGuardedCtrlChord -TargetHwnd $labelHwnd -Step 'copy complete Nano label table using committed exporter route' -Vk 0x43 -ExpectedTitleLike '编辑标号' -SleepMs 600
  $actual=[Windows.Forms.Clipboard]::GetText()
  [IO.File]::WriteAllText((Join-Path $OutDir 'labels_raw.tsv'),$actual,[Text.UTF8Encoding]::new($false))
  if($actual -eq $sentinel){throw 'KV_NANO_LABEL_COPY_NOT_CONFIRMED'}
  return (Normalize-Labels $actual)
}
function Close-Labels {
  Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $labelHwnd -Step 'hide Nano labels editor' -Keys '%{F4}' -ExpectedTitleLike '编辑标号' -SuccessTitleLike @('KV STUDIO*')
  if((Get-KvForegroundSnapshot).hwnd -ne $s.hwnd.ToInt64()){throw 'KV_NANO_LABEL_CLOSE_MAIN_REQUIRED'}
}
function Answer-LabelDeleteConfirmation([bool]$Accept, [bool]$Range = $false) {
  $fg=Get-KvForegroundSnapshot
  if($fg.process_id -ne $s.process_id -or $fg.title -ne 'KV STUDIO' -or $fg.class_name -ne '#32770'){throw 'KV_NANO_LABEL_DELETE_CONFIRMATION_REQUIRED'}
  $modal=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
  $body=Find-Id $modal '65535'
  $expectedQuestion=if($Range){'^选择范围是否删除[?？]$'}else{'^是否删除[?？]$'}
  if($body.Current.Name -notmatch $expectedQuestion){throw 'KV_NANO_LABEL_DELETE_CONFIRMATION_TEXT_MISMATCH'}
  $button=Find-Id $modal $(if($Accept){'6'}else{'7'})
  if($button.Current.Name -ne $(if($Accept){'是(Y)'}else{'否(N)'})){throw 'KV_NANO_LABEL_DELETE_CONFIRMATION_BUTTON_MISMATCH'}
  $r=$button.Current.BoundingRectangle
  Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd ([IntPtr]$fg.hwnd) -Step $(if($Accept){'confirm verified label row deletion'}else{'cancel previous uncommitted label deletion before fresh read'}) -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SuccessProcessId $s.process_id
  $after=Get-KvForegroundSnapshot
  if($after.title -ne '编辑标号'){throw 'KV_NANO_LABEL_DELETE_SUCCESSOR_REQUIRED'}
}

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Initialize-KvUiGuard -OutDir $OutDir
$result=[ordered]@{ok=$false;action=$Action;project_path=[IO.Path]::GetFullPath($ProjectPath);program=$ProgramName;row=$Row;source='';before_source='';session=$null}
try {
  $source='';$expected=''
  if($Action -in @('CreateScript','UpdateScript','CreateAreaScript','UpdateAreaScript','InsertLadder','UpdateLadder')){$source=Read-Source $SourcePath}
  if($Action -in @('UpdateScript','DeleteScript','UpdateAreaScript','DeleteAreaScript','UpdateLadder','DeleteLadder')){$expected=Read-Source $ExpectedSourcePath}
  if($Action -in @('ReadScript','ReadAreaScript','ReadLadder') -and $ExpectedSourcePath){$expected=Read-Source $ExpectedSourcePath}
  if($Action -eq 'WriteLabels'){
    $labelWrite=Get-KvNanoLabelWrite -SourcePath $SourcePath -ExpectedSourcePath $ExpectedSourcePath -Row $Row
    $source=$labelWrite.source
  }
  if($Action -in @('WriteLabels','DeleteLabel') -or ($Action -eq 'ReadLabels' -and $ExpectedSourcePath)){
    if(-not $ExpectedSourcePath -or -not(Test-Path -LiteralPath $ExpectedSourcePath -PathType Leaf)){throw 'KV_NANO_LABEL_EXPECTED_TABLE_REQUIRED'}
    $expected=Normalize-Labels ([IO.File]::ReadAllText([IO.Path]::GetFullPath($ExpectedSourcePath),[Text.UTF8Encoding]::new($false,$true)))
  }
  if($Condition -notmatch '^(?:CR|MR|R|LR)\d+$'){throw 'KV_NANO_CONDITION_DEVICE_INVALID'}
  if($Action -like '*Ladder' -and $source -match '(?im)^(?:;|DEVICE:|BOX_|ENDH?\b)'){throw 'KV_NANO_PLAIN_LADDER_ONLY'}
  if($CreatedProjectResultPath){
    # During an open menu Process.MainWindowTitle can be empty. Validate the
    # creation receipt and native project editor independently for Nano only.
    $receipt=Get-Content -LiteralPath $CreatedProjectResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    $p=Get-Process -Id ([int]$receipt.process_id) -ErrorAction Stop
    $receiptStart=[datetime]::Parse($receipt.process_start_utc).ToUniversalTime()
    if(-not $receipt.ok -or [IO.Path]::GetFullPath($receipt.project_path) -ine $result.project_path -or [IO.Path]::GetFullPath($receipt.requested_project_path) -ine $result.project_path -or $p.ProcessName -ine 'Kvs' -or $p.StartTime.ToUniversalTime() -ne $receiptStart -or [IO.Path]::GetFullPath($p.Path) -ine [IO.Path]::GetFullPath($receipt.kvs_exe)){throw 'KV_NANO_CREATION_PROCESS_IDENTITY_MISMATCH'}
    $pattern='^KV STUDIO.* - \['+[regex]::Escape([IO.Path]::GetFileNameWithoutExtension($ProjectPath))+'(?: \*)?\]$'
    $h=Get-KvPathBoundEditorHwnd -ProcessId $p.Id -TitlePattern $pattern
    if($h -eq [IntPtr]::Zero){throw 'KV_NANO_CREATED_EDITOR_MISSING'}
    $title=[Windows.Automation.AutomationElement]::FromHandle($h).Current.Name
    $cpu='';if($title -match '\[编辑器:\s*(KV-[A-Za-z0-9-]+)\]'){$cpu=$matches[1]}
    $s=[pscustomobject]@{project_path=$result.project_path;process_id=$p.Id;process_start_utc=$p.StartTime.ToUniversalTime().ToString('o');hwnd=$h;title=$title;cpu_model=$cpu;kvs_exe=$p.Path;kvs_version=$p.FileVersion}
  }else{$s=Get-KvProjectSession -ProjectPath $ProjectPath}
  if(-not $s.cpu_model -and $s.title -match '\[编辑器 \(ST/脚本编辑中\):\s*(KV-N[A-Za-z0-9-]+)\]'){$s.cpu_model=$matches[1]}
  if($s.cpu_model -notmatch '^KV-N'){throw 'KV_NANO_CPU_REQUIRED'}
  $result.session=$s
  $root=[Windows.Automation.AutomationElement]::FromHandle($s.hwnd)
  $initial=Get-KvForegroundSnapshot
  if($Action -in @('Close','ReadLabels','InspectLabels') -and $initial.process_id -eq $s.process_id -and $initial.title -eq 'KV STUDIO' -and $initial.class_name -eq '#32770'){
    $modal=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$initial.hwnd)
    $body=Find-Id $modal '65535';$okButton=Find-Id $modal '2'
    if(-not $okButton){$okButton=Find-Id $modal '1'}
    if($body -and $body.Current.Name -eq '由于粘贴数据中存在非法数据, 因此中止了粘贴处理。' -and $okButton -and $okButton.Current.Name -eq '确定'){
      $r=$okButton.Current.BoundingRectangle
      Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd ([IntPtr]$initial.hwnd) -Step 'dismiss fingerprinted rejected Nano label paste before read or cleanup' -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SuccessProcessId $s.process_id
      $initial=Get-KvForegroundSnapshot
    }
    elseif($body -and $body.Current.Name -match '^(?:选择范围)?是否删除[?？]$'){
      Answer-LabelDeleteConfirmation $false ($body.Current.Name -match '^选择范围')
      $initial=Get-KvForegroundSnapshot
    }
  }
  if($Action -eq 'Close' -and $initial.process_id -eq $s.process_id -and $initial.title -eq '编辑标号'){
    $labelHwnd=[IntPtr]$initial.hwnd
    Close-Labels
    $initial=Get-KvForegroundSnapshot
  }
  if($initial.process_id -eq $s.process_id -and $initial.title -eq '编辑列表' -and $initial.class_name -eq '#32770'){
    Cancel-Ladder (Get-LadderDialog)
  }
  if($initial.process_id -eq $s.process_id -and $initial.title -eq 'DirectInput' -and $initial.class_name -eq '#32770'){
    $direct=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$initial.hwnd)
    $directLabel=Find-Id $direct '1527';$directEdit=Find-Id $direct '1265';$directCancel=Find-Id $direct '2'
    if($directLabel.Current.Name -ne '直接输入' -or -not $directEdit -or $directCancel.Current.Name -ne '取消(C)'){throw 'KV_NANO_DIRECT_INPUT_FINGERPRINT_MISMATCH'}
    Invoke-KvGuardedSendKeysAllowTargetCloseToWindow -TargetHwnd ([IntPtr]$initial.hwnd) -SuccessHwnd $s.hwnd -Step 'cancel fingerprinted direct input without applying' -Keys '{ESC}' -ExpectedTitleLike 'DirectInput'
  }
  if($Action -in @('Close','Reopen')){
    Save-Project
    $oldSession=$s
    Close-Project
    if($Action -eq 'Reopen'){
      $newProcess=Start-Process -FilePath $oldSession.kvs_exe -ArgumentList ('"'+$oldSession.project_path+'"') -PassThru
      @{process_id=$newProcess.Id;process_start_utc=$newProcess.StartTime.ToUniversalTime().ToString('o');project_path=$oldSession.project_path} | ConvertTo-Json | Set-Content (Join-Path $OutDir 'launched_process.json') -Encoding UTF8
      $deadline=(Get-Date).AddSeconds(30)
      do {Start-Sleep -Milliseconds 300;$s=Get-KvProjectSession -ProjectPath $ProjectPath -AllowMissing} while(-not $s -and (Get-Date) -lt $deadline)
      if(-not $s){throw 'KV_NANO_REOPEN_TIMEOUT'}
      $result.session=$s
      $result.closed_process_id=$oldSession.process_id
    }
  } elseif($Action -eq 'Save') { Save-Project } elseif($Action -in @('InspectLabels','ReadLabels','WriteLabels','DeleteLabel')) {
    $fg=Get-KvForegroundSnapshot
    if($Action -eq 'DeleteLabel' -and $fg.process_id -eq $s.process_id -and $fg.title -eq 'KV STUDIO' -and $fg.class_name -eq '#32770'){
      Answer-LabelDeleteConfirmation $false
      $fg=Get-KvForegroundSnapshot
    }
    if($fg.process_id -ne $s.process_id -or $fg.title -ne '编辑标号'){
    $tree=Find-Id $root 'ProjectTreeView'
    $node=Resolve-KvTreeNodeByPath -Tree $tree -Path @('^标号$')
    if(-not $node){throw 'KV_NANO_LABEL_TREE_NODE_REQUIRED'}
    $point=Get-KvTreeItemClickPoint -Element $node
    Invoke-KvGuardedMouseClick -TargetHwnd $s.hwnd -Step 'select exact Nano labels tree node' -X $point.x -Y $point.y -ExpectedTitleLike 'KV STUDIO*'
    Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $s.hwnd -Step 'open exact Nano labels table' -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO*' -SuccessTitleLike @('编辑标号') -SleepMs 300
    }
    $fg=Get-KvForegroundSnapshot
    if($fg.process_id -ne $s.process_id -or $fg.title -ne '编辑标号'){throw 'KV_NANO_LABEL_DIALOG_REQUIRED'}
    $dialog=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
    $labelHwnd=[IntPtr]$fg.hwnd
    if($Action -ne 'InspectLabels'){
      $tabName=if($LabelScope -eq 'Global'){'全局'}else{'局部'}
      Click-Named $tabName 'TabItem' $labelHwnd
      if($LabelScope -eq 'Local'){
        $combo=Find-Id $dialog '_comboBoxModule'
        if(-not $combo){throw 'KV_NANO_LABEL_PROGRAM_COMBO_REQUIRED'}
        $value=$null
        if($Action -eq 'ReadLabels' -and $combo.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$value) -and $value.Current.Value -cne $ProgramName){
          $r=$combo.Current.BoundingRectangle
          Invoke-KvGuardedMouseClick -TargetHwnd $labelHwnd -Step 'open local label module selector for snapshot read' -X ([int]($r.Right-10)) -Y ([int]($r.Y+$r.Height/2)) -ExpectedTitleLike '编辑标号'
          $items=@([Windows.Automation.AutomationElement]::RootElement.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,$ProgramName)))|Where-Object {$_.Current.ProcessId -eq $s.process_id -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::ListItem -and -not $_.Current.IsOffscreen})
          if($items.Count -ne 1){throw 'KV_NANO_LABEL_MODULE_ITEM_UNIQUE_REQUIRED'}
          $r=$items[0].Current.BoundingRectangle
          Invoke-KvGuardedMouseClick -TargetHwnd $labelHwnd -Step 'select exact local label module for snapshot read' -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -ExpectedTitleLike '编辑标号'
          $value=$null
        }
        if(-not $combo.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$value) -or $value.Current.Value -cne $ProgramName){throw 'KV_NANO_LABEL_SELECTED_PROGRAM_MISMATCH'}
      }
      $actual=Read-Labels $dialog
      $result.label_scope=$LabelScope
      $result.before_source=$actual
      if($ExpectedSourcePath -and $actual -cne $expected){Close-Labels;throw 'KV_NANO_EXPECTED_SOURCE_MISMATCH'}
      $rows=@($actual -split "`n"|Where-Object {$_})
      if($Action -in @('WriteLabels','DeleteLabel')){
        if($Row -gt ($rows.Count+1) -or ($Action -eq 'DeleteLabel' -and $Row -gt $rows.Count)){Close-Labels;throw 'KV_NANO_LABEL_ROW_OUT_OF_RANGE'}
        if($Action -eq 'DeleteLabel'){Assert-KvUserDeviceWrite ($rows[$Row-1].Split([char]9))[2]}
        Focus-LabelGrid $dialog
        $keys='^{HOME}';if($Row -gt 1){$keys+='{DOWN '+($Row-1)+'}'}
        Invoke-KvGuardedSendKeys -TargetHwnd $labelHwnd -Step 'select exact Nano label row first column' -Keys $keys -ExpectedTitleLike '编辑标号'
        if($Action -eq 'WriteLabels'){
          $pasteSource=$source
          if($labelWrite.reset_table){
            # KV STUDIO ignores empty cells in an overwrite paste. Rebuild the
            # reviewed complete table as a block so intentional blanks persist.
            $select='^{HOME}+{RIGHT 3}'
            if($rows.Count -gt 1){$select+='+{DOWN '+($rows.Count-1)+'}'}
            Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $labelHwnd -Step 'clear complete verified user label table before restoring planned blank fields' -Keys ($select+'{DELETE}') -ExpectedTitleLike '编辑标号' -SuccessTitleLike @('KV STUDIO')
            Answer-LabelDeleteConfirmation $true $true
            Focus-LabelGrid $dialog
            Invoke-KvGuardedSendKeys -TargetHwnd $labelHwnd -Step 'select first cell for complete planned label table' -Keys '^{HOME}' -ExpectedTitleLike '编辑标号'
            $pasteSource=$labelWrite.after
          }
          $pasteText=$pasteSource.Replace("`n","`r`n")+"`r`n"
          Invoke-KvGuardedClipboardSetText -TargetHwnd $labelHwnd -Step 'prepare exact Nano label row clipboard' -Text $pasteText -ExpectedTitleLike '编辑标号'
          if([Windows.Forms.Clipboard]::GetText() -cne $pasteText){throw 'KV_NANO_LABEL_PASTE_CLIPBOARD_CHANGED'}
          Invoke-KvGuardedCtrlChord -TargetHwnd $labelHwnd -Step 'paste planned Nano label TSV block once' -Vk 0x56 -ExpectedTitleLike '编辑标号' -SleepMs 600
          Invoke-KvGuardedSendKeys -TargetHwnd $labelHwnd -Step 'commit pasted label row before clipboard verification' -Keys '{TAB}' -ExpectedTitleLike '编辑标号'
          $result.pasted_row_count=if($labelWrite.reset_table){$labelWrite.table_count}else{$labelWrite.row_count}
          $result.paste_count=1
          $result.rebuilt_table_for_empty_fields=$labelWrite.reset_table
          $afterRows=@($labelWrite.after -split "`n")
        }else{
          Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $labelHwnd -Step 'directly delete all four cells of the verified label row' -Keys '+{RIGHT 3}{DELETE}' -ExpectedTitleLike '编辑标号' -SuccessTitleLike @('KV STUDIO')
          Answer-LabelDeleteConfirmation $true
          $afterRows=[Collections.Generic.List[string]]::new();for($i=0;$i -lt $rows.Count;$i++){if($i -ne $Row-1){$afterRows.Add($rows[$i])}}
        }
        $actual=Read-Labels $dialog
        if($actual -cne ($afterRows -join "`n")){throw 'KV_NANO_LABEL_WRITE_READBACK_MISMATCH'}
      }
      $result.source=$actual
      $result.label_count=@($actual -split "`n"|Where-Object {$_}).Count
      Close-Labels
      if($Action -ne 'ReadLabels'){Save-Project}
    }else{
    $dialog.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition) | ForEach-Object {@{name=$_.Current.Name;id=$_.Current.AutomationId;class=$_.Current.ClassName;type=$_.Current.ControlType.ProgrammaticName;rect=$_.Current.BoundingRectangle.ToString()}} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutDir 'label_controls.json') -Encoding UTF8
    & (Join-Path $scriptsRoot 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'labels.png' 6>$null | Out-Null
    Close-Labels
    }
  } else {
    $tree=Find-Id $root 'ProjectTreeView'
    $node=Resolve-KvTreeNodeByPath -Tree $tree -Path @('^程序:','每次扫描执行型模块',('^'+[regex]::Escape($ProgramName)+'$'))
    if(-not $node){throw 'KV_NANO_PROGRAM_MISSING'}
    $scroll=$null
    if($node.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern,[ref]$scroll)){
      Assert-KvUiForegroundHwnd -ExpectedHwnd $s.hwnd -Step 'reveal exact Nano program' -ExpectedTitleLike 'KV STUDIO*' -AllowSingleRecovery | Out-Null
      $scroll.ScrollIntoView()
    }
    $point=Get-KvTreeItemClickPoint -Element $node
    Invoke-KvGuardedDoubleClick -TargetHwnd $s.hwnd -Step 'open exact Nano program' -X $point.x -Y $point.y -ExpectedTitleLike 'KV STUDIO*' -SleepMs 200
    # Normalize row addresses on the target program, then choose text-window input.
    Open-Menu 0x53
    $collapse=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,'全部折叠转换梯形图(O)')))
    if(-not $collapse){throw 'KV_NANO_COLLAPSE_COMMAND_MISSING'}
    if($collapse.Current.IsEnabled){Click-Named '全部折叠转换梯形图(O)'}else{
      Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'close disabled collapse menu in empty or folded program' -Keys '{ESC}' -ExpectedTitleLike 'KV STUDIO*'
    }
    Open-Menu 0x53
    Click-Named '转换编辑方法(N)'
    Click-Named '窗口(W)'
    if($Action -eq 'Inspect'){
      if($InspectMenuName -eq 'ST/脚本(S)'){Open-Menu 0x53}else{Open-Menu 0x45}
      if($InspectMenuName -and $InspectMenuName -ne 'ST/脚本(S)'){
        if($InspectMenuName -ne '插入(W)'){throw 'KV_NANO_INSPECTION_MENU_NOT_ALLOWED'}
        Click-Named $InspectMenuName
      }
      $result.source='diagnostic only'
    } elseif($Action -in @('CreateScript','ReadScript','UpdateScript','DeleteScript','CreateAreaScript','ReadAreaScript','UpdateAreaScript','DeleteAreaScript')){
      $area=$Action -like '*AreaScript'
      $creating=$Action -in @('CreateScript','CreateAreaScript')
      $updating=$Action -in @('UpdateScript','UpdateAreaScript')
      $deleting=$Action -in @('DeleteScript','DeleteAreaScript')
      if($creating){
        # Allocate a new complete rung; never insert into an existing cell.
        Select-Cell 1
        Open-Menu 0x45
        Click-Named '插入(W)'
        Click-Named '空行(E)'
        Select-Cell $(if($area){1}else{5})
        Open-Menu 0x53
        Click-Named $(if($area){'插入域脚本(A)'}else{'插入框脚本(B)'})
        $window=Get-ScriptWindow
        $actual=Read-Script $window $source
        Close-Script $window
        if($actual -cne $source){throw 'KV_NANO_SCRIPT_SOURCE_READBACK_MISMATCH'}
        if(-not $area){
        Select-Cell 1
        Click-Named '输入 NO 接点(F5)' 'Button'
        $fg=Get-KvForegroundSnapshot
        if($fg.process_id -ne $s.process_id -or $fg.title -ne '' -or $fg.class_name -notlike 'WindowsForms10.Window*'){throw 'KV_NANO_CONTACT_DIALOG_REQUIRED'}
        $d=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
        $label=Find-Id $d '_labelPalOpe';$ok=Find-Id $d '_buttonOk'
        $edits=@($d.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.ClassName -like 'WindowsForms10.Edit*' -and $_.Current.Name -eq ''})
        if($label.Current.Name.Trim() -ne '与左母线连接的软元件' -or $edits.Count -ne 1 -or $ok.Current.Name -ne '覆盖'){throw 'KV_NANO_CONTACT_FINGERPRINT_REQUIRED'}
        $r=$edits[0].Current.BoundingRectangle
        Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'focus verified script condition operand' -X ([int]($r.X+10)) -Y ([int]($r.Y+6))
        Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'type validated script condition device' -Keys ('^a'+$Condition+'{TAB}')
        $r=$ok.Current.BoundingRectangle
        Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'apply verified script condition' -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SuccessProcessId $s.process_id
        Select-Cell 2
        Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'connect script condition columns two through four' -Keys '{F9}{F9}{F9}' -ExpectedTitleLike 'KV STUDIO*'
        }
      } else {
        $window=Open-Script
        $actual=Read-Script $window
        $result.before_source=$actual
        if($expected -and $actual -cne $expected){Close-Script $window;throw 'KV_NANO_EXPECTED_SOURCE_MISMATCH'}
        if($updating){$actual=Read-Script $window $source}
        Close-Script $window
        if($updating -and $actual -cne $source){throw 'KV_NANO_SCRIPT_SOURCE_READBACK_MISMATCH'}
        if($deleting){
          Select-Cell $(if($area){1}else{5})
          Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'delete source verified script box' -Keys '{DELETE}' -ExpectedTitleLike 'KV STUDIO*'
          Open-Menu 0x45
          Click-Named '删除行(Y)'
          $actual=''
        }
      }
      $result.source=$actual
      $result.script_kind=if($area){'area'}else{'box'}
      if($Action -notin @('ReadScript','ReadAreaScript')){Save-Project}
      if($creating -or $updating){
        $window=Open-Script
        $result.source=Read-Script $window
        Close-Script $window
        if($result.source -cne $source){throw 'KV_NANO_APPLIED_SCRIPT_READBACK_MISMATCH'}
      }
    } elseif($Action -like '*Ladder'){
      Select-Cell 1
      Invoke-KvGuardedCtrlChord -TargetHwnd $s.hwnd -Step 'open selected plain ladder mnemonic list' -Vk 0x44 -ExpectedTitleLike 'KV STUDIO*' -AllowModalAfter -SleepMs 250
      $dialog=Get-LadderDialog
      $actual=Read-Ladder $dialog
      $result.before_source=$actual
      if($expected -and (Normalize-Ladder $actual) -cne (Normalize-Ladder $expected)){Cancel-Ladder $dialog;throw 'KV_NANO_EXPECTED_SOURCE_MISMATCH'}
      if($Action -in @('InsertLadder','UpdateLadder')){
        $r=$dialog.edit.Current.BoundingRectangle
        Invoke-KvGuardedMouseClick -TargetHwnd $dialog.hwnd -Step 'focus verified mnemonic edit control' -X ([int]($r.X+15)) -Y ([int]($r.Y+15)) -ExpectedTitleLike '编辑列表'
        Invoke-KvGuardedSendKeys -TargetHwnd $dialog.hwnd -Step 'select mnemonic edit text' -Keys '^a' -ExpectedTitleLike '编辑列表'
        Invoke-KvGuardedClipboardPaste -TargetHwnd $dialog.hwnd -Step 'paste plain ladder source' -Text ($source.Replace("`n","`r`n")+"`r`n") -ExpectedTitleLike '编辑列表'
        if((Read-Ladder $dialog) -cne $source){throw 'KV_NANO_LADDER_PASTE_READBACK_MISMATCH'}
        $button=Find-Id $dialog.window $(if($Action -eq 'InsertLadder'){'4'}else{'1370'})
        $buttonName=if($Action -eq 'InsertLadder'){'插入(I)'}else{'替换块(R)'}
        if(-not $button -or $button.Current.Name -ne $buttonName -or -not $button.Current.IsEnabled){throw 'KV_NANO_LIST_APPLY_FINGERPRINT_REQUIRED'}
        $r=$button.Current.BoundingRectangle
        Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd $dialog.hwnd -Step ('apply verified mnemonic list '+$buttonName) -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SuccessProcessId $s.process_id -SleepMs 300
        $actual=$source
      } else {
        Cancel-Ladder $dialog
        if($Action -eq 'DeleteLadder'){
          Open-Menu 0x45
          Click-Named '删除行(Y)'
          $actual=''
        }
      }
      $result.source=$actual
      if($Action -ne 'ReadLadder'){Save-Project}
    }
  }
  $fg=Get-KvForegroundSnapshot
  if($Action -eq 'Inspect'){
    $root.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition) | ForEach-Object {@{name=$_.Current.Name;id=$_.Current.AutomationId;type=$_.Current.ControlType.ProgrammaticName;enabled=$_.Current.IsEnabled;rect=$_.Current.BoundingRectangle.ToString()}} | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $OutDir 'controls.json') -Encoding UTF8
    Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'close diagnostic menu' -Keys $(if($InspectMenuName -eq '插入(W)'){'{ESC}{ESC}'}else{'{ESC}'}) -ExpectedTitleLike 'KV STUDIO*'
  }
  $result.ok=$true
  & (Join-Path $scriptsRoot 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'desktop.png' 6>$null | Out-Null
} catch {
  $result.error_code=$_.Exception.Message
  $result.error_detail=$_.ScriptStackTrace
  & (Join-Path $scriptsRoot 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'failure.png' 6>$null | Out-Null
} finally {
  $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutDir 'nano_operation_result.json') -Encoding UTF8
  [IO.File]::WriteAllText((Join-Path $OutDir 'source_readback.txt'),[string]$result.source,[Text.UTF8Encoding]::new($false))
}
if(-not $result.ok){throw $result.error_code}
exit 0
