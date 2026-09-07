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
 & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'runner_children\set_fb_arguments_guarded.ps1') -ProjectPath $ProjectPath -FbModuleName $FbModuleName -SnapshotOnly -OutDir $dest -ChecklistPath $ChecklistPath
 if($LASTEXITCODE -ne 0){throw "Snapshot runner failed: $Name"}
 $result=Get-Content (Join-Path $dest 'fb_snapshot_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
 $actual=[IO.File]::ReadAllText($result.raw_path).Replace("`r`n","`n").TrimEnd("`r","`n")
 if(-not $result.ok -or -not $result.focus_verified -or -not $result.clipboard_fresh -or $actual -cne $expected){throw "Snapshot did not match reference: $Name"}
 Write-KvUiGuardRunLog -Event 'snapshot_reference_match' -Data @{run=$Name;rows=$result.row_count;exact_match=$true}
 return $result
}
try {
 $runs+=Run-Snapshot 'repeat1'
 $runs+=Run-Snapshot 'repeat2'
 $processes=@(Get-Process Kvs|Where-Object {$_.MainWindowTitle -like ('*'+[IO.Path]::GetFileNameWithoutExtension($ProjectPath)+'*')})
 if($processes.Count -ne 1){throw 'KV_PROJECT_WINDOW_AMBIGUOUS'}
 $p=$processes[0]
 Assert-KvFbNoPopup $p.MainWindowHandle
 $editor=Get-KvFbFocusAncestor '_ladderSplitContainer' $p.Id
 if(-not $editor){throw 'KV_FB_ACTIVE_EDITOR_UNPROVEN'}
 $pane=Select-KvFbArgumentPane $editor $p.Id
 $grid=[Windows.Automation.AutomationElement]::FocusedElement
 Assert-KvFbGridFocus $pane $grid
 $filter=Find-KvFbElement $pane '_usageFilterComboBox'
 $seq=[KvFbSnapshotNative]::GetClipboardSequenceNumber()
 $filter.SetFocus()
 $blocked=$false
 try {
  Invoke-KvGuardedCtrlChord -TargetHwnd $p.MainWindowHandle -Step 'negative test wrong focus before copy' -Vk 0x43 -ExpectedTitleLike '*KV STUDIO*' -FocusOracle {Assert-KvFbGridFocus $pane $grid}
 } catch {if($_.Exception.Message -ne 'KV_FB_GRID_FOCUS_LOST'){throw};$blocked=$true}
 if(-not $blocked -or [KvFbSnapshotNative]::GetClipboardSequenceNumber() -ne $seq){throw 'Wrong focus was not blocked before copy'}
 Write-KvUiGuardRunLog -Event 'negative_focus_test_passed' -Data @{error_code='KV_FB_GRID_FOCUS_LOST';clipboard_unchanged=$true}
 Invoke-KvGuardedShiftTab -TargetHwnd $p.MainWindowHandle -Step 'restore tested grid from filter' -ExpectedTitleLike '*KV STUDIO*' -FocusOracle {if(-not [Windows.Automation.AutomationElement]::FocusedElement.Equals($filter)){throw 'KV_FB_FILTER_FOCUS_MISMATCH'}}
 $grid=[Windows.Automation.AutomationElement]::FocusedElement
 Assert-KvFbGridFocus $pane $grid
 $oldEditorHwnd=[IntPtr]$editor.Current.NativeWindowHandle
 Invoke-KvGuardedCtrlChord -TargetHwnd $p.MainWindowHandle -Step 'live test close current verified FB Ctrl F4' -Vk 0x73 -ExpectedTitleLike '*KV STUDIO*' -AllowModalAfter -SleepMs 200
 Assert-KvFbNoPopup $p.MainWindowHandle
 if([KvSharedUiGuardWin32]::IsWindow($oldEditorHwnd)){throw 'Ctrl F4 did not destroy the FB editor window'}
 Write-KvUiGuardRunLog -Event 'fb_editor_closed_verified' -Data @{old_editor_hwnd=$oldEditorHwnd.ToInt64();vk=0x73}
 $runs+=Run-Snapshot 'after_close_reopen'
 $events=@(Get-Content $env:KV_WORKFLOW_RUN_LOG|ForEach-Object {$_|ConvertFrom-Json})
 $timings=@($events|Where-Object type -eq 'atomic_action')
 if(@($timings|Where-Object {$_.elapsed_ms -ge 10000 -or -not $_.ok}).Count){throw 'Atomic timing failed'}
 $result=@{ok=$true;reference_matches=$runs.Count;row_counts=@($runs.row_count);copy_ms=@($runs.copy_elapsed_ms);wrong_focus_blocked=$true;close_reopen_verified=$true;max_atomic_ms=($timings|Measure-Object elapsed_ms -Maximum).Maximum}
 Write-KvUiGuardRunLog -Event 'live_snapshot_test_completed' -Data $result
 $result|ConvertTo-Json|Set-Content (Join-Path $OutDir 'test_result.json') -Encoding UTF8
 $result|ConvertTo-Json
} catch {
 Write-KvUiGuardRunLog -Event 'live_snapshot_test_failed' -Data @{ok=$false;error=$_.Exception.Message}
 @{ok=$false;error=$_.Exception.Message}|ConvertTo-Json|Set-Content (Join-Path $OutDir 'test_result.json') -Encoding UTF8
 throw
}
