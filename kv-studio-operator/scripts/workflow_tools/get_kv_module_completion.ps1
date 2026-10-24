param(
  [Parameter(Mandatory=$true)][string]$PlanPath,
  [string]$ArtifactsRoot = '',
  [string]$OutDir = '',
  [switch]$AllowIncomplete
)
# Module completeness gate: a module is complete only when its MNM import, its
# local variables (and FB arguments for function blocks) have succeeded in this
# run. Compile output over an incomplete project is noise, so check this first.
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $PlanPath -PathType Leaf)) { throw "KV_PLAN_MISSING: $PlanPath" }
$plan = Get-Content -LiteralPath $PlanPath -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $ArtifactsRoot) { $ArtifactsRoot = [string]$plan.artifact_root }
if (-not $OutDir) { $OutDir = Join-Path $ArtifactsRoot 'module_completion' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function Read-JsonOrNull([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try { return (Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json) } catch { return $null }
}
function Get-SafeModule([string]$Name) { return ($Name -replace '[^A-Za-z0-9_.-]+', '_') }

$sets = @($plan.variable_sets)
$modules = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $sets.Count; $i++) {
  $set = $sets[$i]
  $module = [string]$set.module_name
  $safe = Get-SafeModule $module
  $number = $i + 1
  $importReceipt = Read-JsonOrNull (Join-Path $ArtifactsRoot ("import_mnm_$number\step_receipt.json"))
  $placementReceipt = Read-JsonOrNull (Join-Path $ArtifactsRoot ("module_placement\$module\step_receipt.json"))
  $argsReceipt = Read-JsonOrNull (Join-Path $ArtifactsRoot ("set_fb_arguments\module_{0:D2}_{1}\step_receipt.json" -f $number, $safe))
  $varResult = Read-JsonOrNull (Join-Path $ArtifactsRoot ("set_variables\module_{0:D2}_{1}\set_variables_result.json" -f $number, $safe))

  $importOk = [bool]($importReceipt -and $importReceipt.ok)
  $placementOk = if ($placementReceipt) { [bool]$placementReceipt.ok } else { $true }
  $argsOk = if ($argsReceipt) { [bool]$argsReceipt.ok } else { $true }
  $varsOk = [bool]($varResult -and $varResult.ok)
  $reason = @()
  if (-not $importOk) { $reason += 'import_missing_or_failed' }
  if ($argsReceipt -and -not $argsOk) { $reason += 'fb_arguments_missing_or_failed' }
  if (-not $varsOk) {
    if ($varResult -and $varResult.error_code) { $reason += "variables:$($varResult.error_code)" }
    else { $reason += 'variables_missing_or_failed' }
  }
  if ($placementReceipt -and -not $placementOk) { $reason += 'placement_failed' }
  $modules.Add([pscustomobject]@{
    number = $number
    module = $module
    category = [string]$set.category
    import_ok = $importOk
    placement_ok = $placementOk
    fb_arguments_ok = $argsOk
    variables_ok = $varsOk
    complete = ($reason.Count -eq 0)
    reasons = @($reason)
  })
}

$incomplete = @($modules | Where-Object { -not $_.complete })
$report = [ordered]@{
  ok = ($incomplete.Count -eq 0)
  plan_path = $PlanPath
  artifacts_root = $ArtifactsRoot
  total_modules = $modules.Count
  complete_modules = @($modules | Where-Object { $_.complete }).Count
  incomplete_count = $incomplete.Count
  incomplete = @($incomplete | ForEach-Object { [pscustomobject]@{ module = $_.module; reasons = $_.reasons } })
  modules = $modules.ToArray()
  generated_at = (Get-Date).ToString('o')
}
$reportPath = Join-Path $OutDir 'module_completion.json'
$report | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $reportPath -Encoding UTF8
$report | ConvertTo-Json -Depth 4

Write-Host ("KV_MODULE_COMPLETION: complete={0}/{1} incomplete={2} report={3}" -f $report.complete_modules, $report.total_modules, $report.incomplete_count, $reportPath)
if ($report.incomplete_count -gt 0 -and -not $AllowIncomplete) { exit 41 }
exit 0
