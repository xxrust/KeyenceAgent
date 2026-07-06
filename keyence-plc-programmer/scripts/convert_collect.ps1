param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [string]$OutDir = (Join-Path ([IO.Path]::GetTempPath()) ('keyence-plc-programmer\kvtool\convert_' + (Get-Date -Format 'yyyyMMdd_HHmmss'))),

  [string]$KvsExe = 'C:\Program Files (x86)\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe',

  [int]$OpenWaitSeconds = 15,

  [int]$ConvertWaitSeconds = 150,

  [switch]$RestartKvs
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class KvToolWindow {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
}
"@

function Write-RunLog {
  param([string]$Message)
  Add-Content -LiteralPath (Join-Path $OutDir 'run.log') -Value ((Get-Date -Format s) + ' ' + $Message) -Encoding UTF8
}

function Save-Screenshot {
  param([string]$Name)
  try {
    $bounds = [Windows.Forms.Screen]::PrimaryScreen.Bounds
    $bitmap = New-Object Drawing.Bitmap $bounds.Width, $bounds.Height
    $graphics = [Drawing.Graphics]::FromImage($bitmap)
    $graphics.CopyFromScreen(0, 0, 0, 0, $bitmap.Size)
    $path = Join-Path $OutDir $Name
    $bitmap.Save($path)
    $graphics.Dispose()
    $bitmap.Dispose()
    Write-RunLog "screenshot $Name"
  } catch {
    Write-RunLog ('screenshot failed: ' + $_.Exception.Message)
  }
}

function Save-UiaDump {
  param([string]$Name)
  try {
    Add-Type -AssemblyName UIAutomationClient
    Add-Type -AssemblyName UIAutomationTypes
    $process = Get-Process Kvs -ErrorAction Stop | Select-Object -First 1
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $condition = New-Object System.Windows.Automation.PropertyCondition(
      [System.Windows.Automation.AutomationElement]::ProcessIdProperty,
      $process.Id
    )
    $items = $root.FindAll([System.Windows.Automation.TreeScope]::Subtree, $condition)
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add(('PID=' + $process.Id + ' TITLE=' + $process.MainWindowTitle + ' COUNT=' + $items.Count))
    for ($i = 0; $i -lt $items.Count; $i++) {
      try {
        $element = $items.Item($i)
        $current = $element.Current
        $nameText = ($current.Name -replace "`r|`n", ' ')
        if ($nameText -or $current.AutomationId -or $current.ClassName) {
          $lines.Add(('{0}`t{1}`t{2}`t{3}`t{4}' -f $i, $current.ControlType.ProgrammaticName, $nameText, $current.ClassName, $current.AutomationId))
        }
      } catch {
      }
    }
    [IO.File]::WriteAllLines((Join-Path $OutDir $Name), $lines, [Text.UTF8Encoding]::new($false))
    Write-RunLog "uia $Name"
  } catch {
    Write-RunLog ('uia dump failed: ' + $_.Exception.Message)
  }
}

try {
  Write-RunLog 'start convert_collect'
  Write-RunLog "ProjectPath=$ProjectPath"
  Write-RunLog "KvsExe=$KvsExe"
  Write-RunLog "OutDir=$OutDir"

  if (-not (Test-Path -LiteralPath $ProjectPath)) {
    throw "ProjectPath not found: $ProjectPath"
  }
  if (-not (Test-Path -LiteralPath $KvsExe)) {
    throw "KvsExe not found: $KvsExe"
  }

  if ($RestartKvs) {
    Get-Process Kvs -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  }

  $process = Get-Process Kvs -ErrorAction SilentlyContinue | Select-Object -First 1
  if (-not $process) {
    Start-Process -FilePath $KvsExe -ArgumentList ('"' + $ProjectPath + '"') | Out-Null
    Write-RunLog 'started Kvs with project'
  } else {
    Write-RunLog ('using existing Kvs pid=' + $process.Id)
  }

  $deadline = (Get-Date).AddSeconds(90)
  do {
    Start-Sleep -Seconds 2
    $process = Get-Process Kvs -ErrorAction SilentlyContinue | Select-Object -First 1
  } while ((-not $process -or $process.MainWindowHandle -eq 0) -and (Get-Date) -lt $deadline)
  if (-not $process -or $process.MainWindowHandle -eq 0) {
    throw 'Kvs main window was not found.'
  }

  [KvToolWindow]::ShowWindow($process.MainWindowHandle, 3) | Out-Null
  Start-Sleep -Milliseconds 500
  [KvToolWindow]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
  Start-Sleep -Seconds $OpenWaitSeconds

  $process = Get-Process -Id $process.Id
  Write-RunLog ('window=' + $process.MainWindowTitle)
  Save-Screenshot '00_opened.png'
  Save-UiaDump 'ui_00_opened.txt'

  [KvToolWindow]::SetForegroundWindow($process.MainWindowHandle) | Out-Null
  Start-Sleep -Milliseconds 500
  [System.Windows.Forms.SendKeys]::SendWait('^{F9}')
  Write-RunLog 'sent Ctrl+F9'
  Start-Sleep -Seconds $ConvertWaitSeconds

  Save-Screenshot '01_after_convert_wait.png'
  Save-UiaDump 'ui_01_after_convert_wait.txt'

  try { [System.Windows.Forms.Clipboard]::Clear() } catch {}
  [System.Windows.Forms.SendKeys]::SendWait('^c')
  Start-Sleep -Milliseconds 700
  try {
    Set-Content -LiteralPath (Join-Path $OutDir 'clipboard_after_convert.txt') -Value ([System.Windows.Forms.Clipboard]::GetText()) -Encoding UTF8
  } catch {
    Write-RunLog ('clipboard read failed: ' + $_.Exception.Message)
  }

  'done' | Set-Content -LiteralPath (Join-Path $OutDir 'done.txt') -Encoding UTF8
  Write-RunLog 'done'
} catch {
  Write-RunLog ('ERROR ' + $_.Exception.ToString())
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  exit 1
}
