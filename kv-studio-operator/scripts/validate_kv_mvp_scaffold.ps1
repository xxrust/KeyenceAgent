param(
  [Parameter(Mandatory=$true)]
  [string]$ScaffoldRoot,

  [string]$ChecklistPath = '',
  [string]$OutDir = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptRoot 'kv_variable_definition_lib.ps1')

if (-not $OutDir) {
  $OutDir = Join-Path $ScaffoldRoot '_validation'
}

$ScaffoldRoot = [IO.Path]::GetFullPath($ScaffoldRoot)
$OutDir = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Write-ValidationResult([object]$Payload) {
  $path = Join-Path $OutDir 'scaffold_validation.json'
  $Payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $path -Encoding UTF8
  return $path
}

function Stop-ScaffoldValidation([string]$ErrorCode, [string]$Message, [string[]]$Evidence = @(), [int]$ExitCode = 41) {
  $payload = [ordered]@{
    ok = $false
    error_code = $ErrorCode
    operation = 'validate KV MVP scaffold'
    scaffold_root = $ScaffoldRoot
    message = $Message
    evidence = $Evidence
    remediation = @(
      'Regenerate the scaffold with scripts/new_kv_mvp_scaffold.ps1, or repair the listed file.',
      'Do not run KV STUDIO until scaffold_validation.json reports ok=true.'
    )
  }
  $resultPath = Write-ValidationResult $payload
  $payload.evidence = @($Evidence + $resultPath)
  [Console]::Error.WriteLine('KV_SCAFFOLD_VALIDATION_FAILED ' + (($payload | ConvertTo-Json -Depth 8 -Compress)))
  exit $ExitCode
}

function Resolve-ScaffoldPath([string]$RelativePath) {
  if ([string]::IsNullOrWhiteSpace($RelativePath)) { return '' }
  if ([IO.Path]::IsPathRooted($RelativePath)) { return [IO.Path]::GetFullPath($RelativePath) }
  return [IO.Path]::GetFullPath((Join-Path $ScaffoldRoot $RelativePath))
}

function Assert-File([string]$Path, [string]$Label) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_REQUIRED_FILE_MISSING' "$Label not found: $Path"
  }
}

function Read-TsvRows([string]$Path, [string[]]$RequiredColumns, [string]$Label) {
  Assert-File $Path $Label
  $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::Default)
  if ([string]::IsNullOrWhiteSpace($text)) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_TSV_EMPTY' "$Label is empty: $Path"
  }
  $firstLine = @($text -split "(`r`n|`n|`r)" | Where-Object { $_ -ne '' } | Select-Object -First 1)
  if ($firstLine.Count -eq 0) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_TSV_EMPTY' "$Label has no TSV header: $Path"
  }
  $headers = @([string]$firstLine[0] -split "`t")
  $missing = @($RequiredColumns | Where-Object { $headers -notcontains $_ })
  if ($missing.Count -gt 0) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_TSV_SCHEMA_INVALID' "$Label missing required column(s): $($missing -join ', '). Path=$Path"
  }
  $rows = @($text | ConvertFrom-Csv -Delimiter "`t")
  return $rows
}

function Get-ExecutableRows([object[]]$Rows, [string]$Scope) {
  @($Rows | Where-Object { $_.scope -eq $Scope -and $_.status -ne 'display_name' -and $_.name })
}

function Get-MnmModuleTypeFromText([string]$Text) {
  foreach ($line in ($Text -split "(`r`n|`n|`r)")) {
    if ($line -match '^;MODULE_TYPE:(\d+)\s*$') { return [int]$matches[1] }
  }
  return $null
}

function Test-MnmReferencesName([string]$Text, [string]$Name) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
  $pattern = '(?<![A-Za-z0-9_])' + [regex]::Escape($Name) + '(?![A-Za-z0-9_])'
  return [regex]::IsMatch($Text, $pattern)
}

function Test-SoftDeviceLikeVariableName([string]$Name) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
  return ($Name -match '^(X|Y|R|MR|LR|CR|B|VB|DM|EM|FM|ZF|W|TM|TC|TS|CM|CC|CS|T|C)\d+([._][A-Za-z0-9]+)?$')
}

function Assert-NoSoftDeviceLikeVariableRows([object[]]$Rows, [string]$Scope, [string]$Path) {
  $bad = @($Rows | Where-Object { Test-SoftDeviceLikeVariableName ([string]$_.name) } | ForEach-Object { [string]$_.name } | Select-Object -Unique)
  if ($bad.Count -gt 0) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_VARIABLE_NAME_SOFT_DEVICE_CONFLICT' "$Scope variable name(s) look like KV soft-device names and will be rejected by KV STUDIO variable paste: $($bad -join ', ')" @($Path)
  }
}

function Assert-KvVariableDefinitions([object[]]$Rows, [string]$Scope, [string]$Path, [string]$ExpectedOwnerProgram = '') {
  $errors = @(Get-KvVariableDefinitionErrors -Rows $Rows -Scope $Scope -SourcePath $Path -ExpectedOwnerProgram $ExpectedOwnerProgram)
  if ($errors.Count -gt 0) {
    $evidencePath = Join-Path $OutDir ("variable_definition_errors_{0}_{1}.json" -f $Scope, ([IO.Path]::GetFileNameWithoutExtension($Path)))
    [pscustomobject]@{
      ok = $false
      source = $Path
      scope = $Scope
      supported_type_pattern = Get-KvVariableSupportedTypePatternText
      errors = $errors
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
    $first = $errors[0]
    Stop-ScaffoldValidation ([string]$first.code) ([string]$first.message) @($Path, $evidencePath)
  }
}

function Get-FileHashText([string]$Path) {
  if ([string]::IsNullOrWhiteSpace($Path)) { return '' }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
  (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
}

if (-not (Test-Path -LiteralPath $ScaffoldRoot -PathType Container)) {
  Stop-ScaffoldValidation 'KV_SCAFFOLD_ROOT_MISSING' "ScaffoldRoot not found: $ScaffoldRoot"
}

$manifestPath = Join-Path $ScaffoldRoot 'scaffold.json'
Assert-File $manifestPath 'scaffold.json'

try {
  $manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
} catch {
  Stop-ScaffoldValidation 'KV_SCAFFOLD_MANIFEST_INVALID_JSON' "scaffold.json is not valid JSON: $($_.Exception.Message)" @($manifestPath)
}

if (-not $manifest.project.name) { Stop-ScaffoldValidation 'KV_SCAFFOLD_MANIFEST_MISSING_FIELD' 'scaffold.json missing project.name' @($manifestPath) }
if (-not $manifest.project.cpu_model) { Stop-ScaffoldValidation 'KV_SCAFFOLD_MANIFEST_MISSING_FIELD' 'scaffold.json missing project.cpu_model' @($manifestPath) }
if (-not $manifest.project.local_program) { Stop-ScaffoldValidation 'KV_SCAFFOLD_MANIFEST_MISSING_FIELD' 'scaffold.json missing project.local_program' @($manifestPath) }
if ([int]$manifest.schema_version -ne 2) {
  Stop-ScaffoldValidation 'KV_SCAFFOLD_SCHEMA_UNSUPPORTED' 'scaffold.json must use schema_version=2 with per-MNM variable files.' @($manifestPath)
}
if ([string]$manifest.variables.schema -ne 'per_mnm') {
  Stop-ScaffoldValidation 'KV_SCAFFOLD_VARIABLE_SCHEMA_INVALID' 'scaffold.json variables.schema must be per_mnm. Top-level variables.global_tsv/local_tsv is not authoritative.' @($manifestPath)
}

$sourceModelPath = ''
$sourceModel = $null
if ($manifest.source_model) {
  $sourceModelPath = Resolve-ScaffoldPath ([string]$manifest.source_model)
  Assert-File $sourceModelPath 'scaffold source model'
  try {
    $sourceModel = Get-Content -Raw -LiteralPath $sourceModelPath -Encoding UTF8 | ConvertFrom-Json
  } catch {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MODEL_INVALID_JSON' "scaffold.model.json is not valid JSON: $($_.Exception.Message)" @($sourceModelPath)
  }
  if ([int]$sourceModel.schema_version -ne 1) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MODEL_SCHEMA_UNSUPPORTED' 'scaffold.model.json must use schema_version=1.' @($sourceModelPath)
  }
}

$mnmEntries = @($manifest.mnm_files)
if ($mnmEntries.Count -eq 0) {
  Stop-ScaffoldValidation 'KV_SCAFFOLD_MNM_LIST_EMPTY' 'scaffold.json must contain at least one mnm_files entry.' @($manifestPath)
}

$checklistGuard = Join-Path (Split-Path -Parent $PSCommandPath) 'assert_kv_operation_checklist.ps1'
if (-not (Test-Path -LiteralPath $checklistGuard)) {
  Stop-ScaffoldValidation 'KV_SCAFFOLD_VALIDATOR_INTERNAL_ERROR' "Checklist guard script not found: $checklistGuard"
}
$global:LASTEXITCODE = 0
$checklistJson = & $checklistGuard -ChecklistPath $ChecklistPath -SearchRoots @($ScaffoldRoot) -OperationName 'validate KV MVP scaffold'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$checklistResult = $checklistJson | ConvertFrom-Json

$requiredTsvColumns = @('scope','owner_program','name','data_type','device','initial_value','comment','evidence','status')

$mnmChecks = @()
$variableSetChecks = @()
$globalDefinitions = @{}
foreach ($entry in $mnmEntries) {
  $mnmPath = Resolve-ScaffoldPath ([string]$entry.path)
  Assert-File $mnmPath 'MNM file'
  $moduleName = [string]$entry.module_name
  if (-not $moduleName) { $moduleName = [IO.Path]::GetFileNameWithoutExtension($mnmPath) }
  if (-not $entry.variables -or -not $entry.variables.global_tsv -or -not $entry.variables.local_tsv) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_VARIABLE_SET_MISSING' "MNM entry must define variables.global_tsv and variables.local_tsv. module=$moduleName" @($manifestPath)
  }
  $entryGlobalTsv = Resolve-ScaffoldPath ([string]$entry.variables.global_tsv)
  $entryLocalTsv = Resolve-ScaffoldPath ([string]$entry.variables.local_tsv)
  $globalRows = Read-TsvRows $entryGlobalTsv $requiredTsvColumns "global variable TSV for $moduleName"
  $localRows = Read-TsvRows $entryLocalTsv $requiredTsvColumns "local variable TSV for $moduleName"
  $definedGlobalRows = @(Get-ExecutableRows $globalRows 'global')
  $definedLocalRows = @(Get-ExecutableRows $localRows 'local')
  Assert-KvVariableDefinitions $definedGlobalRows 'global' $entryGlobalTsv
  Assert-KvVariableDefinitions $definedLocalRows 'local' $entryLocalTsv $moduleName
  if ($definedLocalRows.Count -eq 0) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_LOCAL_VARIABLES_EMPTY' "local variable TSV must contain executable local rows for module/program $moduleName." @($entryLocalTsv)
  }
  $wrongOwnerRows = @($definedLocalRows | Where-Object { [string]$_.owner_program -ne $moduleName })
  if ($wrongOwnerRows.Count -gt 0) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_LOCAL_OWNER_MISMATCH' "local variable rows must use owner_program=$moduleName. Wrong rows: $($wrongOwnerRows.name -join ', ')" @($entryLocalTsv)
  }
  foreach ($row in $definedGlobalRows) {
    $name = [string]$row.name
    $signature = @([string]$row.data_type, [string]$row.device, [string]$row.initial_value) -join "`t"
    if ($globalDefinitions.ContainsKey($name) -and $globalDefinitions[$name] -ne $signature) {
      Stop-ScaffoldValidation 'KV_SCAFFOLD_GLOBAL_VARIABLE_CONFLICT' "Global variable $name has conflicting definitions across MNM variable sets." @($entryGlobalTsv)
    }
    $globalDefinitions[$name] = $signature
  }
  $bytes = [IO.File]::ReadAllBytes($mnmPath)
  $hasBom = ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE)
  if (-not $hasBom) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MNM_ENCODING_INVALID' "MNM file must be UTF-16LE with BOM: $mnmPath" @($mnmPath)
  }
  $text = [Text.Encoding]::Unicode.GetString($bytes)
  $actualModuleType = Get-MnmModuleTypeFromText $text
  if ($null -eq $actualModuleType) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MNM_MODULE_TYPE_MISSING' "MNM file missing ;MODULE_TYPE:<n>: $mnmPath" @($mnmPath)
  }
  $expectedModuleType = if ($null -ne $entry.module_type -and [string]$entry.module_type -ne '') { [int]$entry.module_type } else { 0 }
  if ($actualModuleType -ne $expectedModuleType) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MNM_MODULE_TYPE_MISMATCH' "MNM ;MODULE_TYPE does not match scaffold.json. file=$mnmPath expected=$expectedModuleType actual=$actualModuleType" @($manifestPath, $mnmPath)
  }
  if ($actualModuleType -ne 0 -and $actualModuleType -ne 2) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MNM_MODULE_TYPE_UNSUPPORTED' "Unsupported MODULE_TYPE=$actualModuleType in $mnmPath. Use 0 for scan-executed modules or 2 for function blocks." @($mnmPath)
  }
  $referencedNames = @($definedGlobalRows | ForEach-Object { [string]$_.name } | Where-Object { $_ } | Select-Object -Unique)
  $unreferencedNames = @($referencedNames | Where-Object { -not (Test-MnmReferencesName $text $_) })
  if ($unreferencedNames.Count -gt 0) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_GLOBAL_VARIABLE_NOT_REFERENCED_BY_MNM' "Executable global variable rows must be referenced by their MNM file so the compile gate proves global variable definitions. Missing MNM references: $($unreferencedNames -join ', ')" @($mnmPath, $entryGlobalTsv)
  }
  $mnmChecks += [pscustomobject]@{
    path = $mnmPath
    module_name = $moduleName
    module_type = $actualModuleType
    utf16le_bom = $hasBom
    referenced_executable_global_variable_count = $referencedNames.Count
  }
  $variableSetChecks += [pscustomobject]@{
    module_name = $moduleName
    global_tsv = $entryGlobalTsv
    local_tsv = $entryLocalTsv
    executable_global_variable_count = $definedGlobalRows.Count
    executable_local_variable_count = $definedLocalRows.Count
  }
}

if ($sourceModel) {
  $modelModules = @($sourceModel.modules)
  if ($modelModules.Count -ne $mnmEntries.Count) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MODEL_RENDER_MISMATCH' "scaffold.model.json module count does not match scaffold.json mnm_files count. model=$($modelModules.Count) manifest=$($mnmEntries.Count)" @($sourceModelPath, $manifestPath)
  }
  foreach ($module in $modelModules) {
    $moduleName = [string]$module.name
    $entry = @($mnmEntries | Where-Object { [string]$_.module_name -eq $moduleName } | Select-Object -First 1)
    if ($entry.Count -eq 0) {
      Stop-ScaffoldValidation 'KV_SCAFFOLD_MODEL_RENDER_MISMATCH' "Module from scaffold.model.json is missing from scaffold.json: $moduleName" @($sourceModelPath, $manifestPath)
    }
    $entryObj = $entry[0]
    $mnmPath = Resolve-ScaffoldPath ([string]$entryObj.path)
    $entryGlobalTsv = Resolve-ScaffoldPath ([string]$entryObj.variables.global_tsv)
    $entryLocalTsv = Resolve-ScaffoldPath ([string]$entryObj.variables.local_tsv)
    $globalRows = Read-TsvRows $entryGlobalTsv $requiredTsvColumns "global variable TSV for $moduleName model check"
    $localRows = Read-TsvRows $entryLocalTsv $requiredTsvColumns "local variable TSV for $moduleName model check"
    $actualGlobals = @(Get-ExecutableRows $globalRows 'global' | ForEach-Object { [string]$_.name } | Sort-Object)
    $expectedGlobals = @(@($module.variables.global) | ForEach-Object { [string]$_.name } | Sort-Object)
    $actualLocals = @(Get-ExecutableRows $localRows 'local' | ForEach-Object { [string]$_.name } | Sort-Object)
    $expectedLocals = @(@($module.variables.local) | ForEach-Object { [string]$_.name } | Sort-Object)
    if ((Compare-Object $expectedGlobals $actualGlobals).Count -gt 0) {
      Stop-ScaffoldValidation 'KV_SCAFFOLD_MODEL_RENDER_MISMATCH' "Generated global TSV for $moduleName does not match scaffold.model.json variable names." @($sourceModelPath, $entryGlobalTsv)
    }
    if ((Compare-Object $expectedLocals $actualLocals).Count -gt 0) {
      Stop-ScaffoldValidation 'KV_SCAFFOLD_MODEL_RENDER_MISMATCH' "Generated local TSV for $moduleName does not match scaffold.model.json variable names." @($sourceModelPath, $entryLocalTsv)
    }
    $mnmText = [Text.Encoding]::Unicode.GetString([IO.File]::ReadAllBytes($mnmPath))
    foreach ($instruction in @($module.mnm.instructions | ForEach-Object { [string]$_ } | Where-Object { $_ })) {
      if ($mnmText -notmatch ('(?m)^' + [regex]::Escape($instruction) + '\s*$')) {
        Stop-ScaffoldValidation 'KV_SCAFFOLD_MODEL_RENDER_MISMATCH' "Generated MNM for $moduleName is missing model instruction: $instruction" @($sourceModelPath, $mnmPath)
      }
    }
    foreach ($stLine in @($module.mnm.st_lines | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' })) {
      $renderedLine = if ($stLine.StartsWith(';')) { $stLine } else { ';' + $stLine }
      if ($mnmText -notmatch ('(?m)^' + [regex]::Escape($renderedLine) + '\s*$')) {
        Stop-ScaffoldValidation 'KV_SCAFFOLD_MODEL_RENDER_MISMATCH' "Generated MNM for $moduleName is missing model ST line: $renderedLine" @($sourceModelPath, $mnmPath)
      }
    }
  }
}

$payload = [ordered]@{
  ok = $true
  operation = 'validate KV MVP scaffold'
  scaffold_root = $ScaffoldRoot
  manifest = $manifestPath
  checklist_path = [string]$checklistResult.checklist_path
  project_name = [string]$manifest.project.name
  cpu_model = [string]$manifest.project.cpu_model
  local_program = [string]$manifest.project.local_program
  variable_schema = 'per_mnm'
  source_model = $sourceModelPath
  source_model_hash = Get-FileHashText $sourceModelPath
  variable_sets = $variableSetChecks
  executable_global_variable_count = $globalDefinitions.Count
  executable_local_variable_count = @($variableSetChecks | ForEach-Object { $_.executable_local_variable_count } | Measure-Object -Sum).Sum
  mnm_files = $mnmChecks
}
$resultPath = Write-ValidationResult $payload
$payload.result_path = $resultPath
$payload | ConvertTo-Json -Depth 8
