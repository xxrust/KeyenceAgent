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
  $skillsRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))
  $resolver = Join-Path $skillsRoot 'keyence-plc-programmer\scripts\resolve_kvstudio_local.ps1'
  if (Test-Path -LiteralPath $resolver -PathType Leaf) {
    $resolved = & powershell -NoProfile -ExecutionPolicy Bypass -File $resolver | ConvertFrom-Json
    return [string]$resolved.KvsExe
  }
  throw "KV STUDIO resolver not found: $resolver"
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$sharedUiGuard = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'guards\kv_ui_guard.ps1'
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
  public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumChildProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr hDlg, int nIDDlgItem);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, string lParam);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
}
"@

$BM_CLICK = 0x00F5
$textOkZh = -join ([char[]](0x786E, 0x5B9A))
$textYesZh = -join ([char[]](0x662F))
$script:KvDialogOkTexts = @($textOkZh, 'OK')
$script:KvDialogAffirmTexts = @($textOkZh, 'OK', ($textYesZh + '(Y)'), $textYesZh, 'Yes')

function Get-WindowTitle([IntPtr]$Hwnd) {
  $builder = New-Object System.Text.StringBuilder 512
  [void][KvBrowseFolderWin32]::GetWindowText($Hwnd, $builder, $builder.Capacity)
  return $builder.ToString()
}

function Get-WindowClass([IntPtr]$Hwnd) {
  $builder = New-Object System.Text.StringBuilder 256
  [void][KvBrowseFolderWin32]::GetClassName($Hwnd, $builder, $builder.Capacity)
  return $builder.ToString()
}

function Get-DialogChildRows([IntPtr]$DialogHwnd) {
  $children = New-Object System.Collections.Generic.List[object]
  $callback = [KvBrowseFolderWin32+EnumChildProc]{
    param([IntPtr]$childHwnd, [IntPtr]$lParam)
    $children.Add([pscustomobject]@{
      hwnd = $childHwnd.ToInt64()
      text = Get-WindowTitle $childHwnd
      class_name = Get-WindowClass $childHwnd
    }) | Out-Null
    return $true
  }
  [void][KvBrowseFolderWin32]::EnumChildWindows($DialogHwnd, $callback, [IntPtr]::Zero)
  return @($children)
}

function Invoke-DialogButtonByText {
  param(
    [Parameter(Mandatory=$true)][IntPtr]$DialogHwnd,
    [Parameter(Mandatory=$true)][string]$Label,
    [Parameter(Mandatory=$true)][string[]]$ButtonTexts
  )
  $button = @(Get-DialogChildRows $DialogHwnd | Where-Object {
    $_.class_name -eq 'Button' -and ($ButtonTexts -contains $_.text)
  } | Select-Object -First 1)
  if ($button.Count -eq 0) { return $false }
  Log "click '$($button[0].text)' on $Label dialog title=$(Get-WindowTitle $DialogHwnd)"
  [KvBrowseFolderWin32]::SetForegroundWindow($DialogHwnd) | Out-Null
  Start-Sleep -Milliseconds 200
  [KvBrowseFolderWin32]::SendMessage([IntPtr]([int64]$button[0].hwnd), $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
  Start-Sleep -Milliseconds 1000
  return $true
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
  foreach ($id in @(1, 2)) {
    $ok = [KvBrowseFolderWin32]::GetDlgItem($hwnd, $id)
    if ($ok -ne [IntPtr]::Zero) {
      Log "click OK id=$id on $Label dialog title=$(Get-WindowTitle $hwnd)"
      [KvBrowseFolderWin32]::SendMessage($ok, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
      Start-Sleep -Milliseconds 700
      return
    }
  }
  $clickedByText = Invoke-DialogButtonByText -DialogHwnd $hwnd -Label $Label -ButtonTexts $script:KvDialogOkTexts
  if ($clickedByText) {
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
      foreach ($id in @(1, 2)) {
        $ok = [KvBrowseFolderWin32]::GetDlgItem($hwnd, $id)
        if ($ok -ne [IntPtr]::Zero) {
          Log "click OK id=$id on post-export dialog title=$(Get-WindowTitle $hwnd)"
          [KvBrowseFolderWin32]::SetForegroundWindow($hwnd) | Out-Null
          Start-Sleep -Milliseconds 200
          [KvBrowseFolderWin32]::SendMessage($ok, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
          Start-Sleep -Milliseconds 1000
          return $true
        }
      }
      $clickedByText = Invoke-DialogButtonByText -DialogHwnd $hwnd -Label 'post-export' -ButtonTexts $script:KvDialogAffirmTexts
      if ($clickedByText) {
        return $true
      }
      $dialogRowsPath = Join-Path $OutDir 'unknown_post_export_dialog_win32_children.json'
      Get-DialogChildRows $hwnd | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $dialogRowsPath -Encoding UTF8
      throw "Unrecognized post-export dialog remained open. Evidence: $dialogRowsPath"
    }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return $false
}

function Resolve-CleanStateAssertScript {
  $scriptsRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
  $assert = Join-Path $scriptsRoot 'assert_kvstudio_ui_safe.ps1'
  if (-not (Test-Path -LiteralPath $assert -PathType Leaf)) { throw "KV STUDIO clean-state assert script not found: $assert" }
  return $assert
}

function Invoke-KvStudioCleanStatePostcheck {
  $assert = Resolve-CleanStateAssertScript
  $postcheckJson = Join-Path $OutDir 'postcheck_kvstudio_ui_safe.json'
  Log "run clean-state postcheck $assert"
  & powershell -NoProfile -ExecutionPolicy Bypass -File $assert -OutJson $postcheckJson | Tee-Object -FilePath (Join-Path $OutDir 'postcheck_kvstudio_ui_safe.stdout.txt') | Out-Null
  $postcheckExit = $LASTEXITCODE
  if ($postcheckExit -ne 0) {
    throw "KV STUDIO clean-state postcheck failed with exit code $postcheckExit. Evidence: $postcheckJson"
  }
  return $postcheckJson
}

function Invoke-PostExportDialogsUntilClear([int]$ProcessId, [int]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  $handled = 0
  do {
    $dialog = Find-KvsNonFolderDialog -ProcessId $ProcessId
    if (-not $dialog) {
      return $handled
    }
    Save-DialogDescendantsSnapshot -Dialog $dialog -Name ('post_export_dialog_{0:D2}.json' -f ($handled + 1))
    $hwnd = [IntPtr]$dialog.Current.NativeWindowHandle
    if ($hwnd -eq [IntPtr]::Zero) { throw 'Post-export dialog has no native HWND.' }
    $handledOne = $false
    foreach ($id in @(6, 1, 2)) {
      $button = [KvBrowseFolderWin32]::GetDlgItem($hwnd, $id)
      if ($button -ne [IntPtr]::Zero) {
        Log "click post-export dialog button id=$id title=$(Get-WindowTitle $hwnd)"
        [KvBrowseFolderWin32]::SetForegroundWindow($hwnd) | Out-Null
        Start-Sleep -Milliseconds 200
        [KvBrowseFolderWin32]::SendMessage($button, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
        Start-Sleep -Milliseconds 1000
        $handled += 1
        $handledOne = $true
        break
      }
    }
    if ($handledOne) { continue }
    $clickedByText = Invoke-DialogButtonByText -DialogHwnd $hwnd -Label 'post-export' -ButtonTexts $script:KvDialogAffirmTexts
    if ($clickedByText) {
      $handled += 1
      continue
    }
    $dialogRowsPath = Join-Path $OutDir ('unknown_post_export_dialog_{0:D2}_win32_children.json' -f ($handled + 1))
    Get-DialogChildRows $hwnd | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $dialogRowsPath -Encoding UTF8
    throw "Unrecognized post-export dialog remained open. Evidence: $dialogRowsPath"
  } while ((Get-Date) -lt $deadline)
  return $handled
}

function Wait-CurrentRunMnmFiles([string]$Root, [datetime]$Since, [int]$Seconds) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $files = @(Get-ChildItem -LiteralPath $Root -Recurse -Filter '*.mnm' -File -ErrorAction SilentlyContinue |
      Where-Object { $_.LastWriteTime -ge $Since.AddSeconds(-2) } |
      Select-Object FullName, Length, LastWriteTime)
    if ($files.Count -gt 0) { return $files }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  return @()
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

try {
  $ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
  $ExportDir = [IO.Path]::GetFullPath($ExportDir)
  $OutDir = [IO.Path]::GetFullPath($OutDir)
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

  Log 'send known prefix Alt+F,R,S through guarded physical VK uppercase accelerators'
  Invoke-KvGuardedAltVk -TargetHwnd $process.MainWindowHandle -Step 'mnm export Alt+F' -Vk 0x46 -ExpectedTitleLike 'KV STUDIO*' -SleepMs 300
  Invoke-KvGuardedVkTap -TargetHwnd $process.MainWindowHandle -Step 'mnm export mnemonic R' -Vk 0x52 -ExpectedTitleLike 'KV STUDIO*' -SleepMs 300
  Invoke-KvGuardedVkTapCallerOracle -TargetHwnd $process.MainWindowHandle -Step 'mnm export save S' -Vk 0x53 -ExpectedTitleLike 'KV STUDIO*' -Action 'S starts mnemonic-list export; caller waits for option or browse dialog' -SleepMs 900
  Save-TopWindowSnapshot 'top_windows_after_save_s.json'
  Save-ForegroundSnapshot 'foreground_after_save_s.json'
  $optionDialog = Wait-KvsNonFolderDialog -ProcessId $process.Id -Seconds 8
  if ($optionDialog) {
    Save-TopWindowSnapshot 'top_windows_export_option_dialog.json'
    Invoke-DialogOk -Dialog $optionDialog -Label 'export option'
    Start-Sleep -Milliseconds 300
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

  Save-DialogDescendantsSnapshot -Dialog $dialog -Name 'browse_dialog_default_selection.json'
  Log 'confirm current browse-folder selection'
  Invoke-DialogOk -Dialog $dialog -Label 'browse folder default'
  Start-Sleep -Seconds 2
  [void](Invoke-PostExportDialogsUntilClear -ProcessId $process.Id -Seconds 12)
  Save-TopWindowSnapshot 'top_windows_after_folder_ok.json'
  Save-ForegroundSnapshot 'foreground_after_folder_ok.json'

  $mnmFiles = @(Wait-CurrentRunMnmFiles -Root $ExportDir -Since $runStart -Seconds 8)
  $mnmFiles | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'mnm_files.json') -Encoding UTF8
  if ($mnmFiles.Count -eq 0) { throw "No current-run .mnm files were exported under $ExportDir" }
  Invoke-KvStudioCleanStatePostcheck | Out-Null
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
