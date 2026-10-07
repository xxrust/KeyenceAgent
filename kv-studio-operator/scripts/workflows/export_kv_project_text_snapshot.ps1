param(
  [Parameter(Mandatory=$true)][string]$ProjectPath,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [int]$TimeoutSeconds = 600,
  [switch]$PlanOnly,
  [switch]$KeepProjectOpen
)
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$snapshotScript = Join-Path $root 'export_kv_project_text_snapshot.ps1'
if (-not (Test-Path -LiteralPath $snapshotScript -PathType Leaf)) { throw "Snapshot script missing: $snapshotScript" }
$snapshotId = 'snapshot'
$args = @('-ProjectPath',$ProjectPath,'-OutDir',$OutDir,'-SnapshotId',$snapshotId,'-TimeoutSeconds',[string]$TimeoutSeconds)
if ($PlanOnly) { $args += '-PlanOnly' }
if ($KeepProjectOpen) { $args += '-KeepProjectOpen' }
& powershell -STA -NoProfile -ExecutionPolicy Bypass -File $snapshotScript @args
$exit = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }
$snapshotRoot = Join-Path $OutDir $snapshotId
$manifestPath = Join-Path $snapshotRoot 'source_snapshot_manifest.json'
$manifest = $null
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
  try { $manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json } catch {}
}
$result = [ordered]@{
  ok = ($exit -eq 0 -and $manifest -and (($PlanOnly) -or [string]$manifest.status -eq 'ready'))
  planned = [bool]$PlanOnly
  project_path = $ProjectPath
  snapshot_root = $snapshotRoot
  manifest_path = $manifestPath
  status = if ($manifest) { [string]$manifest.status } else { 'missing' }
  missing_capabilities = if ($manifest) { @($manifest.missing_capabilities) } else { @('snapshot_manifest') }
  generated_text_index = Join-Path $snapshotRoot 'text_index.json'
}
$result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $OutDir 'workflow_result.json') -Encoding UTF8
if ($result.ok) { exit 0 }
$finalExit = 1
if ($exit -ne 0) { $finalExit = $exit }
exit $finalExit
