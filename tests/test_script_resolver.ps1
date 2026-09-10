param([string]$RepoRoot = (Split-Path -Parent $PSScriptRoot))
$ErrorActionPreference = 'Stop'
$scripts = Join-Path $RepoRoot 'kv-studio-operator/scripts'
. (Join-Path $scripts 'Resolve-KvStudioOperatorScript.ps1')
$expected = Join-Path $scripts 'workflows/set_kv_fb_arguments.ps1'
foreach ($name in @('set_kv_fb_arguments.ps1','workflows/set_kv_fb_arguments.ps1',$expected)) {
  $actual = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scripts -Name $name -Classes customer_workflow
  if ($actual -ne [IO.Path]::GetFullPath($expected)) { throw "Wrong resolved path: $actual" }
}
$rejected = 0
foreach ($case in @(
  @{name=$expected;classes=@('gate')},
  @{name=(Join-Path $RepoRoot 'scripts/audit_keyence_system.ps1');classes=@()},
  @{name='../../scripts/audit_keyence_system.ps1';classes=@()},
  @{name='Resolve-KvStudioOperatorScript.ps1';classes=@('customer_workflow')},
  @{name='missing.ps1';classes=@('gate')}
)) {
  try { $null = Resolve-KvStudioOperatorScriptPath -ScriptRoot $scripts -Name $case.name -Classes $case.classes }
  catch { $rejected++; continue }
  throw "Resolver accepted forbidden route: $($case.name)"
}
[pscustomobject]@{ok=$true;valid_routes=3;rejected_routes=$rejected} | ConvertTo-Json
