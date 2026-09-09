param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$PlanPath,
  [Parameter(Mandatory=$true)][string]$OutDir
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$manifestPath = Join-Path $root 'script_manifest.json'
$workflowRelativePath = 'workflows/mutate_kv_structure_definitions.ps1'
$manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
$entry = @($manifest.classes.customer_workflow | Where-Object { ([string]$_.path).Replace('\','/') -eq $workflowRelativePath })
if ($entry.Count -ne 1 -or @($entry[0].runner_children).Count -ne 1) { throw 'Structure mutation workflow must declare exactly one runner child in script_manifest.json.' }
$childRelativePath = [string]$entry[0].runner_children[0]
$approvedChildren = @($manifest.classes.runner_child_approved | ForEach-Object { ([string]$_.path).Replace('\','/') })
if ($approvedChildren -notcontains $childRelativePath.Replace('\','/')) { throw "Structure mutation runner child is not approved: $childRelativePath" }
$child = Join-Path $root $childRelativePath
if (-not (Test-Path -LiteralPath $child -PathType Leaf)) { throw "Structure mutation runner child not found: $child" }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$runLog = Join-Path $OutDir 'run.log'
$env:KV_WORKFLOW_RUN_LOG = $runLog
@{timestamp=(Get-Date).ToString('o');type='workflow_preflight_started';workflow=$workflowRelativePath;runner_child=$childRelativePath} | ConvertTo-Json -Compress | Add-Content -LiteralPath $runLog -Encoding UTF8
$gate = Join-Path $root 'gates\assert_kv_mvp_ui_guard_usage.ps1'
$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
$gateOutput = @(& powershell -NoProfile -ExecutionPolicy Bypass -File $gate -ScriptsRoot $root -ManifestPath $manifestPath -OutDir (Join-Path $OutDir 'ui_guard_preflight') -ScriptNames $childRelativePath 2>&1)
$gateExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
if ($gateExitCode -ne 0) {
  @{timestamp=(Get-Date).ToString('o');type='workflow_preflight_failed';workflow=$workflowRelativePath;runner_child=$childRelativePath;exit_code=$gateExitCode;gate_output=($gateOutput -join "`n")} | ConvertTo-Json -Compress | Add-Content -LiteralPath $runLog -Encoding UTF8
  exit $gateExitCode
}
@{timestamp=(Get-Date).ToString('o');type='workflow_preflight_passed';workflow=$workflowRelativePath;runner_child=$childRelativePath} | ConvertTo-Json -Compress | Add-Content -LiteralPath $runLog -Encoding UTF8
& $child -ProjectPath $ProjectPath -PlanPath $PlanPath -OutDir $OutDir
exit $LASTEXITCODE
