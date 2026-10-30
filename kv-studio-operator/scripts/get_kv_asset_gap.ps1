param(
  [Parameter(Mandatory=$true)][string]$Asset,
  [switch]$Json,
  [switch]$CheckEvidence
)
# The only sanctioned source for "what is missing" statements.
# It resolves an asset against assets/ontology.json and reports whether the
# gap is a capability gap (missing_route) or only a snapshot wiring gap.
$ErrorActionPreference = 'Stop'
$scriptsRoot = $PSScriptRoot
$skillRoot = Split-Path -Parent $scriptsRoot
$ontologyPath = Join-Path $skillRoot 'assets\ontology.json'
if (-not (Test-Path -LiteralPath $ontologyPath -PathType Leaf)) { throw "KV_ONTOLOGY_MISSING: $ontologyPath" }
$ontology = Get-Content -Raw -LiteralPath $ontologyPath -Encoding UTF8 | ConvertFrom-Json
$assetNode = $ontology.assets.PSObject.Properties[$Asset]
if (-not $assetNode) {
  $unknown = [ordered]@{ ok = $false; asset = $Asset; error = 'KV_ASSET_NOT_DECLARED'; message = "Asset '$Asset' is not in assets/ontology.json. Declare it before talking about gaps." }
  if ($Json) { $unknown | ConvertTo-Json -Depth 6 } else { "UNKNOWN: $($unknown.message)" }
  exit 3
}
$value = $assetNode.Value
$status = [string]$value.snapshot_status
$capabilities = @()
foreach ($capability in @($ontology.capabilities.PSObject.Properties)) {
  if (@($capability.Value.assets) -contains $Asset) {
    $evidence = @()
    foreach ($item in @($capability.Value.evidence)) {
      if (-not $item) { continue }
      $path = [string]$item
      $resolved = if ([IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $skillRoot $path }
      $exists = Test-Path -LiteralPath $resolved
      $evidence += [ordered]@{ item = $path; exists = $exists }
    }
    $scriptPath = Join-Path $scriptsRoot ([string]$capability.Value.script)
    $capabilities += [ordered]@{
      name = $capability.Name
      script = [string]$capability.Value.script
      script_exists = (Test-Path -LiteralPath $scriptPath -PathType Leaf)
      evidence = $evidence
    }
  }
}
$capabilityNames = @($capabilities | ForEach-Object { $_.name })
$verdict = switch ($status) {
  'wired' { 'WIRED' }
  'wired_limited' { 'WIRED_LIMITED' }
  'not_wired' { 'NOT_WIRED' }
  'missing_route' { 'MISSING_ROUTE' }
  default { 'UNKNOWN_STATUS' }
}
$phrasing = switch ($status) {
  'wired' { "已接入快照，产物：$($value.snapshot_artifact)" }
  'wired_limited' { "已接入快照但有限制：$($value.limited_reason)" }
  'not_wired' { "能力已存在（$($capabilityNames -join ', ')），只是还没接进快照 stage" }
  'missing_route' { "没有可用读取路线：$($value.missing_reason)" }
  default { "未知状态：$status" }
}
$errors = @()
if ($status -in @('wired', 'wired_limited') -and $capabilityNames.Count -eq 0) { $errors += 'wired asset has no capability' }
if ($status -eq 'not_wired' -and $capabilityNames.Count -eq 0) { $errors += 'not_wired asset has no capability (must be missing_route)' }
if ($status -eq 'missing_route' -and $capabilityNames.Count -gt 0) { $errors += 'missing_route asset has a capability; it must be not_wired' }
if ($CheckEvidence) {
  foreach ($capability in $capabilities) {
    if (-not $capability.script_exists) { $errors += "capability $($capability.name) script missing: $($capability.script)" }
    if (@($capability.evidence | Where-Object { $_.exists }).Count -eq 0) { $errors += "capability $($capability.name) has no existing evidence" }
  }
}
$result = [ordered]@{
  ok = ($errors.Count -eq 0)
  asset = $Asset
  status = $status
  verdict = $verdict
  snapshot_stage = [string]$value.snapshot_stage
  snapshot_artifact = [string]$value.snapshot_artifact
  capabilities = $capabilities
  allowed_phrasing = $phrasing
  errors = $errors
}
if ($Json) {
  $result | ConvertTo-Json -Depth 8
} else {
  "ASSET       $Asset"
  "STATUS      $status ($verdict)"
  "CAPABILITY  $(if ($capabilityNames.Count) { $capabilityNames -join ', ' } else { '(none)' })"
  "PHRASING    $phrasing"
  foreach ($errorItem in $errors) { "ERROR       $errorItem" }
}
if ($errors.Count -gt 0) { exit 2 }
exit 0
