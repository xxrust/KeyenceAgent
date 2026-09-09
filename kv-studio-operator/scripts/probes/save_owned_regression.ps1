$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot '..\guards\kv_ui_guard.ps1')
Initialize-KvUiGuard -OutDir H:\kvOp\error_snapshot_fix_20260906\save_regression
$p=@(Get-Process Kvs | Where-Object {$_.MainWindowTitle -like '*[[]ScopeReuseRegressionFixed *'})
if($p.Count -ne 1){throw 'Owned regression project not unique'}
Invoke-KvGuardedCtrlChord -TargetHwnd $p[0].MainWindowHandle -Step 'save owned scope regression before error test' -Vk 0x53 -ExpectedTitleLike '*ScopeReuseRegressionFixed*' -SleepMs 250
