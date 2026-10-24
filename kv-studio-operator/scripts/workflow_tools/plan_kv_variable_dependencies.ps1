param(
  [Parameter(Mandatory=$true)][string]$VariablesTsv,
  [string]$StructureDefinitionsPath = '',
  [int[]]$AxisIndexes = @(),
  [string[]]$FbTypes = @(),
  [switch]$RequireReady,
  [string]$OutDir = ''
)
# Offline dependency planner for variable insertion. It answers one question
# before any KV STUDIO write: is this variable's type / device / FB available in
# the target project? Blocked rows are reported with the missing prerequisite and
# are never inserted by a dependency-ordered writer.
$ErrorActionPreference = 'Stop'
if (-not $OutDir) { $OutDir = Join-Path (Split-Path -Parent $VariablesTsv) 'variable_dependencies' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
if (-not (Test-Path -LiteralPath $VariablesTsv -PathType Leaf)) { throw "KV_VARIABLES_TSV_MISSING: $VariablesTsv" }

$rows = @(Import-Csv -LiteralPath $VariablesTsv -Delimiter "`t" -Encoding UTF8 | Where-Object { $_.name -and $_.status -ne 'display_name' })

$structures = @{}
if ($StructureDefinitionsPath) {
  if (-not (Test-Path -LiteralPath $StructureDefinitionsPath -PathType Leaf)) { throw "KV_STRUCTURE_DEFINITIONS_MISSING: $StructureDefinitionsPath" }
  $doc = Get-Content -LiteralPath $StructureDefinitionsPath -Raw -Encoding UTF8 | ConvertFrom-Json
  foreach ($s in @($doc.structures)) {
    $members = @()
    foreach ($m in @($s.members)) {
      if ($m.data_type) { $members += [pscustomobject]@{ name = [string]$m.name; data_type = [string]$m.data_type } }
    }
    $structures[[string]$s.name] = $members
  }
}
$fbSet = @{}
foreach ($t in $FbTypes) { $fbSet[[string]$t] = $true }
$axisSet = @{}
foreach ($i in $AxisIndexes) { $axisSet[[int]$i] = $true }

function Get-ArrayElement([string]$DataType) {
  $t = ([string]$DataType).Trim()
  if ($t -match '(?i)^ARRAY\[[^\]]*\]\s+OF\s+(.+)$') { return ([string]$matches[1]).Trim() }
  return ''
}
function Test-Scalar([string]$DataType) {
  $t = ([string]$DataType).Trim()
  return ($t -match '^(?i:BOOL|INT|DINT|UINT|UDINT|REAL|LREAL|TIME|WORD|DWORD|STRING(\[\d+\])?)$')
}
function Resolve-TypeDependencies([string]$DataType) {
  # Returns { depth: int, missing: string[] } for a type expression.
  $t = ([string]$DataType).Trim()
  if (-not $t) { return [pscustomobject]@{ depth = 0; missing = @('empty_type') } }
  if (Test-Scalar $t) { return [pscustomobject]@{ depth = 0; missing = @() } }
  $element = Get-ArrayElement $t
  if ($element) {
    $inner = Resolve-TypeDependencies $element
    return [pscustomobject]@{ depth = $inner.depth + 1; missing = @($inner.missing) }
  }
  if ($structures.ContainsKey($t)) {
    $missing = @()
    $depth = 1
    foreach ($member in $structures[$t]) {
      $inner = Resolve-TypeDependencies ([string]$member.data_type)
      $depth = [math]::Max($depth, $inner.depth + 1)
      $missing += @($inner.missing)
    }
    return [pscustomobject]@{ depth = $depth; missing = @($missing | Select-Object -Unique) }
  }
  if ($fbSet.ContainsKey($t)) { return [pscustomobject]@{ depth = 1; missing = @() } }
  return [pscustomobject]@{ depth = 1; missing = @("missing_type:$t") }
}

$results = New-Object System.Collections.Generic.List[object]
$requiredStructures = New-Object System.Collections.Generic.HashSet[string]
$requiredAxes = New-Object System.Collections.Generic.HashSet[int]
$requiredFbTypes = New-Object System.Collections.Generic.HashSet[string]
foreach ($row in $rows) {
  $deps = @()
  $missing = @()
  $typeInfo = Resolve-TypeDependencies ([string]$row.data_type)
  $missing += @($typeInfo.missing)
  if ($typeInfo.depth -gt 0) { $deps += "type_depth:$($typeInfo.depth)" }
  if ($structures.ContainsKey(([string]$row.data_type).Trim())) { [void]$requiredStructures.Add(([string]$row.data_type).Trim()) }

  $device = ([string]$row.device).Trim()
  if ($device -match '^_MC_Axis\[(\d+)\]$') {
    $index = [int]$matches[1]
    $deps += "axis:$index"
    [void]$requiredAxes.Add($index)
    if (-not $axisSet.ContainsKey($index)) { $missing += "missing_axis:$index" }
  } elseif ($device -match '^_MC_AxisGroup\[(\d+)\]$') {
    $index = [int]$matches[1]
    $deps += "axis_group:$index"
    if (-not $axisSet.ContainsKey($index)) { $missing += "missing_axis_group:$index" }
  }
  if ($fbSet.ContainsKey(([string]$row.data_type).Trim())) { [void]$requiredFbTypes.Add(([string]$row.data_type).Trim()) }

  $status = if (@($missing | Select-Object -Unique).Count -gt 0) { 'blocked' } else { 'ready' }
  $results.Add([pscustomobject]@{
    name = [string]$row.name
    scope = [string]$row.scope
    owner_program = [string]$row.owner_program
    data_type = [string]$row.data_type
    device = $device
    group = [string]$row.group
    status = $status
    dependencies = @($deps)
    missing = @($missing | Select-Object -Unique)
  })
}

$ready = @($results | Where-Object { $_.status -eq 'ready' })
$blocked = @($results | Where-Object { $_.status -eq 'blocked' })
$report = [ordered]@{
  ok = ($blocked.Count -eq 0)
  variables_tsv = $VariablesTsv
  structure_definitions_path = $StructureDefinitionsPath
  total = $results.Count
  ready_count = $ready.Count
  blocked_count = $blocked.Count
  required_structures = @($requiredStructures | Sort-Object)
  required_axes = @($requiredAxes | Sort-Object)
  required_fb_types = @($requiredFbTypes | Sort-Object)
  blocked = $blocked
  ready = $ready
  generated_at = (Get-Date).ToString('o')
}
$reportPath = Join-Path $OutDir 'variable_dependency_report.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
Write-Host ("KV_VARIABLE_DEPENDENCIES: ready={0} blocked={1} structures={2} axes={3} fb_types={4} report={5}" -f `
  $ready.Count, $blocked.Count, $report.required_structures.Count, $report.required_axes.Count, $report.required_fb_types.Count, $reportPath)
if ($RequireReady -and $blocked.Count -gt 0) { exit 41 }
exit 0
