param(
  [string]$MnmPath = '',
  [string]$ProjectPath = 'C:\Users\Public\KVSkillPractice\Projects\CodexUiCompileSmoke\CodexUiCompileSmoke.kpr',
  [string]$OutDir = 'C:\Users\Public\KVSkillPractice\vm-103\mnm_import_validation',
  [string]$KvsExe = 'D:\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe',
  [string]$ExpectedModuleName = '',
  [switch]$SaveAfterImport,
  [string]$ProjectSearchRoot = '',
  [object]$FailOnMissingProjectPlainText = $false,
  [object]$FailOnMissingValidationNeedles = $false,
  [switch]$DeleteExistingModuleBeforeImport,
  [object]$RestartKvs = $true,
  [string]$ExpectedCategory = '',
  [string]$ChecklistPath = '',
  [switch]$VerboseUiDump,
  [switch]$AuditImportWaits,
  [switch]$AuditProjectTextScan,
  [switch]$AuditUiNameScan
)

$ErrorActionPreference='Continue'
$out=$OutDir
$project=$ProjectPath
$kvs=$KvsExe
New-Item -ItemType Directory -Force -Path $out | Out-Null

$checklistGuard = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'assert_kv_operation_checklist.ps1'
if (-not (Test-Path -LiteralPath $checklistGuard)) { throw "Checklist guard script not found: $checklistGuard" }
$global:LASTEXITCODE = 0
& $checklistGuard -ChecklistPath $ChecklistPath -SearchRoots @($out, $project, $MnmPath) -OperationName 'import MNM into KV STUDIO' | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Set-Content -LiteralPath (Join-Path $out 'bootstrap.log') -Value ((Get-Date -Format s) + ' bootstrap start') -Encoding UTF8
function Log($m){
  $line = (Get-Date -Format s) + ' ' + $m + [Environment]::NewLine
  [IO.File]::AppendAllText((Join-Path $out 'run.log'), $line, [Text.Encoding]::UTF8)
}

function ConvertTo-BoolValue([object]$Value, [bool]$Default) {
  if ($null -eq $Value) { return $Default }
  if ($Value -is [bool]) { return [bool]$Value }
  if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64]) {
    return ([int64]$Value) -ne 0
  }

  $text = ([string]$Value).Trim()
  if ($text.Length -eq 0) { return $Default }
  switch -Regex ($text) {
    '^(?i:\$?true|1|yes|y|on)$' { return $true }
    '^(?i:\$?false|0|no|n|off)$' { return $false }
    default { throw "Invalid boolean value: $Value" }
  }
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$sharedUiGuard = Join-Path (Split-Path -Parent $PSCommandPath) 'kv_ui_guard.ps1'
if (-not (Test-Path -LiteralPath $sharedUiGuard)) { throw "Shared KV UI guard script not found: $sharedUiGuard" }
. $sharedUiGuard
Initialize-KvUiGuard -OutDir $out -CheckpointSubdir 'shared_ui_guard_checkpoints'
Add-Type @"
using System;using System.Runtime.InteropServices;
public class W{
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd,int nCmdShow);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int X,int Y);
[DllImport("user32.dll")] public static extern void mouse_event(int dwFlags,int dx,int dy,int dwData,int dwExtraInfo);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
[DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
[DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
[DllImport("user32.dll")] public static extern IntPtr SetActiveWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr hWnd);
[DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
[DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
[DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
[DllImport("user32.dll")] public static extern short GetKeyState(int nVirtKey);
[DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);
[DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
[DllImport("user32.dll")] public static extern void keybd_event(byte bVk, byte bScan, int dwFlags, int dwExtraInfo);
public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}
"@
$script:KvGuardTargetHwnd = [IntPtr]::Zero
$script:KvGuardExpectedTitleLike = 'KV STUDIO*'
function SetKvGuardTarget([IntPtr]$hwnd, [string]$titleLike){
  $script:KvGuardTargetHwnd = $hwnd
  if($titleLike){ $script:KvGuardExpectedTitleLike = $titleLike }
}
function GetElementGuardHwnd($element){
  try{
    $current=$element
    $walker=[System.Windows.Automation.TreeWalker]::ControlViewWalker
    while($current){
      if($current.Current.ControlType.ProgrammaticName -eq 'ControlType.Window' -and [int64]$current.Current.NativeWindowHandle -ne 0){
        return [IntPtr]$current.Current.NativeWindowHandle
      }
      $current=$walker.GetParent($current)
    }
  }catch{}
  return $script:KvGuardTargetHwnd
}
function SendVkTap([byte]$vk){
  Invoke-KvGuardedVkTap -TargetHwnd $script:KvGuardTargetHwnd -Step ('MNM import VK tap '+$vk) -Vk $vk -ExpectedTitleLike $script:KvGuardExpectedTitleLike -SleepMs 80
}
function TestCapsLockOn(){
  return (([W]::GetKeyState(0x14) -band 0x0001) -ne 0)
}
function SetCapsLockState([bool]$enabled){
  $current=TestCapsLockOn
  Log ('CapsLock before accelerator normalization='+$current)
  if($current -ne $enabled){
    SendVkTap 0x14
    Start-Sleep -Milliseconds 100
  }
  $after=TestCapsLockOn
  Log ('CapsLock after accelerator normalization='+$after)
  if($after -ne $enabled){
    throw ('Failed to set CapsLock state to '+$enabled)
  }
}
function SendAltLetter([byte]$vk){
  Invoke-KvGuardedAltVk -TargetHwnd $script:KvGuardTargetHwnd -Step ('MNM import Alt+VK '+$vk) -Vk $vk -ExpectedTitleLike $script:KvGuardExpectedTitleLike -SleepMs 120
}
function Shot($n){try{$b=[Windows.Forms.Screen]::PrimaryScreen.Bounds;$bmp=New-Object Drawing.Bitmap $b.Width,$b.Height;$g=[Drawing.Graphics]::FromImage($bmp);$g.CopyFromScreen(0,0,0,0,$bmp.Size);$bmp.Save((Join-Path $out $n));$g.Dispose();$bmp.Dispose();Log "shot $n"}catch{Log ('shot err '+$_.Exception.Message)}}
function TestKvSplashVisible(){
  try{
    $bounds=[Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap=New-Object Drawing.Bitmap $bounds.Width,$bounds.Height
    $graphics=[Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen(0,0,0,0,$bitmap.Size)
    $graphics.Dispose()
    $blue=0
    $samples=0
    $startX=[int]($bounds.Width*0.45)
    $endX=[int]($bounds.Width*0.85)
    $startY=[int]($bounds.Height*0.45)
    $endY=[int]($bounds.Height*0.85)
    for($x=$startX;$x -lt $endX;$x+=25){
      for($y=$startY;$y -lt $endY;$y+=25){
        $c=$bitmap.GetPixel($x,$y)
        $samples++
        if($c.B -gt 120 -and $c.R -lt 60 -and $c.G -lt 140){ $blue++ }
      }
    }
    $bitmap.Dispose()
    $ratio=if($samples -gt 0){ $blue / $samples }else{ 0 }
    Log ('splash_blue_ratio='+$ratio)
    return ($ratio -gt 0.08)
  }catch{
    Log ('splash detection failed: '+$_.Exception.Message)
    return $false
  }
}
function WaitKvInteractive([int]$seconds){
  $deadline=(Get-Date).AddSeconds($seconds)
  do{
    if(-not (TestKvSplashVisible)){
      Start-Sleep -Milliseconds 500
      if(-not (TestKvSplashVisible)){
        Log 'KV splash/loader not visible; main window is interactable'
        return $true
      }
    }
    Start-Sleep -Milliseconds 500
  }while((Get-Date) -lt $deadline)
  return $false
}
function GetForegroundTitle(){
  $hwnd=[W]::GetForegroundWindow()
  $builder=New-Object System.Text.StringBuilder 512
  [void][W]::GetWindowText($hwnd,$builder,$builder.Capacity)
  return [pscustomobject]@{Hwnd=$hwnd;Title=$builder.ToString()}
}
function ForceKvStudioForeground([IntPtr]$hwnd){
  if($hwnd -eq [IntPtr]::Zero){ return $false }
  if([W]::IsIconic($hwnd)){ [W]::ShowWindow($hwnd,9)|Out-Null }
  $foreground=[W]::GetForegroundWindow()
  $targetPid=[uint32]0
  $foregroundPid=[uint32]0
  $targetThread=[W]::GetWindowThreadProcessId($hwnd,[ref]$targetPid)
  $foregroundThread=[W]::GetWindowThreadProcessId($foreground,[ref]$foregroundPid)
  $currentThread=[W]::GetCurrentThreadId()
  $attachedTarget=$false
  $attachedForeground=$false
  try{
    if($targetThread -ne $currentThread){
      $attachedTarget=[W]::AttachThreadInput($currentThread,$targetThread,$true)
    }
    if($foregroundThread -ne 0 -and $foregroundThread -ne $currentThread -and $foregroundThread -ne $targetThread){
      $attachedForeground=[W]::AttachThreadInput($currentThread,$foregroundThread,$true)
    }
    [W]::BringWindowToTop($hwnd)|Out-Null
    [W]::SetActiveWindow($hwnd)|Out-Null
    [W]::SetFocus($hwnd)|Out-Null
    [W]::SetForegroundWindow($hwnd)|Out-Null
  }finally{
    if($attachedForeground){ [W]::AttachThreadInput($currentThread,$foregroundThread,$false)|Out-Null }
    if($attachedTarget){ [W]::AttachThreadInput($currentThread,$targetThread,$false)|Out-Null }
  }
  Start-Sleep -Milliseconds 120
  $fg=GetForegroundTitle
  return ($fg.Hwnd -eq $hwnd -or $fg.Title -like 'KV STUDIO*')
}
function AssertKvStudioForeground([string]$action, [string]$projectNeedle=''){
  $fg=GetForegroundTitle
  Log ('foreground before '+$action+': hwnd='+$fg.Hwnd+' title='+$fg.Title)
  if($fg.Title -notlike 'KV STUDIO*'){
    throw ('Refusing '+$action+': foreground window is not KV STUDIO. Title='+$fg.Title)
  }
  if($projectNeedle -and $fg.Title -notlike ('*'+$projectNeedle+'*')){
    throw ('Refusing '+$action+': foreground KV STUDIO project does not match '+$projectNeedle+'. Title='+$fg.Title)
  }
}
function ClickPoint([int]$x, [int]$y, [string]$label){
  Invoke-KvGuardedMouseClick -TargetHwnd $script:KvGuardTargetHwnd -Step ('MNM import click '+$label) -X $x -Y $y -ExpectedTitleLike $script:KvGuardExpectedTitleLike -SleepMs 120
  Log ('clicked '+$label+' '+$x+','+$y)
}
function ClickAutomationElementCenter($element, [string]$label){
  if($label -notmatch '^(menu target|mnemonic-list read|open dialog Open button|MNM read choice button|post-insert confirmation button|post-import dialog button|program kind OK button|.* dialog button .*)'){
    throw ('Unsafe center click blocked: '+$label)
  }
  $rect=$element.Current.BoundingRectangle
  $cx=[int]($rect.Left + ($rect.Width / 2))
  $cy=[int]($rect.Top + ($rect.Height / 2))
  $oldHwnd=$script:KvGuardTargetHwnd
  $oldTitle=$script:KvGuardExpectedTitleLike
  $target=GetElementGuardHwnd $element
  if($target -ne [IntPtr]::Zero){ SetKvGuardTarget $target '*' }
  ClickPoint $cx $cy $label
  SetKvGuardTarget $oldHwnd $oldTitle
}
function DoubleClickAutomationElementCenter($element, [string]$label){
  throw ('Unsafe double-click blocked: '+$label)
}
function ClickRectCenter($rect, [string]$label){
  $cx=[int]($rect.Left + ($rect.Width / 2))
  $cy=[int]($rect.Top + ($rect.Height / 2))
  ClickPoint $cx $cy $label
}
function GetWindowClassName([IntPtr]$hwnd){
  $builder=New-Object System.Text.StringBuilder 256
  [void][W]::GetClassName($hwnd,$builder,$builder.Capacity)
  return $builder.ToString()
}
function GetWindowTextValue([IntPtr]$hwnd){
  $builder=New-Object System.Text.StringBuilder 512
  [void][W]::GetWindowText($hwnd,$builder,$builder.Capacity)
  return $builder.ToString()
}
function GetVisibleDialogWindows(){
  $script:visibleDialogWindows=@()
  $callback=[W+EnumWindowsProc]{
    param([IntPtr]$hwnd,[IntPtr]$lparam)
    try{
      if([W]::IsWindowVisible($hwnd)){
        $className=GetWindowClassName $hwnd
        if($className -eq '#32770'){
          $script:visibleDialogWindows += [pscustomobject]@{
            Hwnd=$hwnd
            Title=(GetWindowTextValue $hwnd)
            Class=$className
          }
        }
      }
    }catch{}
    return $true
  }
  [void][W]::EnumWindows($callback,[IntPtr]::Zero)
  return @($script:visibleDialogWindows)
}
function GetVisiblePopupMenuWindows(){
  $script:visiblePopupMenuWindows=@()
  $callback=[W+EnumWindowsProc]{
    param([IntPtr]$hwnd,[IntPtr]$lparam)
    try{
      if([W]::IsWindowVisible($hwnd)){
        $className=GetWindowClassName $hwnd
        if($className -eq '#32768'){
          $script:visiblePopupMenuWindows += [pscustomobject]@{
            Hwnd=$hwnd
            Title=(GetWindowTextValue $hwnd)
            Class=$className
          }
        }
      }
    }catch{}
    return $true
  }
  [void][W]::EnumWindows($callback,[IntPtr]::Zero)
  return @($script:visiblePopupMenuWindows)
}
function WaitForPopupMenuWindow([int]$milliseconds){
  $deadline=(Get-Date).AddMilliseconds($milliseconds)
  do{
    $menus=@(GetVisiblePopupMenuWindows)
    if($menus.Count -gt 0){
      Log ('visible popup menu found count='+$menus.Count)
      return $true
    }
    Start-Sleep -Milliseconds 50
  }while((Get-Date) -lt $deadline)
  Log ('visible popup menu not found within '+$milliseconds+'ms')
  return $false
}
function WaitForStandardOpenDialog([int]$milliseconds){
  $deadline=(Get-Date).AddMilliseconds($milliseconds)
  do{
    $dialog=GetStandardOpenDialogByWin32
    if($dialog){
      Log ('standard open dialog detected by Win32 hwnd='+$dialog.Hwnd+' title='+$dialog.Title)
      return $true
    }
    Start-Sleep -Milliseconds 50
  }while((Get-Date) -lt $deadline)
  return $false
}
function GetStandardOpenDialogByWin32(){
  foreach($dialog in @(GetVisibleDialogWindows)){
    if(TestOpenDialogByNativeHwnd ([int64]$dialog.Hwnd)){
      return $dialog
    }
  }
  return $null
}
function TestOpenDialogByNativeHwnd([int64]$nativeHwnd){
  if($nativeHwnd -eq 0){ return $false }
  try{
    $root=[System.Windows.Automation.AutomationElement]::RootElement
    $dialog=$root.FindFirst(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NativeWindowHandleProperty,[int]$nativeHwnd))
    )
    if(-not $dialog){ return $false }
    if($dialog.Current.ClassName -ne '#32770'){ return $false }
    $openButton=$dialog.FindFirst(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1')),
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
      ))
    )
    $fileNameEdit=$dialog.FindFirst(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1148'))
    )
    return ($null -ne $openButton -and $null -ne $fileNameEdit)
  }catch{
    return $false
  }
}
function SaveVisibleTopWindowSnapshot([string]$name){
  $rows=@()
  try{
    foreach($dialog in @(GetVisibleDialogWindows)){
      $children=@()
      try{
        $root=[System.Windows.Automation.AutomationElement]::RootElement
        $dialogElement=$root.FindFirst(
          [System.Windows.Automation.TreeScope]::Descendants,
          (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NativeWindowHandleProperty,[int]$dialog.Hwnd))
        )
        if($dialogElement){
          $desc=$dialogElement.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
          for($i=0;$i -lt $desc.Count -and $i -lt 120;$i++){
            $e=$desc.Item($i)
            $r=$e.Current.BoundingRectangle
            $children += [pscustomobject]@{
              Name=$e.Current.Name
              Class=$e.Current.ClassName
              Type=$e.Current.ControlType.ProgrammaticName
              AutomationId=$e.Current.AutomationId
              Rect=('{0},{1},{2},{3}' -f $r.Left,$r.Top,$r.Width,$r.Height)
            }
          }
        }
      }catch{
        $children += [pscustomobject]@{Name=('dialog child snapshot failed: '+$_.Exception.Message);Class='';Type='';AutomationId='';Rect=''}
      }
      $rows += [pscustomobject]@{Kind='Dialog';Hwnd=[string]$dialog.Hwnd;Title=$dialog.Title;Class=$dialog.Class;Children=$children}
    }
    foreach($menu in @(GetVisiblePopupMenuWindows)){
      $rows += [pscustomobject]@{Kind='PopupMenu';Hwnd=[string]$menu.Hwnd;Title=$menu.Title;Class=$menu.Class}
    }
    $fg=GetForegroundTitle
    $rows += [pscustomobject]@{Kind='Foreground';Hwnd=[string]$fg.Hwnd;Title=$fg.Title;Class=''}
    $rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $out $name) -Encoding UTF8
    Log ('saved top-window snapshot '+$name)
  }catch{
    Log ('top-window snapshot failed '+$name+': '+$_.Exception.Message)
  }
}
function WaitForVisibleDialogHwnd([int]$seconds, [bool]$logMiss=$true){
  $deadline=(Get-Date).AddSeconds($seconds)
  do{
    $dialogs=@(GetVisibleDialogWindows)
    if($dialogs.Count -gt 0){
      $dialog=$dialogs[0]
      Log ('visible #32770 dialog hwnd='+$dialog.Hwnd+' title='+$dialog.Title)
      return $dialog.Hwnd
    }
    Start-Sleep -Milliseconds 300
  }while((Get-Date) -lt $deadline)
  if($logMiss){ Log ('visible #32770 dialog not found within '+$seconds+'s') }
  return [IntPtr]::Zero
}
function DumpUi($name){
  try{
    $root=[System.Windows.Automation.AutomationElement]::RootElement
    $all=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
    $rows=@()
    for($i=0;$i -lt $all.Count;$i++){
      $e=$all.Item($i)
      $r=$e.Current.BoundingRectangle
      $rows += [pscustomobject]@{
        Index=$i
        Name=$e.Current.Name
        Class=$e.Current.ClassName
        Type=$e.Current.ControlType.ProgrammaticName
        AutomationId=$e.Current.AutomationId
        IsEnabled=$e.Current.IsEnabled
        Rect=('{0},{1},{2},{3}' -f $r.Left,$r.Top,$r.Width,$r.Height)
      }
    }
    $rows | Where-Object { $_.Name -or $_.Class -or $_.AutomationId } |
      Select-Object -First 900 |
      ConvertTo-Json -Depth 4 |
      Set-Content -LiteralPath (Join-Path $out $name) -Encoding UTF8
    Log "dump $name"
  }catch{
    Log ('dump err '+$name+' '+$_.Exception.Message)
  }
}
function FindKvsMainWindowElement(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $windows=$root.FindAll(
    [System.Windows.Automation.TreeScope]::Children,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window))
  )
  for($i=0;$i -lt $windows.Count;$i++){
    $window=$windows.Item($i)
    $name=$window.Current.Name
    $class=$window.Current.ClassName
    $rect=$window.Current.BoundingRectangle
    if($name -like 'KV STUDIO*' -and $class -like 'WindowsForms10.Window*' -and $rect.Width -gt 400 -and $rect.Height -gt 300){
      return $window
    }
  }
  return $null
}
function WaitKvsMainWindowReady([int]$seconds){
  $deadline=(Get-Date).AddSeconds($seconds)
  do{
    $process=Get-Process Kvs -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' } |
      Sort-Object StartTime -Descending |
      Select-Object -First 1
    if($process){
      $hwnd=[IntPtr]$process.MainWindowHandle
      for($try=1;$try -le 10;$try++){
        if([W]::IsIconic($hwnd)){
          [W]::ShowWindow($hwnd,9)|Out-Null
          Start-Sleep -Milliseconds 150
        }
        [void](ForceKvStudioForeground $hwnd)
        Start-Sleep -Milliseconds 150
        $fg=GetForegroundTitle
        if($fg.Title -like 'KV STUDIO*' -and -not [W]::IsIconic($hwnd)){
          Log ('KV STUDIO main window ready and foreground: '+$process.MainWindowTitle+' try='+$try)
          return $true
        }
      }
      Log ('KV STUDIO window found but not foreground yet: '+$process.MainWindowTitle)
    }
    Start-Sleep -Seconds 2
  }while((Get-Date) -lt $deadline)
  Log 'KV STUDIO main window was not ready before timeout'
  return $false
}
function OpenProjectModuleEditor([string]$moduleName){
  throw 'OpenProjectModuleEditor is disabled for MVP MNM import; do not touch project tree/editor before full MNM import.'
  if(-not $moduleName){ return $false }
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $tree=$root.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'ProjectTreeView'))
  )
  if(-not $tree){
    Log 'project tree not found before MNM import'
    return $false
  }
  $items=$tree.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::TreeItem))
  )
  for($i=0;$i -lt $items.Count;$i++){
    $item=$items.Item($i)
    $name=[string]$item.Current.Name
    if($name -eq $moduleName -or $name -like ($moduleName+' *') -or $name -like ('*'+$moduleName+'*')){
      try{
        $select=$item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $select.Select()
        Log ('selected project module '+$name)
      }catch{
        ClickAutomationElementCenter $item ('project module '+$name)
      }
      Start-Sleep -Milliseconds 250
      try{
        $invoke=$item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $invoke.Invoke()
        Log ('invoked project module '+$name)
      }catch{
        DoubleClickAutomationElementCenter $item ('project module '+$name)
      }
      try{
        Invoke-KvGuardedSendKeys -TargetHwnd $script:KvGuardTargetHwnd -Step ('open project module Enter '+$name) -Keys '{ENTER}' -ExpectedTitleLike $script:KvGuardExpectedTitleLike -Action 'Enter opens selected project module' -SleepMs 2000
        Log ('sent Enter to open project module '+$name)
      }catch{
        Log ('Enter open project module failed '+$name+': '+$_.Exception.Message)
      }
      Start-Sleep -Seconds 2
      return $true
    }
  }
  Log ('project module not found before MNM import: '+$moduleName)
  return $false
}
function FindProjectModuleTreeItem([string]$moduleName){
  if(-not $moduleName){ return $null }
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $tree=$root.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'ProjectTreeView'))
  )
  if(-not $tree){ return $null }
  $items=$tree.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::TreeItem))
  )
  for($i=0;$i -lt $items.Count;$i++){
    $item=$items.Item($i)
    $name=[string]$item.Current.Name
    if($name -eq $moduleName -or $name -match ('^' + [regex]::Escape($moduleName) + '\s+\[\d+\]$')){
      return $item
    }
  }
  return $null
}
function ConfirmDeleteDialogIfPresent(){
  $deadline=(Get-Date).AddSeconds(5)
  do{
    foreach($dialog in @(GetVisibleDialogs)){
      try{
        $buttons=$dialog.FindAll(
          [System.Windows.Automation.TreeScope]::Descendants,
          (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
        )
        for($i=0;$i -lt $buttons.Count;$i++){
          $button=$buttons.Item($i)
          $name=[string]$button.Current.Name
          if($name -match '^(是|はい|Yes|OK|确定)'){
            try{
              $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
            }catch{
              ClickAutomationElementCenter $button ('delete confirm '+$name)
            }
            Log ('confirmed delete dialog by '+$name)
            Start-Sleep -Seconds 2
            return $true
          }
        }
      }catch{}
    }
    Start-Sleep -Milliseconds 200
  }while((Get-Date) -lt $deadline)
  return $false
}
function RemoveProjectModuleIfPresent([string]$moduleName){
  if(-not $moduleName){ return $false }
  $item=FindProjectModuleTreeItem $moduleName
  if(-not $item){
    Log ('project module not present before delete: '+$moduleName)
    return $true
  }
  $name=[string]$item.Current.Name
  try{
    $select=$item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    $select.Select()
    Log ('selected project module for delete '+$name)
  }catch{
    ClickAutomationElementCenter $item ('project module delete select '+$name)
    Log ('clicked project module for delete '+$name)
  }
  Start-Sleep -Milliseconds 250
  try{ $item.SetFocus() }catch{}
  Invoke-KvGuardedSendKeys -TargetHwnd $script:KvGuardTargetHwnd -Step ('delete existing module '+$name) -Keys '{DELETE}' -ExpectedTitleLike $script:KvGuardExpectedTitleLike -Action 'Delete selected existing project module before MNM repair import' -SleepMs 700
  if(-not (ConfirmDeleteDialogIfPresent)){
    Log ('delete confirmation dialog not found for '+$name)
  }
  Start-Sleep -Seconds 2
  $remaining=FindProjectModuleTreeItem $moduleName
  if($remaining){
    Log ('project module remained after delete attempt: '+[string]$remaining.Current.Name)
    return $false
  }
  Log ('deleted existing project module before MNM import: '+$name)
  return $true
}
function RenameProjectModuleIfPresent([string]$moduleName){
  throw 'RenameProjectModuleIfPresent is disabled for MVP MNM import.'
}
function InvokeProgramNewMenu(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $all=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  $programMenu=$null
  for($i=0;$i -lt $all.Count;$i++){
    $element=$all.Item($i)
    if($element.Current.ControlType.ProgrammaticName -eq 'ControlType.MenuItem' -and $element.Current.Name -eq '程序(M)'){
      $programMenu=$element
      break
    }
  }
  if($programMenu){
    try{
      $programMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
      Log 'expanded program menu by UIA'
    }catch{
      try{
        $programMenu.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Log 'invoked program menu by UIA'
      }catch{
        Invoke-KvGuardedSendKeys -TargetHwnd $script:KvGuardTargetHwnd -Step 'open program menu Alt+M fallback' -Keys '%m' -ExpectedTitleLike $script:KvGuardExpectedTitleLike -Action 'Alt+M opens program menu fallback' -SleepMs 700
        Log 'opened program menu by Alt+M fallback'
      }
    }
  }else{
    Invoke-KvGuardedSendKeys -TargetHwnd $script:KvGuardTargetHwnd -Step 'open program menu Alt+M fallback no UIA' -Keys '%m' -ExpectedTitleLike $script:KvGuardExpectedTitleLike -Action 'Alt+M opens program menu fallback' -SleepMs 700
    Log 'opened program menu by Alt+M fallback; UIA menu not found'
  }
  Start-Sleep -Milliseconds 700
  $all=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  for($i=0;$i -lt $all.Count;$i++){
    $element=$all.Item($i)
    $rect=$element.Current.BoundingRectangle
    if($element.Current.ControlType.ProgrammaticName -eq 'ControlType.MenuItem' -and
       $element.Current.Name -like '新建*' -and
       $rect.Left -ge 200 -and $rect.Left -le 700 -and $rect.Top -ge 50 -and $rect.Top -le 200){
      try{
        $element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
      }catch{
        ClickAutomationElementCenter $element 'program new menu'
      }
      Log 'invoked program new menu'
      Start-Sleep -Seconds 1
      return $true
    }
  }
  return $false
}
function CreatePlaceholderModule(){
  throw 'CreatePlaceholderModule is disabled for MVP MNM import.'
}
function FindMnemonicReadChoiceButton([bool]$PreferOverwrite){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $buttons=$root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
  )
  $overwritePrefix=(-join ([char[]](0x8986,0x76D6)))
  $insertPrefix=(-join ([char[]](0x63D2,0x5165)))
  $targetPrefixes = if($PreferOverwrite){ @($overwritePrefix,$insertPrefix) } else { @($insertPrefix,$overwritePrefix) }
  foreach($targetPrefix in $targetPrefixes){
    for($i=0;$i -lt $buttons.Count;$i++){
      $button=$buttons.Item($i)
      $name=[string]$button.Current.Name
      $automationId=[string]$button.Current.AutomationId
      $rect=GetElementRectObject $button
      if(-not $button.Current.IsEnabled){ continue }
      if($name -notlike ($targetPrefix+'*')){ continue }
      if($rect.Width -lt 40 -or $rect.Height -lt 18){ continue }
      if($automationId -like '_button*'){ continue }
      if($rect.Left -lt 250 -or $rect.Left -gt 2200){ continue }
      if($rect.Top -lt 150 -or $rect.Top -gt 1200){ continue }
      Log ('found mnemonic read choice button name='+$name+' automationId='+$automationId+' rect='+$rect.Left+','+$rect.Top+','+$rect.Width+','+$rect.Height)
      return $button
    }
  }
  return $null
}
function FindLadderInlineEditBar(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $buttons=$root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
  )
  $overwritePrefix=(-join ([char[]](0x8986,0x76D6)))
  $insertPrefix=(-join ([char[]](0x63D2,0x5165)))
  $cancelPrefix=(-join ([char[]](0x53D6,0x6D88)))
  $found=@{}
  for($i=0;$i -lt $buttons.Count;$i++){
    $button=$buttons.Item($i)
    $name=[string]$button.Current.Name
    $rect=GetElementRectObject $button
    if(-not $button.Current.IsEnabled){ continue }
    if($rect.Top -lt 180 -or $rect.Top -gt 520){ continue }
    if($rect.Left -lt 500 -or $rect.Left -gt 2600){ continue }
    if($name -like ($overwritePrefix+'*')){ $found.Overwrite=$button; continue }
    if($name -like ($insertPrefix+'*')){ $found.Insert=$button; continue }
    if($name -like ($cancelPrefix+'*')){ $found.Cancel=$button; continue }
  }
  if($found.Overwrite -and $found.Insert -and $found.Cancel){
    return [pscustomobject]@{Overwrite=$found.Overwrite;Insert=$found.Insert;Cancel=$found.Cancel}
  }
  return $null
}
function CancelLadderInlineEditBarIfPresent([string]$stage){
  $bar=FindLadderInlineEditBar
  if(-not $bar){ return $false }
  AssertKvStudioForeground ("cancel ladder inline edit bar "+$stage)
  try{
    $invoke=$bar.Cancel.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $invoke.Invoke()
    Log ('cancelled ladder inline edit bar by UIA InvokePattern on Cancel stage='+$stage)
  }catch{
    throw ('Ladder inline edit bar appeared at '+$stage+' but UIA InvokePattern on Cancel failed: '+$_.Exception.Message)
  }
  Start-Sleep -Seconds 1
  if(FindLadderInlineEditBar){
    throw ('Ladder inline edit bar appeared at '+$stage+' and remained visible after UIA Cancel. This is not an MNM import confirmation.')
  }
  throw ('Ladder inline edit bar appeared at '+$stage+'; cancelled by UIA InvokePattern on Cancel. This is not an MNM import confirmation.')
}
function ClickKvsInsertButton([bool]$PreferOverwrite){
  CancelLadderInlineEditBarIfPresent 'before_mnm_choice_click' | Out-Null
  $button=FindMnemonicReadChoiceButton -PreferOverwrite $PreferOverwrite
  if(-not $button){
    Log 'MNM read choice button not found after MNM file open'
    return $false
  }
  try{
    $invoke=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $invoke.Invoke()
    Log ('invoked MNM read choice button '+$button.Current.Name)
  }catch{
    ClickAutomationElementCenter $button ('MNM read choice button '+$button.Current.Name)
  }
  Start-Sleep -Seconds 2
  return $true
}
function TestKvsMnemonicImportPanelOpen(){
  CancelLadderInlineEditBarIfPresent 'mnm_panel_probe' | Out-Null
  return ($null -ne (FindMnemonicReadChoiceButton -PreferOverwrite $true))
}
function CompleteMnemonicReadInsertFlow([bool]$PreferOverwrite){
  if(-not (TestKvsMnemonicImportPanelOpen)){
    Log 'MNM read choice panel not present after file open; import cannot be considered committed'
    return $false
  }
  if(-not (ClickKvsInsertButton -PreferOverwrite $PreferOverwrite)){
    return $false
  }
  Start-Sleep -Seconds 3
  if(-not (TestKvsMnemonicImportPanelOpen)){
      Log 'MNM read choice panel closed after commit'
    return $true
  }
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $buttons=$root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
  )
  $okCn=(-join ([char[]](0x786E,0x5B9A)))
  $yesCn=(-join ([char[]](0x662F)))
  $yesJp=(-join ([char[]](0x306F,0x3044)))
  $names=@('OK',$okCn,$yesCn,$yesJp)
  for($i=0;$i -lt $buttons.Count;$i++){
    $button=$buttons.Item($i)
    $name=[string]$button.Current.Name
    if(-not $button.Current.IsEnabled){ continue }
    if($names -notcontains $name){ continue }
    try{
      $invoke=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
      $invoke.Invoke()
      Log ('invoked post-insert confirmation button '+$name)
    }catch{
      ClickAutomationElementCenter $button ('post-insert confirmation button '+$name)
    }
    Start-Sleep -Seconds 3
    if(-not (TestKvsMnemonicImportPanelOpen)){
      Log 'MNM read choice panel closed after confirmation'
      return $true
    }
  }
  Log 'MNM read choice panel still open after commit; import not committed'
  return $false
}
function GetElementPatternNames($element){
  $names=@()
  try{
    foreach($pattern in $element.GetSupportedPatterns()){
      $names += $pattern.ProgrammaticName
    }
  }catch{}
  return $names
}
function GetElementRectObject($element){
  $rect=$element.Current.BoundingRectangle
  return [pscustomobject]@{
    Left=[double]$rect.Left
    Top=[double]$rect.Top
    Width=[double]$rect.Width
    Height=[double]$rect.Height
    Right=[double]($rect.Left + $rect.Width)
    Bottom=[double]($rect.Top + $rect.Height)
  }
}
function GetVisibleMenuItems(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $items=$root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::MenuItem))
  )
  $visible=@()
  for($i=0;$i -lt $items.Count;$i++){
    $item=$items.Item($i)
    $rect=GetElementRectObject $item
    if($item.Current.IsEnabled -and $rect.Width -gt 10 -and $rect.Height -gt 8){
      $visible += $item
    }
  }
  return $visible
}
function TestHasPatternName($element, [string]$patternText){
  foreach($name in (GetElementPatternNames $element)){
    if($name -like ('*'+$patternText+'*')){ return $true }
  }
  return $false
}
function OpenFileMenuByUia(){
  Invoke-KvGuardedSendKeys -TargetHwnd $script:KvGuardTargetHwnd -Step 'close transient menu before UIA file menu' -Keys '{ESC}' -ExpectedTitleLike $script:KvGuardExpectedTitleLike -Action 'Esc closes transient menu before UIA file-menu route' -SleepMs 200
  Start-Sleep -Milliseconds 200
  $items=@(GetVisibleMenuItems)
  $topMenuItems=@()
  foreach($item in $items){
    $rect=GetElementRectObject $item
    if($rect.Top -ge 20 -and $rect.Top -le 90 -and $rect.Width -gt 30 -and $rect.Height -gt 15){
      $topMenuItems += [pscustomobject]@{ Item=$item; Left=$rect.Left; Top=$rect.Top; Name=$item.Current.Name }
    }
  }
  if($topMenuItems.Count -eq 0){
    Log 'top menu items not found for file menu'
    return $false
  }
  $fileItem=($topMenuItems | Sort-Object Left,Top | Select-Object -First 1).Item
  Log ('opening file menu by UIA name='+$fileItem.Current.Name)
  ExpandOrClickMenuItem $fileItem 'file menu' | Out-Null
  Start-Sleep -Milliseconds 600
  return $true
}
function FindMnemonicListMenuItem(){
  $items=@(GetVisibleMenuItems)
  $popupItems=@()
  foreach($item in $items){
    $rect=GetElementRectObject $item
    if($rect.Top -gt 40 -and $rect.Width -gt 80){
      $popupItems += $item
    }
  }
  if($popupItems.Count -eq 0){ return $null }
  $leftEdge=($popupItems | ForEach-Object { (GetElementRectObject $_).Left } | Measure-Object -Minimum).Minimum
  $parentCandidates=@()
  foreach($item in $popupItems){
    $rect=GetElementRectObject $item
    $access=([string]$item.Current.AccessKey).Trim()
    if([Math]::Abs($rect.Left - $leftEdge) -le 8 -and $access -match '^(?i)r$'){
      $parentCandidates += $item
    }
  }
  foreach($item in $parentCandidates){
    if(TestHasPatternName $item 'ExpandCollapse'){ return $item }
  }
  if($parentCandidates.Count -gt 0){ return $parentCandidates[0] }
  return $null
}
function FindMnemonicReadMenuItem($parent){
  if(-not $parent){ return $null }
  $parentRect=GetElementRectObject $parent
  $items=@(GetVisibleMenuItems)
  $childCandidates=@()
  foreach($item in $items){
    $rect=GetElementRectObject $item
    $access=([string]$item.Current.AccessKey).Trim()
    if($access -notmatch '^(?i)r$'){ continue }
    if($rect.Left -le ($parentRect.Right - 12)){ continue }
    if($rect.Top -lt ($parentRect.Top - 8)){ continue }
    if($rect.Top -gt ($parentRect.Bottom + 80)){ continue }
    if($item.Current.Name -eq $parent.Current.Name -and [Math]::Abs($rect.Left - $parentRect.Left) -lt 8){ continue }
    $childCandidates += $item
  }
  foreach($item in $childCandidates){
    if(-not (TestHasPatternName $item 'ExpandCollapse')){ return $item }
  }
  if($childCandidates.Count -gt 0){ return $childCandidates[0] }
  return $null
}
function ExpandOrClickMenuItem($item, [string]$label){
  if(-not $item){ return $false }
  $rect=GetElementRectObject $item
  Log ('menu target '+$label+' name='+$item.Current.Name+' access='+$item.Current.AccessKey+' rect='+$rect.Left+','+$rect.Top+','+$rect.Width+','+$rect.Height+' patterns='+((GetElementPatternNames $item) -join ','))
  try{
    $expandPattern=$item.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    $expandPattern.Expand()
    Log ('expanded '+$label+' by ExpandCollapsePattern')
    return $true
  }catch{
    Log ('ExpandCollapse unavailable for '+$label+': '+$_.Exception.Message)
  }
  try{
    $invokePattern=$item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $invokePattern.Invoke()
    Log ('invoked '+$label+' by InvokePattern')
    return $true
  }catch{
    Log ('Invoke unavailable for '+$label+': '+$_.Exception.Message)
  }
  ClickAutomationElementCenter $item $label
  return $true
}
function InvokeOrClickMenuItem($item, [string]$label){
  if(-not $item){ return $false }
  $rect=GetElementRectObject $item
  Log ('menu target '+$label+' name='+$item.Current.Name+' access='+$item.Current.AccessKey+' rect='+$rect.Left+','+$rect.Top+','+$rect.Width+','+$rect.Height+' patterns='+((GetElementPatternNames $item) -join ','))
  try{
    $invokePattern=$item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $invokePattern.Invoke()
    Log ('invoked '+$label+' by InvokePattern')
    return $true
  }catch{
    Log ('Invoke unavailable for '+$label+': '+$_.Exception.Message)
  }
  if($label -eq 'mnemonic-list read'){
    throw 'Mnemonic-list read menu item did not support InvokePattern; refusing coordinate click because prior coordinate click opened DirectInput inline editor.'
  }
  ClickAutomationElementCenter $item $label
  return $true
}
function InvokeMnemonicImportMenuByUia(){
  AssertKvStudioForeground 'UIA mnemonic import menu route'
  if(-not (OpenFileMenuByUia)){
    SaveVisibleTopWindowSnapshot 'top_windows_uia_file_menu_not_found.json'
    Log 'UIA mnemonic import route failed: file menu was not opened'
    return $false
  }
  Start-Sleep -Milliseconds 500
  $mnemonicList=FindMnemonicListMenuItem
  if(-not $mnemonicList){
    SaveVisibleTopWindowSnapshot 'top_windows_uia_mnemonic_list_not_found.json'
    Log 'UIA mnemonic import route failed: mnemonic list parent item not found'
    return $false
  }
  if(-not (ExpandOrClickMenuItem $mnemonicList 'menu target')){
    SaveVisibleTopWindowSnapshot 'top_windows_uia_mnemonic_list_not_expanded.json'
    Log 'UIA mnemonic import route failed: mnemonic list parent item was not expanded'
    return $false
  }
  Start-Sleep -Milliseconds 500
  $readItem=FindMnemonicReadMenuItem $mnemonicList
  if(-not $readItem){
    SaveVisibleTopWindowSnapshot 'top_windows_uia_mnemonic_read_not_found.json'
    Log 'UIA mnemonic import route failed: mnemonic read item not found'
    return $false
  }
  if(-not (InvokeOrClickMenuItem $readItem 'mnemonic-list read')){
    SaveVisibleTopWindowSnapshot 'top_windows_uia_mnemonic_read_not_invoked.json'
    Log 'UIA mnemonic import route failed: mnemonic read item was not invoked'
    return $false
  }
  if(-not (WaitForStandardOpenDialog 2500)){
    SaveVisibleTopWindowSnapshot 'top_windows_uia_mnemonic_read_no_open_dialog.json'
    Log 'UIA mnemonic import route failed: standard open dialog was not detected after menu invoke'
    return $false
  }
  Log 'ROUTE_UIA_MNM_READ_FILE_DIALOG invoked mnemonic list read/import through the same File menu command'
  return $true
}
function InvokeMnemonicImportMenu(){
  AssertKvStudioForeground 'Alt+F,R,R mnemonic import route'
  SetCapsLockState $true
  Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $script:KvGuardTargetHwnd -Step 'MNM import Alt+F,R,R' -Keys '%frr' -ExpectedTitleLike $script:KvGuardExpectedTitleLike -SuccessTitleLike @('打开','KV STUDIO*') -Action 'Alt+F,R,R opens MNM read dialog' -SleepMs 300
  Log 'sent Alt+F,R,R by shared UI guard'
  if(-not (WaitForStandardOpenDialog 3000)){
    SaveVisibleTopWindowSnapshot 'top_windows_after_sendkeys_alt_f_r_r_no_open_dialog.json'
    throw 'Alt+F,R,R via SendKeys did not expose a verified standard MNM file-open dialog; refusing inline editor path'
  }
  Log 'ROUTE_ALTFRR_MNM_READ_FILE_DIALOG invoked mnemonic list read/import through SendKeys Alt+F,R,R'
}
function TestStandardOpenDialogPresent(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $windows=$root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty,'#32770'))
  )
  for($i=0;$i -lt $windows.Count;$i++){
    $dialog=$windows.Item($i)
    $openButton=$dialog.FindFirst(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1')),
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
      ))
    )
    $fileNameEdit=$dialog.FindFirst(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1148'))
    )
    if($openButton -and $fileNameEdit){ return $true }
  }
  return $false
}
function NewInlineMnemonicBodyFile([string]$path){
  # MNM import is a whole-file workflow. Keep DEVICE/MODULE/AREA_ST/ENDH intact.
  if($path){ Log ('using complete MNM file for mnemonic read: '+$path) }
  return $path
}
function AssertMnmChineseEncoding([string]$path){
  if(-not $path){ return }
  if(-not (Test-Path -LiteralPath $path)){ throw "MNM file not found for encoding validation: $path" }
  $bytes=[IO.File]::ReadAllBytes($path)
  $ansi=[Text.Encoding]::Default
  $decodeName='system ANSI code page '+$ansi.CodePage
  $decodedText=$ansi.GetString($bytes)
  if($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE){
    $decodeName='UTF-16LE BOM'
    $decodedText=[Text.Encoding]::Unicode.GetString($bytes)
    if($decodedText.Length -gt 0 -and [int][char]$decodedText[0] -eq 0xFEFF){
      $decodedText=$decodedText.Substring(1)
    }
  }elseif($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF){
    throw 'MNM encoding validation failed: UTF-8 BOM is not accepted for this KV STUDIO MNM import workflow.'
  }
  $required=@()
  $baseName=[IO.Path]::GetFileNameWithoutExtension($path)
  if($baseName -like 'TrafficLight*'){
    $required=@(
    [string]::Concat([char[]]@(0x542F,0x52A8)),
    [string]::Concat([char[]]@(0x7EA2,0x004C,0x0045,0x0044,0x706F)),
    [string]::Concat([char[]]@(0x9EC4,0x004C,0x0045,0x0044,0x706F)),
    [string]::Concat([char[]]@(0x7EFF,0x004C,0x0045,0x0044,0x706F))
    )
  }
  $headerDevice = $null
  $headerModuleType = $null
  if($decodedText -match '^\uFEFF?DEVICE:(\d+)'){ $headerDevice = [int]$matches[1] }
  if($decodedText -match '(?m)^;MODULE_TYPE:(\d+)\s*$'){ $headerModuleType = [int]$matches[1] }
  if($null -eq $headerDevice){
    throw 'MNM device header validation failed: missing DEVICE:<n>.'
  }
  if($null -eq $headerModuleType){
    throw 'MNM module type validation failed: missing ;MODULE_TYPE:<n>.'
  }
  $deviceOk = (($headerModuleType -eq 2 -and $headerDevice -eq 59) -or ($headerModuleType -eq 0 -and ($headerDevice -eq 63 -or $headerDevice -eq 59)))
  if(-not $deviceOk){
    throw ('MNM device header validation failed: MODULE_TYPE='+$headerModuleType+' allows DEVICE:'+(if($headerModuleType -eq 2){'59'}elseif($headerModuleType -eq 0){'63 or 59'}else{'unsupported'})+', actual DEVICE:'+$headerDevice+'.')
  }
  $missing=@()
  foreach($needle in $required){
    if(-not $decodedText.Contains($needle)){ $missing += $needle }
  }
  if($missing.Count -gt 0){
    throw ('MNM encoding validation failed. Missing after '+$decodeName+' decode: '+($missing -join ', '))
  }
  Log ('MNM encoding validation passed by '+$decodeName+': '+$path)
}
function SetInlineMnemonicReadFile([string]$path){
  Log 'inline AutomationId=1265 path entry is disabled: it aliases the ladder inline edit bar and can create editor input.'
  return $false
}
function SetOpenDialogFileByVerifiedDialogHandle([string]$path){
  $path=[IO.Path]::GetFullPath($path)
  $deadline=(Get-Date).AddSeconds(20)
  do{
    $nativeDialog=GetStandardOpenDialogByWin32
    if(-not $nativeDialog){
      Start-Sleep -Milliseconds 200
      continue
    }
    try{
      $root=[System.Windows.Automation.AutomationElement]::RootElement
      $dialog=$root.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NativeWindowHandleProperty,[int]$nativeDialog.Hwnd))
      )
      if(-not $dialog){
        Log ('verified open dialog hwnd not found in UIA tree hwnd='+$nativeDialog.Hwnd)
        Start-Sleep -Milliseconds 200
        continue
      }
      $openButton=$dialog.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.AndCondition(
          (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1')),
          (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
        ))
      )
      $fileNameEdit=$dialog.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1148'))
      )
      if(-not $openButton -or -not $fileNameEdit){
        Log ('verified open dialog missing filename edit or open button hwnd='+$nativeDialog.Hwnd)
        Start-Sleep -Milliseconds 200
        continue
      }
      $valuePattern=$fileNameEdit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
      $valuePattern.SetValue($path)
      Log ('set verified open dialog filename by ValuePattern hwnd='+$nativeDialog.Hwnd)
      Start-Sleep -Milliseconds 200
      $invokePattern=$openButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
      $invokePattern.Invoke()
      Log ('invoked verified open dialog Open button by InvokePattern hwnd='+$nativeDialog.Hwnd)
      $closedDeadline=(Get-Date).AddSeconds(4)
      do{
        Start-Sleep -Milliseconds 100
        if(-not (GetStandardOpenDialogByWin32)){
          Log 'verified standard open dialog closed after ValuePattern/Open invoke'
          return $true
        }
      }while((Get-Date) -lt $closedDeadline)
      SaveVisibleTopWindowSnapshot 'top_windows_open_dialog_not_closed_after_valuepattern_open.json'
      throw 'Open dialog did not close after ValuePattern/Open invoke; refusing to assume MNM file was accepted'
    }catch{
      Log ('verified open dialog ValuePattern path failed: '+$_.Exception.Message)
      Start-Sleep -Milliseconds 300
    }
  }while((Get-Date) -lt $deadline)
  Log 'verified standard open dialog handle path did not complete'
  return $false
}
function SetOpenDialogFile([string]$path){
  if(SetInlineMnemonicReadFile $path){
    return $true
  }
  if(SetOpenDialogFileByVerifiedDialogHandle $path){
    return $true
  }
  if(SetOpenDialogFileByUia $path){
    return $true
  }
  Log 'refusing generic #32770/keyboard filename fallback: no verified open-file dialog was found'
  return $false

  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $dialogs=$null
  $deadline=(Get-Date).AddSeconds(20)
  do{
    try{
      $windows=$root.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window))
      )
      $dialogList=@()
      for($w=0;$w -lt $windows.Count;$w++){
        $window=$windows.Item($w)
        if($window.Current.ClassName -eq '#32770'){
          $dialogList += $window
        }
      }
      if($dialogList.Count -gt 0){
        $dialogs=$dialogList
        break
      }
    }catch{
      Log ('open dialog child-window scan failed: '+$_.Exception.Message)
    }
    Start-Sleep -Milliseconds 500
  }while((Get-Date) -lt $deadline)
  if(-not $dialogs){
    Log 'open dialog not found by UIA child-window scan'
    return $false
  }
  for($i=0;$i -lt $dialogs.Count;$i++){
    $dialog=$dialogs.Item($i)
    try{
      $openButton=$dialog.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.AndCondition(
          (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1')),
          (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
        ))
      )
      $edits=$dialog.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Edit))
      )
    }catch{
      Log ('open dialog descendant scan failed: '+$_.Exception.Message)
      continue
    }
    if($edits.Count -eq 0){ continue }
    $edit=$edits.Item($edits.Count - 1)
    $setByValuePattern=$false
    try{
      $valuePattern=$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
      $valuePattern.SetValue($path)
      $setByValuePattern=$true
      Log 'set open dialog filename by ValuePattern'
    }catch{
      throw ('Open dialog filename edit did not support ValuePattern; refusing clipboard fallback: '+$_.Exception.Message)
    }
    Start-Sleep -Milliseconds 300
    if($openButton){
      try{
        $invokePattern=$openButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $invokePattern.Invoke()
        Log 'invoked open dialog Open button by InvokePattern'
      }catch{
        ClickAutomationElementCenter $openButton 'open dialog Open button'
      }
    }else{
      throw 'Open dialog Open button not found; refusing Enter fallback'
    }
    return $true
  }
  Log 'open dialog found but filename edit was not accessible by UIA'
  return $false
}
function SetOpenDialogFileByUia([string]$path){
  $path=[IO.Path]::GetFullPath($path)
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $deadline=(Get-Date).AddSeconds(20)
  do{
    try{
      $windows=$root.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window))
      )
      $foreground=GetForegroundTitle
      $foregroundNative=0
      try{ $foregroundNative=[int64]$foreground.Hwnd }catch{}
      for($w=0;$w -lt $windows.Count;$w++){
        $dialog=$windows.Item($w)
        if($dialog.Current.ClassName -ne '#32770'){ continue }
        if($foregroundNative -ne 0 -and [int64]$dialog.Current.NativeWindowHandle -ne $foregroundNative){ continue }
        $dialogName=[string]$dialog.Current.Name
        $openButton=$dialog.FindFirst(
          [System.Windows.Automation.TreeScope]::Descendants,
          (New-Object System.Windows.Automation.AndCondition(
            (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1')),
            (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
          ))
        )
        $edits=$dialog.FindAll(
          [System.Windows.Automation.TreeScope]::Descendants,
          (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Edit))
        )
        if($edits.Count -eq 0 -or -not $openButton){ continue }
        $edit=$null
        for($i=0;$i -lt $edits.Count;$i++){
          $candidate=$edits.Item($i)
          if($candidate.Current.AutomationId -eq '1148'){
            $edit=$candidate
            break
          }
        }
        if(-not $edit){ $edit=$edits.Item($edits.Count - 1) }
        try{
          [W]::SetForegroundWindow([IntPtr]$dialog.Current.NativeWindowHandle) | Out-Null
          Start-Sleep -Milliseconds 150
        }catch{}
        $fg=GetForegroundTitle
        if([int64]$fg.Hwnd -ne [int64]$dialog.Current.NativeWindowHandle){
          throw ('Open dialog is not foreground before filename keyboard submission. Foreground='+$fg.Title)
        }
        try{
          $dialogHwnd=[IntPtr]$dialog.Current.NativeWindowHandle
          Invoke-KvGuardedSendKeys -TargetHwnd $dialogHwnd -Step 'open dialog filename Alt+N' -Keys '%n' -ExpectedTitleLike '*' -Action 'Alt+N focuses filename field' -SleepMs 150
          Invoke-KvGuardedSendKeys -TargetHwnd $dialogHwnd -Step 'open dialog filename Ctrl+A' -Keys '^a' -ExpectedTitleLike '*' -Action 'Ctrl+A selects filename field text' -SleepMs 80
          Invoke-KvGuardedClipboardPaste -TargetHwnd $dialogHwnd -Step 'open dialog filename Ctrl+V' -Text $path -ExpectedTitleLike '*' -SleepMs 150
          Log 'set open dialog filename by foreground Alt+N clipboard path'
          Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $dialogHwnd -Step 'open dialog submit Enter' -Keys '{ENTER}' -ExpectedTitleLike '*' -SuccessTitleLike @('选择程序种类','KV STUDIO*') -Action 'Enter submits verified open dialog' -SleepMs 500
          Log 'submitted open dialog by foreground Enter key'
        }catch{
          throw ('Open dialog foreground filename keyboard submission failed: '+$_.Exception.Message)
        }
        $closedDeadline=(Get-Date).AddSeconds(3)
        do{
          Start-Sleep -Milliseconds 100
          if(-not (GetStandardOpenDialogByWin32)){
            Log 'verified standard open dialog closed after foreground Enter submission'
            return $true
          }
        }while((Get-Date) -lt $closedDeadline)
        SaveVisibleTopWindowSnapshot 'top_windows_open_dialog_not_closed_after_open.json'
        throw 'Open dialog did not close after foreground Enter submission; refusing to assume MNM file was accepted'
        return $true
      }
    }catch{
      Log ('UIA open dialog filename path failed: '+$_.Exception.Message)
    }
    Start-Sleep -Milliseconds 300
  }while((Get-Date) -lt $deadline)
  Log 'open dialog not found by UIA-first path'
  return $false
}
function GetVisibleDialogs(){
  $dialogs=@()
  $seen=@{}
  $callback=[W+EnumWindowsProc]{
    param([IntPtr]$hwnd,[IntPtr]$lparam)
    try{
      if(-not [W]::IsWindowVisible($hwnd)){ return $true }
      $classBuilder=New-Object System.Text.StringBuilder 256
      [void][W]::GetClassName($hwnd,$classBuilder,$classBuilder.Capacity)
      if($classBuilder.ToString() -ne '#32770'){ return $true }
      $key=[string]$hwnd
      if($seen.ContainsKey($key)){ return $true }
      $seen[$key]=$true
      $element=[System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
      if($element){
        $rect=$element.Current.BoundingRectangle
        if($rect.Width -gt 80 -and $rect.Height -gt 40){
          $script:kvVisibleDialogs += $element
        }
      }
    }catch{}
    return $true
  }
  $script:kvVisibleDialogs=@()
  [void][W]::EnumWindows($callback,[IntPtr]::Zero)
  foreach($dialog in @($script:kvVisibleDialogs)){
    if($dialog){
      $dialogs += $dialog
    }
  }
  return $dialogs
}
function GetElementTextLines($element){
  $lines=@()
  try{
    $name=([string]$element.Current.Name).Trim()
    if($name){ $lines += $name }
  }catch{}
  try{
    $valuePattern=$element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $value=([string]$valuePattern.Current.Value).Trim()
    if($value){ $lines += $value }
  }catch{}
  try{
    $children=$element.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
    for($i=0;$i -lt $children.Count;$i++){
      $child=$children.Item($i)
      try{
        $childName=([string]$child.Current.Name).Trim()
        if($childName){ $lines += $childName }
      }catch{}
      try{
        $childValuePattern=$child.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $childValue=([string]$childValuePattern.Current.Value).Trim()
        if($childValue){ $lines += $childValue }
      }catch{}
    }
  }catch{}
  return @($lines | Where-Object { $_ } | Select-Object -Unique)
}
function SaveVisibleDialogSnapshot([string]$stage){
  $rows=@()
  foreach($dialog in @(GetVisibleDialogs)){
    try{
      if($dialog.Current.ClassName -ne '#32770'){ continue }
      $rect=$dialog.Current.BoundingRectangle
      $textLines=GetElementTextLines $dialog
      $rows += [pscustomobject]@{
        Stage=$stage
        Name=$dialog.Current.Name
        Class=$dialog.Current.ClassName
        NativeWindowHandle=$dialog.Current.NativeWindowHandle
        Rect=('{0},{1},{2},{3}' -f $rect.Left,$rect.Top,$rect.Width,$rect.Height)
        Text=$textLines
        TextJoined=($textLines -join "`n")
      }
    }catch{}
  }
  $safeStage=($stage -replace '[^A-Za-z0-9_.-]','_')
  $rows | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out ("visible_dialogs_$safeStage.json")) -Encoding UTF8
  Log ("saved visible dialog snapshot stage=$stage count="+(@($rows).Count))
  return @($rows)
}
function TestMnmReadFailureText([string]$text){
  if(-not $text){ return $false }
  $mnemonicReadFailed = [string]::Concat([char[]]@(0x8BFB,0x53D6,0x52A9,0x8BB0,0x7B26,0x5217,0x8868,0x5931,0x8D25))
  $mnemonic = [string]::Concat([char[]]@(0x52A9,0x8BB0,0x7B26))
  $failed = [string]::Concat([char[]]@(0x5931,0x8D25))
  $incorrect = [string]::Concat([char[]]@(0x4E0D,0x6B63,0x786E))
  $machineMismatch = [string]::Concat([char[]]@(0x673A,0x578B,0x4E0D,0x540C))
  $maxRows = [string]::Concat([char[]]@(0x6700,0x5927,0x884C,0x6570))
  $programName = [string]::Concat([char[]]@(0x7A0B,0x5E8F,0x540D))
  $structure = [string]::Concat([char[]]@(0x7ED3,0x6784,0x4F53))
  $duplicate = [string]::Concat([char[]]@(0x91CD,0x590D))
  if($text.Contains($mnemonicReadFailed)){ return $true }
  if($text.Contains($mnemonic) -and $text.Contains($failed)){ return $true }
  if($text.Contains($incorrect) -and $text.Contains($mnemonic)){ return $true }
  if($text.Contains('PLC') -and $text.Contains($machineMismatch) -and $text.Contains($maxRows)){ return $true }
  if(($text.Contains($programName) -or $text.Contains($structure)) -and $text.Contains($duplicate)){ return $true }
  return $false
}
function DismissDialogElement($dialog, [string]$label){
  try{
    $buttons=$dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
    for($i=0;$i -lt $buttons.Count;$i++){
      $button=$buttons.Item($i)
      if(-not $button.Current.IsEnabled){ continue }
      $buttonName=[string]$button.Current.Name
      if($buttonName -and $buttonName -notmatch '^(OK|确定|是|Yes|はい)$'){ continue }
      try{
        $invokePattern=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $invokePattern.Invoke()
        Log ('dismissed '+$label+' dialog by button: '+$button.Current.Name)
        return $true
      }catch{
        ClickAutomationElementCenter $button ($label+' dialog button '+$button.Current.Name)
        return $true
      }
    }
  }catch{
    Log ('dismiss dialog failed '+$label+': '+$_.Exception.Message)
  }
  return $false
}
function AssertNoMnmReadFailureDialog([string]$stage){
  $dialogs=SaveVisibleDialogSnapshot $stage
  foreach($row in $dialogs){
    $text=[string]$row.TextJoined
    if(TestMnmReadFailureText $text){
      try{
        $root=[System.Windows.Automation.AutomationElement]::RootElement
        $dialog=$root.FindFirst(
          [System.Windows.Automation.TreeScope]::Children,
          (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NativeWindowHandleProperty,[int]$row.NativeWindowHandle))
        )
        if($dialog){ DismissDialogElement $dialog 'mnemonic read failure' | Out-Null }
      }catch{}
      $text | Set-Content -LiteralPath (Join-Path $out ("mnm_read_failure_$($stage -replace '[^A-Za-z0-9_.-]','_').txt")) -Encoding UTF8
      $flatText = $text -replace "(`r`n|`n|`r)", ' | '
      throw ("MNM read/import failed at stage " + $stage + ": " + $flatText)
    }
  }
}
function DismissInstructionErrorDialogs([string]$stage){
  $needle=[string]::Concat([char[]]@(0x4E0D,0x5B58,0x5728,0x7684,0x6307,0x4EE4))
  $dismissed=0
  $errorTexts=@()
  foreach($dialog in @(GetVisibleDialogs)){
    try{
      if($dialog.Current.ClassName -ne '#32770'){ continue }
      $text=[string]((GetElementTextLines $dialog) -join "`n")
      if(-not $text.Contains($needle)){ continue }
      $text | Set-Content -LiteralPath (Join-Path $out ("instruction_error_$($stage -replace '[^A-Za-z0-9_.-]','_')_$dismissed.txt")) -Encoding UTF8
      $errorTexts += $text
      DismissDialogElement $dialog ('instruction error '+$stage) | Out-Null
      $dismissed++
    }catch{}
  }
  if($dismissed -gt 0){ Log ("dismissed instruction-error dialogs stage=$stage count=$dismissed") }
  if($errorTexts.Count -gt 0){
    throw ("Instruction error dialog appeared at stage ${stage}: " + (($errorTexts -join ' | ') -replace "(`r`n|`n|`r)", ' | '))
  }
}
function DismissUnitConfigDialogIfPresent([string]$stage){
  $titleNeedle=[string]::Concat([char[]]@(0x786E,0x8BA4,0x5355,0x5143,0x914D,0x7F6E,0x8BBE,0x5B9A))
  $noNeedle=[string]::Concat([char[]]@(0x5426))
  foreach($dialog in @(GetVisibleDialogs)){
    try{
      if($dialog.Current.ClassName -ne '#32770'){ continue }
      $title=[string]$dialog.Current.Name
      $text=[string]((GetElementTextLines $dialog) -join "`n")
      if(-not ($title.Contains($titleNeedle) -or $text.Contains($titleNeedle))){ continue }
      $text | Set-Content -LiteralPath (Join-Path $out ("unit_config_dialog_$($stage -replace '[^A-Za-z0-9_.-]','_').txt")) -Encoding UTF8
      [W]::SetForegroundWindow([IntPtr]$dialog.Current.NativeWindowHandle) | Out-Null
      Start-Sleep -Milliseconds 200
      Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd ([IntPtr]$dialog.Current.NativeWindowHandle) -Step ('dismiss unit config Alt+N '+$stage) -Keys '%n' -ExpectedTitleLike '*' -SuccessTitleLike 'KV STUDIO*' -Action 'Alt+N selects No in unit configuration prompt' -SleepMs 2000
      Log ('dismissed unit-configuration prompt with Alt+N stage='+$stage)
      Start-Sleep -Seconds 2
      return $true
    }catch{
      Log ('unit config dialog handling failed stage='+$stage+': '+$_.Exception.Message)
      throw
    }
  }
  return $false
}
function ResolveProgramKindName([string]$category){
  $normalized=([string]$category).Trim()
  if($normalized.Length -eq 0){ return '' }
  switch($normalized){
    'scan' { return '每次扫描执行型模块' }
    'function_block' { return '功能块' }
    'standby' { return '后备模块' }
    'initialization' { return '初始化模块' }
    'fixed_cycle' { return '固定周期模块' }
    'interrupt' { return '中断模块' }
    'unit_sync' { return '单元间同步模块' }
    default { throw ('Unsupported program category for program-kind dialog: '+$category) }
  }
}
function DumpProgramKindDialog($dialog, [string]$name, [string]$targetKind, [string]$actualKind){
  try{
    $rows=@()
    $desc=$dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
    for($i=0;$i -lt $desc.Count;$i++){
      $e=$desc.Item($i)
      $r=$e.Current.BoundingRectangle
      $rows += [pscustomobject]@{
        Index=$i
        Name=$e.Current.Name
        Class=$e.Current.ClassName
        Type=$e.Current.ControlType.ProgrammaticName
        AutomationId=$e.Current.AutomationId
        IsEnabled=$e.Current.IsEnabled
        Rect=('{0},{1},{2},{3}' -f $r.Left,$r.Top,$r.Width,$r.Height)
      }
    }
    [pscustomobject]@{
      target_kind=$targetKind
      actual_kind=$actualKind
      dialog_name=$dialog.Current.Name
      dialog_automation_id=$dialog.Current.AutomationId
      elements=$rows
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out $name) -Encoding UTF8
    Log ('dump '+$name)
  }catch{
    Log ('program kind dialog dump failed: '+$_.Exception.Message)
  }
}
function GetProgramKindComboText($combo){
  try{
    $selectionPattern=$combo.GetCurrentPattern([System.Windows.Automation.SelectionPattern]::Pattern)
    $selected=@($selectionPattern.GetSelection())
    $names=@()
    foreach($item in $selected){
      $n=([string]$item.Current.Name).Trim()
      if($n){ $names += $n }
    }
    if($names.Count -gt 0){ return ($names -join '|') }
  }catch{}
  try{
    $valuePattern=$combo.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $value=([string]$valuePattern.Current.Value).Trim()
    if($value){ return $value }
  }catch{}
  try{
    $lines=@(GetElementTextLines $combo | Where-Object { $_ })
    if($lines.Count -gt 0){ return ($lines -join '|') }
  }catch{}
  return ''
}
function FindProgramKindListItem($dialog, $combo, [string]$targetKind){
  $nameCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$targetKind)
  $listItemCondition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem)
  $targetCondition = New-Object System.Windows.Automation.AndCondition($nameCondition,$listItemCondition)

  foreach($scopeRoot in @($combo,$dialog)){
    if(-not $scopeRoot){ continue }
    try{
      $match=$scopeRoot.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$targetCondition)
      if($match){ return $match }
    }catch{}
  }

  try{
    $root=[System.Windows.Automation.AutomationElement]::RootElement
    $match=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$targetCondition)
    if($match){ return $match }
  }catch{}

  return $null
}
function SelectProgramKind($dialog, [string]$targetKind){
  if(-not $targetKind){ return '' }
  $combo=$dialog.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ComboBox))
  )
  if(-not $combo){ throw ('Program kind dialog found but ComboBox was not found for target kind: '+$targetKind) }
  try{ [W]::SetForegroundWindow([IntPtr]$dialog.Current.NativeWindowHandle) | Out-Null }catch{}
  try{ $combo.SetFocus() }catch{ Log ('program kind combo SetFocus failed: '+$_.Exception.Message) }
  try{
    $expand=$combo.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    $expand.Expand()
    Log ('expanded program kind combo for target='+$targetKind)
  }catch{
    throw ('Program kind combo did not support ExpandCollapsePattern for target '+$targetKind+': '+$_.Exception.Message)
  }
  Start-Sleep -Milliseconds 100
  $findStarted=Get-Date
  $match=FindProgramKindListItem $dialog $combo $targetKind
  $findMs=[math]::Round(((Get-Date)-$findStarted).TotalMilliseconds,0)
  Log ('program kind exact lookup target='+$targetKind+' elapsed_ms='+$findMs+' found='+[bool]$match)
  if(-not $match){
    $root=[System.Windows.Automation.AutomationElement]::RootElement
    $items=$root.FindAll(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::ListItem))
    )
    for($i=0;$i -lt $items.Count;$i++){
      $item=$items.Item($i)
      if(([string]$item.Current.Name).Trim() -eq $targetKind){
        $match=$item
        break
      }
    }
    $fallbackMs=[math]::Round(((Get-Date)-$findStarted).TotalMilliseconds,0)
    Log ('program kind fallback enumeration target='+$targetKind+' elapsed_ms='+$fallbackMs+' found='+[bool]$match)
  }
  if(-not $match){
    DumpProgramKindDialog $dialog 'program_kind_dialog_target_missing.json' $targetKind (GetProgramKindComboText $combo)
    throw ('Program kind list item not found: '+$targetKind)
  }
  try{
    $selection=$match.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    $selection.Select()
    Log ('selected program kind by SelectionItemPattern: '+$targetKind)
  }catch{
    DumpProgramKindDialog $dialog 'program_kind_dialog_select_failed.json' $targetKind (GetProgramKindComboText $combo)
    throw ('Failed to select program kind '+$targetKind+': '+$_.Exception.Message)
  }
  Start-Sleep -Milliseconds 100
  $actual=GetProgramKindComboText $combo
  DumpProgramKindDialog $dialog 'program_kind_dialog_after_select.json' $targetKind $actual
  if($actual -and $actual -notlike ('*'+$targetKind+'*')){
    throw ('Program kind selection mismatch: expected '+$targetKind+', actual '+$actual)
  }
  return $actual
}
function ConfirmProgramKindDialog([string]$expectedCategory){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $dialog=$root.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.AndCondition(
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'ModuleTypeSelectForm')),
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window))
    ))
  )
  if(-not $dialog){
    Log 'program kind dialog not found'
    return $false
  }
  $targetKind=ResolveProgramKindName $expectedCategory
  if($targetKind){
    DumpProgramKindDialog $dialog 'program_kind_dialog_before_select.json' $targetKind ''
    $actualKind=SelectProgramKind $dialog $targetKind
    Log ('program kind target='+$targetKind+' actual='+$actualKind)
  }else{
    Log 'program kind dialog present; no ExpectedCategory supplied, accepting current selection'
  }
  $button=$dialog.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.AndCondition(
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'_buttonOK')),
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
    ))
  )
  if(-not $button){ throw 'Program kind dialog found but OK button _buttonOK was not found.' }
  try{
    $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
    Log ('invoked program kind OK button by AutomationId _buttonOK category='+$expectedCategory)
  }catch{
    ClickAutomationElementCenter $button 'program kind OK button'
  }
  return $true
}
function ConfirmAnyPostImportDialog(){
  $dialogs=@(GetVisibleDialogs)
  foreach($dialog in $dialogs){
    $name=$dialog.Current.Name
    $class=$dialog.Current.ClassName
    if($class -ne '#32770'){ continue }
    $buttons=$dialog.FindAll(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
    )
    for($i=0;$i -lt $buttons.Count;$i++){
      $button=$buttons.Item($i)
      $buttonName=$button.Current.Name
      if($buttonName -eq 'OK' -or $buttonName -match 'OK|纭畾|纰哄畾|銇亜|鏄瘄鎵撳紑|闁嬨亸'){
        try{
          $invokePattern=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
          $invokePattern.Invoke()
          Log ('invoked post-import dialog button: '+$buttonName+' dialog='+$name)
        }catch{
          ClickAutomationElementCenter $button ('post-import dialog button '+$buttonName)
        }
        return $true
      }
    }
  }
  return $false
}
function TestUiElementName([string]$name){
  if(-not $name){ return $false }
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $all=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  for($i=0;$i -lt $all.Count;$i++){
    $elementName=$all.Item($i).Current.Name
    if($elementName -eq $name -or $elementName -like ('*'+$name+'*')){
      return $true
    }
  }
  return $false
}
function FindProjectFilesContainingText([string]$root, [string]$needle){
  $matches=@()
  if(-not $root -or -not (Test-Path -LiteralPath $root) -or -not $needle){
    return $matches
  }
  $encodingDefault=[Text.Encoding]::Default
  $encodingUnicode=[Text.Encoding]::Unicode
  Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    try{
      $bytes=[IO.File]::ReadAllBytes($_.FullName)
      $defaultText=$encodingDefault.GetString($bytes)
      $unicodeText=$encodingUnicode.GetString($bytes)
      if($defaultText.Contains($needle) -or $unicodeText.Contains($needle)){
        $matches += [pscustomobject]@{
          FullName=$_.FullName
          Length=$_.Length
          LastWriteTime=$_.LastWriteTime.ToString('s')
        }
      }
    }catch{}
  }
  return $matches
}
function GetMnmValidationNeedles([string]$path, [string]$expectedModuleName){
  $needles=@()
  if($expectedModuleName){ $needles += $expectedModuleName }
  if($path -and (Test-Path -LiteralPath $path)){
    Get-Content -LiteralPath $path -ErrorAction SilentlyContinue | ForEach-Object {
      $line=([string]$_).Trim()
      if($line -match '^(LD|LDP|LDF|AND|ANI|OR|ORI|OUT|SET|RES|MOV|DMOV|CMP|TMR|CNT)\s+([A-Za-z_][A-Za-z0-9_]*|[A-Z]+[0-9]+)'){
        $device=$matches[2]
        if($device -and $device -notmatch '^_Always(On|Off)$'){
          $needles += $device
        }
      }
      if($line -match '^;MODULE:(.+)$'){
        $needles += $matches[1].Trim()
      }
    }
  }
  return @($needles | Where-Object { $_ } | Select-Object -Unique)
}
function FindProjectFilesContainingAnyText([string]$root, [string[]]$needles){
  $results=@()
  foreach($needle in $needles){
    $matches=FindProjectFilesContainingText $root $needle
    $results += [pscustomobject]@{
      Needle=$needle
      Found=(@($matches).Count -gt 0)
      MatchingFiles=@($matches)
    }
  }
  return $results
}
function GetMissingValidationNeedles($matches){
  $missing=@()
  foreach($match in @($matches)){
    if(-not $match.Found){
      $missing += $match.Needle
    }
  }
  return @($missing | Where-Object { $_ } | Select-Object -Unique)
}
try{
  $RestartKvs = ConvertTo-BoolValue $RestartKvs $true
  $FailOnMissingProjectPlainText = ConvertTo-BoolValue $FailOnMissingProjectPlainText $false
  $FailOnMissingValidationNeedles = ConvertTo-BoolValue $FailOnMissingValidationNeedles $false
  if($MnmPath){ $MnmPath=[IO.Path]::GetFullPath($MnmPath) }
  if($project){ $project=[IO.Path]::GetFullPath($project) }
  if($ProjectSearchRoot){ $ProjectSearchRoot=[IO.Path]::GetFullPath($ProjectSearchRoot) }
  Log 'start mnm import'
  Log ('MnmPath='+$MnmPath)
  Log ('ProjectPath='+$project)
  Log ('OutDir='+$out)
  if(-not $ExpectedModuleName -and $MnmPath){
    $ExpectedModuleName=[IO.Path]::GetFileNameWithoutExtension($MnmPath)
  }
  if(-not $ProjectSearchRoot){
    $ProjectSearchRoot=Split-Path -Parent $project
  }
  Log ('ExpectedModuleName='+$ExpectedModuleName)
  Log ('SaveAfterImport='+$SaveAfterImport.IsPresent)
  Log ('FailOnMissingProjectPlainText='+$FailOnMissingProjectPlainText)
  Log ('FailOnMissingValidationNeedles='+$FailOnMissingValidationNeedles)
  Log ('DeleteExistingModuleBeforeImport='+$DeleteExistingModuleBeforeImport.IsPresent)
  Log ('ProjectSearchRoot='+$ProjectSearchRoot)
  if(-not (Test-Path -LiteralPath $project)){ throw "ProjectPath not found: $project" }
  if(-not (Test-Path -LiteralPath $kvs)){ throw "KvsExe not found: $kvs" }
  if($MnmPath -and -not (Test-Path -LiteralPath $MnmPath)){ throw "MnmPath not found: $MnmPath" }
  AssertMnmChineseEncoding $MnmPath
  $expectedProjectNeedle=[IO.Path]::GetFileNameWithoutExtension($project)
  if($RestartKvs){
    Get-Process Kvs -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  }
  $p = Get-Process Kvs -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowTitle -like ('*'+$expectedProjectNeedle+'*') } |
    Select-Object -First 1
  $projectOpenRequested = $false
  if(-not $p){
    Start-Process -FilePath $kvs -ArgumentList ('"'+$project+'"') | Out-Null
    $projectOpenRequested = $true
  }
  $deadline=(Get-Date).AddSeconds(90)
  while((-not $p) -and (Get-Date) -lt $deadline) {
    Start-Sleep -Milliseconds 500
    $p=Get-Process Kvs -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowTitle -like ('*'+$expectedProjectNeedle+'*') } |
      Select-Object -First 1
    if((-not $p) -and (-not $projectOpenRequested) -and (Get-Date) -gt $deadline.AddSeconds(-82)){
      Log ('target project window not visible yet; requesting project open explicitly: '+$project)
      Start-Process -FilePath $kvs -ArgumentList ('"'+$project+'"') | Out-Null
      $projectOpenRequested = $true
    }
  }
  if(-not $p){ throw "Kvs target project window not found after start: $expectedProjectNeedle" }
  [void](ForceKvStudioForeground ([IntPtr]$p.MainWindowHandle))
  Start-Sleep -Milliseconds 150
  [void](ForceKvStudioForeground ([IntPtr]$p.MainWindowHandle))
  if(-not (WaitKvsMainWindowReady 90)){
    throw 'KV STUDIO main window did not become ready.'
  }
  if(-not (WaitKvInteractive 60)){
    throw 'KV STUDIO main window still shows splash/loader; refusing menu route.'
  }
  $titleDeadline=(Get-Date).AddSeconds(60)
  $reopenRequestedForTitle=$false
  while((Get-Date) -lt $titleDeadline){
    $targetProjectProcess=Get-Process Kvs -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowTitle -like ('*'+$expectedProjectNeedle+'*') } |
      Select-Object -First 1
    if($targetProjectProcess){
      $p=$targetProjectProcess
      [void](ForceKvStudioForeground ([IntPtr]$p.MainWindowHandle))
      break
    }
    if((-not $reopenRequestedForTitle) -and (Get-Date) -gt $titleDeadline.AddSeconds(-52)){
      Log ('foreground KV STUDIO title does not contain target project; requesting project open before startup guard: '+$project)
      Start-Process -FilePath $kvs -ArgumentList ('"'+$project+'"') | Out-Null
      $reopenRequestedForTitle=$true
    }
    Start-Sleep -Milliseconds 500
  }
  try{ $p.Refresh() }catch{}
  if($p.MainWindowTitle -notlike ('*'+$expectedProjectNeedle+'*')){
    throw "Kvs target project title did not become visible before startup guard: expected=$expectedProjectNeedle actual=$($p.MainWindowTitle)"
  }
  SetKvGuardTarget ([IntPtr]$p.MainWindowHandle) ('KV STUDIO*'+$expectedProjectNeedle+'*')
  AssertKvStudioForeground 'MNM import startup' $expectedProjectNeedle
  if($RestartKvs){ Start-Sleep -Seconds 2 } else { Start-Sleep -Milliseconds 200 }
  Shot '00_before_import.png'
  DismissInstructionErrorDialogs 'before_import'
  DismissUnitConfigDialogIfPresent 'before_import' | Out-Null
  if($DeleteExistingModuleBeforeImport -and $ExpectedModuleName){
    if(-not (RemoveProjectModuleIfPresent $ExpectedModuleName)){
      throw "Failed to delete existing module before import: $ExpectedModuleName"
    }
  }elseif($ExpectedModuleName){
    Log ('skipping project-tree module open before MNM import; full MNM import must create/update module: '+$ExpectedModuleName)
  }
  AssertKvStudioForeground 'MNM import route' $expectedProjectNeedle
  $routeOpened=$false
  for($attempt=1;$attempt -le 2 -and -not $routeOpened;$attempt++){
    InvokeMnemonicImportMenu
    if(DismissUnitConfigDialogIfPresent ('mnm_route_attempt_'+$attempt)){
      Log ('unit configuration prompt interrupted MNM route attempt '+$attempt+'; retrying route after explicit No')
      continue
    }
    $routeOpened=$true
  }
  if(-not $routeOpened){
    throw 'MNM import route was interrupted by unit-configuration prompt more than once'
  }
  Shot '01_after_import_route.png'
  if($VerboseUiDump){ DumpUi 'uia_after_import_route.json' }
  if($MnmPath){
    if(-not (SetOpenDialogFile $MnmPath)){
      throw 'MNM file path target was not a verified mnemonic-read path edit or standard file-open dialog; refusing clipboard/Enter fallback'
    }
    if($AuditImportWaits){ Start-Sleep -Seconds 8 } else { Start-Sleep -Milliseconds 800 }
    Shot '02_after_file_open.png'
    if($VerboseUiDump){ DumpUi 'uia_after_file_open.json' }
    AssertNoMnmReadFailureDialog 'after_file_open'
    Log 'standard open dialog accepted MNM file; no separate MNM insert/overwrite panel is required for this route'
    DismissInstructionErrorDialogs 'after_file_open'
    $programKindConfirmed = ConfirmProgramKindDialog $ExpectedCategory
    if($programKindConfirmed){
      if($AuditImportWaits){ Start-Sleep -Seconds 8 } else { Start-Sleep -Milliseconds 800 }
      AssertNoMnmReadFailureDialog 'after_program_kind_confirm'
    }elseif(ConfirmAnyPostImportDialog){
      if($AuditImportWaits){ Start-Sleep -Seconds 8 } else { Start-Sleep -Milliseconds 800 }
      AssertNoMnmReadFailureDialog 'after_post_import_dialog'
    }
  }
  Shot '03_after_import_confirm.png'
  if($VerboseUiDump){ DumpUi 'uia_after_import_confirm.json' }
  AssertNoMnmReadFailureDialog 'after_import_confirm'
  $foundExpected=$false
  if($AuditUiNameScan -and $ExpectedModuleName){
    $foundExpected=TestUiElementName $ExpectedModuleName
  } elseif($ExpectedModuleName) {
    Log "skipping UI name scan for expected module in fast mode: $ExpectedModuleName"
  }
  $validationNeedles=GetMnmValidationNeedles $MnmPath $ExpectedModuleName
  $projectContentMatches = @()
  if($AuditProjectTextScan){
    $projectContentMatches=FindProjectFilesContainingAnyText $ProjectSearchRoot $validationNeedles
  } else {
    $projectContentMatches=@($validationNeedles | ForEach-Object {
      [pscustomobject]@{ Needle=$_; Found=$false; Matches=@(); Skipped=$true }
    })
    Log 'skipping project text scan after MNM import in fast mode'
  }
  $foundAnyProjectContent=(@($projectContentMatches | Where-Object { $_.Found }).Count -gt 0)
  $missingValidationNeedles=GetMissingValidationNeedles $projectContentMatches
  [pscustomobject]@{
    MnmPath=$MnmPath
    ProjectPath=$project
    ExpectedModuleName=$ExpectedModuleName
    FoundExpectedModule=$foundExpected
    ValidationNeedles=$validationNeedles
    FoundAnyProjectContent=$foundAnyProjectContent
    MissingValidationNeedles=$missingValidationNeedles
    ProjectContentMatches=$projectContentMatches
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $out 'import_validation.json') -Encoding UTF8
  if($FailOnMissingValidationNeedles -and @($missingValidationNeedles).Count -gt 0){
    throw "Missing MNM validation needles after import: $($missingValidationNeedles -join ', ')"
  }
  if($AuditUiNameScan -and $ExpectedModuleName -and -not $foundExpected){
    Log "Expected module name is not visible in KV STUDIO UI yet: $ExpectedModuleName"
    throw "Expected module name is not visible in KV STUDIO after MNM import: $ExpectedModuleName"
  }
  if($SaveAfterImport){
    $saveProcess=Get-Process Kvs -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowTitle -like ('*'+$expectedProjectNeedle+'*') } |
      Select-Object -First 1
    if(-not $saveProcess){
      throw "KV STUDIO target project window not found before Ctrl+S after MNM import: $expectedProjectNeedle"
    }
    [void](ForceKvStudioForeground ([IntPtr]$saveProcess.MainWindowHandle))
    Start-Sleep -Milliseconds 300
    [void](ForceKvStudioForeground ([IntPtr]$saveProcess.MainWindowHandle))
    AssertKvStudioForeground 'Ctrl+S after MNM import' $expectedProjectNeedle
    Invoke-KvGuardedSendKeys -TargetHwnd $saveProcess.MainWindowHandle -Step 'save after MNM import Ctrl+S' -Keys '^s' -ExpectedTitleLike $script:KvGuardExpectedTitleLike -Action 'Ctrl+S saves project after MNM import' -SleepMs $(if($AuditImportWaits){8000}else{500})
    Log 'sent Ctrl+S'
    if($AuditImportWaits){ Start-Sleep -Seconds 8 } else { Start-Sleep -Milliseconds 800 }
    Shot '04_after_save.png'
    if($VerboseUiDump){ DumpUi 'uia_after_save.json' }
    AssertNoMnmReadFailureDialog 'after_save'
    $projectMatches=@()
    $projectContentMatchesAfterSave=@()
    if($AuditProjectTextScan){
      $projectMatches=FindProjectFilesContainingText $ProjectSearchRoot $ExpectedModuleName
      $projectContentMatchesAfterSave=FindProjectFilesContainingAnyText $ProjectSearchRoot $validationNeedles
    } else {
      Log 'skipping project text scan after MNM save in fast mode'
      $projectContentMatchesAfterSave=@($validationNeedles | ForEach-Object {
        [pscustomobject]@{ Needle=$_; Found=$false; Matches=@(); Skipped=$true }
      })
    }
    $foundAnyProjectContentAfterSave=(@($projectContentMatchesAfterSave | Where-Object { $_.Found }).Count -gt 0)
    $missingValidationNeedlesAfterSave=GetMissingValidationNeedles $projectContentMatchesAfterSave
    [pscustomobject]@{
      ProjectSearchRoot=$ProjectSearchRoot
      ExpectedModuleName=$ExpectedModuleName
      PlainTextSearchIsAdvisory=(-not $FailOnMissingProjectPlainText)
      FoundInProjectFiles=(@($projectMatches).Count -gt 0)
      MatchingFiles=@($projectMatches)
      ValidationNeedles=$validationNeedles
      FoundAnyProjectContent=$foundAnyProjectContentAfterSave
      MissingValidationNeedles=$missingValidationNeedlesAfterSave
      ProjectContentMatches=$projectContentMatchesAfterSave
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'persistence_validation.json') -Encoding UTF8
    if($FailOnMissingValidationNeedles -and @($missingValidationNeedlesAfterSave).Count -gt 0){
      throw "Missing MNM validation needles after save: $($missingValidationNeedlesAfterSave -join ', ')"
    }
    if(-not $foundAnyProjectContentAfterSave){
      $plainTextMissMessage="No MNM validation needles found in project files after save: $($validationNeedles -join ', ')"
      if($FailOnMissingProjectPlainText){
        throw $plainTextMissMessage
      }
      Log ($plainTextMissMessage+'; continuing because KV project persistence is not guaranteed plaintext. Use exported MNM and convert result as the acceptance gate.')
    }
  }
  '0'|Set-Content -LiteralPath (Join-Path $out 'exit_code.txt') -Encoding ASCII
}catch{
  Log ('ERR '+$_.Exception.ToString())
  $_.Exception.ToString()|Set-Content -LiteralPath (Join-Path $out 'fail.txt') -Encoding UTF8
  '1'|Set-Content -LiteralPath (Join-Path $out 'exit_code.txt') -Encoding ASCII
  try{
    Get-Process Kvs -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 } |
      Stop-Process -Force -ErrorAction SilentlyContinue
    Log 'closed visible KV STUDIO windows after import failure'
  }catch{}
  exit 1
}
