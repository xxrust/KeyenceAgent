param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [Parameter(Mandatory=$true)]
  [string]$ExportDir,

  [string]$KvsExe = '',
  [string]$OutDir = '',
  [string]$ChecklistPath = '',
  [object]$RestartKvs = $false,
  [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
if (-not $OutDir) {
  $OutDir = Join-Path $ExportDir ('_export_mnm_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
}
New-Item -ItemType Directory -Force -Path $OutDir, $ExportDir | Out-Null

$checklistGuard = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'assert_kv_operation_checklist.ps1'
if (-not (Test-Path -LiteralPath $checklistGuard)) { throw "Checklist guard script not found: $checklistGuard" }
$global:LASTEXITCODE = 0
& $checklistGuard -ChecklistPath $ChecklistPath -SearchRoots @($OutDir, $ProjectPath, $ExportDir) -OperationName 'export MNM from KV STUDIO' | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

function Log([string]$Message) {
  $line = (Get-Date -Format s) + ' ' + $Message
  [IO.File]::AppendAllText((Join-Path $OutDir 'run.log'), $line + [Environment]::NewLine, [Text.Encoding]::UTF8)
  Write-Host $line
}

function ConvertTo-BoolValue([object]$Value, [bool]$Default) {
  if ($null -eq $Value) { return $Default }
  if ($Value -is [bool]) { return [bool]$Value }
  $text = ([string]$Value).Trim()
  if ($text.Length -eq 0) { return $Default }
  switch -Regex ($text) {
    '^(?i:\$?true|1|yes|y|on)$' { return $true }
    '^(?i:\$?false|0|no|n|off)$' { return $false }
    default { throw "Invalid boolean value: $Value" }
  }
}

if (-not $KvsExe) {
  $resolver = 'C:\Users\liangyuhang\.codex\skills\keyence-plc-programmer\scripts\resolve_kvstudio_local.ps1'
  if (-not (Test-Path -LiteralPath $resolver)) { throw "KV STUDIO resolver not found: $resolver" }
  $resolved = (& powershell -NoProfile -ExecutionPolicy Bypass -File $resolver | ConvertFrom-Json)
  $KvsExe = $resolved.KvsExe
}
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "ProjectPath not found: $ProjectPath" }
if (-not (Test-Path -LiteralPath $KvsExe -PathType Leaf)) { throw "KvsExe not found: $KvsExe" }

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$sharedUiGuard = Join-Path (Split-Path -Parent $PSCommandPath) 'kv_ui_guard.ps1'
if (-not (Test-Path -LiteralPath $sharedUiGuard)) { throw "Shared KV UI guard script not found: $sharedUiGuard" }
. $sharedUiGuard
Initialize-KvUiGuard -OutDir $OutDir -CheckpointSubdir 'export_guard'

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KvExportWin32 {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr FindWindow(string lpClassName, string lpWindowName);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr hDlg, int nIDDlgItem);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, string lParam);
}
"@

$WM_SETTEXT = 0x000C
$BM_CLICK = 0x00F5

function Get-ForegroundTitle {
  $hwnd = [KvExportWin32]::GetForegroundWindow()
  $builder = New-Object System.Text.StringBuilder 512
  [void][KvExportWin32]::GetWindowText($hwnd, $builder, $builder.Capacity)
  [pscustomobject]@{ Hwnd = $hwnd; Title = $builder.ToString() }
}

function Get-KvProcess([string]$ProjectNeedle, [int]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $process = Get-Process Kvs -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowTitle -like "*$ProjectNeedle*" } |
      Select-Object -First 1
    if ($process) { return $process }
    $process = Get-Process Kvs -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' } |
      Select-Object -First 1
    if ($process) { return $process }
    Start-Sleep -Milliseconds 300
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Wait-FolderDialog([int]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $dialogs = $root.FindAll([System.Windows.Automation.TreeScope]::Children,
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty,'#32770')))
    for ($i = 0; $i -lt $dialogs.Count; $i++) {
      $dialog = $dialogs.Item($i)
      $tree = $dialog.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty,'SysTreeView32')))
      if ($tree) { return $dialog }
    }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Set-FolderDialogPathIfPossible([string]$Path) {
  $dialog = Wait-FolderDialog 8
  if (-not $dialog) { return $false }
  $hwnd = [IntPtr]$dialog.Current.NativeWindowHandle
  [KvExportWin32]::SetForegroundWindow($hwnd) | Out-Null
  $edit = [KvExportWin32]::GetDlgItem($hwnd, 1152)
  if ($edit -ne [IntPtr]::Zero) {
    [KvExportWin32]::SendMessage($edit, $WM_SETTEXT, [IntPtr]::Zero, $Path) | Out-Null
  } else {
    Invoke-KvGuardedClipboardPaste -TargetHwnd $hwnd -Step 'paste export folder path' -Text $Path -ExpectedTitleLike '*' -SleepMs 300
  }
  $ok = [KvExportWin32]::GetDlgItem($hwnd, 1)
  if ($ok -ne [IntPtr]::Zero) {
    [KvExportWin32]::SendMessage($ok, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 800
    return $true
  }
  Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $hwnd -Step 'confirm export folder Enter' -Keys '{ENTER}' -ExpectedTitleLike '*' -SuccessTitleLike @('KV STUDIO*','*') -Action 'Enter confirms folder dialog' -SleepMs 800
  return $true
}

function Click-DefaultDialogOkOrEnter([int]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $dialogs = $root.FindAll([System.Windows.Automation.TreeScope]::Children,
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty,'#32770')))
    for ($i = 0; $i -lt $dialogs.Count; $i++) {
      $dialog = $dialogs.Item($i)
      $tree = $dialog.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty,'SysTreeView32')))
      if ($tree) { continue }
      $hwnd = [IntPtr]$dialog.Current.NativeWindowHandle
      $ok = [KvExportWin32]::GetDlgItem($hwnd, 1)
      if ($ok -ne [IntPtr]::Zero) {
        [KvExportWin32]::SendMessage($ok, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 500
        return $true
      }
      [KvExportWin32]::SetForegroundWindow($hwnd) | Out-Null
      Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $hwnd -Step 'confirm export option dialog Enter' -Keys '{ENTER}' -ExpectedTitleLike '*' -SuccessTitleLike @('KV STUDIO*','*') -Action 'Enter confirms export option dialog' -SleepMs 500
      return $true
    }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $false
}

function Write-ExportResult([bool]$Ok, [string]$ErrorCode, [string]$Message, [object[]]$MnmFiles = @()) {
  [ordered]@{
    ok = $Ok
    error_code = $ErrorCode
    operation = 'export MNM from KV STUDIO'
    project_path = $ProjectPath
    export_dir = $ExportDir
    out_dir = $OutDir
    message = $Message
    mnm_files = @($MnmFiles)
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'export_mnm_result.json') -Encoding UTF8
}

try {
  $ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
  $ExportDir = [IO.Path]::GetFullPath($ExportDir)
  $RestartKvs = ConvertTo-BoolValue $RestartKvs $false
  $projectNeedle = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  $runStart = Get-Date
  Log "start export ProjectPath=$ProjectPath ExportDir=$ExportDir"
  if ($RestartKvs) {
    Get-Process Kvs -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1
  }
  $process = Get-KvProcess $projectNeedle 2
  if (-not $process) {
    Start-Process -FilePath $KvsExe -ArgumentList ('"' + $ProjectPath + '"') | Out-Null
  }
  $process = Get-KvProcess $projectNeedle $TimeoutSeconds
  if (-not $process) { throw 'KV STUDIO main window not found for export.' }
  [KvExportWin32]::ShowWindow($process.MainWindowHandle, 3) | Out-Null
  [KvExportWin32]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
  Start-Sleep -Milliseconds 300
  $fg = Get-ForegroundTitle
  if ($fg.Title -notlike 'KV STUDIO*') { throw "KV STUDIO is not foreground before export. foreground=$($fg.Title)" }

  Invoke-KvGuardedSendKeys -TargetHwnd $process.MainWindowHandle -Step 'export mnm Alt+F' -Keys '%f' -ExpectedTitleLike 'KV STUDIO*' -Action 'Alt+F opens File menu' -SleepMs 250
  Invoke-KvGuardedSendKeys -TargetHwnd $process.MainWindowHandle -Step 'export mnm mnemonic list R' -Keys 'r' -ExpectedTitleLike 'KV STUDIO*' -Action 'R opens mnemonic-list submenu' -SleepMs 250
  Invoke-KvGuardedSendKeys -TargetHwnd $process.MainWindowHandle -Step 'export mnm save S' -Keys 's' -ExpectedTitleLike 'KV STUDIO*' -Action 'S selects mnemonic-list save' -SleepMs 800
  if (-not (Click-DefaultDialogOkOrEnter 8)) {
    Invoke-KvGuardedSendKeys -TargetHwnd $process.MainWindowHandle -Step 'export mnm default OK Enter' -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO*' -Action 'Enter accepts export option dialog' -SleepMs 800
  }
  if (-not (Set-FolderDialogPathIfPossible $ExportDir)) {
    throw "Export folder dialog did not appear or could not be confirmed: $ExportDir"
  }
  Start-Sleep -Seconds 3
  $mnmFiles = @(Get-ChildItem -LiteralPath $ExportDir -Recurse -Filter '*.mnm' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $runStart.AddSeconds(-2) } |
    Select-Object FullName, Length, LastWriteTime)
  if ($mnmFiles.Count -eq 0) { throw "No .mnm files were exported under $ExportDir" }
  $mnmFiles | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'mnm_files.json') -Encoding UTF8
  Write-ExportResult $true '' 'MNM export completed.' $mnmFiles
  exit 0
} catch {
  $message = $_.Exception.ToString()
  Log ('ERROR ' + $message)
  $message | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  $code = 'KV_MNM_EXPORT_FAILED'
  if ($message -like '*foreground*') { $code = 'KV_FOCUS_LOST' }
  if ($message -like '*folder dialog*') { $code = 'KV_EXPORT_FOLDER_DIALOG_MISSING' }
  if ($message -like '*No .mnm files*') { $code = 'KV_MNM_EXPORT_NO_FILES' }
  Write-ExportResult $false $code $message @()
  exit 1
}
