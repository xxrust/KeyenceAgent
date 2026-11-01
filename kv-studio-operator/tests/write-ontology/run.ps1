param([string]$WorkRoot = '')

$ErrorActionPreference = 'Stop'
$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
$gate = Join-Path $skillRoot 'scripts\gates\assert_kv_asset_coverage.ps1'
$ontologyPath = Join-Path $skillRoot 'assets\ontology.json'
if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-write-ontology-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null
$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') { $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail }) }

$validOut = Join-Path $WorkRoot 'valid'
& powershell -NoProfile -ExecutionPolicy Bypass -File $gate -OntologyPath $ontologyPath -OutDir $validOut *> (Join-Path $WorkRoot 'valid.stdout.txt')
$validExit = $LASTEXITCODE
$validResultPath = Join-Path $validOut 'asset_coverage_result.json'
$validResult = if (Test-Path -LiteralPath $validResultPath) { Get-Content -Raw -LiteralPath $validResultPath -Encoding UTF8 | ConvertFrom-Json } else { $null }
Add-Case 'published write ontology passes coverage gate' ($validExit -eq 0 -and $validResult -and $validResult.ok) "exit=$validExit"
Add-Case 'published and approved write routes plus acceptance recipe are enumerated' ($validResult -and $validResult.write_capability_count -ge 16 -and $validResult.write_recipe_count -ge 1) ''

$mutated = Get-Content -Raw -LiteralPath $ontologyPath -Encoding UTF8 | ConvertFrom-Json
$mutated.write_capabilities.create_project.depends_on = @('compile_project')
$invalidOntology = Join-Path $WorkRoot 'cycle.json'
$mutated | ConvertTo-Json -Depth 32 | Set-Content -LiteralPath $invalidOntology -Encoding UTF8
$cycleOut = Join-Path $WorkRoot 'cycle'
& powershell -NoProfile -ExecutionPolicy Bypass -File $gate -OntologyPath $invalidOntology -OutDir $cycleOut *> (Join-Path $WorkRoot 'cycle.stdout.txt')
$cycleExit = $LASTEXITCODE
$cycleResultPath = Join-Path $cycleOut 'asset_coverage_result.json'
$cycleResult = if (Test-Path -LiteralPath $cycleResultPath) { Get-Content -Raw -LiteralPath $cycleResultPath -Encoding UTF8 | ConvertFrom-Json } else { $null }
$cycleRejected = $cycleResult -and @($cycleResult.errors | Where-Object { $_.code -eq 'KV_WRITE_DEPENDENCY_CYCLE' }).Count -eq 1
Add-Case 'cyclic write dependency is rejected' ($cycleExit -ne 0 -and $cycleRejected) "exit=$cycleExit"

$failed = @($cases | Where-Object { -not $_.ok })
$result = [ordered]@{ test = 'write-ontology'; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
$result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 4
if ($failed.Count -gt 0) { exit 41 }
exit 0
