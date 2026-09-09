param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\guards\kv_ui_guard.ps1')
$env:KV_WORKFLOW_RUN_LOG=Join-Path $OutDir 'run.log'
Initialize-KvUiGuard -OutDir $OutDir
$p=Get-Process Kvs
$root=[Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)
$els=$root.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)
$pane=@($els|Where-Object {$_.Current.AutomationId -eq '_tabFBMacroParam' -and $_.Current.ControlType -eq [Windows.Automation.ControlType]::Pane})[0]
if(-not $pane){throw 'Argument pane missing'}
Assert-KvUiForegroundHwnd -ExpectedHwnd $p.MainWindowHandle -Step 'activate before focus route' -AllowSingleRecovery|Out-Null
Invoke-KvGuardedAltVk -TargetHwnd $p.MainWindowHandle -Step 'physical Alt L' -Vk 0x4C -SleepMs 120
$filter=$pane.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'_usageFilterComboBox')))
$f=[Windows.Automation.AutomationElement]::FocusedElement
if(-not $f.Equals($filter)){throw "Filter not focused: $($f.Current.AutomationId)"}
Invoke-KvGuardedShiftTab -TargetHwnd $p.MainWindowHandle -Step 'physical Shift Tab from proven filter' -FocusOracle {if(-not [Windows.Automation.AutomationElement]::FocusedElement.Equals($filter)){throw 'Focus changed'}}
$f=[Windows.Automation.AutomationElement]::FocusedElement
$trace=@();$e=$f
for($i=0;$e -and $i -lt 12;$i++){$trace+=@{id=$e.Current.AutomationId;name=$e.Current.Name;type=$e.Current.ControlType.ProgrammaticName;hwnd=$e.Current.NativeWindowHandle};$e=[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($e)}
$trace|ConvertTo-Json -Depth 3|Set-Content (Join-Path $OutDir 'focus_chain.json') -Encoding UTF8
