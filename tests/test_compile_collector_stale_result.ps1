param([Parameter(Mandatory=$true)][string]$OutDir,[Parameter(Mandatory=$true)][string]$ChecklistPath)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null
# No matching process is intentional: failure must replace a previous success.
@{ok=$true;marker='stale'} | ConvertTo-Json | Set-Content (Join-Path $OutDir 'result.json') -Encoding UTF8
$tool=Join-Path (Split-Path -Parent $PSScriptRoot) 'kv-studio-operator\scripts\runner_children\copy_convert_result_from_tree_handle.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -ProjectNeedle ('Missing_'+[guid]::NewGuid().ToString('N')) -OutDir $OutDir -ChecklistPath $ChecklistPath
if ($LASTEXITCODE -eq 0) {throw 'Missing project unexpectedly accepted.'}
$r=Get-Content (Join-Path $OutDir 'result.json') -Encoding UTF8 -Raw | ConvertFrom-Json
if ($r.ok -or $r.marker -eq 'stale' -or $r.compile_success_verified) {throw 'Stale success survived failure.'}
'Stale result regression passed.'
