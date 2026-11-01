param([string]$OutRoot='', [switch]$PlanOnly, [switch]$KeepProjectOpen)
if ($args.Count -gt 0) {
  [Console]::Error.WriteLine("Unknown argument(s): $($args -join ' ')")
  exit 64
}
$runner=Join-Path (Split-Path -Parent $PSScriptRoot) 'run-workflow-test.ps1'
$a=@('-ScenarioPath',(Join-Path $PSScriptRoot 'scenario.json'))
if($OutRoot){$a+=@('-OutRoot',$OutRoot)}
if($PlanOnly){$a+='-PlanOnly'}
if($KeepProjectOpen){$a+='-KeepProjectOpen'}
& powershell -STA -NoProfile -ExecutionPolicy Bypass -File $runner @a
exit $LASTEXITCODE
