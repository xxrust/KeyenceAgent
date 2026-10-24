param([string]$OutRoot='', [switch]$PlanOnly, [switch]$KeepProjectOpen)
$runner=Join-Path (Split-Path -Parent $PSScriptRoot) 'run-workflow-test.ps1'
$a=@('-ScenarioPath',(Join-Path $PSScriptRoot 'scenario.json'))
if($OutRoot){$a+=@('-OutRoot',$OutRoot)}
if($PlanOnly){$a+='-PlanOnly'}
if($KeepProjectOpen){$a+='-KeepProjectOpen'}
& powershell -STA -NoProfile -ExecutionPolicy Bypass -File $runner @a
$exitCode=$LASTEXITCODE
if($exitCode -ne 0 -or $PlanOnly -or -not $OutRoot){ exit $exitCode }

# The snapshot must now include ordinary program locals, not only FB locals.
# This is a post-run assertion on the same run directory the harness created.
$runDir=@(Get-ChildItem -LiteralPath $OutRoot -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like '13_project_text_snapshot_*' } |
  Sort-Object LastWriteTime | Select-Object -Last 1)
if($runDir.Count -eq 0){ Write-Output 'FAIL: run directory not found under OutRoot'; exit 1 }
$manifestPath=@(Get-ChildItem -LiteralPath $runDir[0].FullName -Recurse -Filter 'source_snapshot_manifest.json' -File -ErrorAction SilentlyContinue | Select-Object -First 1)
if($manifestPath.Count -eq 0){ Write-Output 'FAIL: source_snapshot_manifest.json not found'; exit 1 }
$manifest=Get-Content -Raw -LiteralPath $manifestPath[0].FullName -Encoding UTF8 | ConvertFrom-Json
$programModules=@($manifest.discovered_program_local_modules)
if($programModules.Count -eq 0){ Write-Output 'FAIL: discovered_program_local_modules is empty'; exit 1 }
$variablesResultPath=Join-Path $manifestPath[0].Directory.FullName 'text\variables\variable_snapshot_result.json'
if(-not(Test-Path -LiteralPath $variablesResultPath -PathType Leaf)){ Write-Output 'FAIL: text\variables\variable_snapshot_result.json missing'; exit 1 }
$variablesResult=Get-Content -Raw -LiteralPath $variablesResultPath -Encoding UTF8 | ConvertFrom-Json
$localOwners=@($variablesResult.snapshots | Where-Object { [string]$_.scope -eq 'local' } | ForEach-Object { [string]$_.owner_program })
$covered=@($programModules | Where-Object { $localOwners -contains $_ })
if($covered.Count -eq 0){ Write-Output ('FAIL: no program local snapshot matched ' + ($programModules -join ',')); exit 1 }
Write-Output ('program-local coverage: {0}/{1} modules' -f $covered.Count,$programModules.Count)
exit 0
