param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$ContractPath,[Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
. (Join-Path (Split-Path -Parent $PSScriptRoot) 'workflow_tools\kv_complete_module_contract.ps1')
New-Item -ItemType Directory -Force -Path $OutDir|Out-Null
try {
  $checked=Read-KvCompleteModuleContract $ContractPath $ProjectPath
  $result=@{ok=$true;ui_started=$false;module_name=$checked.contract.module_name;contract=$checked.contract;inputs=@($checked.input_paths|ForEach-Object{@{path=$_;sha256=(Get-FileHash -LiteralPath $_ -Algorithm SHA256).Hash}});verification_scope='BOOL ladder declarations, symbol closure, existing parent, create-only, source evidence presence'}
}catch{$result=@{ok=$false;ui_started=$false;error_code=($_.Exception.Message -split ':')[0];message=$_.Exception.Message}}
$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $OutDir 'module_preflight_result.json') -Encoding UTF8
if(-not $result.ok){[Console]::Error.WriteLine($result.message);exit 1}
exit 0
