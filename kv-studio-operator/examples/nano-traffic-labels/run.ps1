param(
  [string]$OutRoot='',
  [string]$SourceProjectPath='',
  [string]$ExpectedLabelsPath='',
  [string]$KvsExe='',
  [switch]$PlanOnly
)
$ErrorActionPreference='Stop'
if(-not $OutRoot){$OutRoot=Join-Path $env:TEMP ('nano-batch-plan-'+(Get-Date -Format 'yyyyMMdd_HHmmss'))}
$OutRoot=[IO.Path]::GetFullPath($OutRoot)
if(Test-Path -LiteralPath $OutRoot){throw 'KV_TEST_OUTPUT_MUST_BE_NEW'}
New-Item -ItemType Directory -Path $OutRoot|Out-Null
$scriptsRoot=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../scripts'))
$inputs=Join-Path $OutRoot 'inputs'
New-Item -ItemType Directory -Path $inputs|Out-Null
foreach($name in @('labels.tsv','phase.txt','area.txt','ladder.txt')){Copy-Item (Join-Path $PSScriptRoot $name) (Join-Path $inputs $name)}
[IO.File]::WriteAllText((Join-Path $inputs 'empty.tsv'),'')
$rungs=@([IO.File]::ReadAllText((Join-Path $inputs 'ladder.txt')) -split '(?m)(?=^LDB? )'|Where-Object {$_})
for($i=0;$i -lt $rungs.Count;$i++){[IO.File]::WriteAllText((Join-Path $inputs ('rung_'+($i+1)+'.txt')),$rungs[$i],[Text.UTF8Encoding]::new($false))}
$checklist=Join-Path $inputs 'CHECKLIST.md'
@'
# Checklist
## KV STUDIO
- Nano only; offline copy or new blank project; exact process identity.
- CR and CM are excluded from labels and all comment writes.
## Steps
- Freeze TSV and all script/ladder sources before desktop input.
- Paste all labels once; compile, reopen and compare every planned source.
- Close only the process owned by this run, including failures.
'@|Set-Content $checklist -Encoding UTF8
$receipt='';$owned=$null;$success=$false;$errorText='';$closeOk=$false
$projectRoot=Join-Path $OutRoot 'projects'
$project=Join-Path $projectRoot 'NanoTrafficNamed/NanoTrafficNamed.kpr'
$sourceHashes=@()
try {
  if($SourceProjectPath){
    if($PlanOnly){throw 'KV_TEST_COPY_PLAN_REQUIRES_EXISTING_PREPARED_PROJECT'}
    $SourceProjectPath=[IO.Path]::GetFullPath($SourceProjectPath)
    $sourceDir=Split-Path -Parent $SourceProjectPath
    $copyDir=Join-Path $projectRoot (Split-Path -Leaf $sourceDir)
    New-Item -ItemType Directory -Path $projectRoot|Out-Null
    $sourceHashes=@(Get-ChildItem $sourceDir -File -Recurse|ForEach-Object {@{path=$_.FullName;sha256=(Get-FileHash $_.FullName).Hash}})
    Copy-Item -LiteralPath $sourceDir -Destination $copyDir -Recurse
    $project=Join-Path $copyDir (Split-Path -Leaf $SourceProjectPath)
    $project=[IO.Path]::GetFullPath($project)
    if(-not $ExpectedLabelsPath -or -not(Test-Path -LiteralPath $ExpectedLabelsPath -PathType Leaf)){throw 'KV_TEST_COPY_EXPECTED_LABELS_REQUIRED'}
    Copy-Item -LiteralPath $ExpectedLabelsPath -Destination (Join-Path $inputs 'expected_labels.tsv') -Force
    if(-not $KvsExe){$install=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scriptsRoot 'get_kvstudio_install.ps1') -Probe|ConvertFrom-Json;$KvsExe=$install.KvsExe}
    $owned=Start-Process -FilePath $KvsExe -ArgumentList ('"'+$project+'"') -PassThru
    $ownedStart=$owned.StartTime.ToUniversalTime()
    # The source is the verified named example; old and new code are identical.
    $edits=@(@{action='UpdateScript';row=1;source='phase.txt';expected='phase.txt'},@{action='UpdateAreaScript';row=2;source='area.txt';expected='area.txt'})
    # The caller supplies a reviewed old table; do not manufacture its expected
    # value by reading the same editor that will later be checked against it.
    $firstRung=4
  }else{
    $create=@{ProjectName='NanoTrafficNamed';ProjectRoot=$projectRoot;CpuModel='KV-NC32';OutDir=(Join-Path $OutRoot 'create');ChecklistPath=$checklist;PlanOnly=$PlanOnly}
    if($KvsExe){$create.KvsExe=$KvsExe}
    & (Join-Path $scriptsRoot 'workflows/create_kv_project.ps1') @create
    if($PlanOnly){$success=$true;return}
    $receipt=Join-Path $create.OutDir 'artifacts/create/create_project_result.json'
    $created=Get-Content $receipt -Raw -Encoding UTF8|ConvertFrom-Json
    $owned=Get-Process -Id $created.process_id
    $ownedStart=$owned.StartTime.ToUniversalTime()
    $edits=@(@{action='CreateScript';row=1;source='phase.txt'},@{action='InsertLadder';row=2;source='ladder.txt'},@{action='CreateAreaScript';row=2;source='area.txt'})
    Copy-Item (Join-Path $inputs 'empty.tsv') (Join-Path $inputs 'expected_labels.tsv')
    $firstRung=4
  }
  $contract=@{schema_version=1;program='Main';labels=@{source='labels.tsv';expected='expected_labels.tsv'};edits=$edits;ladder=@(for($i=0;$i -lt 7;$i++){@{row=$firstRung+$i;source=('rung_'+($i+1)+'.txt')}})}
  $contractPath=Join-Path $inputs 'program.json'
  $contract|ConvertTo-Json -Depth 8|Set-Content $contractPath -Encoding UTF8
  $invoke=@{ProjectPath=$project;ContractPath=$contractPath;OutDir=(Join-Path $OutRoot 'apply');ChecklistPath=$checklist;CreatedProjectResultPath=$receipt;TimeoutSeconds=600}
  & (Join-Path $scriptsRoot 'workflows/apply_kv_nano_program_plan.ps1') @invoke
  $result=Get-Content (Join-Path $invoke.OutDir 'workflow_result.json') -Raw -Encoding UTF8|ConvertFrom-Json
  if(-not $result.ok){throw 'KV_TEST_PLAN_FAILED'}
  $success=$true;$closeOk=$true
}catch{$errorText=$_.Exception.Message;Write-Host $errorText}finally{
  if(-not $closeOk -and $owned){
    try{
      $cleanupParams=@{ProjectPath=$project;OutDir=(Join-Path $OutRoot 'cleanup');Action='Close'}
      # Reopen invalidates the initial creation receipt. Only use it while the
      # original created process is still alive and has no project argument.
      $original=Get-Process -Id $owned.Id -ErrorAction SilentlyContinue
      if($receipt -and $original -and $original.StartTime.ToUniversalTime() -eq $ownedStart){$cleanupParams.CreatedProjectResultPath=$receipt}
      & (Join-Path $scriptsRoot 'workflows/manage_kv_nano_program.ps1') @cleanupParams
      $closeOk=$true
    }catch{}
  }
  if($owned){
    $current=Get-Process -Id $owned.Id -ErrorAction SilentlyContinue
    if($current -and $current.ProcessName -eq 'Kvs' -and $current.StartTime.ToUniversalTime() -eq $ownedStart){$current.Kill();$null=$current.WaitForExit(8000);$success=$false}
  }
  # Reopen may have created a successor PID. Identity records are emitted by
  # the runner, and only those exact fresh processes belong to this harness.
  foreach($file in @(Get-ChildItem -LiteralPath $OutRoot -Recurse -Filter launched_process.json -File)){
    $record=Get-Content $file.FullName -Raw -Encoding UTF8|ConvertFrom-Json
    $process=Get-Process -Id $record.process_id -ErrorAction SilentlyContinue
    if($process -and $process.ProcessName -eq 'Kvs' -and $process.StartTime.ToUniversalTime().ToString('o') -eq $record.process_start_utc){$process.Kill();$null=$process.WaitForExit(8000);$success=$false}
  }
  foreach($item in $sourceHashes){if((Get-FileHash $item.path).Hash -ne $item.sha256){$success=$false;$errorText+=' SOURCE_CHANGED'}}
  @{ok=$success;planned=[bool]$PlanOnly;error=$errorText;project_path=$project;workflow_result=(Join-Path $OutRoot 'apply/workflow_result.json');closed=$closeOk;hardware_run_verified=$false}|ConvertTo-Json -Depth 5|Set-Content (Join-Path $OutRoot 'test_result.json') -Encoding UTF8
}
if(-not $success){exit 41}
