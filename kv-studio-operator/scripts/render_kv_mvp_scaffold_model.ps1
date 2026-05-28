param(
  [Parameter(Mandatory=$true)]
  [string]$ModelPath,

  [string]$ScaffoldRoot = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptRoot 'kv_variable_definition_lib.ps1')

$ModelPath = [IO.Path]::GetFullPath($ModelPath)
if (-not (Test-Path -LiteralPath $ModelPath -PathType Leaf)) {
  throw "Scaffold model not found: $ModelPath"
}

$model = Get-Content -Raw -LiteralPath $ModelPath -Encoding UTF8 | ConvertFrom-Json
if (-not $ScaffoldRoot) {
  $ScaffoldRoot = Split-Path -Parent $ModelPath
}
$ScaffoldRoot = [IO.Path]::GetFullPath($ScaffoldRoot)

if ([int]$model.schema_version -ne 1) {
  throw 'Unsupported scaffold.model.json schema_version. Expected schema_version=1.'
}
if (-not $model.project.name) { throw 'scaffold model missing project.name.' }
if (-not $model.project.cpu_model) { throw 'scaffold model missing project.cpu_model.' }

$modules = @($model.modules)
if ($modules.Count -eq 0) { throw 'scaffold model must contain at least one module.' }

$ProjectName = [string]$model.project.name
$CpuModel = [string]$model.project.cpu_model
$PrimaryLocalProgram = if ($model.project.local_program) { [string]$model.project.local_program } else { [string]$modules[0].name }
$TaskSummary = if ($model.task.summary) { [string]$model.task.summary } else { 'KV STUDIO MVP scaffold generated from structured model.' }
$TemplateName = if ($model.template) { [string]$model.template } else { 'StructuredModel' }
$ScaffoldVersion = if ($model.scaffold_version) { [string]$model.scaffold_version } else { '3.0.0' }

$mnmDir = Join-Path $ScaffoldRoot 'mnm'
$varDir = Join-Path $ScaffoldRoot 'variables'
New-Item -ItemType Directory -Force -Path $ScaffoldRoot, $mnmDir, $varDir | Out-Null

function Write-Text([string]$Path, [string]$Text, [Text.Encoding]$Encoding) {
  $parent = Split-Path -Parent $Path
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  [IO.File]::WriteAllText($Path, $Text, $Encoding)
}

function New-VariableTsv([string]$Scope, [string]$OwnerProgram, [object[]]$Rows, [string]$Evidence) {
  $lines = @('scope' + "`t" + 'owner_program' + "`t" + 'name' + "`t" + 'data_type' + "`t" + 'device' + "`t" + 'initial_value' + "`t" + 'comment' + "`t" + 'evidence' + "`t" + 'status')
  foreach ($row in @($Rows)) {
    $definition = New-KvVariableDefinition `
      -Scope $Scope `
      -OwnerProgram $OwnerProgram `
      -Name ([string]$row.name) `
      -DataType ([string]$row.data_type) `
      -Device ([string]$row.device) `
      -InitialValue $(if ($null -ne $row.initial_value) { [string]$row.initial_value } else { 'FALSE' }) `
      -Comment ([string]$row.comment) `
      -Evidence $Evidence `
      -Status $(if ($row.status) { [string]$row.status } else { 'defined' })
    $lines += ConvertTo-KvVariableTsvLine $definition
  }
  return ($lines -join "`r`n") + "`r`n"
}

function New-MnmText($Module) {
  $moduleName = [string]$Module.name
  if (-not $moduleName) { throw 'Module is missing name.' }
  $moduleType = if ($null -ne $Module.module_type -and [string]$Module.module_type -ne '') { [int]$Module.module_type } else { 0 }
  $comment = if ($Module.mnm.comment) { [string]$Module.mnm.comment } else { "Generated scan module $moduleName." }
  $instructions = @($Module.mnm.instructions | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' })
  $stLines = @($Module.mnm.st_lines | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' })
  if ($instructions.Count -eq 0 -and $stLines.Count -eq 0) { throw "Module $moduleName has neither mnm.instructions nor mnm.st_lines." }
  $lines = @(
    'DEVICE:63'
    ";MODULE:$moduleName"
    ";MODULE_TYPE:$moduleType"
    "; $comment"
  )
  if ($stLines.Count -gt 0) {
    $lines += 'AREA_ST'
    foreach ($line in $stLines) {
      if ($line.StartsWith(';')) {
        $lines += $line
      } else {
        $lines += (';' + $line)
      }
    }
    $lines += @('END', 'ENDH')
  } else {
    $lines += $instructions
  }
  return ($lines -join "`r`n") + "`r`n"
}

$mnmEntries = @()
$variableSets = @()
$allModuleNames = [System.Collections.Generic.HashSet[string]]::new()

foreach ($module in $modules) {
  $moduleName = [string]$module.name
  if (-not $moduleName) { throw 'Every module must have a name.' }
  if (-not $allModuleNames.Add($moduleName)) { throw "Duplicate module name in scaffold model: $moduleName" }
}

foreach ($module in $modules) {
  $moduleName = [string]$module.name
  $moduleType = if ($null -ne $module.module_type -and [string]$module.module_type -ne '') { [int]$module.module_type } else { 0 }
  $mnmPath = Join-Path $mnmDir ($moduleName + '.mnm')
  $moduleVarDir = Join-Path $varDir $moduleName
  $globalTsv = Join-Path $moduleVarDir 'global_variables.tsv'
  $localTsv = Join-Path $moduleVarDir 'local_variables.tsv'
  $evidence = if ($model.evidence) { [string]$model.evidence } else { 'scaffold_model' }

  Write-Text $mnmPath (New-MnmText $module) ([Text.Encoding]::Unicode)
  Write-Text $globalTsv (New-VariableTsv 'global' $moduleName @($module.variables.global) $evidence) ([Text.Encoding]::Default)
  Write-Text $localTsv (New-VariableTsv 'local' $moduleName @($module.variables.local) $evidence) ([Text.Encoding]::Default)

  $mnmEntries += [ordered]@{
    path = ('mnm/' + [IO.Path]::GetFileName($mnmPath))
    module_name = $moduleName
    module_type = $moduleType
    encoding = 'UTF-16LE'
    variables = [ordered]@{
      global_tsv = ('variables/' + $moduleName + '/global_variables.tsv')
      local_tsv = ('variables/' + $moduleName + '/local_variables.tsv')
    }
  }
  $variableSets += [ordered]@{
    module_name = $moduleName
    global_tsv = ('variables/' + $moduleName + '/global_variables.tsv')
    local_tsv = ('variables/' + $moduleName + '/local_variables.tsv')
  }
}

$manifest = [ordered]@{
  schema_version = 2
  project = [ordered]@{
    name = $ProjectName
    cpu_model = $CpuModel
    local_program = $PrimaryLocalProgram
  }
  version = [ordered]@{
    scaffold_version = $ScaffoldVersion
    created_at = (Get-Date).ToString('s')
    template = $TemplateName
    source_model = 'scaffold.model.json'
  }
  task = [ordered]@{
    summary = $TaskSummary
    agent_fill_rule = 'Edit scaffold.model.json first, then run render_kv_mvp_scaffold_model.ps1. Generated MNM/TSV files are KV STUDIO adapter artifacts.'
  }
  checklist = 'CHECKLIST.md'
  source_model = 'scaffold.model.json'
  mnm_files = $mnmEntries
  variables = [ordered]@{
    schema = 'per_mnm'
    sets = $variableSets
    encoding = 'system-default ANSI'
    source = 'generated_from_scaffold_model'
  }
}
$manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $ScaffoldRoot 'scaffold.json') -Encoding UTF8

$moduleNames = @($modules | ForEach-Object { [string]$_.name })
$versionText = @"
# Project Version

Project: $ProjectName
CPU: $CpuModel
Modules: $($moduleNames -join ', ')
Scaffold version: $ScaffoldVersion
Template: $TemplateName
Source model: scaffold.model.json

## Change Notes

- Scaffold adapter files generated from scaffold.model.json by render_kv_mvp_scaffold_model.ps1.
- MNM and TSV files are generated KV STUDIO adapter artifacts.
"@
Set-Content -LiteralPath (Join-Path $ScaffoldRoot 'VERSION.md') -Value $versionText -Encoding UTF8

$taskText = @"
# Task

$TaskSummary

## Source Model

- Edit scaffold.model.json for modules, MNM instructions, and variables.
- Run render_kv_mvp_scaffold_model.ps1 after model changes.
- Do not hand-maintain TSV as the source of truth.

## Acceptance

- Import every generated MNM file as the module_type declared in scaffold.json.
- Define merged globals once.
- Define local variables per module and verify them with AuditVariablePersistence for multi-MNM work.
- Compile/convert through KV STUDIO with copied result text showing OK.
"@
Set-Content -LiteralPath (Join-Path $ScaffoldRoot 'TASK.md') -Value $taskText -Encoding UTF8

$checklistText = @"
# KV STUDIO Operation Checklist

Project: $ProjectName
CPU: $CpuModel
Modules: $($moduleNames -join ', ')
Template: $TemplateName

## Steps

- [ ] Confirm this scaffold is disposable or explicitly approved for KV STUDIO operation.
- [ ] Confirm scaffold.model.json is the source of truth and generated files were rendered after the latest model edit.
- [ ] Confirm scaffold.json contains every generated MNM entry and each entry has the intended module_type.
- [ ] Confirm every MNM file is UTF-16LE and contains ;MODULE_TYPE:<n>.
- [ ] Confirm every module has paired generated global and local TSV files.
- [ ] Confirm executable global variables are referenced by their paired MNM file.
- [ ] Confirm local variable rows use owner_program equal to the target module name.
- [ ] Confirm no operation will type program text directly into the ladder/program editor.

## Required Evidence

- Same-run project creation result.
- Same-run MNM import results for every module.
- Same-run module placement checks for every module.
- Same-run variable definition checks for every module.
- Same-run conversion result copied from KV STUDIO.
"@
Set-Content -LiteralPath (Join-Path $ScaffoldRoot 'CHECKLIST.md') -Value $checklistText -Encoding UTF8

[pscustomobject]@{
  ok = $true
  scaffold_root = $ScaffoldRoot
  model = $ModelPath
  manifest = (Join-Path $ScaffoldRoot 'scaffold.json')
  checklist = (Join-Path $ScaffoldRoot 'CHECKLIST.md')
  modules = $moduleNames
  generated_mnm_count = $mnmEntries.Count
  generated_variable_set_count = $variableSets.Count
} | ConvertTo-Json -Depth 5
