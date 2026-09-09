$ErrorActionPreference='Stop'
$env:KV_WORKFLOW_RUN_LOG='H:\kvOp\error_snapshot_fix_20260906\sample_snapshot\run.log'
. (Join-Path $PSScriptRoot '..\guards\kv_ui_guard.ps1')
Initialize-KvUiGuard -OutDir H:\kvOp\error_snapshot_fix_20260906\sample_snapshot\group_all
$fg=Get-KvForegroundSnapshot
$title=-join [char[]](0x53D8,0x91CF,0x7EC4)
if($fg.process_name -ne 'Kvs' -or $fg.title -ne $title){throw 'Expected variable group dialog'}
Invoke-KvGuardedAltVk -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'select all variable groups' -Vk 0x41 -ExpectedTitleLike $title -SleepMs 150
Invoke-KvGuardedVkTapCallerOracle -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'confirm variable group selection' -Vk 0x0D -ExpectedTitleLike $title -SleepMs 150
$after=Get-KvForegroundSnapshot
if($after.process_name -ne 'Kvs' -or $after.title -ne (-join [char[]](0x53D8,0x91CF,0x7F16,0x8F91))){throw 'Variable editor successor not proven'}
