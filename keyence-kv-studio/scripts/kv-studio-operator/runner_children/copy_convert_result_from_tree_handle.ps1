param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectNeedle,
  [Parameter(Mandatory=$true)]
  [string]$OutDir,
  [string]$ChecklistPath = '',
  [int]$MaxLookupMs = 60000
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$checklistGuard = Join-Path (Split-Path -Parent (Split-Path -Parent $PSCommandPath)) 'assert_kv_operation_checklist.ps1'
if (-not (Test-Path -LiteralPath $checklistGuard)) { throw "Checklist guard script not found: $checklistGuard" }
$global:LASTEXITCODE = 0
& $checklistGuard -ChecklistPath $ChecklistPath -SearchRoots @($OutDir) -OperationName 'copy KV STUDIO conversion result' | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

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
  [DllImport("user32.dll")] public static extern IntPtr GetDlgItem(IntPtr hDlg, int nIDDlgItem);
  [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
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

$BM_CLICK = 0x00F5

function Log {
  param([string]$Message)
  $line = (Get-Date -Format s) + ' ' + $Message + [Environment]::NewLine
  [IO.File]::AppendAllText((Join-Path $OutDir 'run.log'), $line, [Text.Encoding]::UTF8)
}

function Get-KvWindows {
  param([int]$ProcessIdValue)
  $root = [Windows.Automation.AutomationElement]::RootElement
  $pidCondition = New-Object Windows.Automation.PropertyCondition(
    [Windows.Automation.AutomationElement]::ProcessIdProperty,
    $ProcessIdValue
  )
  $windowCondition = New-Object Windows.Automation.PropertyCondition(
    [Windows.Automation.AutomationElement]::ControlTypeProperty,
    [Windows.Automation.ControlType]::Window
  )
  $root.FindAll(
    [Windows.Automation.TreeScope]::Descendants,
    (New-Object Windows.Automation.AndCondition($pidCondition, $windowCondition))
  )
}

function Close-ConversionResultDialogs {
  param([int]$ProcessIdValue)
  $convertResultTitle = -join ([char[]](0x8F6C,0x6362,0x7ED3,0x679C))
  $closed = 0
  foreach ($window in @(Get-KvWindows $ProcessIdValue)) {
    $name = [string]$window.Current.Name
    $class = [string]$window.Current.ClassName
    if ($name -ne $convertResultTitle -or $class -ne '#32770') { continue }
    $hwnd = [IntPtr]$window.Current.NativeWindowHandle
    $ok = [KvTreeHandleWin32]::GetDlgItem($hwnd, 1)
    if ($ok -ne [IntPtr]::Zero) {
      [KvTreeHandleWin32]::SetForegroundWindow($hwnd) | Out-Null
      Start-Sleep -Milliseconds 100
      [KvTreeHandleWin32]::SendMessage($ok, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero) | Out-Null
      Start-Sleep -Milliseconds 400
      $closed++
      Log "closed conversion result dialog by OK hwnd=$($hwnd.ToInt64())"
      continue
    }
    $patternObj = $null
    if ($window.TryGetCurrentPattern([Windows.Automation.WindowPattern]::Pattern, [ref]$patternObj)) {
      $patternObj.Close()
      Start-Sleep -Milliseconds 400
      $closed++
      Log "closed conversion result dialog by WindowPattern hwnd=$($hwnd.ToInt64())"
    }
  }
  $closed
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
  $treeCandidates = @()
  $allVisibleChildren = @()
  do {
    $children = [KvTreeHandleWin32]::EnumChildren($process.MainWindowHandle)
    $candidateList = [System.Collections.Generic.List[object]]::new()
    $visibleList = [System.Collections.Generic.List[object]]::new()
    foreach ($child in $children) {
      if (-not [KvTreeHandleWin32]::IsWindowVisible($child)) { continue }
      $className = Get-ClassName $child
      $title = Get-WindowTitle $child
      $rect = Get-WindowRectObject $child
      $width = $rect.Right - $rect.Left
      $height = $rect.Bottom - $rect.Top
      $visibleList.Add([pscustomobject]@{
        hwnd = $child
        class = $className
        title = $title
        left = $rect.Left
        top = $rect.Top
        right = $rect.Right
        bottom = $rect.Bottom
        width = $width
        height = $height
      })
      if ($className -notlike '*SysTreeView32*') { continue }
      if ($width -lt 300 -or $height -lt 60) { continue }
      $candidateList.Add([pscustomobject]@{
        hwnd = $child
        class = $className
        title = $title
        left = $rect.Left
        top = $rect.Top
        right = $rect.Right
        bottom = $rect.Bottom
        width = $width
        height = $height
        distance_to_bottom = [math]::Abs($mainRect.Bottom - $rect.Bottom)
      })
    }
    $treeCandidates = @($candidateList)
    $allVisibleChildren = @($visibleList)
    if ($treeCandidates.Count -gt 0) { break }
    Start-Sleep -Milliseconds 150
  } while ($lookupWatch.ElapsedMilliseconds -lt $MaxLookupMs)

  if ($treeCandidates.Count -eq 0) {
    $allVisibleChildren |
      Sort-Object top,left |
      ConvertTo-Json -Depth 5 |
      Set-Content -LiteralPath (Join-Path $OutDir 'visible_children_no_result_tree.json') -Encoding UTF8
    throw "No visible result SysTreeView32 candidates found under KV STUDIO within ${MaxLookupMs}ms."
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
  $compileResultPath = Join-Path $OutDir 'compile_result_copied.txt'
  Set-Content -LiteralPath $compileResultPath -Value $text -Encoding UTF8
  Log "copied_result_length=$($text.Length)"

  $okNeedle = (-join ([char[]](0x8F6C,0x6362,0x7ED3,0x679C))) + ' OK'
  $ngNeedle = (-join ([char[]](0x8F6C,0x6362,0x7ED3,0x679C))) + ' NG'
  $clipboard = ''
  $clipboardOk = $false
  try {
    [Windows.Forms.Clipboard]::SetText($text)
    $clipboard = [Windows.Forms.Clipboard]::GetText()
    $clipboardOk = (-not [string]::IsNullOrWhiteSpace($clipboard) -and $clipboard.Contains($okNeedle))
  } catch {
    Log "clipboard mirror failed: $($_.Exception.Message)"
  }
  if ($text.Contains($ngNeedle)) {
    [pscustomobject]@{
      ok = $false
      error_code = 'KV_COMPILE_RESULT_NG'
      message = 'KV STUDIO conversion result is NG.'
      route = 'win32_child_hwnd_to_uia_treeitem_to_file_clipboard_optional'
      lookup_ms = $lookupWatch.ElapsedMilliseconds
      line_count = $lines.Count
      clipboard_length = $clipboard.Length
      contains_ok = $text.Contains($okNeedle)
      contains_ng = $true
      clipboard_contains_ok = $clipboardOk
      compile_result_path = $compileResultPath
    } | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'result.json') -Encoding UTF8
    throw 'KV_COMPILE_RESULT_NG: KV STUDIO conversion result is NG. See compile_result_copied.txt.'
  }
  if (-not $text.Contains($okNeedle)) { throw "Copied text does not contain expected OK marker: $okNeedle" }

  [pscustomobject]@{
    ok = $true
    route = 'win32_child_hwnd_to_uia_treeitem_to_file_clipboard_optional'
    lookup_ms = $lookupWatch.ElapsedMilliseconds
    line_count = $lines.Count
    clipboard_length = $clipboard.Length
    contains_ok = $text.Contains($okNeedle)
    contains_ng = $text.Contains($ngNeedle)
    clipboard_contains_ok = $clipboardOk
    compile_result_path = $compileResultPath
  } | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $OutDir 'result.json') -Encoding UTF8
  [void](Close-ConversionResultDialogs -ProcessIdValue $process.Id)
  Log 'done'
} catch {
  Log ('ERROR ' + $_.Exception.ToString())
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  exit 1
}
