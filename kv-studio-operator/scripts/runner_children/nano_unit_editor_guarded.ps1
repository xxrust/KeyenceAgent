param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [ValidateSet('Open','Inspect','Query','Select','SetParameter','Commit','Cancel','Delete','Add')][string]$Action='Query',
  [int]$UnitIndex=0,
  [string]$ExpectedModel='',
  [string]$ParameterName='',
  [string]$ExpectedValue='',
  [string]$Value='',
  [string]$ExpectedAfterRowsPath='',
  [string]$ExpectedLayoutPath='',
  [string]$ExpectedSnapshotPath='',
  [string]$ContractPath=''
)
$ErrorActionPreference='Stop'
$scriptsRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $scriptsRoot 'kv_window_binding.ps1')
. (Join-Path $scriptsRoot 'kv_tree_resolver.ps1')
. (Join-Path $scriptsRoot 'guards/kv_ui_guard.ps1')
. (Join-Path $scriptsRoot 'workflow_tools/kv_nano_unit_native.ps1')
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
Add-Type -AssemblyName System.Windows.Forms
New-Item -ItemType Directory -Force -Path $OutDir|Out-Null
Initialize-KvUiGuard -OutDir $OutDir
$result=[ordered]@{ok=$false;action=$Action;project_path=[IO.Path]::GetFullPath($ProjectPath)}
function Dump($Scope,[string]$Name){
  $rows=@($Scope.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|ForEach-Object{
    $e=$_;$value=$null;$selected=$null;$v=$null
    if($e.TryGetCurrentPattern([Windows.Automation.ValuePattern]::Pattern,[ref]$v)){$value=$v.Current.Value}
    $v=$null;if($e.TryGetCurrentPattern([Windows.Automation.SelectionItemPattern]::Pattern,[ref]$v)){$selected=$v.Current.IsSelected}
    [pscustomobject]@{name=$e.Current.Name;id=$e.Current.AutomationId;class=$e.Current.ClassName;type=$e.Current.ControlType.ProgrammaticName;hwnd=$e.Current.NativeWindowHandle;enabled=$e.Current.IsEnabled;offscreen=$e.Current.IsOffscreen;rect=$e.Current.BoundingRectangle.ToString();value=$value;selected=$selected;parent=[Windows.Automation.TreeWalker]::ControlViewWalker.GetParent($e).Current.Name}
  })
  $rows|ConvertTo-Json -Depth 6|Set-Content (Join-Path $OutDir ($Name+'.json')) -Encoding UTF8
  return $rows
}
function Elements { @($editor.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)) }
function FindControl([string]$Class,[string]$Id) {
  $all=@(Elements|Where-Object {$_.Current.ClassName -eq $Class -and $_.Current.AutomationId -eq $Id -and -not $_.Current.IsOffscreen})
  if($all.Count -ne 1){throw "KV_NANO_UNIT_CONTROL_REQUIRED:$Class/$Id count=$($all.Count)"};return $all[0]
}
function CurrentRows {
 $grid=FindControl 'SysListView32' '666'
 return ,([KvNanoUnitNative]::Rows([IntPtr]$grid.Current.NativeWindowHandle,$s.process_id))
}
function SelectUnit([int]$Index,[string]$Model,[switch]$CanvasFocus) {
 $views=@(Elements|Where-Object {$_.Current.ClassName -eq 'AfxFrameOrView140' -and $_.Current.AutomationId -eq '59648'})
 if($views.Count -ne 1 -or $Index -lt 0 -or $Index -gt 7){throw 'KV_NANO_UNIT_CANVAS_REQUIRED'}
 $r=$views[0].Current.BoundingRectangle
 # Cell dimensions observed in the Nano unit drawing. Every click is checked
 # against the selected-unit title before any parameter input is allowed.
 $scroll=[KvNanoUnitNative]::GetScrollPos([IntPtr]$views[0].Current.NativeWindowHandle,0)
 $x=[int]($r.X+168+73*$Index-$scroll);$y=[int]($r.Y+45)
 if($x -ge $r.Right){throw 'KV_NANO_UNIT_CANVAS_SCROLL_NOT_SUPPORTED'}
 Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step "select Nano unit $Index $Model" -X $x -Y $y -ExpectedTitleLike '*单元编辑器*' -SleepMs 180
 $tabs=@(Elements|Where-Object {$_.Current.AutomationId -eq '501' -and $_.Current.ClassName -like 'Afx:TabWnd:*'})
 if($tabs.Count -ne 1){throw 'KV_NANO_UNIT_SETTINGS_TAB_REQUIRED'}
 $r=$tabs[0].Current.BoundingRectangle
 Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'select installed unit settings tab' -X ([int]($r.X+135)) -Y ([int]($r.Y+12)) -ExpectedTitleLike '*单元编辑器*' -SleepMs 120
 $actual=(FindControl 'Static' '703').Current.Name
 if($actual -cne "[$Index] $Model"){throw "KV_NANO_UNIT_SELECTED_MODEL_MISMATCH:$actual"}
 if($CanvasFocus){
  Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'focus verified selected unit canvas for deletion' -X $x -Y $y -ExpectedTitleLike '*单元编辑器*' -SleepMs 100
 }
}
function ClickButton([string]$Id,[string]$Name) {
 $button=FindControl 'Button' $Id
 if($button.Current.Name -cne $Name -or -not $button.Current.IsEnabled){throw 'KV_NANO_UNIT_BUTTON_FINGERPRINT_MISMATCH'}
 $r=$button.Current.BoundingRectangle
 Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd ([IntPtr]$fg.hwnd) -Step "unit editor $Name" -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SuccessProcessId $s.process_id -SleepMs 300
}
function FinishCommit {
 $deadline=(Get-Date).AddSeconds(8)
 do{
  $current=Get-KvForegroundSnapshot
  if($current.hwnd -eq $s.hwnd){
    Invoke-KvGuardedCtrlChord -TargetHwnd $s.hwnd -Step 'save offline unit configuration' -Vk 0x53 -ExpectedTitleLike 'KV STUDIO*' -SleepMs 400
    return
  }
  if($current.process_id -eq $s.process_id -and $current.class_name -ceq '#32770' -and $current.title -ceq 'KV STUDIO'){
    $prompt=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$current.hwnd)
    $controls=Dump $prompt 'system_comment_prompt'
    $message=@($controls|Where-Object {$_.id -eq '65535' -and $_.class -eq 'Static'})
    $expectedText="通过设定更改，更改了内置功能中使用的 CR/CM 的分配。`n是否在更改后的软元件分配区登录样例注释？"
    if($message.Count -ne 1 -or $message[0].name -cne $expectedText){throw 'KV_NANO_UNIT_SYSTEM_COMMENT_PROMPT_MISMATCH'}
    $no=@($prompt.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.ClassName -eq 'Button' -and $_.Current.AutomationId -eq '7' -and $_.Current.Name -ceq '否(N)'})
    if($no.Count -ne 1){throw 'KV_NANO_UNIT_SYSTEM_COMMENT_NO_REQUIRED'}
    $r=$no[0].Current.BoundingRectangle
    Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd ([IntPtr]$current.hwnd) -Step 'decline CR CM sample comment registration' -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SuccessProcessId $s.process_id -SleepMs 300
    $result.system_comments_registration='declined'
  }elseif($current.process_id -ne $s.process_id){throw 'KV_NANO_UNIT_COMMIT_PROCESS_MISMATCH'}
  Start-Sleep -Milliseconds 80
 }while((Get-Date) -lt $deadline)
 throw 'KV_NANO_UNIT_COMMIT_SUCCESSOR_REVIEW_REQUIRED'
}
try{
  $s=Get-KvProjectSession -ProjectPath $ProjectPath
  if($s.cpu_model -ne 'KV-NC32'){throw 'KV_NANO_UNIT_NC32_REQUIRED'}
  $result.session=$s
  $main=[Windows.Automation.AutomationElement]::FromHandle($s.hwnd)
  $result.project_tree=@($main.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::TreeItem}|ForEach-Object {$_.Current.Name})
  $layout=@($result.project_tree|Where-Object {$_ -match '^\[\d+\]\s+KV-NC'}|ForEach-Object {if($_ -match '^\[\d+\]\s+(\S+)'){$Matches[1]}})
  if($Action -in @('Add','Delete')){
    $plannedLayout=@($layout)
    if($Action -eq 'Add'){$plannedLayout+= $ExpectedModel}
    else{$plannedLayout=@(0..($layout.Count-1)|Where-Object {$_ -ne $UnitIndex}|ForEach-Object {$layout[$_]})}
    ConvertTo-Json -InputObject $plannedLayout|Set-Content (Join-Path $OutDir 'layout_expected.json') -Encoding UTF8
  }
  $existing=Get-KvForegroundSnapshot
  if($Action -eq 'Commit' -and $existing.process_id -eq $s.process_id -and $existing.class_name -ceq '#32770' -and $existing.title -ceq 'KV STUDIO'){
    FinishCommit;$result.ok=$true;return
  }
  if($existing.process_id -ne $s.process_id -or $existing.title -notlike '*单元编辑器*'){
    $cpu=@($main.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.ControlType -eq [Windows.Automation.ControlType]::TreeItem -and $_.Current.Name -match '^\[0\]\s+KV-NC32\b'})
    if($cpu.Count -ne 1){throw 'KV_NANO_UNIT_CPU_TREE_REQUIRED'}
    $r=$cpu[0].Current.BoundingRectangle
    foreach($i in 1..2){Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd $s.hwnd -Step ('open exact Nano CPU tree click '+$i) -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SuccessProcessId $s.process_id -SleepMs 60}
  }
  $fg=Get-KvForegroundSnapshot
  if($fg.process_id -ne $s.process_id -or $fg.title -notlike '*单元编辑器*'){throw 'KV_NANO_UNIT_EDITOR_REQUIRED'}
  $editor=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$fg.hwnd)
  $pendingDelete=($fg.title -ceq '单元编辑器' -and $Action -eq 'Delete')
  if($pendingDelete){
    $editors=@($main.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.Name -ceq '单元编辑器 - 编辑模式'})
    if($editors.Count -ne 1){throw 'KV_NANO_UNIT_DELETE_EDITOR_REQUIRED'}
    $editor=$editors[0]
    if((FindControl 'Static' '703').Current.Name -cne "[$UnitIndex] $ExpectedModel"){throw 'KV_NANO_UNIT_PENDING_DELETE_IDENTITY_MISMATCH'}
  }
  $result.editor=$fg
  if($Action -eq 'Add'){
    if($ExpectedModel -notin @('KV-NC1EP','KV-NC16EXT*')){throw 'KV_NANO_UNIT_ADD_MODEL_NOT_VERIFIED'}
    $installed=@($result.project_tree|Where-Object {$_ -match '^\[\d+\]\s+KV-NC'})
    if($UnitIndex -ne $installed.Count){throw 'KV_NANO_UNIT_APPEND_INDEX_REQUIRED'}
    $view=@(Elements|Where-Object {$_.Current.ClassName -eq 'AfxFrameOrView140' -and $_.Current.AutomationId -eq '59648'})
    if($view.Count -ne 1){throw 'KV_NANO_UNIT_CANVAS_REQUIRED'}
    $r=$view[0].Current.BoundingRectangle;$scroll=[KvNanoUnitNative]::GetScrollPos([IntPtr]$view[0].Current.NativeWindowHandle,0);$x=[int]($r.X+168+73*$UnitIndex-$scroll)
    if($x -ge $r.Right){throw 'KV_NANO_UNIT_CANVAS_SCROLL_NOT_SUPPORTED'}
    Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'select planned empty append slot before catalog insertion' -X $x -Y ([int]($r.Y+45)) -ExpectedTitleLike '*单元编辑器*'
    $tabs=@(Elements|Where-Object {$_.Current.AutomationId -eq '501' -and $_.Current.ClassName -like 'Afx:TabWnd:*'})
    if($tabs.Count -ne 1){throw 'KV_NANO_UNIT_CATALOG_TAB_REQUIRED'}
    $r=$tabs[0].Current.BoundingRectangle
    Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'select Nano unit catalog' -X ([int]($r.X+43)) -Y ([int]($r.Y+12)) -ExpectedTitleLike '*单元编辑器*'
    $toolbar=FindControl 'ToolbarWindow32' '59392';$r=$toolbar.Current.BoundingRectangle
    foreach($offset in @(12,38,64,90)){
      Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step "select flat catalog mode $offset" -X ([int]($r.X+$offset)) -Y ([int]($r.Y+12)) -ExpectedTitleLike '*单元编辑器*' -SleepMs 60
    }
    $grids=@(Elements|Where-Object {$_.Current.ClassName -eq 'SysListView32' -and $_.Current.AutomationId -in @('568','566') -and -not $_.Current.IsOffscreen})
    if($grids.Count -ne 1){throw 'KV_NANO_UNIT_FLAT_CATALOG_REQUIRED'}
    $grid=$grids[0];$r=$grid.Current.BoundingRectangle
    Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'focus Nano model catalog' -X ([int]($r.X+150)) -Y ([int]($r.Y+20)) -ExpectedTitleLike '*单元编辑器*'
    Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'start catalog from first model' -Keys '^{HOME}' -ExpectedTitleLike '*单元编辑器*' -SleepMs 35
    $count=[KvNanoUnitNative]::SendMessage([IntPtr]$grid.Current.NativeWindowHandle,0x1004,[IntPtr]::Zero,[IntPtr]::Zero).ToInt32()
    if($count -le 0 -or $count -gt 256){throw 'KV_NANO_UNIT_CATALOG_COUNT_INVALID'}
    $found=$false
    for($i=0;$i -lt $count;$i++){
      $actual=(FindControl 'Static' '698').Current.Name
      if($actual -ceq $ExpectedModel){$found=$true;break}
      Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step "scan Nano catalog model $i" -Keys '{DOWN}' -ExpectedTitleLike '*单元编辑器*' -SleepMs 35
    }
    if(-not $found){throw 'KV_NANO_UNIT_CATALOG_MODEL_NOT_FOUND'}
    $result.catalog_model=$actual;$result.catalog_row=$i
    Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'add exact selected Nano catalog model' -Keys '{ENTER}' -ExpectedTitleLike '*单元编辑器*' -SleepMs 250
    SelectUnit $UnitIndex $ExpectedModel
    $result.added_rows=CurrentRows
  }
  if($Action -eq 'Query'){
    $units=@()
    foreach($line in $result.project_tree){
      if($line -match '^\[(\d+)\]\s+(KV-NC\S+)\s+(.+)$'){
        $index=[int]$Matches[1];$model=$Matches[2];$allocation=$Matches[3]
        SelectUnit $index $model
        $units += [pscustomobject]@{unit_index=$index;model=$model;allocation=$allocation;rows=(CurrentRows)}
      }
    }
    if(-not $units.Count){throw 'KV_NANO_UNIT_LAYOUT_EMPTY'}
    $result.units=$units
    $units|ConvertTo-Json -Depth 10|Set-Content (Join-Path $OutDir 'units.json') -Encoding UTF8
    if($ExpectedLayoutPath){
      $expected=Get-Content -LiteralPath $ExpectedLayoutPath -Raw -Encoding UTF8|ConvertFrom-Json
      if(($expected -join '|') -cne (($units|ForEach-Object {$_.model}) -join '|')){throw 'KV_NANO_UNIT_SAVED_LAYOUT_MISMATCH'}
    }
    if($ExpectedSnapshotPath){
      $expected=Get-Content -LiteralPath $ExpectedSnapshotPath -Raw -Encoding UTF8|ConvertFrom-Json
      if((ConvertTo-Json -InputObject @($expected) -Depth 14 -Compress) -cne (ConvertTo-Json -InputObject @($units) -Depth 14 -Compress)){throw 'KV_NANO_UNIT_SNAPSHOT_MISMATCH'}
    }
    if($ParameterName){
      $unit=@($units|Where-Object {$_.unit_index -eq $UnitIndex -and $_.model -ceq $ExpectedModel})
      if($unit.Count -ne 1){throw 'KV_NANO_UNIT_QUERY_PARAMETER_UNIT_MISMATCH'}
      $cells=@($unit[0].rows|Where-Object {$_[1] -ceq $ParameterName})
      if($cells.Count -ne 1 -or $cells[0][2] -cne $Value){throw 'KV_NANO_UNIT_SAVED_PARAMETER_MISMATCH'}
    }
  }
  if($Action -in @('Select','SetParameter','Delete')){
    if(-not $ExpectedModel){throw 'KV_NANO_UNIT_EXPECTED_MODEL_REQUIRED'}
    if(-not $pendingDelete){SelectUnit $UnitIndex $ExpectedModel}
    $result.before=CurrentRows
  }
  if($Action -eq 'SetParameter'){
    $rows=CurrentRows
    $indices=@(0..($rows.Count-1)|Where-Object {$rows[$_][1] -ceq $ParameterName})
    if($indices.Count -ne 1){throw 'KV_NANO_UNIT_PARAMETER_UNIQUE_REQUIRED'}
    $row=$indices[0]
    if($rows[$row][2] -cne $ExpectedValue){throw 'KV_NANO_UNIT_EXPECTED_VALUE_MISMATCH'}
    $grid=FindControl 'SysListView32' '666';$r=$grid.Current.BoundingRectangle
    Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'focus unit parameter list label column' -X ([int]($r.X+80)) -Y ([int]($r.Y+28)) -ExpectedTitleLike '*单元编辑器*'
    Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'select planned unit parameter row' -Keys ('{HOME}{DOWN '+$row+'}') -ExpectedTitleLike '*单元编辑器*'
    $result.selected_controls=Dump $editor 'selected_controls'
    $result.parameter_row=$row
    if((FindControl 'Static' '698').Current.Name -cne $ParameterName){throw 'KV_NANO_UNIT_PARAMETER_SELECTION_MISMATCH'}
    $inputs=@(Elements|Where-Object {(($_.Current.AutomationId -eq '501' -and $_.Current.ClassName -in @('ComboBox','Edit')) -or ($_.Current.AutomationId -eq '506' -and $_.Current.ClassName -eq 'SysIPAddress32')) -and -not $_.Current.IsOffscreen})
    if($inputs.Count -ne 1 -or -not $inputs[0].Current.IsEnabled){throw 'KV_NANO_UNIT_PARAMETER_INPUT_REQUIRED'}
    $input=$inputs[0];$r=$input.Current.BoundingRectangle
    if($input.Current.ClassName -eq 'ComboBox'){
      $items=[KvNanoUnitNative]::ComboItems([IntPtr]$input.Current.NativeWindowHandle)
      $result.options=$items
      $option=@(0..($items.Count-1)|Where-Object {$items[$_] -ceq $Value})
      if($option.Count -ne 1){throw 'KV_NANO_UNIT_ENUM_VALUE_NOT_OFFERED'}
      $null=Assert-KvUiForegroundHwnd -ExpectedHwnd ([IntPtr]$fg.hwnd) -Step 'set exact native unit enumeration' -ExpectedTitleLike '*单元编辑器*'
      Write-KvUiGuardRunLog -Event 'native_combo_write_before' -Data @{parameter=$ParameterName;old=$ExpectedValue;new=$Value;hwnd=$input.Current.NativeWindowHandle}
      [KvNanoUnitNative]::SetCombo([IntPtr]$input.Current.NativeWindowHandle,$s.process_id,$option[0],$Value)
      $r=(FindControl 'Static' '502').Current.BoundingRectangle
      Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'commit native enum selection to unit parameter' -X ([int]($r.X+30)) -Y ([int]($r.Y+$r.Height/2)) -ExpectedTitleLike '*单元编辑器*'
    }elseif($input.Current.ClassName -eq 'SysIPAddress32'){
      if($Value -notmatch '^\d{1,3}(\.\d{1,3}){3}$' -or @($Value.Split('.')|Where-Object {[int]$_ -gt 255}).Count){throw 'KV_NANO_UNIT_IPV4_INVALID'}
      $octets=$Value.Split('.')
      $fields=@($input.FindAll([Windows.Automation.TreeScope]::Children,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.ClassName -eq 'Edit'}|Sort-Object {$_.Current.BoundingRectangle.X})
      if($fields.Count -ne 4){throw 'KV_NANO_UNIT_IPV4_FIELDS_REQUIRED'}
      for($i=0;$i -lt 4;$i++){
        if($fields[$i].Current.Name -ceq $octets[$i]){continue}
        $r=$fields[$i].Current.BoundingRectangle
        Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step "focus IP octet $i" -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -ExpectedTitleLike '*单元编辑器*'
        Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'select existing IP octet' -Keys '^a' -ExpectedTitleLike '*单元编辑器*'
        Invoke-KvGuardedClipboardSetText -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'prepare planned IP octet' -Text $octets[$i] -ExpectedTitleLike '*单元编辑器*'
        Invoke-KvGuardedCtrlChord -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'paste planned IP octet' -Vk 0x56 -ExpectedTitleLike '*单元编辑器*'
      }
      $r=(FindControl 'Static' '502').Current.BoundingRectangle
      Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'commit IPv4 field to verified parameter row' -X ([int]($r.X+30)) -Y ([int]($r.Y+$r.Height/2)) -ExpectedTitleLike '*单元编辑器*'
    }else{
      if($Value -notmatch '^[A-Za-z0-9_.:+ -]{1,64}$'){throw 'KV_NANO_UNIT_TEXT_VALUE_NOT_SUPPORTED'}
      Invoke-KvGuardedMouseClick -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'focus verified unit parameter text' -X ([int]($r.X+30)) -Y ([int]($r.Y+$r.Height/2)) -ExpectedTitleLike '*单元编辑器*'
      Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'select existing parameter text' -Keys '^a' -ExpectedTitleLike '*单元编辑器*'
      Invoke-KvGuardedClipboardSetText -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'prepare planned parameter value' -Text $Value -ExpectedTitleLike '*单元编辑器*'
      Invoke-KvGuardedCtrlChord -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'paste planned parameter value' -Vk 0x56 -ExpectedTitleLike '*单元编辑器*'
      Invoke-KvGuardedSendKeys -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'commit parameter text edit' -Keys '{TAB}' -ExpectedTitleLike '*单元编辑器*'
    }
    $result.after=CurrentRows
    if($result.after[$row][2] -cne $Value){throw "KV_NANO_UNIT_PARAMETER_READBACK_MISMATCH:$($result.after[$row][2])"}
    if($ExpectedAfterRowsPath){
      [string[][]]$expectedAfter=Get-Content $ExpectedAfterRowsPath -Raw -Encoding UTF8|ConvertFrom-Json
      if((ConvertTo-Json -InputObject $expectedAfter -Depth 12 -Compress) -cne (ConvertTo-Json -InputObject ([string[][]]$result.after) -Depth 12 -Compress)){throw 'KV_NANO_UNIT_EXPECTED_AFTER_ROWS_MISMATCH'}
    }else{
      for($i=0;$i -lt $rows.Count;$i++){
        if($i -ne $row -and ($rows[$i] -join "`t") -cne ($result.after[$i] -join "`t")){throw "KV_NANO_UNIT_UNPLANNED_PARAMETER_CHANGE:$i"}
      }
    }
  }
  if($Action -eq 'Delete'){
    if($UnitIndex -eq 0){throw 'KV_NANO_UNIT_CPU_DELETE_FORBIDDEN'}
    if(-not $pendingDelete){
      SelectUnit $UnitIndex $ExpectedModel -CanvasFocus
      Invoke-KvGuardedVkTapCallerOracle -TargetHwnd ([IntPtr]$fg.hwnd) -Step 'delete verified selected expansion unit' -Vk 0x2E -ExpectedTitleLike '*单元编辑器*'
    }
    $modal=Get-KvForegroundSnapshot
    if($modal.process_id -ne $s.process_id -or $modal.title -cne '单元编辑器' -or $modal.class_name -cne '#32770'){throw 'KV_NANO_UNIT_DELETE_CONFIRMATION_REQUIRED'}
    $dialog=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$modal.hwnd)
    $controls=Dump $dialog 'delete_confirmation'
    $message=@($controls|Where-Object {$_.id -eq '65535' -and $_.class -eq 'Static'})
    $expectedMessage="根据单元配置更改进行程序的软元件自动转换模式时, 由于与该单元相关的程序变为无效, 因此有必要手动删除程序。`n`n可以删除吗?"
    if($message.Count -ne 1 -or $message[0].name -cne $expectedMessage){throw 'KV_NANO_UNIT_DELETE_MESSAGE_FINGERPRINT_MISMATCH'}
    $yes=@($dialog.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.AutomationId -eq '6' -and $_.Current.Name -ceq '是(Y)' -and $_.Current.ClassName -eq 'Button'})
    if($yes.Count -ne 1){throw 'KV_NANO_UNIT_DELETE_YES_REQUIRED'}
    $r=$yes[0].Current.BoundingRectangle
    Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd ([IntPtr]$modal.hwnd) -Step 'confirm exact unit deletion warning in project copy' -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SuccessProcessId $s.process_id -SleepMs 300
    $fg=Get-KvForegroundSnapshot
    if($fg.hwnd -ne $editor.Current.NativeWindowHandle){throw 'KV_NANO_UNIT_DELETE_EDITOR_SUCCESSOR_REQUIRED'}
  }
  if($Action -eq 'Commit'){
    ClickButton '23017' 'OK'
    FinishCommit
    $result.ok=$true;return
  }
  if($Action -eq 'Cancel'){
    if($fg.class_name -ne '#32770'){ClickButton '23016' '取消'}
    $cancelModal=Get-KvForegroundSnapshot
    if($cancelModal.process_id -eq $s.process_id -and $cancelModal.title -ceq '单元编辑器' -and $cancelModal.class_name -ceq '#32770'){
      $dialog=[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$cancelModal.hwnd)
      $controls=Dump $dialog 'cancel_confirmation'
      $text=@($controls|Where-Object {$_.id -eq '65535' -and $_.class -eq 'Static'})
      $discardText="放弃已更改的数据,  并关闭单元编辑器。可以吗?`n`n如果按 [OK],  则放弃更改,  关闭单元编辑器。`n如果按下 [取消],  则取消操作 (不关闭单元编辑器) 。"
      if($text.Count -ne 1 -or $text[0].name -cne $discardText){throw 'KV_NANO_UNIT_DISCARD_FINGERPRINT_REQUIRED'}
      $button=@($dialog.FindAll([Windows.Automation.TreeScope]::Descendants,[Windows.Automation.Condition]::TrueCondition)|Where-Object {$_.Current.ClassName -eq 'Button' -and $_.Current.AutomationId -eq '1' -and $_.Current.Name -ceq '确定'})
      if($button.Count -ne 1){throw 'KV_NANO_UNIT_DISCARD_BUTTON_REQUIRED'}
      $r=$button[0].Current.BoundingRectangle
      Invoke-KvGuardedMouseClickAllowProcessSuccessor -TargetHwnd ([IntPtr]$cancelModal.hwnd) -Step 'discard unsaved unit edits in owned copy' -X ([int]($r.X+$r.Width/2)) -Y ([int]($r.Y+$r.Height/2)) -SuccessProcessId $s.process_id -SleepMs 300
    }
    if((Get-KvForegroundSnapshot).hwnd -ne $s.hwnd){throw 'KV_NANO_UNIT_CANCEL_MAIN_REQUIRED'}
    $result.ok=$true;return
  }
  $controls=Dump $editor 'controls'
  $result.lists=@($controls|Where-Object {$_.class -eq 'SysListView32'}|ForEach-Object {[pscustomobject]@{id=$_.id;rows=[KvNanoUnitNative]::Rows([IntPtr]$_.hwnd,$s.process_id)}})
  & (Join-Path $scriptsRoot 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'desktop.png' 6>$null|Out-Null
  $result.ok=$true
}catch{
  $result.error_code=$_.Exception.Message
  try{& (Join-Path $scriptsRoot 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'failure.png' 6>$null|Out-Null}catch{}
  throw
}finally{$result|ConvertTo-Json -Depth 10|Set-Content (Join-Path $OutDir 'nano_unit_result.json') -Encoding UTF8}
