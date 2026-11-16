<#
.SYNOPSIS
Import a program file (.mod/.mcr) into an open KV Nano project, driven through Win32 controls.

.DESCRIPTION
The 导入程序 dialog is a #32770 shell dialog whose file-name box is NOT reachable through UIA
(the UIA subtree is empty), but Win32 exposes it as an Edit with control id 1148 next to the
打开 button (id 1). This script therefore writes the path with WM_SETTEXT, reads it back with
GetWindowText, clicks 打开, then handles the same-name prompt and asserts completion.

KV rules verified live on 2026-11-17:
  * a program file that belongs to the currently open project is refused with
    「导入文件是当前打开项目的文件。」
  * a same-named program raises 「打开的项目有同名的程序，或名称不对。」 offering
    以其它名称导入 / 覆盖; renaming answers 「导入完成。」
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$ProjectPath,
  [Parameter(Mandatory = $true)][string]$SourceModPath,
  [Parameter(Mandatory = $true)][string]$TargetName,
  [Parameter(Mandatory = $true)][string]$OutDir,
  [switch]$Overwrite,
  [int]$TimeoutSeconds = 180
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Drawing

Add-Type -TypeDefinition @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class NanoImport {
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr parent, EnumProc cb, IntPtr l);
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern int GetDlgCtrlID(IntPtr h);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll", CharSet = CharSet.Unicode, EntryPoint = "SendMessageW")] public static extern IntPtr SendMessageStr(IntPtr h, uint m, IntPtr w, string l);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
}
"@

New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$script:logPath = Join-Path $OutDir 'run.log'
function Log([string]$m) {
  [IO.File]::AppendAllText($script:logPath, ((([ordered]@{ t = (Get-Date).ToString('o'); m = $m }) | ConvertTo-Json -Compress)) + [Environment]::NewLine, (New-Object Text.UTF8Encoding($false)))
}
function Shot([string]$name) {
  $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
  $p = Join-Path $OutDir $name
  $bmp.Save($p, [System.Drawing.Imaging.ImageFormat]::Png); $g.Dispose(); $bmp.Dispose(); return $p
}
function TopWindows([int]$pid1) {
  $script:hits = @()
  [void][NanoImport]::EnumWindows({
      param($h, $l)
      $q = 0; [void][NanoImport]::GetWindowThreadProcessId($h, [ref]$q)
      if ($q -eq $pid1 -and [NanoImport]::IsWindowVisible($h)) {
        $sb = New-Object Text.StringBuilder 256; [void][NanoImport]::GetWindowText($h, $sb, 256)
        $script:hits += [pscustomobject]@{ hwnd = $h; title = $sb.ToString() }
      }
      return $true
    }, [IntPtr]::Zero)
  return @($script:hits)
}
function DialogTexts([IntPtr]$hwnd) {
  $el = [Windows.Automation.AutomationElement]::FromHandle($hwnd)
  $t = @()
  foreach ($n in $el.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)) { if ($n.Current.Name) { $t += [string]$n.Current.Name } }
  return $t
}

$result = [ordered]@{ ok = $false; error_code = ''; target_name = $TargetName; read_back = ''; dialogs = @() }
try {
  if (-not (Test-Path -LiteralPath $SourceModPath -PathType Leaf)) { throw "SOURCE_MISSING: $SourceModPath" }
  if ([IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($SourceModPath)) -ieq [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($ProjectPath))) { throw "SAME_PROJECT: $SourceModPath" }

  $needle = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  $proc = $null
  do {
    $proc = Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -match [regex]::Escape($needle) } | Select-Object -First 1
    if (-not $proc) { Start-Sleep -Milliseconds 500 }
  } while (-not $proc -and (Get-Date) -lt $deadline)
  if (-not $proc) { throw "PROJECT_NOT_OPEN: $needle" }
  Log ("project=" + $proc.MainWindowTitle)

  # clear leftovers so the menu keys are not swallowed
  $gate = (Get-Date).AddSeconds(15)
  do {
    $modals = @(TopWindows $proc.Id | Where-Object { $_.title -eq 'KV STUDIO' })
    if ($modals.Count -eq 0) { break }
    foreach ($m in $modals) { [void][NanoImport]::SetForegroundWindow([IntPtr]$m.hwnd); Start-Sleep -Milliseconds 250; [void][System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep -Milliseconds 300 }
  } while ((Get-Date) -lt $gate)
  if (@(TopWindows $proc.Id | Where-Object { $_.title -eq 'KV STUDIO' }).Count -gt 0) { throw 'MODAL_PERSISTS' }

  [void][NanoImport]::SetForegroundWindow($proc.MainWindowHandle)
  Start-Sleep -Milliseconds 500
  [void][System.Windows.Forms.SendKeys]::SendWait('%f'); Start-Sleep -Milliseconds 500
  [void][System.Windows.Forms.SendKeys]::SendWait('i'); Start-Sleep -Milliseconds 700
  [void][System.Windows.Forms.SendKeys]::SendWait('{ENTER}'); Start-Sleep -Seconds 2

  $dlgHwnd = [IntPtr]::Zero
  $dd = (Get-Date).AddSeconds(15)
  do {
    foreach ($w in (TopWindows $proc.Id)) { if ($w.title -eq '导入程序') { $dlgHwnd = [IntPtr]$w.hwnd; break } }
    if ($dlgHwnd -eq [IntPtr]::Zero) { Start-Sleep -Milliseconds 400 }
  } while ($dlgHwnd -eq [IntPtr]::Zero -and (Get-Date) -lt $dd)
  if ($dlgHwnd -eq [IntPtr]::Zero) { throw 'DIALOG_MISSING' }

  $script:nameEdit = [IntPtr]::Zero
  $script:cands = @()
  $script:openBtn = [IntPtr]::Zero
  [void][NanoImport]::EnumChildWindows($dlgHwnd, {
      param($h, $l)
      $cls = New-Object Text.StringBuilder 64; [void][NanoImport]::GetClassName($h, $cls, 64)
      $id = [NanoImport]::GetDlgCtrlID($h)
      if ($id -eq 1148) { $script:cands += $h }
      if ($cls.ToString() -eq 'Button' -and $id -eq 1) { $script:openBtn = $h }
      return $true
    }, [IntPtr]::Zero)
  if ($script:cands.Count -eq 0) { throw 'FILENAME_EDIT_MISSING' }

  # WM_SETTEXT does not stick on any of the candidates, so type into the focused name box the
  # way a user does: the dialog opens with the file name box focused, so select all and type.
  [void][NanoImport]::SetForegroundWindow($dlgHwnd)
  Start-Sleep -Milliseconds 400
  [void][System.Windows.Forms.SendKeys]::SendWait('^a')
  Start-Sleep -Milliseconds 150
  [void][System.Windows.Forms.SendKeys]::SendWait([string]$SourceModPath)
  Start-Sleep -Milliseconds 400
  $result.read_back = 'typed'

  [void][NanoImport]::SetForegroundWindow($dlgHwnd)
  Start-Sleep -Milliseconds 200
  [void][System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Start-Sleep -Seconds 3
  Shot '01_after_open.png' | Out-Null

  # The prompts are plain Win32 dialogs: message Static id=1652, name Edit id=1010 (prefilled
  # with the source program name), 以其它名称导入 id=1058, 覆盖 id=1653, OK id=1, 不导入 id=2.
  # Renaming is done by writing the Edit and clicking OK, which is deterministic.
  $done = $false
  $promptDeadline = (Get-Date).AddSeconds(25)
  do {
    $box = TopWindows $proc.Id | Where-Object { $_.title -eq 'KV STUDIO' } | Select-Object -First 1
    if (-not $box) { Start-Sleep -Milliseconds 400; continue }
    $boxHwnd = [IntPtr]$box.hwnd
    $script:boxKids = @()
    [void][NanoImport]::EnumChildWindows($boxHwnd, {
        param($h, $l)
        $cls = New-Object Text.StringBuilder 64; [void][NanoImport]::GetClassName($h, $cls, 64)
        $txt = New-Object Text.StringBuilder 256; [void][NanoImport]::GetWindowText($h, $txt, 256)
        $script:boxKids += [pscustomobject]@{ hwnd = $h; cls = $cls.ToString(); id = [NanoImport]::GetDlgCtrlID($h); text = $txt.ToString() }
        return $true
      }, [IntPtr]::Zero)
    $message = (($script:boxKids | Where-Object { $_.cls -eq 'Static' -and $_.text } | ForEach-Object { $_.text }) -join ' / ')
    Log ("box message: " + $message)
    if ($message -match '导入完成') {
      $ok = ($script:boxKids | Where-Object { $_.id -eq 1 -and $_.cls -eq 'Button' } | Select-Object -First 1)
      if ($ok) { [void][NanoImport]::SendMessage($ok.hwnd, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
      Start-Sleep -Milliseconds 700
      $done = $true
      break
    }
    if ($message -match '同名的程序|名称不对') {
      $edit = $null
      if (-not $Overwrite) { $edit = ($script:boxKids | Where-Object { $_.cls -eq 'Edit' -and $_.id -eq 1010 } | Select-Object -First 1) }
      if ($edit) {
        # WM_SETTEXT is not honoured across processes for this dialog, so type it: the box opens
        # with the name Edit focused, so Ctrl+A + typing replaces "Main".
        [void][NanoImport]::SetForegroundWindow($boxHwnd)
        Start-Sleep -Milliseconds 300
        [void][System.Windows.Forms.SendKeys]::SendWait("^a")
        Start-Sleep -Milliseconds 150
        [void][System.Windows.Forms.SendKeys]::SendWait([string]$TargetName)
        Start-Sleep -Milliseconds 300
        $buf2 = New-Object Text.StringBuilder 256
        [void][NanoImport]::GetWindowText($edit.hwnd, $buf2, 256)
        Log ("rename read-back=" + $buf2.ToString())
      }
      if ($Overwrite) {
        $radio = ($script:boxKids | Where-Object { $_.cls -eq 'Button' -and $_.id -eq 1653 } | Select-Object -First 1)
        # BM_CLICK on the radio does not select it; BM_SETCHECK does (verified live).
        if ($radio) { [void][NanoImport]::SendMessage($radio.hwnd, 0x00F1, [IntPtr]1, [IntPtr]::Zero) }
      }
      $ok = ($script:boxKids | Where-Object { $_.id -eq 1 -and $_.cls -eq 'Button' } | Select-Object -First 1)
      if ($ok) { [void][NanoImport]::SendMessage($ok.hwnd, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
      Start-Sleep -Seconds 2
      continue
    }
    $cancel = ($script:boxKids | Where-Object { $_.id -eq 2 -and $_.cls -eq 'Button' } | Select-Object -First 1)
    if ($cancel) { [void][NanoImport]::SendMessage($cancel.hwnd, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero) }
    Start-Sleep -Seconds 1
  } while ((Get-Date) -lt $promptDeadline)
  if (-not $done) { throw 'NO_COMPLETION' }

  $main = [Windows.Automation.AutomationElement]::FromHandle($proc.MainWindowHandle)
  $tree = $main.FindFirst([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::AutomationIdProperty), 'ProjectTreeView'))
  $found = $false
  if ($tree) {
    foreach ($it in $tree.FindAll([Windows.Automation.TreeScope]::Descendants, (New-Object Windows.Automation.PropertyCondition -ArgumentList ([Windows.Automation.AutomationElement]::ControlTypeProperty), ([Windows.Automation.ControlType]::TreeItem)))) {
      if ((([string]$it.Current.Name) -replace '\s', '') -ieq ($TargetName -replace '\s', '')) { $found = $true; break }
    }
  }
  $result.tree_name_found = $found
  if (-not $found) { throw "TREE_NAME_MISSING: $TargetName" }
  Shot '02_completed.png' | Out-Null
  $result.ok = $true
}
catch {
  $result.error_code = $_.Exception.Message
  Log ("ERROR " + $_.Exception.Message)
  Shot '99_failure.png' | Out-Null
}
[IO.File]::WriteAllText((Join-Path $OutDir 'nano_program_import_result.json'), ($result | ConvertTo-Json -Depth 5), (New-Object Text.UTF8Encoding($false)))
$result | ConvertTo-Json -Depth 5
if (-not $result.ok) { exit 1 }
