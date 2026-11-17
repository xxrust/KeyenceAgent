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

# A basename is not a project identity: two copies commonly have the same name.
# Match one complete command-line argument, never a path substring or title alone.
function Test-KvProjectCommandLine {
  param([string]$CommandLine,[string]$ProjectPath)
  if (-not $CommandLine) { return $false }
  $path=[IO.Path]::GetFullPath($ProjectPath)
  $pattern='(?:^|\s)(?:"'+[regex]::Escape($path)+'"|'+[regex]::Escape($path)+')(?=\s|$)'
  return [bool]($CommandLine -match $pattern)
}

function Get-KvProjectSession {
  param([Parameter(Mandatory=$true)][string]$ProjectPath,[string]$CreatedProjectResultPath='',[switch]$AllowMissing)
  $path=[IO.Path]::GetFullPath($ProjectPath)
  $bound=@(Get-CimInstance Win32_Process -Filter "Name='Kvs.exe'" -ErrorAction Stop |
    Where-Object { Test-KvProjectCommandLine $_.CommandLine $path } |
    ForEach-Object { Get-Process -Id ([int]$_.ProcessId) -ErrorAction SilentlyContinue })
  if ($CreatedProjectResultPath) {
    . (Join-Path $PSScriptRoot 'kv_project_process_binding.ps1')
    $created=Get-KvCreatedProjectProcess $path $CreatedProjectResultPath
    if (@($bound | Where-Object { $_.Id -ne $created.Id }).Count) { throw 'KV_PROJECT_PROCESS_AMBIGUOUS' }
    $bound=@($created)
  }
  if ($bound.Count -gt 1) { throw 'KV_PROJECT_PROCESS_AMBIGUOUS' }
  if (-not $bound.Count) {
    if ($AllowMissing) { return $null }
    throw 'KV_PROJECT_PATH_BOUND_PROCESS_MISSING'
  }
  $process=$bound[0]
  $hwnd=Get-KvProjectEditorHwnd -ProcessId $process.Id
  if ($hwnd -eq [IntPtr]::Zero) {
    if ($AllowMissing) { return $null }
    throw 'KV_PROJECT_EDITOR_WINDOW_MISSING'
  }
  $element=[Windows.Automation.AutomationElement]::FromHandle($hwnd)
  $title=[string]$element.Current.Name
  $pattern='^KV STUDIO.* - \['+[regex]::Escape([IO.Path]::GetFileNameWithoutExtension($path))+'(?: \*)?\]$'
  if ($title -notmatch $pattern) { throw 'KV_PROJECT_WINDOW_IDENTITY_MISMATCH' }
  $cpu=''
  if ($title -match '\[编辑器:\s*(KV-[A-Za-z0-9-]+)\]') { $cpu=$matches[1] }
  [pscustomobject]@{project_path=$path;process_id=$process.Id;process_start_utc=$process.StartTime.ToUniversalTime().ToString('o');hwnd=$hwnd;title=$title;cpu_model=$cpu;kvs_exe=$process.Path;kvs_version=$process.FileVersion}
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
