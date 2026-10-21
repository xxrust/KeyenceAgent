# Read-only window/process binding that does not rely on MainWindowTitle.
# Root cause this fixes: when KV STUDIO shows the conversion result panel, the .NET
# MainWindowTitle/MainWindowHandle of the Kvs process can point at that panel (or be
# empty), so every title-based project lookup fails even though the project editor is
# open and healthy.  Bind the process by its command line and the editor window by a
# semantic anchor (the project tree control) instead.

function Get-KvProcessesByCommandLine {
  param([Parameter(Mandatory=$true)][string]$Needle)
  if (-not $Needle) { return @() }
  $hits = @(Get-CimInstance Win32_Process -Filter "Name='Kvs.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -and $_.CommandLine.IndexOf($Needle, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
  return @($hits | ForEach-Object { Get-Process -Id ([int]$_.ProcessId) -ErrorAction SilentlyContinue } | Where-Object { $_ })
}

function Test-KvWindowHasProjectTree {
  param([Parameter(Mandatory=$true)][IntPtr]$Hwnd)
  if ($Hwnd -eq [IntPtr]::Zero) { return $false }
  try {
    Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue
    Add-Type -AssemblyName UIAutomationTypes -ErrorAction SilentlyContinue
    $root = [System.Windows.Automation.AutomationElement]::FromHandle($Hwnd)
    if (-not $root) { return $false }
    $cond = New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty, 'ProjectTreeView')
    $tree = $root.FindFirst([System.Windows.Automation.TreeScope]::Descendants, $cond)
    return [bool]$tree
  } catch { return $false }
}

function Get-KvProjectEditorHwnd {
  param(
    [Parameter(Mandatory=$true)][int]$ProcessId,
    [string]$Needle = ''
  )
  try {
    Add-Type -AssemblyName UIAutomationClient -ErrorAction SilentlyContinue
    Add-Type -AssemblyName UIAutomationTypes -ErrorAction SilentlyContinue
    $root = [System.Windows.Automation.AutomationElement]::RootElement
    $wins = $root.FindAll([System.Windows.Automation.TreeScope]::Children, [System.Windows.Automation.Condition]::TrueCondition)
    $fallback = [IntPtr]::Zero
    $fallbackTitle = ''
    foreach ($w in $wins) {
      try { if ($w.Current.ProcessId -ne $ProcessId) { continue } } catch { continue }
      $h = [IntPtr]$w.Current.NativeWindowHandle
      if ($h -eq [IntPtr]::Zero) { continue }
      if (Test-KvWindowHasProjectTree -Hwnd $h) { return $h }
      $name = [string]$w.Current.Name
      if ($Needle -and $name -like "KV STUDIO*$Needle*") { $fallback = $h; $fallbackTitle = $name }
    }
    return $fallback
  } catch { return [IntPtr]::Zero }
}