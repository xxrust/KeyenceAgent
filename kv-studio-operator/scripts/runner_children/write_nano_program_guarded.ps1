<#
.SYNOPSIS
Write a KV program body from a mnemonic text file through the ladder 编辑列表.

.DESCRIPTION
This reuses the same guarded UI machinery as set_fb_program_body_guarded.ps1 (KV-X): open the
program in the tree, Ctrl+D for 编辑列表, paste the mnemonic body with the guard's clipboard
paste, accept 全部覆盖 if asked, apply, close and save. On KV Nano the same route works - the
only differences found live (2026-11-17) are:

  * 编辑列表 on Nano is a modal #32770 window titled 编辑列表 with Edit id=1010,
    插入(&I) id=4, 替换块(&R) id=1370, 取消 id=2 (KV-X exposes an embedded panel with
    _buttonInsert instead), so the insert/apply step clicks 替换块 by rectangle;
  * the Nano ladder editor does not expose _buttonInsert, so the editor proof used by the FB
    script is skipped here; instead the modal 编辑列表 presence is the proof.

.EXAMPLE
powershell -File write_nano_program_guarded.ps1 -ProjectPath C:\kvrun\nano\imp_B\纯48.kpr `
  -ProgramName WriteTest -MnmPath C:\kvrun\nano\WriteTest_rebuild.mnm -OutDir C:\kvrun\nano\wr
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ProjectPath,
  [Parameter(Mandatory = $true)][string]$ProgramName,
  [Parameter(Mandatory = $true)][string]$MnmPath,
  [Parameter(Mandatory = $true)][string]$OutDir,
  [switch]$NoSave
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null
. (Join-Path (Split-Path -Parent $PSCommandPath) '..\guards\kv_ui_guard.ps1')
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Initialize-KvUiGuard -OutDir $OutDir -CheckpointSubdir 'nano_program_ui'
if (-not ('NanoWriteTitles' -as [type])) {
  Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class NanoWriteTitles {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
}
"@
}
function Get-ChildWindowTitles([int]$ProcessId) {
  $script:titles = @()
  [void][NanoWriteTitles]::EnumWindows({
      param($h, $l)
      $q = 0; [void][NanoWriteTitles]::GetWindowThreadProcessId($h, [ref]$q)
      if ($q -eq $ProcessId -and [NanoWriteTitles]::IsWindowVisible($h)) {
        $sb = New-Object Text.StringBuilder 256; [void][NanoWriteTitles]::GetWindowText($h, $sb, 256)
        if ($sb.ToString()) { $script:titles += [pscustomobject]@{ hwnd = $h; title = $sb.ToString() } }
      }
      return $true
    }, [IntPtr]::Zero)
  return @($script:titles)
}

$projectNeedle = [IO.Path]::GetFileNameWithoutExtension([IO.Path]::GetFullPath($ProjectPath))
$p = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$projectNeedle*" })
if ($p.Count -ne 1) { if ($p.Count -eq 0) { throw 'KV_PROJECT_PROCESS_NOT_FOUND' }; throw 'KV_TARGET_PROJECT_WINDOW_AMBIGUOUS' }
$p = $p[0]
$main = [Windows.Automation.AutomationElement]::FromHandle($p.MainWindowHandle)

# ---- select the program node -----------------------------------------------------------
$treeCond = New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::AutomationIdProperty, 'ProjectTreeView')
$tree = $main.FindFirst([Windows.Automation.TreeScope]::Descendants, $treeCond)
if (-not $tree) { throw 'KV_PROJECT_TREE_MISSING' }
$items = $tree.FindAll([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::ControlTypeProperty), ([Windows.Automation.ControlType]::TreeItem)))
$item = $null
for ($i = 0; $i -lt $items.Count; $i++) {
  if (([string]$items.Item($i).Current.Name).Trim() -eq $ProgramName) { $item = $items.Item($i); break }
}
if (-not $item) { throw "KV_MODULE_NOT_FOUND: $ProgramName" }
$sel = $null
if ($item.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$sel)) { $sel.Select() }
$item.SetFocus()
Invoke-KvGuardedSendKeys -TargetHwnd $p.MainWindowHandle -Step 'nano_program_open' -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 800

# ---- prepare the body text --------------------------------------------------------------
$mnmLines = @(Get-Content -LiteralPath $MnmPath -Encoding Default)
$moduleHeader = @($mnmLines | Where-Object { $_ -match '^;MODULE:' } | Select-Object -First 1)
if ($moduleHeader.Count -gt 0) {
  $moduleValue = ([string]$moduleHeader[0]).Substring(8).Trim()
  if ($moduleValue -ne $ProgramName) { throw "KV_MNM_MODULE_MISMATCH: expected=$ProgramName actual=$moduleValue" }
}
$bodyLines = @($mnmLines | Where-Object { $_ -notmatch '^(DEVICE:|;MODULE:|;MODULE_TYPE:|END$|ENDH$)' -and $_.Trim() })
if ($bodyLines.Count -eq 0) { throw 'KV_MNM_PROGRAM_BODY_EMPTY' }
$text = (($bodyLines -join "`r`n") + "`r`n")
$bodyPath = Join-Path $OutDir 'program_body_paste.mnm'
[IO.File]::WriteAllText($bodyPath, $text, [Text.Encoding]::Default)
Write-KvUiGuardRunLog -Event 'nano_program_body_prepared' -Data @{ source = $MnmPath; body_rows = $bodyLines.Count; body_path = $bodyPath }

# ---- open 编辑列表 (Ctrl+D) ------------------------------------------------------------
Invoke-KvGuardedCtrlChord -TargetHwnd $p.MainWindowHandle -Step 'nano_program_open_edit_list' -Vk 0x44 -ExpectedTitleLike 'KV STUDIO*' -AllowModalAfter -SleepMs 700

# The modal may appear a moment after Ctrl+D, so look for a 编辑列表 window first.
$editHwnd = [IntPtr]::Zero
$waitEdit = (Get-Date).AddSeconds(6)
do {
  foreach ($w in (Get-ChildWindowTitles -ProcessId $p.Id)) { if ($w.title -match '编辑列表') { $editHwnd = [IntPtr]$w.hwnd; break } }
  if ($editHwnd -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 300 }
} while ($editHwnd -eq [IntPtr]::Zero -and (Get-Date) -lt $waitEdit)
$editSnapshot = Get-KvForegroundSnapshot
$editTitleLike = 'KV STUDIO*'
$editMode = 'embedded_panel'
if ($editSnapshot -and $editSnapshot.process_id -eq $p.Id -and $editSnapshot.class_name -eq '#32770') {
  $editHwnd = [IntPtr]$editSnapshot.hwnd
  $editTitleLike = '*'
  $editMode = 'modal_window'
}
Write-KvUiGuardRunLog -Event 'nano_program_edit_list_detected' -Data @{ mode = $editMode; hwnd = $editHwnd.ToInt64(); title = $editSnapshot.title }

# ---- paste the body ---------------------------------------------------------------------
try {
  Invoke-KvGuardedClipboardPaste -TargetHwnd $editHwnd -Step 'nano_program_body_paste' -Text $text -ExpectedTitleLike $editTitleLike -SleepMs 600
}
catch {
  # An edit list that still holds rows makes KV ask 全部覆盖; accepting it only replaces the
  # edit-list content, which is what this runner wants.
  $ov = Get-KvForegroundSnapshot
  if ($ov.class_name -ne '#32770' -or $ov.process_id -ne $p.Id) { throw }
  Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd ([IntPtr]$ov.hwnd) -Step 'nano_program_accept_overwrite' -Keys '{ENTER}' -ExpectedTitleLike '*' -SuccessTitleLike @('*') -SleepMs 400
  Write-KvUiGuardRunLog -Event 'nano_program_overwrite_accepted' -Data @{ hwnd = $ov.hwnd }
}

$result = [ordered]@{ ok = $false; error_code = ''; program = $ProgramName; body_rows = $bodyLines.Count; mode = $editMode; inserted = $false }
try {
  if ($editMode -eq 'modal_window') {
    # Nano's modal edit list applies with 替换块(&R) (id=1370); 插入(&I) is id=4.
    $editEl = [Windows.Automation.AutomationElement]::FromHandle($editHwnd)
    $buttons = @($editEl.FindAll([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::ControlTypeProperty), ([Windows.Automation.ControlType]::Button))))
    $apply = $null
    foreach ($button in $buttons) { if ($button.Current.Name -match '替换') { $apply = $button; break } }
    $applyRect = $null
    if ($apply) { $applyRect = $apply.Current.BoundingRectangle }
    else {
      # UIA does not always expose the dialog buttons; fall back to Win32 control ids.
      Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class NanoEditListWin32 {
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr l);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
}
"@ -ErrorAction SilentlyContinue
      $script:replaceHwnd = [IntPtr]::Zero
      [void][NanoEditListWin32]::EnumChildWindows($editHwnd, {
          param($h, $l)
          if ([NanoEditListWin32]::GetDlgCtrlID($h) -eq 1370) { $script:replaceHwnd = $h }
          return $true
        }, [IntPtr]::Zero)
      if ($script:replaceHwnd -eq [IntPtr]::Zero) { throw 'KV_NANO_EDIT_LIST_REPLACE_MISSING' }
      $rect = New-Object NanoEditListWin32+RECT
      [void][NanoEditListWin32]::GetWindowRect($script:replaceHwnd, [ref]$rect)
      $applyRect = [pscustomobject]@{ X = $rect.L; Y = $rect.T; Width = ($rect.R - $rect.L); Height = ($rect.B - $rect.T) }
    }
    $r = $applyRect
    Invoke-KvGuardedMouseClick -TargetHwnd $editHwnd -Step 'nano_program_apply_replace' -X ([int]($r.X + $r.Width / 2)) -Y ([int]($r.Y + $r.Height / 2)) -ExpectedTitleLike '*' -SleepMs 900
    $post = Get-KvForegroundSnapshot
    if ($post.class_name -eq '#32770' -and $post.process_id -eq $p.Id -and $post.hwnd -ne $editHwnd.ToInt64()) {
      Write-KvUiGuardRunLog -Event 'nano_program_error_modal' -Data @{ text = $post.title }
      Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd ([IntPtr]$post.hwnd) -Step 'dismiss nano program error' -Keys '{ENTER}' -ExpectedTitleLike '*' -SuccessTitleLike @('*') -SleepMs 300
      throw 'KV_NANO_PROGRAM_TEXT_REJECTED'
    }
    $result.inserted = $true
  }
  else {
    Invoke-KvGuardedSendKeys -TargetHwnd $editHwnd -Step 'nano_program_insert' -Keys '{TAB}' -ExpectedTitleLike $editTitleLike -SleepMs 500
    Invoke-KvGuardedSendKeys -TargetHwnd $editHwnd -Step 'nano_program_insert_confirm' -Keys '{ENTER}' -ExpectedTitleLike $editTitleLike -SleepMs 700
    $result.inserted = $true
  }

  if (-not $NoSave) {
    Invoke-KvGuardedSendKeys -TargetHwnd $p.MainWindowHandle -Step 'nano_program_save' -Keys '^s' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 600
  }
  $result.ok = $true
}
catch {
  $result.error_code = $_.Exception.Message
  Write-KvUiGuardRunLog -Event 'nano_program_body_failed' -Data @{ error = $_.Exception.Message }
}
[IO.File]::WriteAllText((Join-Path $OutDir 'nano_program_body_result.json'), ($result | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
$result | ConvertTo-Json -Depth 5
if (-not $result.ok) { exit 1 }
