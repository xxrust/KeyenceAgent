param([string]$OutDir = '')

$ErrorActionPreference = 'Stop'
. (Join-Path $PSScriptRoot 'UiProbe.ps1')
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms

if (-not $OutDir) { $OutDir = Join-Path $env:TEMP ('ui-probe-test-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}

$functions = @('Get-UiWindow', 'Get-UiWindowList', 'Wait-UiWindow', 'Get-UiChildList', 'Get-UiStaticText',
  'Get-UiRect', 'Set-UiForeground', 'Get-UiForeground', 'Find-UiButton', 'Invoke-UiButton',
  'Click-UiPoint', 'Send-UiKeys', 'Save-UiScreenshot', 'Get-UiDialogList')
foreach ($f in $functions) { Add-Case "function $f exists" ([bool](Get-Command $f -ErrorAction SilentlyContinue)) $f }

# Use any process that currently owns a visible top-level window.
$target = @(Get-Process | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1)[0]
Add-Case 'found a visible window owner' ($null -ne $target) $(if ($target) { "$($target.Id) $($target.ProcessName)" } else { '' })

if ($target) {
  $windows = @(Get-UiWindowList -ProcessId $target.Id)
  Add-Case 'window list returned data' ($windows.Count -gt 0) "count=$($windows.Count)"
  $first = $windows[0]
  Add-Case 'window has class and title' ([bool]$first.Class -and [bool]$first.Title) "$($first.Class) | $($first.Title)"

  $rect = Get-UiRect -Hwnd $first.Handle
  Add-Case 'rect is positive' ($rect.Width -gt 0 -and $rect.Height -gt 0) "$($rect.Width)x$($rect.Height)"

  $children = @(Get-UiChildList -Hwnd $first.Handle)
  Add-Case 'child enumeration runs' ($children.Count -ge 0) "children=$($children.Count)"
  $buttons = @($children | Where-Object { $_.Class -like 'Button*' -or $_.Text -match '确定|OK|取消' })
  Add-Case 'child classes are readable' ($children.Count -eq 0 -or (@($children | Where-Object { $_.Class }).Count -gt 0)) "classed=$((@($children | Where-Object { $_.Class })).Count)"

  $statics = Get-UiStaticText -Hwnd $first.Handle
  Add-Case 'static text read does not throw' ($null -ne $statics) "len=$($statics.Length)"

  $fg = Get-UiForeground
  Add-Case 'foreground readable' ([bool]$fg.Handle -ne 0) "fg=$($fg.Handle) $($fg.Class)"

  $shot = Join-Path $OutDir 'probe.png'
  $saved = Save-UiScreenshot -Path $shot
  Add-Case 'screenshot saved' ((Test-Path -LiteralPath $saved) -and ((Get-Item $saved).Length -gt 1000)) $(if (Test-Path $saved) { (Get-Item $saved).Length } else { 'missing' })

  $dialogs = @(Get-UiDialogList -ProcessId $target.Id)
  Add-Case 'dialog scan runs' ($null -ne $dialogs) "dialogs=$($dialogs.Count)"
}

$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{
  test = 'ui-probe-self-test'
  passed = @($cases | Where-Object { $_.ok }).Count
  failed = $failed.Count
  cases = $cases.ToArray()
  out_dir = $OutDir
}
$result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 3
if ($failed.Count -gt 0) { exit 41 }
exit 0

