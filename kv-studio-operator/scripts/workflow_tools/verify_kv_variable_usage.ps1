param(
  [Parameter(Mandatory=$true)][string]$ScaffoldRoot,
  [string]$StructureDefinitionsPath = '',
  [string[]]$AllowUnresolved = @(),
  [string]$OutDir = ''
)
# Offline preflight: prove that the variables referenced by every scaffold
# program are declared somewhere (globals / module locals / FB arguments) before
# touching KV STUDIO. No UI, no clipboard, no project.
$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path $ScaffoldRoot 'variable_usage_check' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
. (Join-Path $root 'kv_variable_definition_lib.ps1')

$manifestPath = Join-Path $ScaffoldRoot 'scaffold.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "KV_USAGE_SCAFFOLD_MISSING: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw -Encoding UTF8 | ConvertFrom-Json

function Read-TsvRows([string]$Path) {
  if (-not $Path) { return @() }
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
  $lines = @(Get-Content -LiteralPath $Path -Encoding Default | Where-Object { $_ -ne '' })
  if ($lines.Count -lt 2) { return @() }
  $header = @($lines[0] -split "`t")
  $rows = @()
  foreach ($line in $lines[1..($lines.Count - 1)]) {
    $fields = @($line -split "`t", -1)
    $row = [ordered]@{}
    for ($i = 0; $i -lt $header.Count; $i++) { $row[$header[$i]] = if ($i -lt $fields.Count) { $fields[$i] } else { '' } }
    $rows += [pscustomobject]$row
  }
  return $rows
}

$mnemonics = @(
  'LD','LDI','LDP','LDF','AND','ANI','ANDP','ANDF','OR','ORI','ORP','ORF','OUT','OUTF','SET','RES','RST','PLS','PLF',
  'MPS','MRD','MPP','ANB','ORB','INV','END','ENDH','NOP','RET','SBN','MC','MCR','CJ','CJP','CALL','CALLP','FUN','FB',
  'BOOKMARK','RUNG_COMMENT','AREA_ST','AREA_LD','ST','LBL','FOR','NEXT','BREAK','CONTINUE','IF','THEN','ELSIF','ELSE',
  'END_IF','CASE','OF','END_CASE','END_FOR','WHILE','END_WHILE','REPEAT','UNTIL','END_REPEAT','EXIT','RETURN',
  'TON','TOF','TP','CTU','CTD','R_TRIG','F_TRIG','MOVE','MOV','DMOV','FMOV','BMOV','ADD','SUB','MUL','DIV','MOD',
  'CMP','ZCP','INC','DEC','SHL','SHR','ROL','ROR','SUM','MEAN','MAX','MIN','ABS','SQR','SIN','COS','TAN','ASIN',
  'ACOS','ATAN','LOG','EXP','INT','DINT','UINT','UDINT','REAL','LREAL','BOOL','TIME','STRING','ARRAY','TRUE','FALSE',
  'AND','OR','NOT','XOR','DW','D','W','H','K','E','IF','THEN','ELSIF','ELSE','END_IF','CASE','OF','END_CASE','FOR','TO','BY','DO','END_FOR','WHILE','END_WHILE','REPEAT','UNTIL','END_REPEAT','EXIT','RETURN','CONTINUE','TRUE','FALSE','DEFINE','VAR','END_VAR','PROGRAM','FUNCTION_BLOCK','FUNCTION','STRUCT','END_STRUCT','TYPE','END_TYPE'
)
$mnemonicSet = @{}
foreach ($m in $mnemonics) { $mnemonicSet[$m.ToUpperInvariant()] = $true }

$systemAssumed = New-Object System.Collections.Generic.List[object]
$unresolved = New-Object System.Collections.Generic.List[object]
$invalidTypes = New-Object System.Collections.Generic.List[object]
$duplicates = New-Object System.Collections.Generic.List[object]
$conflicts = New-Object System.Collections.Generic.List[object]
$allowSet = @{}
foreach ($a in $AllowUnresolved) { $allowSet[[string]$a] = $true }

$structureTypes = @{}
if ($StructureDefinitionsPath -and (Test-Path -LiteralPath $StructureDefinitionsPath -PathType Leaf)) {
  $doc = Get-Content -LiteralPath $StructureDefinitionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($s in @($doc.structures)) { $structureTypes[[string]$s.name] = @($s.members) }
}
$customTypes = @{}
foreach ($t in @($manifest.variables.allowed_custom_data_types)) { if ($t) { $customTypes[[string]$t] = $true } }

$sets = @($manifest.variables.sets)
$mnmEntries = @($manifest.mnm_files)
$globals = @{}
$localsByModule = @{}
$argsByModule = @{}
foreach ($set in $sets) {
  $module = [string]$set.module_name
  if (-not $module) { continue }
  if (-not $localsByModule.ContainsKey($module)) { $localsByModule[$module] = @{} }
  $globalTsv = [string]$set.global_tsv
  if ($globalTsv) { $globalTsv = Join-Path $ScaffoldRoot $globalTsv }
  foreach ($row in @(Read-TsvRows $globalTsv)) {
    if ([string]$row.status -eq 'display_name' -or -not [string]$row.name) { continue }
    $name = [string]$row.name
    if ($globals.ContainsKey($name)) { $duplicates.Add([pscustomobject]@{ scope = 'global'; name = $name; kind = 'duplicate_global' }) | Out-Null }
    else { $globals[$name] = [string]$row.data_type }
    if ([string]$row.device -and [string]$row.initial_value) {
      $conflicts.Add([pscustomobject]@{ scope = 'global'; name = $name; device = [string]$row.device; initial_value = [string]$row.initial_value }) | Out-Null
    }
    if ($row.data_type -and -not (Test-KvVariableDataType ([string]$row.data_type) -AllowedCustomDataTypes @($customTypes.Keys))) {
      $invalidTypes.Add([pscustomobject]@{ scope = 'global'; name = $name; data_type = [string]$row.data_type; source = [string]$set.global_tsv }) | Out-Null
    }
  }
  $localTsv = [string]$set.local_tsv
  if ($localTsv) { $localTsv = Join-Path $ScaffoldRoot $localTsv }
  foreach ($row in @(Read-TsvRows $localTsv)) {
    if ([string]$row.status -eq 'display_name' -or -not [string]$row.name) { continue }
    $name = [string]$row.name
    if ($localsByModule[$module].ContainsKey($name)) { $duplicates.Add([pscustomobject]@{ scope = $module; name = $name; kind = 'duplicate_local' }) | Out-Null }
    else { $localsByModule[$module][$name] = [string]$row.data_type }
    if ($row.data_type -and -not (Test-KvVariableDataType ([string]$row.data_type) -AllowedCustomDataTypes @($customTypes.Keys))) {
      $invalidTypes.Add([pscustomobject]@{ scope = $module; name = $name; data_type = [string]$row.data_type; source = [string]$set.local_tsv }) | Out-Null
    }
  }
  $argumentsTsv = Join-Path $ScaffoldRoot (Join-Path 'modules' (Join-Path $module 'arguments.tsv'))
  if (Test-Path -LiteralPath $argumentsTsv -PathType Leaf) {
    $argsByModule[$module] = @{}
    foreach ($row in @(Read-TsvRows $argumentsTsv)) {
      if (-not $row.argument_name) { continue }
      $argsByModule[$module][[string]$row.argument_name] = [string]$row.data_type
    }
  }
}

$typeNames = @{}
foreach ($t in $customTypes.Keys) { $typeNames[$t] = $true }
foreach ($t in $structureTypes.Keys) { $typeNames[$t] = $true }

$moduleCount = 0
foreach ($entry in $mnmEntries) {
  $moduleCount++
  $module = [string]$entry.module_name
  $mnmRel = [string]$entry.path
  if (-not $mnmRel) { continue }
  $mnmPath = Join-Path $ScaffoldRoot $mnmRel
  if (-not (Test-Path -LiteralPath $mnmPath -PathType Leaf)) { continue }
  $text = Get-Content -LiteralPath $mnmPath -Raw -Encoding Unicode
  $locals = if ($localsByModule.ContainsKey($module)) { $localsByModule[$module] } else { @{} }
  $fbArgs = if ($argsByModule.ContainsKey($module)) { $argsByModule[$module] } else { @{} }
  $lineNo = 0
  foreach ($line in ($text -split "`r?`n")) {
    $lineNo++
    # Only the statement part; trailing // or (* *) comments are not symbols.
    $statement = $line
    if ($statement -match '^(DEVICE|;MODULE|;MODULE_TYPE):') { continue }
    if ($statement -match '^; Generated ') { continue }
    if ($statement -match '^\s*;') { $statement = $statement.Substring($statement.IndexOf(';') + 1) }
    $statement = ($statement -split '//', 2)[0]
    if (-not $statement.Trim()) { continue }
    foreach ($match in [regex]::Matches($statement, '(?<![\w\.])([A-Za-z_\u4e00-\u9fff][A-Za-z0-9_\u4e00-\u9fff]*)')) {
      $name = $match.Groups[1].Value
      if ($mnemonicSet.ContainsKey($name.ToUpperInvariant())) { continue }
      if ($name -match '^(T|t)#' -or $name -eq 'T') { continue }
      if ($locals.ContainsKey($name) -or $fbArgs.ContainsKey($name) -or $globals.ContainsKey($name)) { continue }
      if ($typeNames.ContainsKey($name)) { continue }
      if ($name.StartsWith('_')) {
        $systemAssumed.Add([pscustomobject]@{ module = $module; line = $lineNo; name = $name }) | Out-Null
        continue
      }
      # Function/FB invocation of a declared or library type: name followed by '('.
      $after = $statement.Substring($match.Index + $match.Length)
      if ($after.TrimStart().StartsWith('(') -and ($typeNames.ContainsKey($name))) { continue }
      if ($allowSet.ContainsKey($name)) { continue }
      $unresolved.Add([pscustomobject]@{ module = $module; line = $lineNo; name = $name; context = $statement.Trim() }) | Out-Null
    }
  }
}

$unresolvedUnique = @($unresolved | Group-Object module,name | ForEach-Object { $_.Group[0] })
$report = [ordered]@{
  ok = ($unresolvedUnique.Count -eq 0 -and $invalidTypes.Count -eq 0 -and $duplicates.Count -eq 0 -and $conflicts.Count -eq 0)
  scaffold_root = $ScaffoldRoot
  modules_checked = $moduleCount
  declared_globals = $globals.Count
  declared_locals = (@($localsByModule.Values | ForEach-Object { $_.Count }) | Measure-Object -Sum).Sum
  declared_fb_arguments = (@($argsByModule.Values | ForEach-Object { $_.Count }) | Measure-Object -Sum).Sum
  system_assumed_count = $systemAssumed.Count
  unresolved_symbols = $unresolvedUnique
  invalid_data_types = $invalidTypes
  duplicate_declarations = $duplicates
  device_initial_conflicts = $conflicts
}
$reportPath = Join-Path $OutDir 'variable_usage_report.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8

if (-not $report.ok) {
  throw "KV_VARIABLE_USAGE_INFEASIBLE: unresolved=$($unresolvedUnique.Count) invalid_types=$($invalidTypes.Count) duplicates=$($duplicates.Count) conflicts=$($conflicts.Count). See $reportPath"
}
Write-Output ("KV_VARIABLE_USAGE_OK modules={0} globals={1} locals={2} fb_args={3} system_assumed={4} report={5}" -f `
  $report.modules_checked, $report.declared_globals, $report.declared_locals, $report.declared_fb_arguments, $report.system_assumed_count, $reportPath)
