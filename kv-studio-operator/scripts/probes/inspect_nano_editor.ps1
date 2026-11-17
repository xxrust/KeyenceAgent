param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [ValidateSet('Inspect','CloseFileMenu','OpenMnemonicMenu','MnmSave','ConfirmExportOptions','ConfirmExportFolder','AcknowledgeMnmWarning','AcknowledgeMnmCompletion','OpenEditList','OpenWholeEditList','CancelEditList')][string]$Action='Inspect',
  [string]$ProgramName='Main',
  [string]$ExportDir=''
)
$ErrorActionPreference='Stop'
$scriptsRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $scriptsRoot 'kv_window_binding.ps1')
. (Join-Path $scriptsRoot 'kv_tree_resolver.ps1')
. (Join-Path $scriptsRoot 'guards/kv_ui_guard.ps1')
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
$lock=[Threading.Mutex]::new($false,'Local\KeyenceAgent.KvStudio.UI')
$held=$false
try {
  $held=$lock.WaitOne(0)
  if(-not $held){throw 'KV_UI_WORKFLOW_BUSY'}
  Initialize-KvUiGuard -OutDir $OutDir
  $s=Get-KvProjectSession -ProjectPath $ProjectPath
  if($s.cpu_model -notmatch '^KV-N'){throw 'KV_NANO_CPU_REQUIRED'}
  $root=[Windows.Automation.AutomationElement]::FromHandle($s.hwnd)
  if($Action -eq 'CloseFileMenu'){
    Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'cancel observed file menu and IME composition' -Keys '{ESC}{ESC}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 300
  }
  if($Action -eq 'OpenMnemonicMenu'){
    Invoke-KvGuardedAltVk -TargetHwnd $s.hwnd -Step 'open file menu' -Vk 0x46 -ExpectedTitleLike 'KV STUDIO*'
    $cond=New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,'助记符列表(R)')
    $item=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,$cond)
    if(-not $item){throw 'KV_MNM_MENU_MISSING'}
    $r=$item.Current.BoundingRectangle
    Invoke-KvGuardedMouseClick -TargetHwnd $s.hwnd -Step 'open named mnemonic submenu' -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -ExpectedTitleLike 'KV STUDIO*' -SleepMs 300
  }
  if($Action -in @('OpenEditList','OpenWholeEditList')){
    $fg=Get-KvForegroundSnapshot
    $oldEditor=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,'编辑列表')))
    if($oldEditor -or ($fg.process_id -eq $s.process_id -and $fg.class_name -eq '#32770')){throw 'KV_UNEXPECTED_MODAL_BEFORE_PROGRAM_OPEN'}
    $tree=Get-KvProjectTree -ProcessId $s.process_id
    $node=Resolve-KvTreeNodeByPath -Tree $tree -Path @('^程序:','每次扫描执行型模块',$ProgramName)
    if(-not $node){throw 'KV_NANO_PROGRAM_MISSING'}
    Select-KvTreeNode -Element $node -Attempts 1 -ClickScript {param($x,$y) Invoke-KvGuardedMouseClick -TargetHwnd $s.hwnd -Step 'select program' -X $x -Y $y -ExpectedTitleLike 'KV STUDIO*'}
    Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'open program' -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 300
    if($Action -eq 'OpenWholeEditList'){
      Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'select entire program from first to last row' -Keys '^{HOME}^+{END}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 300
    }
    Invoke-KvGuardedCtrlChord -TargetHwnd $s.hwnd -Step 'open edit list' -Vk 0x44 -ExpectedTitleLike 'KV STUDIO*' -AllowModalAfter -SleepMs 300
  }
  if($Action -eq 'MnmSave'){
    $cond=New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,'保存(S)...')
    $item=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,$cond)
    if(-not $item){throw 'KV_MNM_SAVE_MENU_MISSING'}
    $r=$item.Current.BoundingRectangle
    Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd $s.hwnd -Step 'open named mnemonic save' -SuccessProcessId $s.process_id -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SleepMs 300
  }
  if($Action -eq 'CancelEditList'){
    $d=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,'编辑列表')))
    if(-not $d -or $d.Current.ClassName -ne '#32770' -or $d.Current.ProcessId -ne $s.process_id){throw 'KV_EDIT_LIST_FINGERPRINT_REQUIRED'}
    Invoke-KvGuardedSendKeysAllowTargetCloseToWindow -TargetHwnd ([IntPtr]$d.Current.NativeWindowHandle) -SuccessHwnd $s.hwnd -Step 'cancel observed edit list' -Keys '{ESC}' -ExpectedTitleLike '编辑列表' -SleepMs 300
  }
  if($Action -eq 'ConfirmExportOptions'){
    $fg=Get-KvForegroundSnapshot
    if($fg.process_id -ne $s.process_id -or $fg.title -ne '选择注释类型' -or $fg.class_name -ne '#32770'){throw 'KV_EXPORT_OPTIONS_FINGERPRINT_REQUIRED'}
    Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'confirm no-comment mnemonic export' -Keys '{ENTER}' -ExpectedTitleLike '选择注释类型' -SuccessTitleLike @('浏览文件夹') -SleepMs 300
  }
  if($Action -eq 'ConfirmExportFolder'){
    $fg=Get-KvForegroundSnapshot
    if($fg.process_id -ne $s.process_id -or $fg.title -ne '浏览文件夹' -or $fg.class_name -ne '#32770'){throw 'KV_EXPORT_FOLDER_FINGERPRINT_REQUIRED'}
    $dialog=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
    $tree=$dialog.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ClassNameProperty,'SysTreeView32')))
    $full=[IO.Path]::GetFullPath($ExportDir)
    if($full -notmatch '^[A-Za-z]:\\' -or -not(Test-Path -LiteralPath $full -PathType Container)){throw 'KV_EXPORT_LOCAL_DIRECTORY_REQUIRED'}
    $drive='^.*\('+[regex]::Escape($full.Substring(0,2))+'\)$'
    $segments=@('桌面','此电脑',$drive)+@($full.Substring(3).TrimEnd('\').Split('\') | Where-Object {$_})
    $node=Resolve-KvTreeNodeByPath -Tree $tree -Path $segments
    if(-not $node){throw 'KV_EXPORT_FOLDER_TREE_PATH_MISSING'}
    Assert-KvUiForegroundHwnd -ExpectedHwnd ([IntPtr]$fg.hwnd) -Step 'select explicit export folder' -ExpectedTitleLike '浏览文件夹' | Out-Null
    $selection=$node.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)
    $selection.Select()
    if(-not $selection.Current.IsSelected){throw 'KV_EXPORT_FOLDER_NOT_SELECTED'}
    Write-KvUiGuardRunLog -Event 'export_folder_selected' -Data @{path=$full;tree_path=$segments;selected=$true}
    Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'confirm explicit export folder' -Keys '{ENTER}' -ExpectedTitleLike '浏览文件夹' -SuccessTitleLike @('KV STUDIO*') -SleepMs 500
  }
  if($Action -in @('AcknowledgeMnmWarning','AcknowledgeMnmCompletion')){
    $fg=Get-KvForegroundSnapshot
    if($fg.process_id -ne $s.process_id -or $fg.title -ne 'KV STUDIO' -or $fg.class_name -ne '#32770'){throw 'KV_EXPORT_WARNING_FINGERPRINT_REQUIRED'}
    $d=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
    $message=if($Action -eq 'AcknowledgeMnmWarning'){'不能读取包括ST/脚本, 数据包的程序助记符文件, 请注意。'}else{'保存了助记符表。'}
    $body=$d.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,$message)))
    if(-not $body){throw 'KV_EXPORT_WARNING_BODY_MISMATCH'}
    Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'acknowledge verified import restriction warning' -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO' -SuccessTitleLike @('KV STUDIO*') -SleepMs 500
  }
  $s | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $OutDir 'session.json')
  $fg=Get-KvForegroundSnapshot
  $fg | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $OutDir 'foreground.json')
  $scope=if($fg.process_id -eq $s.process_id){[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)}else{$root}
  $rows=@($scope.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|ForEach-Object{[pscustomobject]@{name=$_.Current.Name;id=$_.Current.AutomationId;class=$_.Current.ClassName;type=$_.Current.ControlType.ProgrammaticName;hwnd=$_.Current.NativeWindowHandle;enabled=$_.Current.IsEnabled;rect=$_.Current.BoundingRectangle.ToString()}})
  $rows | ConvertTo-Json -Depth 5 | Set-Content -Encoding UTF8 (Join-Path $OutDir 'controls.json')
  & (Join-Path $scriptsRoot 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'desktop.png'
} finally {if($held){$lock.ReleaseMutex()};$lock.Dispose()}
