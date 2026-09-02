param([Parameter(Mandatory=$true)][int]$ExpectedProcessId,[Parameter(Mandatory=$true)][string]$ResultPath)
$ErrorActionPreference='Stop'
try {
  Add-Type -AssemblyName UIAutomationClient
  Add-Type -AssemblyName UIAutomationTypes
  $name='读取(R)...'
  $condition=New-Object System.Windows.Automation.AndCondition(
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,$name)),
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::MenuItem)))
  $item=[System.Windows.Automation.AutomationElement]::RootElement.FindFirst([System.Windows.Automation.TreeScope]::Descendants,$condition)
  if(-not $item){ throw 'KV_MNM_READ_MENU_ITEM_MISSING' }
  if([int]$item.Current.ProcessId -ne $ExpectedProcessId){ throw "KV_MNM_READ_MENU_OWNER_MISMATCH actual=$($item.Current.ProcessId) expected=$ExpectedProcessId" }
  $item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
  [ordered]@{ok=$true;error_code='';pid=$ExpectedProcessId;name=$item.Current.Name;process_id=$item.Current.ProcessId}|ConvertTo-Json|Set-Content -LiteralPath $ResultPath -Encoding UTF8
  exit 0
} catch {
  [ordered]@{ok=$false;error_code='KV_MNM_READ_MENU_INVOKE_UNAVAILABLE';message=$_.Exception.Message;pid=$ExpectedProcessId}|ConvertTo-Json|Set-Content -LiteralPath $ResultPath -Encoding UTF8
  exit 1
}
