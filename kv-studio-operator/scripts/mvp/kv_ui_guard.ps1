$ErrorActionPreference = 'Stop'

if (-not ('KvSharedUiGuardWin32' -as [type])) {
  Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KvSharedUiGuardWin32 {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(int dwFlags, int dx, int dy, int dwData, int dwExtraInfo);
  [DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, int dwFlags, int dwExtraInfo);
}
"@
}

$script:KvUiGuardOutDir = ''
$script:KvUiGuardCheckpointDir = ''
$script:KvUiGuardSeq = 0

function Initialize-KvUiGuard {
  param(
    [Parameter(Mandatory=$true)][string]$OutDir,
    [string]$CheckpointSubdir = 'ui_guard_checkpoints'
  )
  $script:KvUiGuardOutDir = [IO.Path]::GetFullPath($OutDir)
  New-Item -ItemType Directory -Force -Path $script:KvUiGuardOutDir | Out-Null
  $safeCheckpointSubdir = ConvertTo-KvUiGuardSafeName $CheckpointSubdir
  if ($safeCheckpointSubdir.Length -gt 12) { $safeCheckpointSubdir = $safeCheckpointSubdir.Substring(0, 12).Trim('_') }
  if ([string]::IsNullOrWhiteSpace($safeCheckpointSubdir)) { $safeCheckpointSubdir = 'ui_cp' }
  $script:KvUiGuardCheckpointDir = Join-Path $script:KvUiGuardOutDir $safeCheckpointSubdir
  New-Item -ItemType Directory -Force -Path $script:KvUiGuardCheckpointDir | Out-Null
}

function Get-KvForegroundSnapshot {
  $hwnd = [KvSharedUiGuardWin32]::GetForegroundWindow()
  $titleBuilder = New-Object System.Text.StringBuilder 512
  $classBuilder = New-Object System.Text.StringBuilder 256
  [void][KvSharedUiGuardWin32]::GetWindowText($hwnd, $titleBuilder, $titleBuilder.Capacity)
  [void][KvSharedUiGuardWin32]::GetClassName($hwnd, $classBuilder, $classBuilder.Capacity)
  $pidValue = [uint32]0
  [void][KvSharedUiGuardWin32]::GetWindowThreadProcessId($hwnd, [ref]$pidValue)
  $processName = ''
  if ($pidValue -gt 0) {
    try { $processName = (Get-Process -Id ([int]$pidValue) -ErrorAction Stop).ProcessName } catch { $processName = '' }
  }
  [pscustomobject]@{
    hwnd = $hwnd.ToInt64()
    title = $titleBuilder.ToString()
    class_name = $classBuilder.ToString()
    process_id = [int]$pidValue
    process_name = $processName
  }
}

function ConvertTo-KvUiGuardSafeName {
  param([string]$Value)
  $safe = $Value -replace '[^A-Za-z0-9_.-]+', '_'
  if ([string]::IsNullOrWhiteSpace($safe)) { return 'step' }
  $safe = $safe.Trim('_')
  if ($safe.Length -gt 24) { return $safe.Substring(0, 24).Trim('_') }
  return $safe
}

function Write-KvUiGuardCheckpoint {
  param(
    [Parameter(Mandatory=$true)][string]$Step,
    [Parameter(Mandatory=$true)][string]$Status,
    [string]$Action = '',
    $Expected = $null,
    $Before = $null,
    $After = $null,
    [string]$ErrorCode = '',
    [string]$Message = '',
    [string[]]$Evidence = @()
  )
  if (-not $script:KvUiGuardCheckpointDir) {
    throw 'Initialize-KvUiGuard must be called before writing UI guard checkpoints.'
  }
  $script:KvUiGuardSeq += 1
  $fileName = ('{0:D3}_{1}_{2}.json' -f $script:KvUiGuardSeq, (ConvertTo-KvUiGuardSafeName $Step), (ConvertTo-KvUiGuardSafeName $Status))
  $path = Join-Path $script:KvUiGuardCheckpointDir $fileName
  [ordered]@{
    timestamp = (Get-Date).ToString('o')
    step = $Step
    status = $Status
    action = $Action
    expected = $Expected
    foreground_before = $Before
    foreground_after = $After
    error_code = $ErrorCode
    message = $Message
    evidence = $Evidence
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Stop-KvUiGuard {
  param(
    [Parameter(Mandatory=$true)][string]$ErrorCode,
    [Parameter(Mandatory=$true)][string]$Step,
    [Parameter(Mandatory=$true)][string]$Message,
    [string[]]$Evidence = @(),
    [int]$ExitCode = 31
  )
  $payload = [ordered]@{
    ok = $false
    error_code = $ErrorCode
    operation = 'KV STUDIO guarded UI action'
    current_step = $Step
    message = $Message
    evidence = $Evidence
    remediation = @(
      'Use scripts/mvp/kv_ui_guard.ps1 for every global keyboard, mouse, accelerator, and paste operation.',
      'Prove the target HWND is foreground before the action.',
      'If foreground recovery fails once, stop and inspect the checkpoint instead of sending input.'
    )
  }
  $json = $payload | ConvertTo-Json -Depth 6 -Compress
  [Console]::Error.WriteLine("KV_UI_GUARD_FAILED $json")
  exit $ExitCode
}

function Get-KvUiGuardForegroundErrorCode {
  param($Snapshot, [IntPtr]$ExpectedHwnd)
  if (-not $Snapshot) { return 'KV_FOCUS_LOST' }
  if ($Snapshot.hwnd -eq $ExpectedHwnd.ToInt64()) { return '' }
  if ([string]$Snapshot.process_name -match '^(powershell|pwsh|WindowsTerminal|cmd|conhost)$') { return 'KV_FOCUS_LOST_TERMINAL' }
  if ([string]$Snapshot.class_name -eq '#32770') { return 'KV_MODAL_PRESENT' }
  if ([string]$Snapshot.title -like 'KV STUDIO*') { return 'KV_TARGET_WINDOW_NOT_FOREGROUND' }
  return 'KV_FOCUS_LOST'
}

function Assert-KvUiForegroundHwnd {
  param(
    [Parameter(Mandatory=$true)][IntPtr]$ExpectedHwnd,
    [Parameter(Mandatory=$true)][string]$Step,
    [string]$ExpectedTitleLike = '',
    [switch]$AllowSingleRecovery
  )
  if ($ExpectedHwnd -eq [IntPtr]::Zero) {
    $path = Write-KvUiGuardCheckpoint -Step $Step -Status 'failed' -Action 'assert foreground hwnd' -ErrorCode 'KV_TARGET_WINDOW_MISSING' -Message 'Expected HWND is zero.'
    Stop-KvUiGuard -ErrorCode 'KV_TARGET_WINDOW_MISSING' -Step $Step -Message 'Expected HWND is zero.' -Evidence @($path)
  }

  $before = Get-KvForegroundSnapshot
  if ($before.hwnd -eq $ExpectedHwnd.ToInt64() -and ((-not $ExpectedTitleLike) -or $before.title -like $ExpectedTitleLike)) {
    return $before
  }

  if ($AllowSingleRecovery) {
    $recoveryPath = Write-KvUiGuardCheckpoint -Step $Step -Status 'recovery_before' -Action 'restore foreground once' -Expected @{ hwnd = $ExpectedHwnd.ToInt64(); title_like = $ExpectedTitleLike } -Before $before -ErrorCode (Get-KvUiGuardForegroundErrorCode $before $ExpectedHwnd) -Message 'Foreground did not match target; attempting one controlled recovery.'
    [KvSharedUiGuardWin32]::ShowWindow($ExpectedHwnd, 9) | Out-Null
    [KvSharedUiGuardWin32]::SetForegroundWindow($ExpectedHwnd) | Out-Null
    Start-Sleep -Milliseconds 180
    $afterRecovery = Get-KvForegroundSnapshot
    if ($afterRecovery.hwnd -eq $ExpectedHwnd.ToInt64() -and ((-not $ExpectedTitleLike) -or $afterRecovery.title -like $ExpectedTitleLike)) {
      Write-KvUiGuardCheckpoint -Step $Step -Status 'recovery_after' -Action 'restore foreground once' -Expected @{ hwnd = $ExpectedHwnd.ToInt64(); title_like = $ExpectedTitleLike } -Before $before -After $afterRecovery -Message 'Foreground recovery succeeded.' -Evidence @($recoveryPath) | Out-Null
      return $afterRecovery
    }
    $code = Get-KvUiGuardForegroundErrorCode $afterRecovery $ExpectedHwnd
    $failurePath = Write-KvUiGuardCheckpoint -Step $Step -Status 'failed' -Action 'assert foreground hwnd' -Expected @{ hwnd = $ExpectedHwnd.ToInt64(); title_like = $ExpectedTitleLike } -Before $before -After $afterRecovery -ErrorCode $code -Message 'Foreground recovery failed; input was not sent.' -Evidence @($recoveryPath)
    Stop-KvUiGuard -ErrorCode $code -Step $Step -Message "Foreground recovery failed. Actual foreground title='$($afterRecovery.title)' process='$($afterRecovery.process_name)'." -Evidence @($recoveryPath, $failurePath)
  }

  $code = Get-KvUiGuardForegroundErrorCode $before $ExpectedHwnd
  $path = Write-KvUiGuardCheckpoint -Step $Step -Status 'failed' -Action 'assert foreground hwnd' -Expected @{ hwnd = $ExpectedHwnd.ToInt64(); title_like = $ExpectedTitleLike } -Before $before -ErrorCode $code -Message 'Foreground did not match target; input was not sent.'
  Stop-KvUiGuard -ErrorCode $code -Step $Step -Message "Foreground did not match target. Actual foreground title='$($before.title)' process='$($before.process_name)'." -Evidence @($path)
}

function Invoke-KvGuardedSendKeys {
  param(
    [Parameter(Mandatory=$true)][IntPtr]$TargetHwnd,
    [Parameter(Mandatory=$true)][string]$Step,
    [Parameter(Mandatory=$true)][string]$Keys,
    [string]$ExpectedTitleLike = '',
    [string]$Action = 'SendKeys',
    [int]$SleepMs = 150
  )
  $before = Assert-KvUiForegroundHwnd -ExpectedHwnd $TargetHwnd -Step $Step -ExpectedTitleLike $ExpectedTitleLike -AllowSingleRecovery
  $beforePath = Write-KvUiGuardCheckpoint -Step $Step -Status 'before' -Action $Action -Expected @{ hwnd = $TargetHwnd.ToInt64(); title_like = $ExpectedTitleLike; keys = $Keys } -Before $before -Message 'Precondition passed; target owns foreground.'
  [System.Windows.Forms.SendKeys]::SendWait($Keys)
  Start-Sleep -Milliseconds $SleepMs
  $after = Assert-KvUiForegroundHwnd -ExpectedHwnd $TargetHwnd -Step "$Step postcondition" -ExpectedTitleLike $ExpectedTitleLike -AllowSingleRecovery
  Write-KvUiGuardCheckpoint -Step $Step -Status 'after' -Action $Action -Expected @{ hwnd = $TargetHwnd.ToInt64(); title_like = $ExpectedTitleLike; keys = $Keys } -Before $before -After $after -Message 'Postcondition passed; target still owns foreground.' -Evidence @($beforePath) | Out-Null
}

function Invoke-KvGuardedSendKeysAllowTargetClose {
  param(
    [Parameter(Mandatory=$true)][IntPtr]$TargetHwnd,
    [Parameter(Mandatory=$true)][string]$Step,
    [Parameter(Mandatory=$true)][string]$Keys,
    [string]$ExpectedTitleLike = '',
    [string[]]$SuccessTitleLike = @('KV STUDIO*'),
    [string]$Action = 'SendKeys',
    [int]$SleepMs = 300
  )
  $before = Assert-KvUiForegroundHwnd -ExpectedHwnd $TargetHwnd -Step $Step -ExpectedTitleLike $ExpectedTitleLike -AllowSingleRecovery
  $beforePath = Write-KvUiGuardCheckpoint -Step $Step -Status 'before' -Action $Action -Expected @{ hwnd = $TargetHwnd.ToInt64(); title_like = $ExpectedTitleLike; keys = $Keys; success_title_like = @($SuccessTitleLike) } -Before $before -Message 'Precondition passed; target owns foreground.'
  [System.Windows.Forms.SendKeys]::SendWait($Keys)
  Start-Sleep -Milliseconds $SleepMs
  $after = Get-KvForegroundSnapshot
  $targetStillWindow = [KvSharedUiGuardWin32]::IsWindow($TargetHwnd)
  $targetStillForeground = ($targetStillWindow -and $after.hwnd -eq $TargetHwnd.ToInt64() -and ((-not $ExpectedTitleLike) -or $after.title -like $ExpectedTitleLike))
  $successForeground = $false
  foreach ($pattern in @($SuccessTitleLike)) {
    if (-not $pattern -or $after.title -like $pattern) {
      $successForeground = $true
      break
    }
  }
  if ($targetStillForeground -or $successForeground) {
    Write-KvUiGuardCheckpoint -Step $Step -Status 'after' -Action $Action -Expected @{ hwnd = $TargetHwnd.ToInt64(); title_like = $ExpectedTitleLike; keys = $Keys; success_title_like = @($SuccessTitleLike); target_still_window = $targetStillWindow } -Before $before -After $after -Message 'Postcondition passed; target remained foreground or closed into the expected successor foreground.' -Evidence @($beforePath) | Out-Null
    return
  }
  $code = Get-KvUiGuardForegroundErrorCode $after $TargetHwnd
  $failurePath = Write-KvUiGuardCheckpoint -Step $Step -Status 'failed' -Action $Action -Expected @{ hwnd = $TargetHwnd.ToInt64(); title_like = $ExpectedTitleLike; keys = $Keys; success_title_like = @($SuccessTitleLike); target_still_window = $targetStillWindow } -Before $before -After $after -ErrorCode $code -Message 'Target-close action did not end in the target or expected successor foreground.' -Evidence @($beforePath)
  Stop-KvUiGuard -ErrorCode $code -Step $Step -Message "Target-close action did not reach expected successor foreground. Actual foreground title='$($after.title)' process='$($after.process_name)'." -Evidence @($beforePath, $failurePath)
}

function Invoke-KvGuardedClipboardPaste {
  param(
    [Parameter(Mandatory=$true)][IntPtr]$TargetHwnd,
    [Parameter(Mandatory=$true)][string]$Step,
    [Parameter(Mandatory=$true)][string]$Text,
    [string]$ExpectedTitleLike = '',
    [int]$SleepMs = 500
  )
  if ([string]::IsNullOrWhiteSpace($Text)) {
    $path = Write-KvUiGuardCheckpoint -Step $Step -Status 'failed' -Action 'clipboard paste' -Expected @{ hwnd = $TargetHwnd.ToInt64(); title_like = $ExpectedTitleLike } -ErrorCode 'KV_EMPTY_PASTE_TEXT' -Message 'Paste text is empty; clipboard was not changed.'
    Stop-KvUiGuard -ErrorCode 'KV_EMPTY_PASTE_TEXT' -Step $Step -Message 'Paste text is empty; clipboard was not changed.' -Evidence @($path)
  }
  Assert-KvUiForegroundHwnd -ExpectedHwnd $TargetHwnd -Step "$Step clipboard precondition" -ExpectedTitleLike $ExpectedTitleLike -AllowSingleRecovery | Out-Null
  [System.Windows.Forms.Clipboard]::SetText($Text)
  Invoke-KvGuardedSendKeys -TargetHwnd $TargetHwnd -Step $Step -Keys '^v' -ExpectedTitleLike $ExpectedTitleLike -Action 'Ctrl+V guarded clipboard paste' -SleepMs $SleepMs
}

function Invoke-KvGuardedClipboardSetText {
  param(
    [Parameter(Mandatory=$true)][IntPtr]$TargetHwnd,
    [Parameter(Mandatory=$true)][string]$Step,
    [Parameter(Mandatory=$true)][string]$Text,
    [string]$ExpectedTitleLike = ''
  )
  Assert-KvUiForegroundHwnd -ExpectedHwnd $TargetHwnd -Step "$Step clipboard-set precondition" -ExpectedTitleLike $ExpectedTitleLike -AllowSingleRecovery | Out-Null
  [System.Windows.Forms.Clipboard]::SetText($Text)
  Write-KvUiGuardCheckpoint -Step $Step -Status 'after' -Action 'clipboard set text' -Expected @{ hwnd = $TargetHwnd.ToInt64(); title_like = $ExpectedTitleLike; text_length = $Text.Length } -Message 'Clipboard text set under guarded target foreground.' | Out-Null
}

function Invoke-KvGuardedMouseClick {
  param(
    [Parameter(Mandatory=$true)][IntPtr]$TargetHwnd,
    [Parameter(Mandatory=$true)][string]$Step,
    [Parameter(Mandatory=$true)][int]$X,
    [Parameter(Mandatory=$true)][int]$Y,
    [string]$ExpectedTitleLike = '',
    [int]$SleepMs = 120
  )
  $before = Assert-KvUiForegroundHwnd -ExpectedHwnd $TargetHwnd -Step $Step -ExpectedTitleLike $ExpectedTitleLike -AllowSingleRecovery
  $beforePath = Write-KvUiGuardCheckpoint -Step $Step -Status 'before' -Action 'mouse left click' -Expected @{ hwnd = $TargetHwnd.ToInt64(); title_like = $ExpectedTitleLike; x = $X; y = $Y } -Before $before -Message 'Precondition passed; target owns foreground.'
  [KvSharedUiGuardWin32]::SetCursorPos($X, $Y) | Out-Null
  Start-Sleep -Milliseconds 40
  [KvSharedUiGuardWin32]::mouse_event(0x0002, 0, 0, 0, 0)
  Start-Sleep -Milliseconds 30
  [KvSharedUiGuardWin32]::mouse_event(0x0004, 0, 0, 0, 0)
  Start-Sleep -Milliseconds $SleepMs
  $after = Assert-KvUiForegroundHwnd -ExpectedHwnd $TargetHwnd -Step "$Step postcondition" -ExpectedTitleLike $ExpectedTitleLike -AllowSingleRecovery
  Write-KvUiGuardCheckpoint -Step $Step -Status 'after' -Action 'mouse left click' -Expected @{ hwnd = $TargetHwnd.ToInt64(); title_like = $ExpectedTitleLike; x = $X; y = $Y } -Before $before -After $after -Message 'Postcondition passed; target still owns foreground.' -Evidence @($beforePath) | Out-Null
}

function Invoke-KvGuardedVkTap {
  param(
    [Parameter(Mandatory=$true)][IntPtr]$TargetHwnd,
    [Parameter(Mandatory=$true)][string]$Step,
    [Parameter(Mandatory=$true)][byte]$Vk,
    [string]$ExpectedTitleLike = '',
    [int]$SleepMs = 70
  )
  $before = Assert-KvUiForegroundHwnd -ExpectedHwnd $TargetHwnd -Step $Step -ExpectedTitleLike $ExpectedTitleLike -AllowSingleRecovery
  $beforePath = Write-KvUiGuardCheckpoint -Step $Step -Status 'before' -Action 'virtual key tap' -Expected @{ hwnd = $TargetHwnd.ToInt64(); title_like = $ExpectedTitleLike; vk = $Vk } -Before $before -Message 'Precondition passed; target owns foreground.'
  [KvSharedUiGuardWin32]::keybd_event($Vk, 0, 0, 0)
  Start-Sleep -Milliseconds 35
  [KvSharedUiGuardWin32]::keybd_event($Vk, 0, 2, 0)
  Start-Sleep -Milliseconds $SleepMs
  $after = Assert-KvUiForegroundHwnd -ExpectedHwnd $TargetHwnd -Step "$Step postcondition" -ExpectedTitleLike $ExpectedTitleLike -AllowSingleRecovery
  Write-KvUiGuardCheckpoint -Step $Step -Status 'after' -Action 'virtual key tap' -Expected @{ hwnd = $TargetHwnd.ToInt64(); title_like = $ExpectedTitleLike; vk = $Vk } -Before $before -After $after -Message 'Postcondition passed; target still owns foreground.' -Evidence @($beforePath) | Out-Null
}

function Invoke-KvGuardedAltVk {
  param(
    [Parameter(Mandatory=$true)][IntPtr]$TargetHwnd,
    [Parameter(Mandatory=$true)][string]$Step,
    [Parameter(Mandatory=$true)][byte]$Vk,
    [string]$ExpectedTitleLike = '',
    [int]$SleepMs = 100
  )
  $before = Assert-KvUiForegroundHwnd -ExpectedHwnd $TargetHwnd -Step $Step -ExpectedTitleLike $ExpectedTitleLike -AllowSingleRecovery
  $beforePath = Write-KvUiGuardCheckpoint -Step $Step -Status 'before' -Action 'Alt+virtual key' -Expected @{ hwnd = $TargetHwnd.ToInt64(); title_like = $ExpectedTitleLike; vk = $Vk } -Before $before -Message 'Precondition passed; target owns foreground.'
  [KvSharedUiGuardWin32]::keybd_event(0x12, 0, 0, 0)
  Start-Sleep -Milliseconds 35
  [KvSharedUiGuardWin32]::keybd_event($Vk, 0, 0, 0)
  Start-Sleep -Milliseconds 35
  [KvSharedUiGuardWin32]::keybd_event($Vk, 0, 2, 0)
  Start-Sleep -Milliseconds 35
  [KvSharedUiGuardWin32]::keybd_event(0x12, 0, 2, 0)
  Start-Sleep -Milliseconds $SleepMs
  $after = Assert-KvUiForegroundHwnd -ExpectedHwnd $TargetHwnd -Step "$Step postcondition" -ExpectedTitleLike $ExpectedTitleLike -AllowSingleRecovery
  Write-KvUiGuardCheckpoint -Step $Step -Status 'after' -Action 'Alt+virtual key' -Expected @{ hwnd = $TargetHwnd.ToInt64(); title_like = $ExpectedTitleLike; vk = $Vk } -Before $before -After $after -Message 'Postcondition passed; target still owns foreground.' -Evidence @($beforePath) | Out-Null
}
