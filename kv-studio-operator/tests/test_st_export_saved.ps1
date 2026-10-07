param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$scripts=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
foreach($entry in @(
  @{path='workflow_tools/assert_kv_st_module_result.ps1';names=@('Assert-StTrue','Assert-StExportSaved')},
  @{path='runner_children/export_mnm_browse_default_folder_guarded.ps1';names=@('Save-KvExportProject')}
)){
  $tokens=$null;$errors=$null;$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $scripts $entry.path),[ref]$tokens,[ref]$errors)
  if($errors.Count){throw 'Script parse failed'}
  foreach($name in $entry.names){$fn=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq $name},$true);. ([scriptblock]::Create($fn.Extent.Text))}
}
$rows=@()
foreach($case in @('saved','dirty_title','wrong_project','false_flag','missing_flag','string_flag','missing_title')){
  $result=[pscustomobject]@{project_saved=$true;final_title='KV STUDIO Ver.12 - [SavedProject]'}
  switch($case){
    'dirty_title' {$result.final_title='KV STUDIO Ver.12 - [SavedProject *]'}
    'wrong_project' {$result.final_title='KV STUDIO Ver.12 - [Other]'}
    'false_flag' {$result.project_saved=$false}
    'missing_flag' {$result.PSObject.Properties.Remove('project_saved')}
    'string_flag' {$result.project_saved='true'}
    'missing_title' {$result.PSObject.Properties.Remove('final_title')}
  }
  $failure='';try{Assert-StExportSaved $result (Join-Path $OutDir 'SavedProject.kpr')}catch{$failure=$_.Exception.Message}
  if(([string]::IsNullOrEmpty($failure)) -ne ($case -eq 'saved')){throw "Unexpected save evidence case: $case $failure"}
  $rows+=@{case=$case;ok=$true;observed_error=$failure}
}
function Get-Process {param([int]$Id,$ErrorAction);return [pscustomobject]@{MainWindowHandle=$script:TestHwnd}}
function Get-WindowTitle {param([IntPtr]$Hwnd);return $script:TestTitle}
function Invoke-KvGuardedSendKeys {param($TargetHwnd,$Step,$Keys,$ExpectedTitleLike,$Action,$SleepMs);if($Keys -cne '^s'){throw 'Unexpected save route'};$script:SaveCount++;$script:TestTitle=$script:TestTitle.Replace(' *]',']')}
function Log {param($Message)}
foreach($case in @('already_clean','save_dirty','reject_wrong_title','reject_wrong_hwnd')){
  $script:TestHwnd=[IntPtr]123;$script:TestTitle='KV STUDIO Ver.12 - [SavedProject]';$script:SaveCount=0
  $script:ProjectSaved=$false;$script:ProjectSaveChecks=@();$script:FinalProjectTitle=''
  if($case -eq 'save_dirty'){$script:TestTitle='KV STUDIO Ver.12 - [SavedProject *]'}
  if($case -eq 'reject_wrong_title'){$script:TestTitle='KV STUDIO Ver.12 - [Other *]'}
  if($case -eq 'reject_wrong_hwnd'){$script:TestHwnd=[IntPtr]456}
  $failure='';try{Save-KvExportProject -ProcessId 777 -Hwnd ([IntPtr]123) -ProjectName SavedProject -Stage test}catch{$failure=$_.Exception.Message}
  $pass=$case -notlike 'reject_*'
  if(([string]::IsNullOrEmpty($failure)) -ne $pass){throw "Unexpected save route case: $case $failure"}
  $expectedCount=if($case -eq 'save_dirty'){1}else{0}
  if($script:SaveCount -ne $expectedCount -or ($pass -and (-not $script:ProjectSaved -or $script:FinalProjectTitle -match '\*'))){throw "Save route evidence mismatch: $case"}
  $rows+=@{case=$case;ok=$true;observed_error=$failure;ctrl_s_count=$script:SaveCount}
}
$null=New-Item -ItemType Directory -Force -Path $OutDir
@{ok=$true;ui_started=$false;tests=$rows}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($rows.Count) final-save evidence cases"
