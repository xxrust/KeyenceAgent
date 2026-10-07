# File-only validation. Parsing a runner's parameter AST never executes it.
function Get-KvPlanStepParameters([object]$Step, [string]$ScriptPath) {
  $tokens=$null; $errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($ScriptPath,[ref]$tokens,[ref]$errors)
  if ($errors.Count) { throw "KV_PLAN_SCRIPT_PARSE_FAILED: $ScriptPath" }
  $schema=@{}; $aliases=@{}
  foreach ($p in @($ast.ParamBlock.Parameters)) {
    $name=$p.Name.VariablePath.UserPath
    $type=$p.StaticType
    $required=$false; $allowed=@(); $allowEmpty=$false
    foreach ($attribute in @($p.Attributes)) {
      $attributeName=$attribute.TypeName.Name -replace 'Attribute$',''
      if ($attributeName -eq 'Parameter') {
        foreach ($named in @($attribute.NamedArguments)) {
          if ($named.ArgumentName -eq 'Mandatory') { $required=$named.ExpressionOmitted -or $named.Argument.Extent.Text -eq '$true' }
        }
      } elseif ($attributeName -eq 'ValidateSet') {
        $allowed=@($attribute.PositionalArguments | ForEach-Object { $_.SafeGetValue() })
      } elseif ($attributeName -eq 'Alias') {
        foreach ($a in @($attribute.PositionalArguments)) { $aliases[[string]$a.SafeGetValue()]=$name }
      } elseif ($attributeName -eq 'AllowEmptyString') { $allowEmpty=$true }
    }
    $schema[$name]=@{type=$type;required=$required;allowed=$allowed;allow_empty=$allowEmpty}
  }
  $values=@{}
  $hasTyped=$null -ne $Step.parameters
  if ($hasTyped -and $null -ne $Step.arguments -and @($Step.arguments).Count -gt 0) { throw "KV_PLAN_STEP_ARGUMENTS_AMBIGUOUS: $($Step.name)" }
  $pairs=[Collections.Generic.List[object]]::new()
  if ($hasTyped) {
    foreach ($property in $Step.parameters.PSObject.Properties) { $pairs.Add(@{name=$property.Name;value=$property.Value}) }
  } else {
    $args=@($Step.arguments)
    for ($i=0;$i -lt $args.Count;$i++) {
      $token=[string]$args[$i]
      if ($token -notmatch '^-(\w+)$') { throw "KV_PLAN_PARAMETER_TOKEN_INVALID: $($Step.name) $token" }
      $name=$matches[1]
      if ($aliases.ContainsKey($name)) { $name=$aliases[$name] }
      if (-not $schema.ContainsKey($name)) { throw "KV_PLAN_PARAMETER_UNKNOWN: $($Step.name) $name" }
      $value=$true
      if ($schema[$name].type -ne [Management.Automation.SwitchParameter]) {
        if (++$i -ge $args.Count -or ([string]$args[$i] -match '^-[A-Za-z]\w*$')) { throw "KV_PLAN_PARAMETER_VALUE_MISSING: $($Step.name) $name" }
        $value=$args[$i]
      }
      $pairs.Add(@{name=$name;value=$value})
    }
  }
  foreach ($pair in $pairs) {
    $name=$pair.name
    if ($aliases.ContainsKey($name)) { $name=$aliases[$name] }
    if (-not $schema.ContainsKey($name)) { throw "KV_PLAN_PARAMETER_UNKNOWN: $($Step.name) $name" }
    if ($values.ContainsKey($name)) { throw "KV_PLAN_PARAMETER_DUPLICATE: $($Step.name) $name" }
    $spec=$schema[$name]; $value=$pair.value; $type=$spec.type
    if ($null -eq $value -and $spec.required) { throw "KV_PLAN_PARAMETER_REQUIRED: $($Step.name) $name" }
    if ($type -eq [bool] -or $type -eq [Management.Automation.SwitchParameter]) {
      if ($value -isnot [bool]) { throw "KV_PLAN_PARAMETER_TYPE_INVALID: $($Step.name) $name requires boolean" }
    } elseif ($type -eq [string]) {
      if ($null -ne $value -and $value -isnot [string]) { throw "KV_PLAN_PARAMETER_TYPE_INVALID: $($Step.name) $name requires string" }
      if ($spec.required -and -not $spec.allow_empty -and [string]::IsNullOrWhiteSpace([string]$value)) { throw "KV_PLAN_PARAMETER_REQUIRED: $($Step.name) $name" }
    } elseif ($type.IsArray -and $type.GetElementType() -eq [string]) {
      if (@($value | Where-Object { $_ -isnot [string] }).Count) { throw "KV_PLAN_PARAMETER_TYPE_INVALID: $($Step.name) $name requires strings" }
    } elseif ($type -in @([int],[long],[double],[decimal],[uint32],[uint64],[int16],[byte])) {
      try {
        if ($value -is [bool] -or $value -is [array]) { throw 'Not a number' }
        if ($type -notin @([double],[decimal]) -and [string]$value -notmatch '^-?\d+$') { throw 'Not an integer' }
        $null=[Convert]::ChangeType($value,$type,[Globalization.CultureInfo]::InvariantCulture)
      } catch { throw "KV_PLAN_PARAMETER_TYPE_INVALID: $($Step.name) $name requires $type" }
    }
    if ($spec.allowed.Count) {
      foreach ($v in @($value)) { if ($v -notin $spec.allowed) { throw "KV_PLAN_PARAMETER_VALUE_INVALID: $($Step.name) $name" } }
    }
    $values[$name]=$value
  }
  foreach ($name in $schema.Keys) {
    if ($schema[$name].required -and -not $values.ContainsKey($name)) { throw "KV_PLAN_PARAMETER_REQUIRED: $($Step.name) $name" }
  }
  return $values
}

function Test-KvPathWithin([string]$Path,[string]$Directory) {
  if (-not $Directory) { return $false }
  $base=[IO.Path]::GetFullPath($Directory).TrimEnd('\','/')
  return $Path.Equals($base,[StringComparison]::OrdinalIgnoreCase) -or $Path.StartsWith($base+[IO.Path]::DirectorySeparatorChar,[StringComparison]::OrdinalIgnoreCase)
}

function Assert-KvPlanInputsUnchanged([object[]]$Inputs) {
  foreach ($inputFile in @($Inputs)) {
    if (-not (Test-Path -LiteralPath $inputFile.path -PathType Leaf) -or (Get-FileHash -LiteralPath $inputFile.path -Algorithm SHA256).Hash -ne $inputFile.sha256) {
      throw "KV_PLAN_INPUT_CHANGED: $($inputFile.path)"
    }
  }
}

function Assert-KvCompletePlanSteps([object]$Plan,[hashtable]$Prepared,[string]$ScriptsRoot) {
  $steps=@($Plan.steps)
  if ($steps.Count -lt 3 -or $steps[2].name -cne 'module_contract' -or $Prepared['module_contract'].path -ne (Join-Path $ScriptsRoot 'gates/assert_kv_complete_module.ps1')) { throw 'KV_COMPLETE_PLAN_CONTRACT_GATE_REQUIRED' }
  . (Join-Path $ScriptsRoot 'workflow_tools/kv_complete_module_contract.ps1')
  $contractPath=[IO.Path]::GetFullPath([string]$Prepared['module_contract'].parameters.ContractPath)
  $checked=Read-KvCompleteModuleContract $contractPath ([string]$Plan.project_path)
  $c=$checked.contract
  $required=@(
    @{name='module_contract';script='gates/assert_kv_complete_module.ps1'},
    @{name='import';script='runner_children/import_mnm_guarded.ps1'}
  )
  if ($c.category -eq 'function_block') { $required+=@{name='arguments';script='runner_children/set_fb_arguments_guarded.ps1'} }
  $required+=@{name='locals';script='runner_children/set_variables_guarded.ps1'}
  if ($c.category -eq 'function_block') { $required+=@{name='arguments_readback';script='runner_children/set_fb_arguments_guarded.ps1'} }
  $required+=@(
    @{name='compile';script='runner_children/compile_and_copy_result_bounded.ps1'},
    @{name='compile_result';script='runner_children/copy_convert_result_from_tree_handle.ps1'},
    @{name='export';script='runner_children/export_mnm_browse_default_folder_guarded.ps1'},
    @{name='verify';script='workflow_tools/assert_kv_complete_module_result.ps1'}
  )
  if ($steps.Count -ne $required.Count+2) { throw 'KV_COMPLETE_PLAN_STEPS_REQUIRED' }
  for ($i=0;$i -lt $required.Count;$i++) {
    $s=$steps[$i+2]; $expected=$required[$i]
    if ($s.name -cne $expected.name -or $Prepared[[string]$s.name].path -ne (Join-Path $ScriptsRoot $expected.script)) { throw "KV_COMPLETE_PLAN_STEP_ORDER: $($expected.name)" }
  }
  if ($Plan.require_compile_result -isnot [bool] -or -not $Plan.require_compile_result) { throw 'KV_COMPLETE_PLAN_COMPILE_REQUIRED' }
  $import=$Prepared['import'].parameters
  if ($import.MnmPath -ne $c.body_path -or $import.ExpectedModuleName -cne $c.module_name -or $import.ExpectedCategory -cne $c.category -or ($import.ParentPath | ConvertTo-Json -Compress) -cne ($c.parent_path | ConvertTo-Json -Compress) -or $import.SaveAfterImport -isnot [bool] -or -not $import.SaveAfterImport) { throw 'KV_COMPLETE_PLAN_IMPORT_MISMATCH' }
  if ($c.category -eq 'function_block') {
    $arguments=$Prepared['arguments'].parameters
    if ($arguments.FbModuleName -cne $c.module_name -or $arguments.ArgumentsTsv -ne $c.arguments_path -or $arguments.SnapshotOnly -eq $true) { throw 'KV_COMPLETE_PLAN_ARGUMENTS_MISMATCH' }
    $readback=$Prepared['arguments_readback'].parameters
    if ($readback.FbModuleName -cne $c.module_name -or $readback.SnapshotOnly -isnot [bool] -or -not $readback.SnapshotOnly -or $readback.ContainsKey('ArgumentsTsv') -or [IO.Path]::GetFullPath([string]$readback.OutDir) -ne (Join-Path ([IO.Path]::GetFullPath([string]$Plan.artifact_root)) 'arguments_readback')) { throw 'KV_COMPLETE_PLAN_ARGUMENTS_READBACK_MISMATCH' }
    $readbackFiles=@($Prepared['arguments_readback'].contract.files)
    if ($readbackFiles.Count -ne 1 -or $readbackFiles[0] -ne 'fb_snapshot_result.json') { throw 'KV_COMPLETE_PLAN_ARGUMENTS_READBACK_CONTRACT' }
  }
  $locals=$Prepared['locals'].parameters
  if ($locals.LocalProgramName -cne $c.module_name -or $locals.LocalVariablesTsv -ne $c.locals_path -or $locals.AuditPersistence -isnot [bool] -or -not $locals.AuditPersistence -or $locals.SkipGlobal -isnot [bool] -or -not $locals.SkipGlobal -or $locals.SnapshotOnly -eq $true -or $locals.KeepVariableEditorOpen -eq $true) { throw 'KV_COMPLETE_PLAN_LOCALS_MISMATCH' }
  $compileResult=$Prepared['compile_result'].parameters
  if ([IO.Path]::GetFullPath([string]$Plan.compile_result_path) -ne (Join-Path $compileResult.OutDir 'compile_result_copied.txt')) { throw 'KV_COMPLETE_PLAN_COMPILE_RESULT_MISMATCH' }
  $export=$Prepared['export'].parameters
  if ([IO.Path]::GetFullPath([string]$export.ExportDir) -ne (Split-Path -Parent ([IO.Path]::GetFullPath([string]$Plan.project_path)))) { throw 'KV_COMPLETE_PLAN_EXPORT_MISMATCH' }
  $verify=$Prepared['verify'].parameters
  if ([IO.Path]::GetFullPath([string]$verify.ContractPath) -ne $contractPath -or [IO.Path]::GetFullPath([string]$verify.ArtifactsRoot) -ne [IO.Path]::GetFullPath([string]$Plan.artifact_root)) { throw 'KV_COMPLETE_PLAN_VERIFY_MISMATCH' }
  return @($checked.input_paths)
}

function Assert-KvStPlanSteps([object]$Plan,[hashtable]$Prepared,[string]$ScriptsRoot) {
  . (Join-Path $ScriptsRoot 'workflow_tools/kv_st_module_contract.ps1')
  $steps=@($Plan.steps)
  if ($steps[2].name -cne 'module_contract' -or -not $Prepared.ContainsKey('module_contract') -or $Prepared.module_contract.path -ne (Join-Path $ScriptsRoot 'gates/assert_kv_st_module.ps1')) { throw 'KV_ST_PLAN_CONTRACT_GATE_REQUIRED' }
  $contractPath=[IO.Path]::GetFullPath([string]$Prepared.module_contract.parameters.ContractPath)
  $checked=Read-KvStModuleContract $contractPath ([string]$Plan.project_path)
  $c=$checked.contract
  $required=@(@{name='module_contract';path='gates/assert_kv_st_module.ps1'},@{name='import';path='runner_children/import_mnm_guarded.ps1'})
  if($c.category -eq 'function_block'){$required+=@{name='arguments';path='runner_children/set_fb_arguments_guarded.ps1'}}
  $required+=@{name='locals';path='runner_children/set_variables_guarded.ps1'}
  if($c.category -eq 'function_block'){$required+=@{name='arguments_readback';path='runner_children/set_fb_arguments_guarded.ps1'}}
  $required+=@(@{name='compile';path='runner_children/compile_and_copy_result_bounded.ps1'},@{name='compile_result';path='runner_children/copy_convert_result_from_tree_handle.ps1'},@{name='export';path='runner_children/export_mnm_browse_default_folder_guarded.ps1'},@{name='verify';path='workflow_tools/assert_kv_st_module_result.ps1'})
  if($steps.Count -ne $required.Count+2){throw 'KV_ST_PLAN_STEPS_REQUIRED'}
  for($index=0;$index -lt $required.Count;$index++){
    $expected=$required[$index];$step=$steps[$index+2]
    if($step.name -cne $expected.name -or $Prepared[[string]$step.name].path -ne (Join-Path $ScriptsRoot $expected.path)){throw "KV_ST_PLAN_STEP_ORDER: $($expected.name)"}
  }
  $import=$Prepared.import.parameters
  if($import.MnmPath -cne $c.body_path -or $import.ExpectedModuleName -cne $c.module_name -or $import.ExpectedCategory -cne $c.category -or ($import.ParentPath -join "`n") -cne ($c.parent_path -join "`n") -or $import.SaveAfterImport -isnot [bool] -or -not $import.SaveAfterImport -or $import.RestartKvs -isnot [bool] -or $import.RestartKvs -or $import.DeleteExistingModuleBeforeImport -eq $true){throw 'KV_ST_PLAN_IMPORT_MISMATCH'}
  $locals=$Prepared.locals.parameters
  if($locals.LocalProgramName -cne $c.module_name -or $locals.LocalVariablesTsv -cne $c.locals_path -or $locals.LocalPasteFormat -cne 'NameType' -or $locals.AuditPersistence -isnot [bool] -or -not $locals.AuditPersistence -or $locals.SnapshotOnly -eq $true -or $locals.KeepVariableEditorOpen -eq $true -or ($locals.AllowedCustomDataTypes -join "`n") -cne ($checked.custom_types -join "`n")){throw 'KV_ST_PLAN_LOCALS_MISMATCH'}
  if($c.globals_path){
    if($locals.GlobalVariablesTsv -cne $c.globals_path -or $locals.SkipGlobal -isnot [bool] -or $locals.SkipGlobal -or $locals.AppendGlobalVariables -isnot [bool] -or -not $locals.AppendGlobalVariables){throw 'KV_ST_PLAN_GLOBALS_MISMATCH'}
  }elseif($locals.GlobalVariablesTsv -or $locals.SkipGlobal -isnot [bool] -or -not $locals.SkipGlobal){throw 'KV_ST_PLAN_GLOBALS_MISMATCH'}
  if($c.category -eq 'function_block'){
    $arguments=$Prepared.arguments.parameters;$readback=$Prepared.arguments_readback.parameters
    if($arguments.FbModuleName -cne $c.module_name -or $arguments.ArgumentsTsv -cne $c.arguments_path -or $arguments.SnapshotOnly -eq $true){throw 'KV_ST_PLAN_ARGUMENTS_MISMATCH'}
    if($readback.FbModuleName -cne $c.module_name -or $readback.SnapshotOnly -isnot [bool] -or -not $readback.SnapshotOnly -or $readback.ArgumentsTsv -or @($Prepared.arguments_readback.contract.files).Count -ne 1 -or $Prepared.arguments_readback.contract.files[0] -cne 'fb_snapshot_result.json'){throw 'KV_ST_PLAN_ARGUMENT_READBACK_REQUIRED'}
  }
  if($Plan.require_compile_result -isnot [bool] -or -not $Plan.require_compile_result -or $Prepared.compile.parameters.ConvertAction -cne 'CtrlF9' -or [IO.Path]::GetFullPath([string]$Plan.compile_result_path) -ne (Join-Path $Prepared.compile_result.parameters.OutDir 'compile_result_copied.txt')){throw 'KV_ST_PLAN_COMPILE_REQUIRED'}
  $export=$Prepared.export.parameters
  if([IO.Path]::GetFullPath([string]$export.ExportDir) -ne (Split-Path -Parent ([IO.Path]::GetFullPath([string]$Plan.project_path))) -or $export.RestartKvs -isnot [bool] -or $export.RestartKvs){throw 'KV_ST_PLAN_EXPORT_MISMATCH'}
  foreach($name in @('compile','compile_result','export')){
    if([string]$Prepared[$name].parameters.CreatedProjectResultPath -cne [string]$import.CreatedProjectResultPath){throw 'KV_ST_PLAN_PROCESS_BINDING_MISMATCH'}
  }
  $verify=$Prepared.verify.parameters
  if([IO.Path]::GetFullPath([string]$verify.ContractPath) -ne $contractPath -or [IO.Path]::GetFullPath([string]$verify.ArtifactsRoot) -ne [IO.Path]::GetFullPath([string]$Plan.artifact_root)){throw 'KV_ST_PLAN_VERIFY_MISMATCH'}
  return @($checked.input_paths)
}

function Test-KvExecutionPlanPreflight([object]$Plan,[string]$ScriptsRoot) {
  if ($Plan.ok -isnot [bool] -or -not $Plan.ok) { throw 'KV_PLAN_NOT_OK' }
  foreach ($field in @('run_root','result_path','project_path')) { if (-not $Plan.$field) { throw "KV_PLAN_FIELD_REQUIRED: $field" } }
  if ($null -ne $Plan.require_compile_result -and $Plan.require_compile_result -isnot [bool]) { throw 'KV_PLAN_COMPILE_FLAG_INVALID' }
  $steps=@($Plan.steps)
  if ($steps.Count -lt 3) { throw 'KV_PLAN_STEPS_REQUIRED' }
  $manifest=Get-KvStudioOperatorScriptManifest -ScriptRoot $ScriptsRoot
  $allowed=@('runner_child_approved','workflow_tool','gate','customer_scaffold_tool','customer_non_ui_tool')
  $prepared=@{}; $outputPaths=@{}; $allInputs=@{}
  $projectPath=[IO.Path]::GetFullPath([string]$Plan.project_path)
  $exportProjectPath=''
  $projectDirectory=Split-Path -Parent $projectPath
  $outputDirectories=@($steps | ForEach-Object { if ($_.out_dir) { [IO.Path]::GetFullPath([string]$_.out_dir) } })
  for ($i=0;$i -lt $steps.Count;$i++) {
    $step=$steps[$i]
    if (-not $step.name -or $prepared.ContainsKey([string]$step.name)) { throw 'KV_PLAN_STEP_NAME_INVALID' }
    if (@($step.classes).Count -ne 1 -or [string]$step.classes[0] -notin $allowed) { throw "KV_PLAN_STEP_CLASS_INVALID: $($step.name)" }
    $path=Resolve-KvStudioOperatorScriptPath -ScriptRoot $ScriptsRoot -Name ([string]$step.script_name) -Classes @($step.classes)
    $relative=$path.Substring($ScriptsRoot.TrimEnd('\','/').Length+1).Replace('\','/')
    if ($i -lt 2) {
      $expected=@('gates/assert_kv_mvp_ui_guard_usage.ps1','gates/assert_kv_mvp_agent_boundary.ps1')[$i]
      if ($relative -ne $expected -or $step.classes[0] -ne 'gate') { throw "KV_PLAN_REQUIRED_GATE_ORDER: $expected" }
    }
    if (-not $step.out_dir) { throw "KV_PLAN_STEP_OUT_DIR_REQUIRED: $($step.name)" }
    $outDir=[IO.Path]::GetFullPath([string]$step.out_dir)
    if ($outputPaths.ContainsKey($outDir)) { throw "KV_PLAN_STEP_OUT_DIR_DUPLICATE: $outDir" }
    $outputPaths[$outDir]=$true
    $values=Get-KvPlanStepParameters $step $path
    if (-not $values.ContainsKey('OutDir') -or [IO.Path]::GetFullPath([string]$values.OutDir) -ne $outDir) { throw "KV_PLAN_STEP_OUT_DIR_MISMATCH: $($step.name)" }
    foreach ($projectParameter in @('ProjectPath','SourceProjectPath')) {
      $expectedProject=$projectPath
      if ($relative -eq 'runner_children/export_mnm_browse_default_folder_guarded.ps1' -and $exportProjectPath) { $expectedProject=$exportProjectPath }
      if ($values.ContainsKey($projectParameter) -and [IO.Path]::GetFullPath([string]$values[$projectParameter]) -ne $expectedProject) { throw "KV_PLAN_STEP_PROJECT_MISMATCH: $($step.name)" }
    }
    if ($relative -eq 'workflow_tools/new_kv_mnm_export_workspace.ps1' -and $values.RunRoot) {
      # This non-UI step copies the source project to this deterministic path.
      $exportProjectPath=Join-Path (Join-Path (Join-Path ([IO.Path]::GetFullPath([string]$values.RunRoot)) 'project') (Split-Path -Leaf $projectDirectory)) (Split-Path -Leaf $projectPath)
    }
    if ($i -lt 2) {
      if (-not $values.ContainsKey('ScriptsRoot') -or [IO.Path]::GetFullPath([string]$values.ScriptsRoot).TrimEnd('\','/') -ne $ScriptsRoot.TrimEnd('\','/')) { throw 'KV_PLAN_GATE_ROOT_MISMATCH' }
      if ($values.ContainsKey('ScriptNames') -and @($values.ScriptNames).Count) { throw 'KV_PLAN_GATE_SCOPE_RESTRICTED' }
      if ($values.ContainsKey('ManifestPath') -and [IO.Path]::GetFullPath([string]$values.ManifestPath) -ne (Join-Path $ScriptsRoot 'script_manifest.json')) { throw 'KV_PLAN_GATE_MANIFEST_MISMATCH' }
    }
    $contractArgs=@($values.Keys | Where-Object { $values[$_] -is [bool] -and $values[$_] } | ForEach-Object { '-'+$_ })
    $contract=Get-KvStepContract $manifest $relative $contractArgs
    $inputs=@()
    foreach ($key in $values.Keys) {
      if ($key -in @('ProjectPath','SourceProjectPath','OutDir')) { continue }
      foreach ($value in @($values[$key])) {
        if ($value -isnot [string] -or -not $value) { continue }
        try { $exists=Test-Path -LiteralPath $value -PathType Leaf -ErrorAction Stop } catch { $exists=$false }
        if (-not $exists) {
          if ($key -match '(Tsv$|^MnmPath$|^NodesConfigPath$|^PlanPath$)') {
            $missingPath=[IO.Path]::GetFullPath($value)
            if (-not @($outputDirectories | Where-Object { Test-KvPathWithin $missingPath $_ }).Count) { throw "KV_PLAN_INPUT_MISSING: $missingPath" }
          }
          continue
        }
        $inputPath=(Get-Item -LiteralPath $value).FullName
        if (Test-KvPathWithin $inputPath $projectDirectory) { continue }
        if (@($outputDirectories | Where-Object { Test-KvPathWithin $inputPath $_ }).Count) { continue }
        if (-not $allInputs.ContainsKey($inputPath)) { $allInputs[$inputPath]=[pscustomobject]@{path=$inputPath;sha256=(Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash} }
        $inputs+= $allInputs[$inputPath]
      }
    }
    $prepared[[string]$step.name]=@{path=$path;contract=$contract;parameters=$values;inputs=@($inputs)}
  }
  if ($Plan.operation -eq 'create_complete_module') {
    . (Join-Path $ScriptsRoot 'workflow_tools/kv_complete_module_contract.ps1')
    if (-not $prepared.ContainsKey('module_contract') -or $steps[2].name -cne 'module_contract') { throw 'KV_COMPLETE_PLAN_CONTRACT_GATE_REQUIRED' }
    $contractPath=[IO.Path]::GetFullPath([string]$prepared['module_contract'].parameters.ContractPath)
    if (-not $allInputs.ContainsKey($contractPath)) { $allInputs[$contractPath]=[pscustomobject]@{path=$contractPath;sha256=(Get-FileHash -LiteralPath $contractPath -Algorithm SHA256).Hash} }
    $rawContract=Get-Content -Raw -Encoding UTF8 -LiteralPath $contractPath | ConvertFrom-Json
    foreach ($relativeInput in @($rawContract.body_path,$rawContract.locals_path,$rawContract.arguments_path)+@($rawContract.evidence_paths)) {
      if (-not $relativeInput) { continue }
      $inputPath=Resolve-KvCompleteModuleInputPath $contractPath ([string]$relativeInput)
      if (-not $allInputs.ContainsKey($inputPath)) { $allInputs[$inputPath]=[pscustomobject]@{path=$inputPath;sha256=(Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash} }
    }
    foreach ($inputPath in @(Assert-KvCompletePlanSteps $Plan $prepared $ScriptsRoot)) {
      # Contract evidence is transitive input even when stored beside outputs.
      if (-not $allInputs.ContainsKey($inputPath)) { throw "KV_COMPLETE_PLAN_INPUT_NOT_FROZEN: $inputPath" }
    }
  }
  if ($Plan.operation -eq 'create_st_module') {
    foreach ($inputPath in @(Assert-KvStPlanSteps $Plan $prepared $ScriptsRoot)) {
      if (-not $allInputs.ContainsKey($inputPath)) { $allInputs[$inputPath]=[pscustomobject]@{path=$inputPath;sha256=(Get-FileHash -LiteralPath $inputPath -Algorithm SHA256).Hash} }
    }
  }
  Assert-KvPlanInputsUnchanged @($allInputs.Values)
  return [pscustomobject]@{ok=$true;status='planned';prepared_steps=$prepared;inputs=@($allInputs.Values)}
}
