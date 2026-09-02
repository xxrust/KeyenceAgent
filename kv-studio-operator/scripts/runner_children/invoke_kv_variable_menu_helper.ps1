param(
  [Parameter(Mandatory=$true)][int]$ExpectedProcessId,
  [Parameter(Mandatory=$true)][string]$ExpectedProjectNeedle,
  [Parameter(Mandatory=$true)][string]$ResultPath
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes

function Write-Result([bool]$Ok, [string]$Code, [string]$Message) {
  [ordered]@{ ok=$Ok; error_code=$Code; message=$Message; expected_process_id=$ExpectedProcessId; expected_project_needle=$ExpectedProjectNeedle } |
    ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $ResultPath -Encoding UTF8
}

function Get-PidMenuItems {
  $root = [System.Windows.Automation.AutomationElement]::RootElement
  $condition = New-Object System.Windows.Automation.AndCondition(
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ProcessIdProperty, $ExpectedProcessId)),
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty, [System.Windows.Automation.ControlType]::MenuItem))
  )
  @($root.FindAll([System.Windows.Automation.TreeScope]::Descendants, $condition) | ForEach-Object { $_ })
}

try {
  $process = Get-Process -Id $ExpectedProcessId -ErrorAction Stop
  $process.Refresh()
  if ($process.ProcessName -ne 'Kvs' -or $process.MainWindowHandle -eq 0 -or -not $process.Responding -or $process.MainWindowTitle -notlike "*$ExpectedProjectNeedle*") { throw 'PID-bound Kvs main window validation failed.' }
  $view = @(Get-PidMenuItems | Where-Object { $name=[string]$_.Current.Name; $name -match '^视图' -or $name -match '^View' } | Sort-Object { $_.Current.BoundingRectangle.Left } | Select-Object -First 1)
  if ($view.Count -ne 1) { throw 'View menu item was not found in the bound Kvs UIA tree.' }
  try { $view[0].GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand() }
  catch { $view[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke() }
  Start-Sleep -Milliseconds 250
  $variable = @(Get-PidMenuItems | Where-Object { $name=[string]$_.Current.Name; ($name -match '^变量' -or $name -match '^Variable') -and ($name -match 'L' -or $name -notmatch '[A-Z]') } | Where-Object { -not $_.Current.IsOffscreen } | Select-Object -First 1)
  if ($variable.Count -ne 1) { throw 'Visible Variable menu item was not found after expanding View.' }
  $variable[0].GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
  Write-Result $true '' 'Invoked the PID-bound View -> Variable menu item by UIA.'
  exit 0
} catch {
  Write-Result $false 'KV_VARIABLE_FOREGROUND_REQUIRED' $_.Exception.Message
  exit 1
}
