param(
  [Parameter(Mandatory=$true)]
  [ValidateSet('new_project','repair_existing_project')]
  [string]$Mode,

  [Parameter(Mandatory=$true)]
  [string]$ScaffoldRoot,

  [Parameter(Mandatory=$true)]
  [string]$OutRoot,

  [string]$ProjectName = '',
  [string]$CpuModel = '',
  [string]$ProjectPath = '',
  [string]$KvsExe = '',
  [string]$ChecklistPath = '',
  [string]$AdminUser = '',
  [string]$AdminPassword = '',
  [string]$AdminCredentialPath = '',
  [string]$SourceSnapshotManifestPath = '',
  [int]$TimeoutSeconds = 600,
  [switch]$AuditVariablePersistence,
  [ValidateSet('Full','NameType')]
  [string]$LocalPasteFormat = 'NameType',
  # Optional override; scaffold.json variables.attributes=full also enables it.
  [switch]$FullGlobalAttributes,
  [switch]$DeleteExistingModulesBeforeImport,
  # Optional mutation-plan JSON for user data types (structures). When present,
  # the plan imports them after project creation and before module imports.
  [string]$StructurePlanPath = '',

  [Parameter(Mandatory=$true)]
  [string]$OutDir
)

$ErrorActionPreference = 'Stop'
$scriptDir = Split-Path -Parent $PSCommandPath
$scriptRoot = Split-Path -Parent $scriptDir
. (Join-Path $scriptRoot 'kv_variable_definition_lib.ps1')

function Resolve-ScaffoldPath([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
  if ([IO.Path]::IsPathRooted($Path)) { return [IO.Path]::GetFullPath($Path) }
  return [IO.Path]::GetFullPath((Join-Path $ScaffoldRoot $Path))
}

function Read-VariableRows([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Variable TSV not found: $Path" }
  $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::Default)
  if ([string]::IsNullOrWhiteSpace($text)) { throw "Variable TSV is empty: $Path" }
  @($text | ConvertFrom-Csv -Delimiter "`t")
}

function Get-ExecutableVariableRowsFromPath([string]$Path, [string]$Scope) {
  @(Get-KvExecutableVariableRows -Rows @(Read-VariableRows $Path) -Scope $Scope)
}

function Get-ExecutableVariableNames([string]$Path, [string]$Scope) {
  @((Get-ExecutableVariableRowsFromPath $Path $Scope) | ForEach-Object { [string]$_.name } | Where-Object { $_ } | Select-Object -Unique)
}

function New-MergedGlobalVariablesTsv([object[]]$Entries, [string]$TargetDir) {
  $header = 'scope' + "`t" + 'owner_program' + "`t" + 'name' + "`t" + 'data_type' + "`t" + 'device' + "`t" + 'initial_value' + "`t" + 'comment' + "`t" + 'evidence' + "`t" + 'status'
  $byName = [ordered]@{}
  foreach ($entry in $Entries) {
    foreach ($row in (Get-ExecutableVariableRowsFromPath $entry.global_tsv 'global')) {
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
  New-Item -ItemType Directory -Force -Path $TargetDir | Out-Null
  $path = Join-Path $TargetDir 'global_variables_merged.tsv'
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

function Add-Arg([System.Collections.Generic.List[string]]$List, [string]$Name, [string]$Value) {
  if ([string]::IsNullOrWhiteSpace($Value)) { return }
  $List.Add($Name)
  $List.Add($Value)
}

function Add-SwitchArg([System.Collections.Generic.List[string]]$List, [string]$Name, [bool]$Enabled) {
  if ($Enabled) { $List.Add($Name) }
}

function New-Step([string]$Name, [string]$ScriptName, [string[]]$Classes, [string[]]$Arguments, [string]$OutDirValue, [string]$Kind = 'script', [int]$TimeoutSeconds = 0) {
  $step = [ordered]@{
    name = $Name
    kind = $Kind
    script_name = $ScriptName
    classes = @($Classes)
    arguments = @($Arguments)
    out_dir = $OutDirValue
  }
  # A per-step hard timeout is enforced by the flat executor (it kills the
  # process tree). Use it for steps whose synchronous UIA calls cannot be
  # cancelled from inside the child.
  if ($TimeoutSeconds -gt 0) { $step.timeout_seconds = $TimeoutSeconds }
  $step
}

try {
  $ScaffoldRoot = [IO.Path]::GetFullPath($ScaffoldRoot)
  $OutRoot = [IO.Path]::GetFullPath($OutRoot)
  $OutDir = [IO.Path]::GetFullPath($OutDir)
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

  $manifestPath = Join-Path $ScaffoldRoot 'scaffold.json'
  if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "scaffold.json not found: $manifestPath" }
  $manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
  if ([int]$manifest.schema_version -ne 2 -or [string]$manifest.variables.schema -ne 'per_mnm') {
    throw 'Unsupported scaffold variable schema. Use schema_version=2 and variables.schema=per_mnm.'
  }
  $manifestVariableAttributes = if ($manifest.variables.attributes) { [string]$manifest.variables.attributes } else { 'name_type' }
  if ($manifestVariableAttributes -notin @('name_type','full')) {
    throw "Unsupported scaffold variables.attributes value: $manifestVariableAttributes. Use name_type or full."
  }
  $effectiveFullGlobalAttributes = [bool]($FullGlobalAttributes -or ($manifestVariableAttributes -eq 'full'))

  if (-not $ProjectName) {
    if ($manifest.project.name) { $ProjectName = [string]$manifest.project.name }
    elseif ($ProjectPath) { $ProjectName = [IO.Path]::GetFileNameWithoutExtension($ProjectPath) }
  }
  if (-not $CpuModel -and $manifest.project.cpu_model) { $CpuModel = [string]$manifest.project.cpu_model }
  if (-not $ProjectName) { throw 'Project name is missing from parameter and scaffold.json.' }
  if ($Mode -eq 'new_project' -and -not $CpuModel) { throw 'CPU model is missing from parameter and scaffold.json.' }

  $manifestChecklist = ''
  if ($manifest.checklist) { $manifestChecklist = Resolve-ScaffoldPath ([string]$manifest.checklist) }
  if (-not $ChecklistPath -and $manifestChecklist) { $ChecklistPath = $manifestChecklist }

  if ($Mode -eq 'repair_existing_project') {
    if (-not $ProjectPath) { throw 'ProjectPath is required for repair_existing_project.' }
    $ProjectPath = [IO.Path]::GetFullPath($ProjectPath)
    if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) { throw "ProjectPath not found: $ProjectPath" }
    if (-not $SourceSnapshotManifestPath) {
      foreach ($candidate in @((Join-Path $ScaffoldRoot 'source_snapshot_manifest.json'), (Join-Path $ScaffoldRoot 'architecture\source_snapshot_manifest.json'))) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { $SourceSnapshotManifestPath = $candidate; break }
      }
    }
    if (-not $SourceSnapshotManifestPath) { throw 'Source snapshot manifest is required for repair_existing_project.' }
    $SourceSnapshotManifestPath = [IO.Path]::GetFullPath($SourceSnapshotManifestPath)
  }

  $runRoot = Join-Path $OutRoot $ProjectName
  $artifactRoot = Join-Path $runRoot 'artifacts'
  $projectRoot = Join-Path $runRoot 'Projects'
  $scaffoldArtifactRoot = Join-Path $artifactRoot 'scaffold'
  New-Item -ItemType Directory -Force -Path $runRoot, $artifactRoot, $scaffoldArtifactRoot | Out-Null
  if ($Mode -eq 'new_project') { New-Item -ItemType Directory -Force -Path $projectRoot | Out-Null }
  Get-ChildItem -LiteralPath $ScaffoldRoot -Force | ForEach-Object {
    Copy-Item -LiteralPath $_.FullName -Destination $scaffoldArtifactRoot -Recurse -Force
  }

  $resolvedMnmFiles = @()
  foreach ($entry in @($manifest.mnm_files)) {
    $mnmPath = Resolve-ScaffoldPath ([string]$entry.path)
    if (-not (Test-Path -LiteralPath $mnmPath -PathType Leaf)) { throw "MNM file not found: $mnmPath" }
    $moduleName = [string]$entry.module_name
    if (-not $moduleName) { $moduleName = [IO.Path]::GetFileNameWithoutExtension($mnmPath) }
    $moduleType = if ($null -ne $entry.module_type -and [string]$entry.module_type -ne '') { [int]$entry.module_type } else { 0 }
    $category = if ($entry.category) { [string]$entry.category } elseif ($moduleType -eq 2) { 'function_block' } else { 'scan' }
    $entryGlobalTsv = Resolve-ScaffoldPath ([string]$entry.variables.global_tsv)
    $entryLocalTsv = Resolve-ScaffoldPath ([string]$entry.variables.local_tsv)
    if (-not (Test-Path -LiteralPath $entryGlobalTsv -PathType Leaf)) { throw "Global variable TSV not found for ${moduleName}: $entryGlobalTsv" }
    if (-not (Test-Path -LiteralPath $entryLocalTsv -PathType Leaf)) { throw "Local variable TSV not found for ${moduleName}: $entryLocalTsv" }
    if ($Mode -eq 'repair_existing_project') {
      $writeRows = @(Get-ExecutableVariableRowsFromPath $entryGlobalTsv 'global') + @(Get-ExecutableVariableRowsFromPath $entryLocalTsv 'local')
      $writeErrors = @(Get-KvVariableWriteCapabilityErrors -Rows $writeRows)
      if ($writeErrors.Count) { throw "$($writeErrors[0].code): $($writeErrors[0].message)" }
    }
    $entryArgumentsTsv = ''
    if ($moduleType -eq 2) {
      $entryArgumentsTsv = Resolve-ScaffoldPath ([string]$entry.arguments.tsv)
      if (-not (Test-Path -LiteralPath $entryArgumentsTsv -PathType Leaf)) { throw "FB arguments TSV not found for ${moduleName}: $entryArgumentsTsv" }
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
  if ($resolvedMnmFiles.Count -eq 0) { throw 'scaffold.json must contain at least one mnm_files entry.' }

  $manifestCustomDataTypes = @()
  if ($manifest.variables -and $manifest.variables.allowed_custom_data_types) { $manifestCustomDataTypes += @($manifest.variables.allowed_custom_data_types) }
  if ($manifest.allowed_custom_data_types) { $manifestCustomDataTypes += @($manifest.allowed_custom_data_types) }
  $fbTypeNames = @(
    @(
      $resolvedMnmFiles | Where-Object { [int]$_.module_type -eq 2 } | ForEach-Object { [string]$_.module_name }
      $manifestCustomDataTypes
    ) |
      ForEach-Object { ([string]$_).Trim() } |
      Where-Object { $_ } |
      Select-Object -Unique
  )

  $variableArtifactDir = Join-Path $artifactRoot 'variables'
  $mergedGlobal = New-MergedGlobalVariablesTsv $resolvedMnmFiles $variableArtifactDir
  $projectPathForRun = if ($Mode -eq 'new_project') { Join-Path (Join-Path $projectRoot $ProjectName) ($ProjectName + '.kpr') } else { $ProjectPath }
  if ($Mode -eq 'new_project' -and (Test-Path -LiteralPath $projectPathForRun)) { throw "KV_NEW_PROJECT_ALREADY_EXISTS: use a fresh output directory or the existing-project repair workflow: $projectPathForRun" }
  $projectNeedle = [IO.Path]::GetFileNameWithoutExtension($projectPathForRun)
  $projectSearchRoot = if ($Mode -eq 'new_project') { Join-Path $projectRoot $ProjectName } else { Split-Path -Parent $ProjectPath }
  $resultPath = if ($Mode -eq 'new_project') { Join-Path $runRoot 'mvp_result.json' } else { Join-Path $runRoot 'repair_result.json' }

  $steps = [System.Collections.Generic.List[object]]::new()
  # The flat executor's preflight requires the UI guard and agent boundary gates
  # to be the first two steps of every plan; scaffold validation follows them.
  $steps.Add((New-Step 'assert_ui_guard_usage' 'assert_kv_mvp_ui_guard_usage.ps1' @('gate') @('-ScriptsRoot',$scriptRoot,'-OutDir',(Join-Path $artifactRoot 'ui_guard_usage')) (Join-Path $artifactRoot 'ui_guard_usage') 'gate'))
  $steps.Add((New-Step 'assert_agent_boundary' 'assert_kv_mvp_agent_boundary.ps1' @('gate') @('-ScriptsRoot',$scriptRoot,'-MvpScriptsRoot',(Join-Path $scriptRoot 'runner_children'),'-OutDir',(Join-Path $artifactRoot 'agent_boundary')) (Join-Path $artifactRoot 'agent_boundary') 'gate'))
  $steps.Add((New-Step 'validate_scaffold' 'validate_kv_mvp_scaffold.ps1' @('customer_scaffold_tool') @('-ScaffoldRoot',$ScaffoldRoot,'-ChecklistPath',$ChecklistPath,'-OutDir',(Join-Path $artifactRoot 'scaffold_validation')) (Join-Path $artifactRoot 'scaffold_validation') 'gate'))

  if ($Mode -eq 'repair_existing_project') {
    $sourceGateDir = Join-Path $artifactRoot 'source_snapshot_gate'
    $steps.Add((New-Step 'assert_existing_project_source_snapshot' 'assert_kv_existing_project_snapshot.ps1' @('customer_non_ui_tool') @('-ProjectPath',$ProjectPath,'-SnapshotManifestPath',$SourceSnapshotManifestPath,'-OutDir',$sourceGateDir) $sourceGateDir 'gate'))
    $planGateArgs = @('-ScaffoldRoot',$ScaffoldRoot,'-SourceSnapshotManifestPath',$SourceSnapshotManifestPath,'-SourceSnapshotGateResultPath',(Join-Path $sourceGateDir 'existing_project_snapshot_gate.json'),'-OutDir',(Join-Path $artifactRoot 'mnm_import_plan_gate'))
    if ($DeleteExistingModulesBeforeImport) { $planGateArgs += '-DeleteExistingModulesBeforeImport' }
    $steps.Add((New-Step 'assert_mnm_import_plan' 'assert_kv_mnm_import_plan.ps1' @('customer_scaffold_tool') $planGateArgs (Join-Path $artifactRoot 'mnm_import_plan_gate') 'gate'))
  } else {
    $createArgs = [System.Collections.Generic.List[string]]::new()
    Add-Arg -List $createArgs -Name '-ProjectName' -Value $ProjectName
    Add-Arg -List $createArgs -Name '-ProjectRoot' -Value $projectRoot
    Add-Arg -List $createArgs -Name '-CpuModel' -Value $CpuModel
    Add-Arg -List $createArgs -Name '-OutDir' -Value (Join-Path $artifactRoot 'create_project')
    Add-Arg -List $createArgs -Name '-ChecklistPath' -Value $ChecklistPath
    Add-Arg -List $createArgs -Name '-TimeoutSeconds' -Value '120'
    # Keep an already visible, PID-bound KV STUDIO instance when possible.
    # Restarting here can put Kvs into its standby shell and lose foreground focus.
    Add-SwitchArg -List $createArgs -Name '-RestartKvs' -Enabled $false
    Add-Arg -List $createArgs -Name '-KvsExe' -Value $KvsExe
    Add-Arg -List $createArgs -Name '-AdminUser' -Value $AdminUser
    Add-Arg -List $createArgs -Name '-AdminPassword' -Value $AdminPassword
    Add-Arg -List $createArgs -Name '-AdminCredentialPath' -Value $AdminCredentialPath
    $steps.Add((New-Step 'create_project' 'create_project_local_guarded.ps1' @('runner_child_approved') $createArgs.ToArray() (Join-Path $artifactRoot 'create_project') 'runner_child'))
  }
  # create_project starts KV STUDIO without the project path on its command
  # line, so later steps must bind through the creation evidence instead of
  # command-line matching.
  $createdProjectResultPath = if ($Mode -eq 'new_project') { Join-Path (Join-Path $artifactRoot 'create_project') 'create_project_result.json' } else { '' }

  if ($StructurePlanPath) {
    $structurePlanFull = [IO.Path]::GetFullPath($StructurePlanPath)
    if (-not (Test-Path -LiteralPath $structurePlanFull -PathType Leaf)) { throw "KV_STRUCTURE_PLAN_MISSING: $structurePlanFull" }
    $structuresOut = Join-Path $artifactRoot 'structures'
    $steps.Add((New-Step 'import_structures' 'mutate_structure_definitions_guarded.ps1' @('runner_child_approved') @('-ProjectPath',$projectPathForRun,'-PlanPath',$structurePlanFull,'-OutDir',$structuresOut) $structuresOut 'runner_child' 1800))
  }

  $defaultProgramName = 'Main'
  $scaffoldModuleNames = @($resolvedMnmFiles | ForEach-Object { [string]$_.module_name })
  $scaffoldHasDefaultProgram = (@($scaffoldModuleNames | Where-Object { $_ -ieq $defaultProgramName }).Count -gt 0)
  $stageModuleName = ''
  $stageMnmPath = ''
  if ($Mode -eq 'new_project' -and $resolvedMnmFiles.Count -gt 0 -and $scaffoldHasDefaultProgram) {
    # KV STUDIO refuses to delete the last program, so a scaffold module named
    # Main cannot replace the fresh project's default Main by delete-first.
    # Import a disposable staging program first; then the real Main can be
    # imported with pre-delete, and the staging program is removed afterwards.
    $stageModuleName = 'KV_Stage_Temp'
    $suffix = 1
    while (@($scaffoldModuleNames | Where-Object { $_ -ieq $stageModuleName }).Count -gt 0) {
      $suffix++
      $stageModuleName = "KV_Stage_Temp$suffix"
    }
    $stageDir = Join-Path $artifactRoot 'staging'
    New-Item -ItemType Directory -Force -Path $stageDir | Out-Null
    $stageMnmPath = Join-Path $stageDir ($stageModuleName + '.mnm')
    $stageText = "DEVICE:63`r`n;MODULE:$stageModuleName`r`n;MODULE_TYPE:0`r`nLD X0`r`nEND`r`nENDH`r`n"
    [IO.File]::WriteAllText($stageMnmPath, $stageText, (New-Object System.Text.UnicodeEncoding($false, $true)))
  }
  if ($stageModuleName) {
    $stageArgs = [System.Collections.Generic.List[string]]::new()
    Add-Arg -List $stageArgs -Name '-MnmPath' -Value $stageMnmPath
    Add-Arg -List $stageArgs -Name '-ProjectPath' -Value $projectPathForRun
    Add-Arg -List $stageArgs -Name '-OutDir' -Value (Join-Path $artifactRoot 'stage_default_program')
    Add-Arg -List $stageArgs -Name '-ExpectedModuleName' -Value $stageModuleName
    Add-Arg -List $stageArgs -Name '-ExpectedCategory' -Value 'scan'
    Add-Arg -List $stageArgs -Name '-ProjectSearchRoot' -Value $projectSearchRoot
    if ($createdProjectResultPath) { Add-Arg -List $stageArgs -Name '-CreatedProjectResultPath' -Value $createdProjectResultPath }
    Add-Arg -List $stageArgs -Name '-ChecklistPath' -Value $ChecklistPath
    Add-SwitchArg -List $stageArgs -Name '-SaveAfterImport' -Enabled $true
    Add-Arg -List $stageArgs -Name '-RestartKvs' -Value 'false'
    Add-Arg -List $stageArgs -Name '-KvsExe' -Value $KvsExe
    $steps.Add((New-Step 'stage_default_program' 'import_mnm_guarded.ps1' @('runner_child_approved') $stageArgs.ToArray() (Join-Path $artifactRoot 'stage_default_program') 'runner_child'))
  }

  for ($i = 0; $i -lt $resolvedMnmFiles.Count; $i++) {
    $entry = $resolvedMnmFiles[$i]
    $importArgs = [System.Collections.Generic.List[string]]::new()
    Add-Arg -List $importArgs -Name '-MnmPath' -Value $entry.path
    Add-Arg -List $importArgs -Name '-ProjectPath' -Value $projectPathForRun
    Add-Arg -List $importArgs -Name '-OutDir' -Value (Join-Path $artifactRoot ("import_mnm_$($i + 1)"))
    Add-Arg -List $importArgs -Name '-ExpectedModuleName' -Value $entry.module_name
    Add-Arg -List $importArgs -Name '-ExpectedCategory' -Value $entry.category
    Add-Arg -List $importArgs -Name '-ProjectSearchRoot' -Value $projectSearchRoot
    if ($createdProjectResultPath) { Add-Arg -List $importArgs -Name '-CreatedProjectResultPath' -Value $createdProjectResultPath }
    Add-Arg -List $importArgs -Name '-ChecklistPath' -Value $ChecklistPath
    Add-SwitchArg -List $importArgs -Name '-SaveAfterImport' -Enabled $true
    # A fresh KV STUDIO project already contains a default 'Main' module. Give
    # every new-project import the pre-delete flag so a scaffold module named
    # Main replaces that placeholder instead of failing on a same-name conflict;
    # the runner no-ops when the name is absent. Repair keeps the explicit gate.
    if ($Mode -eq 'new_project' -or $DeleteExistingModulesBeforeImport) { Add-SwitchArg -List $importArgs -Name '-DeleteExistingModuleBeforeImport' -Enabled $true }
    Add-Arg -List $importArgs -Name '-RestartKvs' -Value $(if ($Mode -eq 'repair_existing_project' -and $i -eq 0) { 'true' } else { 'false' })
    Add-Arg -List $importArgs -Name '-KvsExe' -Value $KvsExe
    $steps.Add((New-Step "$(if ($Mode -eq 'repair_existing_project') { 'repair_' } else { '' })import_mnm_$($i + 1)" 'import_mnm_guarded.ps1' @('runner_child_approved') $importArgs.ToArray() (Join-Path $artifactRoot ("import_mnm_$($i + 1)")) 'runner_child' 240))

    if ($Mode -eq 'new_project') {
      $placementDir = Join-Path (Join-Path $artifactRoot 'module_placement') $entry.module_name
      $steps.Add((New-Step "verify_module_placement_$($entry.module_name)" 'assert_kv_module_placement.ps1' @('workflow_tool') @('-ProjectTreePath',(Join-Path $projectSearchRoot 'WsTreeEnv.xml'),'-ModuleName',$entry.module_name,'-Category',$entry.category,'-OutDir',$placementDir) $placementDir 'tool'))
    }
  }

  # Remove the disposable staging program (when Main was replaced) or the
  # untouched default Main (when the scaffold does not declare it), so the saved
  # project contains exactly the scaffold programs.
  $cleanupModuleName = if ($stageModuleName) { $stageModuleName } else { $defaultProgramName }
  if ($Mode -eq 'new_project' -and $resolvedMnmFiles.Count -gt 0) {
    $cleanupOut = Join-Path $artifactRoot 'delete_default_program'
    $cleanupArgs = @('-ProjectPath',$projectPathForRun,'-ExpectedModuleName',$cleanupModuleName,'-DeleteOnly','-RestartKvs','false','-ChecklistPath',$ChecklistPath,'-OutDir',$cleanupOut,'-KvsExe',$KvsExe)
    if ($createdProjectResultPath) { $cleanupArgs += @('-CreatedProjectResultPath',$createdProjectResultPath) }
    $steps.Add((New-Step $(if ($stageModuleName) { 'delete_staged_program' } else { 'delete_default_program' }) 'import_mnm_guarded.ps1' @('runner_child_approved') $cleanupArgs $cleanupOut 'runner_child'))
  }

  $fbArgumentRoot = Join-Path $artifactRoot 'set_fb_arguments'
  for ($i = 0; $i -lt $resolvedMnmFiles.Count; $i++) {
    $entry = $resolvedMnmFiles[$i]
    if ([int]$entry.module_type -ne 2) { continue }
    $safeModule = ($entry.module_name -replace '[^A-Za-z0-9_.-]+', '_')
    $fbOutDir = Join-Path $fbArgumentRoot ('module_{0:D2}_{1}' -f ($i + 1), $safeModule)
    $fbArgArgs = @('-ProjectPath',$projectPathForRun,'-FbModuleName',$entry.module_name,'-ArgumentsTsv',$entry.arguments_tsv,'-ChecklistPath',$ChecklistPath,'-OutDir',$fbOutDir)
    if ($fbTypeNames.Count -gt 0) { $fbArgArgs += @('-AllowedCustomDataTypes',($fbTypeNames -join ',')) }
    $steps.Add((New-Step "$(if ($Mode -eq 'repair_existing_project') { 'repair_' } else { '' })set_fb_arguments_$($entry.module_name)" 'set_fb_arguments_guarded.ps1' @('runner_child_approved') $fbArgArgs $fbOutDir 'runner_child'))
  }

  $setVariablesRoot = Join-Path $artifactRoot 'set_variables'
  $globalVariablesPasted = $false
  $setVariableSummaries = @()
  for ($i = 0; $i -lt $resolvedMnmFiles.Count; $i++) {
    $entry = $resolvedMnmFiles[$i]
    $safeModule = ($entry.module_name -replace '[^A-Za-z0-9_.-]+', '_')
    $moduleOutDir = Join-Path $setVariablesRoot ('module_{0:D2}_{1}' -f ($i + 1), $safeModule)
    $setArgs = [System.Collections.Generic.List[string]]::new()
    Add-Arg -List $setArgs -Name '-ProjectPath' -Value $projectPathForRun
    Add-Arg -List $setArgs -Name '-GlobalVariablesTsv' -Value $mergedGlobal.path
    Add-Arg -List $setArgs -Name '-LocalVariablesTsv' -Value $entry.local_tsv
    Add-Arg -List $setArgs -Name '-LocalProgramName' -Value $entry.module_name
    Add-Arg -List $setArgs -Name '-LocalPasteFormat' -Value $LocalPasteFormat
    if ($effectiveFullGlobalAttributes) { Add-SwitchArg -List $setArgs -Name '-FullGlobalAttributes' -Enabled $true }
    if ($Mode -eq 'new_project') { Add-SwitchArg -List $setArgs -Name '-NewProjectDefaults' -Enabled $true }
    Add-Arg -List $setArgs -Name '-ChecklistPath' -Value $ChecklistPath
    Add-Arg -List $setArgs -Name '-OutDir' -Value $moduleOutDir
    if ($Mode -eq 'repair_existing_project') { Add-SwitchArg -List $setArgs -Name '-AppendGlobalVariables' -Enabled $true }
    if ($fbTypeNames.Count -gt 0) { Add-Arg -List $setArgs -Name '-AllowedCustomDataTypes' -Value ($fbTypeNames -join ',') }
    if ($globalVariablesPasted -or [int]$mergedGlobal.executable_global_variable_count -eq 0) { Add-SwitchArg -List $setArgs -Name '-SkipGlobal' -Enabled $true }
    # A variable step is not successful until the saved grids have been
    # closed, reopened, copied, and matched against the requested rows.
    Add-SwitchArg -List $setArgs -Name '-AuditPersistence' -Enabled $true
    if ($AuditVariablePersistence) {
      $forbiddenLocalNames = @()
      for ($j = 0; $j -lt $resolvedMnmFiles.Count; $j++) {
        if ($j -eq $i) { continue }
        $forbiddenLocalNames += @(Get-ExecutableVariableNames $resolvedMnmFiles[$j].local_tsv 'local')
      }
      $ownedLocalNames = @(Get-ExecutableVariableNames $entry.local_tsv 'local')
      $forbiddenLocalNames = @($forbiddenLocalNames | Where-Object { $_ -and $ownedLocalNames -notcontains $_ } | Select-Object -Unique)
      if ($forbiddenLocalNames.Count -gt 0) { Add-Arg -List $setArgs -Name '-ForbiddenLocalNamesCsv' -Value ($forbiddenLocalNames -join ',') }
    }
    $steps.Add((New-Step "$(if ($Mode -eq 'repair_existing_project') { 'repair_' } else { '' })set_variables_$($entry.module_name)" 'set_variables_guarded.ps1' @('runner_child_approved') $setArgs.ToArray() $moduleOutDir 'runner_child' 600))
    if ([int]$mergedGlobal.executable_global_variable_count -gt 0) { $globalVariablesPasted = $true }
    $setVariableSummaries += [pscustomobject]@{
      module_name = $entry.module_name
      global_pasted_in_this_step = (-not ($setArgs.ToArray() -contains '-SkipGlobal'))
      local_tsv = $entry.local_tsv
      result_path = Join-Path $moduleOutDir 'set_variables_result.json'
      validation_path = Join-Path $moduleOutDir 'variable_persistence_validation.json'
    }
  }

  $compileOutDir = Join-Path $artifactRoot 'compile_convert'
  $compileStepArgs = @('-ProjectPath',$projectPathForRun,'-OutDir',$compileOutDir,'-WaitSeconds','40','-ChecklistPath',$ChecklistPath,'-ConvertAction','CtrlF9')
  if ($createdProjectResultPath) { $compileStepArgs += @('-CreatedProjectResultPath',$createdProjectResultPath) }
  $steps.Add((New-Step "$(if ($Mode -eq 'repair_existing_project') { 'repair_' } else { '' })compile_convert" 'compile_and_copy_result_bounded.ps1' @('runner_child_approved') $compileStepArgs $compileOutDir 'runner_child' 300))
  $copyOutDir = Join-Path $artifactRoot 'copy_result'
  $copyStepArgs = @('-ProjectNeedle',$projectNeedle,'-ProjectPath',$projectPathForRun,'-OutDir',$copyOutDir,'-ChecklistPath',$ChecklistPath,'-MaxLookupMs','8000')
  if ($createdProjectResultPath) { $copyStepArgs += @('-CreatedProjectResultPath',$createdProjectResultPath) }
  # The result lookup calls synchronous UIA APIs that cannot be cancelled from
  # inside the child; the executor's per-step timeout is the hard bound.
  $steps.Add((New-Step "$(if ($Mode -eq 'repair_existing_project') { 'repair_' } else { '' })copy_convert_result" 'copy_convert_result_from_tree_handle.ps1' @('runner_child_approved') $copyStepArgs $copyOutDir 'runner_child' 120))

  # Saved scan-order evidence: read the saved project tree (offline inventory)
  # and compare the module schedule with the scaffold import order. Extra
  # modules are tolerated because a fresh KV STUDIO project keeps its default
  # Main until the still-open replacement gap is fixed.
  $inventoryOutDir = Join-Path $artifactRoot 'project_inventory'
  $steps.Add((New-Step 'export_project_inventory' 'export_kv_project_inventory.ps1' @('customer_non_ui_tool') @('-ProjectPath',$projectPathForRun,'-OutDir',$inventoryOutDir) $inventoryOutDir 'tool'))
  $scanOrderOutDir = Join-Path $artifactRoot 'scan_order'
  $scanOrderInventory = Join-Path $inventoryOutDir 'project_inventory.json'
  $steps.Add((New-Step 'verify_saved_scan_order' 'assert_kv_scan_order.ps1' @('customer_non_ui_tool') @('-ScaffoldPath',$manifestPath,'-ActualInventory',$scanOrderInventory,'-OutDir',$scanOrderOutDir,'-AllowExtraModules') $scanOrderOutDir 'tool'))

  $plan = [ordered]@{
    ok = $true
    schema_version = 1
    operation = $Mode
    scaffold_root = $ScaffoldRoot
    scaffold_manifest = $manifestPath
    project_name = $ProjectName
    cpu_model = $CpuModel
    project_path = $projectPathForRun
    project_needle = $projectNeedle
    run_root = $runRoot
    artifact_root = $artifactRoot
    result_path = $resultPath
    checklist_path = $ChecklistPath
    timeout_seconds = $TimeoutSeconds
    source_snapshot_manifest = $SourceSnapshotManifestPath
    delete_existing_modules_before_import = [bool]($DeleteExistingModulesBeforeImport -or $Mode -eq 'new_project')
    structure_plan_path = $(if ($StructurePlanPath) { [IO.Path]::GetFullPath($StructurePlanPath) } else { '' })
    default_program_staging = [ordered]@{
      scaffold_contains_default_program = $scaffoldHasDefaultProgram
      stage_module_name = $stageModuleName
      stage_mnm_path = $stageMnmPath
      cleanup_module_name = $cleanupModuleName
    }
    mnm_files = @($resolvedMnmFiles)
    merged_global_variables_tsv = $mergedGlobal.path
    executable_global_variable_count = $mergedGlobal.executable_global_variable_count
    variable_sets = @($resolvedMnmFiles | ForEach-Object {
      [pscustomobject]@{ module_name = $_.module_name; category = $_.category; global_tsv = $_.global_tsv; local_tsv = $_.local_tsv; arguments_tsv = $_.arguments_tsv }
    })
    set_variable_summaries = $setVariableSummaries
    compile_result_path = Join-Path $copyOutDir 'compile_result_copied.txt'
    project_inventory_path = $scanOrderInventory
    scan_order_result_path = Join-Path $scanOrderOutDir 'scan_order_verification.json'
    steps = @($steps)
  }
  $planPath = Join-Path $OutDir 'execution_plan.json'
  $plan | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $planPath -Encoding UTF8
  $plan.plan_path = $planPath
  $plan | ConvertTo-Json -Depth 12
  exit 0
} catch {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  [ordered]@{
    ok = $false
    error_code = 'KV_EXECUTION_PLAN_FAILED'
    operation = 'new KV MVP execution plan'
    mode = $Mode
    scaffold_root = $ScaffoldRoot
    message = $_.Exception.ToString()
  } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'execution_plan_result.json') -Encoding UTF8
  exit 1
}
