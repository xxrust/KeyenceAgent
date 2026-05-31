param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [Parameter(Mandatory=$true)]
  [string]$ScaffoldRoot,

  [string]$OutRoot = 'C:\Users\Public\KVSkillPractice\mvp_repair_runs',
  [string]$ProjectName = '',
  [string]$KvsExe = '',
  [string]$ConfigPath = '',
  [string]$ChecklistPath = '',
  [string]$SourceSnapshotManifestPath = '',
  [int]$TimeoutSeconds = 600,
  [switch]$AuditVariablePersistence,
  [ValidateSet('Full','NameType')]
  [string]$LocalPasteFormat = 'NameType',
  [switch]$DeleteExistingModulesBeforeImport
)

$ErrorActionPreference = 'Stop'
$start = Get-Date
$scriptRoot = Split-Path -Parent $PSCommandPath
$mvpScriptRoot = Join-Path $scriptRoot 'mvp'
$variableDefinitionLib = Join-Path $scriptRoot 'kv_variable_definition_lib.ps1'
if (-not (Test-Path -LiteralPath $variableDefinitionLib -PathType Leaf)) { throw "KV variable definition library not found: $variableDefinitionLib" }
. $variableDefinitionLib
$configLoader = Join-Path $scriptRoot 'Import-KvStudioOperatorConfig.ps1'
if (Test-Path -LiteralPath $configLoader -PathType Leaf) {
  $operatorConfig = & $configLoader -ConfigPath $ConfigPath -ScriptRoot $scriptRoot
  if ($operatorConfig.found) {
    if (-not $PSBoundParameters.ContainsKey('KvsExe') -and $operatorConfig.kvs_exe) { $KvsExe = [string]$operatorConfig.kvs_exe }
    if (-not $PSBoundParameters.ContainsKey('OutRoot') -and $operatorConfig.repair_out_root) { $OutRoot = [string]$operatorConfig.repair_out_root }
    if (-not $PSBoundParameters.ContainsKey('TimeoutSeconds') -and $null -ne $operatorConfig.timeout_seconds) { $TimeoutSeconds = [int]$operatorConfig.timeout_seconds }
    if (-not $PSBoundParameters.ContainsKey('LocalPasteFormat') -and $operatorConfig.local_paste_format) { $LocalPasteFormat = [string]$operatorConfig.local_paste_format }
  }
}
$steps = [System.Collections.Generic.List[object]]::new()
$script:currentStep = 'init'
$script:lastFailure = $null

function New-Cn([int[]]$CodePoints) {
  -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Resolve-ScaffoldPath([string]$RelativePath) {
  if ([IO.Path]::IsPathRooted($RelativePath)) { return [IO.Path]::GetFullPath($RelativePath) }
  return [IO.Path]::GetFullPath((Join-Path $ScaffoldRoot $RelativePath))
}

function Read-VariableRows([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path)) { throw "Variable TSV not found: $Path" }
  $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::Default)
  if ([string]::IsNullOrWhiteSpace($text)) { throw "Variable TSV is empty: $Path" }
  @($text | ConvertFrom-Csv -Delimiter "`t")
}

function Get-ExecutableVariableRows([string]$Path, [string]$Scope) {
  @(Get-KvExecutableVariableRows -Rows @(Read-VariableRows $Path) -Scope $Scope)
}

function Get-ExecutableVariableNames([string]$Path, [string]$Scope) {
  @((Get-ExecutableVariableRows $Path $Scope) | ForEach-Object { [string]$_.name } | Where-Object { $_ } | Select-Object -Unique)
}

function New-MergedGlobalVariablesTsv([object[]]$Entries, [string]$OutDir) {
  $header = 'scope' + "`t" + 'owner_program' + "`t" + 'name' + "`t" + 'data_type' + "`t" + 'device' + "`t" + 'initial_value' + "`t" + 'comment' + "`t" + 'evidence' + "`t" + 'status'
  $byName = [ordered]@{}
  foreach ($entry in $Entries) {
    foreach ($row in (Get-ExecutableVariableRows $entry.global_tsv 'global')) {
      $name = [string]$row.name
      $signature = @([string]$row.data_type, [string]$row.device, [string]$row.initial_value) -join "`t"
      if ($byName.Contains($name) -and $byName[$name].signature -ne $signature) {
        throw "Global variable conflict while merging per-MNM variable sets. name=$name first=$($byName[$name].source) second=$($entry.global_tsv)"
      }
      if (-not $byName.Contains($name)) {
        $byName[$name] = [pscustomobject]@{ signature = $signature; source = $entry.global_tsv; row = $row }
      }
    }
  }
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $path = Join-Path $OutDir 'global_variables_merged.tsv'
  $lines = @($header)
  foreach ($item in $byName.Values) {
    $row = $item.row
    $lines += @(
      [string]$row.scope
      [string]$row.owner_program
      [string]$row.name
      [string]$row.data_type
      [string]$row.device
      [string]$row.initial_value
      [string]$row.comment
      [string]$row.evidence
      [string]$row.status
    ) -join "`t"
  }
  [IO.File]::WriteAllText($path, (($lines -join "`r`n") + "`r`n"), [Text.Encoding]::Default)
  [pscustomobject]@{
    path = $path
    executable_global_variable_count = $byName.Count
    source_files = @($Entries | ForEach-Object { $_.global_tsv } | Select-Object -Unique)
  }
}

function Get-ElapsedSeconds {
  [math]::Round(((Get-Date) - $start).TotalSeconds, 3)
}

function Assert-TimeBudget([string]$Stage) {
  $elapsed = ((Get-Date) - $start).TotalSeconds
  if ($elapsed -gt $TimeoutSeconds) {
    throw "MVP repair time budget exceeded at ${Stage}: $([math]::Round($elapsed, 3))s > ${TimeoutSeconds}s"
  }
}

function Get-ArgumentValue([string[]]$Arguments, [string]$Name) {
  for ($i = 0; $i -lt $Arguments.Count; $i++) {
    if ($Arguments[$i] -eq $Name -and ($i + 1) -lt $Arguments.Count) { return $Arguments[$i + 1] }
  }
  return ''
}

function Read-JsonFileIfPossible([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try { return (Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}

function Get-StepResultFile([string]$OutDir) {
  if (-not $OutDir -or -not (Test-Path -LiteralPath $OutDir -PathType Container)) { return $null }
  Get-ChildItem -LiteralPath $OutDir -File -Recurse -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -like '*result.json' } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
}

function Clear-StaleStepArtifacts([string]$OutDir) {
  if (-not $OutDir) { return }
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  foreach ($name in @('fail.txt','exit_code.txt','timeout_result.json','runner_child_stdout.txt','runner_child_stderr.txt')) {
    $path = Join-Path $OutDir $name
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      Remove-Item -LiteralPath $path -Force
    }
  }
}

function Get-StepFailureSummary([string]$Name, [string[]]$Arguments, [int]$ExitCode) {
  $outDir = Get-ArgumentValue $Arguments '-OutDir'
  $summary = [ordered]@{
    step = $Name
    exit_code = $ExitCode
    out_dir = $outDir
    error_code = ''
    child_result_path = ''
    checkpoint_path = ''
    fail_text_path = ''
    evidence = @()
    message = ''
  }
  if (-not $outDir -or -not (Test-Path -LiteralPath $outDir -PathType Container)) { return [pscustomobject]$summary }
  $resultFile = Get-StepResultFile $outDir
  if ($resultFile) {
    $summary.child_result_path = $resultFile.FullName
    $summary.evidence += $resultFile.FullName
    $child = Read-JsonFileIfPossible $resultFile.FullName
    if ($child) {
      if ($child.error_code) { $summary.error_code = [string]$child.error_code }
      if ($child.message) { $summary.message = [string]$child.message }
      if ($child.evidence) { $summary.evidence += @($child.evidence | ForEach-Object { [string]$_ }) }
    }
  }
  $checkpoint = Get-ChildItem -LiteralPath $outDir -File -Filter '*failed.json' -Recurse -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1
  if ($checkpoint) {
    $summary.checkpoint_path = $checkpoint.FullName
    $summary.evidence += $checkpoint.FullName
  }
  $failText = Join-Path $outDir 'fail.txt'
  if (Test-Path -LiteralPath $failText -PathType Leaf) {
    $summary.fail_text_path = $failText
    $summary.evidence += $failText
    if (-not $summary.message) {
      try { $summary.message = ([IO.File]::ReadAllText($failText, [Text.Encoding]::UTF8)).Trim() } catch {}
    }
  }
  $stderrPath = Join-Path $outDir 'runner_child_stderr.txt'
  if (Test-Path -LiteralPath $stderrPath -PathType Leaf) {
    $stderrItem = Get-Item -LiteralPath $stderrPath
    if ($stderrItem.Length -gt 0) {
      $summary.evidence += $stderrPath
      if (-not $summary.message) {
        try { $summary.message = ([IO.File]::ReadAllText($stderrPath, [Text.Encoding]::UTF8)).Trim() } catch {}
      }
    }
  }
  if (-not $summary.error_code) { $summary.error_code = 'KV_MVP_REPAIR_STEP_FAILED' }
  $summary.evidence = @($summary.evidence | Where-Object { $_ } | Select-Object -Unique)
  return [pscustomobject]$summary
}

function Test-StepResultOk([string]$OutDir) {
  if (-not $OutDir -or -not (Test-Path -LiteralPath $OutDir -PathType Container)) { return $true }
  $failText = Join-Path $OutDir 'fail.txt'
  $resultFile = Get-StepResultFile $OutDir
  if (-not $resultFile) { return -not (Test-Path -LiteralPath $failText -PathType Leaf) }
  $child = Read-JsonFileIfPossible $resultFile.FullName
  if ($null -eq $child -or $null -eq $child.ok) { return $true }
  return ([bool]$child.ok)
}

function Stop-ProcessTree([int]$ProcessIdValue) {
  $children = @(Get-CimInstance Win32_Process -Filter "ParentProcessId=$ProcessIdValue" -ErrorAction SilentlyContinue)
  foreach ($child in $children) {
    Stop-ProcessTree ([int]$child.ProcessId)
  }
  $process = Get-Process -Id $ProcessIdValue -ErrorAction SilentlyContinue
  if ($process) {
    Stop-Process -Id $ProcessIdValue -Force -ErrorAction SilentlyContinue
  }
}

function Get-StepTimeoutSeconds([string[]]$Arguments) {
  $remaining = [math]::Max(1, [int]($TimeoutSeconds - ((Get-Date) - $start).TotalSeconds))
  $waitValue = Get-ArgumentValue $Arguments '-WaitSeconds'
  if ($waitValue -match '^\d+$') {
    return [math]::Min($remaining, ([int]$waitValue + 30))
  }
  return $remaining
}

function Invoke-MvpStep([string]$Name, [string]$ScriptName, [string[]]$Arguments) {
  Assert-TimeBudget "before $Name"
  $script:currentStep = $Name
  $scriptPath = Join-Path $mvpScriptRoot $ScriptName
  if (-not (Test-Path -LiteralPath $scriptPath)) { throw "Required MVP script is missing: $scriptPath" }
  $stepStart = Get-Date
  $outDir = Get-ArgumentValue $Arguments '-OutDir'
  if ($outDir) { Clear-StaleStepArtifacts $outDir }
  $stdoutPath = if ($outDir) { Join-Path $outDir 'runner_child_stdout.txt' } else { Join-Path $artifactRoot ("${Name}_stdout.txt") }
  $stderrPath = if ($outDir) { Join-Path $outDir 'runner_child_stderr.txt' } else { Join-Path $artifactRoot ("${Name}_stderr.txt") }
  $command = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) + $Arguments
  $process = Start-Process -FilePath 'powershell.exe' -ArgumentList $command -NoNewWindow -PassThru -RedirectStandardOutput $stdoutPath -RedirectStandardError $stderrPath
  $stepTimeoutSeconds = Get-StepTimeoutSeconds $Arguments
  $deadline = (Get-Date).AddSeconds($stepTimeoutSeconds)
  $timedOut = $false
  while (-not $process.HasExited) {
    Start-Sleep -Milliseconds 250
    if ($outDir -and -not (Test-StepResultOk $outDir)) {
      Stop-ProcessTree $process.Id
      break
    }
    if ((Get-Date) -ge $deadline) {
      $timedOut = $true
      Stop-ProcessTree $process.Id
      break
    }
  }
  if ($timedOut) {
    $elapsed = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 3)
    $timeoutPayload = [ordered]@{
      ok = $false
      error_code = 'KV_MVP_STEP_TIMEOUT'
      step = $Name
      script = $scriptPath
      elapsed_seconds = $elapsed
      step_timeout_seconds = $stepTimeoutSeconds
      stdout_path = $stdoutPath
      stderr_path = $stderrPath
      message = "MVP repair child step timed out and its process tree was terminated: $Name"
    }
    if ($outDir) {
      $timeoutPath = Join-Path $outDir 'timeout_result.json'
      $timeoutPayload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $timeoutPath -Encoding UTF8
      $timeoutPayload.message | Set-Content -LiteralPath (Join-Path $outDir 'fail.txt') -Encoding UTF8
    }
    $steps.Add([pscustomobject]@{ name = $Name; script = $scriptPath; exit_code = -2; elapsed_seconds = $elapsed; timeout = $true; step_timeout_seconds = $stepTimeoutSeconds })
    $script:lastFailure = Get-StepFailureSummary $Name $Arguments -2
    $script:lastFailure.error_code = 'KV_MVP_STEP_TIMEOUT'
    if (-not $script:lastFailure.message) { $script:lastFailure.message = $timeoutPayload.message }
    if ($outDir) { $script:lastFailure.evidence += (Join-Path $outDir 'timeout_result.json') }
    throw "MVP repair step timed out: $Name elapsed=${elapsed}s timeout=${stepTimeoutSeconds}s"
  }
  $process.WaitForExit()
  $exit = [int]$process.ExitCode
  $childExitCodePath = if ($outDir) { Join-Path $outDir 'exit_code.txt' } else { '' }
  if ($childExitCodePath -and (Test-Path -LiteralPath $childExitCodePath -PathType Leaf)) {
    $childExitCodeText = ([IO.File]::ReadAllText($childExitCodePath, [Text.Encoding]::ASCII)).Trim()
    if ($childExitCodeText -match '^-?\d+$') { $exit = [int]$childExitCodeText }
  }
  if ($exit -eq 0 -and $outDir -and (Test-Path -LiteralPath (Join-Path $outDir 'fail.txt') -PathType Leaf)) {
    $exit = 1
  }
  if ($exit -eq 0 -and (Test-Path -LiteralPath $stderrPath -PathType Leaf) -and (Get-Item -LiteralPath $stderrPath).Length -gt 0) {
    $exit = 1
    if ($outDir) {
      'Child step wrote to stderr; treating this as a failed guarded step.' | Set-Content -LiteralPath (Join-Path $outDir 'fail.txt') -Encoding UTF8
    }
  }
  if ($exit -eq 0 -and -not (Test-StepResultOk $outDir)) { $exit = 1 }
  $elapsed = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 3)
  $steps.Add([pscustomobject]@{ name = $Name; script = $scriptPath; exit_code = $exit; elapsed_seconds = $elapsed })
  if ($exit -ne 0) {
    $script:lastFailure = Get-StepFailureSummary $Name $Arguments $exit
    throw "MVP repair step failed: $Name exit_code=$exit"
  }
  Assert-TimeBudget "after $Name"
}

$ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "ProjectPath not found: $ProjectPath" }
$ScaffoldRoot = [IO.Path]::GetFullPath($ScaffoldRoot)
$manifestPath = Join-Path $ScaffoldRoot 'scaffold.json'
if (-not (Test-Path -LiteralPath $manifestPath)) { throw "scaffold.json not found: $manifestPath" }
$manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
if ([int]$manifest.schema_version -ne 2 -or [string]$manifest.variables.schema -ne 'per_mnm') {
  throw 'Unsupported scaffold variable schema. Use schema_version=2 and variables.schema=per_mnm.'
}

if (-not $ProjectName) {
  if ($manifest.project.name) { $ProjectName = [string]$manifest.project.name } else { $ProjectName = [IO.Path]::GetFileNameWithoutExtension($ProjectPath) }
}
$ProjectNeedleName = [IO.Path]::GetFileNameWithoutExtension($ProjectPath)

$manifestChecklist = ''
if ($manifest.checklist) { $manifestChecklist = Resolve-ScaffoldPath ([string]$manifest.checklist) }
if (-not $ChecklistPath -and $manifestChecklist) { $ChecklistPath = $manifestChecklist }
$checklistGuard = Join-Path $scriptRoot 'assert_kv_operation_checklist.ps1'
if (-not (Test-Path -LiteralPath $checklistGuard)) { throw "Checklist guard script not found: $checklistGuard" }
$global:LASTEXITCODE = 0
$checklistJson = & $checklistGuard -ChecklistPath $ChecklistPath -SearchRoots @($ScaffoldRoot, $OutRoot, $ProjectPath) -OperationName 'repair existing KV STUDIO MVP project'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$checklistResult = ($checklistJson | ConvertFrom-Json)
$ChecklistPath = [string]$checklistResult.checklist_path

$runRoot = Join-Path $OutRoot $ProjectName
$artifactRoot = Join-Path $runRoot 'artifacts'
$scaffoldArtifactRoot = Join-Path $artifactRoot 'scaffold'
$reportPath = Join-Path $runRoot 'repair_result.json'
$agentBoundaryContractPath = ''
$sourceSnapshotGateResult = $null
$mnmImportPlanGateResult = $null
$mnmImportPlanGatePath = ''
$changePlanPath = Join-Path $artifactRoot 'change_plan.json'
$regressionEvidencePath = Join-Path $artifactRoot 'regression_evidence.json'
New-Item -ItemType Directory -Force -Path $runRoot, $artifactRoot, $scaffoldArtifactRoot | Out-Null

$script:currentStep = 'assert_existing_project_source_snapshot'
if (-not $SourceSnapshotManifestPath) {
  $snapshotCandidates = @(
    (Join-Path $ScaffoldRoot 'source_snapshot_manifest.json'),
    (Join-Path $ScaffoldRoot 'architecture\source_snapshot_manifest.json')
  )
  foreach ($candidate in $snapshotCandidates) {
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
      $SourceSnapshotManifestPath = $candidate
      break
    }
  }
}
$snapshotGate = Join-Path $scriptRoot 'assert_kv_existing_project_snapshot.ps1'
if (-not (Test-Path -LiteralPath $snapshotGate -PathType Leaf)) { throw "Existing-project snapshot gate script not found: $snapshotGate" }
$sourceSnapshotGateJson = & $snapshotGate -ProjectPath $ProjectPath -SnapshotManifestPath $SourceSnapshotManifestPath -OutDir (Join-Path $artifactRoot 'source_snapshot_gate')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$sourceSnapshotGateResult = $sourceSnapshotGateJson | ConvertFrom-Json

$scaffoldValidator = Join-Path $scriptRoot 'validate_kv_mvp_scaffold.ps1'
$script:currentStep = 'validate_scaffold'
& $scaffoldValidator -ScaffoldRoot $ScaffoldRoot -ChecklistPath $ChecklistPath -OutDir (Join-Path $artifactRoot 'scaffold_validation') | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$uiGuardUsageCheck = Join-Path $scriptRoot 'assert_kv_mvp_ui_guard_usage.ps1'
$script:currentStep = 'assert_ui_guard_usage'
& $uiGuardUsageCheck -ScriptsRoot $mvpScriptRoot -OutDir (Join-Path $artifactRoot 'ui_guard_usage') | Out-Null
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

$agentBoundaryCheck = Join-Path $scriptRoot 'assert_kv_mvp_agent_boundary.ps1'
$script:currentStep = 'assert_agent_boundary'
$agentBoundaryJson = & $agentBoundaryCheck -ScriptsRoot $scriptRoot -MvpScriptsRoot $mvpScriptRoot -OutDir (Join-Path $artifactRoot 'agent_boundary')
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$agentBoundaryResult = ($agentBoundaryJson | ConvertFrom-Json)
$agentBoundaryContractPath = [string]$agentBoundaryResult.contract_path

$mnmEntries = @($manifest.mnm_files)
if ($mnmEntries.Count -eq 0) { throw 'scaffold.json must contain at least one mnm_files entry.' }
$fbTypeNames = @(
  $mnmEntries |
    Where-Object {
      $moduleTypeForCustom = if ($null -ne $_.module_type -and [string]$_.module_type -ne '') { [int]$_.module_type } else { 0 }
      $moduleTypeForCustom -eq 2
    } |
    ForEach-Object {
      if ($_.module_name) { [string]$_.module_name } else { [IO.Path]::GetFileNameWithoutExtension([string]$_.path) }
    } |
    Where-Object { $_ } |
    Select-Object -Unique
)
$resolvedMnmFiles = @()
foreach ($entry in $mnmEntries) {
  $mnmPath = Resolve-ScaffoldPath ([string]$entry.path)
  if (-not (Test-Path -LiteralPath $mnmPath)) { throw "MNM file not found: $mnmPath" }
  $moduleName = [string]$entry.module_name
  if (-not $moduleName) { $moduleName = [IO.Path]::GetFileNameWithoutExtension($mnmPath) }
  $moduleType = if ($null -ne $entry.module_type -and [string]$entry.module_type -ne '') { [int]$entry.module_type } else { 0 }
  $category = if ($entry.category) { [string]$entry.category } elseif ($moduleType -eq 2) { 'function_block' } else { 'scan' }
  if (-not $entry.variables -or -not $entry.variables.global_tsv -or -not $entry.variables.local_tsv) {
    throw "MNM entry $moduleName must define variables.global_tsv and variables.local_tsv."
  }
  $entryGlobalTsv = Resolve-ScaffoldPath ([string]$entry.variables.global_tsv)
  $entryLocalTsv = Resolve-ScaffoldPath ([string]$entry.variables.local_tsv)
  if (-not (Test-Path -LiteralPath $entryGlobalTsv)) { throw "Global variable TSV not found for ${moduleName}: $entryGlobalTsv" }
  if (-not (Test-Path -LiteralPath $entryLocalTsv)) { throw "Local variable TSV not found for ${moduleName}: $entryLocalTsv" }
  $entryArgumentsTsv = ''
  if ($moduleType -eq 2) {
    if (-not $entry.arguments -or -not $entry.arguments.tsv) {
      throw "Function-block MNM entry $moduleName must define arguments.tsv."
    }
    $entryArgumentsTsv = Resolve-ScaffoldPath ([string]$entry.arguments.tsv)
    if (-not (Test-Path -LiteralPath $entryArgumentsTsv)) { throw "FB arguments TSV not found for ${moduleName}: $entryArgumentsTsv" }
  }
  $resolvedMnmFiles += [pscustomobject]@{
    path = $mnmPath
    module_name = $moduleName
    module_type = $moduleType
    category = $category
    global_tsv = $entryGlobalTsv
    local_tsv = $entryLocalTsv
    arguments_tsv = $entryArgumentsTsv
  }
}

$script:currentStep = 'assert_mnm_import_plan'
$mnmImportPlanGate = Join-Path $scriptRoot 'assert_kv_mnm_import_plan.ps1'
if (-not (Test-Path -LiteralPath $mnmImportPlanGate -PathType Leaf)) { throw "MNM import plan gate script not found: $mnmImportPlanGate" }
$mnmImportPlanGatePath = Join-Path (Join-Path $artifactRoot 'mnm_import_plan_gate') 'mnm_import_plan_gate.json'
$mnmImportPlanArgs = @(
  '-ScaffoldRoot', $ScaffoldRoot,
  '-SourceSnapshotManifestPath', $SourceSnapshotManifestPath,
  '-SourceSnapshotGateResultPath', (Join-Path (Join-Path $artifactRoot 'source_snapshot_gate') 'existing_project_snapshot_gate.json'),
  '-OutDir', (Join-Path $artifactRoot 'mnm_import_plan_gate')
)
if ($DeleteExistingModulesBeforeImport) { $mnmImportPlanArgs += '-DeleteExistingModulesBeforeImport' }
$global:LASTEXITCODE = 0
$mnmImportPlanJson = & $mnmImportPlanGate @mnmImportPlanArgs
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$mnmImportPlanGateResult = $mnmImportPlanJson | ConvertFrom-Json

Get-ChildItem -LiteralPath $ScaffoldRoot -Force | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $scaffoldArtifactRoot -Recurse -Force
}
$variableArtifactDir = Join-Path $artifactRoot 'variables'
$mergedGlobal = New-MergedGlobalVariablesTsv $resolvedMnmFiles $variableArtifactDir

$sourceSnapshotBefore = [ordered]@{
  manifest = $SourceSnapshotManifestPath
  gate_result_path = Join-Path (Join-Path $artifactRoot 'source_snapshot_gate') 'existing_project_snapshot_gate.json'
  fingerprint_hash = [string]$sourceSnapshotGateResult.project_fingerprint.hash
  mnm_count = [int]$sourceSnapshotGateResult.mnm_count
  variable_manifest_count = [int]$sourceSnapshotGateResult.variable_manifest_count
  architecture_path = [string]$sourceSnapshotGateResult.architecture_path
}
$changePlan = [ordered]@{
  ok = $true
  schema_version = 1
  operation = 'existing_project_update'
  project_path = $ProjectPath
  source_snapshot_before = $sourceSnapshotBefore
  mnm_import_plan_gate = [ordered]@{
    path = $mnmImportPlanGatePath
    delete_required = [bool]$mnmImportPlanGateResult.delete_required
    delete_existing_modules_before_import = [bool]$DeleteExistingModulesBeforeImport
    conflicts = @($mnmImportPlanGateResult.conflicts)
  }
  scaffold_after = [ordered]@{
    root = $ScaffoldRoot
    manifest = $manifestPath
    mnm_files = @($resolvedMnmFiles | ForEach-Object {
      [ordered]@{
        module_name = [string]$_.module_name
        module_type = [int]$_.module_type
        category = [string]$_.category
        mnm_path = [string]$_.path
        global_tsv = [string]$_.global_tsv
        local_tsv = [string]$_.local_tsv
        arguments_tsv = [string]$_.arguments_tsv
        global_variable_names = @(Get-ExecutableVariableNames $_.global_tsv 'global')
        local_variable_names = @(Get-ExecutableVariableNames $_.local_tsv 'local')
      }
    })
    merged_global_variables_tsv = $mergedGlobal.path
  }
  apply_plan = @(
    'Before KV STUDIO opens, compare incoming MNM module names with the verified source snapshot MNM inventory.',
    'If a same-name module exists, require -DeleteExistingModulesBeforeImport and pre-delete the existing module before importing the replacement MNM.',
    'Import every scaffold MNM into the existing project.',
    'For each user function block, open its self-variable table and apply arguments.tsv before compile.',
    'Apply merged global variables once, then apply each module local variable TSV to its owning local program.',
    'Run bounded KV STUDIO compile/convert and copy the conversion result text.',
    'Accept only same-run compile OK and source snapshot gate evidence.'
  )
}
$changePlan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $changePlanPath -Encoding UTF8

function Write-RepairResult([bool]$Ok, [string]$Status, [string]$Message = '') {
  $compileResultPath = Join-Path (Join-Path $artifactRoot 'copy_result') 'compile_result_copied.txt'
  $compileText = ''
  if (Test-Path -LiteralPath $compileResultPath) {
    $compileText = [IO.File]::ReadAllText($compileResultPath, [Text.Encoding]::UTF8)
  }
  $okNeedle = (New-Cn @(0x8F6C,0x6362,0x7ED3,0x679C)) + ' OK'
  $ngNeedle = (New-Cn @(0x8F6C,0x6362,0x7ED3,0x679C)) + ' NG'
  [ordered]@{
    ok = $Ok
    status = $Status
    message = $Message
    elapsed_seconds = Get-ElapsedSeconds
    timeout_seconds = $TimeoutSeconds
    checklist_path = $ChecklistPath
    current_step = $script:currentStep
    scaffold_root = $ScaffoldRoot
    scaffold_manifest = $manifestPath
    project_name = $ProjectName
    project_path = $ProjectPath
    source_snapshot_manifest = $SourceSnapshotManifestPath
    source_snapshot_gate = $sourceSnapshotGateResult
    mnm_import_plan_gate = $mnmImportPlanGateResult
    mnm_import_plan_gate_path = $mnmImportPlanGatePath
    change_plan_path = $changePlanPath
    regression_evidence_path = if (Test-Path -LiteralPath $regressionEvidencePath -PathType Leaf) { $regressionEvidencePath } else { '' }
    agent_allowed_phases = @('prepare_repair_scaffold_before_kv_studio_opens', 'verify_same_run_artifacts_after_runner_exits')
    script_owned_phase = 'from first KV STUDIO launch through compile result copy'
    agent_boundary_contract_path = $agentBoundaryContractPath
    mnm_files = @($resolvedMnmFiles)
    merged_global_variables_tsv = $mergedGlobal.path
    variable_sets = @($resolvedMnmFiles | ForEach-Object {
      [pscustomobject]@{ module_name = $_.module_name; category = $_.category; global_tsv = $_.global_tsv; local_tsv = $_.local_tsv; arguments_tsv = $_.arguments_tsv }
    })
    compile_result_path = $compileResultPath
    compile_result_contains_ok = ($compileText.Contains($okNeedle))
    compile_result_contains_ng = ($compileText.Contains($ngNeedle))
    compile_result_length = $compileText.Length
    error_code = if ($script:lastFailure -and $script:lastFailure.error_code) { [string]$script:lastFailure.error_code } elseif (-not $Ok) { 'KV_MVP_REPAIR_FAILED' } else { '' }
    failure = $script:lastFailure
    steps = @($steps)
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

try {
  for ($i = 0; $i -lt $resolvedMnmFiles.Count; $i++) {
    $entry = $resolvedMnmFiles[$i]
    $importArgs = @(
      '-MnmPath', $entry.path,
      '-ProjectPath', $ProjectPath,
      '-OutDir', (Join-Path $artifactRoot ("import_mnm_$($i + 1)")),
      '-ExpectedModuleName', $entry.module_name,
      '-ExpectedCategory', $entry.category,
      '-ProjectSearchRoot', (Split-Path -Parent $ProjectPath),
      '-ChecklistPath', $ChecklistPath,
      '-SaveAfterImport',
      '-RestartKvs', $(if ($i -eq 0) { '$true' } else { '$false' })
    )
    if ($DeleteExistingModulesBeforeImport) { $importArgs += '-DeleteExistingModuleBeforeImport' }
    if ($KvsExe) { $importArgs += @('-KvsExe', $KvsExe) }
    Invoke-MvpStep "repair_import_mnm_$($i + 1)" 'import_mnm_guarded.ps1' $importArgs
  }

  $fbArgumentRoot = Join-Path $artifactRoot 'set_fb_arguments'
  New-Item -ItemType Directory -Force -Path $fbArgumentRoot | Out-Null
  for ($i = 0; $i -lt $resolvedMnmFiles.Count; $i++) {
    $entry = $resolvedMnmFiles[$i]
    if ([int]$entry.module_type -ne 2) { continue }
    if (-not $entry.arguments_tsv) { throw "Function-block arguments TSV is missing after resolution: $($entry.module_name)" }
    $safeModule = ($entry.module_name -replace '[^A-Za-z0-9_.-]+', '_')
    Invoke-MvpStep "repair_set_fb_arguments_$($entry.module_name)" 'set_fb_arguments_guarded.ps1' @(
      '-ProjectPath', $ProjectPath,
      '-FbModuleName', $entry.module_name,
      '-ArgumentsTsv', $entry.arguments_tsv,
      '-ChecklistPath', $ChecklistPath,
      '-OutDir', (Join-Path $fbArgumentRoot ('module_{0:D2}_{1}' -f ($i + 1), $safeModule))
    )
  }

  $setVariablesRoot = Join-Path $artifactRoot 'set_variables'
  New-Item -ItemType Directory -Force -Path $setVariablesRoot | Out-Null
  $globalVariablesPasted = $false
  $setVariableSummaries = @()
  for ($i = 0; $i -lt $resolvedMnmFiles.Count; $i++) {
    $entry = $resolvedMnmFiles[$i]
    $safeModule = ($entry.module_name -replace '[^A-Za-z0-9_.-]+', '_')
    $moduleOutDir = Join-Path $setVariablesRoot ('module_{0:D2}_{1}' -f ($i + 1), $safeModule)
    $setArgs = @(
      '-ProjectPath', $ProjectPath,
      '-GlobalVariablesTsv', $mergedGlobal.path,
      '-LocalVariablesTsv', $entry.local_tsv,
      '-LocalProgramName', $entry.module_name,
      '-LocalPasteFormat', $LocalPasteFormat,
      '-ChecklistPath', $ChecklistPath,
      '-OutDir', $moduleOutDir,
      '-AppendGlobalVariables'
    )
    if ($fbTypeNames.Count -gt 0) {
      $setArgs += @('-AllowedCustomDataTypes', ($fbTypeNames -join ','))
    }
    if ($globalVariablesPasted -or [int]$mergedGlobal.executable_global_variable_count -eq 0) { $setArgs += '-SkipGlobal' }
    if ($AuditVariablePersistence) {
      $setArgs += '-AuditPersistence'
      $forbiddenLocalNames = @()
      for ($j = 0; $j -lt $resolvedMnmFiles.Count; $j++) {
        if ($j -eq $i) { continue }
        $forbiddenLocalNames += @(Get-ExecutableVariableNames $resolvedMnmFiles[$j].local_tsv 'local')
      }
      $forbiddenLocalNames = @($forbiddenLocalNames | Where-Object { $_ } | Select-Object -Unique)
      if ($forbiddenLocalNames.Count -gt 0) { $setArgs += @('-ForbiddenLocalNamesCsv', ($forbiddenLocalNames -join ',')) }
    }
    Invoke-MvpStep "repair_set_variables_$($entry.module_name)" 'set_variables_guarded.ps1' $setArgs
    if ([int]$mergedGlobal.executable_global_variable_count -gt 0) { $globalVariablesPasted = $true }
    $setVariableSummaries += [pscustomobject]@{
      module_name = $entry.module_name
      global_pasted_in_this_step = (-not ($setArgs -contains '-SkipGlobal'))
      local_tsv = $entry.local_tsv
      result_path = (Join-Path $moduleOutDir 'set_variables_result.json')
      validation_path = (Join-Path $moduleOutDir 'variable_persistence_validation.json')
      ok = (Test-Path -LiteralPath (Join-Path $moduleOutDir 'set_variables_result.json'))
    }
  }
  [pscustomobject]@{
    Ok = $true
    Basis = 'repair runner applied merged globals once and each MNM local variable TSV to its own module/program'
    MergedGlobalVariablesTsv = $mergedGlobal.path
    ExecutableGlobalVariableCount = $mergedGlobal.executable_global_variable_count
    ModuleResults = $setVariableSummaries
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $setVariablesRoot 'variable_persistence_validation.json') -Encoding UTF8

  Invoke-MvpStep 'repair_compile_convert' 'compile_and_copy_result_bounded.ps1' @(
    '-ProjectPath', $ProjectPath,
    '-OutDir', (Join-Path $artifactRoot 'compile_convert'),
    '-WaitSeconds', '40',
    '-ChecklistPath', $ChecklistPath,
    '-ConvertAction', 'CtrlF9'
  )

  Invoke-MvpStep 'repair_copy_convert_result' 'copy_convert_result_from_tree_handle.ps1' @(
    '-ProjectNeedle', $ProjectNeedleName,
    '-OutDir', (Join-Path $artifactRoot 'copy_result'),
    '-ChecklistPath', $ChecklistPath,
    '-MaxLookupMs', '1000'
  )

  $compileResultPath = Join-Path (Join-Path $artifactRoot 'copy_result') 'compile_result_copied.txt'
  if (-not (Test-Path -LiteralPath $compileResultPath -PathType Leaf)) {
    throw "Copied compile result file is missing: $compileResultPath"
  }
  $copyText = [IO.File]::ReadAllText($compileResultPath, [Text.Encoding]::UTF8)
  $okNeedle = (New-Cn @(0x8F6C,0x6362,0x7ED3,0x679C)) + ' OK'
  if (-not $copyText.Contains($okNeedle)) {
    throw 'Copied compile result does not contain the OK conversion result.'
  }
  [ordered]@{
    ok = $true
    operation = 'existing_project_update_regression'
    project_path = $ProjectPath
    source_snapshot_gate = $sourceSnapshotBefore
    mnm_import_plan_gate_path = $mnmImportPlanGatePath
    mnm_import_plan_gate = $mnmImportPlanGateResult
    change_plan_path = $changePlanPath
    compile_result_path = $compileResultPath
    compile_result_contains_ok = $true
    steps = @($steps)
    variable_sets = @($resolvedMnmFiles | ForEach-Object {
      [ordered]@{
        module_name = [string]$_.module_name
        category = [string]$_.category
        global_tsv = [string]$_.global_tsv
        local_tsv = [string]$_.local_tsv
        arguments_tsv = [string]$_.arguments_tsv
      }
    })
  } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $regressionEvidencePath -Encoding UTF8
  Write-RepairResult $true 'pass' ''
  exit 0
} catch {
  Write-RepairResult $false 'fail' $_.Exception.ToString()
  exit 1
}
