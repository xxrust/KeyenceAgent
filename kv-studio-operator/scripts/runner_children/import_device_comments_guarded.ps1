param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  # Full path of the CSV/TXT comment table to read into the project.  The file is
  # produced by export_device_comments_guarded.ps1 (or authored by hand in the
  # exact same shape): "<device>,,<comment1>,<comment2>,...,<comment8>,".
  [Parameter(Mandatory=$true)]
  [string]$CommentsPath,

  [Parameter(Mandatory=$true)]
  [string]$OutDir,

  [string]$KvsExe = '',
  [string]$CreatedProjectResultPath = '',
  [int]$TimeoutSeconds = 180,
  [switch]$SaveAfterImport,
  [switch]$CloseProjectWhenLaunched,
  [switch]$PlanOnly
)

# Import a device-comment table into an open KV STUDIO project through
# "File(F) > Read device comments in CSV/TXT format(Q)".
#
# Verified menu evidence (2026-11-03, KV STUDIO 12G / KV-X310 project): the File
# menu lists both directions of the comment table --
#   "save device comments in CSV/TXT format (K)..."    (export, see export_device_comments_guarded.ps1)
#   "read device comments in CSV/TXT format (Q)..."     (import, this runner)
# so the import is the documented counterpart of the already-verified export.
#
# Route (every input goes through scripts/guards/kv_ui_guard.ps1):
#   1. validate the input table off-UI (shape + device syntax + duplicates) so a
#      malformed file can never reach KV STUDIO;
#   2. bind the single KV STUDIO process that owns $ProjectPath (never guess by
#      title prefix: modal dialogs can be titled "KV STUDIO" as well);
#   3. wait for a clean, stable editor title, then claim the one allowed
#      foreground activation of this session;
#   4. Alt+F then Q through the guarded physical-accelerator helpers;
#   5. wait for the modal Open dialog (#32770 owned by the bound process), dump
#      its element tree as evidence, and verify the file-type selector says CSV;
#   6. write the absolute path into the file-name field with WM_SETTEXT (works
#      across processes, unlike typing into a dialog that may not own focus) and
#      read it back with WM_GETTEXT before pressing the Open button (IDOK);
#   7. handle the post-import dialogs by strict allow-list.  An unknown dialog is
#      a hard failure with a window snapshot -- never "click the default button
#      and hope";
#   8. optionally Ctrl+S so the comments land in the .cm1 comment bank, then
#      report everything as JSON.
#
# The runner is deliberately fail-closed: it never deletes comments and never
# guesses a dialog button.  Callers verify the result by re-exporting the
# comment table and diffing it (see workflows/import_kv_device_comments.ps1).

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$script:ProcessId = 0
$script:LaunchedByRunner = $false
$script:ClosedProject = $false
$script:DialogEvidence = [ordered]@{}
$script:ImportedRows = 0
$script:CommentsSha = ''
$script:Saved = $false
$script:RunId = if ($env:KV_WORKFLOW_RUN_ID) { [string]$env:KV_WORKFLOW_RUN_ID } else { Get-Date -Format 'yyyyMMdd_HHmmss' }

function Log([string]$Message) {
  $path = if ($env:KV_WORKFLOW_RUN_LOG) { $env:KV_WORKFLOW_RUN_LOG } else { Join-Path $OutDir 'run.log' }
  @{ timestamp = (Get-Date).ToString('o'); run_id = $env:KV_WORKFLOW_RUN_ID; type = 'import_device_comments_step'; message = $Message } |
    ConvertTo-Json -Compress | Add-Content -LiteralPath $path -Encoding UTF8
}

function Write-Result([bool]$Ok, [string]$Code, [string]$Message) {
  [ordered]@{
    ok = $Ok
    error_code = $Code
    message = $Message
    project_path = $ProjectPath
    comments_path = $CommentsPath
    comments_sha256 = $script:CommentsSha
    rows_in_file = $script:ImportedRows
    out_dir = $OutDir
    process_id = $script:ProcessId
    launched_by_runner = $script:LaunchedByRunner
    saved = $script:Saved
    closed_project = $script:ClosedProject
    dialog_evidence = $script:DialogEvidence
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'device_comments_import_result.json') -Encoding UTF8
}

function Get-Zh([int[]]$Codes) { return (-join ([char[]]$Codes)) }

$script:ZhGlobal = Get-Zh @(0x5168, 0x5C40)   # "global" program selector value (same literal the export route reads)
# Dialog classification words are built from code points on purpose: KV STUDIO
# scripts in this repository stay pure ASCII so Windows PowerShell 5.1 cannot
# mis-decode a source file that has no BOM.
$script:ZhDone = Get-Zh @(0x5B8C, 0x6210)              # done
$script:ZhRead = Get-Zh @(0x8BFB, 0x53D6)              # read
$script:ZhReadIn = Get-Zh @(0x8BFB, 0x5165)            # read in
$script:ZhImported = Get-Zh @(0x5DF2, 0x5BFC, 0x5165)  # imported
$script:ZhError = Get-Zh @(0x9519, 0x8BEF)             # error
$script:ZhFail = Get-Zh @(0x5931, 0x8D25)              # failure
$script:ZhCannot = Get-Zh @(0x4E0D, 0x80FD)            # cannot
$script:ZhNoWay = Get-Zh @(0x65E0, 0x6CD5)             # unable
$script:ZhOverwrite = Get-Zh @(0x8986, 0x76D6)         # overwrite
$script:ZhQuestion = Get-Zh @(0x662F, 0x5426)          # "whether ...?"
$script:ZhOk = Get-Zh @(0x786E, 0x5B9A)                # "OK/confirm" button label
$script:ZhYes = Get-Zh @(0x662F)                       # "Yes" button label prefix

# ---------------------------------------------------------------------------
# off-UI validation of the comment table
# ---------------------------------------------------------------------------
# KV STUDIO writes the table with the system ANSI code page (GBK on a Chinese
# Windows), so the file is read with the same encoding it was written with.
function Read-CommentTable([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "KV_COMMENTS_IMPORT_FILE_MISSING: $Path" }
  $bytes = [IO.File]::ReadAllBytes($Path)
  if ($bytes.Length -eq 0) { throw 'KV_COMMENTS_IMPORT_FILE_EMPTY' }
  $encoding = [Text.Encoding]::GetEncoding(0)   # ANSI code page, same as the exporter
  $text = $encoding.GetString($bytes)
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
  $lines = @($text -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 })
  if ($lines.Count -lt 2) { throw "KV_COMMENTS_IMPORT_TOO_FEW_LINES: $($lines.Count)" }

  $header = @($lines[0] -split ',')
  # The exporter/save dialog always writes the eight comment banks as columns
  # 3..10 (indexes 2..9), so a table with a different shape is not a KV comment
  # table and must not be imported.
  if ($header.Count -lt 9) { throw "KV_COMMENTS_IMPORT_HEADER_INVALID: fields=$($header.Count)" }
  # A comment table always starts with two empty columns (device, spare) followed
  # by the eight comment banks, so the shape is checked structurally instead of by
  # matching localised header text.
  if ([string]$header[0] -ne '' -or [string]$header[1] -ne '') { throw "KV_COMMENTS_IMPORT_HEADER_UNEXPECTED: '$($header[0])','$($header[1])'" }
  if (-not [string]$header[2]) { throw "KV_COMMENTS_IMPORT_HEADER_UNEXPECTED: empty comment bank header" }

  $rows = New-Object System.Collections.Generic.List[object]
  $seen = New-Object 'System.Collections.Generic.HashSet[string]'
  for ($i = 1; $i -lt $lines.Count; $i++) {
    $fields = @($lines[$i] -split ',')
    $device = ([string]$fields[0]).Trim()
    if (-not $device) { throw "KV_COMMENTS_IMPORT_DEVICE_MISSING: line=$($i + 1)" }
    # Device syntax: area letters followed by digits, optionally a member index
    # (e.g. R30000, DM1000, MR1200.3, CM700).  A wrong-shaped token means the
    # file is not a KV comment table.
    # Device syntax: area letters, then a number that may contain hex digits
    # (B0B, W0F4) or a bit member (DM10090.0).  Requiring a leading digit after the
    # area keeps pure words such as 'ABC' from passing as a device.
    if ($device -notmatch '^[A-Za-z]{1,3}[0-9][0-9A-Fa-f]*(\.[0-9A-Fa-f]+)?$') { throw "KV_COMMENTS_IMPORT_DEVICE_INVALID: '$device' line=$($i + 1)" }
    if (-not $seen.Add($device.ToUpperInvariant())) { throw "KV_COMMENTS_IMPORT_DEVICE_DUPLICATE: '$device'" }
    $comments = @()
    for ($c = 2; $c -lt [Math]::Min($fields.Count, 10); $c++) {
      $value = ([string]$fields[$c]).Trim()
      if ($value) { $comments += $value }
    }
    $rows.Add([pscustomobject]@{ line = $i + 1; device = $device; comments = $comments }) | Out-Null
  }
  # toArray(), not @($rows): Windows PowerShell 5.1 raises "Argument types do not
  # match" when @() wraps a List[object] inside a hashtable literal.
  return [pscustomobject]@{ lines = $lines; header = $header; rows = $rows.ToArray() }
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
$sharedUiGuard = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'guards\kv_ui_guard.ps1'
if (-not (Test-Path -LiteralPath $sharedUiGuard -PathType Leaf)) { throw "Shared KV UI guard script not found: $sharedUiGuard" }
. $sharedUiGuard

Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class KvCommentImportWin32 {
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr hDlg, int nIDDlgItem);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, string lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetWindow(IntPtr hWnd, uint uCmd);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}
"@

$BM_CLICK = 0x00F5
$WM_SETTEXT = 0x000C
$WM_GETTEXT = 0x000D
$script:DialogEditId = 1148            # file-name field of the standard MFC open dialog
$script:DialogFileTypeComboId = 1136   # file-type selector
$script:DialogProgramComboId = 1435     # program selector ("global" for device comments)
$script:DialogOpenButtonId = 1         # IDOK == "Open"

function Get-WindowTitle([IntPtr]$Hwnd) {
  $builder = New-Object System.Text.StringBuilder 512
  [void][KvCommentImportWin32]::GetWindowText($Hwnd, $builder, $builder.Capacity)
  return $builder.ToString()
}
function Get-WindowClass([IntPtr]$Hwnd) {
  $builder = New-Object System.Text.StringBuilder 256
  [void][KvCommentImportWin32]::GetClassName($Hwnd, $builder, $builder.Capacity)
  return $builder.ToString()
}
# Cross-process controls cannot be read with GetWindowText, so the dialog fields
# are read/written with WM_GETTEXT / WM_SETTEXT, which the OS marshals.
function Get-ControlText([IntPtr]$ParentHwnd, [int]$ControlId) {
  $target = [KvCommentImportWin32]::GetDlgItem($ParentHwnd, $ControlId)
  if ($target -eq [IntPtr]::Zero) { return '' }
  $buffer = New-Object System.Text.StringBuilder 1024
  [void][KvCommentImportWin32]::SendMessage($target, $WM_GETTEXT, [IntPtr]1024, $buffer)
  return $buffer.ToString()
}
# The file-name field of a modern MFC open dialog is ComboBoxEx32 > ComboBox >
# Edit, all three sharing control id 1148.  GetDlgItem(id) returns the OUTER
# ComboBoxEx32, and WM_SETTEXT on that container does nothing (read back was
# empty on the first live attempt), so the real Edit child has to be resolved by
# walking the dialog's descendants.
function Get-DialogChildren([IntPtr]$Parent) {
  $list = New-Object System.Collections.Generic.List[object]
  $callback = [KvCommentImportWin32+EnumWindowsProc] {
    param($hWnd, $lParam)
    $list.Add([pscustomobject]@{
        hwnd  = [IntPtr]$hWnd
        class = (Get-WindowClass $hWnd)
        id    = ([KvCommentImportWin32]::GetDlgCtrlID([IntPtr]$hWnd))
      }) | Out-Null
    return $true
  }
  [void][KvCommentImportWin32]::EnumChildWindows($Parent, $callback, [IntPtr]::Zero)
  return $list.ToArray()
}
# Buttons of a DirectUI message box are not child HWNDs: they are UIA Button
# elements inside a #32770 shell.  Enumerating them through UIA is the only
# reliable route, and invoking them through UIA InvokePattern is what the KV
# dialog handlers for other workflows do as well.
function Get-DialogButtons([System.Windows.Automation.AutomationElement]$Dialog) {
  $buttons = New-Object System.Collections.Generic.List[object]
  $condition = New-Object System.Windows.Automation.PropertyCondition(
    [System.Windows.Automation.AutomationElement]::ControlTypeProperty,
    [System.Windows.Automation.ControlType]::Button)
  $found = $Dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition)
  for ($i = 0; $i -lt $found.Count; $i++) { $buttons.Add($found.Item($i)) | Out-Null }
  return $buttons.ToArray()
}
# Accepts the affirmative button of an information box only.  A Cancel/No button
# would be a different decision, so it is never clicked here: the caller's text
# allow-list already rejected anything that is not a plain success message.
function Invoke-DialogButton([object[]]$Buttons) {
  $affirmative = @($script:ZhOk, $script:ZhYes, 'OK', 'Ok')
  foreach ($button in @($Buttons)) {
    $name = [string]$button.Current.Name
    $match = $false
    foreach ($candidate in $affirmative) { if ($name -and $name.StartsWith($candidate)) { $match = $true; break } }
    if (-not $match) { continue }
    $pattern = $null
    if ($button.TryGetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern, [ref]$pattern)) {
      $pattern.Invoke()
      Log "invoked dialog button '$name' through UIA InvokePattern"
      return $true
    }
  }
  return $false
}
function Find-FileNameEdit([IntPtr]$DialogHwnd) {  $children = @(Get-DialogChildren $DialogHwnd)
  $preferred = @($children | Where-Object { $_.class -eq 'Edit' -and $_.id -eq $script:DialogEditId } | Select-Object -First 1)
  if ($preferred.Count -eq 0) {
    $anyEdit = @($children | Where-Object { $_.class -eq 'Edit' } | Select-Object -First 1)
    if ($anyEdit.Count -eq 0) { return [IntPtr]::Zero }
    return $anyEdit[0].hwnd
  }
  return $preferred[0].hwnd
}
function Get-FileNameText([IntPtr]$DialogHwnd) {
  # Reading a file-name field back is provider-specific.  On the KV STUDIO
  # comment-read dialog every Win32 candidate (Edit#1148, ComboBox#1148,
  # ComboBoxEx32#1148) answers WM_GETTEXT with an empty string although the field
  # visibly holds the path, so UIA is tried first: the UIA proxy marshals the value
  # out of the target process where a raw WM_GETTEXT does not.
  try {
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($DialogHwnd)
    $byClass = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty, 'Edit')
    $byId = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, [string]$script:DialogEditId)
    $condition = New-Object System.Windows.Automation.AndCondition($byClass, $byId)
    $element = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $condition)
    if ($element) {
      $pattern = $null
      if ($element.TryGetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern, [ref]$pattern)) {
        $value = [string]$pattern.Current.Value
        Log "file name readback (UIA ValuePattern) -> '$value'"
        if ($value) { return $value }
      }
      if ($element.Current.Name) {
        Log "file name readback (UIA Name) -> '$($element.Current.Name)'"
        return [string]$element.Current.Name
      }
      Log 'file name readback (UIA) -> empty'
    } else {
      Log 'file name readback (UIA) -> no Edit#1148 element'
    }
  } catch {
    Log "UIA readback failed: $($_.Exception.Message)"
  }
  return ''
}
function Set-FileNameText([IntPtr]$DialogHwnd, [string]$Value) {
  $edit = Find-FileNameEdit $DialogHwnd
  if ($edit -eq [IntPtr]::Zero) { return $false }
  [void][KvCommentImportWin32]::SendMessage($edit, $WM_SETTEXT, [IntPtr]::Zero, $Value)
  return $true
}
function Write-DialogSnapshot([System.Windows.Automation.AutomationElement]$Dialog, [string]$Name) {
  $rows = New-Object System.Collections.Generic.List[object]
  $all = $Dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
  for ($i = 0; $i -lt $all.Count; $i++) {
    $e = $all.Item($i)
    $rows.Add([pscustomobject]@{
        idx           = $i
        name          = $e.Current.Name
        class         = $e.Current.ClassName
        automation_id = $e.Current.AutomationId
        control_type  = $e.Current.ControlType.ProgrammaticName
      }) | Out-Null
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
# Every top-level #32770 of the bound process: a KV modal is an owned popup, so it
# is not reliably reachable through RootElement enumeration.
function Get-OwnedDialogs([int]$ProcessId) {
  $result = New-Object System.Collections.Generic.List[object]
  $callback = [KvCommentImportWin32+EnumWindowsProc] {
    param($hWnd, $lParam)
    $owner = 0
    [void][KvCommentImportWin32]::GetWindowThreadProcessId($hWnd, [ref]$owner)
    if ($owner -eq $ProcessId) {
      $class = Get-WindowClass $hWnd
      # Only on-screen popups count: KV STUDIO keeps long-lived invisible helper
      # windows (the interpreter frame is one of them) that are not dialogs the
      # user could ever answer, and treating them as dialogs makes every run look
      # like it left a window behind.
      if ($class -eq '#32770' -and [KvCommentImportWin32]::IsWindowVisible($hWnd)) {
        $result.Add([pscustomobject]@{
            hwnd    = [IntPtr]$hWnd
            title   = (Get-WindowTitle $hWnd)
            enabled = [KvCommentImportWin32]::IsWindowEnabled($hWnd)
            has_ok  = ([KvCommentImportWin32]::GetDlgItem([IntPtr]$hWnd, $script:DialogOpenButtonId) -ne [IntPtr]::Zero)
          }) | Out-Null
      }
    }
    return $true
  }
  [void][KvCommentImportWin32]::EnumWindows($callback, [IntPtr]::Zero)
  return $result.ToArray()
}
function Find-OpenDialog([int]$ProcessId) {
  foreach ($dialog in @(Get-OwnedDialogs $ProcessId)) {
    # the comment-table open dialog carries a file-name edit and an IDOK button
    if ($dialog.has_ok -and $dialog.title -and (Find-FileNameEdit $dialog.hwnd) -ne [IntPtr]::Zero) { return $dialog }
  }
  return $null
}

$AE = [System.Windows.Automation.AutomationElement]
$TC = [System.Windows.Automation.ControlType]

# ---------------------------------------------------------------------------
# step 0: validate the table off-UI
# ---------------------------------------------------------------------------
try {
  $CommentsPath = [IO.Path]::GetFullPath($CommentsPath)
  $ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
  $OutDir = [IO.Path]::GetFullPath($OutDir)

  $table = Read-CommentTable $CommentsPath
  $script:ImportedRows = @($table.rows).Count
  $script:CommentsSha = (Get-FileHash -LiteralPath $CommentsPath -Algorithm SHA256).Hash
  $commented = @($table.rows | Where-Object { @($_.comments).Count -gt 0 }).Count
  Log "table validated: file=$CommentsPath rows=$($script:ImportedRows) rows_with_comment=$commented sha256=$($script:CommentsSha)"
  if ($commented -eq 0) { throw 'KV_COMMENTS_IMPORT_NO_COMMENTS' }

  if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "ProjectPath not found: $ProjectPath" }
  if ($PlanOnly) {
    # PlanOnly proves the input contract without touching the desktop at all.
    Write-Result $true '' "plan only: $($script:ImportedRows) rows would be read from $CommentsPath"
    exit 0
  }

  $KvsExe = if ($KvsExe) { $KvsExe } else {
    $skillsRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSCommandPath)))
    $resolver = Join-Path $skillsRoot 'keyence-plc-programmer\scripts\resolve_kvstudio_local.ps1'
    if (-not (Test-Path -LiteralPath $resolver -PathType Leaf)) { throw "KV STUDIO resolver not found: $resolver" }
    $resolved = & powershell -NoProfile -ExecutionPolicy Bypass -File $resolver | ConvertFrom-Json
    [string]$resolved.KvsExe
  }
  if (-not (Test-Path -LiteralPath $KvsExe -PathType Leaf)) { throw "KvsExe not found: $KvsExe" }

  $projectNeedle = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  $cleanTitlePattern = '^KV STUDIO.* - \[' + [regex]::Escape($projectNeedle) + '\]$'
  $anyTitlePattern = '^KV STUDIO.* - \[' + [regex]::Escape($projectNeedle) + '(?: \*)?\]$'

  Initialize-KvUiGuard -OutDir $OutDir -CheckpointSubdir 'device_comments_import'

  # -------------------------------------------------------------------------
  # step 1: bind exactly one KV STUDIO process for this project
  # -------------------------------------------------------------------------
  $processes = @(Get-KvsProjectProcess $ProjectPath $anyTitlePattern)
  if ($CreatedProjectResultPath) {
    $creation = Get-Content -LiteralPath $CreatedProjectResultPath -Raw -Encoding UTF8 | ConvertFrom-Json
    if ($creation.ok -isnot [bool] -or -not $creation.ok -or -not $creation.project_path -or
      [IO.Path]::GetFullPath([string]$creation.project_path) -ine $ProjectPath) { throw 'KV_COMMENTS_IMPORT_CREATION_EVIDENCE_INVALID' }
    $processes = @(Get-Process -Id ([int]$creation.process_id) -ErrorAction Stop)
  }
  if ($processes.Count -gt 1) { throw 'KV_COMMENTS_IMPORT_PROJECT_PROCESS_AMBIGUOUS' }
  $process = $processes | Select-Object -First 1
  if (-not $process) {
    $matching = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match $anyTitlePattern })
    if ($matching.Count -gt 1) { throw 'KV_COMMENTS_IMPORT_PROJECT_PROCESS_AMBIGUOUS' }
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

  # wait for the editor to finish loading: a clean title without "*" that stays
  # stable for 2.5 s (importing into a half-loaded project would bind the wrong
  # window and lose the accelerator)
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $stableSince = $null
  do {
    $process = Get-Process -Id $targetId -ErrorAction SilentlyContinue
    if (-not $process -or $process.MainWindowHandle -eq 0) { Start-Sleep -Milliseconds 400; continue }
    if ($process.MainWindowTitle -match $cleanTitlePattern) {
      if ($stableSince -and ((Get-Date) - $stableSince).TotalSeconds -ge 2.5) { break }
      if (-not $stableSince) { $stableSince = Get-Date }
    } else {
      $stableSince = $null
    }
    Start-Sleep -Milliseconds 400
  } while ((Get-Date) -lt $deadline)
  $process = Get-Process -Id $targetId -ErrorAction Stop
  if ($process.MainWindowHandle -eq 0 -or $process.MainWindowTitle -notmatch $cleanTitlePattern) {
    throw "KV_COMMENTS_IMPORT_TARGET_WINDOW_NOT_READY: $($process.MainWindowTitle)"
  }
  $hwnd = [IntPtr]$process.MainWindowHandle
  Log "bound pid=$targetId hwnd=$($hwnd.ToInt64()) title='$($process.MainWindowTitle)'"

  if ([KvCommentImportWin32]::IsIconic($hwnd)) { [void][KvCommentImportWin32]::ShowWindow($hwnd, 9) }
  Save-TopWindowSnapshot 'top_windows_before_import.json'
  Assert-KvUiForegroundHwnd -ExpectedHwnd $hwnd -Step 'device comment import menu route' -ExpectedTitleLike 'KV STUDIO*' -AllowSingleRecovery | Out-Null

  # -------------------------------------------------------------------------
  # step 2: File(F) > Read device comments in CSV/TXT format(Q)
  # -------------------------------------------------------------------------
  # UIA records the menu items as evidence first; the menu itself is driven by
  # the guarded physical accelerators because UIA Invoke on these items blocks
  # until the modal dialog is closed.
  try {
    $mainElement = $AE::FromHandle($hwnd)
    $menuBar = $mainElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants, (New-Object System.Windows.Automation.PropertyCondition($AE::ControlTypeProperty, $TC::MenuBar)))
    if ($menuBar) {
      $fileMenu = $menuBar.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition).Item(0)
      $fileMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
      Start-Sleep -Milliseconds 600
      $menuRows = New-Object System.Collections.Generic.List[object]
      foreach ($entry in $fileMenu.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
        $menuRows.Add([pscustomobject]@{ name = $entry.Current.Name; control_type = $entry.Current.ControlType.ProgrammaticName }) | Out-Null
      }
      $menuRows | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'file_menu_items.json') -Encoding UTF8
      $script:DialogEvidence['comment_import_menu_item'] = @($menuRows | Where-Object { $_.name -match 'CSV/TXT.*[\uFF08(]Q[\uFF09)]' }).Count
      Log "file menu items=$($menuRows.Count) import_matches=$($script:DialogEvidence['comment_import_menu_item'])"
      $fileMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Collapse()
      Start-Sleep -Milliseconds 300
    }
  } catch {
    Log "menu snapshot failed: $($_.Exception.Message)"
  }
  Invoke-KvGuardedAltVk -TargetHwnd $hwnd -Step 'device comment import Alt+F' -Vk 0x46 -ExpectedTitleLike 'KV STUDIO*' -SleepMs 500
  Invoke-KvGuardedVkTapCallerOracle -TargetHwnd $hwnd -Step 'device comment import Q' -Vk 0x51 -ExpectedTitleLike 'KV STUDIO*' -Action 'Q opens the device comment read dialog; the caller waits for the modal dialog' -SleepMs 1200

  # -------------------------------------------------------------------------
  # step 3: fill and confirm the modal Open dialog
  # -------------------------------------------------------------------------
  $dialogInfo = $null
  $deadline = (Get-Date).AddSeconds(20)
  while ((Get-Date) -lt $deadline) {
    $dialogInfo = Find-OpenDialog $targetId
    if ($dialogInfo) { break }
    Start-Sleep -Milliseconds 300
  }
  if (-not $dialogInfo) {
    Save-TopWindowSnapshot 'top_windows_no_open_dialog.json'
    throw 'KV_COMMENTS_IMPORT_DIALOG_MISSING'
  }
  $dialogHwnd = $dialogInfo.hwnd
  $dialogElement = $AE::FromHandle($dialogHwnd)
  $dialogRows = Write-DialogSnapshot -Dialog $dialogElement -Name 'open_dialog_elements.json'
  $fileType = ''
  foreach ($row in $dialogRows) {
    if ([string]$row.automation_id -eq [string]$script:DialogFileTypeComboId) { $fileType = [string]$row.name }
  }
  $script:DialogEvidence['dialog_title'] = (Get-WindowTitle $dialogHwnd)
  $script:DialogEvidence['file_type'] = $fileType
  $script:DialogEvidence['file_name_field_id'] = $script:DialogEditId
  $script:DialogEvidence['open_button_id'] = $script:DialogOpenButtonId
  $script:DialogEvidence['dialog_children'] = @(Get-DialogChildren $dialogHwnd | ForEach-Object { '{0}#{1}' -f $_.class, $_.id })
  # The dialog asks for the program whose comment bank is read; the verified
  # default for a global device-comment table is the global program.
  $programSelector = Get-ControlText $dialogHwnd $script:DialogProgramComboId
  $script:DialogEvidence['program_selector'] = $programSelector
  Log "open dialog hwnd=$($dialogHwnd.ToInt64()) title='$(Get-WindowTitle $dialogHwnd)' file_type='$fileType' program='$programSelector'"
  # A file-type selector that no longer offers CSV means the menu item is not the
  # table we validated, so stop instead of importing into an unknown format.
  if ($fileType -and $fileType -notmatch 'CSV') { throw "KV_COMMENTS_IMPORT_FILE_TYPE_UNEXPECTED: $fileType" }
  if ($programSelector -and $programSelector -ne $script:ZhGlobal) { throw "KV_COMMENTS_IMPORT_PROGRAM_SELECTOR_MISMATCH: '$programSelector'" }

  if (-not (Set-FileNameText $dialogHwnd $CommentsPath)) { throw 'KV_COMMENTS_IMPORT_FILENAME_FIELD_MISSING' }
  Start-Sleep -Milliseconds 300
  $readBack = Get-FileNameText $dialogHwnd
  Log "file name read-back='$readBack' expected='$CommentsPath'"
  $script:DialogEvidence['file_name_readback'] = $readBack
  if ($readBack -and $readBack -ne $CommentsPath) { throw "KV_COMMENTS_IMPORT_FILENAME_READBACK_MISMATCH: '$readBack'" }
  if (-not $readBack) {
    # The field is visibly filled (the screenshot checkpoint below is the
    # evidence) but neither UIA nor WM_GETTEXT can read it back.  Do not guess and
    # do not abandon the import: keep going, and rely on the two effect-based
    # post-conditions below (project becomes dirty, caller's re-export diff).
    $script:DialogEvidence['file_name_readback_unavailable'] = $true
    Log 'file name field could not be read back; continuing on effect-based verification'
    $dialogSnapshot = [pscustomobject]@{ hwnd = $dialogHwnd.ToInt64(); title = (Get-WindowTitle $dialogHwnd); class_name = (Get-WindowClass $dialogHwnd) }
    Write-KvUiGuardCheckpoint -Step 'device comment import dialog filled' -Status 'before' -Action 'file name field holds the absolute table path' -Expected @{ hwnd = $dialogHwnd.ToInt64(); path = $CommentsPath } -Before $dialogSnapshot -Message 'Screenshot evidence for the filled file name field.' | Out-Null
  }

  $openButton = [KvCommentImportWin32]::GetDlgItem($dialogHwnd, $script:DialogOpenButtonId)
  if ($openButton -eq [IntPtr]::Zero) { throw 'KV_COMMENTS_IMPORT_OPEN_BUTTON_MISSING' }
  Log "clicking open button text='$(Get-WindowTitle $openButton)'"
  [void][KvCommentImportWin32]::SendMessage($openButton, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)

  # -------------------------------------------------------------------------
  # step 4: post-import dialogs, strict allow-list only
  # -------------------------------------------------------------------------
  # KV STUDIO reports a successful read either silently or with a plain
  # information box.  Anything else (error list, format warning, "overwrite?"
  # question) must stop the run with evidence: guessing a button here could
  # silently discard the comment table.
  $handled = New-Object System.Collections.Generic.List[string]
  $transient = New-Object System.Collections.Generic.List[string]
  # KV STUDIO shows short-lived progress windows (InterpreterC, or a bare
  # "KV STUDIO" popup) that close by themselves and are immediately followed by
  # another window, so the settle condition is "no dialog at all for 3 s", not
  # "no dialog on this poll".
  $deadline = (Get-Date).AddSeconds(240)
  $settleWindow = New-TimeSpan -Seconds 3
  $noDialogSince = $null
  do {
    $pending = @(Get-OwnedDialogs $targetId | Where-Object { $_.hwnd -ne $dialogHwnd })
    $openDialogAlive = @(Get-OwnedDialogs $targetId | Where-Object { $_.hwnd -eq $dialogHwnd }).Count -gt 0
    if ($pending.Count -eq 0) {
      $noDialogSince = $null
      if ($openDialogAlive) { Start-Sleep -Milliseconds 400; continue }
      if (-not $noDialogSince) { $noDialogSince = Get-Date }
      if (((Get-Date) - $noDialogSince) -ge $settleWindow) { break }
      Start-Sleep -Milliseconds 400
      continue
    }
    $noDialogSince = $null
    $dialog = $pending[0]
    $dialogElement = $AE::FromHandle($dialog.hwnd)
    $rows = Write-DialogSnapshot -Dialog $dialogElement -Name ('post_import_dialog_{0:D2}_elements.json' -f ($handled.Count + 1))
    $text = (@($rows | Where-Object { $_.name } | ForEach-Object { $_.name }) -join ' | ')
    # A window with no readable text at all ("InterpreterC", or the bare
    # "KV STUDIO" frame that exists before its label is painted) is a progress
    # window: there is nothing to press, so it is waited out.
    if (-not $text) {
      if ($transient -notcontains $dialog.title) {
        $transient.Add([string]$dialog.title) | Out-Null
        Log "transient progress dialog title='$($dialog.title)' text=empty; waiting for it to close"
      }
      Start-Sleep -Milliseconds 500
      continue
    }
    Log "post-import dialog title='$($dialog.title)' text='$text'"
    $successWords = @($script:ZhDone, $script:ZhRead, $script:ZhReadIn, $script:ZhImported) -join '|'
    $dangerWords = @($script:ZhError, $script:ZhFail, $script:ZhCannot, $script:ZhNoWay, $script:ZhOverwrite, $script:ZhQuestion) -join '|'
    $safe = ($text -match $successWords) -and ($text -notmatch $dangerWords)
    if (-not $safe) {
      Save-TopWindowSnapshot 'top_windows_unknown_import_dialog.json'
      throw "KV_COMMENTS_IMPORT_UNKNOWN_DIALOG: title='$($dialog.title)' text='$text'"
    }
    # This message box is a DirectUI window whose controls are all exposed as
    # ControlType.Pane, so no Button element exists to invoke.  The text allow-list
    # above already proved it is a plain "read N comments" information box whose
    # only action is its default button; the verified route is therefore Enter on
    # the focused dialog through the guard (which asserts the dialog owns the
    # foreground), never a blind click on an unidentified control.
    $buttons = @(Get-DialogButtons $dialogElement)
    if ($buttons.Count -gt 0 -and (Invoke-DialogButton $buttons)) {
      Log 'dialog button invoked through UIA InvokePattern'
    } else {
      # AllowTargetClose: the dialog is expected to disappear as the result of the
      # Enter, so the postcondition is "foreground returned to KV STUDIO", not
      # "the dialog is still foreground".
      Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $dialog.hwnd -Step 'dismiss import information box' -Keys '{ENTER}' -ExpectedTitleLike '*' -SuccessTitleLike @('KV STUDIO*') -SleepMs 600
      Log 'dismissed information box with Enter (no UIA Button element exposed)'
    }
    $handled.Add($text) | Out-Null
    Start-Sleep -Milliseconds 600
  } while ((Get-Date) -lt $deadline)
  $script:DialogEvidence['post_import_dialogs'] = @($handled)
  $script:DialogEvidence['transient_progress_dialogs'] = @($transient)
  if ($handled.Count -eq 0) { Log 'no post-import dialog appeared (silent import)' }

  # an unknown dialog still on screen means the import did not settle
  $residual = @(Get-OwnedDialogs $targetId)
  if ($residual.Count -gt 0) {
    Save-TopWindowSnapshot 'top_windows_residual_after_import.json'
    throw "KV_COMMENTS_IMPORT_POST_DIALOG: $($residual[0].title)"
  }

  # Effect-based post-condition: reading a comment table changes the project, and
  # KV STUDIO marks a changed project with "*" in its title.  A clean title here
  # means the dialog was probably dismissed without reading anything, so stop
  # instead of reporting a success that the caller's diff would have to discover.
  $afterImport = Get-Process -Id $targetId -ErrorAction SilentlyContinue
  $titleAfterImport = if ($afterImport) { $afterImport.MainWindowTitle } else { '' }
  $script:DialogEvidence['title_after_import'] = $titleAfterImport
  Log "title after import='$titleAfterImport'"
  if ($titleAfterImport -and $titleAfterImport -notmatch '\*') {
    throw "KV_COMMENTS_IMPORT_NO_EFFECT: project title is still clean ('$titleAfterImport')"
  }

  # -------------------------------------------------------------------------
  # step 5: persist the comment bank
  # -------------------------------------------------------------------------
  if ($SaveAfterImport) {
    # Comments live in <project>.cm1; they are only written to disk on save.
    $current = Get-Process -Id $targetId -ErrorAction SilentlyContinue
    if (-not $current) { throw 'KV_COMMENTS_IMPORT_PROCESS_EXITED' }
    $titleBefore = $current.MainWindowTitle
    Invoke-KvGuardedCtrlChord -TargetHwnd $hwnd -Step 'save project after comment import' -Vk 0x53 -ExpectedTitleLike 'KV STUDIO*' -Action 'Ctrl+S saves the imported comment bank' -SleepMs 2500 | Out-Null
    $after = Get-Process -Id $targetId -ErrorAction SilentlyContinue
    $titleAfter = if ($after) { $after.MainWindowTitle } else { '' }
    Log "title before save='$titleBefore' after='$titleAfter'"
    if ($titleAfter -match '\*') { throw "KV_COMMENTS_IMPORT_SAVE_INCOMPLETE: '$titleAfter'" }
    $script:Saved = $true
  }

  if ($script:LaunchedByRunner -and $CloseProjectWhenLaunched) {
    $current = Get-Process -Id $targetId -ErrorAction SilentlyContinue
    if ($current -and $current.MainWindowTitle -match $cleanTitlePattern) {
      try {
        Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $hwnd -Step 'close comment import project' -Keys '%{F4}' -ExpectedTitleLike 'KV STUDIO*' -SuccessTitleLike @('KV STUDIO*') -SleepMs 1200
        $script:ClosedProject = $true
      } catch { Log "close failed: $($_.Exception.Message)" }
    }
  }

  Write-Result $true '' "Imported $($script:ImportedRows) comment rows from $CommentsPath"
  exit 0
} catch {
  $message = $_.Exception.ToString()
  Log ('ERROR ' + $message)
  $message | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  $code = 'KV_COMMENTS_IMPORT_FAILED'
  foreach ($pair in @(
      'KV_COMMENTS_IMPORT_FILE_MISSING', 'KV_COMMENTS_IMPORT_FILE_EMPTY', 'KV_COMMENTS_IMPORT_TOO_FEW_LINES',
      'KV_COMMENTS_IMPORT_HEADER_INVALID', 'KV_COMMENTS_IMPORT_HEADER_UNEXPECTED', 'KV_COMMENTS_IMPORT_DEVICE_MISSING',
      'KV_COMMENTS_IMPORT_DEVICE_INVALID', 'KV_COMMENTS_IMPORT_DEVICE_DUPLICATE', 'KV_COMMENTS_IMPORT_NO_COMMENTS',
      'KV_COMMENTS_IMPORT_PROJECT_PROCESS_AMBIGUOUS', 'KV_COMMENTS_IMPORT_TARGET_WINDOW_NOT_READY',
      'KV_COMMENTS_IMPORT_DIALOG_MISSING', 'KV_COMMENTS_IMPORT_FILE_TYPE_UNEXPECTED',
      'KV_COMMENTS_IMPORT_FILENAME_FIELD_MISSING', 'KV_COMMENTS_IMPORT_FILENAME_READBACK_MISMATCH',
      'KV_COMMENTS_IMPORT_OPEN_BUTTON_MISSING', 'KV_COMMENTS_IMPORT_UNKNOWN_DIALOG',
      'KV_COMMENTS_IMPORT_POST_DIALOG', 'KV_COMMENTS_IMPORT_PROCESS_EXITED',
      'KV_COMMENTS_IMPORT_SAVE_INCOMPLETE', 'KV_COMMENTS_IMPORT_CREATION_EVIDENCE_INVALID')) {
    if ($message -like ('*' + $pair + '*')) { $code = $pair; break }
  }
  Write-Result $false $code $message
  exit 1
}
