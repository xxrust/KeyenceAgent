param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [ValidateSet('ToolsMenu','Open','Inspect','Navigate','ReadPage','WritePage','Apply','Close')][string]$Action='Open',
  [ValidateSet('点参数','点参数通用设定','I/O 设定','原点复归设定','JOG设定','比较器设定')][string]$PageName='I/O 设定',
  [string]$ExpectedTablePath='',
  [string]$SourcePath='',
  [string]$ContractPath=''
)
$ErrorActionPreference='Stop'
$scriptsRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $scriptsRoot 'kv_window_binding.ps1')
. (Join-Path $scriptsRoot 'guards/kv_ui_guard.ps1')
. (Join-Path $scriptsRoot 'workflow_tools/kv_nano_cpu_position_contract.ps1')
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
New-Item -ItemType Directory -Force -Path $OutDir|Out-Null
Initialize-KvUiGuard -OutDir $OutDir
$result=[ordered]@{ok=$false;action=$Action;project_path=$ProjectPath}
function Snapshot($Scope,[string]$Name){
  $rows=@($Scope.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|ForEach-Object{
    $element=$_;$value=$null;$selection=$null;$range=$null
    $v=$null;if($element.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$v)){$value=$v.Current.Value}
    $v=$null;if($element.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$v)){$selection=$v.Current.IsSelected}
    $v=$null;if($element.TryGetCurrentPattern([Windows.Automation.RangeValuePattern]::Pattern,[ref]$v)){$range=@{value=$v.Current.Value;min=$v.Current.Minimum;max=$v.Current.Maximum}}
    [pscustomobject]@{name=$element.Current.Name;id=$element.Current.AutomationId;class=$element.Current.ClassName;type=$element.Current.ControlType.ProgrammaticName;hwnd=$element.Current.NativeWindowHandle;enabled=$element.Current.IsEnabled;offscreen=$element.Current.IsOffscreen;rect=$element.Current.BoundingRectangle.ToString();value=$value;selected=$selection;range=$range;parent=[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($element).Current.Name}
  })
  $rows|ConvertTo-Json -Depth 6|Set-Content (Join-Path $OutDir ($Name+'.json')) -Encoding UTF8
  return $rows
}
try{
  if($Action -eq 'WritePage'){$write=Get-KvCpuPositionWrite $PageName $ExpectedTablePath $SourcePath}
  $s=Get-KvProjectSession -ProjectPath $ProjectPath
  if($s.cpu_model -ne 'KV-NC32'){throw 'KV_CPU_POSITION_NC32_REQUIRED'}
  $result.session=$s
  $root=[Windows.Automation.AutomationElement]::FromHandle($s.hwnd)
  if($Action -in @('ToolsMenu','Open')){
    Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'clear prior research menu state' -Keys '{ESC}{ESC}' -ExpectedTitleLike 'KV STUDIO*'
    Invoke-KvGuardedAltVk -TargetHwnd $s.hwnd -Step 'open Nano Tools menu for CPU positioning configuration' -Vk 0x54 -ExpectedTitleLike 'KV STUDIO*'
    $menu=Snapshot $root 'tools_menu'
    if($Action -eq 'Open'){
      $items=@($root.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::MenuItem -and $_.Current.Name -match 'CPU.*定位.*参数.*\(I\)' -and $_.Current.IsEnabled -and -not $_.Current.IsOffscreen})
      if($items.Count -ne 1){throw 'KV_CPU_POSITION_TOOLS_MENU_ITEM_REQUIRED'}
      $r=$items[0].Current.BoundingRectangle
      Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd $s.hwnd -Step 'open exact observed Tools CPU positioning I menu command' -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SuccessProcessId $s.process_id -SleepMs 600
    }
  }
  $fg=Get-KvForegroundSnapshot
  if($Action -ne 'ToolsMenu'){
    if($fg.process_id -ne $s.process_id -or $fg.title -notlike '*定位*'){throw 'KV_CPU_POSITION_DIALOG_REQUIRED'}
    $dialog=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
    if($Action -in @('Navigate','ReadPage','WritePage')){
      $nodes=@($dialog.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::TreeItem -and $_.Current.Name -ceq $PageName})
      if($nodes.Count -ne 1){throw 'KV_CPU_POSITION_PAGE_UNIQUE_REQUIRED'}
      $r=$nodes[0].Current.BoundingRectangle
      Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step ('select exact CPU parameter page '+$PageName) -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -ExpectedTitleLike 'CPU定位参数设定*' -SleepMs 300
      $nodePattern=$nodes[0].GetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern)
      if(-not $nodePattern.Current.IsSelected){throw 'KV_CPU_POSITION_PAGE_SELECTION_FAILED'}
      $fg=Get-KvForegroundSnapshot
      $result.page=$PageName
    }
    if($Action -in @('ReadPage','WritePage')){
      function Copy-Grid([string]$FileName){
      $scroll=$dialog.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'_hScrollBar')))
      if(-not $scroll){throw 'KV_CPU_POSITION_GRID_SCROLL_REQUIRED'}
      $grid=[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($scroll)
      $r=$grid.Current.BoundingRectangle
      if($grid.Current.ControlType -ne [Windows.Automation.ControlType]::Pane -or $r.Width -lt 300 -or $r.Height -lt 150){throw 'KV_CPU_POSITION_GRID_FINGERPRINT_REQUIRED'}
      Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'focus observed CPU parameter grid for read-only copy' -X ([int]($r.X+100)) -Y ([int]($r.Y+65)) -ExpectedTitleLike 'CPU定位参数设定*'
      $sentinel='CPU_POSITION_COPY_'+[guid]::NewGuid().ToString('N')
      Invoke-KvGuardedClipboardSetText -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'initialize fresh CPU parameter copy sentinel' -Text $sentinel -ExpectedTitleLike 'CPU定位参数设定*'
      Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'select complete CPU parameter grid range for snapshot' -Keys '{ESC}^{HOME}^+{END}' -ExpectedTitleLike 'CPU定位参数设定*'
      Invoke-KvGuardedCtrlChord -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'copy all CPU parameter grid cells' -Vk 0x43 -ExpectedTitleLike 'CPU定位参数设定*' -SleepMs 350
      $text=[Windows.Forms.Clipboard]::GetText()
      [IO.File]::WriteAllText((Join-Path $OutDir $FileName),$text,[Text.UTF8Encoding]::new($false))
      if($text -eq $sentinel -or -not $text.Trim() -or $text -notmatch "`t"){throw 'KV_CPU_POSITION_GRID_FULL_COPY_NOT_CONFIRMED'}
      if($PageName -ne '点参数'){
        $lines=@($text.TrimEnd("`r","`n") -split '\r?\n')
        if(@($lines|Where-Object {$_.Split([char]9).Count -ne 3}).Count){throw 'KV_CPU_POSITION_THREE_AXIS_COPY_REQUIRED'}
        $rowCount=switch($PageName){'点参数通用设定'{1};'I/O 设定'{12};'原点复归设定'{9};'JOG设定'{4};'比较器设定'{6}}
        if($lines.Count -ne $rowCount){throw 'KV_CPU_POSITION_ROW_COUNT_MISMATCH'}
      }else{
        $lines=@($text.TrimEnd("`r","`n") -split '\r?\n')
        if($lines.Count -ne 60 -or @($lines|Where-Object {$_.Split([char]9).Count -ne 8}).Count){throw 'KV_CPU_POSITION_POINT_TABLE_SHAPE_MISMATCH'}
      }
      return (ConvertTo-KvCpuPositionTable $text)
      }
      $text=Copy-Grid 'table.tsv'
      $result.table=$text
      if($ExpectedTablePath){
        $expected=ConvertTo-KvCpuPositionTable ([IO.File]::ReadAllText($ExpectedTablePath,[Text.UTF8Encoding]::new($false,$true)))
        if($text -cne $expected){throw 'KV_CPU_POSITION_EXPECTED_TABLE_MISMATCH'}
      }
      if($Action -eq 'WritePage'){
        $result.before=$text;$result.changes=$write.changes
        if($PageName -eq 'JOG设定'){
          Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'select first JOG parameter cell before planned TSV block' -Keys '{ESC}^{HOME}' -ExpectedTitleLike 'CPU定位参数设定*'
          Invoke-KvGuardedClipboardSetText -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'prepare planned complete JOG table TSV' -Text ($write.after.Replace("`n","`r`n")+"`r`n") -ExpectedTitleLike 'CPU定位参数设定*'
          Invoke-KvGuardedCtrlChord -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'paste complete planned JOG table once' -Vk 0x56 -ExpectedTitleLike 'CPU定位参数设定*' -SleepMs 300
          $result.paste_count=1
        }else{
          foreach($change in $write.changes){
            $keys='{ESC}^{HOME}';if($change.row -gt 0){$keys+='{DOWN '+$change.row+'}'};if($change.axis -gt 1){$keys+='{RIGHT '+($change.axis-1)+'}'}
            Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'navigate exact planned I/O cell using grid selection' -Keys $keys -ExpectedTitleLike 'CPU定位参数设定*'
            Invoke-KvGuardedClipboardSetText -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'prepare planned I/O enumeration value' -Text $change.after -ExpectedTitleLike 'CPU定位参数设定*'
            Invoke-KvGuardedCtrlChord -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'paste exact planned I/O cell value' -Vk 0x56 -ExpectedTitleLike 'CPU定位参数设定*' -SleepMs 250
          }
        }
        Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'commit planned CPU parameter grid edits' -Keys '{TAB}' -ExpectedTitleLike 'CPU定位参数设定*'
        $after=Copy-Grid 'table_after.tsv'
        if($after -cne $write.after){throw 'KV_CPU_POSITION_WRITE_READBACK_MISMATCH'}
        $result.table=$after
      }
    }
    $result.dialog=$fg
    $controls=Snapshot $dialog 'controls'
    & (Join-Path $scriptsRoot 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'desktop.png' 6>$null|Out-Null
    if($Action -eq 'Apply'){
      $buttons=@($dialog.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::Button -and $_.Current.Name.Trim() -ceq '应用'})
      if($buttons.Count -ne 1 -or -not $buttons[0].Current.IsEnabled){throw 'KV_CPU_POSITION_APPLY_ENABLED_REQUIRED'}
      $r=$buttons[0].Current.BoundingRectangle
      Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'apply verified offline CPU parameters to project only' -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SuccessProcessId $s.process_id -SleepMs 400
      $result.after_apply=Get-KvForegroundSnapshot
      $null=Snapshot ([Windows.Automation.AutomationElement]::FromHandle([IntPtr]$result.after_apply.hwnd)) 'after_apply'
      & (Join-Path $scriptsRoot 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'after_apply.png' 6>$null|Out-Null
      if($result.after_apply.hwnd -ne $fg.hwnd){throw 'KV_CPU_POSITION_APPLY_SUCCESSOR_REVIEW_REQUIRED'}
      if($buttons[0].Current.IsEnabled){throw 'KV_CPU_POSITION_APPLY_NOT_COMMITTED'}
    }
    if($Action -eq 'Close'){
      Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'close CPU parameter editor after verified read or apply' -Keys '%{F4}' -ExpectedTitleLike 'CPU定位参数设定*' -SuccessTitleLike @('KV STUDIO*') -SleepMs 300
      if((Get-KvForegroundSnapshot).hwnd -ne $s.hwnd.ToInt64()){throw 'KV_CPU_POSITION_CLOSE_MAIN_REQUIRED'}
    }
  }else{& (Join-Path $scriptsRoot 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'desktop.png' 6>$null|Out-Null}
  $result.ok=$true
}catch{
  $result.error_code=$_.Exception.Message
  try{& (Join-Path $scriptsRoot 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'failure.png' 6>$null|Out-Null}catch{}
  throw
}finally{$result|ConvertTo-Json -Depth 8|Set-Content (Join-Path $OutDir 'cpu_position_result.json') -Encoding UTF8}
