param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$OutDir,[Parameter(Mandatory=$true)][string]$ChecklistPath)
$ErrorActionPreference='Stop'
New-Item -ItemType Directory -Force $OutDir | Out-Null
$env:KV_WORKFLOW_RUN_LOG=Join-Path $OutDir 'run.log'
$scripts=Split-Path -Parent $PSScriptRoot
foreach($step in @('compile','collect')){
 $watch=[Diagnostics.Stopwatch]::StartNew()
 @{timestamp=(Get-Date).ToString('o');type='step_started';step=$step}|ConvertTo-Json -Compress|Add-Content $env:KV_WORKFLOW_RUN_LOG -Encoding UTF8
 if($step -eq 'compile'){
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'runner_children\compile_and_copy_result_bounded.ps1') -ProjectPath $ProjectPath -OutDir (Join-Path $OutDir $step) -ChecklistPath $ChecklistPath
 }else{
  & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $scripts 'runner_children\copy_convert_result_from_tree_handle.ps1') -ProjectNeedle ([IO.Path]::GetFileNameWithoutExtension($ProjectPath)) -OutDir (Join-Path $OutDir $step) -ChecklistPath $ChecklistPath
 }
 $code=$LASTEXITCODE
 @{timestamp=(Get-Date).ToString('o');type='step_finished';step=$step;exit_code=$code;elapsed_ms=$watch.ElapsedMilliseconds}|ConvertTo-Json -Compress|Add-Content $env:KV_WORKFLOW_RUN_LOG -Encoding UTF8
 if($step -eq 'compile' -and $code -ne 0){throw 'Compile trigger failed'}
}
