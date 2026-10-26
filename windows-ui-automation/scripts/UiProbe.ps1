# UiProbe.ps1 - application-agnostic Windows UI probing helpers.
# Dot-source this file from automation scripts. No business logic, no fixed
# coordinates: every function takes a process/window/element handle.
#
#   . <skill>\scripts\UiProbe.ps1
#   $w = Get-UiWindow -ProcessName notepad -TitleLike '记事本'
#   Get-UiChildList -Hwnd $w.Handle
#   Get-UiStaticText -Hwnd $w.Handle
#   Invoke-UiButton -Element $el -Name '确定'
#   Save-UiScreenshot -Path C:\temp\shot.png

if (-not ('UiProbeNative' -as [type])) {
  Add-Type -TypeDefinition @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class UiProbeNative {
  public delegate bool EnumProc(IntPtr h, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr p, EnumProc cb, IntPtr l);
  [DllImport("user32.dll")] public static extern int GetWindowThreadProcessId(IntPtr h, out int pid);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr h);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern IntPtr SendMessage(IntPtr h, uint m, IntPtr w, string l);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr h, uint m, IntPtr w, IntPtr l);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static string Text(IntPtr h) { var sb = new StringBuilder(512); GetWindowText(h, sb, 512); return sb.ToString(); }
  public static string Class(IntPtr h) { var sb = new StringBuilder(256); GetClassName(h, sb, 256); return sb.ToString(); }
  public static List<string> Windows(int pid, bool visibleOnly) {
    var res = new List<string>();
    EnumWindows((h, l) => {
      int p; GetWindowThreadProcessId(h, out p);
      if (p != pid) { return true; }
      if (visibleOnly && !IsWindowVisible(h)) { return true; }
      var t = Text(h); if (t.Length == 0) { return true; }
      res.Add(h.ToInt64() + "|" + Class(h) + "|" + t);
      return true;
    }, IntPtr.Zero);
    return res;
  }
  public static List<string> Children(IntPtr p) {
    var res = new List<string>();
    EnumChildWindows(p, (h, l) => {
      res.Add(h.ToInt64() + "|" + Class(h) + "|" + Text(h));
      return true;
    }, IntPtr.Zero);
    return res;
  }
  public static string Statics(IntPtr p) {
    var sb = new StringBuilder();
    EnumChildWindows(p, (h, l) => {
      if (Class(h).Contains("Static")) { var t = Text(h); if (t.Length > 0) sb.Append(t).Append("|"); }
      return true;
    }, IntPtr.Zero);
    return sb.ToString();
  }
  public static void Click(int x, int y) {
    SetCursorPos(x, y); System.Threading.Thread.Sleep(120);
    mouse_event(0x0002, 0, 0, 0, IntPtr.Zero); System.Threading.Thread.Sleep(60);
    mouse_event(0x0004, 0, 0, 0, IntPtr.Zero);
  }
}
"@
}

function Get-UiProcess {
  param([string]$ProcessName, [int]$ProcessId)
  if ($ProcessId -gt 0) { return Get-Process -Id $ProcessId -ErrorAction Stop }
  $p = @(Get-Process -Name $ProcessName -ErrorAction Stop | Where-Object { $_.MainWindowHandle -ne 0 })
  if ($p.Count -eq 0) { throw "UI_PROCESS_NOT_FOUND: $ProcessName" }
  return $p[0]
}

function Get-UiWindowList {
  param(
    [string]$ProcessName,
    [int]$ProcessId,
    [switch]$IncludeHidden
  )
  $p = Get-UiProcess -ProcessName $ProcessName -ProcessId $ProcessId
  foreach ($row in [UiProbeNative]::Windows($p.Id, (-not $IncludeHidden))) {
    $parts = $row -split '\|', 3
    [pscustomobject]@{ Handle = [long]$parts[0]; Class = $parts[1]; Title = $parts[2]; ProcessId = $p.Id }
  }
}

function Get-UiWindow {
  param(
    [string]$ProcessName,
    [int]$ProcessId,
    [string]$TitleLike,
    [string]$ClassLike
  )
  $windows = @(Get-UiWindowList -ProcessName $ProcessName -ProcessId $ProcessId)
  $matches = @($windows | Where-Object {
    (-not $TitleLike -or $_.Title -like $TitleLike) -and
    (-not $ClassLike -or $_.Class -like $ClassLike)
  })
  if ($matches.Count -eq 0) { throw "UI_WINDOW_NOT_FOUND: title='$TitleLike' class='$ClassLike'" }
  if ($matches.Count -gt 1) { throw "UI_WINDOW_AMBIGUOUS: $($matches.Count) matched title='$TitleLike'" }
  return $matches[0]
}

function Wait-UiWindow {
  param(
    [string]$ProcessName,
    [int]$ProcessId,
    [string]$TitleLike,
    [string]$ClassLike,
    [int]$TimeoutSeconds = 10,
    [int]$PollMs = 300
  )
  $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
  do {
    try { return Get-UiWindow -ProcessName $ProcessName -ProcessId $ProcessId -TitleLike $TitleLike -ClassLike $ClassLike } catch {}
    Start-Sleep -Milliseconds $PollMs
  } while ((Get-Date) -lt $deadline)
  throw "UI_WINDOW_TIMEOUT: title='$TitleLike' after ${TimeoutSeconds}s"
}

function Get-UiChildList {
  param([Parameter(Mandatory=$true)][long]$Hwnd)
  foreach ($row in [UiProbeNative]::Children([IntPtr]$Hwnd)) {
    $parts = $row -split '\|', 3
    [pscustomobject]@{ Handle = [long]$parts[0]; Class = $parts[1]; Text = $parts[2]; Parent = $Hwnd }
  }
}

function Get-UiStaticText {
  param([Parameter(Mandatory=$true)][long]$Hwnd)
  return [UiProbeNative]::Statics([IntPtr]$Hwnd)
}

function Get-UiRect {
  param([Parameter(Mandatory=$true)][long]$Hwnd)
  $r = New-Object UiProbeNative+RECT
  if (-not [UiProbeNative]::GetWindowRect([IntPtr]$Hwnd, [ref]$r)) { throw "UI_RECT_FAILED: $Hwnd" }
  [pscustomobject]@{ Left = $r.L; Top = $r.T; Right = $r.R; Bottom = $r.B; Width = ($r.R - $r.L); Height = ($r.B - $r.T) }
}

function Set-UiForeground {
  param([Parameter(Mandatory=$true)][long]$Hwnd)
  [void][UiProbeNative]::SetForegroundWindow([IntPtr]$Hwnd)
  Start-Sleep -Milliseconds 300
  $fg = [UiProbeNative]::GetForegroundWindow()
  if ($fg -ne [IntPtr]$Hwnd) { throw "UI_FOREGROUND_MISMATCH: wanted=$Hwnd actual=$($fg.ToInt64())" }
  return $true
}

function Get-UiForeground {
  $h = [UiProbeNative]::GetForegroundWindow()
  [pscustomobject]@{ Handle = $h.ToInt64(); Class = [UiProbeNative]::Class($h); Title = [UiProbeNative]::Text($h) }
}

function Find-UiButton {
  param(
    [Parameter(Mandatory=$true)]$Element,
    [Parameter(Mandatory=$true)][string]$Name
  )
  foreach ($b in @($Element.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition))) {
    if ([string]$b.Current.Name -eq $Name) { return $b }
  }
  return $null
}

function Invoke-UiButton {
  param(
    $Element,
    [string]$Name,
    [long]$Hwnd = 0,
    [int]$TimeoutMs = 0
  )
  if (-not $Element -and $Hwnd -ne 0) {
    $Element = [System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
  }
  if (-not $Element) { throw 'UI_BUTTON_NO_ELEMENT' }
  if (-not $Name) { throw 'UI_BUTTON_NO_NAME' }
  $b = Find-UiButton -Element $Element -Name $Name
  if (-not $b) { throw "UI_BUTTON_NOT_FOUND: $Name" }
  # WinForms buttons ignore BM_CLICK; focus+space works for both WinForms and
  # native MFC buttons. Wait for enablement first.
  $deadline = if ($TimeoutMs -gt 0) { (Get-Date).AddMilliseconds($TimeoutMs) } else { Get-Date }
  do {
    if ($b.Current.IsEnabled) { break }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  try {
    $b.SetFocus()
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait(' ')
  } catch {
    $native = [long]$b.Current.NativeWindowHandle
    if ($native -eq 0) { throw "UI_BUTTON_FOCUS_FAILED: $Name" }
    [void][UiProbeNative]::SendMessage([IntPtr]$native, 0x00F5, [IntPtr]::Zero, [IntPtr]::Zero)
  }
  Start-Sleep -Milliseconds 300
  return $true
}

function Click-UiPoint {
  param(
    [long]$Hwnd,
    [int]$OffsetX,
    [int]$OffsetY,
    [int]$X,
    [int]$Y
  )
  if ($Hwnd -ne 0) {
    $r = Get-UiRect -Hwnd $Hwnd
    $X = $r.Left + $OffsetX
    $Y = $r.Top + $OffsetY
  }
  if ($X -le 0 -or $Y -le 0) { throw 'UI_CLICK_NO_TARGET' }
  [UiProbeNative]::Click($X, $Y)
  return ([pscustomobject]@{ X = $X; Y = $Y })
}

function Send-UiKeys {
  param([Parameter(Mandatory=$true)][string]$Keys, [int]$DelayMs = 60)
  [System.Windows.Forms.SendKeys]::SendWait($Keys)
  if ($DelayMs -gt 0) { Start-Sleep -Milliseconds $DelayMs }
}

function Save-UiScreenshot {
  param(
    [Parameter(Mandatory=$true)][string]$Path,
    [switch]$Retry
  )
  Add-Type -AssemblyName System.Drawing
  Add-Type -AssemblyName System.Windows.Forms
  $dir = Split-Path -Parent $Path
  if ($dir) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
  $attempts = if ($Retry) { 3 } else { 1 }
  for ($i = 0; $i -lt $attempts; $i++) {
    try {
      $b = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
      $bmp = New-Object System.Drawing.Bitmap($b.Width, $b.Height)
      $g = [System.Drawing.Graphics]::FromImage($bmp)
      $g.CopyFromScreen($b.Location, [System.Drawing.Point]::Empty, $b.Size)
      $bmp.Save($Path, [System.Drawing.Imaging.ImageFormat]::Png)
      $g.Dispose(); $bmp.Dispose()
      return $Path
    } catch {
      Start-Sleep -Milliseconds 300
      if ($i -eq ($attempts - 1)) { throw }
    }
  }
}

function Get-UiDialogList {
  param(
    [string]$ProcessName,
    [int]$ProcessId,
    [string[]]$ClassLike = @('#32770')
  )
  $out = @()
  foreach ($w in @(Get-UiWindowList -ProcessName $ProcessName -ProcessId $ProcessId)) {
    $hit = $false
    foreach ($c in $ClassLike) { if ($w.Class -like $c) { $hit = $true } }
    if ($hit) { $out += $w }
  }
  return $out
}
