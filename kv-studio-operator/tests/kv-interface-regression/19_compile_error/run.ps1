param([string]$OutRoot='', [switch]$PlanOnly, [switch]$KeepProjectOpen)
$runner=Join-Path (Split-Path -Parent $PSScriptRoot) 'run-workflow-test.ps1'
$arguments=@('-ScenarioPath',(Join-Path $PSScriptRoot 'scenario.json'))
if($OutRoot){$arguments+=@('-OutRoot',$OutRoot)}
if($PlanOnly){$arguments+='-PlanOnly'}
if($KeepProjectOpen){$arguments+='-KeepProjectOpen'}
& powershell -STA -NoProfile -ExecutionPolicy Bypass -File $runner @arguments
exit $LASTEXITCODE
