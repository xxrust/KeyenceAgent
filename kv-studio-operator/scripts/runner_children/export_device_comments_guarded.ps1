param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [Parameter(Mandatory=$true)]
  [string]$ExportDir,

  [Parameter(Mandatory=$true)]
  [string]$OutDir,

  [string]$KvsExe = '',
  [string]$CreatedProjectResultPath = '',
  [string]$ProgramName = '',
  [string]$FileBaseName = '',
  [switch]$CloseProjectWhenLaunched,
  [int]$TimeoutSeconds = 120
)

# Export the KV STUDIO device comment list (File > save comments as CSV/TXT) into
# the caller's directory.  Verified route:
#   1. bind the project's main window by command line / window title
#   2. wait until the editor finished loading (clean title, stable)
#   3. open the File menu through UIA and invoke the comment-export menu item
#   4. the modal Save As dialog (#32770) opens with the file name field focused
#   5. verify the dialog state (CSV file type, program selector), type a unique
#      file name, read it back, then press the save button (IDOK, BM_CLICK)
#   6. verify the new file is a current-run comment list, then move it to ExportDir
# Every keyboard action goes through scripts/guards/kv_ui_guard.ps1; targeted
# UIA invocation and dialog-button BM_CLICK follow the existing MNM export route.

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir, $ExportDir | Out-Null
$script:ProcessId = 0
$script:LaunchedByRunner = $false
$script:ClosedProject = $false
$script:DialogEvidence = [ordered]@{}
$script:ArtifactRows = 0
$script:ArtifactSha = ''
$script:RunId = if ($env:KV_WORKFLOW_RUN_ID) { [string]$env:KV_WORKFLOW_RUN_ID } else { Get-Date -Format 'yyyyMMdd_HHmmss' }

function Log([string]$Message) {
  $path = if ($env:KV_WORKFLOW_RUN_LOG) { $env:KV_WORKFLOW_RUN_LOG } else { Join-Path $OutDir 'run.log' }
  @{ timestamp = (Get-Date).ToString('o'); run_id = $env:KV_WORKFLOW_RUN_ID; type = 'export_device_comments_step'; message = $Message } |
    ConvertTo-Json -Compress | Add-Content -LiteralPath $path -Encoding UTF8
}

function Write-Result([bool]$Ok, [string]$Code, [string]$Message, [string]$Artifact = '') {
  [ordered]@{
    ok = $Ok
    error_code = $Code
    message = $Message
    project_path = $ProjectPath
    export_dir = $ExportDir
    out_dir = $OutDir
    artifact_path = $Artifact
    artifact_rows = $script:ArtifactRows
    artifact_sha256 = $script:ArtifactSha
    process_id = $script:ProcessId
    launched_by_runner = $script:LaunchedByRunner
    closed_project = $script:ClosedProject
    dialog_evidence = $script:DialogEvidence
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'device_comments_export_result.json') -Encoding UTF8
}

function Get-Zh([int[]]$Codes) { return (-join ([char[]]$Codes)) }

$script:ZhGlobal = Get-Zh @(0x5168, 0x5C40)          # "global" program entry in the save dialog
$script:ZhSave = Get-Zh @(0x4FDD, 0x5B58)            # save button text
$script:MenuAccelRx = 'CSV/TXT.*[\uFF08(]K[\uFF09)]' # comment export item, accelerator (K)

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
Initialize-KvUiGuard -OutDir $OutDir -CheckpointSubdir 'device_comments'

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class KvCommentExportWin32 {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr hDlg, int nIDDlgItem);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, string lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, StringBuilder lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  public delegate bool EnumChildProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumChildProc lpEnumFunc, IntPtr lParam);
}
"@

$BM_CLICK = 0x00F5
$script:DialogEditId = 1148
$script:DialogFolderComboId = 1137
$script:DialogFileTypeComboId = 1136
$script:DialogSaveButtonId = 1
$script:DialogProgramComboAutomationId = '1435'
$script:DialogFileTypeComboAutomationId = '1136'

function Get-WindowTitle([IntPtr]$Hwnd) {
  $builder = New-Object System.Text.StringBuilder 512
  [void][KvCommentExportWin32]::GetWindowText($Hwnd, $builder, $builder.Capacity)
  return $builder.ToString()
}
function Get-WindowClass([IntPtr]$Hwnd) {
  $builder = New-Object System.Text.StringBuilder 256
  [void][KvCommentExportWin32]::GetClassName($Hwnd, $builder, $builder.Capacity)
  return $builder.ToString()
}
# GetWindowText cannot read another process's control text (it returns an empty
# string for cross-process controls), so the dialog fields are read and written
# with WM_GETTEXT / WM_SETTEXT, which the system marshals across processes.
function Get-ControlText([IntPtr]$ParentHwnd, [int]$ControlId) {
  $target = [KvCommentExportWin32]::GetDlgItem($ParentHwnd, $ControlId)
  if ($target -eq [IntPtr]::Zero) { return '' }
  $buffer = New-Object System.Text.StringBuilder 512
  [void][KvCommentExportWin32]::SendMessage($target, 0x000D, [IntPtr]512, $buffer)
  return $buffer.ToString()
}
function Get-FileNameText([IntPtr]$DialogHwnd) {
  return (Get-ControlText $DialogHwnd $script:DialogEditId)
}
function Set-FileNameText([IntPtr]$DialogHwnd, [string]$Value) {
  $target = [KvCommentExportWin32]::GetDlgItem($DialogHwnd, $script:DialogEditId)
  if ($target -eq [IntPtr]::Zero) { return $false }
  [void][KvCommentExportWin32]::SendMessage($target, 0x000C, [IntPtr]::Zero, $Value)
  return $true
}
function Write-DialogSnapshot([System.Windows.Automation.AutomationElement]$Dialog, [string]$Name) {
  $rows = New-Object System.Collections.Generic.List[object]
  $all = $Dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  for ($i = 0; $i -lt $all.Count; $i++) {
    $e = $all.Item($i)
    $rows.Add([pscustomobject]@{ idx = $i; name = $e.Current.Name; class = $e.Current.ClassName; automation_id = $e.Current.AutomationId; control_type = $e.Current.ControlType.ProgrammaticName }) | Out-Null
  }
  $rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir $Name) -Encoding UTF8
  return $rows
}
function Save-TopWindowSnapshot([string]$Name) {
  $rows = @(Get-Process -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | ForEach-Object {
      [pscustomobject]@{ pid = $_.Id; process = $_.ProcessName; hwnd = $_.MainWindowHandle.ToInt64(); title = $_.MainWindowTitle }
    })
  $rows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir $Name) -Encoding UTF8
}
function Get-KvsProjectProcess([string]$Path, [string]$TitlePattern) {
  $pattern = '(?:^|\s)(?:"' + [regex]::Escape($Path) + '"|' + [regex]::Escape($Path) + ')(?=\s|$)'
  return @(Get-CimInstance Win32_Process -Filter "Name='Kvs.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine -match $pattern } |
    ForEach-Object { Get-Process -Id ([int]$_.ProcessId) -ErrorAction SilentlyContinue })
}

$artifactPath = ''
try {
  $ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
  $ExportDir = [IO.Path]::GetFullPath($ExportDir)
  $OutDir = [IO.Path]::GetFullPath($OutDir)
  New-Item -ItemType Directory -Force -Path $OutDir, $ExportDir | Out-Null
  $KvsExe = Resolve-KvsExe
  if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "ProjectPath not found: $ProjectPath" }
  if (-not (Test-Path -LiteralPath $KvsExe -PathType Leaf)) { throw "KvsExe not found: $KvsExe" }
  $projectDir = Split-Path -Parent $ProjectPath
  $projectNeedle = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  $cleanTitlePattern = '^KV STUDIO.* - \[' + [regex]::Escape($projectNeedle) + '\]$'
  $anyTitlePattern = '^KV STUDIO.* - \[' + [regex]::Escape($projectNeedle) + '(?: \*)?\]$'
  $fileName = if ($FileBaseName) { [string]$FileBaseName } else { 'kv_device_comments_' + $script:RunId }
  if ($fileName -notmatch '\.csv$') { $fileName = $fileName + '.csv' }
  if ($fileName -match '[\\/:*?"<>|]') { throw "KV_COMMENTS_FILENAME_INVALID: $fileName" }
  $expectedArtifact = Join-Path $projectDir $fileName
  $finalArtifact = Join-Path $ExportDir $fileName
  if (Test-Path -LiteralPath $expectedArtifact) { throw "KV_COMMENTS_TARGET_EXISTS: $expectedArtifact" }
  if (Test-Path -LiteralPath $finalArtifact) { throw "KV_COMMENTS_TARGET_EXISTS: $finalArtifact" }
  $runStart = Get-Date
  Log "start ProjectPath=$ProjectPath ExportDir=$ExportDir file=$fileName"

  $processes = @(Get-KvsProjectProcess $ProjectPath $anyTitlePattern)
  if ($CreatedProjectResultPath) {
    $creation = Get-Content -LiteralPath $CreatedProjectResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($creation.ok -isnot [bool] -or -not $creation.ok -or -not $creation.project_path -or [IO.Path]::GetFullPath([string]$creation.project_path) -ine $ProjectPath -or -not $creation.process_id -or -not $creation.process_start_utc) { throw 'KV_COMMENTS_CREATION_EVIDENCE_INVALID' }
    $created = Get-Process -Id ([int]$creation.process_id) -ErrorAction Stop
    if (@($processes | Where-Object { $_.Id -ne $created.Id }).Count) { throw 'KV_COMMENTS_PROJECT_PROCESS_AMBIGUOUS' }
    $processes = @($created)
  }
  if ($processes.Count -gt 1) { throw 'KV_COMMENTS_PROJECT_PROCESS_AMBIGUOUS' }
  $process = $processes | Select-Object -First 1
  if (-not $process) {
    $matching = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match $anyTitlePattern })
    if ($matching.Count -gt 1) { throw 'KV_COMMENTS_PROJECT_PROCESS_AMBIGUOUS' }
    if ($matching.Count -eq 1) { $process = $matching[0] }
  }
  if (-not $process) {
    Log "project is not open; launching $KvsExe"
    $launched = Start-Process -FilePath $KvsExe -WorkingDirectory (Split-Path -Parent $KvsExe) -ArgumentList ('"' + $ProjectPath + '"') -PassThru
    $script:LaunchedByRunner = $true
    $targetId = $launched.Id
  } else {
    $targetId = $process.Id
  }
  $script:ProcessId = $targetId

  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $stableSince = $null
  do {
    $process = Get-Process -Id $targetId -ErrorAction SilentlyContinue
    if (-not $process -or $process.MainWindowHandle -eq 0) { Start-Sleep -Milliseconds 400; continue }
    $title = $process.MainWindowTitle
    if ($title -match $cleanTitlePattern) {
      if ($stableSince -and ((Get-Date) - $stableSince).TotalSeconds -ge 2.5) { break }
      if (-not $stableSince) { $stableSince = Get-Date }
    } else {
      $stableSince = $null
    }
    Start-Sleep -Milliseconds 400
  } while ((Get-Date) -lt $deadline)
  $process = Get-Process -Id $targetId -ErrorAction Stop
  if ($process.MainWindowHandle -eq 0 -or $process.MainWindowTitle -notmatch $cleanTitlePattern) {
    throw "KV_COMMENTS_TARGET_WINDOW_NOT_READY: $($process.MainWindowTitle)"
  }
  $hwnd = [IntPtr]$process.MainWindowHandle
  Log "bound pid=$targetId hwnd=$($hwnd.ToInt64()) title='$($process.MainWindowTitle)'"

  if ([KvCommentExportWin32]::IsIconic($hwnd)) { [void][KvCommentExportWin32]::ShowWindow($hwnd, 9) }
  Save-TopWindowSnapshot 'top_windows_before_export.json'
  # the menu route is a UI action: claim the one allowed foreground activation first
  Assert-KvUiForegroundHwnd -ExpectedHwnd $hwnd -Step 'device comment export menu route' -ExpectedTitleLike 'KV STUDIO*' -AllowSingleRecovery | Out-Null

  # ---- open File > comment export with the documented guarded accelerators ----
  # UIA InvokePattern on this menu item blocks until its modal dialog closes, so the
  # menu is driven by the guarded physical accelerators (Alt+F then K).  UIA only
  # records the menu items as evidence before the keyboard route runs.
  $AE = [System.Windows.Automation.AutomationElement]
  $TS = [System.Windows.Automation.TreeScope]
  $TC = [System.Windows.Automation.ControlType]
  $mainElement = $AE::FromHandle($hwnd)
  $menuBar = $mainElement.FindFirst($TS::Descendants, (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $TC::MenuBar)))
  if ($menuBar) {
    $topItems = $menuBar.FindAll($TS::Children, [System.Windows.Automation.Condition]::TrueCondition)
    if ($topItems.Count -gt 0) {
      $fileMenu = $topItems.Item(0)
      try {
        $fileMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
        Start-Sleep -Milliseconds 600
        $menuRows = New-Object System.Collections.Generic.List[object]
        foreach ($entry in $fileMenu.FindAll($TS::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
          $menuRows.Add([pscustomobject]@{ name = $entry.Current.Name; control_type = $entry.Current.ControlType.ProgrammaticName }) | Out-Null
        }
        $menuRows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'file_menu_items.json') -Encoding UTF8
        Log "file menu items=$($menuRows.Count) comment_export_matches=$(@($menuRows | Where-Object { $_.name -match $script:MenuAccelRx }).Count)"
        $fileMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse()
        Start-Sleep -Milliseconds 300
      } catch {
        Log "menu snapshot failed: $($_.Exception.Message)"
      }
    }
  } else {
    Log 'no UIA menu bar found; using guarded accelerators only'
  }
  Invoke-KvGuardedAltVk -TargetHwnd $hwnd -Step 'device comment export Alt+F' -Vk 0x46 -ExpectedTitleLike 'KV STUDIO*' -SleepMs 500
  Invoke-KvGuardedVkTapCallerOracle -TargetHwnd $hwnd -Step 'device comment export K' -Vk 0x4B -ExpectedTitleLike 'KV STUDIO*' -Action 'K opens the device comment save dialog; the caller waits for the modal dialog' -SleepMs 1200

  # ---- wait for the modal Save As dialog, then verify its state ----
  # The modal dialog is owned by the main window, so it is not reliably returned by
  # RootElement child enumeration.  The guard foreground snapshot identifies it
  # (owned window class #32770 of the bound process, carrying the IDOK button).
  function Get-KvSaveDialogHwnd([int]$ProcessId) {
    $snapshot = Get-KvForegroundSnapshot
    if ($snapshot.process_id -ne $ProcessId) { return [IntPtr]::Zero }
    if ([string]$snapshot.class_name -ne '#32770') { return [IntPtr]::Zero }
    $candidate = [IntPtr]$snapshot.hwnd
    if ([KvCommentExportWin32]::GetDlgItem($candidate, $script:DialogSaveButtonId) -eq [IntPtr]::Zero) { return [IntPtr]::Zero }
    return $candidate
  }
  $dialogHwnd = [IntPtr]::Zero
  $deadline = (Get-Date).AddSeconds(20)
  while ((Get-Date) -lt $deadline) {
    $dialogHwnd = Get-KvSaveDialogHwnd $targetId
    if ($dialogHwnd -ne [IntPtr]::Zero) { break }
    Start-Sleep -Milliseconds 300
  }
  if ($dialogHwnd -eq [IntPtr]::Zero) {
    Save-TopWindowSnapshot 'top_windows_no_save_dialog.json'
    throw 'KV_COMMENTS_SAVE_DIALOG_MISSING'
  }
  $dialog = $AE::FromHandle($dialogHwnd)
  Log "save dialog hwnd=$($dialogHwnd.ToInt64()) title='$(Get-WindowTitle $dialogHwnd)' class='$(Get-WindowClass $dialogHwnd)'"
  $dialogRows = Write-DialogSnapshot -Dialog $dialog -Name 'save_dialog_elements.json'
  $fileType = ''
  $programName = ''
  foreach ($row in $dialogRows) {
    if ($row.automation_id -eq $script:DialogFileTypeComboAutomationId) { $fileType = [string]$row.name }
    if ($row.automation_id -eq $script:DialogProgramComboAutomationId) { $programName = [string]$row.name }
  }
  $folderText = Get-ControlText $dialogHwnd $script:DialogFolderComboId
  $requestedProgram = if ($ProgramName) { [string]$ProgramName } else { $script:ZhGlobal }
  $script:DialogEvidence = [ordered]@{
    dialog_title = (Get-WindowTitle $dialogHwnd)
    file_type = $fileType
    program_selector = $programName
    requested_program = $requestedProgram
    folder_text = $folderText
    expected_folder = (Split-Path -Leaf $projectDir)
    file_name_field_id = $script:DialogEditId
    save_button_id = $script:DialogSaveButtonId
  }
  if ($fileType -notmatch 'CSV') { throw "KV_COMMENTS_FILE_TYPE_UNEXPECTED: $fileType" }
  if ($programName -and $programName -ne $requestedProgram) { throw "KV_COMMENTS_PROGRAM_SELECTOR_MISMATCH: $programName" }

  # ---- type the unique file name into the auto-focused field, then read it back ----
  # The dialog focuses the file name field when it opens, so the documented route is
  # the guarded keyboard one.  If the value does not read back, set it directly.
  Invoke-KvGuardedSendKeys -TargetHwnd $dialogHwnd -Step 'device comment export file name' -Keys $fileName -ExpectedTitleLike '*' -Action 'type the unique comment export file name into the focused file name field' -SleepMs 400
  $readBack = Get-FileNameText $dialogHwnd
  if ($readBack -ne $fileName) {
    Log "file name read-back mismatch ('$readBack'); setting the field text directly"
    [void](Set-FileNameText $dialogHwnd $fileName)
    Start-Sleep -Milliseconds 300
    $readBack = Get-FileNameText $dialogHwnd
  }
  Log "file name read-back='$readBack' expected='$fileName'"
  if ($readBack -ne $fileName) { throw "KV_COMMENTS_FILENAME_READBACK_MISMATCH: '$readBack'" }

  # ---- press save (IDOK) and wait for a current-run artifact ----
  $saveButton = [KvCommentExportWin32]::GetDlgItem($dialogHwnd, $script:DialogSaveButtonId)
  if ($saveButton -eq [IntPtr]::Zero) { throw 'KV_COMMENTS_SAVE_BUTTON_MISSING' }
  Log "clicking save button text='$(Get-WindowTitle $saveButton)'"
  [void][KvCommentExportWin32]::SendMessage($saveButton, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
  $artifact = $null
  $deadline = (Get-Date).AddSeconds(30)
  while ((Get-Date) -lt $deadline) {
    if (Test-Path -LiteralPath $expectedArtifact -PathType Leaf) {
      $candidate = Get-Item -LiteralPath $expectedArtifact
      if ($candidate.Length -gt 0 -and $candidate.LastWriteTime -ge $runStart.AddSeconds(-2)) { $artifact = $candidate; break }
    }
    Start-Sleep -Milliseconds 300
  }
  if (-not $artifact) {
    $recent = @(Get-ChildItem $projectDir -File -Filter '*.csv' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3 | ForEach-Object { $_.Name })
    Log ('artifact missing; recent csv: ' + ($recent -join ', '))
    throw 'KV_COMMENTS_ARTIFACT_MISSING'
  }
  $residualHwnd = Get-KvSaveDialogHwnd $targetId
  if ($residualHwnd -ne [IntPtr]::Zero) {
    Write-DialogSnapshot -Dialog ($AE::FromHandle($residualHwnd)) -Name 'residual_dialog_elements.json' | Out-Null
    throw 'KV_COMMENTS_POST_SAVE_DIALOG'
  }
  $lines = @(Get-Content -LiteralPath $artifact.FullName -Encoding Default)
  $fieldCount = @(($lines[0] -split ',')).Count
  if ($lines.Count -lt 2 -or $fieldCount -lt 9) { throw "KV_COMMENTS_ARTIFACT_INVALID: lines=$($lines.Count) fields=$fieldCount" }
  $script:ArtifactRows = $lines.Count
  Log "artifact=$($artifact.FullName) size=$($artifact.Length) lines=$($lines.Count)"

  Move-Item -LiteralPath $artifact.FullName -Destination $finalArtifact -Force
  $script:ArtifactSha = (Get-FileHash -LiteralPath $finalArtifact -Algorithm SHA256).Hash
  $artifactPath = $finalArtifact

  if ($script:LaunchedByRunner -and $CloseProjectWhenLaunched) {
    $current = Get-Process -Id $targetId -ErrorAction SilentlyContinue
    if ($current -and $current.MainWindowTitle -match $cleanTitlePattern) {
      try {
        Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $hwnd -Step 'close comment export project' -Keys '%{F4}' -ExpectedTitleLike 'KV STUDIO*' -SuccessTitleLike @('KV STUDIO*') -SleepMs 1200
        $script:ClosedProject = $true
      } catch { Log "close failed: $($_.Exception.Message)" }
    } else {
      Log 'project is not clean; leaving it open'
    }
  }

  Write-Result $true '' "Device comment list exported to $finalArtifact" $artifactPath
  exit 0
} catch {
  $message = $_.Exception.ToString()
  Log ('ERROR ' + $message)
  $message | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  $code = 'KV_COMMENTS_EXPORT_FAILED'
  foreach ($pair in @(
      @{ m = 'KV_COMMENTS_PROJECT_PROCESS_AMBIGUOUS'; c = 'KV_COMMENTS_PROJECT_PROCESS_AMBIGUOUS' },
      @{ m = 'KV_COMMENTS_TARGET_WINDOW_NOT_READY'; c = 'KV_COMMENTS_TARGET_WINDOW_NOT_READY' },
      @{ m = 'KV_COMMENTS_SAVE_DIALOG_MISSING'; c = 'KV_COMMENTS_SAVE_DIALOG_MISSING' },
      @{ m = 'KV_COMMENTS_FILE_TYPE_UNEXPECTED'; c = 'KV_COMMENTS_FILE_TYPE_UNEXPECTED' },
      @{ m = 'KV_COMMENTS_PROGRAM_SELECTOR_MISMATCH'; c = 'KV_COMMENTS_PROGRAM_SELECTOR_MISMATCH' },
      @{ m = 'KV_COMMENTS_FILENAME_READBACK_MISMATCH'; c = 'KV_COMMENTS_FILENAME_READBACK_MISMATCH' },
      @{ m = 'KV_COMMENTS_SAVE_BUTTON_MISSING'; c = 'KV_COMMENTS_SAVE_BUTTON_MISSING' },
      @{ m = 'KV_COMMENTS_ARTIFACT_MISSING'; c = 'KV_COMMENTS_ARTIFACT_MISSING' },
      @{ m = 'KV_COMMENTS_ARTIFACT_INVALID'; c = 'KV_COMMENTS_ARTIFACT_INVALID' },
      @{ m = 'KV_COMMENTS_POST_SAVE_DIALOG'; c = 'KV_COMMENTS_POST_SAVE_DIALOG' },
      @{ m = 'KV_COMMENTS_TARGET_EXISTS'; c = 'KV_COMMENTS_TARGET_EXISTS' })) {
    if ($message -like ('*' + $pair.m + '*')) { $code = $pair.c; break }
  }
  Write-Result $false $code $message ''
  exit 1
}
