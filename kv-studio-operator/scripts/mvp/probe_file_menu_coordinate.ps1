param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,
  [string]$OutDir = 'C:\Users\Public\KVSkillPractice\menu_probe',
  [string]$KvsExe = 'D:\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe',
  [int]$MenuOffsetX = 45,
  [int]$MenuOffsetY = 62
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class MenuProbeWin32 {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(int flags, int dx, int dy, int data, int extra);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder text, int count);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder text, int count);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
"@

function Log([string]$Message) {
  $line = (Get-Date -Format s) + ' ' + $Message + [Environment]::NewLine
  [IO.File]::AppendAllText((Join-Path $OutDir 'run.log'), $line, [Text.Encoding]::UTF8)
}

function Get-Title([IntPtr]$Handle) {
  $builder = [Text.StringBuilder]::new(512)
  [void][MenuProbeWin32]::GetWindowText($Handle, $builder, $builder.Capacity)
  $builder.ToString()
}

function Get-Class([IntPtr]$Handle) {
  $builder = [Text.StringBuilder]::new(256)
  [void][MenuProbeWin32]::GetClassName($Handle, $builder, $builder.Capacity)
  $builder.ToString()
}

function Get-Rect([IntPtr]$Handle) {
  $rect = New-Object MenuProbeWin32+RECT
  [void][MenuProbeWin32]::GetWindowRect($Handle, [ref]$rect)
  $rect
}

function Save-Screenshot([string]$Name) {
  $bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = [Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
  $bitmap.Save((Join-Path $OutDir $Name))
  $graphics.Dispose()
  $bitmap.Dispose()
}

function Test-KvSplashVisible {
  $bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
  $bitmap = [Drawing.Bitmap]::new($bounds.Width, $bounds.Height)
  $graphics = [Drawing.Graphics]::FromImage($bitmap)
  $graphics.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
  $graphics.Dispose()
  $blue = 0
  $samples = 0
  $startX = [int]($bounds.Width * 0.45)
  $endX = [int]($bounds.Width * 0.85)
  $startY = [int]($bounds.Height * 0.45)
  $endY = [int]($bounds.Height * 0.85)
  for ($x = $startX; $x -lt $endX; $x += 25) {
    for ($y = $startY; $y -lt $endY; $y += 25) {
      $c = $bitmap.GetPixel($x, $y)
      $samples++
      if ($c.B -gt 120 -and $c.R -lt 60 -and $c.G -lt 140) { $blue++ }
    }
  }
  $bitmap.Dispose()
  $ratio = if ($samples -gt 0) { $blue / $samples } else { 0 }
  Log "splash_blue_ratio=$ratio"
  return ($ratio -gt 0.08)
}

function Wait-KvInteractive([int]$Seconds = 60) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    if (-not (Test-KvSplashVisible)) {
      Start-Sleep -Milliseconds 500
      if (-not (Test-KvSplashVisible)) {
        Log 'KV splash/loader not visible; treating main window as interactable'
        return $true
      }
    }
    Start-Sleep -Milliseconds 500
  } while ((Get-Date) -lt $deadline)
  return $false
}

function Click-Point([int]$X, [int]$Y, [string]$Label) {
  [MenuProbeWin32]::SetCursorPos($X, $Y) | Out-Null
  Start-Sleep -Milliseconds 80
  [MenuProbeWin32]::mouse_event(0x0002, 0, 0, 0, 0)
  Start-Sleep -Milliseconds 40
  [MenuProbeWin32]::mouse_event(0x0004, 0, 0, 0, 0)
  Log "clicked $Label at $X,$Y"
}

function Get-PopupWindows {
  $items = [System.Collections.Generic.List[object]]::new()
  $callback = [MenuProbeWin32+EnumWindowsProc]{
    param([IntPtr]$hwnd, [IntPtr]$lparam)
    try {
      if (-not [MenuProbeWin32]::IsWindowVisible($hwnd)) { return $true }
      $class = Get-Class $hwnd
      if ($class -ne '#32768') { return $true }
      $title = Get-Title $hwnd
      $rect = Get-Rect $hwnd
      $items.Add([pscustomobject]@{
        hwnd = [int64]$hwnd
        title = $title
        class = $class
        left = $rect.Left
        top = $rect.Top
        right = $rect.Right
        bottom = $rect.Bottom
        width = $rect.Right - $rect.Left
        height = $rect.Bottom - $rect.Top
      })
    } catch {}
    return $true
  }
  [void][MenuProbeWin32]::EnumWindows($callback, [IntPtr]::Zero)
  @($items)
}

try {
  Get-Process Kvs -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
  Start-Sleep -Seconds 1
  Start-Process -FilePath $KvsExe -ArgumentList ('"' + $ProjectPath + '"') | Out-Null
  $needle = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)
  $deadline = (Get-Date).AddSeconds(45)
  $process = $null
  do {
    Start-Sleep -Milliseconds 500
    $process = Get-Process Kvs -ErrorAction SilentlyContinue |
      Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$needle*" } |
      Select-Object -First 1
  } while (-not $process -and (Get-Date) -lt $deadline)
  if (-not $process) { throw "KV STUDIO project window not found for $needle" }
  [MenuProbeWin32]::ShowWindow($process.MainWindowHandle, 3) | Out-Null
  [MenuProbeWin32]::BringWindowToTop($process.MainWindowHandle) | Out-Null
  [MenuProbeWin32]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
  Start-Sleep -Seconds 2
  if (-not (Wait-KvInteractive 60)) { throw 'KV STUDIO splash/loader did not clear before menu probe.' }
  $rect = Get-Rect $process.MainWindowHandle
  Save-Screenshot '00_before_click.png'
  $x = $rect.Left + $MenuOffsetX
  $y = $rect.Top + $MenuOffsetY
  Click-Point $x $y 'file_menu'
  Start-Sleep -Milliseconds 500
  Save-Screenshot '01_after_file_click.png'
  $popups = @(Get-PopupWindows)
  $popups | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'popups_after_file_click.json') -Encoding UTF8
  [pscustomobject]@{
    ok = ($popups.Count -gt 0)
    project = $ProjectPath
    main_title = $process.MainWindowTitle
    main_rect = "$($rect.Left),$($rect.Top),$($rect.Right - $rect.Left),$($rect.Bottom - $rect.Top)"
    click = "$x,$y"
    popup_count = $popups.Count
    popups = $popups
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'result.json') -Encoding UTF8
} catch {
  Log ('ERROR ' + $_.Exception.ToString())
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  exit 1
}
