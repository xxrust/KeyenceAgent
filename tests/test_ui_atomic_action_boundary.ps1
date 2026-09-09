param([string]$OutDir = (Join-Path ([IO.Path]::GetTempPath()) ('kv_ui_atomic_boundary_' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
$repoRoot = Split-Path -Parent $PSScriptRoot
$sourceScripts = Join-Path $repoRoot 'kv-studio-operator\scripts'
$fixtureScripts = Join-Path $OutDir 'scripts'
$fixtureGuardDir = Join-Path $fixtureScripts 'guards'
$fixtureRunnerDir = Join-Path $fixtureScripts 'runner_children'
$gate = Join-Path $sourceScripts 'gates\assert_kv_mvp_ui_guard_usage.ps1'
New-Item -ItemType Directory -Force -Path $fixtureGuardDir,$fixtureRunnerDir | Out-Null
Copy-Item -LiteralPath (Join-Path $sourceScripts 'guards\kv_ui_guard.ps1') -Destination (Join-Path $fixtureGuardDir 'kv_ui_guard.ps1')
Copy-Item -LiteralPath (Join-Path $sourceScripts 'script_manifest.json') -Destination (Join-Path $fixtureScripts 'script_manifest.json')

$approvedFixture = Join-Path $fixtureRunnerDir 'approved_fixture.ps1'
$rejectedFixture = Join-Path $fixtureRunnerDir 'rejected_fixture.ps1'
[IO.File]::WriteAllText($approvedFixture, "Invoke-KvGuardedSendKeys -TargetHwnd 1 -Step 'fixture' -Keys 'x'`r`n")
[IO.File]::WriteAllText($rejectedFixture, "Invoke-KvGuardedUnapprovedChord -TargetHwnd 1 -Step 'fixture'`r`n")

& powershell -NoProfile -ExecutionPolicy Bypass -File $gate -ScriptsRoot $fixtureScripts -ManifestPath (Join-Path $fixtureScripts 'script_manifest.json') -OutDir (Join-Path $OutDir 'approved') -ScriptNames 'runner_children/approved_fixture.ps1' | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Approved atomic action fixture was rejected.' }

$previousErrorActionPreference = $ErrorActionPreference
$ErrorActionPreference = 'Continue'
& powershell -NoProfile -ExecutionPolicy Bypass -File $gate -ScriptsRoot $fixtureScripts -ManifestPath (Join-Path $fixtureScripts 'script_manifest.json') -OutDir (Join-Path $OutDir 'rejected') -ScriptNames 'runner_children/rejected_fixture.ps1' *> (Join-Path $OutDir 'rejected_output.txt')
$rejectedExitCode = $LASTEXITCODE
$ErrorActionPreference = $previousErrorActionPreference
if ($rejectedExitCode -eq 0) { throw 'Unapproved atomic action fixture was accepted.' }
$findings = @(Get-Content -Raw -Encoding UTF8 (Join-Path $OutDir 'rejected\kv_ui_guard_usage_findings.json') | ConvertFrom-Json)
if (@($findings | Where-Object { $_.pattern -eq 'UnapprovedAtomicAction' -and $_.text -like 'Invoke-KvGuardedUnapprovedChord*' }).Count -ne 1) {
  throw 'Unapproved atomic action did not produce the required finding.'
}

$manifest = Get-Content -Raw -Encoding UTF8 (Join-Path $sourceScripts 'script_manifest.json') | ConvertFrom-Json
$workflowRelative = 'workflows/mutate_kv_structure_definitions.ps1'
$workflowEntry = @($manifest.classes.customer_workflow | Where-Object { ([string]$_.path).Replace('\','/') -eq $workflowRelative })
if ($workflowEntry.Count -ne 1 -or @($workflowEntry[0].runner_children).Count -ne 1) {
  throw 'Structure workflow does not declare exactly one runner child.'
}
$approvedChildren = @($manifest.classes.runner_child_approved | ForEach-Object { ([string]$_.path).Replace('\','/') })
if ($approvedChildren -notcontains ([string]$workflowEntry[0].runner_children[0]).Replace('\','/')) {
  throw 'Structure workflow dependency is not an approved runner child.'
}
$workflowText = Get-Content -Raw -Encoding UTF8 (Join-Path $sourceScripts $workflowRelative)
$gateIndex = $workflowText.IndexOf('assert_kv_mvp_ui_guard_usage.ps1')
$runnerIndex = $workflowText.LastIndexOf('& $child')
if ($gateIndex -lt 0 -or $runnerIndex -lt 0 -or $gateIndex -ge $runnerIndex) {
  throw 'Structure workflow does not execute the UI atomic-action gate before its runner child.'
}

[pscustomobject]@{
  ok = $true
  approved_fixture_passed = $true
  unapproved_fixture_rejected = $true
  workflow_preflight_precedes_runner = $true
  desktop_input = $false
  evidence = $OutDir
} | ConvertTo-Json -Depth 4
