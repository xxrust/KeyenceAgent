param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectName,
  [Parameter(Mandatory=$true)]
  [string[]]$UnitNamePatterns,
  [string]$ProjectPath = '',
  [int]$MaxScanSteps = 120,
  [int]$MaxDurationSeconds = 180,
  [string]$OutDir = 'C:\Users\Public\KVSkillPractice\kv_unit_config_runs',
  [switch]$KeepWindowOpen
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
Add-Type -AssemblyName UIAutomationClient,UIAutomationTypes,System.Windows.Forms

if (-not ('KvExpansionUnitWin32' -as [type])) {
  Add-Type @"
using System;
using System.Text;
using System.Runtime.InteropServices;
public class KvExpansionUnitWin32 {
  public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);
  [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool IsWindowEnabled(IntPtr hWnd);
  [DllImport("user32.dll")] public static extern bool PostMessage(IntPtr hWnd, int Msg, IntPtr wParam, IntPtr lParam);
  [DllImport("user32.dll")] public static extern bool EnumChildWindows(IntPtr hWnd, EnumWindowsProc lpEnumFunc, IntPtr lParam);
  [DllImport("user32.dll")] public static extern IntPtr GetParent(IntPtr hWnd);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetWindowText(IntPtr hWnd, StringBuilder lpString, int nMaxCount);
  [DllImport("user32.dll", CharSet=CharSet.Unicode)] public static extern int GetClassName(IntPtr hWnd, StringBuilder lpClassName, int nMaxCount);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr hWnd, out uint lpdwProcessId);
}
"@
}

$BM_CLICK = 0x00F5
$WM_CLOSE = 0x0010
$NameUnitConfiguration = -join ([char[]](0x5355,0x5143,0x914D,0x7F6E))
$NameCpuUnit = '[0]  KV-X310'
$NameUnitEditor = (-join ([char[]](0x5355,0x5143,0x7F16,0x8F91,0x5668))) + '*'
$NameOkCn = -join ([char[]](0x786E,0x5B9A))
$NameConvertResult = -join ([char[]](0x8F6C,0x6362,0x7ED3,0x679C))

function Normalize-UnitNamePatterns {
  $normalized = @()
  foreach ($item in @($UnitNamePatterns)) {
    foreach ($part in ([string]$item -split ',')) {
      $trimmed = $part.Trim()
      if ($trimmed) { $normalized += $trimmed }
    }
  }
  if ($normalized.Count -eq 0) { throw 'UnitNamePatterns must contain at least one unit name or wildcard pattern.' }
  $script:UnitNamePatterns = $normalized
}

function New-EvidencePath([string]$Name) {
  Join-Path $OutDir ("{0}_{1}.json" -f (Get-Date -Format 'yyyyMMdd_HHmmss_fff'), $Name)
}

function Write-JsonFile([string]$Path, $Value) {
  $Value | ConvertTo-Json -Depth 16 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Assert-TimeBudget {
  param([Diagnostics.Stopwatch]$Stopwatch, [string]$Step)
  if ($Stopwatch.Elapsed.TotalSeconds -gt $MaxDurationSeconds) {
    throw "KV_EXPANSION_UNIT_TIMEOUT: step '$Step' exceeded MaxDurationSeconds=$MaxDurationSeconds elapsed=$([math]::Round($Stopwatch.Elapsed.TotalSeconds, 3))"
  }
}

function Get-KvsProcess {
  $process = Get-Process Kvs -ErrorAction SilentlyContinue |
    Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like "*$ProjectName*" } |
    Select-Object -First 1
  if (-not $process) { throw "KV STUDIO process with project '$ProjectName' was not found." }
  $process
}

function Get-VisibleTopWindows {
  $rows = New-Object System.Collections.ArrayList
  $callback = [KvExpansionUnitWin32+EnumWindowsProc]{
    param($handle, $lParam)
    if ([KvExpansionUnitWin32]::IsWindowVisible($handle)) {
      $titleBuilder = [Text.StringBuilder]::new(512)
      $classBuilder = [Text.StringBuilder]::new(256)
      [void][KvExpansionUnitWin32]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity)
      [void][KvExpansionUnitWin32]::GetClassName($handle, $classBuilder, $classBuilder.Capacity)
      $procIdValue = [uint32]0
      [void][KvExpansionUnitWin32]::GetWindowThreadProcessId($handle, [ref]$procIdValue)
      $processName = ''
      try { $processName = (Get-Process -Id ([int]$procIdValue) -ErrorAction Stop).ProcessName } catch {}
      [void]$rows.Add([pscustomobject]@{
        hwnd = $handle.ToInt64()
        process_id = [int]$procIdValue
        process_name = $processName
        title = $titleBuilder.ToString()
        class_name = $classBuilder.ToString()
      })
    }
    return $true
  }
  [void][KvExpansionUnitWin32]::EnumWindows($callback, [IntPtr]::Zero)
  @($rows)
}

function Get-KvRelevantWindows {
  $process = Get-KvsProcess
  Get-VisibleTopWindows | Where-Object {
    $_.process_id -eq $process.Id -and (
      $_.title -like 'KV STUDIO*' -or
      $_.title -like $NameUnitEditor -or
      $_.title -eq $NameConvertResult -or
      $_.class_name -eq '#32770'
    )
  } | Sort-Object title, hwnd
}

function Close-StaleConvertResultDialogs {
  $closed = @()
  foreach ($window in @(Get-KvRelevantWindows | Where-Object { $_.title -eq $NameConvertResult })) {
    [void][KvExpansionUnitWin32]::PostMessage([IntPtr]$window.hwnd, $WM_CLOSE, [IntPtr]::Zero, [IntPtr]::Zero)
    $closed += $window
    Start-Sleep -Milliseconds 300
  }
  $closed
}

function Get-ElementFromHwnd([long]$Hwnd) {
  $element = [Windows.Automation.AutomationElement]::FromHandle([IntPtr]$Hwnd)
  if (-not $element) { throw "AutomationElement.FromHandle failed for $Hwnd." }
  $element
}

function Get-MainWindowElement {
  $process = Get-KvsProcess
  Get-ElementFromHwnd -Hwnd $process.MainWindowHandle
}

function Find-Descendant {
  param([Windows.Automation.AutomationElement]$Root, [scriptblock]$Predicate)
  $all = $Root.FindAll([Windows.Automation.TreeScope]::Descendants, [Windows.Automation.Condition]::TrueCondition)
  for ($i = 0; $i -lt $all.Count; $i++) {
    $e = $all.Item($i)
    if (& $Predicate $e) { return $e }
  }
  $null
}

function Find-TreeItemInMain {
  param([string]$Exact = '', [string]$Contains = '')
  $window = Get-MainWindowElement
  Find-Descendant -Root $window -Predicate {
    param($e)
    try {
      if ($e.Current.ControlType.ProgrammaticName -ne 'ControlType.TreeItem') { return $false }
      $name = $e.Current.Name
      if ($Exact -and $name -eq $Exact) { return $true }
      if ($Contains -and $name.Contains($Contains)) { return $true }
      $false
    } catch {
      $false
    }
  }
}

function Expand-TreeItem {
  param([Windows.Automation.AutomationElement]$Item, [string]$Label)
  if (-not $Item) { throw "Tree item '$Label' was not found." }
  $pattern = $null
  if ($Item.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern, [ref]$pattern)) {
    try { $pattern.ScrollIntoView() } catch {}
  }
  $pattern = $null
  if ($Item.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
    try { $pattern.Select(); Start-Sleep -Milliseconds 100 } catch {}
  }
  $pattern = $null
  if (-not $Item.TryGetCurrentPattern([Windows.Automation.ExpandCollapsePattern]::Pattern, [ref]$pattern)) {
    return 'NoExpandCollapsePattern'
  }
  if ($pattern.Current.ExpandCollapseState -ne [Windows.Automation.ExpandCollapseState]::Expanded) {
    $pattern.Expand()
    Start-Sleep -Milliseconds 300
  }
  $pattern.Current.ExpandCollapseState.ToString()
}

function Set-ForegroundWindowByHwnd([long]$Hwnd) {
  if ([KvExpansionUnitWin32]::IsIconic([IntPtr]$Hwnd)) {
    [KvExpansionUnitWin32]::ShowWindow([IntPtr]$Hwnd, 9) | Out-Null
  }
  [KvExpansionUnitWin32]::SetForegroundWindow([IntPtr]$Hwnd) | Out-Null
  Start-Sleep -Milliseconds 200
}

function Send-EnterToElement([Windows.Automation.AutomationElement]$Element) {
  $pattern = $null
  if ($Element.TryGetCurrentPattern([Windows.Automation.ScrollItemPattern]::Pattern, [ref]$pattern)) {
    try { $pattern.ScrollIntoView() } catch {}
  }
  $pattern = $null
  if ($Element.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern, [ref]$pattern)) {
    try { $pattern.Select(); Start-Sleep -Milliseconds 100 } catch {}
  }
  $Element.SetFocus()
  Start-Sleep -Milliseconds 120
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Start-Sleep -Milliseconds 700
}

function Wait-TopWindow([scriptblock]$Predicate, [int]$TimeoutMs = 8000) {
  $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
  do {
    foreach ($window in @(Get-KvRelevantWindows)) {
      if (& $Predicate $window) { return $window }
    }
    Start-Sleep -Milliseconds 200
  } while ((Get-Date) -lt $deadline)
  $null
}

function Open-UnitEditor {
  $existing = Wait-TopWindow -TimeoutMs 500 -Predicate { param($w) $w.title -like $NameUnitEditor -and $w.class_name -like 'Afx:*' }
  if ($existing) { return [pscustomobject]@{ reused_existing = $true; window = $existing } }
  $unit = Find-TreeItemInMain -Exact $NameUnitConfiguration
  $unitState = Expand-TreeItem -Item $unit -Label 'unit configuration'
  $cpu = Find-TreeItemInMain -Exact $NameCpuUnit
  if (-not $cpu) { $cpu = Find-TreeItemInMain -Contains 'KV-X310' }
  if (-not $cpu) { throw 'CPU tree item KV-X310 was not found.' }
  $process = Get-KvsProcess
  Set-ForegroundWindowByHwnd -Hwnd $process.MainWindowHandle
  $cpuName = $cpu.Current.Name
  Send-EnterToElement -Element $cpu
  $editor = Wait-TopWindow -TimeoutMs 8000 -Predicate { param($w) $w.title -like $NameUnitEditor -and $w.class_name -like 'Afx:*' }
  if (-not $editor) { throw 'Unit editor window did not open after pressing Enter on CPU unit.' }
  [pscustomobject]@{
    reused_existing = $false
    unit_state = $unitState
    cpu_name = $cpuName
    window = $editor
  }
}

function Get-DescendantByAutomationId {
  param([Windows.Automation.AutomationElement]$Root, [string]$AutomationId)
  Find-Descendant -Root $Root -Predicate {
    param($e)
    try { $e.Current.AutomationId -eq $AutomationId } catch { $false }
  }
}

function Get-ElementText {
  param([Windows.Automation.AutomationElement]$Element)
  if (-not $Element) { return '' }
  $valuePattern = $null
  if ($Element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern, [ref]$valuePattern)) {
    try { return [string]$valuePattern.Current.Value } catch {}
  }
  try { return [string]$Element.Current.Name } catch {}
  ''
}

function Get-UnitSelectionDetail {
  param([Windows.Automation.AutomationElement]$EditorElement)
  $nameElement = Get-DescendantByAutomationId -Root $EditorElement -AutomationId '698'
  $descriptionElement = Get-DescendantByAutomationId -Root $EditorElement -AutomationId '697'
  $listElement = Get-DescendantByAutomationId -Root $EditorElement -AutomationId '566'
  [pscustomobject]@{
    name = Get-ElementText -Element $nameElement
    description = Get-ElementText -Element $descriptionElement
    list_hwnd = $(if ($listElement) { try { $listElement.Current.NativeWindowHandle } catch { 0 } } else { 0 })
    list_class = $(if ($listElement) { try { $listElement.Current.ClassName } catch { '' } } else { '' })
  }
}

function Test-UnitMatches {
  param([string]$Pattern, $Detail)
  $texts = @($Detail.name, $Detail.description) | Where-Object { $_ }
  foreach ($text in $texts) {
    if ($Pattern.Contains('*') -or $Pattern.Contains('?')) {
      if ($text -like $Pattern) { return $true }
    } else {
      if ($text -eq $Pattern) { return $true }
      if ($text.StartsWith($Pattern, [StringComparison]::OrdinalIgnoreCase)) {
        if ($text.Length -eq $Pattern.Length) { return $true }
        $next = $text.Substring($Pattern.Length, 1)
        if ($next -match '[\s\[\]\(\)_\-/]') { return $true }
      }
    }
  }
  $false
}

function Focus-UnitSelectionList {
  param([long]$UnitEditorHwnd)
  Set-ForegroundWindowByHwnd -Hwnd $UnitEditorHwnd
  [System.Windows.Forms.SendKeys]::SendWait('%1')
  Start-Sleep -Milliseconds 250
  [System.Windows.Forms.SendKeys]::SendWait('^{HOME}')
  Start-Sleep -Milliseconds 100
  [System.Windows.Forms.SendKeys]::SendWait('{HOME}')
  Start-Sleep -Milliseconds 150
}

function Select-And-AddUnit {
  param(
    [string]$Pattern,
    [Windows.Automation.AutomationElement]$EditorElement,
    [long]$UnitEditorHwnd,
    [Diagnostics.Stopwatch]$Stopwatch
  )
  Focus-UnitSelectionList -UnitEditorHwnd $UnitEditorHwnd
  $records = @()
  for ($i = 0; $i -le $MaxScanSteps; $i++) {
    Assert-TimeBudget -Stopwatch $Stopwatch -Step "scan $Pattern"
    $detail = Get-UnitSelectionDetail -EditorElement $EditorElement
    $matched = Test-UnitMatches -Pattern $Pattern -Detail $detail
    $records += [pscustomobject]@{
      step_index = $i
      name = $detail.name
      description = $detail.description
      matched = $matched
    }
    if ($matched) {
      [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
      Start-Sleep -Milliseconds 650
      return [pscustomobject]@{
        pattern = $Pattern
        found_at = $i
        selected_before_enter = $detail
        records_tail = @($records | Select-Object -Last 30)
      }
    }
    [System.Windows.Forms.SendKeys]::SendWait('{DOWN}')
    Start-Sleep -Milliseconds 55
  }
  throw "KV_EXPANSION_UNIT_NOT_FOUND: '$Pattern' not found after $MaxScanSteps scan steps."
}

function Get-ChildWindowRows([long]$ParentHwnd) {
  $rows = New-Object System.Collections.ArrayList
  $callback = [KvExpansionUnitWin32+EnumWindowsProc]{
    param($handle, $lParam)
    $titleBuilder = [Text.StringBuilder]::new(512)
    $classBuilder = [Text.StringBuilder]::new(256)
    [void][KvExpansionUnitWin32]::GetWindowText($handle, $titleBuilder, $titleBuilder.Capacity)
    [void][KvExpansionUnitWin32]::GetClassName($handle, $classBuilder, $classBuilder.Capacity)
    [void]$rows.Add([pscustomobject]@{
      hwnd = $handle.ToInt64()
      parent = ([KvExpansionUnitWin32]::GetParent($handle)).ToInt64()
      visible = [KvExpansionUnitWin32]::IsWindowVisible($handle)
      enabled = [KvExpansionUnitWin32]::IsWindowEnabled($handle)
      title = $titleBuilder.ToString()
      class_name = $classBuilder.ToString()
    })
    return $true
  }
  [void][KvExpansionUnitWin32]::EnumChildWindows([IntPtr]$ParentHwnd, $callback, [IntPtr]::Zero)
  @($rows)
}

function Invoke-ChildButtonByTitle {
  param([long]$ParentHwnd, [string[]]$Titles)
  $buttons = @(Get-ChildWindowRows -ParentHwnd $ParentHwnd | Where-Object {
    $_.visible -and $_.enabled -and $_.class_name -eq 'Button'
  })
  foreach ($title in $Titles) {
    $button = $buttons | Where-Object { $_.title -eq $title } | Select-Object -First 1
    if ($button) {
      [void][KvExpansionUnitWin32]::PostMessage([IntPtr]$button.hwnd, $BM_CLICK, [IntPtr]::Zero, [IntPtr]::Zero)
      Start-Sleep -Milliseconds 700
      return [pscustomobject]@{ title = $button.title; hwnd = $button.hwnd; method = 'PostMessage_BM_CLICK' }
    }
  }
  $null
}

function Invoke-UnitEditorOk {
  param($UnitEditorWindow)
  $button = Invoke-ChildButtonByTitle -ParentHwnd $UnitEditorWindow.hwnd -Titles @('OK')
  if (-not $button) { throw 'Unit editor OK button was not found.' }
  $button
}

function Get-DialogTextByHwnd([long]$Hwnd) {
  $children = @(Get-ChildWindowRows -ParentHwnd $Hwnd)
  (@($children | Where-Object { $_.class_name -eq 'Static' -and $_.title } | ForEach-Object { $_.title }) -join ' ')
}

function Handle-KvMessageDialogs {
  param([int]$TimeoutMs = 12000)
  $handled = @()
  $deadline = (Get-Date).AddMilliseconds($TimeoutMs)
  do {
    $dialog = @(Get-KvRelevantWindows | Where-Object { $_.class_name -eq '#32770' -and $_.title -eq 'KV STUDIO' } | Select-Object -First 1)
    if ($dialog.Count -eq 0) {
      Start-Sleep -Milliseconds 200
      if ((Get-Date) -gt $deadline) { break }
      continue
    }
    $text = Get-DialogTextByHwnd -Hwnd $dialog[0].hwnd
    $button = Invoke-ChildButtonByTitle -ParentHwnd $dialog[0].hwnd -Titles @($NameOkCn, 'OK', '是(Y)', 'Yes')
    if (-not $button) { throw "KV STUDIO dialog could not be handled: $text" }
    $handled += [pscustomobject]@{ dialog = $dialog[0]; text = $text; button = $button }
    Start-Sleep -Milliseconds 800
  } while ((Get-Date) -lt $deadline)
  $handled
}

function Save-Project {
  $process = Get-KvsProcess
  Set-ForegroundWindowByHwnd -Hwnd $process.MainWindowHandle
  [System.Windows.Forms.SendKeys]::SendWait('^s')
  Start-Sleep -Milliseconds 1000
  (Get-KvsProcess).MainWindowTitle
}

function Get-ProjectTextEvidence {
  param([string]$Path)
  if (-not $Path) { return [pscustomobject]@{ skipped = $true; reason = 'ProjectPath not provided.' } }
  $projectDir = Split-Path -Parent $Path
  if (-not (Test-Path -LiteralPath $projectDir)) { return [pscustomobject]@{ skipped = $true; reason = "Project directory not found: $projectDir" } }
  $hits = @()
  foreach ($file in @(Get-ChildItem -LiteralPath $projectDir -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -in @('WsTreeEnv.xml','UnitSet.ue2','UnitSet.bak') })) {
    $bytes = [IO.File]::ReadAllBytes($file.FullName)
    $ascii = [Text.Encoding]::Default.GetString($bytes)
    $unicode = [Text.Encoding]::Unicode.GetString($bytes)
    $text = $ascii + "`n" + $unicode
    foreach ($pattern in @('KV-B16X','KV-AD40V','DM10300','DM10\d{3}','R\d{5}')) {
      $matches = [regex]::Matches($text, $pattern) | Select-Object -First 20
      foreach ($m in $matches) {
        $start = [Math]::Max(0, $m.Index - 60)
        $len = [Math]::Min(160, $text.Length - $start)
        $hits += [pscustomobject]@{
          file = $file.FullName
          pattern = $pattern
          value = $m.Value
          context = ($text.Substring($start, $len) -replace '[\x00-\x08\x0B\x0C\x0E-\x1F]', '')
        }
      }
    }
  }
  [pscustomobject]@{
    skipped = $false
    project_dir = $projectDir
    hits = $hits
    unit_tree_entries = @(Get-WsTreeUnitEntries -ProjectDir $projectDir)
  }
}

function Get-WsTreeUnitEntries {
  param([string]$ProjectDir)
  $path = Join-Path $ProjectDir 'WsTreeEnv.xml'
  if (-not (Test-Path -LiteralPath $path)) { return @() }
  $content = Get-Content -Raw -Encoding UTF8 -LiteralPath $path
  $entries = @()
  $regex = [regex]'<value\.first>\[(?<slot>\d+)\]\s+(?<unit>\S+)\s+(?<relay>R\d+|-+)\s+(?<dm>DM\d+|-+)</value\.first>'
  foreach ($match in $regex.Matches($content)) {
    $unit = $match.Groups['unit'].Value
    $matchesRequest = $false
    foreach ($pattern in @($UnitNamePatterns)) {
      if ($pattern.Contains('*') -or $pattern.Contains('?')) {
        if ($unit -like $pattern) { $matchesRequest = $true; break }
      } elseif ($unit -eq $pattern) {
        $matchesRequest = $true
        break
      }
    }
    $entries += [pscustomobject]@{
      slot = [int]$match.Groups['slot'].Value
      unit = $unit
      relay_start = $match.Groups['relay'].Value
      dm_start = $match.Groups['dm'].Value
      matches_requested_unit = $matchesRequest
      source = $path
    }
  }
  $entries
}

$stopwatch = [Diagnostics.Stopwatch]::StartNew()
$evidencePath = New-EvidencePath 'configure_kv_expansion_units'
$result = [ordered]@{
  ok = $false
  script = 'configure_kv_expansion_units.ps1'
  project_name = $ProjectName
  project_path = $ProjectPath
  requested_unit_name_patterns = @($UnitNamePatterns)
  max_duration_seconds = $MaxDurationSeconds
  started_at = (Get-Date).ToString('o')
  phases = [ordered]@{}
  evidence_path = $evidencePath
}

try {
  Normalize-UnitNamePatterns
  $result.requested_unit_name_patterns = @($UnitNamePatterns)
  $result.phases.before_windows = @(Get-KvRelevantWindows)
  $result.phases.closed_stale_convert_results = @(Close-StaleConvertResultDialogs)
  Assert-TimeBudget -Stopwatch $stopwatch -Step 'open unit editor'
  $open = Open-UnitEditor
  $result.phases.open_unit_editor = $open
  $editorElement = Get-ElementFromHwnd -Hwnd $open.window.hwnd
  $added = @()
  foreach ($pattern in @($UnitNamePatterns)) {
    $added += Select-And-AddUnit -Pattern $pattern -EditorElement $editorElement -UnitEditorHwnd $open.window.hwnd -Stopwatch $stopwatch
  }
  $result.phases.add_units = $added
  if (-not $KeepWindowOpen) {
    Assert-TimeBudget -Stopwatch $stopwatch -Step 'unit editor OK'
    $result.phases.unit_editor_ok = Invoke-UnitEditorOk -UnitEditorWindow $open.window
    $result.phases.message_dialogs = @(Handle-KvMessageDialogs)
    $result.phases.saved_title = Save-Project
    Start-Sleep -Milliseconds 700
  }
  $result.phases.after_windows = @(Get-KvRelevantWindows)
  $result.phases.project_text_evidence = Get-ProjectTextEvidence -Path $ProjectPath
  $result.elapsed_seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
  if ($result.elapsed_seconds -gt $MaxDurationSeconds) {
    throw "KV_EXPANSION_UNIT_TIMEOUT: elapsed=$($result.elapsed_seconds) MaxDurationSeconds=$MaxDurationSeconds"
  }
  $result.ok = $true
} catch {
  $result.error = $_.Exception.Message
  $result.error_detail = $_.Exception.ToString()
  $result.elapsed_seconds = [math]::Round($stopwatch.Elapsed.TotalSeconds, 3)
  $result.windows_on_error = @(try { Get-KvRelevantWindows } catch { @() })
  Write-JsonFile -Path $evidencePath -Value $result
  Write-Error "configure_kv_expansion_units failed; evidence: $evidencePath; error: $($_.Exception.Message)"
  exit 63
}

$result.finished_at = (Get-Date).ToString('o')
Write-JsonFile -Path $evidencePath -Value $result
Write-Host "OK: configured expansion units '$($UnitNamePatterns -join ',')' elapsed=$($result.elapsed_seconds)s evidence=$evidencePath"
