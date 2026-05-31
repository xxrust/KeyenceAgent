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
  @(Get-KvExecutableVariableRows -Rows $Rows -Scope $Scope)
}

function Get-MnmModuleTypeFromText([string]$Text) {
  foreach ($line in ($Text -split "(`r`n|`n|`r)")) {
    if ($line -match '^;MODULE_TYPE:(\d+)\s*$') { return [int]$matches[1] }
  }
  return $null
}

function Get-MnmDeviceCodeFromText([string]$Text) {
  foreach ($line in ($Text -split "(`r`n|`n|`r)")) {
    $normalized = $line.TrimStart([char]0xFEFF)
    if ($normalized -match '^DEVICE:(\d+)\s*$') { return [int]$matches[1] }
  }
  return $null
}

function Test-MnmReferencesName([string]$Text, [string]$Name) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
  $pattern = '(?<![A-Za-z0-9_])' + [regex]::Escape($Name) + '(?![A-Za-z0-9_])'
  return [regex]::IsMatch($Text, $pattern)
}

$script:NetworkConfigPayloadKeyPattern = "(?im)(^|[\s,{])[""']?(ethernet_ip|ethernetIp|ethercat|device_path|devicePath|device_path_text|devicePathText|node_address|nodeAddress|ip_address|ipAddress|variable_name_prefix|variableNamePrefix|variable_names|variableNames|batch_axis_registration|batchAxisRegistration|esi_path|esiPath|esi_file|esiFile)[""']?\s*[:=]"

function Assert-NoNetworkConfigPayloadText([string]$Text, [string]$Path, [string]$Label, [string]$NetworkConfigPath) {
  if ([string]::IsNullOrEmpty($Text)) { return }
  $matches = @([regex]::Matches($Text, $script:NetworkConfigPayloadKeyPattern))
  if ($matches.Count -eq 0) { return }
  $hits = @(
    $matches |
      Select-Object -First 8 |
      ForEach-Object {
        $before = if ($_.Index -gt 0) { $Text.Substring(0, $_.Index) } else { '' }
        $lineNumber = ([regex]::Matches($before, "(`r`n|`n|`r)")).Count + 1
        '{0}:line {1}: {2}' -f $Label, $lineNumber, $_.Groups[2].Value
      }
  )
  Stop-ScaffoldValidation 'KV_SCAFFOLD_NETWORK_CONFIG_LEAK' "EtherCAT/EtherNet/IP unit configuration payload keys belong only in architecture/network_config.json. Move these entries out of TASK.md, VERSION.md, MNM comments, and variable TSV files: $($hits -join '; ')" @($Path, $NetworkConfigPath)
}

function Assert-MnmImportableInstructionText([string]$Text, [string]$Path) {
  $badBracketedInstructions = @()
  foreach ($line in ($Text -split "(`r`n|`n|`r)")) {
    $trimmed = ([string]$line).Trim()
    if ($trimmed -match '^\[(FBEXEC|FBCALL|FUN)\]\b') {
      $badBracketedInstructions += $trimmed
    }
  }
  if ($badBracketedInstructions.Count -gt 0) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MNM_BRACKETED_INSTRUCTION_INVALID' "MNM import text must use raw KEYENCE mnemonic instructions such as FBEXEC, FBCALL, or FUN without square brackets. Invalid line(s): $($badBracketedInstructions -join ' | ')" @($Path)
  }
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

function Assert-KvVariableDefinitions([object[]]$Rows, [string]$Scope, [string]$Path, [string]$ExpectedOwnerProgram = '', [string[]]$AllowedCustomDataTypes = @()) {
  $errors = @(Get-KvVariableDefinitionErrors -Rows $Rows -Scope $Scope -SourcePath $Path -ExpectedOwnerProgram $ExpectedOwnerProgram -AllowedCustomDataTypes $AllowedCustomDataTypes)
  if ($errors.Count -gt 0) {
    $evidencePath = Join-Path $OutDir ("variable_definition_errors_{0}_{1}.json" -f $Scope, ([IO.Path]::GetFileNameWithoutExtension($Path)))
    [pscustomobject]@{
      ok = $false
      source = $Path
      scope = $Scope
      supported_type_pattern = Get-KvVariableSupportedTypePatternText -AllowedCustomDataTypes $AllowedCustomDataTypes
      allowed_custom_data_types = @($AllowedCustomDataTypes)
      errors = $errors
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
    $first = $errors[0]
    Stop-ScaffoldValidation ([string]$first.code) ([string]$first.message) @($Path, $evidencePath)
  }
}

function Assert-FbArgumentDefinitions([object[]]$Rows, [string]$OwnerProgram, [string]$Path) {
  $allowedKinds = @('IN','OUT','IN-OUT')
  $errors = [System.Collections.Generic.List[object]]::new()
  foreach ($row in @($Rows | Where-Object { $_.status -ne 'display_name' -and $_.argument_name })) {
    if ([string]$row.owner_program -ne $OwnerProgram) {
      $errors.Add([pscustomobject]@{ code='KV_FB_ARGUMENT_OWNER_MISMATCH'; argument_name=[string]$row.argument_name; message="FB argument owner_program must be $OwnerProgram." })
    }
    if ($allowedKinds -notcontains ([string]$row.argument_kind)) {
      $errors.Add([pscustomobject]@{ code='KV_FB_ARGUMENT_KIND_INVALID'; argument_name=[string]$row.argument_name; argument_kind=[string]$row.argument_kind; message='FB argument_kind must be IN, OUT, or IN-OUT.' })
    }
    if (-not (Test-KvVariableDataType ([string]$row.data_type))) {
      $errors.Add([pscustomobject]@{ code='KV_FB_ARGUMENT_DATA_TYPE_UNSUPPORTED'; argument_name=[string]$row.argument_name; data_type=[string]$row.data_type; message='FB argument data_type is outside the supported KEYENCE type grammar.' })
    }
  }
  if ($errors.Count -gt 0) {
    $evidencePath = Join-Path $OutDir ("fb_argument_definition_errors_{0}.json" -f ([IO.Path]::GetFileNameWithoutExtension($Path)))
    [pscustomobject]@{
      ok = $false
      source = $Path
      owner_program = $OwnerProgram
      supported_type_pattern = Get-KvVariableSupportedTypePatternText
      errors = @($errors)
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

$networkConfigPath = ''
$networkConfig = $null
if (-not $manifest.architecture -or -not $manifest.architecture.network_config) {
  Stop-ScaffoldValidation 'KV_SCAFFOLD_NETWORK_CONFIG_MISSING' 'scaffold.json must declare architecture.network_config. EtherCAT/EtherNet/IP unit configuration is not allowed in TASK.md, VERSION.md, MNM comments, or variable TSV files.' @($manifestPath)
}
$networkConfigPath = Resolve-ScaffoldPath ([string]$manifest.architecture.network_config)
Assert-File $networkConfigPath 'network configuration architecture file'
try {
  $networkConfig = Get-Content -Raw -LiteralPath $networkConfigPath -Encoding UTF8 | ConvertFrom-Json
} catch {
  Stop-ScaffoldValidation 'KV_SCAFFOLD_NETWORK_CONFIG_INVALID_JSON' "architecture.network_config is not valid JSON: $($_.Exception.Message)" @($networkConfigPath)
}
if ([int]$networkConfig.schema_version -ne 1) {
  Stop-ScaffoldValidation 'KV_SCAFFOLD_NETWORK_CONFIG_SCHEMA_UNSUPPORTED' 'architecture/network_config.json must use schema_version=1.' @($networkConfigPath)
}
if ([string]$networkConfig.route -ne 'project_tree_unit_configuration') {
  Stop-ScaffoldValidation 'KV_SCAFFOLD_NETWORK_CONFIG_ROUTE_INVALID' 'network_config.route must be project_tree_unit_configuration.' @($networkConfigPath)
}
if (-not $networkConfig.ethernet_ip -or $null -eq $networkConfig.ethernet_ip.devices) {
  Stop-ScaffoldValidation 'KV_SCAFFOLD_NETWORK_CONFIG_ETHERNET_MISSING' 'network_config must contain ethernet_ip.devices array, even when empty.' @($networkConfigPath)
}
if (-not $networkConfig.ethercat -or $null -eq $networkConfig.ethercat.devices) {
  Stop-ScaffoldValidation 'KV_SCAFFOLD_NETWORK_CONFIG_ETHERCAT_MISSING' 'network_config must contain ethercat.devices array, even when empty.' @($networkConfigPath)
}

foreach ($docName in @('TASK.md','VERSION.md')) {
  $docPath = Join-Path $ScaffoldRoot $docName
  if (Test-Path -LiteralPath $docPath -PathType Leaf) {
    Assert-NoNetworkConfigPayloadText ([IO.File]::ReadAllText($docPath, [Text.Encoding]::UTF8)) $docPath $docName $networkConfigPath
  }
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

$incomingModuleNameKeys = @(
  $mnmEntries | ForEach-Object {
    $declared = [string]$_.module_name
    if (-not $declared) { $declared = [IO.Path]::GetFileNameWithoutExtension([string]$_.path) }
    $declared.Trim().ToUpperInvariant()
  }
)
$duplicateIncomingModuleNames = @($incomingModuleNameKeys | Group-Object | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name })
if ($duplicateIncomingModuleNames.Count -gt 0) {
  Stop-ScaffoldValidation 'KV_SCAFFOLD_DUPLICATE_MNM_MODULE_NAME' "scaffold.json contains duplicate MNM/module names. Direct multi-MNM import cannot be stable with duplicates: $($duplicateIncomingModuleNames -join ', ')" @($manifestPath)
}

$allowedCategories = @('scan','function_block','standby','interrupt')
$manifestCustomDataTypes = @()
if ($manifest.variables -and $manifest.variables.allowed_custom_data_types) {
  $manifestCustomDataTypes += @($manifest.variables.allowed_custom_data_types)
}
if ($manifest.allowed_custom_data_types) {
  $manifestCustomDataTypes += @($manifest.allowed_custom_data_types)
}
$fbTypeNames = @(
  @(
    $mnmEntries |
      Where-Object {
        $moduleTypeForCustom = if ($null -ne $_.module_type -and [string]$_.module_type -ne '') { [int]$_.module_type } else { 0 }
        $moduleTypeForCustom -eq 2
      } |
      ForEach-Object {
        if ($_.module_name) { [string]$_.module_name } else { [IO.Path]::GetFileNameWithoutExtension([string]$_.path) }
      }
    $manifestCustomDataTypes
  ) |
    ForEach-Object { ([string]$_).Trim() } |
    Where-Object { $_ } |
    Select-Object -Unique
)

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
  Assert-File $entryGlobalTsv "global variable TSV for $moduleName"
  Assert-File $entryLocalTsv "local variable TSV for $moduleName"
  Assert-NoNetworkConfigPayloadText ([IO.File]::ReadAllText($entryGlobalTsv, [Text.Encoding]::Default)) $entryGlobalTsv "global variable TSV for $moduleName" $networkConfigPath
  Assert-NoNetworkConfigPayloadText ([IO.File]::ReadAllText($entryLocalTsv, [Text.Encoding]::Default)) $entryLocalTsv "local variable TSV for $moduleName" $networkConfigPath
  $globalRows = Read-TsvRows $entryGlobalTsv $requiredTsvColumns "global variable TSV for $moduleName"
  $localRows = Read-TsvRows $entryLocalTsv $requiredTsvColumns "local variable TSV for $moduleName"
  $definedGlobalRows = @(Get-ExecutableRows $globalRows 'global')
  $definedLocalRows = @(Get-ExecutableRows $localRows 'local')
  $noLocalMarkers = @($localRows | Where-Object { Test-KvNoLocalVariablesMarkerRow $_ })
  Assert-KvVariableDefinitions $definedGlobalRows 'global' $entryGlobalTsv '' $fbTypeNames
  Assert-KvVariableDefinitions $definedLocalRows 'local' $entryLocalTsv $moduleName $fbTypeNames
  $noLocalMarkerErrors = @(Get-KvNoLocalVariablesMarkerErrors -Rows $localRows -SourcePath $entryLocalTsv -ExpectedOwnerProgram $moduleName)
  if ($noLocalMarkerErrors.Count -gt 0) {
    $evidencePath = Join-Path $OutDir ("no_local_variables_marker_errors_{0}.json" -f ([IO.Path]::GetFileNameWithoutExtension($entryLocalTsv)))
    [pscustomobject]@{
      ok = $false
      source = $entryLocalTsv
      module_name = $moduleName
      errors = $noLocalMarkerErrors
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $evidencePath -Encoding UTF8
    $first = $noLocalMarkerErrors[0]
    Stop-ScaffoldValidation ([string]$first.code) ([string]$first.message) @($entryLocalTsv, $evidencePath)
  }
  if ($definedLocalRows.Count -eq 0) {
    if ($noLocalMarkers.Count -ne 1) {
      Stop-ScaffoldValidation 'KV_SCAFFOLD_LOCAL_VARIABLES_EMPTY' "local variable TSV must contain executable local rows for module/program $moduleName, or exactly one no_local_variables marker row." @($entryLocalTsv)
    }
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
  Assert-NoNetworkConfigPayloadText $text $mnmPath "MNM file for $moduleName" $networkConfigPath
  Assert-MnmImportableInstructionText $text $mnmPath
  $actualDeviceCode = Get-MnmDeviceCodeFromText $text
  if ($null -eq $actualDeviceCode) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MNM_DEVICE_MISSING' "MNM file missing DEVICE:<n>: $mnmPath" @($mnmPath)
  }
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
  $category = if ($entry.category) { [string]$entry.category } elseif ($actualModuleType -eq 2) { 'function_block' } else { 'scan' }
  if ($allowedCategories -notcontains $category) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MODULE_CATEGORY_UNSUPPORTED' "Unsupported module category '$category' in scaffold.json for $moduleName. Supported categories: $($allowedCategories -join ', ')." @($manifestPath)
  }
  $expectedDeviceCode = if ($null -ne $entry.device -and [string]$entry.device -ne '') { [int]$entry.device } else { $null }
  if ($null -ne $expectedDeviceCode -and $actualDeviceCode -ne $expectedDeviceCode) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MNM_DEVICE_MISMATCH' "MNM DEVICE does not match scaffold.json. module=$moduleName module_type=$actualModuleType expected_device=$expectedDeviceCode actual_device=$actualDeviceCode" @($manifestPath, $mnmPath)
  }
  if ($actualModuleType -eq 2 -and $actualDeviceCode -ne 59) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_FUNCTION_BLOCK_DEVICE_INVALID' "Function-block MNM must use DEVICE:59 based on KV STUDIO export evidence. module=$moduleName actual_device=$actualDeviceCode" @($mnmPath)
  }
  if ($actualModuleType -eq 0 -and @('scan','standby','interrupt') -contains $category -and $actualDeviceCode -ne 63 -and $actualDeviceCode -ne 59) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_PROGRAM_DEVICE_UNSUPPORTED' "Program MNM MODULE_TYPE=0 currently allows DEVICE:63 or DEVICE:59. The scaffold category selects KV STUDIO program kind; DEVICE is not used as the standby discriminator. module=$moduleName category=$category actual_device=$actualDeviceCode" @($mnmPath)
  }
  if ($actualModuleType -eq 2 -and $category -ne 'function_block') {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MODULE_CATEGORY_MISMATCH' "MODULE_TYPE=2 must use category=function_block. module=$moduleName category=$category" @($manifestPath, $mnmPath)
  }
  if ($category -eq 'standby' -and $actualModuleType -ne 0) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_STANDBY_MODULE_TYPE_INVALID' "Standby category uses ordinary program MNM MODULE_TYPE=0; the category is applied by selecting 后备模块 in KV STUDIO's program-kind dialog. module=$moduleName actual_module_type=$actualModuleType" @($manifestPath, $mnmPath)
  }
  $argumentCount = 0
  if ($actualModuleType -eq 2) {
    if (-not $entry.arguments -or -not $entry.arguments.tsv) {
      Stop-ScaffoldValidation 'KV_SCAFFOLD_FB_ARGUMENTS_MISSING' "Function-block module must define arguments.tsv for self-variable table paste. module=$moduleName" @($manifestPath)
    }
    $argumentsTsv = Resolve-ScaffoldPath ([string]$entry.arguments.tsv)
    $argumentRows = Read-TsvRows $argumentsTsv @('owner_program','argument_name','argument_kind','constant','data_type','default_value','retain','hidden','comment1','comment2','comment3','comment4','comment5','comment6','comment7','comment8','evidence','status') "FB argument TSV for $moduleName"
    $definedArgumentRows = @($argumentRows | Where-Object { $_.status -ne 'display_name' -and $_.argument_name })
    if ($definedArgumentRows.Count -eq 0) {
      Stop-ScaffoldValidation 'KV_SCAFFOLD_FB_ARGUMENTS_EMPTY' "Function-block arguments.tsv must contain executable argument rows. module=$moduleName" @($argumentsTsv)
    }
    Assert-FbArgumentDefinitions $definedArgumentRows $moduleName $argumentsTsv
    $argumentCount = $definedArgumentRows.Count
    $argumentNames = @($definedArgumentRows | ForEach-Object { [string]$_.argument_name } | Where-Object { $_ } | Select-Object -Unique)
    $unreferencedArguments = @($argumentNames | Where-Object { -not (Test-MnmReferencesName $text $_) })
    if ($unreferencedArguments.Count -gt 0) {
      Stop-ScaffoldValidation 'KV_SCAFFOLD_FB_ARGUMENT_NOT_REFERENCED_BY_MNM' "FB argument rows must be referenced by the FB MNM/ST body. Missing MNM references: $($unreferencedArguments -join ', ')" @($mnmPath, $argumentsTsv)
    }
  }
  if ($actualModuleType -eq 0 -and $category -eq 'function_block') {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MODULE_CATEGORY_MISMATCH' "category=function_block must use MODULE_TYPE=2. module=$moduleName" @($manifestPath, $mnmPath)
  }
  if ($category -eq 'interrupt') {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MODULE_CATEGORY_SUPPORT_INCOMPLETE' "Module category '$category' is not accepted until a same-run KV STUDIO probe proves MNM import mapping, CPU-system interrupt settings, interrupt-enable path, placement, and compile behavior. module=$moduleName" @($manifestPath, $mnmPath)
  }
  if ($actualModuleType -eq 0 -and $text -notmatch '(?m)^ENDH\s*$') {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_MNM_ENDH_MISSING' "Scan-executed MNM must contain ENDH so KV STUDIO conversion can complete: $mnmPath" @($mnmPath)
  }
  $referencedNames = @($definedGlobalRows | ForEach-Object { [string]$_.name } | Where-Object { $_ } | Select-Object -Unique)
  $unreferencedNames = @($referencedNames | Where-Object { -not (Test-MnmReferencesName $text $_) })
  if ($unreferencedNames.Count -gt 0) {
    Stop-ScaffoldValidation 'KV_SCAFFOLD_GLOBAL_VARIABLE_NOT_REFERENCED_BY_MNM' "Executable global variable rows must be referenced by their MNM file so the compile gate proves global variable definitions. Missing MNM references: $($unreferencedNames -join ', ')" @($mnmPath, $entryGlobalTsv)
  }
  $mnmChecks += [pscustomobject]@{
    path = $mnmPath
    module_name = $moduleName
    device = $actualDeviceCode
    module_type = $actualModuleType
    category = $category
    utf16le_bom = $hasBom
    fb_argument_count = $argumentCount
    referenced_executable_global_variable_count = $referencedNames.Count
  }
  $variableSetChecks += [pscustomobject]@{
    module_name = $moduleName
    global_tsv = $entryGlobalTsv
    local_tsv = $entryLocalTsv
    executable_global_variable_count = $definedGlobalRows.Count
    executable_local_variable_count = $definedLocalRows.Count
    no_local_variables_marked = ($definedLocalRows.Count -eq 0 -and $noLocalMarkers.Count -eq 1)
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
  network_config = $networkConfigPath
  network_config_hash = Get-FileHashText $networkConfigPath
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
