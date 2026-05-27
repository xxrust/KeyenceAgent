param(
  [string]$ProjectPath = 'C:\Users\Public\KVSkillPractice\Projects\CodexUiCompileSmoke\CodexUiCompileSmoke.kpr',
  [string]$OutDir = 'C:\Users\Public\KVSkillPractice\vm-103\mnm_export_validation',
  [string]$KvsExe = 'C:\Program Files (x86)\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe',
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
}
"@
function Shot($n){try{$b=[Windows.Forms.Screen]::PrimaryScreen.Bounds;$bmp=New-Object Drawing.Bitmap $b.Width,$b.Height;$g=[Drawing.Graphics]::FromImage($bmp);$g.CopyFromScreen(0,0,0,0,$bmp.Size);$bmp.Save((Join-Path $out $n));$g.Dispose();$bmp.Dispose();Log "shot $n"}catch{Log ('shot err '+$_.Exception.Message)}}
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
function ClickAutomationElementCenter($element, [string]$label){
  $rect=$element.Current.BoundingRectangle
  $cx=[int]($rect.Left + ($rect.Width / 2))
  $cy=[int]($rect.Top + ($rect.Height / 2))
  [W]::SetCursorPos($cx,$cy) | Out-Null
  Start-Sleep -Milliseconds 150
  [W]::mouse_event(0x0002,0,0,0,0)
  Start-Sleep -Milliseconds 80
  [W]::mouse_event(0x0004,0,0,0,0)
  Log ('clicked '+$label+' '+$cx+','+$cy)
}
function ClickPoint([int]$x, [int]$y, [string]$label){
  [W]::SetCursorPos($x,$y) | Out-Null
  Start-Sleep -Milliseconds 150
  [W]::mouse_event(0x0002,0,0,0,0)
  Start-Sleep -Milliseconds 80
  [W]::mouse_event(0x0004,0,0,0,0)
  Log ('clicked '+$label+' '+$x+','+$y)
}
function ClickRectCenter($rect, [string]$label){
  $cx=[int]($rect.Left + ($rect.Width / 2))
  $cy=[int]($rect.Top + ($rect.Height / 2))
  ClickPoint $cx $cy $label
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
function FindMnemonicSaveMenuItem($parent){
  if(-not $parent){ return $null }
  $parentRect=GetElementRectObject $parent
  $items=@(GetVisibleMenuItems)
  $childCandidates=@()
  foreach($item in $items){
    $rect=GetElementRectObject $item
    $access=([string]$item.Current.AccessKey).Trim()
    if($access -notmatch '^(?i)s$'){ continue }
    if($rect.Left -le ($parentRect.Right - 12)){ continue }
    if($rect.Top -lt ($parentRect.Top - 8)){ continue }
    if($rect.Top -gt ($parentRect.Bottom + 120)){ continue }
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
function InvokeMnemonicExportMenu(){
  if(-not (OpenFileMenuByUia)){
    [System.Windows.Forms.SendKeys]::SendWait('%f')
    Start-Sleep -Milliseconds 500
  }
  Shot '01a_file_menu.png'
  DumpUi '01a_file_menu.json'

  $parent=FindMnemonicListMenuItem
  if(-not $parent){
    Log 'mnemonic-list parent menu not found by UIA; falling back to Alt+F,R,S'
    [System.Windows.Forms.SendKeys]::SendWait('r')
    Start-Sleep -Milliseconds 350
    Shot '01b_mnemonic_submenu.png'
    [System.Windows.Forms.SendKeys]::SendWait('s')
    Start-Sleep -Seconds 2
    Log 'sent fallback Alt+F,R,S for mnemonic list save/export'
    return
  }

  $save=FindMnemonicSaveMenuItem $parent
  if(-not $save){
    ExpandOrClickMenuItem $parent 'mnemonic-list parent'
    Start-Sleep -Milliseconds 700
    Shot '01b_mnemonic_submenu.png'
    DumpUi '01b_mnemonic_submenu.json'
    $save=FindMnemonicSaveMenuItem $parent
  }else{
    Shot '01b_mnemonic_submenu.png'
    DumpUi '01b_mnemonic_submenu.json'
  }
  if(-not $save){
    throw 'mnemonic-list save child menu not found by UIA'
  }
  InvokeOrClickMenuItem $save 'mnemonic-list save/export'
  Start-Sleep -Seconds 2
  Log 'invoked mnemonic list save/export through UIA menu path'
}
function SelectBrowseDialogPublicFolder(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $dialogs=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  for($i=0;$i -lt $dialogs.Count;$i++){
    $w=$dialogs.Item($i)
    if($w.Current.ClassName -ne '#32770'){ continue }
    $tree=$w.FindFirst(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty,'SysTreeView32'))
    )
    if(-not $tree){ continue }
    $items=$tree.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
    Log ('browse dialog tree items=' + $items.Count)
    $names=@('公用','Public')
    for($j=0;$j -lt $items.Count;$j++){
      $item=$items.Item($j)
      if($j -lt 12){ Log ('tree item ' + $j + ' name=' + $item.Current.Name + ' class=' + $item.Current.ClassName) }
      if($names -contains $item.Current.Name){
        ClickAutomationElementCenter $item ('folder tree item '+$item.Current.Name)
        Start-Sleep -Milliseconds 500
        return $true
      }
    }
    $rect=$w.Current.BoundingRectangle
    $x=[int]($rect.Left + 105)
    $y=[int]($rect.Top + 362)
    [W]::SetCursorPos($x,$y) | Out-Null
    Start-Sleep -Milliseconds 150
    [W]::mouse_event(0x0002,0,0,0,0)
    Start-Sleep -Milliseconds 80
    [W]::mouse_event(0x0004,0,0,0,0)
    Log ('clicked fallback Public row '+$x+','+$y)
    Start-Sleep -Milliseconds 500
    return $true
  }
  Log 'browse folder dialog tree not found for Public selection'
  return $false
}
function InvokeFolderDialogOk(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $windows=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  for($i=0;$i -lt $windows.Count;$i++){
    $w=$windows.Item($i)
    if($w.Current.ClassName -eq '#32770'){
      $tree=$w.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty,'SysTreeView32'))
      )
      if(-not $tree){ continue }
      $button=$w.FindFirst(
        [System.Windows.Automation.TreeScope]::Descendants,
        (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1'))
      )
      if($button){
        ClickAutomationElementCenter $button 'folder dialog OK by coordinates'
        Start-Sleep -Seconds 2
        $stillThere=$root.FindFirst(
          [System.Windows.Automation.TreeScope]::Descendants,
          (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty,'SysTreeView32'))
        )
        if($stillThere){
          try{
            $pattern=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
            $pattern.Invoke()
            Log 'invoked folder dialog OK by UIA fallback'
          }catch{
            Log ('UIA invoke fallback failed '+$_.Exception.Message)
          }
        }
        return $true
      }
    }
  }
  Log 'folder dialog OK button not found by UIA'
  return $false
}
function FindBrowseFolderDialog(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $dialogs=$root.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  for($i=0;$i -lt $dialogs.Count;$i++){
    $w=$dialogs.Item($i)
    if($w.Current.ClassName -ne '#32770'){ continue }
    $tree=$w.FindFirst(
      [System.Windows.Automation.TreeScope]::Descendants,
      (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::ClassNameProperty,'SysTreeView32'))
    )
    if($tree){ return [pscustomobject]@{ Window=$w; Tree=$tree } }
  }
  return $null
}
function TestTreeItemName($name, [string[]]$matchers){
  foreach($matcher in $matchers){
    if($matcher -like 'regex:*'){
      if($name -match $matcher.Substring(6)){ return $true }
    }elseif($matcher -like 'contains:*'){
      if($name -like ('*'+$matcher.Substring(9)+'*')){ return $true }
    }else{
      if($name -eq $matcher){ return $true }
    }
  }
  return $false
}
function FindVisibleTreeItem($tree, [string[]]$matchers, $parent, [int]$timeoutMs){
  $deadline=(Get-Date).AddMilliseconds($timeoutMs)
  do{
    $items=$tree.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
    $candidates=@()
    $parentRect=$null
    if($parent){ $parentRect=GetElementRectObject $parent }
    for($j=0;$j -lt $items.Count;$j++){
      $item=$items.Item($j)
      if($item.Current.ControlType -ne [System.Windows.Automation.ControlType]::TreeItem){ continue }
      $name=[string]$item.Current.Name
      if(-not (TestTreeItemName -name $name -matchers $matchers)){ continue }
      $rect=GetElementRectObject $item
      if($rect.Width -le 0 -or $rect.Height -le 0){ continue }
      if($parentRect){
        if($rect.Top -lt ($parentRect.Top - 2)){ continue }
        if($rect.Left -lt ($parentRect.Left - 30)){ continue }
      }
      $candidates += [pscustomobject]@{ Item=$item; Top=$rect.Top; Left=$rect.Left; Name=$name }
    }
    if($candidates.Count -gt 0){
      return ($candidates | Sort-Object Top,Left | Select-Object -First 1).Item
    }
    Start-Sleep -Milliseconds 200
  } while((Get-Date) -lt $deadline)
  return $null
}
function SelectAndExpandTreeItem($item, [string]$label, [bool]$expand){
  if(-not $item){ return $false }
  try{
    $scroll=$item.GetCurrentPattern([System.Windows.Automation.ScrollItemPattern]::Pattern)
    $scroll.ScrollIntoView()
    Log ('scroll into view '+$label)
    Start-Sleep -Milliseconds 150
  }catch{
    Log ('scroll unavailable '+$label+': '+$_.Exception.Message)
  }
  try{
    $select=$item.GetCurrentPattern([System.Windows.Automation.SelectionItemPattern]::Pattern)
    $select.Select()
    Log ('selected '+$label+' by SelectionItemPattern')
  }catch{
    ClickAutomationElementCenter $item ('tree item '+$label)
  }
  Start-Sleep -Milliseconds 250
  if($expand){
    try{
      $expandPattern=$item.GetCurrentPattern([System.Windows.Automation.ExpandCollapsePattern]::Pattern)
      if($expandPattern.Current.ExpandCollapseState -ne [System.Windows.Automation.ExpandCollapseState]::Expanded){
        $expandPattern.Expand()
        Log ('expanded '+$label+' by ExpandCollapsePattern')
        Start-Sleep -Milliseconds 500
      }else{
        Log ('already expanded '+$label)
      }
    }catch{
      Log ('expand unavailable '+$label+': '+$_.Exception.Message)
    }
  }
  return $true
}
function GetBrowsePathSteps([string]$folderPath){
  $resolved=(Resolve-Path -LiteralPath $folderPath).Path
  $root=[IO.Path]::GetPathRoot($resolved)
  $drive=$root.Substring(0,1).ToUpperInvariant()
  $relative=$resolved.Substring($root.Length).Trim('\')
  $parts=@()
  if($relative.Length -gt 0){ $parts=@($relative -split '\\') }
  $thisPc=(-join ([char[]](0x6B64,0x7535,0x8111)))
  $usersCn=(-join ([char[]](0x7528,0x6237)))
  $publicCn=(-join ([char[]](0x516C,0x7528)))
  $steps=@(
    ,@($thisPc,'This PC','Computer'),
    ,@( ('regex:\(' + [Regex]::Escape($drive) + ':\)$'), ('contains:' + ($drive+':')) )
  )
  if($parts.Count -gt 0){
    for($i=0;$i -lt $parts.Count;$i++){
      $part=$parts[$i]
      if($i -eq 0 -and $part -ieq 'Users'){
        $steps += ,@($usersCn,'Users')
      }elseif($i -eq 1 -and $parts[0] -ieq 'Users' -and $part -ieq 'Public'){
        $steps += ,@($publicCn,'Public')
      }else{
        $steps += ,@($part)
      }
    }
  }
  return $steps
}
function SelectBrowseDialogFolderPath([string]$folderPath){
  $dialog=FindBrowseFolderDialog
  if(-not $dialog){
    Log 'browse folder dialog tree not found'
    return $false
  }
  $tree=$dialog.Tree
  $items=$tree.FindAll([System.Windows.Automation.TreeScope]::Descendants,[System.Windows.Automation.Condition]::TrueCondition)
  Log ('browse dialog tree items=' + $items.Count)
  for($j=0;$j -lt [Math]::Min(20,$items.Count);$j++){
    $item=$items.Item($j)
    Log ('tree item ' + $j + ' name=' + $item.Current.Name + ' type=' + $item.Current.ControlType.ProgrammaticName)
  }
  $steps=GetBrowsePathSteps $folderPath
  $parent=$null
  for($i=0;$i -lt $steps.Count;$i++){
    $matchers=@()
    foreach($matcherValue in @($steps[$i])){
      if($matcherValue -is [array]){
        $matchers += [string[]]$matcherValue
      }else{
        $matchers += [string]$matcherValue
      }
    }
    $matchers=[string[]]$matchers
    $label=($matchers -join '|')
    $item=FindVisibleTreeItem -tree $tree -matchers $matchers -parent $parent -timeoutMs 5000
    if(-not $item){
      Log ('folder path step not found: '+$label)
      return $false
    }
    $shouldExpand=($i -lt ($steps.Count - 1))
    SelectAndExpandTreeItem -item $item -label $label -expand $shouldExpand | Out-Null
    $parent=$item
  }
  Log ('selected target export folder path '+$folderPath)
  return $true
}
function InvokeFolderDialogOkSafe(){
  $dialog=FindBrowseFolderDialog
  if(-not $dialog){
    Log 'folder dialog not found before OK'
    return $false
  }
  $button=$dialog.Window.FindFirst(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1'))
  )
  if($button){
    try{
      $pattern=$button.GetCurrentPattern([System.Windows.Automation.InvokePattern]::Pattern)
      $pattern.Invoke()
      Log 'invoked folder dialog OK by InvokePattern'
      Start-Sleep -Seconds 2
      return $true
    }catch{
      Log ('folder OK InvokePattern failed '+$_.Exception.Message)
    }
  }
  [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  Log 'sent Enter to folder dialog OK'
  Start-Sleep -Seconds 2
  return $true
}
function ClickDefaultDialogOk(){
  $root=[System.Windows.Automation.AutomationElement]::RootElement
  $buttons=$root.FindAll(
    [System.Windows.Automation.TreeScope]::Descendants,
    (New-Object System.Windows.Automation.PropertyCondition([System.Windows.Automation.AutomationElement]::AutomationIdProperty,'1'))
  )
  for($i=0;$i -lt $buttons.Count;$i++){
    $button=$buttons.Item($i)
    if($button.Current.IsEnabled){
      ClickAutomationElementCenter $button 'default dialog OK'
      return $true
    }
  }
  return $false
}
try{
  $RestartKvs = ConvertTo-BoolValue $RestartKvs $true
  Log 'start mnm export'
  $runStart = Get-Date
  Log ('ProjectPath='+$project)
  Log ('OutDir='+$out)
  if(-not (Test-Path -LiteralPath $project)){ throw "ProjectPath not found: $project" }
  if(-not (Test-Path -LiteralPath $kvs)){ throw "KvsExe not found: $kvs" }
  if($RestartKvs){
    Get-Process Kvs -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
  }
  $p = Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  if(-not $p){
    $started = Start-Process -FilePath $kvs -ArgumentList ('"'+$project+'"') -WindowStyle Maximized -PassThru
    Log ('started Kvs pid='+$started.Id)
  }
  $deadline=(Get-Date).AddSeconds(90)
  do {
    Start-Sleep -Seconds 2
    $p=Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 } | Select-Object -First 1
  } while((-not $p) -and (Get-Date) -lt $deadline)
  if(-not $p){
    Get-Process Kvs -ErrorAction SilentlyContinue |
      Select-Object Id,MainWindowTitle,MainWindowHandle,Path,StartTime |
      ConvertTo-Json -Depth 4 |
      Set-Content -LiteralPath (Join-Path $out 'kvs_processes_on_fail.json') -Encoding UTF8
    throw 'Kvs visible main window not found after start'
  }
  [W]::ShowWindow($p.MainWindowHandle,3)|Out-Null
  Start-Sleep -Seconds 1
  [W]::SetForegroundWindow($p.MainWindowHandle)|Out-Null
  Start-Sleep -Seconds 2
  Shot '00_before_export.png'
  InvokeMnemonicExportMenu
  Shot '01_after_export_route.png'
  DumpUi 'uia_after_export_route.json'
  if(-not (ClickDefaultDialogOk)){
    [System.Windows.Forms.SendKeys]::SendWait('{ENTER}')
  }
  Start-Sleep -Seconds 2
  Shot '02_after_comment_type_ok.png'
  DumpUi 'uia_after_comment_type_ok.json'
  if(-not (SelectBrowseDialogFolderPath $out)){
    throw "Failed to select export folder in browse dialog: $out"
  }
  Shot '02b_after_folder_select.png'
  if(-not (InvokeFolderDialogOkSafe)){
    [System.Windows.Forms.SendKeys]::SendWait('{TAB}{TAB}{ENTER}')
  }
  Start-Sleep -Seconds 8
  Shot '03_after_export_enter.png'
  $searchRoots = @($out, 'C:\Users\Public') | Select-Object -Unique
  $mnmFiles = @()
  foreach($rootPath in $searchRoots){
    if(Test-Path -LiteralPath $rootPath){
      $mnmFiles += Get-ChildItem -LiteralPath $rootPath -Recurse -Filter '*.mnm' -File -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -ge $runStart.AddSeconds(-2) }
    }
  }
  foreach($mnm in $mnmFiles){
    if($mnm.DirectoryName -ne $out){
      Copy-Item -LiteralPath $mnm.FullName -Destination (Join-Path $out $mnm.Name) -Force
      Log ('copied exported mnm from '+$mnm.FullName)
    }
  }
  Get-ChildItem -LiteralPath $out -Recurse | Select FullName,Length,LastWriteTime | Format-Table -AutoSize | Out-String -Width 260 | Set-Content -LiteralPath (Join-Path $out 'export_files.txt') -Encoding UTF8
  $mnmFiles = Get-ChildItem -LiteralPath $out -Recurse -Filter '*.mnm' -File -ErrorAction SilentlyContinue
  $mnmFiles | Select-Object FullName,Length,LastWriteTime | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $out 'mnm_files.json') -Encoding UTF8
  if(-not $mnmFiles){ throw "No .mnm files were produced under $out" }
  '0'|Set-Content -LiteralPath (Join-Path $out 'exit_code.txt') -Encoding ASCII
}catch{
  Log ('ERR '+$_.Exception.ToString())
  $_.Exception.ToString()|Set-Content -LiteralPath (Join-Path $out 'fail.txt') -Encoding UTF8
  '1'|Set-Content -LiteralPath (Join-Path $out 'exit_code.txt') -Encoding ASCII
  exit 1
}
