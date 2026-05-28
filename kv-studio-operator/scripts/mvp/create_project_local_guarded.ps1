param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectName,

  [Parameter(Mandatory=$true)]
  [string]$ProjectRoot,

  [string]$CpuModel = 'KV-X550',
  [string]$KvsExe = '',
  [string]$AdminUser = 'admin',
  [string]$AdminPassword = 'a82701767',
  [string]$OutDir = '',
  [string]$ChecklistPath = '',
  [int]$TimeoutSeconds = 120,
  [switch]$RestartKvs
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) {
  $OutDir = Join-Path $ProjectRoot ('_create_project_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
New-Item -ItemType Directory -Force -Path $OutDir, $ProjectRoot | Out-Null

$checklistGuard = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'assert_kv_operation_checklist.ps1'
if (-not (Test-Path -LiteralPath $checklistGuard)) { throw "Checklist guard script not found: $checklistGuard" }
$global:LASTEXITCODE = 0
& $checklistGuard -ChecklistPath $ChecklistPath -SearchRoots @($OutDir, $ProjectRoot) -OperationName 'create KV STUDIO project' | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

function Log([string]$Message) {
  $line = (Get-Date -Format s) + ' ' + $Message
  Add-Content -LiteralPath (Join-Path $OutDir 'run.log') -Value $line -Encoding UTF8
  Write-Host $line
}

if (-not $KvsExe) {
  $resolver = Join-Path (Split-Path -Parent $PSCommandPath) 'resolve_kvstudio_local.ps1'
  if (-not (Test-Path -LiteralPath $resolver)) {
    $resolver = 'C:\Users\liangyuhang\.codex\skills\keyence-plc-programmer\scripts\resolve_kvstudio_local.ps1'
  }
  if (-not (Test-Path -LiteralPath $resolver)) {
    throw "KV STUDIO resolver not found: $resolver"
  }
  $resolved = (& powershell -NoProfile -ExecutionPolicy Bypass -File $resolver | ConvertFrom-Json)
  $KvsExe = $resolved.KvsExe
}
if (-not (Test-Path -LiteralPath $KvsExe)) { throw "KvsExe not found: $KvsExe" }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$sharedUiGuard = Join-Path (Split-Path -Parent $PSCommandPath) 'kv_ui_guard.ps1'
if (-not (Test-Path -LiteralPath $sharedUiGuard)) { throw "Shared KV UI guard script not found: $sharedUiGuard" }
. $sharedUiGuard
Initialize-KvUiGuard -OutDir $OutDir -CheckpointSubdir 'shared_ui_guard_checkpoints'
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KvWin32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd,int nCmdShow);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr SetActiveWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr SetFocus(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint processId);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint idAttach, uint idAttachTo, bool fAttach);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, string lParam);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
}
"@

$WM_SETTEXT = 0x000C
$BM_CLICK = 0x00F5
$CB_SELECTSTRING = 0x014D
$CB_SETCURSEL = 0x014E

function Save-Uia([string]$Name) {
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $all = $root.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  $rows = @()
  for ($i = 0; $i -lt $all.Count -and $i -lt 2000; $i++) {
    $e = $all.Item($i)
    $r = $e.Current.BoundingRectangle
    if ($e.Current.Name -or $e.Current.ClassName -or $e.Current.AutomationId) {
      $rows += [pscustomobject]@{
        Index = $i
        Name = $e.Current.Name
        Class = $e.Current.ClassName
        Type = $e.Current.ControlType.ProgrammaticName
        AutomationId = $e.Current.AutomationId
        Hwnd = $e.Current.NativeWindowHandle
        Rect = ('{0},{1},{2},{3}' -f $r.Left, $r.Top, $r.Width, $r.Height)
      }
    }
  }
  $rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir $Name) -Encoding UTF8
}

function Find-ElementByAutomationId([string]$AutomationId, [int]$Seconds = 10) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  $condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $AutomationId)
  do {
    $element = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
    if ($element) { return $element }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Find-ChildByAutomationId($RootElement, [string]$AutomationId) {
  if (-not $RootElement) { return $null }
  $condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, $AutomationId)
  return $RootElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
}

function Find-NewProjectDialog([int]$Seconds = 30) {
  $newProjectTitle = [string]::Concat([char[]]@(0x65B0,0x5EFA,0x9879,0x76EE))
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $hwnd = [KvWin32]::FindWindow('#32770', $newProjectTitle)
    if ($hwnd -ne [IntPtr]::Zero) {
      $dialog = [System.Windows.Automation.AutomationElement]::FromHandle($hwnd)
      $title = [string]$dialog.Current.Name
      $projectNameEdit = Find-ChildByAutomationId $dialog '1000'
      $cpuCombo = Find-ChildByAutomationId $dialog '1002'
      if ($projectNameEdit -and $cpuCombo -and ($title -eq $newProjectTitle -or $title.Contains($newProjectTitle))) {
        Log "found new project dialog by hwnd=$hwnd title=$title"
        return $dialog
      }
    }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Find-ElementByName([string]$Name, [int]$Seconds = 5) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  $condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty, $Name)
  do {
    $element = [System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
    if ($element) { return $element }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Set-TextById([string]$AutomationId, [string]$Text) {
  $element = Find-ElementByAutomationId $AutomationId 8
  if (-not $element) { throw "Control not found: $AutomationId" }
  [KvWin32]::SendMessage([IntPtr]$element.Current.NativeWindowHandle, $WM_SETTEXT, [IntPtr]::Zero, $Text) | Out-Null
}

function Click-ById([string]$AutomationId) {
  $element = Find-ElementByAutomationId $AutomationId 8
  if (-not $element) { throw "Control not found: $AutomationId" }
  [KvWin32]::SendMessage([IntPtr]$element.Current.NativeWindowHandle, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
}

function Click-ByName([string]$Name, [int]$Seconds = 5) {
  $element = Find-ElementByName $Name $Seconds
  if (-not $element) { return $false }
  [KvWin32]::SendMessage([IntPtr]$element.Current.NativeWindowHandle, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
  return $true
}

function Dismiss-UnitConfigPromptNoByAltN([int]$Seconds = 8) {
  $titleNeedle = [string]::Concat([char[]]@(0x786E,0x8BA4,0x5355,0x5143,0x914D,0x7F6E,0x8BBE,0x5B9A))
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $dialogs = $root.FindAll(
      [System.Windows.Automation.TreeScope]::Subtree,
      (New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window)),
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty,'#32770'))
      ))
    )
    for ($i = 0; $i -lt $dialogs.Count; $i++) {
      $dialog = $dialogs.Item($i)
      $title = [string]$dialog.Current.Name
      if (-not $title.Contains($titleNeedle)) { continue }
      [KvWin32]::SetForegroundWindow([IntPtr]$dialog.Current.NativeWindowHandle) | Out-Null
      Start-Sleep -Milliseconds 200
      Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd ([IntPtr]$dialog.Current.NativeWindowHandle) -Step 'dismiss unit configuration prompt Alt+N' -Keys '%n' -ExpectedTitleLike "*$titleNeedle*" -SuccessTitleLike 'KV STUDIO*' -Action 'Alt+N selects No in unit configuration prompt' -SleepMs 500
      Log 'answered unit configuration prompt with Alt+N'
      return $true
    }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  return $false
}

function Select-ComboById([string]$AutomationId, [string]$Value) {
  $element = Find-ElementByAutomationId $AutomationId 8
  if (-not $element) { throw "Combo not found: $AutomationId" }
  [KvWin32]::SendMessage([IntPtr]$element.Current.NativeWindowHandle, $CB_SELECTSTRING, [IntPtr]::new(-1), $Value) | Out-Null
  [KvWin32]::SendMessage([IntPtr]$element.Current.NativeWindowHandle, $WM_SETTEXT, [IntPtr]::Zero, $Value) | Out-Null
}

function Get-ForegroundTitle {
  $hwnd = [KvWin32]::GetForegroundWindow()
  $builder = New-Object System.Text.StringBuilder 512
  [void][KvWin32]::GetWindowText($hwnd, $builder, $builder.Capacity)
  return [pscustomobject]@{ Hwnd = $hwnd; Title = $builder.ToString() }
}

function Get-KvStudioMainProcess {
  param([int]$Seconds = 20)
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $process = Get-Process Kvs -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' } |
      Sort-Object StartTime -Descending |
      Select-Object -First 1
    if ($process) { return $process }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Force-KvStudioForeground {
  param([IntPtr]$Hwnd)
  if ($Hwnd -eq [IntPtr]::Zero) { return $false }
  [KvWin32]::ShowWindow($Hwnd, 3) | Out-Null
  $foreground = [KvWin32]::GetForegroundWindow()
  $targetPid = [uint32]0
  $foregroundPid = [uint32]0
  $targetThread = [KvWin32]::GetWindowThreadProcessId($Hwnd, [ref]$targetPid)
  $foregroundThread = [KvWin32]::GetWindowThreadProcessId($foreground, [ref]$foregroundPid)
  $currentThread = [KvWin32]::GetCurrentThreadId()
  $attachedTarget = $false
  $attachedForeground = $false
  try {
    if ($targetThread -ne $currentThread) {
      $attachedTarget = [KvWin32]::AttachThreadInput($currentThread, $targetThread, $true)
    }
    if ($foregroundThread -ne 0 -and $foregroundThread -ne $currentThread -and $foregroundThread -ne $targetThread) {
      $attachedForeground = [KvWin32]::AttachThreadInput($currentThread, $foregroundThread, $true)
    }
    [KvWin32]::BringWindowToTop($Hwnd) | Out-Null
    [KvWin32]::SetActiveWindow($Hwnd) | Out-Null
    [KvWin32]::SetFocus($Hwnd) | Out-Null
    [KvWin32]::SetForegroundWindow($Hwnd) | Out-Null
  } finally {
    if ($attachedForeground) { [KvWin32]::AttachThreadInput($currentThread, $foregroundThread, $false) | Out-Null }
    if ($attachedTarget) { [KvWin32]::AttachThreadInput($currentThread, $targetThread, $false) | Out-Null }
  }
  Start-Sleep -Milliseconds 120
  $fg = Get-ForegroundTitle
  return ($fg.Hwnd -eq $Hwnd -or $fg.Title -like 'KV STUDIO*')
}

function Assert-KvStudioForeground([string]$Action) {
  $deadline = (Get-Date).AddSeconds(15)
  do {
    $fg = Get-ForegroundTitle
    Log ("foreground before ${Action}: hwnd=$($fg.Hwnd) title=$($fg.Title)")
    if ($fg.Title -like 'KV STUDIO*' -and $fg.Title -notmatch '鏈搷搴攟Not Responding') { return }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  throw "Refusing ${Action}: foreground window is not KV STUDIO. Title=$($fg.Title)"
}

function Restore-KvStudioForeground {
  param(
    [System.Diagnostics.Process]$Process,
    [string]$Action
  )
  for ($try = 1; $try -le 20; $try++) {
    $latest = Get-KvStudioMainProcess 1
    if ($latest) { $Process = $latest }
    [void](Force-KvStudioForeground ([IntPtr]$Process.MainWindowHandle))
    Start-Sleep -Milliseconds 250
    $fg = Get-ForegroundTitle
    Log ("foreground restore ${Action}: try=$try hwnd=$($fg.Hwnd) title=$($fg.Title)")
    if ($fg.Title -like 'KV STUDIO*') {
      return
    }
  }
  Assert-KvStudioForeground $Action
}

function Wait-ProjectSaveSettled([string]$ProjectPath, [string]$ProjectName, [int]$Seconds = 8) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $process = Get-Process Kvs -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' } |
      Select-Object -First 1
    $title = if ($process) { $process.MainWindowTitle } else { '' }
    $fileExists = Test-Path -LiteralPath $ProjectPath
    $savedTitle = $title -and ($title -like "*$ProjectName*") -and ($title -notmatch ([regex]::Escape($ProjectName) + '\s+\*'))
    if ($fileExists -and $savedTitle) {
      Log "project save settled title=$title path=$ProjectPath"
      return $true
    }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  Log "project save settle wait timed out path_exists=$(Test-Path -LiteralPath $ProjectPath)"
  return $false
}

try {
  $startedAt = Get-Date
  Log "start create_project_local ProjectName=$ProjectName ProjectRoot=$ProjectRoot CpuModel=$CpuModel KvsExe=$KvsExe"

  if ($RestartKvs) {
    Get-Process Kvs -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
  }
  $allKvs = @(Get-Process Kvs -ErrorAction SilentlyContinue)
  $visibleKvs = @($allKvs | Where-Object { $_.MainWindowHandle -ne 0 })
  if ($allKvs.Count -gt 0 -and $visibleKvs.Count -eq 0) {
    Log ("found Kvs process without main window after restart; starting a fresh visible instance. pids=" + (($allKvs | ForEach-Object { $_.Id }) -join ','))
  }
  $process = $visibleKvs | Select-Object -First 1
  if (-not $process) {
    Start-Process -FilePath $KvsExe -WorkingDirectory (Split-Path -Parent $KvsExe) | Out-Null
  }

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    Start-Sleep -Milliseconds 500
    $process = Get-KvStudioMainProcess 1
  } while (($null -eq $process -or $process.MainWindowHandle -eq 0) -and (Get-Date) -lt $deadline)
  if (-not $process -or $process.MainWindowHandle -eq 0) { throw 'KV STUDIO main window not ready' }
  Restore-KvStudioForeground $process 'Ctrl+N'

  Log 'send Ctrl+N'
  Assert-KvStudioForeground 'Ctrl+N'
  Invoke-KvGuardedSendKeys -TargetHwnd $process.MainWindowHandle -Step 'create project Ctrl+N' -Keys '^n' -ExpectedTitleLike 'KV STUDIO*' -Action 'Ctrl+N opens new project dialog' -SleepMs 200
  $newProjectDialog = Find-NewProjectDialog 45
  if (-not $newProjectDialog) {
    Save-Uia 'fail_no_new_project_dialog.json'
    throw 'New project dialog did not open'
  }
  [KvWin32]::SetForegroundWindow([IntPtr]$newProjectDialog.Current.NativeWindowHandle) | Out-Null
  Start-Sleep -Milliseconds 200

  Set-TextById '1000' $ProjectName
  Select-ComboById '1002' $CpuModel
  Set-TextById '1001' $ProjectRoot
  Set-TextById '1004' "created by create_project_local.ps1"
  Click-ById '1'
  Log 'submitted new project dialog'

  $adminUser = Find-ElementByAutomationId '_ltxUserName' 12
  if ($adminUser) {
    Set-TextById '_ltxUserName' $AdminUser
    Set-TextById '_ltxPassword' $AdminPassword
    Set-TextById '_ltxPasswordConfirmation' $AdminPassword
    Click-ById '_btnOK'
    Log 'submitted admin dialog'
  }

  Start-Sleep -Seconds 2
  if (-not (Dismiss-UnitConfigPromptNoByAltN 8)) {
    Log 'unit configuration prompt not present'
  }

  $projectPath = Join-Path (Join-Path $ProjectRoot $ProjectName) ($ProjectName + '.kpr')
  Start-Sleep -Seconds 2
  $process = Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if ($process -and $process.MainWindowHandle -ne 0) {
    [KvWin32]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
    Assert-KvStudioForeground 'Ctrl+S'
    Invoke-KvGuardedSendKeys -TargetHwnd $process.MainWindowHandle -Step 'save created project Ctrl+S' -Keys '^s' -ExpectedTitleLike 'KV STUDIO*' -Action 'Ctrl+S saves created project' -SleepMs 300
    if (-not (Wait-ProjectSaveSettled $projectPath $ProjectName 8)) {
      Start-Sleep -Seconds 2
    }
  }

  $found = $null
  if (Test-Path -LiteralPath $projectPath) {
    $found = $projectPath
  } else {
    $cutoff = $startedAt.AddMinutes(-1)
    $found = Get-ChildItem -LiteralPath $ProjectRoot -Recurse -Filter '*.kpr' -ErrorAction SilentlyContinue |
      Where-Object { $_.LastWriteTime -ge $cutoff } |
      Sort-Object LastWriteTime -Descending |
      Select-Object -First 1 -ExpandProperty FullName
  }
  if (-not $found) {
    Save-Uia 'fail_no_project_file.json'
    throw "Project file was not created under $ProjectRoot"
  }

  $result = [pscustomobject]@{
    ok = $true
    project_path = $found
    requested_project_path = $projectPath
    kvs_exe = $KvsExe
    cpu_model_requested = $CpuModel
    elapsed_seconds = [Math]::Round(((Get-Date) - $startedAt).TotalSeconds, 3)
  }
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'create_project_result.json') -Encoding UTF8
  $result | ConvertTo-Json -Depth 4
} catch {
  Log ('ERROR ' + $_.Exception.Message)
  Save-Uia 'create_project_error_uia.json'
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  exit 1
}
