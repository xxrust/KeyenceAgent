param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$MnmDir,[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$tool=Join-Path (Split-Path -Parent $PSScriptRoot) 'kv-studio-operator\scripts\export_kv_project_inventory.ps1'
& powershell -NoProfile -ExecutionPolicy Bypass -File $tool -ProjectPath $ProjectPath -MnmDir $MnmDir -OutDir $OutDir | Out-Null
if($LASTEXITCODE -ne 0){throw 'Inventory extraction failed.'}
$r=Get-Content (Join-Path $OutDir 'project_inventory.json') -Raw -Encoding UTF8 | ConvertFrom-Json
if (-not $r.topology -or -not $r.topology.motion -or -not ($r.topology.motion.PSObject.Properties.Name -contains 'axes')) {throw 'Motion inventory schema missing.'}
$programMnm=@($r.mnm_inventory | Where-Object {$_.module_type -eq 0} | ForEach-Object {$_.module_name} | Sort-Object)
$programTree=@($r.program_modules | ForEach-Object {$_.module_name} | Sort-Object)
if ($programMnm.Count -ne 24 -or $programTree.Count -ne 24) {throw 'Sample must contain all 24 ordinary programs.'}
if(@(Compare-Object $programMnm $programTree).Count){throw 'Program inventory differs from exported MNM module names.'}
$orders=@($r.program_modules | ForEach-Object {$_.execution_order} | Sort-Object)
if(@($orders | Group-Object | Where-Object {$_.Count -gt 1}).Count){throw 'Duplicate execution order.'}
if(@($r.topology.motion.axes | Where-Object {$_.tree_text -match 'SV630_1Axis_03713'}).Count){throw 'Device model falsely classified as axis.'}
$typeRootName=-join ([char[]](0x6570,0x636E,0x7C7B,0x578B))
if(@($r.data_types | Where-Object {-not $_.path_text.StartsWith($typeRootName+' >')}).Count){throw 'Non-type tree entry classified as data type.'}
if(-not ($r.data_types.name -contains 'strCylinderCtrl')){throw 'Sample user structure missing.'}
$result=[pscustomobject]@{ok=$true;program_count=$programTree.Count;data_type_count=$r.data_types.Count;basis='independent MNM names versus tree inventory; original sample user structure; category bounds'}
$result | ConvertTo-Json | Set-Content (Join-Path $OutDir 'inventory_test_result.json') -Encoding UTF8
$result | ConvertTo-Json
