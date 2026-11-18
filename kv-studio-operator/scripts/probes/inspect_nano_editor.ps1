param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [ValidateSet('Inspect','FillProbeContact','AcknowledgeConvertFailure','OpenEditMenu','PasteProbeScript','ReadProbeScript','ApplyProbeScript','AcknowledgeModuleNameRestriction','CreateProbeModule','CloseFileMenu','OpenScriptMenu','OpenProgramMenu','ChooseObservedMenu','ChooseObservedToolbar','OpenProbeBox','SelectProbeBox','CompleteProbeCondition','DeleteProbeBox','OpenProgramStart','OpenProgramEnd','OpenMnemonicMenu','MnmSave','ConfirmExportOptions','ConfirmExportFolder','AcknowledgeMnmWarning','AcknowledgeMnmCompletion','AcknowledgeScriptSelectionRestriction','OpenEditList','OpenWholeEditList','SelectProgramBody','ClearProgramBody','CancelEditList')][string]$Action='Inspect',
  [string]$ProgramName='Main',
  [ValidateRange(1,2)][int]$ScriptRow=1,
  [string]$ScriptSourcePath='',
  [string]$VerifiedReadbackPath='',
  [string]$MenuName='',
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
  if(-not $s.cpu_model -and $s.title -match '\[编辑器 \(ST/脚本编辑中\):\s*(KV-N[A-Za-z0-9-]+)\]'){$s.cpu_model=$matches[1]}
  if($s.cpu_model -notmatch '^KV-N'){throw 'KV_NANO_CPU_REQUIRED'}
  $expected="'NanoBoxProbe_Run`r`nDM0 = DM0 + 1"
  if($ScriptSourcePath){
    $expected=[IO.File]::ReadAllText([IO.Path]::GetFullPath($ScriptSourcePath),[Text.UTF8Encoding]::new($false,$true)).TrimEnd("`r","`n")
    if([string]::IsNullOrWhiteSpace($expected)){throw 'KV_NANO_EMPTY_SCRIPT_SOURCE_REJECTED'}
  }
  if($Action -eq 'DeleteProbeBox'){
    if(-not $VerifiedReadbackPath){throw 'KV_NANO_DELETE_READBACK_REQUIRED'}
    $proof=Get-Content -LiteralPath $VerifiedReadbackPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if(-not $proof.ok -or $proof.project_path -ne $s.project_path -or $proof.process_id -ne $s.process_id -or $proof.script_row -ne $ScriptRow -or $proof.source.Replace("`r`n","`n").TrimEnd() -cne $expected.Replace("`r`n","`n").TrimEnd()){throw 'KV_NANO_DELETE_READBACK_MISMATCH'}
  }
  $root=[Windows.Automation.AutomationElement]::FromHandle($s.hwnd)
  if($Action -eq 'FillProbeContact'){
    $fg=Get-KvForegroundSnapshot
    if($fg.process_id -ne $s.process_id -or $fg.title -ne '' -or $fg.class_name -notlike 'WindowsForms10.Window*'){throw 'KV_NANO_CONTACT_DIALOG_REQUIRED'}
    $d=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
    $label=$d.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'_labelPalOpe')))
    $edit=@($d.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition) | Where-Object {$_.Current.ClassName -like 'WindowsForms10.Edit*' -and $_.Current.Name -eq ''})
    $ok=$d.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'_buttonOk')))
    if(-not $label -or $label.Current.Name.Trim() -ne '与左母线连接的软元件' -or $edit.Count -ne 1 -or $ok.Current.Name -ne '覆盖'){
      @{label_found=($null -ne $label);edit_count=$edit.Count;button_name=$ok.Current.Name} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $OutDir 'contact_fingerprint_failure.json')
      throw 'KV_NANO_NO_CONTACT_FINGERPRINT_REQUIRED'
    }
    $r=$edit[0].Current.BoundingRectangle
    Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'focus verified NO contact operand' -X ([int]($r.X+10)) -Y ([int]($r.Y+6))
    Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'type always on Nano probe execution condition' -Keys '^aCR2002{TAB}' -SleepMs 300
    & (Join-Path $scriptsRoot 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'contact_before_apply.png'
    $r=$ok.Current.BoundingRectangle
    Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'apply Nano probe condition to first cell' -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SuccessProcessId $s.process_id -SleepMs 300
  }
  if($Action -eq 'AcknowledgeConvertFailure'){
    $fg=Get-KvForegroundSnapshot
    if($fg.process_id -ne $s.process_id -or $fg.title -ne 'KV STUDIO' -or $fg.class_name -ne '#32770'){throw 'KV_NANO_CONVERT_FAILURE_DIALOG_REQUIRED'}
    $d=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
    $body=$d.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,'转换失败。')))
    if(-not $body){throw 'KV_NANO_CONVERT_FAILURE_BODY_REQUIRED'}
    Invoke-KvGuardedSendKeysAllowTargetCloseToWindow -TargetHwnd ([IntPtr]$fg.hwnd) -SuccessHwnd $s.hwnd -Step 'acknowledge observed Nano conversion failure' -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO' -SleepMs 300
  }
  if($Action -in @('PasteProbeScript','ReadProbeScript','ApplyProbeScript')){
    $fg=Get-KvForegroundSnapshot
    if($fg.process_id -ne $s.process_id -or $fg.title -ne 'ST/脚本编辑窗口' -or $fg.class_name -notlike 'WindowsForms10.Window*'){throw 'KV_NANO_SCRIPT_WINDOW_REQUIRED'}
    $d=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
    $apply=$d.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,'应用后关闭')))
    if(-not $apply -or $apply.Current.ControlType -ne [Windows.Automation.ControlType]::Button){throw 'KV_NANO_SCRIPT_TOOLBAR_REQUIRED'}
    if($Action -eq 'ApplyProbeScript'){
      $r=$apply.Current.BoundingRectangle
      Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'apply verified Nano box script' -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SuccessProcessId $s.process_id -SleepMs 300
    } else {
      $panes=@($d.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition) | Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::Pane -and $_.Current.BoundingRectangle.Height -gt 150})
      if($panes.Count -ne 1){throw 'KV_NANO_SCRIPT_TEXT_PANE_UNIQUE_REQUIRED'}
      $r=$panes[0].Current.BoundingRectangle
      Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'focus verified Nano script source pane' -X ([int]($r.X+15)) -Y ([int]($r.Y+15)) -ExpectedTitleLike 'ST/脚本编辑窗口'
      $focused=[Windows.Automation.AutomationElement]::FocusedElement
      if($focused.Current.NativeWindowHandle -ne $panes[0].Current.NativeWindowHandle){throw 'KV_NANO_SCRIPT_SOURCE_FOCUS_REQUIRED'}
      if($Action -eq 'PasteProbeScript'){
        Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'select source within Nano script text editor' -Keys '^{HOME}^+{END}' -ExpectedTitleLike 'ST/脚本编辑窗口'
        Invoke-KvGuardedClipboardPaste -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'paste Nano probe source as script text' -Text $expected -ExpectedTitleLike 'ST/脚本编辑窗口'
      }
      Invoke-KvGuardedClipboardSetText -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'initialize script readback sentinel' -Text 'KV_NANO_READBACK_PENDING' -ExpectedTitleLike 'ST/脚本编辑窗口'
      Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'read complete Nano script source' -Keys '^{HOME}^+{END}^c' -ExpectedTitleLike 'ST/脚本编辑窗口'
      $actual=[Windows.Forms.Clipboard]::GetText()
      [IO.File]::WriteAllText((Join-Path $OutDir 'script_source_readback.txt'),$actual,[Text.UTF8Encoding]::new($false))
      if($actual.Replace("`r`n","`n").TrimEnd() -cne $expected.Replace("`r`n","`n")){throw 'KV_NANO_SCRIPT_SOURCE_READBACK_MISMATCH'}
      @{ok=$true;cpu_model=$s.cpu_model;project_path=$s.project_path;process_id=$s.process_id;script_row=$ScriptRow;source=$actual;action=$Action} | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $OutDir 'script_readback_result.json')
    }
  }
  if($Action -eq 'AcknowledgeModuleNameRestriction'){
    $dialogs=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::ClassNameProperty,'#32770'))) | Where-Object {$_.Current.IsEnabled -and $_.Current.Name -eq 'KV STUDIO'})
    if($dialogs.Count -ne 1){throw 'KV_NANO_NAME_WARNING_DIALOG_REQUIRED'}
    $body=$dialogs[0].FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'65535')))
    if($body.Current.Name -notlike '非法格式。*不能使用以*结束的格式。'){throw 'KV_NANO_NAME_WARNING_BODY_MISMATCH'}
    Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd ([IntPtr]$dialogs[0].Current.NativeWindowHandle) -Step 'acknowledge observed Nano module naming restriction' -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO' -SuccessTitleLike @('新建程序') -SleepMs 300
  }
  if($Action -eq 'CreateProbeModule'){
    $fg=Get-KvForegroundSnapshot
    if($fg.process_id -ne $s.process_id -or $fg.title -ne '新建程序' -or $fg.class_name -ne '#32770'){throw 'KV_NEW_NANO_PROGRAM_DIALOG_REQUIRED'}
    $d=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
    $edit=$d.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'1010')))
    $kind=$d.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'1013')))
    if(-not $edit -or $edit.Current.ClassName -ne 'Edit' -or $kind.Current.Name -ne '每次扫描执行型模块'){throw 'KV_NEW_NANO_PROGRAM_CONTROLS_MISMATCH'}
    $r=$edit.Current.BoundingRectangle
    Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'focus verified new Nano module name' -X ([int]($r.X+30)) -Y ([int]($r.Y+10)) -ExpectedTitleLike '新建程序'
    Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'select default probe module name' -Keys '^a' -ExpectedTitleLike '新建程序'
    Invoke-KvGuardedClipboardPaste -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'name isolated Nano probe module' -Text 'NanoBoxProbe_Run' -ExpectedTitleLike '新建程序'
    Invoke-KvGuardedSendKeysAllowTargetCloseToWindow -TargetHwnd ([IntPtr]$fg.hwnd) -SuccessHwnd $s.hwnd -Step 'create isolated Nano probe module' -Keys '{ENTER}' -ExpectedTitleLike '新建程序' -SleepMs 300
  }
  if($Action -in @('OpenScriptMenu','OpenProgramMenu','OpenEditMenu')){
    $vk=if($Action -eq 'OpenScriptMenu'){0x53}elseif($Action -eq 'OpenEditMenu'){0x45}else{0x4D}
    Invoke-KvGuardedAltVk -TargetHwnd $s.hwnd -Step 'inspect named Nano menu' -Vk $vk -ExpectedTitleLike 'KV STUDIO*'
  }
  if($Action -in @('ChooseObservedMenu','ChooseObservedToolbar')){
    if([string]::IsNullOrWhiteSpace($MenuName)){throw 'KV_MENU_NAME_REQUIRED'}
    $allowed=if($Action -eq 'ChooseObservedToolbar'){@('输入 NO 接点(F5)','保存项目(Ctrl+S)')}else{@('新建(G)...','转换编辑方法(N)','窗口(W)','插入框脚本(B)','转换选择的ST/脚本(S)','插入(W)','删除行(Y)')}
    if($MenuName -notin $allowed){throw 'KV_NANO_RESEARCH_COMMAND_NOT_ALLOWED'}
    $items=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,$MenuName))) | Where-Object {$_.Current.ControlType -eq $(if($Action -eq 'ChooseObservedToolbar'){[Windows.Automation.ControlType]::Button}else{[Windows.Automation.ControlType]::MenuItem}) -and $_.Current.IsEnabled -and -not $_.Current.IsOffscreen})
    if($items.Count -gt 1){$items=@($items | Where-Object {[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($_).Current.ControlType -ne [Windows.Automation.ControlType]::MenuBar})}
    if($items.Count -ne 1){throw 'KV_VISIBLE_ENABLED_MENU_UNIQUE_REQUIRED'}
    $r=$items[0].Current.BoundingRectangle
    Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd $s.hwnd -Step ('select observed Nano menu '+$MenuName) -SuccessProcessId $s.process_id -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SleepMs 300
  }
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
  if($Action -in @('OpenProbeBox','SelectProbeBox','CompleteProbeCondition','DeleteProbeBox','OpenProgramStart','OpenProgramEnd','OpenEditList','OpenWholeEditList','SelectProgramBody','ClearProgramBody')){
    if($Action -in @('OpenProbeBox','SelectProbeBox','CompleteProbeCondition','DeleteProbeBox') -and $ProgramName -ne 'NanoBoxProbe_Run'){throw 'KV_NANO_PROBE_MODULE_REQUIRED'}
    $fg=Get-KvForegroundSnapshot
    $oldEditor=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,'编辑列表')))
    if($oldEditor -or ($fg.process_id -eq $s.process_id -and $fg.class_name -eq '#32770')){throw 'KV_UNEXPECTED_MODAL_BEFORE_PROGRAM_OPEN'}
    $tree=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'ProjectTreeView')))
    if(-not $tree -or $tree.Current.ProcessId -ne $s.process_id){throw 'KV_PATH_BOUND_PROJECT_TREE_REQUIRED'}
    $node=Resolve-KvTreeNodeByPath -Tree $tree -Path @('^程序:','每次扫描执行型模块',$ProgramName)
    if(-not $node){throw 'KV_NANO_PROGRAM_MISSING'}
    $scroll=$null
    if($node.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern,[ref]$scroll)){
      Assert-KvUiForegroundHwnd -ExpectedHwnd $s.hwnd -Step 'reveal exact Nano program tree node' -ExpectedTitleLike 'KV STUDIO*' -AllowSingleRecovery | Out-Null
      $scroll.ScrollIntoView()
    }
    $point=Get-KvTreeItemClickPoint -Element $node
    if(-not $point){throw 'KV_NANO_PROGRAM_RECT_MISSING'}
    Invoke-KvGuardedDoubleClick -TargetHwnd $s.hwnd -Step 'open exact Nano program node' -X $point.x -Y $point.y -ExpectedTitleLike 'KV STUDIO*' -SleepMs 300
    $ladder=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'_ladderSplitContainer')))
    if(-not $ladder -or $ladder.Current.ProcessId -ne $s.process_id){throw 'KV_NANO_LADDER_EDITOR_REQUIRED'}
    $r=$ladder.Current.BoundingRectangle
    if($r.Width -lt 150 -or $r.Height -lt 90){throw 'KV_NANO_LADDER_RECT_INVALID'}
    Invoke-KvGuardedMouseClick -TargetHwnd $s.hwnd -Step 'focus proven Nano ladder editor' -X ([int]($r.X+90)) -Y ([int]($r.Y+65)) -ExpectedTitleLike 'KV STUDIO*' -SleepMs 200
    $focused=[Windows.Automation.AutomationElement]::FocusedElement
    $focusChain=@()
    $focusProven=$false
    for($depth=0;$focused -and $depth -lt 12;$depth++){
      $focusChain+=@{id=$focused.Current.AutomationId;name=$focused.Current.Name;hwnd=$focused.Current.NativeWindowHandle}
      if(($focused.GetRuntimeId() -join ',') -eq ($ladder.GetRuntimeId() -join ',')){$focusProven=$true;break}
      $focused=[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($focused)
    }
    $focusChain | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 (Join-Path $OutDir 'ladder_focus.json')
    if(-not $focusProven){throw 'KV_NANO_LADDER_FOCUS_REQUIRED'}
    if($Action -in @('OpenProbeBox','SelectProbeBox','CompleteProbeCondition','DeleteProbeBox','OpenProgramStart','OpenProgramEnd')){
      $keys=if($Action -eq 'OpenProgramEnd'){'^{END}'}else{'^{HOME}'}
      Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'position Nano ladder selection' -Keys $keys -ExpectedTitleLike 'KV STUDIO*' -SleepMs 200
      if($Action -eq 'OpenProgramStart' -and $ScriptRow -eq 2){
        Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'select second Nano probe condition row' -Keys '{DOWN}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 200
      }
      if($Action -in @('OpenProbeBox','SelectProbeBox','CompleteProbeCondition','DeleteProbeBox')){
        $rowKeys=if($ScriptRow -eq 2){'{DOWN}'}else{''}
        Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'select explicit Nano probe script cell' -Keys ($rowKeys+'{RIGHT 4}') -ExpectedTitleLike 'KV STUDIO*' -SleepMs 200
      }
      if($Action -eq 'OpenProbeBox'){
        Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $s.hwnd -Step 'reopen saved Nano probe box at column five' -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO*' -SuccessTitleLike @('ST/脚本编辑窗口') -SleepMs 300
        $opened=Get-KvForegroundSnapshot
        if($opened.process_id -ne $s.process_id -or $opened.title -ne 'ST/脚本编辑窗口'){throw 'KV_NANO_WINDOW_INPUT_MUST_BE_SELECTED'}
      }
      if($Action -eq 'DeleteProbeBox'){
        Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $s.hwnd -Step 'delete previously verified Nano probe script box' -Keys '{DELETE}' -ExpectedTitleLike 'KV STUDIO*' -SuccessTitleLike @('KV STUDIO*') -SleepMs 300
      }
      if($Action -eq 'CompleteProbeCondition'){
        Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'select Nano condition connection gap' -Keys '{LEFT 3}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 200
        $wire=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,'输入横向连接线(F9)')))
        if(-not $wire -or -not $wire.Current.IsEnabled){throw 'KV_NANO_HORIZONTAL_WIRE_COMMAND_REQUIRED'}
        Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'connect Nano probe condition columns two through four' -Keys '{F9}{F9}{F9}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 300
      }
    } elseif($Action -eq 'OpenWholeEditList'){
      Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'select entire program from first to last row' -Keys '^{HOME}^+{END}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 300
    }
    if($Action -in @('SelectProgramBody','ClearProgramBody')){
      if($Action -eq 'ClearProgramBody'){
        $backup=Join-Path (Split-Path -Parent $s.project_path) ($ProgramName+'.mod')
        Copy-Item -LiteralPath $backup -Destination (Join-Path $OutDir 'before_body.mod')
        Get-FileHash -LiteralPath $backup | ConvertTo-Json | Set-Content -Encoding UTF8 (Join-Path $OutDir 'before_body_hash.json')
      }
      Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'move to last program row' -Keys '^{END}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 150
      Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'exclude final row from replacement' -Keys '{UP}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 150
      Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'select program body to first row' -Keys '^+{HOME}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 200
      if($Action -eq 'ClearProgramBody'){
        Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'clear selected body in disposable project copy' -Keys '{DELETE}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 300
      }
    } elseif($Action -notin @('OpenProbeBox','SelectProbeBox','CompleteProbeCondition','DeleteProbeBox','OpenProgramStart','OpenProgramEnd')) {
      Invoke-KvGuardedCtrlChord -TargetHwnd $s.hwnd -Step 'open edit list' -Vk 0x44 -ExpectedTitleLike 'KV STUDIO*' -AllowModalAfter -SleepMs 300
    }
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
  if($Action -eq 'AcknowledgeScriptSelectionRestriction'){
    $fg=Get-KvForegroundSnapshot
    if($fg.process_id -ne $s.process_id -or $fg.title -ne 'KV STUDIO' -or $fg.class_name -ne '#32770'){throw 'KV_SCRIPT_RESTRICTION_FINGERPRINT_REQUIRED'}
    $d=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
    $body=$d.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,'框类型ST/框脚本行不能执行该指令。')))
    if(-not $body){throw 'KV_SCRIPT_RESTRICTION_BODY_MISMATCH'}
    Invoke-KvGuardedSendKeysAllowTargetCloseToWindow -TargetHwnd ([IntPtr]$fg.hwnd) -SuccessHwnd $s.hwnd -Step 'acknowledge observed script selection restriction' -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO' -SleepMs 300
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
  $editor=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::NameProperty,'编辑列表')))
  if($editor){
    $edit=$editor.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'1010')))
    if($edit){
      if(-not ('KvNanoProbeText' -as [type])){
        Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;
using System.Text;
public static class KvNanoProbeText {
  [DllImport("user32.dll",CharSet=CharSet.Unicode)] static extern IntPtr SendMessageTimeout(IntPtr hwnd,uint msg,UIntPtr wparam,StringBuilder text,uint flags,uint timeout,out UIntPtr result);
  public static string Read(IntPtr hwnd) {
    var text=new StringBuilder(1048576); UIntPtr result;
    if(SendMessageTimeout(hwnd,13,new UIntPtr((uint)text.Capacity),text,2,2000,out result)==IntPtr.Zero) throw new InvalidOperationException("KV_EDIT_LIST_READ_TIMEOUT");
    return text.ToString();
  }
}
'@
      }
      if($edit.Current.ClassName -ne 'Edit' -or $edit.Current.ProcessId -ne $s.process_id){throw 'KV_EDIT_LIST_TEXT_CONTROL_MISMATCH'}
      $text=[KvNanoProbeText]::Read([IntPtr]$edit.Current.NativeWindowHandle)
      [IO.File]::WriteAllText((Join-Path $OutDir 'edit_list_text.txt'),$text,[Text.UTF8Encoding]::new($false))
    }
  }
  & (Join-Path $scriptsRoot 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'desktop.png'
} catch {
  $failure=@{ok=$false;action=$Action;project_path=$ProjectPath;error_code=$_.Exception.Message;session=$s}
  if(Test-Path -LiteralPath $OutDir){
    $failure | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 (Join-Path $OutDir 'probe_failure.json')
    try{& (Join-Path $scriptsRoot 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'failure.png' | Out-Null}catch{}
  }
  throw
} finally {if($held){$lock.ReleaseMutex()};$lock.Dispose()}
