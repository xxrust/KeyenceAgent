param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,
  [Parameter(Mandatory=$true)]
  [string]$OutDir,
  [string]$ChecklistPath = '',
  [int]$WaitSeconds = 40,
  [switch]$AuditCompileWait,
  [switch]$AuditScreenshots,
  [ValidateSet('CtrlF2','CtrlF9')]
  [string]$ConvertAction = 'CtrlF9'
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$checklistGuard = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'assert_kv_operation_checklist.ps1'
if (-not (Test-Path -LiteralPath $checklistGuard)) { throw "Checklist guard script not found: $checklistGuard" }
$global:LASTEXITCODE = 0
& $checklistGuard -ChecklistPath $ChecklistPath -SearchRoots @($OutDir, $ProjectPath) -OperationName 'compile KV STUDIO project' | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$sharedUiGuard = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'guards\kv_ui_guard.ps1'
if (-not (Test-Path -LiteralPath $sharedUiGuard)) { throw "Shared KV UI guard script not found: $sharedUiGuard" }
. $sharedUiGuard
Initialize-KvUiGuard -OutDir $OutDir -CheckpointSubdir 'shared_ui_guard_checkpoints'
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class KvCompileBoundedWin32 {
  public delegate bool EnumWindowProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern short GetKeyState(int vk);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, int flags, int extra);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(int flags, int dx, int dy, int data, int extraInfo);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public static List<IntPtr> EnumChildren(IntPtr parent) {
    List<IntPtr> result = new List<IntPtr>();
    EnumChildWindows(parent, delegate(IntPtr hwnd, IntPtr lparam) {
      result.Add(hwnd);
      return true;
    }, IntPtr.Zero);
    return result;
  }
}
"@

function Log {
  param([string]$Message)
  $line = (Get-Date -Format s) + ' ' + $Message + [Environment]::NewLine
  [IO.File]::AppendAllText((Join-Path $OutDir 'run.log'), $line, [Text.Encoding]::UTF8)
}

function Get-ForegroundTitle {
  $handle = [KvCompileBoundedWin32]::GetForegroundWindow()
  $text = [Text.StringBuilder]::new(512)
  [void][KvCompileBoundedWin32]::GetWindowText($handle, $text, $text.Capacity)
  $text.ToString()
}

function Get-KvCompileClassName {
  param([IntPtr]$Handle)
  $text = [Text.StringBuilder]::new(256)
  [void][KvCompileBoundedWin32]::GetClassName($Handle, $text, $text.Capacity)
  $text.ToString()
}

function Get-KvCompileWindowRect {
  param([IntPtr]$Handle)
  $rect = New-Object KvCompileBoundedWin32+RECT
  if (-not [KvCompileBoundedWin32]::GetWindowRect($Handle, [ref]$rect)) {
    throw "GetWindowRect failed for hwnd=$Handle"
  }
  $rect
}

function Find-VisibleResultTree {
  param([IntPtr]$MainHwnd)
  $mainRect = Get-KvCompileWindowRect $MainHwnd
  $candidates = [System.Collections.Generic.List[object]]::new()
  foreach ($child in [KvCompileBoundedWin32]::EnumChildren($MainHwnd)) {
    if (-not [KvCompileBoundedWin32]::IsWindowVisible($child)) { continue }
    $className = Get-KvCompileClassName $child
    if ($className -notlike '*SysTreeView32*') { continue }
    $rect = Get-KvCompileWindowRect $child
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -lt 300 -or $height -lt 60) { continue }
    $candidates.Add([pscustomobject]@{
      hwnd = $child.ToInt64()
      class = $className
      left = $rect.Left
      top = $rect.Top
      width = $width
      height = $height
      distance_to_bottom = [math]::Abs($mainRect.Bottom - $rect.Bottom)
    })
  }
  @($candidates |
    Sort-Object @{ Expression = { $_.distance_to_bottom }; Ascending = $true }, @{ Expression = { $_.width }; Ascending = $false } |
    Select-Object -First 1)
}

function Wait-VisibleResultTree {
  param(
    [IntPtr]$MainHwnd,
    [int]$Seconds,
    [string]$Label
  )
  $watch = [Diagnostics.Stopwatch]::StartNew()
  do {
    $candidate = @(Find-VisibleResultTree $MainHwnd)
    if ($candidate.Count -gt 0) {
      $watch.Stop()
      Log "visible result tree found label=$Label elapsed_ms=$($watch.ElapsedMilliseconds) hwnd=$($candidate[0].hwnd) rect=$($candidate[0].left),$($candidate[0].top),$($candidate[0].width),$($candidate[0].height)"
      return $true
    }
    Start-Sleep -Milliseconds 250
  } while ($watch.Elapsed.TotalSeconds -lt $Seconds)
  $watch.Stop()
  Log "visible result tree missing label=$Label elapsed_ms=$($watch.ElapsedMilliseconds)"
  return $false
}

function Invoke-CompileAction {
  param(
    [IntPtr]$TargetHwnd,
    [string]$ProjectNeedle,
    [string]$AttemptName
  )
  if ($ConvertAction -eq 'CtrlF9') {
    Invoke-KvGuardedCtrlChord -TargetHwnd $TargetHwnd -Step "compile convert Ctrl+F9 $AttemptName" -Vk 0x78 -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -Action "Ctrl+F9 compile/convert $AttemptName" -SleepMs 300
    Log "sent Ctrl+F9 $AttemptName"
  } else {
    Invoke-KvGuardedCtrlChord -TargetHwnd $TargetHwnd -Step "compile convert Ctrl+F2 $AttemptName" -Vk 0x71 -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -Action "Ctrl+F2 compile/convert $AttemptName" -SleepMs 300
    Log "sent Ctrl+F2 $AttemptName"
  }
}

function Ensure-CapsLockOn {
  param([IntPtr]$TargetHwnd, [string]$ExpectedTitleLike)
  $before = (([KvCompileBoundedWin32]::GetKeyState(0x14) -band 1) -ne 0)
  Log "CapsLock before=$before"
  if (-not $before) {
    Invoke-KvGuardedVkTap -TargetHwnd $TargetHwnd -Step 'compile CapsLock normalization' -Vk 0x14 -ExpectedTitleLike $ExpectedTitleLike -SleepMs 70
  }
  $after = (([KvCompileBoundedWin32]::GetKeyState(0x14) -band 1) -ne 0)
  Log "CapsLock after=$after"
  if (-not $after) { throw 'CapsLock normalization failed.' }
}

function Save-Screenshot {
  param([string]$Name)
  if (-not $AuditScreenshots) {
    Log "skipped screenshot $Name because AuditScreenshots is disabled"
    return
  }
  $bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = [Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
  $bitmap.Save((Join-Path $OutDir $Name))
  $graphics.Dispose()
  $bitmap.Dispose()
  Log "screenshot $Name"
}

function Get-KvWindows {
  param([int]$ProcessIdValue)
  $root = [Windows.Automation.AutomationElement]::RootElement
  $pidCondition = New-Object Windows.Automation.PropertyCondition(
    [Windows.Automation.AutomationElement]::ProcessIdProperty,
    $ProcessIdValue
  )
  $windowCondition = New-Object Windows.Automation.PropertyCondition(
    [Windows.Automation.AutomationElement]::ControlTypeProperty,
    [Windows.Automation.ControlType]::Window
  )
  $root.FindAll(
    [Windows.Automation.TreeScope]::Descendants,
    (New-Object Windows.Automation.AndCondition($pidCondition, $windowCondition))
  )
}

function Get-WindowTextFlat {
  param($Window)
  $items = $Window.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
  $flat = [Text.StringBuilder]::new()
  [void]$flat.Append([string]$Window.Current.Name)
  $itemsArray = @($items)
  for ($i = 0; $i -lt $itemsArray.Count; $i++) {
    $name = [string]$itemsArray[$i].Current.Name
    if ($name) { [void]$flat.Append(' ' + $name) }
  }
  $flat.ToString()
}

function Assert-NoBlockingPopup {
  param([int]$ProcessIdValue)
  $windows = @(Get-KvWindows $ProcessIdValue)
  for ($i = 0; $i -lt $windows.Count; $i++) {
    $window = $windows[$i]
    $aid = [string]$window.Current.AutomationId
    $name = [string]$window.Current.Name
    $class = [string]$window.Current.ClassName
    if ($name -like 'KV STUDIO - *') { continue }
    if ($aid -eq 'KvVariableForm') {
      $patternObj = $null
      if ($window.TryGetCurrentPattern([Windows.Automation.WindowPattern]::Pattern, [ref]$patternObj)) {
        $patternObj.Close()
        Start-Sleep -Milliseconds 700
        Log 'closed variable editor before compile by WindowPattern'
        continue
      }
      throw 'Variable editor is still open before compile and cannot be closed safely.'
    }
    $text = Get-WindowTextFlat $window
    if ($text.Contains('转换结果') -and ($text.Contains('转换成功') -or $text.Contains('OK'))) {
      $patternObj = $null
      if ($window.TryGetCurrentPattern([Windows.Automation.WindowPattern]::Pattern, [ref]$patternObj)) {
        $patternObj.Close()
        Start-Sleep -Milliseconds 500
        Log 'closed stale conversion result dialog before compile by WindowPattern'
        continue
      }
      throw ('Stale conversion result dialog exists before compile and cannot be closed safely: ' + $text)
    }
    if ($class -eq '#32770' -or $aid -eq 'PasteConfirmationForm' -or $name -eq 'KV STUDIO') {
      throw ('Blocking popup exists before compile: ' + $text)
    }
  }
}

function Dismiss-ConvertFailureIfPresent {
  param([int]$ProcessIdValue)
  $windows = @(Get-KvWindows $ProcessIdValue)
  for ($i = 0; $i -lt $windows.Count; $i++) {
    $window = $windows[$i]
    $text = Get-WindowTextFlat $window
    if ($text -like '*杞崲澶辫触*') {
      [KvCompileBoundedWin32]::SetForegroundWindow([IntPtr]$window.Current.NativeWindowHandle) | Out-Null
      Start-Sleep -Milliseconds 100
      Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$window.Current.NativeWindowHandle) -Step 'dismiss conversion failure dialog Enter' -Keys '{ENTER}' -ExpectedTitleLike '*' -Action 'Enter dismisses conversion failure dialog' -SleepMs 500
      Start-Sleep -Milliseconds 500
      Log 'dismissed conversion failure dialog with Enter'
      return $true
    }
  }
  return $false
}

function Find-ResultArea {
  param([int]$ProcessIdValue)
  $root = [Windows.Automation.AutomationElement]::RootElement
  $pidCondition = New-Object Windows.Automation.PropertyCondition(
    [Windows.Automation.AutomationElement]::ProcessIdProperty,
    $ProcessIdValue
  )
  $aidCondition = New-Object Windows.Automation.PropertyCondition(
    [Windows.Automation.AutomationElement]::AutomationIdProperty,
    'outputTreeControl1'
  )
  $watch = [Diagnostics.Stopwatch]::StartNew()
  $element = $root.FindFirst(
    [Windows.Automation.TreeScope]::Descendants,
    (New-Object Windows.Automation.AndCondition($pidCondition, $aidCondition))
  )
  $watch.Stop()
  Log "Find outputTreeControl1 elapsed_ms=$($watch.ElapsedMilliseconds)"
  if ($watch.ElapsedMilliseconds -gt 1000) {
    Log "WARN result area lookup exceeded 1s: $($watch.ElapsedMilliseconds)ms"
  }
  $element
}

try {
  $process = Get-Process Kvs -ErrorAction Stop |
    Where-Object { $_.MainWindowHandle -ne 0 } |
    Select-Object -First 1
  if (-not $process) { throw 'No visible Kvs process.' }
  $projectNeedle = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)

  Assert-NoBlockingPopup $process.Id
  [KvCompileBoundedWin32]::ShowWindow($process.MainWindowHandle, 3) | Out-Null
  Start-Sleep -Milliseconds 500
  Log 'maximized KV STUDIO before conversion'
  for ($i = 1; $i -le 10; $i++) {
    Invoke-KvUiGuardAltForegroundUnlock
    [KvCompileBoundedWin32]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
    Start-Sleep -Milliseconds 150
    $title = Get-ForegroundTitle
    Log "foreground compile try=$i title=$title"
    if ($title -like 'KV STUDIO*' -and $title -like "*$projectNeedle*" -and -not [KvCompileBoundedWin32]::IsIconic($process.MainWindowHandle)) {
      break
    }
  }
  $title = Get-ForegroundTitle
  if ($title -notlike 'KV STUDIO*' -or $title -notlike "*$projectNeedle*") {
    throw "KV STUDIO is not foreground on target project before compile. title=$title"
  }
  if ($title.Contains('模拟器') -or $title.Contains('妯℃嫙鍣')) {
    throw "KV STUDIO is in simulator mode before compile. Close simulator mode or restart from a clean editor-state workflow. title=$title"
  }

  Invoke-KvGuardedVkTap -TargetHwnd $process.MainWindowHandle -Step 'compile editor focus settle Esc' -Vk 0x1B -ExpectedTitleLike "KV STUDIO*$projectNeedle*" -SleepMs 250
  Log 'sent Esc to settle editor focus before conversion'

  Ensure-CapsLockOn $process.MainWindowHandle "KV STUDIO*$projectNeedle*"
  Save-Screenshot '00_before_compile.png'
  Invoke-CompileAction $process.MainWindowHandle $projectNeedle 'attempt1'
  $resultTreeVisible = Wait-VisibleResultTree $process.MainWindowHandle 8 'after_attempt1'
  if (-not $resultTreeVisible) {
    Log 'visible result tree did not appear after first compile action; sending one more guarded compile action inside compile atomic step'
    Invoke-CompileAction $process.MainWindowHandle $projectNeedle 'attempt2'
    $secondWaitSeconds = [math]::Max(8, [math]::Min($WaitSeconds, 20))
    $resultTreeVisible = Wait-VisibleResultTree $process.MainWindowHandle $secondWaitSeconds 'after_attempt2'
  }
  if (-not $resultTreeVisible) {
    throw 'Visible conversion result tree did not appear after guarded compile actions.'
  }

  if ($AuditCompileWait) {
    $deadline = (Get-Date).AddSeconds($WaitSeconds)
    do {
      Start-Sleep -Milliseconds 500
      if (Dismiss-ConvertFailureIfPresent $process.Id) { break }
      $result = Find-ResultArea $process.Id
      if ($result) {
        $name = [string]$result.Current.Name
        if ($name -like '*杞崲缁撴灉*' -or $name -like '*Convert*') { break }
      }
    } while ((Get-Date) -lt $deadline)
  } else {
    Start-Sleep -Milliseconds 900
    Log 'fast compile mode: skipped UIA result-area wait; copy_convert_result step owns compile-result oracle'
  }

  Save-Screenshot '01_after_compile.png'
  $resultArea = $null
  if ($AuditCompileWait) {
    Dismiss-ConvertFailureIfPresent $process.Id | Out-Null
    $resultArea = Find-ResultArea $process.Id
    if ($resultArea) {
      Log 'outputTreeControl1 result area found; text extraction deferred to copy_convert_result_from_tree_handle.ps1'
    } else {
      Log 'outputTreeControl1 result area not found; text extraction deferred to copy_convert_result_from_tree_handle.ps1'
    }
  }
  [pscustomobject]@{
    ok = $true
    convert_action = $ConvertAction
    foreground = Get-ForegroundTitle
    result_area_found = [bool]$resultArea
    text_extraction_deferred = $true
    audit_compile_wait = [bool]$AuditCompileWait
  } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $OutDir 'result.json') -Encoding UTF8
  Log 'done'
  return
} catch {
  Log ('ERROR ' + $_.Exception.ToString())
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  exit 1
}
