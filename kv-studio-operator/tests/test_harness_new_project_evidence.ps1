param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'kv-interface-regression/run-workflow-test.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Harness parse failed'}
$definition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Test-KvsNewProjectEvidence'},$true)
. ([scriptblock]::Create($definition.Extent.Text))
New-Item -ItemType Directory -Force -Path $OutDir|Out-Null
$project=Join-Path ([IO.Path]::GetFullPath($OutDir)) 'created.kpr'
$resultPath=Join-Path ([IO.Path]::GetFullPath($OutDir)) 'create_project_result.json'
$started=[datetime]::UtcNow.AddMinutes(-1)
$processStart=$started.AddSeconds(1)
'test artifact, not a real PLC project'|Set-Content -LiteralPath $project -Encoding UTF8
$base=@{ok=$true;project_path=$project;cpu_model_actual='KV-X520';process_id=42;process_start_utc=$processStart.ToString('o')}
$after=@([pscustomobject]@{id=42;started_utc=$processStart;command_line='Kvs.exe'})
$results=@()
foreach($case in @('valid','stale_result','false_success','string_success','planned','wrong_path','missing_project','stale_project','wrong_cpu','bad_start','existing_process','old_process','missing_after','reused_pid')){
  $value=$base.Clone();$before=@();$currentAfter=$after
  'test artifact, not a real PLC project'|Set-Content -LiteralPath $project -Encoding UTF8
  switch($case){
    'false_success'{$value.ok=$false}
    'string_success'{$value.ok='true'}
    'planned'{$value.status='planned'}
    'wrong_path'{$value.project_path=Join-Path $OutDir 'other.kpr'}
    'missing_project'{Remove-Item -LiteralPath $project}
    'stale_project'{(Get-Item -LiteralPath $project).LastWriteTimeUtc=$started.AddSeconds(-1)}
    'wrong_cpu'{$value.cpu_model_actual='KV-X510'}
    'bad_start'{$value.process_start_utc='invalid'}
    'existing_process'{$before=$after}
    'old_process'{$value.process_start_utc=$started.AddSeconds(-1).ToString('o')}
    'missing_after'{$currentAfter=@()}
    'reused_pid'{$currentAfter=@([pscustomobject]@{id=42;started_utc=$processStart.AddSeconds(1)})}
  }
  $value|ConvertTo-Json|Set-Content -LiteralPath $resultPath -Encoding UTF8
  if($case -eq 'stale_result'){(Get-Item -LiteralPath $resultPath).LastWriteTimeUtc=$started.AddSeconds(-1)}
  $caught='';$candidate=$null
  try{$candidate=Test-KvsNewProjectEvidence $resultPath $project 'KV-X520' $started $before $currentAfter}catch{$caught=$_.Exception.Message}
  if($case -eq 'valid'){
    if($caught -or $candidate.id -ne 42 -or $candidate.project_path -ne $project){throw "Valid evidence rejected: $caught"}
  }elseif(-not $caught.StartsWith('KV_TEST_CREATE_')){throw "Unsafe create evidence accepted: $case $caught"}
  $results+=@{name=$case;ok=$true;rejection=$caught}
}
@{ok=$true;ui_started=$false;process_operations='none';tests=$results}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($results.Count) new project ownership/evidence checks."
