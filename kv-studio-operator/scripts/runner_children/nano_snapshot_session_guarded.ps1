param(
 [Parameter(Mandatory=$true)][string]$ProjectPath,
 [Parameter(Mandatory=$true)][string]$OutDir,
 [ValidateSet('Inventory','Close')][string]$Action='Inventory',
 [string]$KvsExe='',
 [string]$OwnershipPath=''
)
$ErrorActionPreference='Stop'
$scriptsRoot=Split-Path -Parent $PSScriptRoot
. (Join-Path $scriptsRoot 'kv_window_binding.ps1')
. (Join-Path $scriptsRoot 'kv_tree_resolver.ps1')
. (Join-Path $scriptsRoot 'guards/kv_ui_guard.ps1')
Add-Type -AssemblyName UIAutomationClient
Add-Type -AssemblyName UIAutomationTypes
New-Item -ItemType Directory -Force $OutDir|Out-Null
Initialize-KvUiGuard -OutDir $OutDir
$result=[ordered]@{ok=$false;action=$Action;project_path=[IO.Path]::GetFullPath($ProjectPath);session=$null;modules=@();tree=@()}
try {
 if($Action -eq 'Inventory'){
  if(Test-Path -LiteralPath $OwnershipPath){throw 'KV_NANO_SNAPSHOT_OWNERSHIP_ALREADY_EXISTS'}
  if(Get-KvProjectSession -ProjectPath $ProjectPath -AllowMissing){throw 'KV_NANO_SNAPSHOT_COPY_ALREADY_OPEN'}
  if(-not(Test-Path -LiteralPath $KvsExe -PathType Leaf)){throw 'KV_NANO_SNAPSHOT_EXE_REQUIRED'}
  # This is the interactive KV STUDIO editor explicitly requested by the caller.
  $p=Start-Process -FilePath $KvsExe -ArgumentList ('"'+$result.project_path+'"') -PassThru
  @{project_path=$result.project_path;process_id=$p.Id;process_start_utc=$p.StartTime.ToUniversalTime().ToString('o')}|ConvertTo-Json|Set-Content $OwnershipPath -Encoding UTF8
  $deadline=(Get-Date).AddSeconds(60)
  do{Start-Sleep -Milliseconds 300;$s=Get-KvProjectSession -ProjectPath $ProjectPath -AllowMissing}while(-not $s -and (Get-Date) -lt $deadline)
  if(-not $s -or $s.process_id -ne $p.Id){throw 'KV_NANO_SNAPSHOT_OWNED_SESSION_MISSING'}
 }else{
  $owner=Get-Content $OwnershipPath -Raw -Encoding UTF8|ConvertFrom-Json
  if([IO.Path]::GetFullPath($owner.project_path) -ine $result.project_path){throw 'KV_NANO_SNAPSHOT_OWNERSHIP_PATH_MISMATCH'}
  $p=Get-Process -Id $owner.process_id -ErrorAction SilentlyContinue
  if(-not $p){$result.ok=$true;$result.already_closed=$true;return}
  if($p.ProcessName -ine 'Kvs' -or $p.StartTime.ToUniversalTime().ToString('o') -ne $owner.process_start_utc){throw 'KV_NANO_SNAPSHOT_OWNERSHIP_IDENTITY_MISMATCH'}
  $s=Get-KvProjectSession -ProjectPath $ProjectPath
  if($s.process_id -ne $p.Id){throw 'KV_NANO_SNAPSHOT_CLOSE_SESSION_MISMATCH'}
 }
 $result.session=$s
 if($Action -eq 'Inventory' -and $s.cpu_model -ne 'KV-NC32'){throw 'KV_NANO_SNAPSHOT_CPU_NOT_VERIFIED'}
 if($Action -eq 'Close'){
  $dialogs=@([KvSharedUiGuardWin32]::VisibleTopLevelWindows($s.process_id)|ForEach-Object {[Windows.Automation.AutomationElement]::FromHandle([IntPtr]$_)}|Where-Object {$_.Current.ClassName -eq '#32770'})
  if($dialogs.Count){
   if($dialogs.Count -ne 1 -or $dialogs[0].Current.Name -ne '另存为'){throw 'KV_NANO_SNAPSHOT_UNKNOWN_CLOSE_DIALOG'}
   $d=$dialogs[0];$dialogHwnd=[IntPtr]$d.Current.NativeWindowHandle
   $prompt=$d.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'1436')))
   $cancel=$d.FindFirst([Windows.Automation.TreeScope]::Descendants,(New-Object Windows.Automation.PropertyCondition([Windows.Automation.AutomationElement]::AutomationIdProperty,'2')))
   if($prompt.Current.Name -ne '必须选择要保存的程序' -or $cancel.Current.Name -ne '取消'){throw 'KV_NANO_SNAPSHOT_SAVE_DIALOG_FINGERPRINT_MISMATCH'}
   Assert-KvUiForegroundHwnd -ExpectedHwnd $dialogHwnd -Step 'bind owned comment export cancellation dialog' -ExpectedTitleLike '另存为' -AllowSingleRecovery|Out-Null
   Invoke-KvGuardedSendKeysAllowTargetCloseToWindow -TargetHwnd $dialogHwnd -SuccessHwnd $s.hwnd -Step 'cancel fingerprinted incomplete comment export on owned copy' -Keys '{ESC}' -ExpectedTitleLike '另存为'
  }
  Assert-KvUiForegroundHwnd -ExpectedHwnd $s.hwnd -Step 'bind owned Nano snapshot editor for close' -ExpectedTitleLike 'KV STUDIO*' -AllowSingleRecovery|Out-Null
  # Match the verified Nano Save/Close route even when no dirty star is shown;
  # Ctrl+S also settles the active editor after a modal parameter window.
  Invoke-KvGuardedSendKeys -TargetHwnd $s.hwnd -Step 'save owned snapshot copy view state' -Keys '^s' -ExpectedTitleLike 'KV STUDIO*' -SleepMs 600
  if((Get-KvProjectSession -ProjectPath $ProjectPath).title -match ' \*\]$'){throw 'KV_NANO_SNAPSHOT_COPY_UNSAVED'}
  Invoke-KvGuardedSendKeysAllowTargetClose -TargetHwnd $s.hwnd -Step 'close only owned Nano snapshot process' -Keys '%{F4}' -ExpectedTitleLike 'KV STUDIO*' -SuccessTitleLike @('*') -SleepMs 500
  if(-not $p.WaitForExit(8000)){throw 'KV_NANO_SNAPSHOT_PROCESS_NOT_CLOSED'}
 }else{
  Assert-KvUiForegroundHwnd -ExpectedHwnd $s.hwnd -Step 'bind owned Nano snapshot editor for inventory' -ExpectedTitleLike 'KV STUDIO*' -AllowSingleRecovery|Out-Null
  $tree=Get-KvProjectTree -ProcessId $s.process_id
  $programRoot=Resolve-KvTreeNodeByPath -Tree $tree -Path @('^程序:')
  if(-not $programRoot){throw 'KV_NANO_SNAPSHOT_PROGRAM_ROOT_MISSING'}
  $result.program_root=$programRoot.Current.Name
  Expand-KvTreeNode $programRoot
  foreach($category in @(Get-KvTreeChildItems $programRoot)){
   Expand-KvTreeNode $category
   $children=@(Get-KvTreeChildItems $category)
   $result.tree+=@{category=$category.Current.Name;children=@($children|ForEach-Object {$_.Current.Name})}
   $index=0
   foreach($module in $children){
    $name=[string]$module.Current.Name
    if(-not $name -or $name -match '^\s*$'){throw 'KV_NANO_SNAPSHOT_EMPTY_MODULE_NAME'}
    $result.modules+=@{name=$name;category=$category.Current.Name;order=(++$index);tree_path=@($programRoot.Current.Name,$category.Current.Name,$name)}
   }
  }
  if(-not $result.modules.Count -or @($result.modules.name|Sort-Object -Unique).Count -ne $result.modules.Count){throw 'KV_NANO_SNAPSHOT_MODULE_INVENTORY_INVALID'}
  & (Join-Path $scriptsRoot 'Capture-KvFrame.ps1') -OutDir $OutDir -Name 'inventory.png' 6>$null|Out-Null
 }
 $result.ok=$true
}catch{$result.error_code=($_.Exception.Message -split ':')[0];$result.message=$_.Exception.Message}
finally{$result|ConvertTo-Json -Depth 12|Set-Content (Join-Path $OutDir 'nano_snapshot_session_result.json') -Encoding UTF8}
if(-not $result.ok){exit 1}
