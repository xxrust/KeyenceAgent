param(
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$ProjectPath = '',
  [string[]]$Items = @('轴组设定','运动通用设定','点参数','同步控制设定','点胶A','点胶B','点胶C'),
  [switch]$PlanOnly
)
$Items = @($Items | ForEach-Object { $_ -split ',' } | Where-Object { $_.Trim() } | ForEach-Object { $_.Trim() })
# Read-only capture of the motion settings views: select the project-tree item,
# open it, copy the table through the clipboard and keep a screenshot for the
# labels/headers that VSFlexGrid does not include in the copy.
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -TypeDefinition @"
using System;
using System.Runtime.InteropServices;
public class MotionWin {
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint dx, uint dy, uint d, IntPtr e);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  public static void Click(int x, int y) { SetCursorPos(x, y); System.Threading.Thread.Sleep(80); mouse_event(0x0002, 0, 0, 0, IntPtr.Zero); mouse_event(0x0004, 0, 0, 0, IntPtr.Zero); }
}
"@
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'guards\kv_ui_guard.ps1')
$null = Initialize-KvUiGuard -OutDir (Join-Path $OutDir 'guard')
$resultPath = Join-Path $OutDir 'motion_settings_result.json'
$needle = if ($ProjectPath) { [IO.Path]::GetFileNameWithoutExtension($ProjectPath) } else { '' }
$process = $null
$deadline = (Get-Date).AddSeconds(10)
do {
  $process = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and ($needle -eq '' -or $_.MainWindowTitle -like "*$needle*") }) | Select-Object -First 1
  if ($process) { break }
  Start-Sleep -Milliseconds 250
} while ((Get-Date) -lt $deadline)
if (-not $process) { throw "KV_MOTION_PROJECT_NOT_OPEN: $ProjectPath" }
$main = [System.Windows.Automation.AutomationElement]::FromHandle($process.MainWindowHandle)
$tree = $main.FindFirst([System.Windows.Automation.TreeScope]::Descendants,
  (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'ProjectTreeView')))
if (-not $tree) { throw 'KV_MOTION_PROJECT_TREE_MISSING' }
# Expand 运动设定 so its children exist in the UIA tree.
$motionRoot = $null
foreach ($element in $tree.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)) {
  if ($element.Current.Name -eq '运动设定') { $motionRoot = $element; break }
}
if ($motionRoot) {
  $expand = $null
  if ($motionRoot.TryGetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$expand)) { $expand.Expand() }
  Start-Sleep -Milliseconds 800
}
$rect = New-Object MotionWin+RECT
[void][MotionWin]::GetWindowRect($process.MainWindowHandle, [ref]$rect)
$records = @()
$exitCode = 0
foreach ($item in $Items) {
  $record = [ordered]@{ item = $item; ok = $false; rows = 0; chars = 0; tsv = ''; screenshot = ''; error = '' }
  try {
    $elements = $tree.FindAll([System.Windows.Automation.TreeScope]::Descendants, [System.Windows.Automation.Condition]::TrueCondition)
    $target = $null
    foreach ($element in $elements) { if ($element.Current.Name -eq $item) { $target = $element; break } }
    if (-not $target) { throw "KV_MOTION_ITEM_MISSING: $item" }
    [void][MotionWin]::SetForegroundWindow($process.MainWindowHandle)
    Start-Sleep -Milliseconds 300
    $selection = $null
    if ($target.TryGetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern, [ref]$selection)) { $selection.Select() }
    Start-Sleep -Milliseconds 400
    Invoke-KvGuardedSendKeys -TargetHwnd $process.MainWindowHandle -Step 'motion open item' -Keys '{ENTER}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 300
    Start-Sleep -Milliseconds 1800
    $safe = ($item -replace '[^\w\u4e00-\u9fff]+', '_')
    Invoke-KvGuardedMouseClick -TargetHwnd $process.MainWindowHandle -Step 'motion table focus' -X ($rect.L + 600) -Y ($rect.T + 260) -ExpectedTitleLike 'KV STUDIO*'
    Start-Sleep -Milliseconds 300
    Invoke-KvGuardedSendKeys -TargetHwnd $process.MainWindowHandle -Step 'motion table home' -Keys '^{HOME}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 200
    Start-Sleep -Milliseconds 200
    Invoke-KvGuardedSendKeys -TargetHwnd $process.MainWindowHandle -Step 'motion table range' -Keys '^+{END}' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 300
    Start-Sleep -Milliseconds 300
    Invoke-KvGuardedSendKeys -TargetHwnd $process.MainWindowHandle -Step 'motion table copy' -Keys '^c' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 500
    Start-Sleep -Milliseconds 700
    $text = [System.Windows.Forms.Clipboard]::GetText()
    $lines = @($text -split "`r?`n" | Where-Object { $_.Trim() })
    $tsvPath = Join-Path $OutDir ($safe + '.tsv')
    [IO.File]::WriteAllText($tsvPath, $text, (New-Object Text.UTF8Encoding($false)))
    $width = $rect.R - $rect.L
    $height = $rect.B - $rect.T
    $bmp = New-Object System.Drawing.Bitmap $width, $height
    $graphics = [System.Drawing.Graphics]::FromImage($bmp)
    $graphics.CopyFromScreen($rect.L, $rect.T, 0, 0, $bmp.Size)
    $shotPath = Join-Path $OutDir ($safe + '.png')
    $bmp.Save($shotPath, [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose(); $bmp.Dispose()
    $record.ok = ($lines.Count -gt 0)
    $record.rows = $lines.Count
    $record.chars = $text.Length
    $record.tsv = $tsvPath
    $record.screenshot = $shotPath
    if (-not $record.ok) { $record.error = 'empty clipboard'; $exitCode = 41 }
  } catch {
    $record.error = $_.Exception.Message
    $exitCode = 41
  }
  $records += [pscustomobject]$record
  Write-Host ("MOTION: {0} rows={1} ok={2} {3}" -f $item, $record.rows, $record.ok, $record.error)
}
$result = [ordered]@{
  ok = ($exitCode -eq 0)
  planned = [bool]$PlanOnly
  project_path = $ProjectPath
  items = $records
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8
$result | ConvertTo-Json -Depth 4
exit $exitCode
