param(
  [string]$OutDir = ('C:\Users\Public\KVSkillPractice\official_repro\vm-103\visible_convert_errors_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Log([string]$Message) {
  Add-Content -LiteralPath (Join-Path $OutDir 'run.log') -Value ((Get-Date -Format s) + ' ' + $Message) -Encoding UTF8
}

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KvVisibleErrOps {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int X, int Y);
  [DllImport("user32.dll")] public static extern void mouse_event(uint f, uint x, uint y, uint d, UIntPtr e);
}
"@

function Shot([string]$Name) {
  try {
    $bounds = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object System.Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
    $bitmap.Save((Join-Path $OutDir $Name), [System.Drawing.Imaging.ImageFormat]::Png)
    $graphics.Dispose()
    $bitmap.Dispose()
    Log "shot $Name"
  } catch {
    Log ('shot_err ' + $_.Exception.Message)
  }
}

function DumpUi([string]$FileName) {
  try {
    $process = Get-Process Kvs -ErrorAction Stop | Select-Object -First 1
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $condition = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $process.Id)
    $items = $root.FindAll([System.Windows.Automation.TreeScope]::Subtree, $condition)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('PID={0} TITLE={1} COUNT={2}' -f $process.Id, $process.MainWindowTitle, $items.Count))
    for ($index = 0; $index -lt $items.Count; $index++) {
      try {
        $element = $items.Item($index)
        $current = $element.Current
        $rect = $current.BoundingRectangle
        $elementName = ($current.Name -replace "`r|`n", ' ')
        if ($elementName -or $current.ClassName -or $current.AutomationId) {
          $lines.Add(('{0}`t{1}`t{2}`t{3}`t{4}`t{5},{6},{7},{8}' -f $index, $current.ControlType.ProgrammaticName, $elementName, $current.ClassName, $current.AutomationId, [int]$rect.Left, [int]$rect.Top, [int]$rect.Width, [int]$rect.Height))
        }
      } catch {}
    }
    [IO.File]::WriteAllLines((Join-Path $OutDir $FileName), $lines, [Text.UTF8Encoding]::new($false))
  } catch {
    Log ('dump_ui_err ' + $_.Exception.Message)
  }
}

function ClickPoint([int]$X, [int]$Y, [string]$Label) {
  [KvVisibleErrOps]::SetCursorPos($X, $Y) | Out-Null
  Start-Sleep -Milliseconds 80
  [KvVisibleErrOps]::mouse_event(2, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 60
  [KvVisibleErrOps]::mouse_event(4, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 250
  Log "click $Label $X,$Y"
}

function RightClickPoint([int]$X, [int]$Y, [string]$Label) {
  [KvVisibleErrOps]::SetCursorPos($X, $Y) | Out-Null
  Start-Sleep -Milliseconds 80
  [KvVisibleErrOps]::mouse_event(8, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 60
  [KvVisibleErrOps]::mouse_event(16, 0, 0, 0, [UIntPtr]::Zero)
  Start-Sleep -Milliseconds 350
  Log "right_click $Label $X,$Y"
}

function Capture([string]$Label, [string]$Keys, [int]$DelayMs = 600) {
  try { [System.Windows.Forms.Clipboard]::Clear() } catch {}
  [System.Windows.Forms.SendKeys]::SendWait($Keys)
  Start-Sleep -Milliseconds $DelayMs
  $text = ''
  try { $text = [System.Windows.Forms.Clipboard]::GetText() } catch {}
  Set-Content -LiteralPath (Join-Path $OutDir ("clip_$Label.txt")) -Value $text -Encoding UTF8
  Log ('capture {0} chars={1}' -f $Label, $text.Length)
  return $text
}

try {
  Log 'start visible error collection'
  $process = Get-Process Kvs -ErrorAction Stop | Select-Object -First 1
  [KvVisibleErrOps]::ShowWindow($process.MainWindowHandle, 3) | Out-Null
  Start-Sleep -Milliseconds 500
  [KvVisibleErrOps]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
  Start-Sleep -Milliseconds 800
  Shot '00_visible.png'
  DumpUi 'ui_visible.txt'

  $attempts = @(
    @{ Label='title_ctrl_a_c'; X=220; Y=530; Kind='left'; Keys='^a^c' },
    @{ Label='row_ctrl_c'; X=215; Y=552; Kind='left'; Keys='^c' },
    @{ Label='row_ctrl_a_c'; X=215; Y=552; Kind='left'; Keys='^a^c' },
    @{ Label='row_context_c'; X=215; Y=552; Kind='right'; Keys='c' },
    @{ Label='row_context_down_enter'; X=215; Y=552; Kind='right'; Keys='{DOWN}{ENTER}' },
    @{ Label='body_ctrl_a_c'; X=430; Y=610; Kind='left'; Keys='^a^c' },
    @{ Label='body_context_c'; X=430; Y=610; Kind='right'; Keys='c' }
  )

  $summary = foreach ($attempt in $attempts) {
    if ($attempt.Kind -eq 'right') {
      RightClickPoint $attempt.X $attempt.Y $attempt.Label
    } else {
      ClickPoint $attempt.X $attempt.Y $attempt.Label
    }
    $text = Capture $attempt.Label $attempt.Keys 900
    [pscustomobject]@{
      Label = $attempt.Label
      TextLength = $text.Length
      Preview = (($text -replace "`r|`n", ' ').Substring(0, [Math]::Min(180, $text.Length)))
    }
  }

  Shot '01_after_attempts.png'
  DumpUi 'ui_after_attempts.txt'
  $summary | ConvertTo-Json -Depth 3 | Set-Content -LiteralPath (Join-Path $OutDir 'capture_summary.json') -Encoding UTF8
  'done' | Set-Content -LiteralPath (Join-Path $OutDir 'done.txt') -Encoding ASCII
  exit 0
} catch {
  Log ('ERR ' + $_.Exception.ToString())
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  exit 1
}
