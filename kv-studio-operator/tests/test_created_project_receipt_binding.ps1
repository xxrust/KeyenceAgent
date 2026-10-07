param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$OutDir=[IO.Path]::GetFullPath($OutDir)
$null=New-Item -ItemType Directory -Force -Path $OutDir
$scripts=Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'
$project=Join-Path $OutDir 'QA_Name.kpr'
$ProjectPath=$project
$expectedProjectNeedle='QA_Name'
$projectNeedle=$expectedProjectNeedle
$startedAt=[datetime]::Parse('2026-09-20T10:00:00.0000000Z').ToUniversalTime()
$executable=Join-Path $OutDir 'Kvs.exe'
$CreatedProjectResultPath=Join-Path $OutDir 'fixture_creation.json'
function Get-Process { param([int]$Id,$ErrorAction);if($Id -ne 777){throw 'TEST_PROCESS_NOT_FOUND'};return $script:mockProcess }
function LogContract { param($Name,$Data) }
$results=@()
foreach($route in @('import','export')){
  $file=if($route -eq 'import'){'import_mnm_guarded.ps1'}else{'export_mnm_browse_default_folder_guarded.ps1'}
  $tokens=$null;$parseErrors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $scripts ('runner_children/'+$file)),[ref]$tokens,[ref]$parseErrors)
  if($parseErrors.Count){throw ('Runner parse failed: '+$file)}
  $block=$ast.Find({param($n)$n -is [Management.Automation.Language.IfStatementAst] -and $n.Clauses[0].Item1.Extent.Text -eq '$CreatedProjectResultPath'},$true)
  if(-not $block){throw 'Receipt binding branch missing'}
  $patternName=if($route -eq 'import'){'expectedProjectTitlePattern'}else{'projectTitlePattern'}
  $patternAssignment=$ast.Find({param($n)$n -is [Management.Automation.Language.AssignmentStatementAst] -and $n.Left.Extent.Text -eq ('$'+$patternName)},$true)
  if(-not $patternAssignment){throw 'Exact title predicate missing'}
  . ([scriptblock]::Create($patternAssignment.Extent.Text))
  foreach($case in @('valid','unsaved','name_suffix','name_prefix','wrong_bracket','string_ok','wrong_project','wrong_requested_path','wrong_pid','reused_pid_start','wrong_executable','wrong_process_name','no_hwnd','ambiguous')){
    $creationFixture=[ordered]@{ok=$true;project_path=$project;requested_project_path=$project;process_id=777;process_start_utc=$startedAt.ToString('o');kvs_exe=$executable}
    $script:mockProcess=[pscustomobject]@{Id=777;ProcessName='Kvs';StartTime=$startedAt;MainWindowHandle=[IntPtr]1234;MainWindowTitle='KV STUDIO - [Editor: KV-X520] - [QA_Name]';Path=$executable}
    $boundProcesses=@();$bound=@()
    switch($case){
      'unsaved' {$script:mockProcess.MainWindowTitle='KV STUDIO - [Editor: KV-X520] - [QA_Name *]'}
      'name_suffix' {$script:mockProcess.MainWindowTitle='KV STUDIO - [Editor: KV-X520] - [QA_NameOther]'}
      'name_prefix' {$script:mockProcess.MainWindowTitle='KV STUDIO - [Editor: KV-X520] - [OtherQA_Name]'}
      'wrong_bracket' {$script:mockProcess.MainWindowTitle='KV STUDIO - [QA_Name] - [Other]'}
      'string_ok' {$creationFixture.ok='true'}
      'wrong_project' {$creationFixture.project_path=Join-Path $OutDir 'Other.kpr'}
      'wrong_requested_path' {$creationFixture.requested_project_path=Join-Path $OutDir 'Other.kpr'}
      'wrong_pid' {$creationFixture.process_id=888}
      'reused_pid_start' {$script:mockProcess.StartTime=$startedAt.AddSeconds(1)}
      'wrong_executable' {$script:mockProcess.Path=Join-Path $OutDir 'OtherKvs.exe'}
      'wrong_process_name' {$script:mockProcess.ProcessName='Other'}
      'no_hwnd' {$script:mockProcess.MainWindowHandle=[IntPtr]::Zero}
      'ambiguous' {$boundProcesses=@([pscustomobject]@{Id=888});$bound=$boundProcesses}
    }
    $creationFixture|ConvertTo-Json|Set-Content -LiteralPath $CreatedProjectResultPath -Encoding UTF8
    $failure=''
    try{. ([scriptblock]::Create($block.Extent.Text))}catch{$failure=$_.Exception.Message}
    $expectedPass=$case -in @('valid','unsaved')
    if(([string]::IsNullOrEmpty($failure)) -ne $expectedPass){throw ("Unexpected $route receipt result: $case, failure=$failure")}
    $results+=@{route=$route;case=$case;ok=$true;observed_error=$failure}
  }
}
@{ok=$true;ui_started=$false;scope='actual receipt branches executed with process snapshots and no UI';tests=$results}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($results.Count) creation receipt identity cases"
