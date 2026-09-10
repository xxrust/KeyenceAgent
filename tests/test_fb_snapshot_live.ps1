param(
 [Parameter(Mandatory=$true)][string]$ProjectPath,
 [Parameter(Mandatory=$true)][string]$FbModuleName,
 [Parameter(Mandatory=$true)][string]$ReferencePath,
 [Parameter(Mandatory=$true)][string]$ChecklistPath,
 [Parameter(Mandatory=$true)][string]$OutDir
)
$ErrorActionPreference='Stop'
$scripts=Join-Path (Split-Path $PSScriptRoot -Parent) 'kv-studio-operator\scripts'
New-Item -ItemType Directory -Force $OutDir|Out-Null
$env:KV_WORKFLOW_RUN_LOG=Join-Path $OutDir 'run.log'
. (Join-Path $scripts 'guards\kv_ui_guard.ps1')
. (Join-Path $scripts 'guards\kv_fb_snapshot.ps1')
Initialize-KvUiGuard -OutDir $OutDir
$expected=[IO.File]::ReadAllText($ReferencePath).Replace("`r`n","`n").TrimEnd("`r","`n")
$runs=@()
function Run-Snapshot([string]$Name){
 $dest=Join-Path $OutDir $Name
 & powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'runner_children\set_fb_arguments_guarded.ps1') -ProjectPath $ProjectPath -FbModuleName $FbModuleName -SnapshotOnly -OutDir $dest -ChecklistPath $ChecklistPath
 if($LASTEXITCODE -ne 0){throw "Snapshot runner failed: $Name"}
 $result=Get-Content (Join-Path $dest 'fb_snapshot_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $actual=[IO.File]::ReadAllText($result.raw_path).Replace("`r`n","`n").TrimEnd("`r","`n")
 if(-not $result.ok -or -not $result.focus_verified -or -not $result.clipboard_fresh -or $actual -cne $expected){throw "Snapshot did not match reference: $Name"}
 Write-KvUiGuardRunLog -Event 'snapshot_reference_match' -Data @{run=$Name;rows=$result.row_count;exact_match=$true}
 return $result
}
function Assert-LastRoute([string]$Table,[int]$Count){
 $route=Get-Content $env:KV_WORKFLOW_RUN_LOG -Encoding UTF8|ForEach-Object {$_|ConvertFrom-Json}|Where-Object type -eq 'fb_declaration_route'|Select-Object -Last 1
 if($route.initial_table -ne $Table -or $route.ctrl_tab_count -ne $Count){throw "Wrong route from $Table"}
}
try {
 $runs+=Run-Snapshot 'baseline'
 $runs+=Run-Snapshot 'from_arguments'
 Assert-LastRoute 'arguments' 2
 $ps=@(Get-Process Kvs|Where-Object {$_.MainWindowTitle -like ('*'+[IO.Path]::GetFileNameWithoutExtension($ProjectPath)+'*')})
 if($ps.Count -ne 1){throw 'KV_PROJECT_WINDOW_AMBIGUOUS'}
 $p=$ps[0]
 $state=Get-KvFbDeclarationFocus $p.Id
 $pane=$state.pane;$grid=$state.focus
 Assert-KvFbGridFocus $pane $grid
 Invoke-KvGuardedCtrlChord -TargetHwnd $p.MainWindowHandle -Step 'test start on local tab' -Vk 0x09 -ExpectedTitleLike '*KV STUDIO*' -SleepMs 120 -FocusOracle {Assert-KvFbGridFocus $pane $grid}
 if((Get-KvFbDeclarationFocus $p.Id).table -ne 'locals'){throw 'Local fixture not reached'}
 $seq=[KvFbSnapshotNative]::GetClipboardSequenceNumber()
 $blocked=$false
 try {
  Invoke-KvGuardedCtrlChord -TargetHwnd $p.MainWindowHandle -Step 'reject argument copy on local table' -Vk 0x43 -ExpectedTitleLike '*KV STUDIO*' -FocusOracle {Assert-KvFbGridFocus $pane $grid}
 } catch {if($_.Exception.Message -notin @('KV_FB_GRID_FOCUS_LOST','KV_FB_ARGUMENT_PANE_IDENTITY_MISMATCH')){throw};$blocked=$true}
 if(-not $blocked -or [KvFbSnapshotNative]::GetClipboardSequenceNumber() -ne $seq){throw 'Wrong table was not blocked before copy'}
 Write-KvUiGuardRunLog -Event 'negative_focus_test_passed' -Data @{clipboard_unchanged=$true;wrong_table='locals'}
 $runs+=Run-Snapshot 'from_locals'
 Assert-LastRoute 'locals' 1
 # The immediately preceding snapshot selected and opened this exact FB.
 $state=Get-KvFbDeclarationFocus $p.Id
 Assert-KvFbGridFocus $state.pane $state.focus
 $oldPaneHwnd=[IntPtr]$state.pane.Current.NativeWindowHandle
 Invoke-KvGuardedCtrlChord -TargetHwnd $p.MainWindowHandle -Step 'close verified FB Ctrl F4' -Vk 0x73 -ExpectedTitleLike '*KV STUDIO*' -AllowModalAfter -SleepMs 200 -FocusOracle {Assert-KvFbGridFocus $state.pane $state.focus}
 Assert-KvFbNoPopup $p.MainWindowHandle
 if([KvSharedUiGuardWin32]::IsWindow($oldPaneHwnd)){throw 'Ctrl F4 did not destroy the verified FB pane'}
 Write-KvUiGuardRunLog -Event 'fb_editor_closed_verified' -Data @{old_pane_hwnd=$oldPaneHwnd.ToInt64()}
 $runs+=Run-Snapshot 'after_close_reopen'
 $events=@(Get-Content $env:KV_WORKFLOW_RUN_LOG -Encoding UTF8|ForEach-Object {$_|ConvertFrom-Json})
 $timings=@($events|Where-Object type -eq 'atomic_action')
 if(@($timings|Where-Object {$_.elapsed_ms -ge 10000 -or -not $_.ok}).Count){throw 'Atomic timing failed'}
 $lookups=@($events|Where-Object type -eq 'module_lookup')
 if(@($lookups|Where-Object {$_.elapsed_ms -ge 1000 -or -not $_.found}).Count){throw 'Module lookup failed'}
 $result=@{ok=$true;reference_matches=$runs.Count;row_counts=@($runs.row_count);from_arguments_ctrl_tabs=2;from_locals_ctrl_tabs=1;wrong_focus_blocked=$true;close_reopen_verified=$true;max_atomic_ms=($timings|Measure-Object elapsed_ms -Maximum).Maximum;max_lookup_ms=($lookups|Measure-Object elapsed_ms -Maximum).Maximum}
 Write-KvUiGuardRunLog -Event 'live_snapshot_test_completed' -Data $result
 $result|ConvertTo-Json|Set-Content (Join-Path $OutDir 'test_result.json') -Encoding UTF8
 $result|ConvertTo-Json
} catch {
 Write-KvUiGuardRunLog -Event 'live_snapshot_test_failed' -Data @{ok=$false;error=$_.Exception.Message}
 @{ok=$false;error=$_.Exception.Message}|ConvertTo-Json|Set-Content (Join-Path $OutDir 'test_result.json') -Encoding UTF8
 throw
}
