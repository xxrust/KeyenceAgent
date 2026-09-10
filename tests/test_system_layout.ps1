param([string]$OutDir = (Join-Path ([IO.Path]::GetTempPath()) ('kv_layout_'+[guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$repo=Split-Path -Parent $PSScriptRoot
$root=Join-Path $repo 'kv-studio-operator/scripts'
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
$entries=@(Get-KvStudioOperatorManifestEntries -ScriptRoot $root)
$files=@(Get-ChildItem -LiteralPath $root -File -Recurse -Filter '*.ps1')
foreach ($file in $files) {
  $rel=$file.FullName.Substring($root.Length+1).Replace('\','/')
  if (@($entries | Where-Object path -eq $rel).Count -ne 1) { throw "KV_SCRIPT_CLASSIFICATION_NOT_UNIQUE: $rel" }
  $tokens=$null;$errors=$null
  $null=[Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$errors)
  if ($errors.Count) { throw "KV_SCRIPT_PARSE_FAILED: $rel" }
}
if (@($files | Group-Object Name | Where-Object Count -gt 1).Count) { throw 'KV_DUPLICATE_ACTIVE_SCRIPT_NAMES' }
foreach ($entry in $entries) { $null=Resolve-KvStudioOperatorScriptPath -ScriptRoot $root -Name $entry.path -Classes @($entry.class) }
foreach ($entry in @($entries | Where-Object class -eq 'customer_workflow')) {
  if (-not $entry.runner_children.Count -or $entry.execution -ne 'flat_manifest_steps') { throw "KV_WORKFLOW_DEPENDENCIES_REQUIRED: $($entry.path)" }
  foreach ($child in $entry.runner_children) { $null=Resolve-KvStudioOperatorScriptPath -ScriptRoot $root -Name $child -Classes runner_child_approved }
}
$query=& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'get_kv_capabilities.ps1') -Capability snapshot_fb_arguments | ConvertFrom-Json
if (-not $query.ok -or $query.operations.Count -ne 1 -or @($query.operations[0].parameters | Where-Object name -eq SnapshotOnly).Count -ne 1) { throw 'KV_PUBLIC_CAPABILITY_DISCOVERY_FAILED' }
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
@{ok=$true;active_scripts=$files.Count;unclassified=0;duplicate_names=0;desktop_input=$false} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $OutDir 'test_result.json')
