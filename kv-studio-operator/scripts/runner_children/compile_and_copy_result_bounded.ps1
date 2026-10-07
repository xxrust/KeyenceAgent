param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,
  [Parameter(Mandatory=$true)]
  [string]$OutDir,
  [string]$ChecklistPath = '',
  [string]$CreatedProjectResultPath = '',
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
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hwnd, uint command);
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
  $path = if($env:KV_WORKFLOW_RUN_LOG){$env:KV_WORKFLOW_RUN_LOG}else{Join-Path $OutDir 'run.log'}
  $line = ([ordered]@{timestamp=(Get-Date).ToString('o');type='compile_step';message=$Message}|ConvertTo-Json -Compress)+[Environment]::NewLine
  [IO.File]::AppendAllText($path, $line, [Text.Encoding]::UTF8)
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
    Invoke-KvGuardedSendKeys -TargetHwnd $TargetHwnd -Step 'open conversion menu' -Keys '%a' -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -Action 'Alt+A opens the conversion menu' -SleepMs 200
    $root=[Windows.Automation.AutomationElement]::FromHandle($TargetHwnd)
    $popupHwnd=[KvCompileBoundedWin32]::GetWindow($TargetHwnd,6)
    if($popupHwnd -eq [IntPtr]::Zero -or -not [KvCompileBoundedWin32]::IsWindowVisible($popupHwnd)){throw 'KV_COMPILE_MENU_NOT_ACTIVE'}
    $convertMenu=[Windows.Automation.AutomationElement]::FromHandle($popupHwnd)
    if($convertMenu.Current.ProcessId -ne $root.Current.ProcessId -or $convertMenu.Current.ControlType -ne [Windows.Automation.ControlType]::Menu -or $convertMenu.Current.IsOffscreen){throw 'KV_COMPILE_MENU_NOT_ACTIVE'}
    $commands=@($convertMenu.FindAll([Windows.Automation.TreeScope]::Children,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AcceleratorKeyProperty,'Ctrl+F9'))))
    if($commands.Count -ne 1 -or -not $commands[0].Current.IsEnabled -or $commands[0].Current.AccessKey -ne 'c'){throw 'KV_COMPILE_COMMAND_UNAVAILABLE'}
    if($commands[0].Current.IsOffscreen -or -not $commands[0].Current.HasKeyboardFocus){throw 'KV_COMPILE_MENU_NOT_ACTIVE'}
    # UIA Invoke blocks on the synchronous conversion modal. The verified
    # menu access key dispatches the same command without blocking the caller.
    Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $TargetHwnd -Step 'invoke verified conversion command' -Keys 'c' -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -SuccessTitleLike @("KV STUDIO*$ProjectNeedle*",'转换结果') -Action 'C invokes the verified enabled conversion menu command' -SleepMs 300
    Log "invoked verified Ctrl+F9 menu command $AttemptName"
  } else {
    Invoke-KvGuardedCtrlChord -TargetHwnd $TargetHwnd -Step "compile convert Ctrl+F2 $AttemptName" -Vk 0x71 -ExpectedTitleLike "KV STUDIO*$ProjectNeedle*" -Action "Ctrl+F2 compile/convert $AttemptName" -SleepMs 300 -AllowModalAfter
    Log "sent Ctrl+F2 $AttemptName"
  }
  $foreground = [Windows.Automation.AutomationElement]::FromHandle([KvCompileBoundedWin32]::GetForegroundWindow())
  if ($foreground.Current.NativeWindowHandle -ne $TargetHwnd.ToInt64()) {
    $target = [Windows.Automation.AutomationElement]::FromHandle($TargetHwnd)
    $flat = Get-WindowTextFlat $foreground
    $failed = -join [char[]](0x8F6C,0x6362,0x5931,0x8D25,0x3002)
    $succeeded = -join [char[]](0x8F6C,0x6362,0x6210,0x529F,0x3002)
    if ($foreground.Current.ProcessId -ne $target.Current.ProcessId -or $foreground.Current.ClassName -ne '#32770' -or (-not $flat.Contains($failed) -and -not $flat.Contains($succeeded))) {
      throw "KV_COMPILE_UNEXPECTED_MODAL: $flat"
    }
    Log "proven conversion result modal deferred to collector: $flat"
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
  $topWindows=$root.FindAll(
    [Windows.Automation.TreeScope]::Children,
    (New-Object Windows.Automation.AndCondition($pidCondition, $windowCondition))
  )
  foreach($window in $topWindows){
    $window
    foreach($child in $window.FindAll([Windows.Automation.TreeScope]::Children,$windowCondition)){ $child }
  }
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
  $projectNeedle = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  $fullProjectPath=[IO.Path]::GetFullPath($ProjectPath)
  $pathPattern='(?:^|\s)(?:"'+[regex]::Escape($fullProjectPath)+'"|'+[regex]::Escape($fullProjectPath)+')(?=\s|$)'
  $pathMatches=@(Get-CimInstance Win32_Process -Filter "Name='Kvs.exe'" -ErrorAction SilentlyContinue | Where-Object {$_.CommandLine -and $_.CommandLine -match $pathPattern} | ForEach-Object {Get-Process -Id ([int]$_.ProcessId) -ErrorAction SilentlyContinue} | Where-Object {$_.MainWindowHandle -ne 0})
  if ($CreatedProjectResultPath) {
    . (Join-Path (Split-Path -Parent $PSScriptRoot) 'kv_project_process_binding.ps1')
    $pathMatches=@(Get-KvCreatedProjectProcess $ProjectPath $CreatedProjectResultPath)
  }
  if($pathMatches.Count -ne 1){throw 'KV_COMPILE_PROJECT_PROCESS_AMBIGUOUS'}
  $process=$pathMatches[0]
  if (-not $process) { throw "No visible Kvs process matched target project '$projectNeedle'. Refusing to operate another project window." }

  Assert-NoBlockingPopup $process.Id
  Log "selected target KV STUDIO pid=$($process.Id) title=$($process.MainWindowTitle) without changing window size"
  for ($i = 1; $i -le 10; $i++) {
    Invoke-KvUiGuardAltForegroundUnlock
    [void](Invoke-KvUiGuardForceForeground -TargetHwnd ([IntPtr]$process.MainWindowHandle))
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

  # Use the verified menu command because the native ladder editor can consume
  # the synthetic Ctrl+F9 chord without starting conversion.
  Log 'kept the verified KV STUDIO main window focus before conversion'

  Ensure-CapsLockOn $process.MainWindowHandle "KV STUDIO*$projectNeedle*"
  Save-Screenshot '00_before_compile.png'
  Invoke-CompileAction $process.MainWindowHandle $projectNeedle 'attempt1'
  $resultTreeVisible = Wait-VisibleResultTree $process.MainWindowHandle $WaitSeconds 'after_attempt1'
  if (-not $resultTreeVisible) {
    throw 'Visible conversion result tree did not appear after guarded compile actions.'
  }

  if ($AuditCompileWait) {
    # Wait-VisibleResultTree above is the compile-completion oracle.  A deep
    # RootElement UIA search is diagnostic only; repeating it until
    # WaitSeconds made an already-complete compile spend tens of seconds in
    # post-processing.  Keep one bounded diagnostic lookup for evidence.
    Start-Sleep -Milliseconds 500
    Dismiss-ConvertFailureIfPresent $process.Id | Out-Null
    $auditResultArea = Find-ResultArea $process.Id
    if ($auditResultArea) {
      Log 'audit result-area lookup found outputTreeControl1 after result-tree completion'
    } else {
      Log 'audit result-area lookup did not find outputTreeControl1; visible result tree remains the compile completion oracle'
    }
  } else {
    Start-Sleep -Milliseconds 900
    Log 'fast compile mode: skipped UIA result-area wait; copy_convert_result step owns compile-result oracle'
  }

  Save-Screenshot '01_after_compile.png'
  $resultArea = $null
  if ($AuditCompileWait) {
    Dismiss-ConvertFailureIfPresent $process.Id | Out-Null
    # Reuse the one diagnostic lookup above; do not rescan the desktop.
    $resultArea = $auditResultArea
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
  $AuditScreenshots=$true
  try { Save-Screenshot 'failure.png' } catch { Log ('failure screenshot unavailable: '+$_.Exception.Message) }
  Log ('ERROR ' + $_.Exception.ToString())
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  exit 1
}
