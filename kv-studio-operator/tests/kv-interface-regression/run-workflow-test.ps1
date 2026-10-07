param(
  [Parameter(Mandatory=$true)][string]$ScenarioPath,
  [string]$OutRoot = '',
  [switch]$PlanOnly,
  [switch]$KeepProjectOpen
)
$ErrorActionPreference = 'Stop'
$scenarioRunnerDir = Split-Path -Parent $PSCommandPath
$testRoot = Split-Path -Parent $scenarioRunnerDir
$skillRoot = Split-Path -Parent $testRoot
$scriptsRoot=Join-Path $skillRoot 'scripts'
. (Join-Path $scriptsRoot 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $scriptsRoot 'workflow_tools/kv_step_evidence.ps1')
. (Join-Path $scriptsRoot 'workflow_tools/kv_plan_preflight.ps1')
. (Join-Path $scenarioRunnerDir 'compile-error-assertions.ps1')
$scenarioPath = [IO.Path]::GetFullPath($ScenarioPath)
$scenario = Get-Content -Raw -LiteralPath $scenarioPath -Encoding UTF8 | ConvertFrom-Json
if (-not $scenario.name -or -not $scenario.workflow) { throw 'Scenario requires name and workflow.' }
$projectMode=if($scenario.project_mode){[string]$scenario.project_mode}else{'sample_copy'}
if($projectMode -notin @('sample_copy','fixture_copy','new_project')){throw 'KV_TEST_PROJECT_MODE_INVALID'}
if($projectMode -eq 'new_project' -and ($scenario.open_project -ne $false -or -not $scenario.project_name -or [string]$scenario.project_name -notmatch '^[A-Za-z][A-Za-z0-9_]{0,47}$' -or -not $scenario.cpu_model -or $scenario.workflow -ne 'scripts/workflows/create_kv_project.ps1')){throw 'KV_TEST_NEW_PROJECT_CONTRACT_INVALID'}
$expectedOutcome=if($scenario.expected_outcome){[string]$scenario.expected_outcome}else{'success'}
if($expectedOutcome -notin @('success','compile_error')){throw 'KV_TEST_EXPECTED_OUTCOME_INVALID'}
$expectedTextPath='';$expectedTextHash=''
if($expectedOutcome -eq 'compile_error'){
  if($projectMode -ne 'fixture_copy' -or $scenario.workflow -ne 'scripts/workflows/compile_kv_project.ps1' -or -not $scenario.expected_compile_result -or [IO.Path]::IsPathRooted([string]$scenario.expected_compile_result)){throw 'KV_TEST_NG_SCENARIO_INVALID'}
  $expectedTextPath=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $scenarioPath) ([string]$scenario.expected_compile_result)))
  if(-not(Test-KvPathWithin $expectedTextPath (Join-Path (Split-Path -Parent $scenarioPath) 'fixtures')) -or -not(Test-Path -LiteralPath $expectedTextPath -PathType Leaf)){throw 'KV_TEST_NG_EXPECTATION_MISSING'}
  $expectedTextHash=(Get-FileHash -LiteralPath $expectedTextPath -Algorithm SHA256).Hash
  $expectedText=[IO.File]::ReadAllText($expectedTextPath,[Text.Encoding]::UTF8)
  $null=Assert-KvCompileDiagnosticText $expectedText $expectedText
}
function Expand-TestValue([string]$Value, [string]$ProjectPath, [string]$ProjectDirectory, [string]$RunDirectory, [string]$FixtureDirectory) {
  $result = [string]$Value
  return $result.Replace('${skill_root}', $skillRoot).Replace('${project}', $ProjectPath).Replace('${project_dir}', $ProjectDirectory).Replace('${project_root}', (Split-Path -Parent $ProjectDirectory)).Replace('${out}', $RunDirectory).Replace('${fixture_dir}', $FixtureDirectory)
}
function Get-ConfiguredKvsExe {
  $loader = Join-Path $skillRoot 'scripts\Import-KvStudioOperatorConfig.ps1'
  $cfg = & $loader -ScriptRoot (Join-Path $skillRoot 'scripts')
  if ($cfg -and $cfg.kvs_exe) { return [IO.Path]::GetFullPath([string]$cfg.kvs_exe) }
  throw 'KV_TEST_KVS_EXE_NOT_CONFIGURED'
}
function Wait-KvsProcess([string]$ProjectNeedle, [int]$StartedProcessId, [int]$Seconds = 40, [datetime]$ExpectedStartTimeUtc = [datetime]::MinValue) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $started = Get-Process -Id $StartedProcessId -ErrorAction SilentlyContinue
    if (-not $started) { throw "KV_TEST_PROJECT_PROCESS_EXITED: $ProjectNeedle pid=$StartedProcessId" }
    if ($started.ProcessName -ne 'Kvs' -or ($ExpectedStartTimeUtc -ne [datetime]::MinValue -and $started.StartTime.ToUniversalTime() -ne $ExpectedStartTimeUtc)) { throw "KV_TEST_PROJECT_PROCESS_IDENTITY_CHANGED: pid=$StartedProcessId" }
    if ($started.MainWindowHandle -ne 0 -and $started.MainWindowTitle -like 'KV STUDIO*' -and $started.MainWindowTitle -like "*$ProjectNeedle*") { return $started }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  throw "KV_TEST_PROJECT_WINDOW_TIMEOUT: $ProjectNeedle pid=$StartedProcessId"
}
function Stop-OwnedKvsTestProcess([object]$StartedProcess,[datetime]$ExpectedStartTimeUtc) {
  $current=Get-Process -Id $StartedProcess.Id -ErrorAction SilentlyContinue
  if (-not $current) { return 'already_exited' }
  if ($current.ProcessName -ne 'Kvs' -or $current.StartTime.ToUniversalTime() -ne $ExpectedStartTimeUtc) { throw 'KV_TEST_CLEANUP_PROCESS_IDENTITY_CHANGED' }
  $StartedProcess.Kill()
  return 'stopped_owned_process'
}
function Get-KvsTestProcessSnapshot {
  foreach($record in @(Get-CimInstance Win32_Process -Filter "Name='Kvs.exe'" -ErrorAction Stop)){
    $process=Get-Process -Id ([int]$record.ProcessId) -ErrorAction SilentlyContinue
    if(-not $process){continue}
    try{$startedUtc=$process.StartTime.ToUniversalTime()}catch{continue}
    [pscustomobject]@{id=$process.Id;started_utc=$startedUtc;command_line=[string]$record.CommandLine}
  }
}
function Get-KvsTestCleanupCandidates([object[]]$Before,[object[]]$After,[string[]]$ProjectPaths){
  $existing=@{}
  foreach($record in @($Before)){$existing[([string]$record.id+'|'+$record.started_utc.ToString('o'))]=$true}
  foreach($record in @($After)){
    if($existing.ContainsKey(([string]$record.id+'|'+$record.started_utc.ToString('o')))){continue}
    foreach($path in @($ProjectPaths)){
      $pattern='(?:^|\s)(?:"'+[regex]::Escape($path)+'"|'+[regex]::Escape($path)+')(?=\s|$)'
      if($record.command_line -and $record.command_line -match $pattern){
        [pscustomobject]@{id=$record.id;started_utc=$record.started_utc;project_path=$path}
        break
      }
    }
  }
}
function Get-KvsTestCleanupProjectPaths([string]$RunDirectory,[string]$OriginalProjectPath){
  $paths=@($OriginalProjectPath)
  foreach($file in @(Get-ChildItem -LiteralPath $RunDirectory -Recurse -File -Filter 'execution_plan.json')){
    if($file.FullName -match '[/\\]_history[/\\]'){continue}
    $p=Get-Content -Raw -Encoding UTF8 -LiteralPath $file.FullName|ConvertFrom-Json
    $candidates=@([string]$p.project_path)
    foreach($step in @($p.steps)){
      if($step.parameters){$candidates+=@([string]$step.parameters.ProjectPath,[string]$step.parameters.SourceProjectPath)}
      $args=@($step.arguments)
      for($i=0;$i -lt $args.Count-1;$i++){if([string]$args[$i] -in @('-ProjectPath','-SourceProjectPath')){$candidates+=[string]$args[$i+1]}}
    }
    foreach($path in @($candidates|Where-Object{$_})){
      $full=[IO.Path]::GetFullPath($path)
      if([IO.Path]::GetExtension($full) -eq '.kpr' -and (Test-KvPathWithin $full $RunDirectory)){$paths+=$full}
    }
  }
  return @($paths|Select-Object -Unique)
}
function Test-KvsNewProjectEvidence([string]$ResultPath,[string]$ProjectPath,[string]$CpuModel,[datetime]$StartedUtc,[object[]]$Before,[object[]]$After){
  if(-not (Test-Path -LiteralPath $ResultPath -PathType Leaf) -or (Get-Item -LiteralPath $ResultPath).LastWriteTimeUtc -lt $StartedUtc){throw 'KV_TEST_CREATE_EVIDENCE_MISSING_OR_STALE'}
  $created=Get-Content -Raw -LiteralPath $ResultPath -Encoding UTF8|ConvertFrom-Json
  if($created.ok -isnot [bool] -or -not $created.ok -or $created.status -eq 'planned' -or $created.planned -eq $true){throw 'KV_TEST_CREATE_EVIDENCE_FAILED'}
  if(-not $created.project_path -or [IO.Path]::GetFullPath([string]$created.project_path) -ne [IO.Path]::GetFullPath($ProjectPath) -or -not (Test-Path -LiteralPath $ProjectPath -PathType Leaf) -or (Get-Item -LiteralPath $ProjectPath).LastWriteTimeUtc -lt $StartedUtc){throw 'KV_TEST_CREATE_PROJECT_PATH_MISMATCH'}
  if([string]$created.cpu_model_actual -ne $CpuModel){throw 'KV_TEST_CREATE_CPU_MISMATCH'}
  $createdStart=[datetime]::MinValue
  if(-not $created.process_id -or -not [datetime]::TryParse([string]$created.process_start_utc,[ref]$createdStart)){throw 'KV_TEST_CREATE_PROCESS_EVIDENCE_INVALID'}
  $createdStart=$createdStart.ToUniversalTime()
  if($createdStart -lt $StartedUtc -or @($Before|Where-Object {$_.id -eq [int]$created.process_id -and $_.started_utc -eq $createdStart}).Count -ne 0){throw 'KV_TEST_CREATE_PROCESS_NOT_NEW'}
  $matches=@($After|Where-Object {$_.id -eq [int]$created.process_id -and $_.started_utc -eq $createdStart})
  if($matches.Count -ne 1){throw 'KV_TEST_CREATE_PROCESS_IDENTITY_MISMATCH'}
  return [pscustomobject]@{id=[int]$created.process_id;started_utc=$createdStart;project_path=$ProjectPath;cpu_model_actual=[string]$created.cpu_model_actual;evidence_path=$ResultPath}
}
function Expand-Arguments([object[]]$Values, [string]$ProjectPath, [string]$ProjectDirectory, [string]$RunDirectory, [string]$FixtureDirectory) {
  $out = [System.Collections.Generic.List[string]]::new()
  foreach ($value in @($Values)) {
    if ($value -is [array]) {
      foreach ($nested in @($value)) { $out.Add((Expand-TestValue ([string]$nested) $ProjectPath $ProjectDirectory $RunDirectory $FixtureDirectory)) }
    } else { $out.Add((Expand-TestValue ([string]$value) $ProjectPath $ProjectDirectory $RunDirectory $FixtureDirectory)) }
  }
  return $out.ToArray()
}
if (-not $OutRoot) { $OutRoot = Join-Path $scenarioRunnerDir 'runs' }
$runDirectory = Join-Path ([IO.Path]::GetFullPath($OutRoot)) (($scenario.name -replace '[^A-Za-z0-9_.-]','_') + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff') + '_' + [guid]::NewGuid().ToString('N').Substring(0,8))
if($projectMode -in @('sample_copy','fixture_copy')){
  if($projectMode -eq 'fixture_copy'){
    $fixtureRoot=Join-Path (Split-Path -Parent $scenarioPath) 'fixtures'
    if(-not $scenario.source_project -or [IO.Path]::IsPathRooted([string]$scenario.source_project)){throw 'KV_TEST_FIXTURE_PROJECT_INVALID'}
    $sourceProjectPath=[IO.Path]::GetFullPath((Join-Path (Split-Path -Parent $scenarioPath) ([string]$scenario.source_project)))
    if(-not (Test-KvPathWithin $sourceProjectPath $fixtureRoot) -or [IO.Path]::GetExtension($sourceProjectPath) -ine '.kpr' -or -not(Test-Path -LiteralPath $sourceProjectPath -PathType Leaf)){throw 'KV_TEST_FIXTURE_PROJECT_INVALID'}
  }else{
  $sampleProjects = @(Get-ChildItem -LiteralPath (Join-Path $skillRoot 'references') -Recurse -Filter '*.kpr' -File | Where-Object { $_.BaseName -like '*v100*' })
  if ($sampleProjects.Count -ne 1) { throw "Expected one KVX sample .kpr under references, found $($sampleProjects.Count)" }
  $sourceProjectPath = $sampleProjects[0].FullName
  }
  $sourceProjectDirectory = Split-Path -Parent $sourceProjectPath
  $projectDirectory = Join-Path $runDirectory (Join-Path 'project' (Split-Path -Leaf $sourceProjectDirectory))
  $projectPath = Join-Path $projectDirectory (Split-Path -Leaf $sourceProjectPath)
}else{
  $projectDirectory=Join-Path $runDirectory (Join-Path 'project' ([string]$scenario.project_name))
  $projectPath=Join-Path $projectDirectory ([string]$scenario.project_name+'.kpr')
}
$fixtureDirectory = Join-Path (Split-Path -Parent $scenarioPath) 'fixtures'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $projectDirectory) | Out-Null
$fixtureInputs=@()
if($projectMode -eq 'fixture_copy'){
  $fixtureInputs=@(Get-ChildItem -LiteralPath $sourceProjectDirectory -Recurse -File|ForEach-Object {@{path=$_.FullName;sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}})
  $fixtureInputs|ConvertTo-Json -Depth 4|Set-Content -LiteralPath (Join-Path $runDirectory 'fixture_fingerprints.json') -Encoding UTF8
}
if($projectMode -in @('sample_copy','fixture_copy')){Copy-Item -LiteralPath $sourceProjectDirectory -Destination (Split-Path -Parent $projectDirectory) -Recurse -Force}
$workflowPath = Join-Path $skillRoot ([string]$scenario.workflow)
if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) { throw "Workflow missing: $workflowPath" }
$arguments = Expand-Arguments @($scenario.arguments) $projectPath $projectDirectory $runDirectory $fixtureDirectory
if ($PlanOnly -and $arguments -notcontains '-PlanOnly') { $arguments += '-PlanOnly' }
$invokeArguments = @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',$workflowPath) + @($arguments)
$stdoutPath = Join-Path $runDirectory 'workflow_stdout.txt'
$stderrPath = Join-Path $runDirectory 'workflow_stderr.txt'
$startedProcess = $null; $workflowExit = 1; $workflowError = ''
$startedProcessTimeUtc=[datetime]::MinValue; $boundProcess=$null; $boundHwnd=0L; $boundTitle=''; $cleanupStatus='not_started'
$workflowProcessesBefore=@();$workflowProcessesAfter=@();$workspaceCleanup=@()
$planningOk=$false; $planningExit=1; $planningInputs=@(); $workflowStartedUtc=$null
$createdProjectEvidence=$null
$expectedFailureEvidence=$null
try {
  $planningArguments=@($arguments)
  if ($planningArguments -notcontains '-PlanOnly') { $planningArguments+='-PlanOnly' }
  $planningStartedUtc=(Get-Date).ToUniversalTime()
  & powershell -STA -NoProfile -ExecutionPolicy Bypass -File $workflowPath @planningArguments *> (Join-Path $runDirectory 'planning_stdout.txt')
  $planningExit=if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 1 }
  if ($planningExit -ne 0) { throw "KV_TEST_PLANNING_FAILED: exit_code=$planningExit" }
  $planFiles=@(Get-ChildItem -LiteralPath $runDirectory -Recurse -File -Filter 'execution_plan.json')
  foreach ($planFile in $planFiles) {
    if ($planFile.LastWriteTimeUtc -lt $planningStartedUtc) { throw 'KV_TEST_PLANNING_EVIDENCE_STALE' }
    $executionPlan=Get-Content -Raw -Encoding UTF8 -LiteralPath $planFile.FullName | ConvertFrom-Json
    if($projectMode -eq 'new_project'){
      $createSteps=@($executionPlan.steps|Where-Object {$_.script_name -eq 'runner_children/create_project_local_guarded.ps1'})
      if($executionPlan.project_path -ne $projectPath -or $createSteps.Count -ne 1 -or $createSteps[0].parameters.ProjectName -ne $scenario.project_name -or $createSteps[0].parameters.CpuModel -ne $scenario.cpu_model -or $createSteps[0].parameters.ProjectRoot -ne (Split-Path -Parent $projectDirectory)){throw 'KV_TEST_NEW_PROJECT_PLAN_MISMATCH'}
    }
    $preflight=Test-KvExecutionPlanPreflight -Plan $executionPlan -ScriptsRoot $scriptsRoot
    $planningInputs+=@($preflight.inputs)
  }
  if ($planFiles.Count -eq 0) {
    # The semantic snapshot planner writes requests and an explicit planned
    # manifest rather than a single flat execution plan.
    $plannedResultPath=Join-Path $runDirectory ([string]$scenario.result_file)
    if (-not (Test-Path -LiteralPath $plannedResultPath -PathType Leaf)) { throw 'KV_TEST_PLANNING_EVIDENCE_MISSING' }
    $plannedResult=Get-Content -Raw -Encoding UTF8 -LiteralPath $plannedResultPath | ConvertFrom-Json
    if ((Get-Item -LiteralPath $plannedResultPath).LastWriteTimeUtc -lt $planningStartedUtc -or $plannedResult.ok -isnot [bool] -or -not $plannedResult.ok -or $plannedResult.planned -isnot [bool] -or -not $plannedResult.planned -or $plannedResult.status -ne 'planned') { throw 'KV_TEST_PLANNING_EVIDENCE_INVALID' }
  }
  foreach ($gate in @('ui_guard_usage','agent_boundary')) {
    $gateOut=Join-Path $runDirectory (Join-Path 'planning_gates' $gate)
    New-Item -ItemType Directory -Force -Path $gateOut | Out-Null
    $gateScript=Join-Path $scriptsRoot "gates/assert_kv_mvp_$gate.ps1"
    $gateStartedUtc=(Get-Date).ToUniversalTime()
    & powershell -STA -NoProfile -ExecutionPolicy Bypass -File $gateScript -ScriptsRoot $scriptsRoot -OutDir $gateOut *> (Join-Path $gateOut 'stdout.txt')
    if ($LASTEXITCODE -ne 0) { throw "KV_TEST_STATIC_GATE_FAILED: $gate" }
    $gateContract=Get-KvStepContract (Get-KvStudioOperatorScriptManifest -ScriptRoot $scriptsRoot) "gates/assert_kv_mvp_$gate.ps1" @()
    $null=Test-KvStepEvidence $gateOut $gateContract $gateStartedUtc
  }
  $planningOk=$true
  Assert-KvPlanInputsUnchanged $planningInputs
  if (-not $PlanOnly -and $scenario.open_project -ne $false) {
    $kvsExe = Get-ConfiguredKvsExe
    if (-not (Test-Path -LiteralPath $kvsExe -PathType Leaf)) { throw "KV_TEST_KVS_EXE_MISSING: $kvsExe" }
    $projectNeedle = [IO.Path]::GetFileNameWithoutExtension($sourceProjectPath)
    $existing = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowTitle -like "*$projectNeedle*" })
    if($projectMode -eq 'fixture_copy'){
      # Fixture compilation binds the exact copied path; another same-named
      # user project is not the test target and must remain untouched.
      if($scenario.workflow -ne 'scripts/workflows/compile_kv_project.ps1'){throw 'KV_TEST_FIXTURE_WORKFLOW_NOT_VERIFIED'}
      $pattern='(?:^|\s)(?:"'+[regex]::Escape($projectPath)+'"|'+[regex]::Escape($projectPath)+')(?=\s|$)'
      $existing=@(Get-CimInstance Win32_Process -Filter "Name='Kvs.exe'" | Where-Object {$_.CommandLine -match $pattern})
    }
    if ($existing.Count -gt 0) { throw 'KV_TEST_PROJECT_ALREADY_OPEN' }
    $startupMutex=New-Object Threading.Mutex($false,'Local\KeyenceAgent.KvStudio.UI')
    $startupLockHeld=$false
    try {
      $startupLockHeld=$startupMutex.WaitOne(0)
      if (-not $startupLockHeld) { throw 'KV_UI_WORKFLOW_BUSY: another workflow owns the desktop before test startup' }
      $startedProcess = Start-Process -FilePath $kvsExe -WorkingDirectory (Split-Path -Parent $kvsExe) -ArgumentList ('"' + $projectPath + '"') -PassThru -WindowStyle Hidden
      $null=$startedProcess.Handle
      $startedProcessTimeUtc=$startedProcess.StartTime.ToUniversalTime()
      $cleanupStatus='preserved'
      $boundProcess = Wait-KvsProcess -ProjectNeedle $projectNeedle -StartedProcessId $startedProcess.Id -ExpectedStartTimeUtc $startedProcessTimeUtc
      $boundHwnd=[long]$boundProcess.MainWindowHandle
      $boundTitle=[string]$boundProcess.MainWindowTitle
    } finally {
      if ($startupLockHeld) { $startupMutex.ReleaseMutex() }
      $startupMutex.Dispose()
    }
  }
  if (-not $PlanOnly) {
    Assert-KvPlanInputsUnchanged $planningInputs
    $workflowProcessesBefore=@(Get-KvsTestProcessSnapshot)
    $workflowStartedUtc=(Get-Date).ToUniversalTime()
    $nativeErrorPreference=$ErrorActionPreference
    try {
      # Native stderr is diagnostic data. Capture the real exit code before
      # deciding whether it is the declared negative test or an unexpected failure.
      $ErrorActionPreference='Continue'
      & powershell @invokeArguments 1> $stdoutPath 2> $stderrPath
      $workflowExit = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 1 }
    } finally { $ErrorActionPreference=$nativeErrorPreference }
    $workflowProcessesAfter=@(Get-KvsTestProcessSnapshot)
  } else { $workflowExit=$planningExit }
} catch {
  $workflowError = $_.Exception.ToString(); $workflowError | Set-Content -LiteralPath $stderrPath -Encoding UTF8; $workflowExit = 1
}
$resultPath = if ($scenario.result_file) { Join-Path $runDirectory ([string]$scenario.result_file) } else { '' }
$result = $null
if ($resultPath -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) { try { $result = Get-Content -Raw -LiteralPath $resultPath -Encoding UTF8 | ConvertFrom-Json } catch {} }
$ok = ($workflowExit -eq 0 -and $result -and $result.ok -is [bool] -and $result.ok -and $result.status -ne 'planned' -and $result.planned -ne $true -and $workflowStartedUtc -and (Get-Item -LiteralPath $resultPath).LastWriteTimeUtc -ge $workflowStartedUtc)
$accepted=if ($PlanOnly) { $planningOk -and $workflowExit -eq 0 } else { $ok }
if(-not $PlanOnly -and $expectedOutcome -eq 'compile_error'){
  try{
    if(-not $planningOk -or -not $workflowStartedUtc -or $workflowError){throw 'KV_TEST_NG_EXECUTION_NOT_COMPLETED'}
    if((Get-FileHash -LiteralPath $expectedTextPath -Algorithm SHA256).Hash -cne $expectedTextHash){throw 'KV_TEST_NG_EXPECTATION_CHANGED'}
    $expectedFailureEvidence=Assert-KvExpectedCompileFailure (Join-Path $runDirectory 'workflow') $projectPath $expectedTextPath $workflowStartedUtc $workflowExit
    $expectedFailureEvidence|ConvertTo-Json -Depth 8|Set-Content -LiteralPath (Join-Path $runDirectory 'expected_failure_validation.json') -Encoding UTF8
    $accepted=$true;$ok=$true
  }catch{$accepted=$false;$ok=$false;$workflowError=$_.Exception.ToString()}
}
if($fixtureInputs.Count){
  try{Assert-KvPlanInputsUnchanged $fixtureInputs}
  catch{$accepted=$false;$ok=$false;$workflowError=$_.Exception.ToString()}
}
if(-not $PlanOnly -and $accepted -and $projectMode -eq 'new_project'){
  try{$createdProjectEvidence=Test-KvsNewProjectEvidence (Join-Path $runDirectory 'workflow/artifacts/create/create_project_result.json') $projectPath ([string]$scenario.cpu_model) $workflowStartedUtc $workflowProcessesBefore $workflowProcessesAfter}
  catch{$accepted=$false;$ok=$false;$workflowError=$_.Exception.ToString();$workflowError|Set-Content -LiteralPath $stderrPath -Encoding UTF8}
}
if (-not $PlanOnly -and $accepted -and -not $KeepProjectOpen) {
  $cleanupMutex=New-Object Threading.Mutex($false,'Local\KeyenceAgent.KvStudio.UI')
  $cleanupLockHeld=$false
  try {
    $cleanupLockHeld=$cleanupMutex.WaitOne(0)
    if ($cleanupLockHeld) {
      if($startedProcess){$cleanupStatus=Stop-OwnedKvsTestProcess $startedProcess $startedProcessTimeUtc}
      $cleanupProjectPaths=Get-KvsTestCleanupProjectPaths $runDirectory $projectPath
      $ownedSuccessors=@(Get-KvsTestCleanupCandidates $workflowProcessesBefore $workflowProcessesAfter $cleanupProjectPaths)
      if($createdProjectEvidence){$ownedSuccessors=@($ownedSuccessors|Where-Object {$_.id -ne $createdProjectEvidence.id})+@($createdProjectEvidence)}
      foreach($successor in $ownedSuccessors){
        $successorProcess=Get-Process -Id $successor.id -ErrorAction SilentlyContinue
        if(-not $successorProcess){continue}
        $null=$successorProcess.Handle
        $status=Stop-OwnedKvsTestProcess $successorProcess $successor.started_utc
        $workspaceCleanup+=@{pid=$successor.id;project_path=$successor.project_path;status=$status}
        if($createdProjectEvidence -and $successor.id -eq $createdProjectEvidence.id){$cleanupStatus=$status}
      }
    } else { $cleanupStatus='preserved_desktop_busy' }
  } catch {
    $cleanupStatus='cleanup_failed';$accepted=$false;$ok=$false;$workflowError=$_.Exception.ToString()
    $workflowError | Set-Content -LiteralPath $stderrPath -Encoding UTF8
  } finally {
    if ($cleanupLockHeld) { $cleanupMutex.ReleaseMutex() }
    $cleanupMutex.Dispose()
  }
}
$lifecycle=[ordered]@{project_mode=$projectMode;created_project_evidence=$createdProjectEvidence;project_path=$projectPath;started_pid=if($startedProcess){$startedProcess.Id}else{$null};started_utc=if($startedProcess){$startedProcessTimeUtc.ToString('o')}else{$null};bound_pid=if($boundProcess){$boundProcess.Id}else{$null};bound_hwnd=$boundHwnd;bound_title=$boundTitle;cleanup_status=$cleanupStatus;workflow_processes_before=$workflowProcessesBefore;workflow_processes_after=$workflowProcessesAfter;workspace_cleanup=$workspaceCleanup;keep_project_open=[bool]$KeepProjectOpen}
$lifecycle | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $runDirectory 'process_lifecycle.json') -Encoding UTF8
$record = [ordered]@{ok=[bool]$accepted;status=if($PlanOnly -and $accepted){'planned'}elseif($ok){'pass'}else{'fail'};expected_outcome=$expectedOutcome;expected_failure_verified=($null -ne $expectedFailureEvidence -and $accepted);planning_ok=$planningOk;planning_exit_code=$planningExit;scenario=$scenario.name;workflow=$workflowPath;project_path=$projectPath;run_directory=$runDirectory;workflow_exit_code=$workflowExit;result_path=$resultPath;result_ok=if($result -and $result.ok -is [bool]){[bool]$result.ok}else{$false};error=$workflowError;stdout_path=$stdoutPath;stderr_path=$stderrPath;process_lifecycle=$lifecycle;generated_utc=(Get-Date).ToUniversalTime().ToString('o')}
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDirectory 'test_result.json') -Encoding UTF8
$record | ConvertTo-Json -Depth 8
if ($accepted) { exit 0 } else { exit 1 }
