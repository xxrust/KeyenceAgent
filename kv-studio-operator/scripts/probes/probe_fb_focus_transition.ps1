param([string]$OutDir='H:\kvOp\fb_focus_transition')
$ErrorActionPreference='Stop'; New-Item -ItemType Directory -Force $OutDir|Out-Null
$env:KV_WORKFLOW_RUN_LOG=Join-Path $OutDir 'run.log'
. (Join-Path $PSScriptRoot '..\guards\kv_ui_guard.ps1'); Initialize-KvUiGuard -OutDir $OutDir
Add-Type -AssemblyName UIAutomationClient
$p=Get-Process Kvs|Select-Object -First 1; $root=[Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
$tree=$root.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'ProjectTreeView')))
$item=@($tree.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|?{$_.Current.Name -like 'FB_Cylinder:*'})[0]
$item.SetFocus(); $sel=$item.GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern);$sel.Select()
function Snap([string]$label){$f=[Windows.Automation.AutomationElement]::FocusedElement;[pscustomobject]@{label=$label;name=$f.Current.Name;id=$f.Current.AutomationId;type=$f.Current.ControlType.ProgrammaticName;hwnd=$f.Current.NativeWindowHandle;pid=$f.Current.ProcessId}}
$s=@();$s+=Snap 'before_alt_l'
Invoke-KvGuardedAltVk -TargetHwnd $p.MainWindowHandle -Step 'probe Alt L focus transition' -Vk 0x4C -ExpectedTitleLike '*KV STUDIO*' -SleepMs 150
$s+=Snap 'after_alt_l'
Invoke-KvGuardedShiftTab -TargetHwnd $p.MainWindowHandle -Step 'probe Shift Tab focus transition' -ExpectedTitleLike '*KV STUDIO*'
$s+=Snap 'after_shift_tab'
Invoke-KvGuardedCtrlChord -TargetHwnd $p.MainWindowHandle -Step 'probe Ctrl Tab focus transition' -Vk 0x09 -ExpectedTitleLike '*KV STUDIO*' -SleepMs 150
$s+=Snap 'after_ctrl_tab'
$s|ConvertTo-Json -Depth 4|Set-Content (Join-Path $OutDir 'focus_transition.json') -Encoding UTF8
