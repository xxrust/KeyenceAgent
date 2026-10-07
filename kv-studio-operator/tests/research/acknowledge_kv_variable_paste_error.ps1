param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$OutDir,[switch]$ConfirmCoefficientRename,[switch]$CloseSavedVariableEditor)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName System.Windows.Forms
. (Join-Path $PSScriptRoot '../../scripts/guards/kv_ui_guard.ps1')
New-Item -ItemType Directory -Force $OutDir | Out-Null
Initialize-KvUiGuard -OutDir $OutDir
$mutex=[Threading.Mutex]::new($false,'Local\KeyenceAgent.KvStudio.UI')
if(-not $mutex.WaitOne(0)){throw 'KV_UI_WORKFLOW_BUSY'}
try {
  $name=[IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  $processes=@(Get-Process Kvs | Where-Object {$_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowTitle -like "*[$name]*"})
  $processes=@($processes | Where-Object {$_.MainWindowTitle.Contains($name)})
  if($processes.Count -ne 1){throw 'KV_TARGET_PROJECT_WINDOW_AMBIGUOUS'}
  $bound=$processes[0]
  if($CloseSavedVariableEditor){
    if($bound.MainWindowTitle.Contains('*')){throw 'KV_PROJECT_NOT_SAVED_BEFORE_RESEARCH_CLOSE'}
    $root=[Windows.Automation.AutomationElement]::FromHandle($bound.MainWindowHandle)
    $condition=[Windows.Automation.PropertyCondition]::new([Windows.Automation.AutomationElement]::AutomationIdProperty,'KvVariableForm')
    $editors=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,$condition))
    if($editors.Count -ne 1 -or $editors[0].Current.ProcessId -ne $bound.Id -or $editors[0].Current.ControlType -ne [Windows.Automation.ControlType]::Window){throw 'KV_EXPECTED_VARIABLE_EDITOR_MISSING'}
    $editor=$editors[0]
    [ordered]@{project_path=$ProjectPath;process_id=$bound.Id;hwnd=$editor.Current.NativeWindowHandle;automation_id=$editor.Current.AutomationId;action='close saved variable editor using bound WindowPattern'} | ConvertTo-Json | Set-Content (Join-Path $OutDir 'editor_evidence.json') -Encoding UTF8
    $editor.GetCurrentPattern([Windows.Automation.WindowPattern]::Pattern).Close()
    [ordered]@{ok=$true;foreground_after=(Get-KvForegroundSnapshot)} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutDir 'result.json') -Encoding UTF8
    return
  }
  $fg=Get-KvForegroundSnapshot
  if($fg.process_id -ne $bound.Id){throw 'KV_EXPECTED_PASTE_ERROR_MODAL_MISSING'}
  $dialog=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
  $controls=@($dialog.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition))
  $evidence=@($controls | ForEach-Object {[pscustomobject]@{name=$_.Current.Name;id=$_.Current.AutomationId;hwnd=$_.Current.NativeWindowHandle;class=$_.Current.ClassName}})
  [ordered]@{project_path=$ProjectPath;process_id=$bound.Id;process_start_utc=$bound.StartTime.ToUniversalTime().ToString('o');foreground=$fg;controls=$evidence} | ConvertTo-Json -Depth 6 | Set-Content (Join-Path $OutDir 'modal_evidence.json') -Encoding UTF8
  if($ConfirmCoefficientRename){
    $source=@($evidence | Where-Object {$_.id -eq '_labelSrcName'})
    $destination=@($evidence | Where-Object {$_.id -eq '_labelDstName'})
    if($source.Count -ne 1 -or $destination.Count -ne 1 -or $source[0].name -ne 'FitA' -or $destination[0].name -ne 'A'){throw 'KV_UNEXPECTED_RENAME_CONFIRMATION'}
    $button=@($controls | Where-Object {$_.Current.AutomationId -eq '_buttonOverwriteAll' -and $_.Current.IsEnabled -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::Button})
    if($button.Count -ne 1 -or $button[0].Current.ProcessId -ne $bound.Id){throw 'KV_RENAME_CONFIRMATION_BUTTON_MISMATCH'}
    Assert-KvUiForegroundHwnd -ExpectedHwnd ([IntPtr]$fg.hwnd) -Step 'confirm diagnosed coefficient rename' -ExpectedTitleLike 'KV STUDIO' | Out-Null
    $invoke=$button[0].GetCurrentPattern([Windows.Automation.InvokePattern]::Pattern)
    $invoke.Invoke()
  }else{
    if($fg.class_name -ne '#32770'){throw 'KV_EXPECTED_PASTE_ERROR_MODAL_MISSING'}
    $expected=[string]::Concat([char]0x7C98,[char]0x8D34,[char]0x6570,[char]0x636E,[char]0x4E2D,[char]0x5B58,[char]0x5728,[char]0x9519,[char]0x8BEF)
    if(-not @($evidence | Where-Object {$_.name.StartsWith($expected)}).Count){throw 'KV_UNEXPECTED_MODAL_TEXT'}
    Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'acknowledge diagnosed paste error' -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO' -SuccessTitleLike @('*') -SleepMs 250
  }
  [ordered]@{ok=$true;acknowledged_only=$true;foreground_after=(Get-KvForegroundSnapshot)} | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutDir 'result.json') -Encoding UTF8
} finally {$mutex.ReleaseMutex();$mutex.Dispose()}
