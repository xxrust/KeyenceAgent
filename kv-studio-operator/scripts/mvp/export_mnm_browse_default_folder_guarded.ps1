param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [Parameter(Mandatory=$true)]
  [string]$ExportDir,

  [Parameter(Mandatory=$true)]
  [string]$OutDir,

  [string]$KvsExe = '',
  [switch]$RestartKvs,
  [switch]$InspectOnly,
  [switch]$AcceptDefaultFolder,
  [int]$TimeoutSeconds = 90
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir, $ExportDir | Out-Null

function Log([string]$Message) {
  $line = (Get-Date -Format s) + ' ' + $Message
  Add-Content -LiteralPath (Join-Path $OutDir 'run.log') -Value $line -Encoding UTF8
  Write-Host $line
}

function Write-Result([bool]$Ok, [string]$Code, [string]$Message, [object[]]$MnmFiles = @()) {
  [ordered]@{
    ok = $Ok
    error_code = $Code
    message = $Message
    project_path = $ProjectPath
    export_dir = $ExportDir
    out_dir = $OutDir
    mnm_files = @($MnmFiles)
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'browse_folder_export_result.json') -Encoding UTF8
}

function Resolve-KvsExe {
  if ($KvsExe) { return $KvsExe }
  $resolver = 'C:\Users\liangyuhang\.codex\skills\keyence-plc-programmer\scripts\resolve_kvstudio_local.ps1'
  if (Test-Path -LiteralPath $resolver -PathType Leaf) {
    $resolved = & powershell -NoProfile -ExecutionPolicy Bypass -File $resolver | ConvertFrom-Json
    return [string]$resolved.KvsExe
  }
  return 'D:\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe'
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$sharedUiGuard = Join-Path (Split-Path -Parent $PSCommandPath) 'kv_ui_guard.ps1'
if (-not (Test-Path -LiteralPath $sharedUiGuard -PathType Leaf)) { throw "Shared KV UI guard script not found: $sharedUiGuard" }
. $sharedUiGuard
Initialize-KvUiGuard -OutDir $OutDir -CheckpointSubdir 'mnm_export'
Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class KvBrowseFolderWin32 {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr hDlg, int nIDDlgItem);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, string lParam);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
}
"@

$BM_CLICK = 0x00F5
$BFFM_SETSELECTIONW = 0x0467

function Get-WindowTitle([IntPtr]$Hwnd) {
  $builder = New-Object System.Text.StringBuilder 512
  [void][KvBrowseFolderWin32]::GetWindowText($Hwnd, $builder, $builder.Capacity)
  return $builder.ToString()
}

function Get-ForegroundRow {
  $hwnd = [KvBrowseFolderWin32]::GetForegroundWindow()
  $titleBuilder = New-Object System.Text.StringBuilder 512
  $classBuilder = New-Object System.Text.StringBuilder 256
  [void][KvBrowseFolderWin32]::GetWindowText($hwnd, $titleBuilder, $titleBuilder.Capacity)
  [void][KvBrowseFolderWin32]::GetClassName($hwnd, $classBuilder, $classBuilder.Capacity)
  $pidValue = [uint32]0
  [void][KvBrowseFolderWin32]::GetWindowThreadProcessId($hwnd, [ref]$pidValue)
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

function Get-ElementRow($Element) {
  $rect = $Element.Current.BoundingRectangle
  [pscustomobject]@{
    name = $Element.Current.Name
    automation_id = $Element.Current.AutomationId
    class_name = $Element.Current.ClassName
    process_id = $Element.Current.ProcessId
    control_type = $Element.Current.ControlType.ProgrammaticName
    enabled = $Element.Current.IsEnabled
    left = [double]$rect.Left
    top = [double]$rect.Top
    width = [double]$rect.Width
    height = [double]$rect.Height
  }
}

function Get-ElementDeepRow($Element) {
  $rect = $Element.Current.BoundingRectangle
  $isSelected = $null
  try {
    $pattern = $null
    if ($Element.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
      $isSelected = $pattern.Current.IsSelected
    }
  } catch {}
  [pscustomobject]@{
    name = $Element.Current.Name
    automation_id = $Element.Current.AutomationId
    class_name = $Element.Current.ClassName
    process_id = $Element.Current.ProcessId
    control_type = $Element.Current.ControlType.ProgrammaticName
    enabled = $Element.Current.IsEnabled
    has_keyboard_focus = $Element.Current.HasKeyboardFocus
    is_keyboard_focusable = $Element.Current.IsKeyboardFocusable
    is_selected = $isSelected
    left = [double]$rect.Left
    top = [double]$rect.Top
    width = [double]$rect.Width
    height = [double]$rect.Height
  }
}

function Save-TopWindowSnapshot([string]$Name) {
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $children = $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
  $rows = @()
  for ($i = 0; $i -lt $children.Count; $i++) { $rows += Get-ElementRow $children.Item($i) }
  $rows | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir $Name) -Encoding UTF8
}

function Save-DialogDescendantsSnapshot([System.Windows.Automation.AutomationElement]$Dialog, [string]$Name) {
  $rows = @()
  $rows += Get-ElementDeepRow $Dialog
  $children = $Dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  for ($i = 0; $i -lt $children.Count; $i++) { $rows += Get-ElementDeepRow $children.Item($i) }
  $rows | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir $Name) -Encoding UTF8
}

function Save-ForegroundSnapshot([string]$Name) {
  Get-ForegroundRow | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir $Name) -Encoding UTF8
}

function Find-BrowseFolderDialog {
  $foreground = Get-ForegroundRow
  if ($foreground.process_name -eq 'Kvs' -and $foreground.class_name -eq '#32770') {
    $foregroundElement = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$foreground.hwnd)
    if ($foregroundElement) {
      $foregroundTree = $foregroundElement.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty,'SysTreeView32'))
      )
      if ($foregroundTree) { return $foregroundElement }
    }
  }
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $dialogCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty,
    '#32770'
  )
  $dialogs = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $dialogCondition)
  $treeCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty,
    'SysTreeView32'
  )
  for ($i = 0; $i -lt $dialogs.Count; $i++) {
    $dialog = $dialogs.Item($i)
    $tree = $dialog.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $treeCondition)
    if ($tree) { return $dialog }
  }
  return $null
}

function Find-KvsNonFolderDialog([int]$ProcessId) {
  $foreground = Get-ForegroundRow
  if ($foreground.process_id -eq $ProcessId -and $foreground.class_name -eq '#32770') {
    $foregroundElement = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$foreground.hwnd)
    if ($foregroundElement) {
      $foregroundTree = $foregroundElement.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty,'SysTreeView32'))
      )
      if (-not $foregroundTree) { return $foregroundElement }
    }
  }
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $dialogCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty,
    '#32770'
  )
  $dialogs = $root.FindAll([System.Windows.Automation.TreeScope]::Children, $dialogCondition)
  $treeCondition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ClassNameProperty,
    'SysTreeView32'
  )
  for ($i = 0; $i -lt $dialogs.Count; $i++) {
    $dialog = $dialogs.Item($i)
    if ($dialog.Current.ProcessId -ne $ProcessId) { continue }
    $tree = $dialog.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $treeCondition)
    if (-not $tree) { return $dialog }
  }
  return $null
}

function Wait-KvsNonFolderDialog([int]$ProcessId, [int]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $dialog = Find-KvsNonFolderDialog -ProcessId $ProcessId
    if ($dialog) { return $dialog }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Invoke-DialogOk([System.Windows.Automation.AutomationElement]$Dialog, [string]$Label) {
  $hwnd = [IntPtr]$Dialog.Current.NativeWindowHandle
  if ($hwnd -eq [IntPtr]::Zero) { throw "$Label dialog has no native HWND." }
  [KvBrowseFolderWin32]::SetForegroundWindow($hwnd) | Out-Null
  Start-Sleep -Milliseconds 250
  $ok = [KvBrowseFolderWin32]::GetDlgItem($hwnd, 1)
  if ($ok -ne [IntPtr]::Zero) {
    Log "click OK on $Label dialog title=$(Get-WindowTitle $hwnd)"
    [KvBrowseFolderWin32]::SendMessage($ok, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
    Start-Sleep -Milliseconds 700
    return
  }
  Log "send Enter on $Label dialog title=$(Get-WindowTitle $hwnd)"
  Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $hwnd -Step "$Label dialog Enter" -Keys '{ENTER}' -ExpectedTitleLike '*' -SuccessTitleLike @('KV STUDIO*','*') -Action "Enter confirms $Label dialog" -SleepMs 700
}

function Invoke-OverwriteYesIfPresent([int]$ProcessId, [int]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $dialog = Find-KvsNonFolderDialog -ProcessId $ProcessId
    if ($dialog) {
      Save-DialogDescendantsSnapshot -Dialog $dialog -Name 'post_export_nonfolder_dialog.json'
      $hwnd = [IntPtr]$dialog.Current.NativeWindowHandle
      $yes = [KvBrowseFolderWin32]::GetDlgItem($hwnd, 6)
      if ($yes -ne [IntPtr]::Zero) {
        Log "click Yes on post-export dialog title=$(Get-WindowTitle $hwnd)"
        [KvBrowseFolderWin32]::SetForegroundWindow($hwnd) | Out-Null
        Start-Sleep -Milliseconds 200
        [KvBrowseFolderWin32]::SendMessage($yes, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 1000
        return $true
      }
      $ok = [KvBrowseFolderWin32]::GetDlgItem($hwnd, 1)
      if ($ok -ne [IntPtr]::Zero) {
        Log "click OK on post-export dialog title=$(Get-WindowTitle $hwnd)"
        [KvBrowseFolderWin32]::SetForegroundWindow($hwnd) | Out-Null
        Start-Sleep -Milliseconds 200
        [KvBrowseFolderWin32]::SendMessage($ok, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 1000
        return $true
      }
      return $false
    }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $false
}

function Wait-BrowseFolderDialog([int]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $dialog = Find-BrowseFolderDialog
    if ($dialog) { return $dialog }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  return $null
}

function Invoke-BrowseFolderSetSelection([System.Windows.Automation.AutomationElement]$Dialog, [string]$Path) {
  $hwnd = [IntPtr]$Dialog.Current.NativeWindowHandle
  if ($hwnd -eq [IntPtr]::Zero) { throw 'Browse folder dialog has no native HWND.' }
  [KvBrowseFolderWin32]::SetForegroundWindow($hwnd) | Out-Null
  Start-Sleep -Milliseconds 250
  Log "BFFM_SETSELECTIONW Path=$Path"
  [KvBrowseFolderWin32]::SendMessage($hwnd, $BFFM_SETSELECTIONW, [IntPtr]1, $Path) | Out-Null
  Start-Sleep -Milliseconds 1200
  Save-DialogDescendantsSnapshot -Dialog $Dialog -Name 'browse_dialog_after_setselection.json'
  Save-ForegroundSnapshot 'foreground_after_setselection.json'
  if ($InspectOnly) {
    Log 'InspectOnly requested; leaving browse-folder dialog open after BFFM_SETSELECTIONW'
    Write-Result $false 'KV_BROWSE_FOLDER_INSPECT_ONLY' 'InspectOnly stopped after setting Browse Folder selection.' @()
    exit 2
  }
  $ok = [KvBrowseFolderWin32]::GetDlgItem($hwnd, 1)
  if ($ok -eq [IntPtr]::Zero) { throw 'Browse folder OK button not found.' }
  [KvBrowseFolderWin32]::SendMessage($ok, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
}

try {
  $ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
  $ExportDir = [IO.Path]::GetFullPath($ExportDir)
  $OutDir = [IO.Path]::GetFullPath($OutDir)
  if (-not $AcceptDefaultFolder -and -not $InspectOnly) {
    throw 'Custom Browse Folder selection is not a stable route. Use -AcceptDefaultFolder through export_mnm_project_copy_default_folder.ps1.'
  }
  $KvsExe = Resolve-KvsExe
  if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "ProjectPath not found: $ProjectPath" }
  if (-not (Test-Path -LiteralPath $KvsExe -PathType Leaf)) { throw "KvsExe not found: $KvsExe" }

  $runStart = Get-Date
  Log "start ProjectPath=$ProjectPath ExportDir=$ExportDir RestartKvs=$RestartKvs"
  if ($RestartKvs) {
    Get-Process Kvs -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  }

  $projectNeedle = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  $process = Get-Process Kvs -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$projectNeedle*" } |
    Select-Object -First 1
  if (-not $process) {
    Start-Process -FilePath $KvsExe -ArgumentList ('"' + $ProjectPath + '"') | Out-Null
  }

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    $process = Get-Process Kvs -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' } |
      Select-Object -First 1
    if ($process -and $process.MainWindowTitle -like "*$projectNeedle*") { break }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  if (-not $process) { throw 'KV STUDIO visible main window not found.' }

  [KvBrowseFolderWin32]::ShowWindow($process.MainWindowHandle, 3) | Out-Null
  [KvBrowseFolderWin32]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
  Start-Sleep -Milliseconds 800
  Save-TopWindowSnapshot 'top_windows_before_prefix.json'
  Save-ForegroundSnapshot 'foreground_before_prefix.json'

  Log 'send known prefix Alt+F,R,S,Enter through guarded key segments'
  Invoke-KvGuardedSendKeys -TargetHwnd $process.MainWindowHandle -Step 'mnm export Alt+F' -Keys '%f' -ExpectedTitleLike 'KV STUDIO*' -Action 'Alt+F opens File menu' -SleepMs 250
  Invoke-KvGuardedSendKeys -TargetHwnd $process.MainWindowHandle -Step 'mnm export mnemonic R' -Keys 'r' -ExpectedTitleLike 'KV STUDIO*' -Action 'R opens mnemonic-list submenu' -SleepMs 250
  Assert-KvUiForegroundHwnd -ExpectedHwnd $process.MainWindowHandle -Step 'mnm export save S precondition' -ExpectedTitleLike 'KV STUDIO*' -AllowSingleRecovery | Out-Null
  [System.Windows.Forms.SendKeys]::SendWait('s')
  Start-Sleep -Milliseconds 700
  Save-TopWindowSnapshot 'top_windows_after_save_s.json'
  Save-ForegroundSnapshot 'foreground_after_save_s.json'
  $optionDialog = Wait-KvsNonFolderDialog -ProcessId $process.Id -Seconds 8
  if ($optionDialog) {
    Save-TopWindowSnapshot 'top_windows_export_option_dialog.json'
    Invoke-DialogOk -Dialog $optionDialog -Label 'export option'
  } else {
    Log 'no export option dialog found after S; continue to browse-folder wait'
  }
  Save-TopWindowSnapshot 'top_windows_after_prefix.json'
  Save-ForegroundSnapshot 'foreground_after_prefix.json'

  $dialog = Wait-BrowseFolderDialog 12
  if (-not $dialog) {
    Save-TopWindowSnapshot 'top_windows_no_browse_folder.json'
    throw 'Browse folder dialog did not appear after known MNM export prefix.'
  }
  Save-TopWindowSnapshot 'top_windows_browse_folder_found.json'

  if ($AcceptDefaultFolder) {
    Save-DialogDescendantsSnapshot -Dialog $dialog -Name 'browse_dialog_default_selection.json'
    Log 'AcceptDefaultFolder requested; confirming current browse-folder selection'
    Invoke-DialogOk -Dialog $dialog -Label 'browse folder default'
  } else {
    Invoke-BrowseFolderSetSelection -Dialog $dialog -Path $ExportDir
  }
  Start-Sleep -Seconds 5
  [void](Invoke-OverwriteYesIfPresent -ProcessId $process.Id -Seconds 2)
  Start-Sleep -Seconds 3
  Save-TopWindowSnapshot 'top_windows_after_folder_ok.json'
  Save-ForegroundSnapshot 'foreground_after_folder_ok.json'

  $mnmFiles = @(Get-ChildItem -LiteralPath $ExportDir -Recurse -Filter '*.mnm' -File -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $runStart.AddSeconds(-2) } |
    Select-Object FullName, Length, LastWriteTime)
  $mnmFiles | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'mnm_files.json') -Encoding UTF8
  if ($mnmFiles.Count -eq 0) { throw "No current-run .mnm files were exported under $ExportDir" }
  Write-Result $true '' 'MNM export completed through browse-folder selection.' $mnmFiles
  exit 0
} catch {
  $message = $_.Exception.ToString()
  Log ('ERROR ' + $message)
  $message | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  $code = 'KV_BROWSE_FOLDER_EXPORT_FAILED'
  if ($message -like '*Browse folder dialog did not appear*') { $code = 'KV_EXPORT_BROWSE_FOLDER_DIALOG_MISSING' }
  if ($message -like '*No current-run .mnm*') { $code = 'KV_MNM_EXPORT_NO_FILES' }
  if ($message -like '*OK button*') { $code = 'KV_EXPORT_BROWSE_FOLDER_OK_MISSING' }
  Write-Result $false $code $message @()
  exit 1
}
