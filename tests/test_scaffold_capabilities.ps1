param([Parameter(Mandatory=$true)][string]$OutDir,[Parameter(Mandatory=$true)][string]$BaselineModelPath)
$ErrorActionPreference='Stop'
$scripts=Join-Path (Split-Path -Parent $PSScriptRoot) 'kv-studio-operator\scripts'
. (Join-Path $scripts 'kv_variable_definition_lib.ps1')
New-Item -ItemType Directory -Force $OutDir | Out-Null
$checks=@()
function Check([string]$Name,[bool]$Pass) {
  if (-not $Pass) { throw "FAILED: $Name" }
  $script:checks += $Name
}
foreach ($field in @('device','initial_value','retain','constant')) {
  $row=[pscustomobject]@{name='State';data_type='BOOL';device='';initial_value=''}
  $value=if($field -eq 'device'){'DM100'}else{'TRUE'}
  $row | Add-Member $field $value -Force
  $errors=@(Get-KvVariableWriteCapabilityErrors @($row))
  Check "unsupported $field rejected" ($errors.Count -eq 1 -and $errors[0].code -eq 'KV_VARIABLE_WRITE_CAPABILITY_UNSUPPORTED')
}
Check 'name/type declaration allowed' (@(Get-KvVariableWriteCapabilityErrors @([pscustomobject]@{name='State';data_type='BOOL'})).Count -eq 0)
Check 'direct explicit FALSE rejected' (@(Get-KvVariableWriteCapabilityErrors @([pscustomobject]@{name='State';data_type='BOOL';initial_value='FALSE'})).Count -eq 1)
Check 'new project default allowed' (@(Get-KvVariableWriteCapabilityErrors @([pscustomobject]@{name='State';data_type='BOOL';initial_value='FALSE'}) -AllowDefaultInitialValues).Count -eq 0)
$cases=@(
  @{name='empty_local';mutate={param($m) $m.modules[0].variables.local=@()};allowed=$true},
  @{name='null_local';mutate={param($m) $m.modules[0].variables.local=$null};allowed=$true},
  @{name='omitted_local';mutate={param($m) $m.modules[0].variables.PSObject.Properties.Remove('local')};allowed=$true},
  @{name='retain_field';mutate={param($m) $m.modules[0].variables.local[0] | Add-Member retain $true};allowed=$false},
  @{name='mixed_body';mutate={param($m) $m.modules[0].mnm | Add-Member st_lines @('Running := Start;')};allowed=$false},
  @{name='reserved_name';mutate={param($m) $m.modules[0].name='AUX'};allowed=$false},
  @{name='undeclared_type_route';mutate={param($m) $m | Add-Member data_types @(@{name='Station';members=@()})};allowed=$false}
)
foreach($case in $cases){
  $root=Join-Path $OutDir $case.name
  New-Item -ItemType Directory -Force $root | Out-Null
  $m=Get-Content $BaselineModelPath -Raw -Encoding UTF8 | ConvertFrom-Json
  & $case.mutate $m
  $modelPath=Join-Path $root 'scaffold.model.json'
  $m | ConvertTo-Json -Depth 20 | Set-Content $modelPath -Encoding UTF8
  $ErrorActionPreference='Continue'
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'render_kv_mvp_scaffold_model.ps1') -ModelPath $modelPath -ScaffoldRoot $root 2>&1 | Out-File (Join-Path $root 'render.log')
  $renderExit=$LASTEXITCODE
  $ErrorActionPreference='Stop'
  Check $case.name (($renderExit -eq 0) -eq $case.allowed)
  if($case.allowed){
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'scaffold_tools\validate_kv_mvp_scaffold.ps1') -ScaffoldRoot $root -OutDir (Join-Path $root 'validation') | Out-Null
    Check 'empty local marker validates' ($LASTEXITCODE -eq 0)
    Check 'acceptance survives render' ([IO.File]::ReadAllText((Join-Path $root 'TASK.md')).Contains([string]$m.task.acceptance[0]))
  }
}
$result=[pscustomobject]@{ok=$true;checks=$checks;count=$checks.Count}
$result | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutDir 'result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 5
