param([Parameter(Mandatory=$true)][string]$OutDir, [switch]$Observe)
$ErrorActionPreference = 'Stop'
$scripts = Join-Path (Split-Path -Parent $PSScriptRoot) 'kv-studio-operator\scripts'
$renderer = Join-Path $scripts 'render_kv_mvp_scaffold_model.ps1'
$validator = Join-Path $scripts 'scaffold_tools\validate_kv_mvp_scaffold.ps1'
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$base = [ordered]@{
  schema_version=1; project=@{name='ScaffoldContract';cpu_model='KV-X520';local_program='Main'}
  task=@{summary='Scaffold semantic regression';acceptance=@('Preserve scan order and variable scope.')}
  modules=@(
    @{name='Main';module_type=0;mnm=@{instructions=@('LD Start','AND Ready','OUT Running','END','ENDH')};variables=@{global=@(@{name='Start';data_type='BOOL'},@{name='Ready';data_type='BOOL'},@{name='Running';data_type='BOOL'});local=@(@{name='State';data_type='BOOL';initial_value='FALSE'})}},
    @{name='Worker';module_type=0;mnm=@{instructions=@('LD Running','OUT State','END','ENDH')};variables=@{global=@(@{name='Running';data_type='BOOL'});local=@(@{name='State';data_type='BOOL';initial_value='FALSE'})}},
    @{name='Reusable';module_type=2;mnm=@{instructions=@('LD Enable','OUT Done','RET')};arguments=@(@{name='Enable';argument_type='IN';data_type='BOOL'},@{name='Done';argument_type='OUT';data_type='BOOL'});variables=@{global=@();local=@(@{name='State';data_type='BOOL';initial_value='FALSE'})}}
  )
}
function Save-Model($Model,[string]$Path) { $Model | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8 }
$cases = @(
  @{name='unchanged'; mutate={}; reject=$false},
  @{name='instruction_order'; mutate={param($root,$model) $p=Join-Path $root 'modules\Main\Main.mnm'; $t=[IO.File]::ReadAllText($p); [IO.File]::WriteAllText($p,$t.Replace("LD Start`r`nAND Ready","AND Ready`r`nLD Start"),[Text.Encoding]::Unicode)};reject=$true},
  @{name='extra_instruction';mutate={param($root,$model) $p=Join-Path $root 'modules\Main\Main.mnm'; $t=[IO.File]::ReadAllText($p); [IO.File]::WriteAllText($p,$t.Replace('OUT Running',"OUT Running`r`nRES Running"),[Text.Encoding]::Unicode)};reject=$true},
  @{name='local_type_drift';mutate={param($root,$model) $p=Join-Path $root 'modules\Main\local_variables.tsv'; $t=[IO.File]::ReadAllText($p,[Text.Encoding]::Default); [IO.File]::WriteAllText($p,$t.Replace("State`tBOOL","State`tINT"),[Text.Encoding]::Default)};reject=$true},
  @{name='model_initial_value_drift';mutate={param($root,$model) $model.modules[0].variables.local[0].initial_value='TRUE'; Save-Model $model (Join-Path $root 'scaffold.model.json')};reject=$true},
  @{name='fb_direction_drift';mutate={param($root,$model) $model.modules[2].arguments[0].argument_type='IN-OUT'; Save-Model $model (Join-Path $root 'scaffold.model.json')};reject=$true},
  @{name='module_order_drift';mutate={param($root,$model) $p=Join-Path $root 'scaffold.json'; $m=Get-Content $p -Raw -Encoding UTF8 | ConvertFrom-Json; $m.mnm_files=@($m.mnm_files[1],$m.mnm_files[0],$m.mnm_files[2]); Save-Model $m $p};reject=$true},
  @{name='module_header_drift';mutate={param($root,$model) $p=Join-Path $root 'modules\Main\Main.mnm'; $t=[IO.File]::ReadAllText($p); [IO.File]::WriteAllText($p,$t.Replace(';MODULE:Main',';MODULE:Wrong'),[Text.Encoding]::Unicode)};reject=$true}
)
$results = @()
foreach ($case in $cases) {
  $root=Join-Path $OutDir $case.name
  New-Item -ItemType Directory -Force $root | Out-Null
  $model=$base | ConvertTo-Json -Depth 20 | ConvertFrom-Json
  $modelPath=Join-Path $root 'scaffold.model.json'
  Save-Model $model $modelPath
  & powershell -NoProfile -ExecutionPolicy Bypass -File $renderer -ModelPath $modelPath -ScaffoldRoot $root 2>&1 | Out-File (Join-Path $root 'render.log')
  if ($LASTEXITCODE -ne 0) { throw "Baseline render failed: $root" }
  & $case.mutate $root $model
  $ErrorActionPreference = 'Continue'
  & powershell -NoProfile -ExecutionPolicy Bypass -File $validator -ScaffoldRoot $root -OutDir (Join-Path $root 'validation') 2>&1 | Out-File (Join-Path $root 'validate.log')
  $ErrorActionPreference = 'Stop'
  $result=Get-Content (Join-Path $root 'validation\scaffold_validation.json') -Raw -Encoding UTF8 | ConvertFrom-Json
  $results += [pscustomobject]@{case=$case.name;expected_reject=$case.reject;accepted=[bool]$result.ok;error_code=$result.error_code;pass=([bool]$result.ok -ne $case.reject)}
}
$payload=[pscustomobject]@{ok=(@($results | Where-Object {-not $_.pass}).Count -eq 0);cases=$results}
$payload | ConvertTo-Json -Depth 8 | Set-Content (Join-Path $OutDir 'result.json') -Encoding UTF8
$payload | ConvertTo-Json -Depth 8
if (-not $payload.ok -and -not $Observe) { exit 1 }
