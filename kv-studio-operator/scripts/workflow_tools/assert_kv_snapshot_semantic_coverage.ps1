param(
  [Parameter(Mandatory=$true)][string]$SnapshotRoot,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string[]]$AllowUnresolved = @()
)
$ErrorActionPreference = 'Stop'
$snapshotRoot = [IO.Path]::GetFullPath($SnapshotRoot)
$outRoot = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
$skillRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# Semantic coverage gate: a snapshot-derived analysis may not silently lose a whole
# category.  Every category reports its count, system types must be present when the
# project declares them, and a symbol used with member access that resolves to nothing
# is treated as an analysis defect rather than noise.
$structurePath = Join-Path $outRoot 'structure.json'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'extract_kv_project_structure.ps1') `
  -SnapshotRoot $snapshotRoot -OutPath $structurePath | Out-Null
$structure = Get-Content -Raw -LiteralPath $structurePath -Encoding UTF8 | ConvertFrom-Json

$symbolsPath = Join-Path $outRoot 'symbols.json'
& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'resolve_kv_symbols.ps1') `
  -SnapshotRoot $snapshotRoot -OutPath $symbolsPath | Out-Null
$symbols = Get-Content -Raw -LiteralPath $symbolsPath -Encoding UTF8 | ConvertFrom-Json

$failures = New-Object System.Collections.Generic.List[string]
foreach ($category in @('programs', 'function_blocks', 'user_data_types', 'system_data_types')) {
  if (-not $structure.PSObject.Properties[$category]) { $failures.Add("category_missing:$category") | Out-Null }
}
if ([int]$structure.program_count -lt 1) { $failures.Add('no_programs_extracted') | Out-Null }
if (-not $structure.data_type_counts) { $failures.Add('data_type_counts_missing') | Out-Null }
if (-not $structure.data_type_notes) { $failures.Add('data_type_omissions_not_declared') | Out-Null }
if ([int]$structure.data_type_counts.system -eq 0) {
  # A project that declares system types (motion, units, project info) must report them.
  $inventory = Get-Content -Raw -LiteralPath (Join-Path $snapshotRoot 'text\project_inventory.json') -Encoding UTF8 | ConvertFrom-Json
  $declaredSystem = @(@($inventory.data_types) | Where-Object { $_.path_text -match '\(System\)' }).Count
  if ($declaredSystem -gt 0) { $failures.Add("system_types_lost:declared=$declaredSystem") | Out-Null }
}
$unresolved = @($symbols.unresolved_symbols)
$programScope = @($structure.programs | ForEach-Object { $_.name })
foreach ($u in $unresolved) {
  $scope = $(if ($u.scope) { [string]$u.scope } elseif ($programScope -contains $u.first_module) { 'program' } else { 'body' })
  if ($scope -eq 'program' -and $AllowUnresolved -notcontains $u.name) { $failures.Add('unresolved_symbol_in_program:' + $u.name + '@' + $u.first_module + ':' + $u.first_line) | Out-Null }
}
if (-not $symbols.counts.by_class) { $failures.Add('symbol_classes_missing') | Out-Null }

$result = [ordered]@{
  schema_version = 1
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  ok = ($failures.Count -eq 0)
  snapshot_root = $snapshotRoot
  categories = [ordered]@{
    programs = [int]$structure.program_count
    function_blocks = @($structure.function_blocks).Count
    user_data_types = [int]$structure.data_type_counts.user
    system_data_types = [int]$structure.data_type_counts.system
    symbols = [int]$symbols.counts.symbols
    unresolved_symbols = [int]$symbols.counts.unresolved
    unresolved_in_programs = [int]$symbols.counts.unresolved_in_programs
    unresolved_in_bodies = [int]$symbols.counts.unresolved_in_bodies
  }
  symbol_classes = $symbols.counts.by_class
  failures = @($failures)
  artifacts = [ordered]@{ structure = $structurePath; symbols = $symbolsPath }
  scope_note = 'counts prove that a category was not silently dropped; they do not prove the analysis is complete beyond the snapshot routes'
}
[IO.File]::WriteAllText((Join-Path $outRoot 'semantic_coverage_result.json'), ($result | ConvertTo-Json -Depth 8), (New-Object System.Text.UTF8Encoding($false)))
$result | ConvertTo-Json -Depth 6
if (-not $result.ok) { exit 1 }
exit 0
