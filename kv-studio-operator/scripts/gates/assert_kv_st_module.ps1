param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$ContractPath,[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'workflow_tools/kv_st_module_contract.ps1')
$null=New-Item -ItemType Directory -Force -Path $OutDir
try{
  $checked=Read-KvStModuleContract $ContractPath $ProjectPath
  $result=@{ok=$true;ui_started=$false;contract=$checked.contract;inputs=@($checked.input_paths|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}});verification_scope=$checked.verification_scope}
}catch{$result=@{ok=$false;ui_started=$false;error_code=($_.Exception.Message -split ':')[0];message=$_.Exception.Message}}
$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $OutDir 'st_module_preflight_result.json') -Encoding UTF8
if(-not $result.ok){[Console]::Error.WriteLine($result.message);exit 1}
exit 0
