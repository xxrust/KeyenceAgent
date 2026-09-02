param([Parameter(Mandatory=$true)][long]$MainWindowHandle,[Parameter(Mandatory=$true)][int]$ExpectedProcessId,[Parameter(Mandatory=$true)][string]$ResultPath)
$ErrorActionPreference='Stop'
try {
  Add-Type -AssemblyName UIAutomationClient
  Add-Type -AssemblyName UIAutomationTypes
  $root=[System.Windows.Automation.AutomationElement]::FromHandle([IntPtr]$MainWindowHandle)
  if([int]$root.Current.ProcessId -ne $ExpectedProcessId){ throw 'KV_CREATE_PROJECT_UIA_OWNER_MISMATCH' }
  $c=New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,'新建项目(Ctrl+N)')
  $button=$root.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$c)
  if(-not $button){ throw 'KV_CREATE_PROJECT_UIA_BUTTON_MISSING' }
  $invoke=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
  $invoke.Invoke()
  [ordered]@{ok=$true;error_code='';pid=$ExpectedProcessId;hwnd=$MainWindowHandle;button_name=$button.Current.Name} | ConvertTo-Json | Set-Content -LiteralPath $ResultPath -Encoding UTF8
  exit 0
} catch {
  [ordered]@{ok=$false;error_code='KV_CREATE_PROJECT_UIA_INVOKE_UNAVAILABLE';message=$_.Exception.Message;pid=$ExpectedProcessId;hwnd=$MainWindowHandle} | ConvertTo-Json | Set-Content -LiteralPath $ResultPath -Encoding UTF8
  exit 1
}
