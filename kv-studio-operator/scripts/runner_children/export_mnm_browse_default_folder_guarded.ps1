param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$ExportDir,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$KvsExe='',
  [string]$CreatedProjectResultPath='',
  [switch]$RestartKvs,
  [switch]$InspectOnly,
  [int]$TimeoutSeconds=90
)
$ErrorActionPreference='Stop'
$scriptsRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $scriptsRoot 'kv_window_binding.ps1')
. (Join-Path $scriptsRoot 'kv_tree_resolver.ps1')
. (Join-Path $scriptsRoot 'guards/kv_ui_guard.ps1')
. (Join-Path $scriptsRoot 'workflow_tools/kv_mnm_text.ps1')
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
New-Item -ItemType Directory -Force -Path $OutDir,$ExportDir | Out-Null
Initialize-KvUiGuard -OutDir $OutDir -CheckpointSubdir 'mnm_export'
$result=[ordered]@{ok=$false;error_code='';message='';project_path=[IO.Path]::GetFullPath($ProjectPath);export_dir=[IO.Path]::GetFullPath($ExportDir);out_dir=[IO.Path]::GetFullPath($OutDir);process_id=0;launched_by_runner=$false;restart_requested=[bool]$RestartKvs;stopped_process_ids=@();project_saved=$false;final_title='';project_save_checks=@();mnm_files=@()}
function Find-Control($Root,[string]$Property,[string]$Value) {
  $prop=[Windows.Automation.AutomationElement]::($Property+'Property')
  $Root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition($prop,$Value)))
}
function Wait-ExportWindow([string[]]$Titles) {
  $deadline=(Get-Date).AddSeconds(8)
  do {
    $fg=Get-KvForegroundSnapshot
    if($fg.process_id -eq $session.process_id -and $fg.class_name -eq '#32770') {
      if($fg.title -notin $Titles){throw ('KV_EXPORT_UNEXPECTED_DIALOG: '+$fg.title)}
      return [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
    }
    Start-Sleep -Milliseconds 100
  } while((Get-Date) -lt $deadline)
  throw ('KV_EXPORT_EXPECTED_DIALOG_MISSING: '+($Titles -join ','))
}
function Click-ExportMenu([string]$Name,[switch]$AllowSuccessor) {
  $root=[Windows.Automation.AutomationElement]::FromHandle($session.hwnd)
  $item=Find-Control $root 'Name' $Name
  if(-not $item -or $item.Current.ControlType -ne [Windows.Automation.ControlType]::MenuItem -or -not $item.Current.IsEnabled){throw ('KV_EXPORT_MENU_ITEM_MISSING: '+$Name)}
  $r=$item.Current.BoundingRectangle
  if($r.IsEmpty -or $r.Width -le 0 -or $r.Height -le 0){throw 'KV_EXPORT_MENU_RECT_INVALID'}
  if($AllowSuccessor){
    Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd $session.hwnd -Step ('MNM menu '+$Name) -SuccessProcessId $session.process_id -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SleepMs 250
  } else {
    Invoke-KvGuardedMouseClick -TargetHwnd $session.hwnd -Step ('MNM menu '+$Name) -ExpectedTitleLike 'KV STUDIO*' -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SleepMs 150
  }
}
function Confirm-ExportDialog($Dialog,[string]$ExpectedButton,[string[]]$SuccessTitles) {
  $button=Find-Control $Dialog 'AutomationId' $ExpectedButton
  if(-not $button -or -not $button.Current.IsEnabled -or $button.Current.Name -notin @('OK','确定')){throw 'KV_EXPORT_CONFIRM_BUTTON_MISMATCH'}
  Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd ([IntPtr]$Dialog.Current.NativeWindowHandle) -Step ('confirm '+$Dialog.Current.Name) -Keys '{ENTER}' -ExpectedTitleLike $Dialog.Current.Name -SuccessTitleLike $SuccessTitles -SleepMs 400
}
function Assert-ExportProjectSaved([string]$Stage) {
  $current=Get-KvProjectSession -ProjectPath $result.project_path -CreatedProjectResultPath $CreatedProjectResultPath
  if($current.process_id -ne $session.process_id -or $current.hwnd -ne $session.hwnd -or $current.process_start_utc -ne $session.process_start_utc){throw 'KV_EXPORT_SESSION_CHANGED'}
  if($current.title -match ' \*\]$'){
    Invoke-KvGuardedSendKeys -TargetHwnd $session.hwnd -Step ('save project '+$Stage) -Keys '^s' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 500
    $current=Get-KvProjectSession -ProjectPath $result.project_path -CreatedProjectResultPath $CreatedProjectResultPath
  }
  if($current.title -match ' \*\]$'){throw 'KV_EXPORT_PROJECT_NOT_SAVED'}
  $result.project_saved=$true;$result.final_title=$current.title
  $result.project_save_checks+=@{stage=$Stage;process_id=$current.process_id;hwnd=$current.hwnd.ToInt64();final_title=$current.title;project_saved=$true}
}
try {
  $session=Get-KvProjectSession -ProjectPath $result.project_path -CreatedProjectResultPath $CreatedProjectResultPath -AllowMissing
  if($RestartKvs -and $session) {
    # Restart is allowed only for the sole path-bound, saved session.
    if(@(Get-Process Kvs).Count -ne 1 -or $session.title -match ' \*\]$'){throw 'KV_EXPORT_RESTART_REFUSED'}
    $result.stopped_process_ids=@($session.process_id)
    Stop-Process -Id $session.process_id -Force
    $session=$null
  }
  if(-not $session) {
    if(-not $KvsExe){
      $install=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'get_kvstudio_install.ps1') | ConvertFrom-Json
      if(-not $install.installed){throw 'KV_NOT_INSTALLED'}
      $KvsExe=$install.kvs_exe
    }
    $launched=Start-Process -FilePath $KvsExe -ArgumentList ('"'+$result.project_path+'"') -PassThru
    $result.launched_by_runner=$true
    $deadline=(Get-Date).AddSeconds($TimeoutSeconds)
    do {
      # Some installations hand the project to a different version/PID. The
      # complete path and editor tree identify that successor, not its basename.
      $session=Get-KvProjectSession -ProjectPath $result.project_path -CreatedProjectResultPath $CreatedProjectResultPath -AllowMissing
      if($session){break}
      Start-Sleep -Milliseconds 200
    } while((Get-Date) -lt $deadline)
    if(-not $session){throw 'KV_PROJECT_EDITOR_WINDOW_MISSING'}
    $result.launcher_process_id=$launched.Id
  }
  $result.process_id=$session.process_id;$result.session=$session
  if($InspectOnly){throw 'KV_EXPORT_INSPECTION_ONLY: no export was performed'}
  # Never select a remembered download folder or collect recent files elsewhere.
  # The unique empty directory also prevents overwrite prompts or stale exports.
  $staging=Join-Path $result.out_dir ('mnm_'+[guid]::NewGuid().ToString('N'))
  New-Item -ItemType Directory -Path $staging | Out-Null
  $result.actual_export_dir=$staging
  Assert-ExportProjectSaved 'before export'
  Invoke-KvGuardedAltVk -TargetHwnd $session.hwnd -Step 'open File menu for MNM export' -Vk 0x46 -ExpectedTitleLike 'KV STUDIO*'
  Click-ExportMenu '助记符列表(R)'
  Click-ExportMenu '保存(S)...' -AllowSuccessor
  $dialog=Wait-ExportWindow @('选择注释类型','浏览文件夹')
  if($dialog.Current.Name -eq '选择注释类型'){
    if(-not (Find-Control $dialog 'AutomationId' '2263')){throw 'KV_EXPORT_COMMENT_SELECTOR_MISSING'}
    Confirm-ExportDialog $dialog '1' @('浏览文件夹')
    $dialog=Wait-ExportWindow @('浏览文件夹')
  }
  $tree=Find-Control $dialog 'ClassName' 'SysTreeView32'
  if(-not $tree -or -not (Find-Control $dialog 'Name' '请选择助记符文件的输出文件夹。')){throw 'KV_EXPORT_FOLDER_DIALOG_MISMATCH'}
  if($staging -notmatch '^[A-Za-z]:\\'){throw 'KV_EXPORT_LOCAL_DIRECTORY_REQUIRED'}
  $drive='^.*\('+[regex]::Escape($staging.Substring(0,2))+'\)$'
  $segments=@('桌面','此电脑',$drive)+@($staging.Substring(3).TrimEnd('\').Split('\')|Where-Object{$_})
  $node=Resolve-KvTreeNodeByPath -Tree $tree -Path $segments
  if(-not $node){throw 'KV_EXPORT_FOLDER_TREE_PATH_MISSING'}
  Assert-KvUiForegroundHwnd -ExpectedHwnd ([IntPtr]$dialog.Current.NativeWindowHandle) -Step 'select explicit mnemonic export directory' -ExpectedTitleLike '浏览文件夹' | Out-Null
  $select=$node.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)
  $select.Select()
  if(-not $select.Current.IsSelected){throw 'KV_EXPORT_FOLDER_NOT_SELECTED'}
  Write-KvUiGuardRunLog -Event 'mnm_export_folder_selected' -Data @{path=$staging;tree_path=$segments;selected=$true}
  Confirm-ExportDialog $dialog '1' @('KV STUDIO')
  $completed=$false
  for($index=0;$index -lt 2;$index++){
    $message=Wait-ExportWindow @('KV STUDIO')
    $warning=Find-Control $message 'Name' '不能读取包括ST/脚本, 数据包的程序助记符文件, 请注意。'
    $success=Find-Control $message 'Name' '保存了助记符表。'
    if(-not $warning -and -not $success){throw 'KV_EXPORT_UNEXPECTED_MESSAGE'}
    $completed=[bool]$success
    Write-KvUiGuardRunLog -Event 'mnm_export_message' -Data @{text=if($success){$success.Current.Name}else{$warning.Current.Name};hwnd=$message.Current.NativeWindowHandle}
    Confirm-ExportDialog $message '2' @('KV STUDIO*')
    if($completed){break}
  }
  if(-not $completed){throw 'KV_EXPORT_COMPLETION_MESSAGE_MISSING'}
  $fg=Get-KvForegroundSnapshot
  if($fg.hwnd -ne $session.hwnd.ToInt64()){throw 'KV_EXPORT_DIALOG_NOT_CLOSED'}
  $files=@(Get-ChildItem -LiteralPath $staging -Filter '*.mnm' -File)
  if(-not $files.Count){throw 'KV_MNM_EXPORT_NO_FILES'}
  foreach($file in $files){
    $mnm=Read-KvMnmFile -Path $file.FullName
    if($mnm.module_name -cne $file.BaseName){throw 'KV_EXPORT_MODULE_FILENAME_MISMATCH'}
  }
  Assert-ExportProjectSaved 'after export'
  foreach($file in $files){
    $target=Join-Path $result.export_dir $file.Name
    Copy-Item -LiteralPath $file.FullName -Destination $target -Force
    if((Get-FileHash -LiteralPath $target).Hash -ne (Get-FileHash -LiteralPath $file.FullName).Hash){throw 'KV_EXPORT_COPY_HASH_MISMATCH'}
    $result.mnm_files+=Get-Item -LiteralPath $target | Select-Object FullName,Length,LastWriteTime
  }
  $result.mnm_files | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 (Join-Path $result.out_dir 'mnm_files.json')
  $result.ok=$true;$result.message='MNM export completed to an explicitly selected empty directory; copied files match by SHA256.'
} catch {
  $result.error_code=($_.Exception.Message -split ':')[0];$result.message=$_.Exception.Message
  Write-KvUiGuardRunLog -Event 'mnm_export_failed' -Data @{error=$result.message}
  $_.Exception.ToString() | Set-Content -Encoding UTF8 (Join-Path $OutDir 'fail.txt')
} finally {
  $result | ConvertTo-Json -Depth 9 | Set-Content -Encoding UTF8 (Join-Path $OutDir 'browse_folder_export_result.json')
}
if(-not $result.ok){exit 1}
