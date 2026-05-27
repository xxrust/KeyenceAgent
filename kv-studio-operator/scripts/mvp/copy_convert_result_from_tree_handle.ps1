param(
  [string]$ProjectNeedle = 'TrafficLightMinST_20260526_MVP5',
  [string]$OutDir = 'E:\personal_project\rust_plc\out\traffic_light_min_loop_20260525\validation\177_copy_convert_result_from_tree_handle',
  [int]$MaxLookupMs = 1000
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type @"
using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using System.Text;
public class KvTreeHandleWin32 {
  public delegate bool EnumWindowProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWndParent, EnumWindowProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr hWnd, out RECT rect);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
  public static List<IntPtr> EnumChildren(IntPtr parent) {
    List<IntPtr> result = new List<IntPtr>();
    EnumChildWindows(parent, delegate(IntPtr hwnd, IntPtr lparam) {
      result.Add(hwnd);
      return true;
    }, IntPtr.Zero);
    return result;
  }
}
"@

function Log {
  param([string]$Message)
  Add-Content -LiteralPath (Join-Path $OutDir 'run.log') -Value ((Get-Date -Format s) + ' ' + $Message) -Encoding UTF8
}

function Get-ClassName {
  param([IntPtr]$Handle)
  $builder = [Text.StringBuilder]::new(256)
  [void][KvTreeHandleWin32]::GetClassName($Handle, $builder, $builder.Capacity)
  $builder.ToString()
}

function Get-WindowTitle {
  param([IntPtr]$Handle)
  $builder = [Text.StringBuilder]::new(512)
  [void][KvTreeHandleWin32]::GetWindowText($Handle, $builder, $builder.Capacity)
  $builder.ToString()
}

function Get-WindowRectObject {
  param([IntPtr]$Handle)
  $rect = New-Object KvTreeHandleWin32+RECT
  if (-not [KvTreeHandleWin32]::GetWindowRect($Handle, [ref]$rect)) {
    throw "GetWindowRect failed for hwnd=$Handle"
  }
  $rect
}

try {
  $process = Get-Process Kvs -ErrorAction Stop |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$ProjectNeedle*" } |
    Select-Object -First 1
  if (-not $process) {
    throw "No visible Kvs process found for project needle $ProjectNeedle."
  }

  $mainTitle = Get-WindowTitle $process.MainWindowHandle
  Log "main_hwnd=$($process.MainWindowHandle) title=$mainTitle"
  if ($mainTitle -notlike "KV STUDIO*$ProjectNeedle*") {
    throw "Main window title mismatch: $mainTitle"
  }

  $lookupWatch = [Diagnostics.Stopwatch]::StartNew()
  $mainRect = Get-WindowRectObject $process.MainWindowHandle
  $children = [KvTreeHandleWin32]::EnumChildren($process.MainWindowHandle)
  $treeCandidates = [System.Collections.Generic.List[object]]::new()
  foreach ($child in $children) {
    if (-not [KvTreeHandleWin32]::IsWindowVisible($child)) { continue }
    $className = Get-ClassName $child
    if ($className -notlike '*SysTreeView32*') { continue }
    $rect = Get-WindowRectObject $child
    $width = $rect.Right - $rect.Left
    $height = $rect.Bottom - $rect.Top
    if ($width -lt 300 -or $height -lt 60) { continue }
    $treeCandidates.Add([pscustomobject]@{
      hwnd = $child
      class = $className
      left = $rect.Left
      top = $rect.Top
      right = $rect.Right
      bottom = $rect.Bottom
      width = $width
      height = $height
      distance_to_bottom = [math]::Abs($mainRect.Bottom - $rect.Bottom)
    })
  }
  if ($treeCandidates.Count -eq 0) {
    throw 'No visible SysTreeView32 candidates found under KV STUDIO.'
  }
  $candidate = $treeCandidates |
    Sort-Object @{ Expression = { $_.distance_to_bottom }; Ascending = $true }, @{ Expression = { $_.width }; Ascending = $false } |
    Select-Object -First 1
  Log "candidate hwnd=$($candidate.hwnd) class=$($candidate.class) rect=$($candidate.left),$($candidate.top),$($candidate.width),$($candidate.height) distance_to_bottom=$($candidate.distance_to_bottom)"

  $treeElement = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$candidate.hwnd)
  if (-not $treeElement) { throw 'AutomationElement.FromHandle returned null for result tree.' }

  $treeItemCondition = New-Object Windows.Automation.PropertyCondition(
    [Windows.Automation.AutomationElement]::ControlTypeProperty,
    [Windows.Automation.ControlType]::TreeItem
  )
  $items = @($treeElement.FindAll([Windows.Automation.TreeScope]::Descendants, $treeItemCondition))
  $lookupWatch.Stop()
  Log "lookup_ms=$($lookupWatch.ElapsedMilliseconds) treeitem_count=$($items.Count)"
  if ($lookupWatch.ElapsedMilliseconds -gt $MaxLookupMs) {
    throw "Result tree handle lookup exceeded ${MaxLookupMs}ms: $($lookupWatch.ElapsedMilliseconds)ms"
  }
  if ($items.Count -eq 0) { throw 'Result tree has no TreeItem descendants.' }

  $lines = [System.Collections.Generic.List[string]]::new()
  foreach ($item in $items) {
    $name = ([string]$item.Current.Name).TrimEnd()
    if ($name) { $lines.Add($name) }
  }
  if ($lines.Count -eq 0) { throw 'Result tree items had no text.' }

  $text = ($lines -join "`r`n")
  Set-Content -LiteralPath (Join-Path $OutDir 'compile_result_copied.txt') -Value $text -Encoding UTF8
  [Windows.Forms.Clipboard]::SetText($text)
  Log "copied_result_length=$($text.Length)"

  $okNeedle = (-join ([char[]](0x8F6C,0x6362,0x7ED3,0x679C))) + ' OK'
  $ngNeedle = (-join ([char[]](0x8F6C,0x6362,0x7ED3,0x679C))) + ' NG'
  $clipboard = [Windows.Forms.Clipboard]::GetText()
  if ([string]::IsNullOrWhiteSpace($clipboard)) { throw 'Clipboard verification failed: clipboard is empty after setting result text.' }
  if (-not $clipboard.Contains($okNeedle)) { throw "Clipboard verification failed: clipboard does not contain expected OK marker: $okNeedle" }
  if (-not $text.Contains($okNeedle)) { throw "Copied text does not contain expected OK marker: $okNeedle" }

  [pscustomobject]@{
    ok = $true
    route = 'win32_child_hwnd_to_uia_treeitem_to_clipboard'
    lookup_ms = $lookupWatch.ElapsedMilliseconds
    line_count = $lines.Count
    clipboard_length = $clipboard.Length
    contains_ok = $text.Contains($okNeedle)
    contains_ng = $text.Contains($ngNeedle)
  } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $OutDir 'result.json') -Encoding UTF8
  Log 'done'
} catch {
  Log ('ERROR ' + $_.Exception.ToString())
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  exit 1
}
