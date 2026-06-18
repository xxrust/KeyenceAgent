param(
  [string]$MnmPath = '',
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,
  [string]$OutDir = (Join-Path ([IO.Path]::GetTempPath()) 'keyence-plc-programmer\mnm_import_validation'),
  [string]$KvsExe = 'C:\Program Files (x86)\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe',
  [string]$ExpectedModuleName = '',
  [switch]$SaveAfterImport,
  [string]$ProjectSearchRoot = '',
  [object]$FailOnMissingProjectPlainText = $false,
  [object]$FailOnMissingValidationNeedles = $false,
  [switch]$DeleteExistingModuleBeforeImport,
  [object]$RestartKvs = $true
)

$ErrorActionPreference='Continue'
$out=$OutDir
$project=$ProjectPath
$kvs=$KvsExe
New-Item -ItemType Directory -Force -Path $out | Out-Null
Set-Content -LiteralPath (Join-Path $out 'bootstrap.log') -Value ((Get-Date -Format s) + ' bootstrap start') -Encoding UTF8
function Log($m){Add-Content -LiteralPath (Join-Path $out 'run.log') -Value ((Get-Date -Format s)+' '+$m) -Encoding UTF8}

function ConvertTo-BoolValue([object]$Value, [bool]$Default) {
  if ($null -eq $Value) { return $Default }
  if ($Value -is [bool]) { return [bool]$Value }
  if ($Value -is [byte] -or $Value -is [int16] -or $Value -is [int32] -or $Value -is [int64]) {
    return ([int64]$Value) -ne 0
  }

  $text = ([string]$Value).Trim()
  if ($text.Length -eq 0) { return $Default }
  switch -Regex ($text) {
    '^(?i:\$?true|1|yes|y|on)$' { return $true }
    '^(?i:\$?false|0|no|n|off)$' { return $false }
    default { throw "Invalid boolean value: $Value" }
  }
}
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type @"
using System;using System.Runtime.InteropServices;
public class W{
[DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr hWnd);
[DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr hWnd,int nCmdShow);
[DllImport("user32.dll")] public static extern bool SetCursorPos(int X,int Y);
[DllImport("user32.dll")] public static extern void mouse_event(int dwFlags,int dx,int dy,int dwData,int dwExtraInfo);
[DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr hWnd);
[DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetClassName(IntPtr hWnd, System.Text.StringBuilder lpClassName, int nMaxCount);
[DllImport("user32.dll", CharSet=CharSet.Auto)] public static extern int GetWindowText(IntPtr hWnd, System.Text.StringBuilder lpString, int nMaxCount);
[DllImport("user32.dll")] public static extern bool EnumWindows(EnumWindowsProc lpEnumFunc, IntPtr lParam);
public delegate bool EnumWindowsProc(IntPtr hWnd, IntPtr lParam);
}
"@
function Shot($n){try{$b=[Windows.Forms.Screen]::PrimaryScreen.Bounds;$bmp=New-Object Drawing.Bitmap $b.Width,$b.Height;$g=[Drawing.Graphics]::FromImage($bmp);$g.CopyFromScreen(0,0,0,0,$bmp.Size);$bmp.Save((Join-Path $out $n));$g.Dispose();$bmp.Dispose();Log "shot $n"}catch{Log ('shot err '+$_.Exception.Message)}}
function ClickPoint([int]$x, [int]$y, [string]$label){
  [W]::SetCursorPos($x,$y) | Out-Null
  Start-Sleep -Milliseconds 150
  [W]::mouse_event(0x0002,0,0,0,0)
  Start-Sleep -Milliseconds 80
  [W]::mouse_event(0x0004,0,0,0,0)
  Log ('clicked '+$label+' '+$x+','+$y)
}
function ClickAutomationElementCenter($element, [string]$label){
  $rect=$element.Current.BoundingRectangle
  $cx=[int]($rect.Left + ($rect.Width / 2))
  $cy=[int]($rect.Top + ($rect.Height / 2))
  ClickPoint $cx $cy $label
}
function DoubleClickAutomationElementCenter($element, [string]$label){
  $rect=$element.Current.BoundingRectangle
  $cx=[int]($rect.Left + ($rect.Width / 2))
  $cy=[int]($rect.Top + ($rect.Height / 2))
  [W]::SetCursorPos($cx,$cy) | Out-Null
  Start-Sleep -Milliseconds 120
  for($i=0;$i -lt 2;$i++){
    [W]::mouse_event(0x0002,0,0,0,0)
    Start-Sleep -Milliseconds 60
    [W]::mouse_event(0x0004,0,0,0,0)
    Start-Sleep -Milliseconds 90
  }
  Log ('double-clicked '+$label+' '+$cx+','+$cy)
}
function ClickRectCenter($rect, [string]$label){
  $cx=[int]($rect.Left + ($rect.Width / 2))
  $cy=[int]($rect.Top + ($rect.Height / 2))
  ClickPoint $cx $cy $label
}
function GetWindowClassName([IntPtr]$hwnd){
  $builder=New-Object System.Text.StringBuilder 256
  [void][W]::GetClassName($hwnd,$builder,$builder.Capacity)
  return $builder.ToString()
}
function GetWindowTextValue([IntPtr]$hwnd){
  $builder=New-Object System.Text.StringBuilder 512
  [void][W]::GetWindowText($hwnd,$builder,$builder.Capacity)
  return $builder.ToString()
}
function GetVisibleDialogWindows(){
  $script:visibleDialogWindows=@()
  $callback=[W+EnumWindowsProc]{
    param([IntPtr]$hwnd,[IntPtr]$lparam)
    try{
      if([W]::IsWindowVisible($hwnd)){
        $className=GetWindowClassName $hwnd
        if($className -eq '#32770'){
          $script:visibleDialogWindows += [pscustomobject]@{
            Hwnd=$hwnd
            Title=(GetWindowTextValue $hwnd)
            Class=$className
          }
        }
      }
    }catch{}
    return $true
  }
  [void][W]::EnumWindows($callback,[IntPtr]::Zero)
  return @($script:visibleDialogWindows)
}
function WaitForVisibleDialogHwnd([int]$seconds, [bool]$logMiss=$true){
  $deadline=(Get-Date).AddSeconds($seconds)
  do{
    $dialogs=@(GetVisibleDialogWindows)
    if($dialogs.Count -gt 0){
      $dialog=$dialogs[0]
      Log ('visible #32770 dialog hwnd='+$dialog.Hwnd+' title='+$dialog.Title)
      return $dialog.Hwnd
    }
    Start-Sleep -Milliseconds 300
  }while((Get-Date) -lt $deadline)
  if($logMiss){ Log ('visible #32770 dialog not found within '+$seconds+'s') }
  return [IntPtr]::Zero
}
function DumpUi($name){
  try{
    $root=[System.Windows.Automation.AutomationElement]::RootElement
    $all=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
    $rows=@()
    for($i=0;$i -lt $all.Count;$i++){
      $e=$all.Item($i)
      $r=$e.Current.BoundingRectangle
      $rows += [pscustomobject]@{
        Index=$i
        Name=$e.Current.Name
        Class=$e.Current.ClassName
        Type=$e.Current.ControlType.ProgrammaticName
        AutomationId=$e.Current.AutomationId
        IsEnabled=$e.Current.IsEnabled
        Rect=('{0},{1},{2},{3}' -f $r.Left,$r.Top,$r.Width,$r.Height)
      }
    }
    $rows | Where-Object { $_.Name -or $_.Class -or $_.AutomationId } |
      Select-Object -First 900 |
      ConvertTo-Json -Depth 4 |
      Set-Content -LiteralPath (Join-Path $out $name) -Encoding UTF8
    Log "dump $name"
  }catch{
    Log ('dump err '+$name+' '+$_.Exception.Message)
  }
}
function FindKvsMainWindowElement(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $windows=$root.FindAll(
    [System.Windows.Automation.TreeScope]::Children,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window))
  )
  for($i=0;$i -lt $windows.Count;$i++){
    $window=$windows.Item($i)
    $name=$window.Current.Name
    $class=$window.Current.ClassName
    $rect=$window.Current.BoundingRectangle
    if($name -like 'KV STUDIO*' -and $class -like 'WindowsForms10.Window*' -and $rect.Width -gt 400 -and $rect.Height -gt 300){
      return $window
    }
  }
  return $null
}
function WaitKvsMainWindowReady([int]$seconds){
  $deadline=(Get-Date).AddSeconds($seconds)
  do{
    $window=FindKvsMainWindowElement
    if($window){
      $hwnd=$window.Current.NativeWindowHandle
      if($hwnd -ne 0){
        [W]::ShowWindow([IntPtr]$hwnd,3)|Out-Null
        Start-Sleep -Milliseconds 250
        [W]::SetForegroundWindow([IntPtr]$hwnd)|Out-Null
        Log ('KV STUDIO main window ready: '+$window.Current.Name)
        return $true
      }
    }
    Start-Sleep -Seconds 2
  }while((Get-Date) -lt $deadline)
  Log 'KV STUDIO main window was not ready before timeout'
  return $false
}
function OpenProjectModuleEditor([string]$moduleName){
  if(-not $moduleName){ return $false }
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $tree=$root.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'ProjectTreeView'))
  )
  if(-not $tree){
    Log 'project tree not found before MNM import'
    return $false
  }
  $items=$tree.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::TreeItem))
  )
  for($i=0;$i -lt $items.Count;$i++){
    $item=$items.Item($i)
    $name=[string]$item.Current.Name
    if($name -eq $moduleName -or $name -like ($moduleName+' *') -or $name -like ('*'+$moduleName+'*')){
      try{
        $select=$item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
        $select.Select()
        Log ('selected project module '+$name)
      }catch{
        ClickAutomationElementCenter $item ('project module '+$name)
      }
      Start-Sleep -Milliseconds 250
      try{
        $invoke=$item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $invoke.Invoke()
        Log ('invoked project module '+$name)
      }catch{
        DoubleClickAutomationElementCenter $item ('project module '+$name)
      }
      try{
        [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
        Log ('sent Enter to open project module '+$name)
      }catch{
        Log ('Enter open project module failed '+$name+': '+$_.Exception.Message)
      }
      Start-Sleep -Seconds 2
      return $true
    }
  }
  Log ('project module not found before MNM import: '+$moduleName)
  return $false
}
function FindProjectModuleTreeItem([string]$moduleName){
  if(-not $moduleName){ return $null }
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $tree=$root.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'ProjectTreeView'))
  )
  if(-not $tree){ return $null }
  $items=$tree.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::TreeItem))
  )
  for($i=0;$i -lt $items.Count;$i++){
    $item=$items.Item($i)
    $name=[string]$item.Current.Name
    if($name -eq $moduleName -or $name -like ($moduleName+' *') -or $name -like ('*'+$moduleName+'*')){
      return $item
    }
  }
  return $null
}
function ConfirmDeleteDialogIfPresent(){
  Start-Sleep -Milliseconds 700
  foreach($dialog in @(GetVisibleDialogs)){
    try{
      $buttons=$dialog.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
      )
      for($i=0;$i -lt $buttons.Count;$i++){
        $button=$buttons.Item($i)
        $name=[string]$button.Current.Name
        if($name -match '^(是|はい|Yes|OK|确定)'){
          try{
            $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
          }catch{
            ClickAutomationElementCenter $button ('delete confirm '+$name)
          }
          Log ('confirmed delete dialog by '+$name)
          Start-Sleep -Seconds 2
          return $true
        }
      }
    }catch{}
  }
  return $false
}
function RemoveProjectModuleIfPresent([string]$moduleName){
  $item=FindProjectModuleTreeItem $moduleName
  if(-not $item){
    Log ('delete-before-import skipped; module not present: '+$moduleName)
    return $true
  }
  try{
    $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
  }catch{
    ClickAutomationElementCenter $item ('select module for delete '+$moduleName)
  }
  Start-Sleep -Milliseconds 500
  [System.Windows.Forms.SendKeys]::SendWait('{DELETE}')
  Log ('sent Delete for existing module '+$moduleName)
  if(-not (ConfirmDeleteDialogIfPresent)){
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Log 'sent Enter for delete confirmation fallback'
    Start-Sleep -Seconds 2
  }
  $remaining=FindProjectModuleTreeItem $moduleName
  if($remaining){
    Log ('module still visible after delete attempt: '+$moduleName)
    return $false
  }
  Log ('deleted existing module before MNM import: '+$moduleName)
  return $true
}
function RenameProjectModuleIfPresent([string]$moduleName){
  $item=FindProjectModuleTreeItem $moduleName
  if(-not $item){
    Log ('rename-before-import skipped; module not present: '+$moduleName)
    return $true
  }
  $newName=('CodexOld_' + (Get-Date -Format 'HHmmss'))
  try{
    $item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern).Select()
  }catch{
    ClickAutomationElementCenter $item ('select module for rename '+$moduleName)
  }
  Start-Sleep -Milliseconds 500
  [System.Windows.Forms.SendKeys]::SendWait('{F2}')
  Start-Sleep -Milliseconds 500
  [System.Windows.Forms.Clipboard]::SetText($newName)
  [System.Windows.Forms.SendKeys]::SendWait('^a')
  Start-Sleep -Milliseconds 100
  [System.Windows.Forms.SendKeys]::SendWait('^v')
  Start-Sleep -Milliseconds 100
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Log ('attempted rename existing module '+$moduleName+' to '+$newName)
  Start-Sleep -Seconds 3
  if(FindProjectModuleTreeItem $moduleName){
    Log ('module still visible after rename attempt: '+$moduleName)
    return $false
  }
  Log ('renamed existing module before MNM import: '+$moduleName+' -> '+$newName)
  return $true
}
function InvokeProgramNewMenu(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $all=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  $programMenu=$null
  for($i=0;$i -lt $all.Count;$i++){
    $element=$all.Item($i)
    if($element.Current.ControlType.ProgrammaticName -eq 'ControlType.MenuItem' -and $element.Current.Name -eq '程序(M)'){
      $programMenu=$element
      break
    }
  }
  if($programMenu){
    try{
      $programMenu.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern).Expand()
      Log 'expanded program menu by UIA'
    }catch{
      try{
        $programMenu.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
        Log 'invoked program menu by UIA'
      }catch{
        [System.Windows.Forms.SendKeys]::SendWait('%m')
        Log 'opened program menu by Alt+M fallback'
      }
    }
  }else{
    [System.Windows.Forms.SendKeys]::SendWait('%m')
    Log 'opened program menu by Alt+M fallback; UIA menu not found'
  }
  Start-Sleep -Milliseconds 700
  $all=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  for($i=0;$i -lt $all.Count;$i++){
    $element=$all.Item($i)
    $rect=$element.Current.BoundingRectangle
    if($element.Current.ControlType.ProgrammaticName -eq 'ControlType.MenuItem' -and
       $element.Current.Name -like '新建*' -and
       $rect.Left -ge 200 -and $rect.Left -le 700 -and $rect.Top -ge 50 -and $rect.Top -le 200){
      try{
        $element.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
      }catch{
        ClickAutomationElementCenter $element 'program new menu'
      }
      Log 'invoked program new menu'
      Start-Sleep -Seconds 1
      return $true
    }
  }
  return $false
}
function CreatePlaceholderModule(){
  $name=('CodexKeep_' + (Get-Date -Format 'HHmmss'))
  if(-not (InvokeProgramNewMenu)){
    Log 'failed to invoke program new menu'
    return $false
  }
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $deadline=(Get-Date).AddSeconds(10)
  do{
    $windows=$root.FindAll(
      [System.Windows.Automation.TreeScope]::Children,
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window))
    )
    for($w=0;$w -lt $windows.Count;$w++){
      $window=$windows.Item($w)
      if($window.Current.Name -notlike '*新建程序*'){ continue }
      $edits=$window.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Edit))
      )
      if($edits.Count -gt 0){
        try{
          $edits.Item(0).GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern).SetValue($name)
        }catch{
          ClickAutomationElementCenter $edits.Item(0) 'new program name edit'
          [System.Windows.Forms.Clipboard]::SetText($name)
          [System.Windows.Forms.SendKeys]::SendWait('^a')
          [System.Windows.Forms.SendKeys]::SendWait('^v')
        }
      }
      $buttons=$window.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
      )
      for($i=0;$i -lt $buttons.Count;$i++){
        $button=$buttons.Item($i)
        if($button.Current.Name -eq 'OK'){
          try{
            $button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern).Invoke()
          }catch{
            ClickAutomationElementCenter $button 'new program OK'
          }
          Log ('created placeholder module '+$name)
          Start-Sleep -Seconds 3
          return ($null -ne (FindProjectModuleTreeItem $name))
        }
      }
    }
    Start-Sleep -Milliseconds 300
  }while((Get-Date) -lt $deadline)
  Log 'new program dialog not completed'
  return $false
}
function FindMnemonicReadChoiceButton([bool]$PreferOverwrite){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $buttons=$root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
  )
  $overwritePrefix=(-join ([char[]](0x8986,0x76D6)))
  $insertPrefix=(-join ([char[]](0x63D2,0x5165)))
  $targetPrefixes = if($PreferOverwrite){ @($overwritePrefix,$insertPrefix) } else { @($insertPrefix,$overwritePrefix) }
  foreach($targetPrefix in $targetPrefixes){
    for($i=0;$i -lt $buttons.Count;$i++){
      $button=$buttons.Item($i)
      $name=[string]$button.Current.Name
      $automationId=[string]$button.Current.AutomationId
      $rect=GetElementRectObject $button
      if(-not $button.Current.IsEnabled){ continue }
      if($name -notlike ($targetPrefix+'*')){ continue }
      if($automationId -like '_button*'){ continue }
      if($rect.Width -lt 40 -or $rect.Height -lt 18){ continue }
      if($rect.Left -lt 250 -or $rect.Left -gt 2200){ continue }
      if($rect.Top -lt 150 -or $rect.Top -gt 1200){ continue }
      Log ('found mnemonic read choice button name='+$name+' automationId='+$automationId+' rect='+$rect.Left+','+$rect.Top+','+$rect.Width+','+$rect.Height)
      return $button
    }
  }
  return $null
}
function ClickKvsInsertButton([bool]$PreferOverwrite){
  $button=FindMnemonicReadChoiceButton -PreferOverwrite $PreferOverwrite
  if(-not $button){
    Log 'MNM read choice button not found after MNM file open'
    return $false
  }
  try{
    $invoke=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $invoke.Invoke()
    Log ('invoked MNM read choice button '+$button.Current.Name)
  }catch{
    ClickAutomationElementCenter $button ('MNM read choice button '+$button.Current.Name)
  }
  Start-Sleep -Seconds 2
  return $true
}
function TestKvsMnemonicImportPanelOpen(){
  return ($null -ne (FindMnemonicReadChoiceButton -PreferOverwrite $true))
}
function CompleteMnemonicReadInsertFlow([bool]$PreferOverwrite){
  if(-not (TestKvsMnemonicImportPanelOpen)){
    Log 'MNM read choice panel not present after file open; import cannot be considered committed'
    return $false
  }
  if(-not (ClickKvsInsertButton -PreferOverwrite $PreferOverwrite)){
    return $false
  }
  Start-Sleep -Seconds 3
  if(-not (TestKvsMnemonicImportPanelOpen)){
      Log 'MNM read choice panel closed after commit'
    return $true
  }
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $buttons=$root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
  )
  $okCn=(-join ([char[]](0x786E,0x5B9A)))
  $yesCn=(-join ([char[]](0x662F)))
  $yesJp=(-join ([char[]](0x306F,0x3044)))
  $names=@('OK',$okCn,$yesCn,$yesJp)
  for($i=0;$i -lt $buttons.Count;$i++){
    $button=$buttons.Item($i)
    $name=[string]$button.Current.Name
    if(-not $button.Current.IsEnabled){ continue }
    if($names -notcontains $name){ continue }
    try{
      $invoke=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
      $invoke.Invoke()
      Log ('invoked post-insert confirmation button '+$name)
    }catch{
      ClickAutomationElementCenter $button ('post-insert confirmation button '+$name)
    }
    Start-Sleep -Seconds 3
    if(-not (TestKvsMnemonicImportPanelOpen)){
      Log 'MNM read choice panel closed after confirmation'
      return $true
    }
  }
  Log 'MNM read choice panel still open after commit; import not committed'
  return $false
}
function GetElementPatternNames($element){
  $names=@()
  try{
    foreach($pattern in $element.GetSupportedPatterns()){
      $names += $pattern.ProgrammaticName
    }
  }catch{}
  return $names
}
function GetElementRectObject($element){
  $rect=$element.Current.BoundingRectangle
  return [pscustomobject]@{
    Left=[double]$rect.Left
    Top=[double]$rect.Top
    Width=[double]$rect.Width
    Height=[double]$rect.Height
    Right=[double]($rect.Left + $rect.Width)
    Bottom=[double]($rect.Top + $rect.Height)
  }
}
function GetVisibleMenuItems(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $items=$root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::MenuItem))
  )
  $visible=@()
  for($i=0;$i -lt $items.Count;$i++){
    $item=$items.Item($i)
    $rect=GetElementRectObject $item
    if($item.Current.IsEnabled -and $rect.Width -gt 10 -and $rect.Height -gt 8){
      $visible += $item
    }
  }
  return $visible
}
function TestHasPatternName($element, [string]$patternText){
  foreach($name in (GetElementPatternNames $element)){
    if($name -like ('*'+$patternText+'*')){ return $true }
  }
  return $false
}
function OpenFileMenuByUia(){
  [System.Windows.Forms.SendKeys]::SendWait('{ESC}')
  Start-Sleep -Milliseconds 200
  $items=@(GetVisibleMenuItems)
  $topMenuItems=@()
  foreach($item in $items){
    $rect=GetElementRectObject $item
    if($rect.Top -ge 20 -and $rect.Top -le 90 -and $rect.Width -gt 30 -and $rect.Height -gt 15){
      $topMenuItems += [pscustomobject]@{ Item=$item; Left=$rect.Left; Top=$rect.Top; Name=$item.Current.Name }
    }
  }
  if($topMenuItems.Count -eq 0){
    Log 'top menu items not found for file menu'
    return $false
  }
  $fileItem=($topMenuItems | Sort-Object Left,Top | Select-Object -First 1).Item
  Log ('opening file menu by UIA name='+$fileItem.Current.Name)
  ExpandOrClickMenuItem $fileItem 'file menu' | Out-Null
  Start-Sleep -Milliseconds 600
  return $true
}
function FindMnemonicListMenuItem(){
  $items=@(GetVisibleMenuItems)
  $popupItems=@()
  foreach($item in $items){
    $rect=GetElementRectObject $item
    if($rect.Top -gt 40 -and $rect.Width -gt 80){
      $popupItems += $item
    }
  }
  if($popupItems.Count -eq 0){ return $null }
  $leftEdge=($popupItems | ForEach-Object { (GetElementRectObject $_).Left } | Measure-Object -Minimum).Minimum
  $parentCandidates=@()
  foreach($item in $popupItems){
    $rect=GetElementRectObject $item
    $access=([string]$item.Current.AccessKey).Trim()
    if([Math]::Abs($rect.Left - $leftEdge) -le 8 -and $access -match '^(?i)r$'){
      $parentCandidates += $item
    }
  }
  foreach($item in $parentCandidates){
    if(TestHasPatternName $item 'ExpandCollapse'){ return $item }
  }
  if($parentCandidates.Count -gt 0){ return $parentCandidates[0] }
  return $null
}
function FindMnemonicReadMenuItem($parent){
  if(-not $parent){ return $null }
  $parentRect=GetElementRectObject $parent
  $items=@(GetVisibleMenuItems)
  $childCandidates=@()
  foreach($item in $items){
    $rect=GetElementRectObject $item
    $access=([string]$item.Current.AccessKey).Trim()
    if($access -notmatch '^(?i)r$'){ continue }
    if($rect.Left -le ($parentRect.Right - 12)){ continue }
    if($rect.Top -lt ($parentRect.Top - 8)){ continue }
    if($rect.Top -gt ($parentRect.Bottom + 80)){ continue }
    if($item.Current.Name -eq $parent.Current.Name -and [Math]::Abs($rect.Left - $parentRect.Left) -lt 8){ continue }
    $childCandidates += $item
  }
  foreach($item in $childCandidates){
    if(-not (TestHasPatternName $item 'ExpandCollapse')){ return $item }
  }
  if($childCandidates.Count -gt 0){ return $childCandidates[0] }
  return $null
}
function ExpandOrClickMenuItem($item, [string]$label){
  if(-not $item){ return $false }
  $rect=GetElementRectObject $item
  Log ('menu target '+$label+' name='+$item.Current.Name+' access='+$item.Current.AccessKey+' rect='+$rect.Left+','+$rect.Top+','+$rect.Width+','+$rect.Height+' patterns='+((GetElementPatternNames $item) -join ','))
  try{
    $expandPattern=$item.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
    $expandPattern.Expand()
    Log ('expanded '+$label+' by ExpandCollapsePattern')
    return $true
  }catch{
    Log ('ExpandCollapse unavailable for '+$label+': '+$_.Exception.Message)
  }
  try{
    $invokePattern=$item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $invokePattern.Invoke()
    Log ('invoked '+$label+' by InvokePattern')
    return $true
  }catch{
    Log ('Invoke unavailable for '+$label+': '+$_.Exception.Message)
  }
  ClickAutomationElementCenter $item $label
  return $true
}
function InvokeOrClickMenuItem($item, [string]$label){
  if(-not $item){ return $false }
  $rect=GetElementRectObject $item
  Log ('menu target '+$label+' name='+$item.Current.Name+' access='+$item.Current.AccessKey+' rect='+$rect.Left+','+$rect.Top+','+$rect.Width+','+$rect.Height+' patterns='+((GetElementPatternNames $item) -join ','))
  if($item.Current.ControlType -eq [System.Windows.Automation.ControlType]::MenuItem){
    ClickRectCenter $rect $label
    return $true
  }
  try{
    $invokePattern=$item.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
    $invokePattern.Invoke()
    Log ('invoked '+$label+' by InvokePattern')
    return $true
  }catch{
    Log ('Invoke unavailable for '+$label+': '+$_.Exception.Message)
  }
  ClickAutomationElementCenter $item $label
  return $true
}
function InvokeMnemonicImportMenu(){
  if(-not (OpenFileMenuByUia)){
    throw 'failed to open file menu by UIA; refusing key fallback that can type into editor'
  }
  Shot '01a_file_menu.png'
  DumpUi '01a_file_menu.json'
  $parent=FindMnemonicListMenuItem
  if(-not $parent){
    throw 'mnemonic-list parent menu not found by UIA; refusing unsafe key fallback'
  }
  $read=FindMnemonicReadMenuItem $parent
  if(-not $read){
    ExpandOrClickMenuItem $parent 'mnemonic-list parent'
    Start-Sleep -Milliseconds 700
    Shot '01b_mnemonic_submenu.png'
    DumpUi '01b_mnemonic_submenu.json'
    $read=FindMnemonicReadMenuItem $parent
  }else{
    Shot '01b_mnemonic_submenu.png'
    DumpUi '01b_mnemonic_submenu.json'
  }
  if(-not $read){
    throw 'mnemonic-list read child menu not found by UIA'
  }
  [System.Windows.Forms.SendKeys]::SendWait('r')
  Log 'sent mnemonic-list read access key after submenu open'
  Start-Sleep -Seconds 2
  if(-not (TestStandardOpenDialogPresent)){
    Log 'read access key did not expose a standard open dialog; clicking read menu item'
    InvokeOrClickMenuItem $read 'mnemonic-list read'
    Start-Sleep -Seconds 2
  }
  Log 'invoked mnemonic list read/import through UIA menu path'
}
function TestStandardOpenDialogPresent(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $windows=$root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty,'#32770'))
  )
  for($i=0;$i -lt $windows.Count;$i++){
    $dialog=$windows.Item($i)
    $openButton=$dialog.FindFirst(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.AndCondition(
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1')),
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
      ))
    )
    $fileNameEdit=$dialog.FindFirst(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1148'))
    )
    if($openButton -and $fileNameEdit){ return $true }
  }
  return $false
}
function NewInlineMnemonicBodyFile([string]$path){
  if(-not $path -or -not (Test-Path -LiteralPath $path)){ return $path }
  $inlineDir=Join-Path $out '_inline_body'
  New-Item -ItemType Directory -Force -Path $inlineDir | Out-Null
  $target=Join-Path $inlineDir ([IO.Path]::GetFileName($path))
  $bodyLines=New-Object System.Collections.Generic.List[string]
  foreach($rawLine in (Get-Content -LiteralPath $path -ErrorAction Stop)){
    $line=[string]$rawLine
    $trim=$line.Trim()
    if($trim -match '^(?i)DEVICE\s*:'){ continue }
    if($trim -match '^(?i);MODULE(_TYPE)?\s*:'){ continue }
    if($trim -match '^\s*;'){ continue }
    if($trim -match '^(?i)ENDH?$'){ continue }
    $bodyLines.Add($line)
  }
  [IO.File]::WriteAllLines($target, [string[]]$bodyLines, [Text.Encoding]::Default)
  Log ('created inline mnemonic body file: '+$target)
  return $target
}
function SetInlineMnemonicReadFile([string]$path){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $deadline=(Get-Date).AddSeconds(8)
  do{
    try{
      $edits=$root.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1265'))
      )
      for($i=0;$i -lt $edits.Count;$i++){
        $edit=$edits.Item($i)
        $rect=GetElementRectObject $edit
        if(-not $edit.Current.IsEnabled){ continue }
        if($rect.Left -lt 250 -or $rect.Left -gt 1200){ continue }
        if($rect.Top -lt 150 -or $rect.Top -gt 1200){ continue }
        $inlinePath=NewInlineMnemonicBodyFile $path
        try{
          $valuePattern=$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
          $valuePattern.SetValue($inlinePath)
          Log ('set inline mnemonic-read path by ValuePattern: '+$inlinePath)
          Start-Sleep -Milliseconds 500
          return $true
        }catch{
          ClickAutomationElementCenter $edit 'inline mnemonic-read path edit'
          Start-Sleep -Milliseconds 200
          [System.Windows.Forms.Clipboard]::SetText($inlinePath)
          [System.Windows.Forms.SendKeys]::SendWait('^a')
          Start-Sleep -Milliseconds 100
          [System.Windows.Forms.SendKeys]::SendWait('^v')
          Log ('set inline mnemonic-read path by clipboard: '+$_.Exception.Message)
          Start-Sleep -Milliseconds 500
          return $true
        }
      }
    }catch{
      Log ('inline mnemonic-read path scan failed: '+$_.Exception.Message)
    }
    Start-Sleep -Milliseconds 300
  }while((Get-Date) -lt $deadline)
  return $false
}
function SetOpenDialogFile([string]$path){
  if(SetInlineMnemonicReadFile $path){
    return $true
  }
  if(SetOpenDialogFileByUia $path){
    return $true
  }
  $dialogHwnd=WaitForVisibleDialogHwnd 3 $true
  if($dialogHwnd -ne [IntPtr]::Zero){
    try{
      [W]::ShowWindow($dialogHwnd,3) | Out-Null
      Start-Sleep -Milliseconds 200
      [W]::SetForegroundWindow($dialogHwnd) | Out-Null
      Start-Sleep -Milliseconds 300
      [System.Windows.Forms.Clipboard]::SetText($path)
      Start-Sleep -Milliseconds 250
      [System.Windows.Forms.SendKeys]::SendWait('%n')
      Start-Sleep -Milliseconds 200
      [System.Windows.Forms.SendKeys]::SendWait('^a')
      Start-Sleep -Milliseconds 100
      [System.Windows.Forms.SendKeys]::SendWait('^v')
      Start-Sleep -Milliseconds 250
      [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
      Log 'set open dialog filename by Win32 dialog foreground + Alt+N clipboard path'
      return $true
    }catch{
      Log ('Win32 open dialog filename path failed: '+$_.Exception.Message)
    }
  }

  try{
    [System.Windows.Forms.Clipboard]::SetText($path)
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait('%n')
    Start-Sleep -Milliseconds 200
    [System.Windows.Forms.SendKeys]::SendWait('^a')
    Start-Sleep -Milliseconds 100
    [System.Windows.Forms.SendKeys]::SendWait('^v')
    Start-Sleep -Milliseconds 250
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Log 'set open dialog filename by keyboard Alt+N clipboard path'
    return $true
  }catch{
    Log ('keyboard open dialog filename path failed: '+$_.Exception.Message)
  }

  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $dialogs=$null
  $deadline=(Get-Date).AddSeconds(20)
  do{
    try{
      $windows=$root.FindAll(
        [System.Windows.Automation.TreeScope]::Children,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window))
      )
      $dialogList=@()
      for($w=0;$w -lt $windows.Count;$w++){
        $window=$windows.Item($w)
        if($window.Current.ClassName -eq '#32770'){
          $dialogList += $window
        }
      }
      if($dialogList.Count -gt 0){
        $dialogs=$dialogList
        break
      }
    }catch{
      Log ('open dialog child-window scan failed: '+$_.Exception.Message)
    }
    Start-Sleep -Milliseconds 500
  }while((Get-Date) -lt $deadline)
  if(-not $dialogs){
    Log 'open dialog not found by UIA child-window scan'
    return $false
  }
  for($i=0;$i -lt $dialogs.Count;$i++){
    $dialog=$dialogs.Item($i)
    try{
      $openButton=$dialog.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.AndCondition(
          (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1')),
          (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
        ))
      )
      $edits=$dialog.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Edit))
      )
    }catch{
      Log ('open dialog descendant scan failed: '+$_.Exception.Message)
      continue
    }
    if($edits.Count -eq 0){ continue }
    $edit=$edits.Item($edits.Count - 1)
    $setByValuePattern=$false
    try{
      $valuePattern=$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
      $valuePattern.SetValue($path)
      $setByValuePattern=$true
      Log 'set open dialog filename by ValuePattern'
    }catch{
      ClickAutomationElementCenter $edit 'open dialog filename edit'
      Start-Sleep -Milliseconds 200
      [System.Windows.Forms.Clipboard]::SetText($path)
      [System.Windows.Forms.SendKeys]::SendWait('^a')
      Start-Sleep -Milliseconds 100
      [System.Windows.Forms.SendKeys]::SendWait('^v')
      Log ('set open dialog filename by clipboard fallback: '+$_.Exception.Message)
    }
    Start-Sleep -Milliseconds 300
    if($openButton){
      try{
        $invokePattern=$openButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $invokePattern.Invoke()
        Log 'invoked open dialog Open button by InvokePattern'
      }catch{
        ClickAutomationElementCenter $openButton 'open dialog Open button'
      }
    }else{
      [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
      Log 'sent Enter in open dialog'
    }
    return $true
  }
  Log 'open dialog found but filename edit was not accessible by UIA'
  return $false
}
function SetOpenDialogFileByUia([string]$path){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $deadline=(Get-Date).AddSeconds(20)
  do{
    try{
      $windows=$root.FindAll(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window))
      )
      for($w=0;$w -lt $windows.Count;$w++){
        $dialog=$windows.Item($w)
        if($dialog.Current.ClassName -ne '#32770'){ continue }
        $dialogName=[string]$dialog.Current.Name
        $openButton=$dialog.FindFirst(
          [System.Windows.Automation.TreeScope]::Descendants,
          (New-Object System.Windows.Automation.AndCondition(
            (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1')),
            (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
          ))
        )
        $edits=$dialog.FindAll(
          [System.Windows.Automation.TreeScope]::Descendants,
          (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Edit))
        )
        if($edits.Count -eq 0 -or -not $openButton){ continue }
        if($dialogName -ne '打开' -and $dialogName -ne 'Open' -and $edits.Count -lt 2){ continue }
        $edit=$null
        for($i=0;$i -lt $edits.Count;$i++){
          $candidate=$edits.Item($i)
          if($candidate.Current.AutomationId -eq '1148'){
            $edit=$candidate
            break
          }
        }
        if(-not $edit){ $edit=$edits.Item($edits.Count - 1) }
        try{
          $valuePattern=$edit.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
          $valuePattern.SetValue($path)
          Log 'set open dialog filename by UIA ValuePattern'
        }catch{
          ClickAutomationElementCenter $edit 'open dialog filename edit'
          Start-Sleep -Milliseconds 200
          [System.Windows.Forms.Clipboard]::SetText($path)
          [System.Windows.Forms.SendKeys]::SendWait('^a')
          Start-Sleep -Milliseconds 100
          [System.Windows.Forms.SendKeys]::SendWait('^v')
          Log ('set open dialog filename by focused edit clipboard: '+$_.Exception.Message)
        }
        Start-Sleep -Milliseconds 300
        try{
          $invokePattern=$openButton.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
          $invokePattern.Invoke()
          Log 'invoked open dialog Open button by UIA InvokePattern'
        }catch{
          ClickAutomationElementCenter $openButton 'open dialog Open button'
        }
        Start-Sleep -Milliseconds 700
        return $true
      }
    }catch{
      Log ('UIA open dialog filename path failed: '+$_.Exception.Message)
    }
    Start-Sleep -Milliseconds 300
  }while((Get-Date) -lt $deadline)
  Log 'open dialog not found by UIA-first path'
  return $false
}
function GetVisibleDialogs(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $windows=$root.FindAll(
    [System.Windows.Automation.TreeScope]::Children,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Window))
  )
  $dialogs=@()
  for($i=0;$i -lt $windows.Count;$i++){
    $window=$windows.Item($i)
    $rect=$window.Current.BoundingRectangle
    if($rect.Width -gt 80 -and $rect.Height -gt 40){
      $dialogs += $window
    }
  }
  return $dialogs
}
function GetElementTextLines($element){
  $lines=@()
  try{
    $name=([string]$element.Current.Name).Trim()
    if($name){ $lines += $name }
  }catch{}
  try{
    $valuePattern=$element.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
    $value=([string]$valuePattern.Current.Value).Trim()
    if($value){ $lines += $value }
  }catch{}
  try{
    $children=$element.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
    for($i=0;$i -lt $children.Count;$i++){
      $child=$children.Item($i)
      try{
        $childName=([string]$child.Current.Name).Trim()
        if($childName){ $lines += $childName }
      }catch{}
      try{
        $childValuePattern=$child.GetCurrentPattern([System.Windows.Automation.ValuePattern]::Pattern)
        $childValue=([string]$childValuePattern.Current.Value).Trim()
        if($childValue){ $lines += $childValue }
      }catch{}
    }
  }catch{}
  return @($lines | Where-Object { $_ } | Select-Object -Unique)
}
function SaveVisibleDialogSnapshot([string]$stage){
  $rows=@()
  foreach($dialog in @(GetVisibleDialogs)){
    try{
      if($dialog.Current.ClassName -ne '#32770'){ continue }
      $rect=$dialog.Current.BoundingRectangle
      $textLines=GetElementTextLines $dialog
      $rows += [pscustomobject]@{
        Stage=$stage
        Name=$dialog.Current.Name
        Class=$dialog.Current.ClassName
        NativeWindowHandle=$dialog.Current.NativeWindowHandle
        Rect=('{0},{1},{2},{3}' -f $rect.Left,$rect.Top,$rect.Width,$rect.Height)
        Text=$textLines
        TextJoined=($textLines -join "`n")
      }
    }catch{}
  }
  $safeStage=($stage -replace '[^A-Za-z0-9_.-]','_')
  $rows | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out ("visible_dialogs_$safeStage.json")) -Encoding UTF8
  Log ("saved visible dialog snapshot stage=$stage count="+(@($rows).Count))
  return @($rows)
}
function TestMnmReadFailureText([string]$text){
  if(-not $text){ return $false }
  $mnemonicReadFailed = [string]::Concat([char[]]@(0x8BFB,0x53D6,0x52A9,0x8BB0,0x7B26,0x5217,0x8868,0x5931,0x8D25))
  $mnemonic = [string]::Concat([char[]]@(0x52A9,0x8BB0,0x7B26))
  $failed = [string]::Concat([char[]]@(0x5931,0x8D25))
  $incorrect = [string]::Concat([char[]]@(0x4E0D,0x6B63,0x786E))
  $machineMismatch = [string]::Concat([char[]]@(0x673A,0x578B,0x4E0D,0x540C))
  $maxRows = [string]::Concat([char[]]@(0x6700,0x5927,0x884C,0x6570))
  $programName = [string]::Concat([char[]]@(0x7A0B,0x5E8F,0x540D))
  $structure = [string]::Concat([char[]]@(0x7ED3,0x6784,0x4F53))
  $duplicate = [string]::Concat([char[]]@(0x91CD,0x590D))
  if($text.Contains($mnemonicReadFailed)){ return $true }
  if($text.Contains($mnemonic) -and $text.Contains($failed)){ return $true }
  if($text.Contains($incorrect) -and $text.Contains($mnemonic)){ return $true }
  if($text.Contains('PLC') -and $text.Contains($machineMismatch) -and $text.Contains($maxRows)){ return $true }
  if(($text.Contains($programName) -or $text.Contains($structure)) -and $text.Contains($duplicate)){ return $true }
  return $false
}
function DismissDialogElement($dialog, [string]$label){
  try{
    $buttons=$dialog.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
    for($i=0;$i -lt $buttons.Count;$i++){
      $button=$buttons.Item($i)
      if(-not $button.Current.IsEnabled){ continue }
      $buttonName=[string]$button.Current.Name
      if($buttonName -and $buttonName -notmatch '^(OK|确定|是|Yes|はい)$'){ continue }
      try{
        $invokePattern=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
        $invokePattern.Invoke()
        Log ('dismissed '+$label+' dialog by button: '+$button.Current.Name)
        return $true
      }catch{
        ClickAutomationElementCenter $button ($label+' dialog button '+$button.Current.Name)
        return $true
      }
    }
  }catch{
    Log ('dismiss dialog failed '+$label+': '+$_.Exception.Message)
  }
  try{
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    Log ('dismissed '+$label+' dialog by Enter fallback')
    return $true
  }catch{}
  return $false
}
function AssertNoMnmReadFailureDialog([string]$stage){
  $dialogs=SaveVisibleDialogSnapshot $stage
  foreach($row in $dialogs){
    $text=[string]$row.TextJoined
    if(TestMnmReadFailureText $text){
      try{
        $root=[System.Windows.Automation.AutomationElement]::RootElement
        $dialog=$root.FindFirst(
          [System.Windows.Automation.TreeScope]::Children,
          (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NativeWindowHandleProperty,[int]$row.NativeWindowHandle))
        )
        if($dialog){ DismissDialogElement $dialog 'mnemonic read failure' | Out-Null }
      }catch{}
      $text | Set-Content -LiteralPath (Join-Path $out ("mnm_read_failure_$($stage -replace '[^A-Za-z0-9_.-]','_').txt")) -Encoding UTF8
      $flatText = $text -replace "(`r`n|`n|`r)", ' | '
      throw ("MNM read/import failed at stage " + $stage + ": " + $flatText)
    }
  }
}
function DismissInstructionErrorDialogs([string]$stage){
  $needle=[string]::Concat([char[]]@(0x4E0D,0x5B58,0x5728,0x7684,0x6307,0x4EE4))
  $dismissed=0
  foreach($dialog in @(GetVisibleDialogs)){
    try{
      if($dialog.Current.ClassName -ne '#32770'){ continue }
      $text=[string]((GetElementTextLines $dialog) -join "`n")
      if(-not $text.Contains($needle)){ continue }
      $text | Set-Content -LiteralPath (Join-Path $out ("instruction_error_$($stage -replace '[^A-Za-z0-9_.-]','_')_$dismissed.txt")) -Encoding UTF8
      DismissDialogElement $dialog ('instruction error '+$stage) | Out-Null
      $dismissed++
    }catch{}
  }
  if($dismissed -gt 0){ Log ("dismissed instruction-error dialogs stage=$stage count=$dismissed") }
}
function ConfirmProgramKindDialog(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $buttons=$root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.AndCondition(
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::NameProperty,'OK')),
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
    ))
  )
  for($i=0;$i -lt $buttons.Count;$i++){
    $button=$buttons.Item($i)
    $rect=$button.Current.BoundingRectangle
    if($rect.Width -ge 40 -and $rect.Width -le 120 -and
       $rect.Height -ge 18 -and $rect.Height -le 40 -and
       $rect.Left -ge 300 -and $rect.Left -le 700 -and
       $rect.Top -ge 250 -and $rect.Top -le 550){
      ClickAutomationElementCenter $button 'program kind OK button'
      return $true
    }
  }
  Log 'program kind dialog not found'
  return $false
}
function ConfirmAnyPostImportDialog(){
  $dialogs=@(GetVisibleDialogs)
  foreach($dialog in $dialogs){
    $name=$dialog.Current.Name
    $class=$dialog.Current.ClassName
    if($class -ne '#32770'){ continue }
    $buttons=$dialog.FindAll(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ControlTypeProperty,[System.Windows.Automation.ControlType]::Button))
    )
    for($i=0;$i -lt $buttons.Count;$i++){
      $button=$buttons.Item($i)
      $buttonName=$button.Current.Name
      if($buttonName -eq 'OK' -or $buttonName -match 'OK|纭畾|纰哄畾|銇亜|鏄瘄鎵撳紑|闁嬨亸'){
        try{
          $invokePattern=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
          $invokePattern.Invoke()
          Log ('invoked post-import dialog button: '+$buttonName+' dialog='+$name)
        }catch{
          ClickAutomationElementCenter $button ('post-import dialog button '+$buttonName)
        }
        return $true
      }
    }
  }
  return $false
}
function TestUiElementName([string]$name){
  if(-not $name){ return $false }
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $all=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  for($i=0;$i -lt $all.Count;$i++){
    $elementName=$all.Item($i).Current.Name
    if($elementName -eq $name -or $elementName -like ('*'+$name+'*')){
      return $true
    }
  }
  return $false
}
function FindProjectFilesContainingText([string]$root, [string]$needle){
  $matches=@()
  if(-not $root -or -not (Test-Path -LiteralPath $root) -or -not $needle){
    return $matches
  }
  $encodingDefault=[Text.Encoding]::Default
  $encodingUnicode=[Text.Encoding]::Unicode
  Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
    try{
      $bytes=[IO.File]::ReadAllBytes($_.FullName)
      $defaultText=$encodingDefault.GetString($bytes)
      $unicodeText=$encodingUnicode.GetString($bytes)
      if($defaultText.Contains($needle) -or $unicodeText.Contains($needle)){
        $matches += [pscustomobject]@{
          FullName=$_.FullName
          Length=$_.Length
          LastWriteTime=$_.LastWriteTime.ToString('s')
        }
      }
    }catch{}
  }
  return $matches
}
function GetMnmValidationNeedles([string]$path, [string]$expectedModuleName){
  $needles=@()
  if($expectedModuleName){ $needles += $expectedModuleName }
  if($path -and (Test-Path -LiteralPath $path)){
    Get-Content -LiteralPath $path -ErrorAction SilentlyContinue | ForEach-Object {
      $line=([string]$_).Trim()
      if($line -match '^(LD|LDP|LDF|AND|ANI|OR|ORI|OUT|SET|RES|MOV|DMOV|CMP|TMR|CNT)\s+([A-Za-z_][A-Za-z0-9_]*|[A-Z]+[0-9]+)'){
        $device=$matches[2]
        if($device -and $device -notmatch '^_Always(On|Off)$'){
          $needles += $device
        }
      }
      if($line -match '^;MODULE:(.+)$'){
        $needles += $matches[1].Trim()
      }
    }
  }
  return @($needles | Where-Object { $_ } | Select-Object -Unique)
}
function FindProjectFilesContainingAnyText([string]$root, [string[]]$needles){
  $results=@()
  foreach($needle in $needles){
    $matches=FindProjectFilesContainingText $root $needle
    $results += [pscustomobject]@{
      Needle=$needle
      Found=(@($matches).Count -gt 0)
      MatchingFiles=@($matches)
    }
  }
  return $results
}
function GetMissingValidationNeedles($matches){
  $missing=@()
  foreach($match in @($matches)){
    if(-not $match.Found){
      $missing += $match.Needle
    }
  }
  return @($missing | Where-Object { $_ } | Select-Object -Unique)
}
try{
  $RestartKvs = ConvertTo-BoolValue $RestartKvs $true
  $FailOnMissingProjectPlainText = ConvertTo-BoolValue $FailOnMissingProjectPlainText $false
  $FailOnMissingValidationNeedles = ConvertTo-BoolValue $FailOnMissingValidationNeedles $false
  Log 'start mnm import'
  Log ('MnmPath='+$MnmPath)
  Log ('ProjectPath='+$project)
  Log ('OutDir='+$out)
  if(-not $ExpectedModuleName -and $MnmPath){
    $ExpectedModuleName=[IO.Path]::GetFileNameWithoutExtension($MnmPath)
  }
  if(-not $ProjectSearchRoot){
    $ProjectSearchRoot=Split-Path -Parent $project
  }
  Log ('ExpectedModuleName='+$ExpectedModuleName)
  Log ('SaveAfterImport='+$SaveAfterImport.IsPresent)
  Log ('FailOnMissingProjectPlainText='+$FailOnMissingProjectPlainText)
  Log ('FailOnMissingValidationNeedles='+$FailOnMissingValidationNeedles)
  Log ('DeleteExistingModuleBeforeImport='+$DeleteExistingModuleBeforeImport.IsPresent)
  Log ('ProjectSearchRoot='+$ProjectSearchRoot)
  if(-not (Test-Path -LiteralPath $project)){ throw "ProjectPath not found: $project" }
  if(-not (Test-Path -LiteralPath $kvs)){ throw "KvsExe not found: $kvs" }
  if($MnmPath -and -not (Test-Path -LiteralPath $MnmPath)){ throw "MnmPath not found: $MnmPath" }
  if($RestartKvs){
    Get-Process Kvs -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  }
  $p = Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if(-not $p){
    Start-Process -FilePath $kvs -ArgumentList ('"'+$project+'"') | Out-Null
  }
  $deadline=(Get-Date).AddSeconds(90)
  do {
    Start-Sleep -Seconds 2
    $p=Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  } while((-not $p) -and (Get-Date) -lt $deadline)
  if(-not $p){ throw 'Kvs visible main window not found after start' }
  [W]::ShowWindow($p.MainWindowHandle,3)|Out-Null
  Start-Sleep -Seconds 1
  [W]::SetForegroundWindow($p.MainWindowHandle)|Out-Null
  if(-not (WaitKvsMainWindowReady 90)){
    throw 'KV STUDIO main window did not become ready.'
  }
  Start-Sleep -Seconds 2
  Shot '00_before_import.png'
  DismissInstructionErrorDialogs 'before_import'
  if($DeleteExistingModuleBeforeImport -and $ExpectedModuleName){
    if(-not (RemoveProjectModuleIfPresent $ExpectedModuleName)){
      if(-not (CreatePlaceholderModule)){
        throw "Failed to create placeholder module before deleting: $ExpectedModuleName"
      }
      if(-not (RemoveProjectModuleIfPresent $ExpectedModuleName)){
        if(-not (RenameProjectModuleIfPresent $ExpectedModuleName)){
          throw "Failed to delete or rename existing module before import: $ExpectedModuleName"
        }
      }
    }
  }elseif($ExpectedModuleName){
    OpenProjectModuleEditor $ExpectedModuleName | Out-Null
  }
  InvokeMnemonicImportMenu
  Shot '01_after_import_route.png'
  DumpUi 'uia_after_import_route.json'
  if($MnmPath){
    if(-not (SetOpenDialogFile $MnmPath)){
      [System.Windows.Forms.Clipboard]::SetText($MnmPath)
      [System.Windows.Forms.SendKeys]::SendWait('^v')
      Start-Sleep -Milliseconds 300
      [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
    }
    Start-Sleep -Seconds 8
    Shot '02_after_file_open.png'
    DumpUi 'uia_after_file_open.json'
    AssertNoMnmReadFailureDialog 'after_file_open'
    if(-not (CompleteMnemonicReadInsertFlow -PreferOverwrite $true)){
      DumpUi 'uia_after_insert_not_committed.json'
      throw 'MNM import did not commit: insert panel remained open after Insert'
    }
    DismissInstructionErrorDialogs 'after_insert_commit'
    $programKindConfirmed = ConfirmProgramKindDialog
    if($programKindConfirmed){
      Start-Sleep -Seconds 8
      AssertNoMnmReadFailureDialog 'after_program_kind_confirm'
    }elseif(ConfirmAnyPostImportDialog){
      Start-Sleep -Seconds 8
      AssertNoMnmReadFailureDialog 'after_post_import_dialog'
    }
  }
  Shot '03_after_import_confirm.png'
  DumpUi 'uia_after_import_confirm.json'
  AssertNoMnmReadFailureDialog 'after_import_confirm'
  $foundExpected=$false
  if($ExpectedModuleName){
    $foundExpected=TestUiElementName $ExpectedModuleName
  }
  $validationNeedles=GetMnmValidationNeedles $MnmPath $ExpectedModuleName
  $projectContentMatches=FindProjectFilesContainingAnyText $ProjectSearchRoot $validationNeedles
  $foundAnyProjectContent=(@($projectContentMatches | Where-Object { $_.Found }).Count -gt 0)
  $missingValidationNeedles=GetMissingValidationNeedles $projectContentMatches
  [pscustomobject]@{
    MnmPath=$MnmPath
    ProjectPath=$project
    ExpectedModuleName=$ExpectedModuleName
    FoundExpectedModule=$foundExpected
    ValidationNeedles=$validationNeedles
    FoundAnyProjectContent=$foundAnyProjectContent
    MissingValidationNeedles=$missingValidationNeedles
    ProjectContentMatches=$projectContentMatches
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $out 'import_validation.json') -Encoding UTF8
  if($FailOnMissingValidationNeedles -and @($missingValidationNeedles).Count -gt 0){
    throw "Missing MNM validation needles after import: $($missingValidationNeedles -join ', ')"
  }
  if($ExpectedModuleName -and -not $foundExpected){
    Log "Expected module name is not visible in KV STUDIO UI yet: $ExpectedModuleName"
  }
  if($SaveAfterImport){
    [System.Windows.Forms.SendKeys]::SendWait('^s')
    Log 'sent Ctrl+S'
    Start-Sleep -Seconds 8
    Shot '04_after_save.png'
    DumpUi 'uia_after_save.json'
    AssertNoMnmReadFailureDialog 'after_save'
    $projectMatches=FindProjectFilesContainingText $ProjectSearchRoot $ExpectedModuleName
    $projectContentMatchesAfterSave=FindProjectFilesContainingAnyText $ProjectSearchRoot $validationNeedles
    $foundAnyProjectContentAfterSave=(@($projectContentMatchesAfterSave | Where-Object { $_.Found }).Count -gt 0)
    $missingValidationNeedlesAfterSave=GetMissingValidationNeedles $projectContentMatchesAfterSave
    [pscustomobject]@{
      ProjectSearchRoot=$ProjectSearchRoot
      ExpectedModuleName=$ExpectedModuleName
      PlainTextSearchIsAdvisory=(-not $FailOnMissingProjectPlainText)
      FoundInProjectFiles=(@($projectMatches).Count -gt 0)
      MatchingFiles=@($projectMatches)
      ValidationNeedles=$validationNeedles
      FoundAnyProjectContent=$foundAnyProjectContentAfterSave
      MissingValidationNeedles=$missingValidationNeedlesAfterSave
      ProjectContentMatches=$projectContentMatchesAfterSave
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $out 'persistence_validation.json') -Encoding UTF8
    if($FailOnMissingValidationNeedles -and @($missingValidationNeedlesAfterSave).Count -gt 0){
      throw "Missing MNM validation needles after save: $($missingValidationNeedlesAfterSave -join ', ')"
    }
    if(-not $foundAnyProjectContentAfterSave){
      $plainTextMissMessage="No MNM validation needles found in project files after save: $($validationNeedles -join ', ')"
      if($FailOnMissingProjectPlainText){
        throw $plainTextMissMessage
      }
      Log ($plainTextMissMessage+'; continuing because KV project persistence is not guaranteed plaintext. Use exported MNM and convert result as the acceptance gate.')
    }
  }
  '0'|Set-Content -LiteralPath (Join-Path $out 'exit_code.txt') -Encoding ASCII
}catch{
  Log ('ERR '+$_.Exception.ToString())
  $_.Exception.ToString()|Set-Content -LiteralPath (Join-Path $out 'fail.txt') -Encoding UTF8
  '1'|Set-Content -LiteralPath (Join-Path $out 'exit_code.txt') -Encoding ASCII
  exit 1
}
