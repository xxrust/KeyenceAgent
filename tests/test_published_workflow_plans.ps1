param([string]$OutDir = (Join-Path ([IO.Path]::GetTempPath()) ('kv_workflow_plans_' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference='Stop'
$root=Join-Path (Split-Path -Parent $PSScriptRoot) 'kv-studio-operator/scripts'
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
. (Join-Path $root 'workflow_tools/kv_step_evidence.ps1')
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$project=Join-Path $OutDir 'fixture.kpr'
New-Item -ItemType File -Force -Path $project | Out-Null
$inputPlan=Join-Path $OutDir 'input.json'
@{operations=@();nodes=@()} | ConvertTo-Json | Set-Content -LiteralPath $inputPlan -Encoding UTF8
$manifest=Get-KvStudioOperatorScriptManifest -ScriptRoot $root
$cases=@(
  @{script='configure_kv_expansion_units.ps1';parameters=@{Models=@('KV-B16X','KV-C32X')}},
  @{script='configure_kv_ethercat_nodes.ps1';parameters=@{NodesConfigPath=$inputPlan}},
  @{script='export_kv_structure_definitions.ps1';parameters=@{StructureName=@('strCylinderCtrl','strCylinderStatus')}},
  @{script='mutate_kv_structure_definitions.ps1';parameters=@{PlanPath=$inputPlan}},
  @{script='export_mnm_project_copy_default_folder.ps1';parameters=@{ExportDir=(Join-Path $OutDir 'exports')}}
)
foreach ($case in $cases) {
  $dest=Join-Path $OutDir ([IO.Path]::GetFileNameWithoutExtension($case.script))
  $params=$case.parameters
  # In-process calls here only prepare plans; no child or UI input is permitted.
  & (Join-Path $root ('workflows/'+$case.script)) -ProjectPath $project -OutDir $dest -PlanOnly @params
  $plan=Get-Content -Raw -Encoding UTF8 (Join-Path $dest 'execution_plan.json') | ConvertFrom-Json
  if ($plan.steps[0].script_name -ne 'gates/assert_kv_mvp_ui_guard_usage.ps1') { throw "Missing UI gate: $($case.script)" }
  foreach ($step in $plan.steps) {
    $resolved=Resolve-KvStudioOperatorScriptPath -ScriptRoot $root -Name $step.script_name -Classes $step.classes
    $null=Get-KvStepContract $manifest $step.script_name @()
    if ($step.parameters.OutDir -ne $step.out_dir) { throw "Output contract mismatch: $($step.name)" }
  }
  if ($case.script -eq 'configure_kv_expansion_units.ps1' -and $plan.steps[2].parameters.Models.Count -ne 2) { throw 'Batch models were flattened' }
  if ($case.script -eq 'export_kv_structure_definitions.ps1' -and $plan.steps[2].parameters.StructureName.Count -ne 2) { throw 'Structure names were flattened' }
  if ($case.script -eq 'export_mnm_project_copy_default_folder.ps1' -and $plan.steps.Count -ne 5) { throw 'Export does not include preparation and collection' }
}
@{ok=$true;published_plans=$cases.Count;desktop_input=$false;out_dir=$OutDir} | ConvertTo-Json
