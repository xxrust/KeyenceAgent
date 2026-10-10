param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$FbModuleName,[Parameter(Mandatory=$true)][string]$MnmPath,[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop';New-Item -ItemType Directory -Force $OutDir|Out-Null
. (Join-Path (Split-Path -Parent $PSCommandPath) '..\guards\kv_ui_guard.ps1');Add-Type -AssemblyName System.Windows.Forms;Add-Type -AssemblyName UIAutomationClient;Add-Type -AssemblyName UIAutomationTypes
Initialize-KvUiGuard -OutDir $OutDir -CheckpointSubdir 'program_body_ui'
$projectNeedle=[IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetFullPath($ProjectPath));$p=@(Get-Process Kvs -ErrorAction SilentlyContinue|Where-Object {$_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$projectNeedle*"});if($p.Count -ne 1){if($p.Count -eq 0){throw 'KV_PROJECT_PROCESS_NOT_FOUND'};throw 'KV_TARGET_PROJECT_WINDOW_AMBIGUOUS'};$p=$p[0];$root=[Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle);$cond=New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::AutomationIdProperty,'ProjectTreeView');$tree=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,$cond);if(!$tree){throw 'KV_PROJECT_TREE_MISSING'}
$items=$tree.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::ControlTypeProperty,[Windows.Automation.ControlType]::TreeItem)));$item=$null;for($i=0;$i -lt $items.Count;$i++){$n=[string]$items.Item($i).Current.Name;if($n -eq $FbModuleName -or $n.StartsWith($FbModuleName+':',[StringComparison]::Ordinal) -or $n.StartsWith($FbModuleName+' [',[StringComparison]::Ordinal)){$item=$items.Item($i);break}};if(!$item){throw 'KV_MODULE_NOT_FOUND'};$sel=$null;if($item.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$sel)){$sel.Select()};$item.SetFocus()
Invoke-KvGuardedSendKeys -TargetHwnd $p.MainWindowHandle -Step 'program_body_open' -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 700
# A newly created FB without a display name does not open a body editor on ENTER.  The
# remaining keys are tree navigation keys in that case: UP would move the project-tree
# selection to a sibling folder and DELETE would then ask to delete that whole folder
# (observed: "[UniversalLibrary] 是否完全删除文件夹").  Prove the editor is present before
# sending anything destructive; otherwise stop with no further input.
$openSnapshot=Get-KvForegroundSnapshot
$editorProven=$false
try{
  $rootEl=[Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
  $insertCond=New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::AutomationIdProperty,'_buttonInsert')
  if($rootEl.FindFirst([Windows.Automation.TreeScope]::Descendants,$insertCond)){$editorProven=$true}
}catch{}
if($openSnapshot.class_name -eq '#32770' -and $openSnapshot.process_id -eq $p.Id){$editorProven=$true}
if(-not $editorProven){
  Write-KvUiGuardRunLog -Event 'program_body_editor_not_proven' -Data @{foreground_title=$openSnapshot.title;class_name=$openSnapshot.class_name;hwnd=$openSnapshot.hwnd}
  throw 'KV_FB_BODY_EDITOR_NOT_OPEN'
}
foreach($s in @(@('end','^{END}',180),@('up','{UP}',180),@('select','^+{HOME}',250),@('delete','{DELETE}',450))){Invoke-KvGuardedSendKeys -TargetHwnd $p.MainWindowHandle -Step "program_body_$($s[0])" -Keys $s[1] -ExpectedTitleLike 'KV STUDIO*' -SleepMs $s[2]}
Invoke-KvGuardedCtrlChord -TargetHwnd $p.MainWindowHandle -Step 'program_body_open_edit_list' -Vk 0x44 -ExpectedTitleLike 'KV STUDIO*' -AllowModalAfter -SleepMs 500
$editSnapshot=Get-KvForegroundSnapshot;$dh=[IntPtr]$p.MainWindowHandle;$editHwnd=$dh;$editTitleLike='KV STUDIO*';$editMode='embedded_panel'
if($editSnapshot -and $editSnapshot.process_id -eq $p.Id -and $editSnapshot.class_name -eq '#32770'){$editHwnd=[IntPtr]$editSnapshot.hwnd;$editTitleLike='*';$editMode='modal_window'}
$root=[Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle);$insertCond=New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::AutomationIdProperty,'_buttonInsert');$insertButton=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,$insertCond);if($editMode -eq 'embedded_panel' -and -not $insertButton){throw 'KV_EDIT_LIST_MODAL_NOT_FOUND'};Write-KvUiGuardRunLog -Event 'program_body_edit_list_detected' -Data @{insert_button_hwnd=if($insertButton){$insertButton.Current.NativeWindowHandle}else{0};foreground_hwnd=$editSnapshot.hwnd;foreground_title=$editSnapshot.title;edit_hwnd=$editHwnd.ToInt64();mode=$editMode};$mnmLines=@(Get-Content $MnmPath -Encoding Default);$headerLines=@($mnmLines|Where-Object {$_ -match '^(DEVICE:|;MODULE:|;MODULE_TYPE:)'});$moduleHeader=@($mnmLines|Where-Object {$_ -match '^;MODULE:'}|Select-Object -First 1);if($moduleHeader.Count -eq 0){throw 'KV_MNM_MODULE_HEADER_MISSING'};$moduleValue=([string]$moduleHeader[0]).Substring(8).Trim();if($moduleValue -ne $FbModuleName){throw "KV_MNM_MODULE_MISMATCH: expected=$FbModuleName actual=$moduleValue"};$bodyLines=@($mnmLines|Where-Object {$_ -notmatch '^(DEVICE:|;MODULE:|;MODULE_TYPE:)'});if($bodyLines.Count -eq 0){throw 'KV_MNM_PROGRAM_BODY_EMPTY'};$headerPath=Join-Path $OutDir 'mnm_declaration_headers.txt';$bodyPath=Join-Path $OutDir 'program_body_paste.mnm';[IO.File]::WriteAllText($headerPath,(($headerLines -join "`r`n")+"`r`n"),[Text.Encoding]::Default);$text=(($bodyLines -join "`r`n")+"`r`n");[IO.File]::WriteAllText($bodyPath,$text,[Text.Encoding]::Default);Write-KvUiGuardRunLog -Event 'program_body_payload_prepared' -Data @{source=$MnmPath;header_count=$headerLines.Count;body_count=$bodyLines.Count;header_path=$headerPath;body_path=$bodyPath;excluded_patterns=@('^DEVICE:','^;MODULE:','^;MODULE_TYPE:')};# An edit list that still holds rows from an earlier attempt makes KV STUDIO ask
# "全部覆盖" when the pasted rows are inserted.  That prompt is safe (it only replaces
# the edit-list content), so accept it here; the guard's own postcondition would
# otherwise abort before the caller could respond.
try{
  Invoke-KvGuardedClipboardPaste -TargetHwnd $editHwnd -Step 'program_body_paste' -Text $text -ExpectedTitleLike $editTitleLike -SleepMs 400
}catch{
  $ov=Get-KvForegroundSnapshot
  if($ov.class_name -ne '#32770' -or $ov.process_id -ne $p.Id){throw}
  $ovEl=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$ov.hwnd)
  $ovBtn=$null
  foreach($aid in @('_buttonOverwriteAll','2')){
    $cond=New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::AutomationIdProperty),$aid
    $ovBtn=$ovEl.FindFirst([Windows.Automation.TreeScope]::Descendants,$cond)
    if($ovBtn){break}
  }
  if(-not $ovBtn){throw}
  $ovRect=$ovBtn.Current.BoundingRectangle
  Invoke-KvGuardedMouseClick -TargetHwnd $ov.hwnd -Step 'program_body_accept_overwrite' -X ([int]($ovRect.X+$ovRect.Width/2)) -Y ([int]($ovRect.Y+$ovRect.Height/2)) -ExpectedTitleLike '*' -SleepMs 300
  Write-KvUiGuardRunLog -Event 'program_body_overwrite_accepted' -Data @{hwnd=$ov.hwnd;button=$ovBtn.Current.Name}
}
Invoke-KvGuardedSendKeys -TargetHwnd $editHwnd -Step 'program_body_tab_insert' -Keys '{TAB}' -ExpectedTitleLike $editTitleLike -SleepMs 100
$post=Get-KvForegroundSnapshot;if($post.class_name -eq '#32770' -and $post.process_id -eq $p.Id -and $post.hwnd -ne $editHwnd.ToInt64()){$ed=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$post.hwnd);$errorText=$post.title;try{$ns=$ed.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition);for($j=0;$j -lt $ns.Count;$j++){if([string]$ns.Item($j).Current.Name){$errorText+=' | '+$ns.Item($j).Current.Name}}}catch{};Write-KvUiGuardRunLog -Event 'program_body_insert_error_modal' -Data @{text=$errorText;hwnd=$post.hwnd};Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd ([IntPtr]$post.hwnd) -Step 'dismiss program body error' -Keys '{ENTER}' -ExpectedTitleLike '*' -SuccessTitleLike @('*') -SleepMs 300;try{Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $editHwnd -Step 'close edit list after error' -Keys '%{F4}' -ExpectedTitleLike $editTitleLike -SuccessTitleLike @('KV STUDIO*') -SleepMs 400}catch{};throw 'KV_PROGRAM_BODY_INVALID_MNEMONIC'}
if($editMode -eq 'modal_window'){Invoke-KvGuardedSendKeysAllowTargetCloseToWindow -TargetHwnd $editHwnd -SuccessHwnd $dh -Step 'program_body_insert' -Keys '{ENTER}' -ExpectedTitleLike $editTitleLike -SleepMs 700}else{Invoke-KvGuardedSendKeys -TargetHwnd $editHwnd -Step 'program_body_insert' -Keys '{ENTER}' -ExpectedTitleLike $editTitleLike -SleepMs 700;$rootAfter=[Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle);$insertAfter=$rootAfter.FindFirst([Windows.Automation.TreeScope]::Descendants,$insertCond);if($insertAfter){throw 'KV_EDIT_LIST_NOT_CLOSED'}}
Invoke-KvGuardedSendKeys -TargetHwnd $dh -Step 'program_body_save' -Keys '^s' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 500
[ordered]@{ok=$true;operation='set_fb_program_body';fb_module=$FbModuleName;mnm_path=$MnmPath;project_path=$ProjectPath;mnm_header_rows=$headerLines.Count;program_body_rows=@($bodyLines).Count;excluded_headers=@($headerLines);payload_path=$bodyPath;modal_closed=$true;result_verification='embedded_edit_list_closed_and_project_saved'}|ConvertTo-Json|Set-Content (Join-Path $OutDir 'program_body_result.json') -Encoding UTF8





