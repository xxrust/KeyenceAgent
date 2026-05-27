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
  [int]$TimeoutSeconds = 120,
  [switch]$RestartKvs
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) {
  $OutDir = Join-Path $ProjectRoot ('_create_project_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
New-Item -ItemType Directory -Force -Path $OutDir, $ProjectRoot | Out-Null

function Log([string]$Message) {
  $line = (Get-Date -Format s) + ' ' + $Message
  Add-Content -LiteralPath (Join-Path $OutDir 'run.log') -Value $line -Encoding UTF8
  Write-Host $line
}

if (-not $KvsExe) {
  $resolver = Join-Path (Split-Path -Parent $PSCommandPath) 'resolve_kvstudio_local.ps1'
  $resolved = (& powershell -NoProfile -ExecutionPolicy Bypass -File $resolver | ConvertFrom-Json)
  $KvsExe = $resolved.KvsExe
}
if (-not (Test-Path -LiteralPath $KvsExe)) { throw "KvsExe not found: $KvsExe" }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KvWin32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd,int nCmdShow);
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
      [System.Windows.Forms.SendKeys]::SendWait('%n')
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

try {
  $startedAt = Get-Date
  Log "start create_project_local ProjectName=$ProjectName ProjectRoot=$ProjectRoot CpuModel=$CpuModel KvsExe=$KvsExe"

  if ($RestartKvs) {
    Get-Process Kvs -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
  }
  $process = Get-Process Kvs -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $process) {
    Start-Process -FilePath $KvsExe -WorkingDirectory (Split-Path -Parent $KvsExe) | Out-Null
  }

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    Start-Sleep -Milliseconds 500
    $process = Get-Process Kvs -ErrorAction SilentlyContinue | Select-Object -First 1
  } while (($null -eq $process -or $process.MainWindowHandle -eq 0) -and (Get-Date) -lt $deadline)
  if (-not $process -or $process.MainWindowHandle -eq 0) { throw 'KV STUDIO main window not ready' }
  [KvWin32]::ShowWindow($process.MainWindowHandle, 3) | Out-Null
  [KvWin32]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
  Start-Sleep -Milliseconds 500

  Log 'send Ctrl+N'
  [System.Windows.Forms.SendKeys]::SendWait('^n')
  $projectNameControl = Find-ElementByAutomationId '1000' 12
  if (-not $projectNameControl) {
    Save-Uia 'fail_no_new_project_dialog.json'
    throw 'New project dialog did not open'
  }

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

  Start-Sleep -Seconds 2
  $process = Get-Process Kvs -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($process -and $process.MainWindowHandle -ne 0) {
    [KvWin32]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
    [System.Windows.Forms.SendKeys]::SendWait('^s')
    Start-Sleep -Seconds 2
  }

  $projectPath = Join-Path (Join-Path $ProjectRoot $ProjectName) ($ProjectName + '.kpr')
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

