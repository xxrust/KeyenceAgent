param([string]$OutRoot='', [switch]$PlanOnly, [switch]$KeepProjectOpen)
$runner=Join-Path (Split-Path -Parent $PSScriptRoot) 'run-workflow-test.ps1'
$a=@('-ScenarioPath',(Join-Path $PSScriptRoot 'scenario.json'))
if($OutRoot){$a+=@('-OutRoot',$OutRoot)}
if($PlanOnly){$a+='-PlanOnly'}
if($KeepProjectOpen){$a+='-KeepProjectOpen'}
& powershell -STA -NoProfile -ExecutionPolicy Bypass -File $runner @a
$exitCode=$LASTEXITCODE
if($exitCode -ne 0 -or $PlanOnly -or -not $OutRoot){ exit $exitCode }

# The import dialog saying "read N comments" is only a side signal. The accepted
# result is the re-export diff: every expected device/comment pair must be
# readable again from the project, with zero mismatches.
$runDir=@(Get-ChildItem -LiteralPath $OutRoot -Directory -ErrorAction SilentlyContinue |
  Where-Object { $_.Name -like '23_import_device_comments_*' } |
  Sort-Object LastWriteTime | Select-Object -Last 1)
if($runDir.Count -eq 0){ Write-Output 'FAIL: run directory not found under OutRoot'; exit 1 }
$verifyFiles=@(Get-ChildItem -LiteralPath $runDir[0].FullName -Recurse -Filter 'comment_import_verification.json' -File -ErrorAction SilentlyContinue)
if($verifyFiles.Count -eq 0){ Write-Output 'FAIL: comment_import_verification.json missing'; exit 1 }
$verification=Get-Content -Raw -LiteralPath $verifyFiles[0].FullName -Encoding UTF8 | ConvertFrom-Json
if($verification.ok -isnot [bool] -or -not $verification.ok -or [int]$verification.mismatch_count -ne 0 -or [int]$verification.verified -lt 3){
  Write-Output ('FAIL: verification ok={0} verified={1} mismatch={2}' -f $verification.ok, $verification.verified, $verification.mismatch_count)
  exit 1
}

# The comment bank lives in <project>.cm1; a run that imported but never saved
# leaves the import in memory only, so the saved flag and the bank itself are
# checked before the scenario is accepted.
$importResult=@(Get-ChildItem -LiteralPath $runDir[0].FullName -Recurse -Filter 'device_comments_import_result.json' -File -ErrorAction SilentlyContinue | Select-Object -First 1)
if($importResult.Count -eq 0){ Write-Output 'FAIL: device_comments_import_result.json missing'; exit 1 }
$import=Get-Content -Raw -LiteralPath $importResult[0].FullName -Encoding UTF8 | ConvertFrom-Json
if($import.saved -ne $true){ Write-Output 'FAIL: project was not saved after the import'; exit 1 }
$cm1=@(Get-ChildItem -LiteralPath (Split-Path -Parent ([IO.Path]::GetFullPath([string]$import.project_path))) -Filter '*.cm1' -File -ErrorAction SilentlyContinue | Select-Object -First 1)
if($cm1.Count -eq 0){ Write-Output 'FAIL: comment bank (*.cm1) not found next to the project'; exit 1 }
if($cm1[0].Length -le 0){ Write-Output 'FAIL: comment bank is empty'; exit 1 }
Write-Output ('comment import verified: {0} entries, mismatch=0, cm1={1} bytes' -f $verification.verified, $cm1[0].Length)
exit 0
