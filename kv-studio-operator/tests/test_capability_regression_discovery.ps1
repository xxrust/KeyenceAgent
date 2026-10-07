param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$skillRoot=Split-Path -Parent $PSScriptRoot
$query=Join-Path $skillRoot 'scripts/get_kv_capabilities.ps1'
$actual=(& powershell -NoProfile -ExecutionPolicy Bypass -File $query | Out-String)|ConvertFrom-Json
if($LASTEXITCODE -ne 0 -or -not $actual.ok){throw 'Discovery failed'}
$results=@()
$scenarioDirectories=@(Get-ChildItem -LiteralPath (Join-Path $PSScriptRoot 'kv-interface-regression') -Directory|Where-Object {$_.Name -match '^\d\d_'})
foreach($directory in $scenarioDirectories){
  $scenarioPath=Join-Path $directory.FullName 'scenario.json'
  $scenario=Get-Content -Raw -LiteralPath $scenarioPath -Encoding UTF8|ConvertFrom-Json
  $operation=@($actual.operations|Where-Object {[IO.Path]::GetFullPath($_.path) -eq [IO.Path]::GetFullPath((Join-Path $skillRoot $scenario.workflow))})
  if($operation.Count -ne 1){throw "Workflow discovery missing: $($scenario.name)"}
  $match=@($operation[0].regression_scenarios|Where-Object {$_.name -eq $scenario.name})
  if($match.Count -ne 1 -or $match[0].scenario_path -ne $scenarioPath -or -not (Test-Path -LiteralPath $match[0].readme_path) -or $match[0].command -notlike '*run.ps1*'){throw "Regression contract discovery mismatch: $($scenario.name)"}
  $mode=if($scenario.project_mode){$scenario.project_mode}else{'sample_copy'}
  if($match[0].project_mode -ne $mode -or ($match[0].arguments|ConvertTo-Json -Compress) -ne ($scenario.arguments|ConvertTo-Json -Compress)){throw "Scenario semantics mismatch: $($scenario.name)"}
  $outcome=if($scenario.expected_outcome){$scenario.expected_outcome}else{'success'}
  if($match[0].expected_outcome -ne $outcome -or $match[0].source_project -ne $scenario.source_project -or $match[0].expected_compile_result -ne $scenario.expected_compile_result){throw "Scenario expected outcome mismatch: $($scenario.name)"}
  foreach($fixture in @($match[0].fixture_paths)){if(-not (Test-Path -LiteralPath $fixture -PathType Leaf) -or $fixture -notlike "$($directory.FullName)\fixtures\*"){throw 'Fixture outside maintained scenario'}}
  $results+=@{name=$scenario.name;project_mode=$mode;ok=$true}
}
if($results.Count -ne $scenarioDirectories.Count){throw "Scenario discovery count mismatch: expected $($scenarioDirectories.Count), got $($results.Count)"}
New-Item -ItemType Directory -Force -Path $OutDir|Out-Null
@{ok=$true;ui_started=$false;tests=$results}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($results.Count) public regression discovery checks."
