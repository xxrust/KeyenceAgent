param(
  [string]$OutRoot = 'C:\Users\Public\KVSkillPractice\mvp_runs',
  [string]$ProjectName = ('TrafficLightMVP_' + (Get-Date -Format 'yyyyMMdd_HHmmss')),
  [string]$CpuModel = 'KV-X310',
  [string]$KvsExe = '',
  [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
$start = Get-Date
$scriptRoot = Split-Path -Parent $PSCommandPath
$mvpScriptRoot = Join-Path $scriptRoot 'mvp'
$runRoot = Join-Path $OutRoot $ProjectName
$artifactRoot = Join-Path $runRoot 'artifacts'
$projectRoot = Join-Path $runRoot 'Projects'
$mnmDir = Join-Path $artifactRoot 'mnm'
$variableDir = Join-Path $artifactRoot 'variables'
$reportPath = Join-Path $runRoot 'mvp_result.json'
$steps = [System.Collections.Generic.List[object]]::new()
$script:currentStep = 'init'

New-Item -ItemType Directory -Force -Path $runRoot, $artifactRoot, $projectRoot, $mnmDir, $variableDir | Out-Null

function Get-ElapsedSeconds {
  [math]::Round(((Get-Date) - $start).TotalSeconds, 3)
}

function Assert-TimeBudget([string]$Stage) {
  $elapsed = ((Get-Date) - $start).TotalSeconds
  if ($elapsed -gt $TimeoutSeconds) {
    throw "MVP time budget exceeded at ${Stage}: $([math]::Round($elapsed, 3))s > ${TimeoutSeconds}s"
  }
}

function Write-MvpResult([bool]$Ok, [string]$Status, [string]$Message = '') {
  $compileResultPath = Join-Path (Join-Path $artifactRoot 'copy_result') 'compile_result_copied.txt'
  $compileText = ''
  if (Test-Path -LiteralPath $compileResultPath) {
    $compileText = [IO.File]::ReadAllText($compileResultPath, [Text.Encoding]::UTF8)
  }
  $result = [ordered]@{
    ok = $Ok
    status = $Status
    message = $Message
    elapsed_seconds = Get-ElapsedSeconds
    timeout_seconds = $TimeoutSeconds
    current_step = $script:currentStep
    project_name = $ProjectName
    cpu_model = $CpuModel
    project_path = (Join-Path (Join-Path $projectRoot $ProjectName) ($ProjectName + '.kpr'))
    mnm_path = (Join-Path $mnmDir 'TrafficLight_MVP.mnm')
    global_variables_tsv = (Join-Path $variableDir 'global_variables.tsv')
    local_variables_tsv = (Join-Path $variableDir 'local_variables.tsv')
    compile_result_path = $compileResultPath
    compile_result_contains_ok = ($compileText -like '*转换结果 OK*')
    compile_result_contains_ng = ($compileText -like '*转换结果 NG*')
    compile_result_length = $compileText.Length
    steps = @($steps)
  }
  $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

function Invoke-MvpStep([string]$Name, [string]$ScriptName, [string[]]$Arguments) {
  Assert-TimeBudget "before $Name"
  $script:currentStep = $Name
  $scriptPath = Join-Path $mvpScriptRoot $ScriptName
  if (-not (Test-Path -LiteralPath $scriptPath)) {
    throw "Required MVP script is missing: $scriptPath"
  }
  $stepStart = Get-Date
  $command = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $scriptPath) + $Arguments
  & powershell @command
  $exit = $LASTEXITCODE
  $elapsed = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 3)
  $steps.Add([pscustomobject]@{
    name = $Name
    script = $scriptPath
    exit_code = $exit
    elapsed_seconds = $elapsed
  })
  if ($exit -ne 0) {
    throw "MVP step failed: $Name exit_code=$exit"
  }
  Assert-TimeBudget "after $Name"
}

function New-MvpArtifacts {
  $script:currentStep = 'generate_artifacts'
  $programName = 'TrafficLight_MVP'
  $mnmPath = Join-Path $mnmDir ($programName + '.mnm')
  $mnmText = @"
DEVICE:63
;MODULE:TrafficLight_MVP
;MODULE_TYPE:2
; MVP traffic light program. Chinese IO display names required by user:
; 输入IO：启动
; 输出IO：红LED灯、黄LED灯、绿LED灯
; 局部变量显示名：状态、计数
LD R000
OUT R500
END
ENDH
"@.TrimStart()
  [IO.File]::WriteAllText($mnmPath, $mnmText, [Text.Encoding]::Unicode)

  $globalTsv = Join-Path $variableDir 'global_variables.tsv'
  $localTsv = Join-Path $variableDir 'local_variables.tsv'
  $global = @"
scope	owner_program	name	data_type	device	initial_value	comment	evidence	status
global		启动	BOOL		FALSE	用户要求的输入IO中文名称；ST程序体不直接引用。	mvp_skill_entrypoint	display_name
global		红LED灯	BOOL		FALSE	用户要求的输出IO中文名称；实际执行输出由 RedLed 绑定 R500。	mvp_skill_entrypoint	display_name
global		黄LED灯	BOOL		FALSE	用户要求的输出IO中文名称；实际执行输出由 YellowLed 绑定 R501。	mvp_skill_entrypoint	display_name
global		绿LED灯	BOOL		FALSE	用户要求的输出IO中文名称；实际执行输出由 GreenLed 绑定 R502。	mvp_skill_entrypoint	display_name
global		G_StartIn	INT		0	Global MVP input placeholder for 启动.	mvp_skill_entrypoint	defined
global		G_RedLed	INT		0	Global MVP output placeholder for 红LED灯.	mvp_skill_entrypoint	defined
global		G_YellowLed	INT		0	Global MVP output placeholder for 黄LED灯.	mvp_skill_entrypoint	defined
global		G_GreenLed	INT		0	Global MVP output placeholder for 绿LED灯.	mvp_skill_entrypoint	defined
"@
  $local = @"
scope	owner_program	name	data_type	device	initial_value	comment	evidence	status
local	TrafficLight_MVP	State	INT		0	ASCII execution local state (状态): 0=red, 1=green, 2=yellow.	mvp_skill_entrypoint	defined
local	TrafficLight_MVP	Count	INT		0	ASCII execution scan counter (计数).	mvp_skill_entrypoint	defined
local	TrafficLight_MVP	StartIn	UINT		0	ASCII execution alias for 输入IO：启动。	mvp_skill_entrypoint	defined
local	TrafficLight_MVP	RedLed	UINT		0	ASCII execution alias for 输出IO：红LED灯。	mvp_skill_entrypoint	defined
local	TrafficLight_MVP	YellowLed	UINT		0	ASCII execution alias for 输出IO：黄LED灯。	mvp_skill_entrypoint	defined
local	TrafficLight_MVP	GreenLed	UINT		0	ASCII execution alias for 输出IO：绿LED灯。	mvp_skill_entrypoint	defined
local	TrafficLight_MVP	状态	INT		0	用户要求的局部变量中文名称；ST程序体不直接引用。	mvp_skill_entrypoint	display_name
local	TrafficLight_MVP	计数	INT		0	用户要求的局部变量中文名称；ST程序体不直接引用。	mvp_skill_entrypoint	display_name
"@
  [IO.File]::WriteAllText($globalTsv, $global, [Text.Encoding]::Default)
  [IO.File]::WriteAllText($localTsv, $local, [Text.Encoding]::Default)

  $check = [ordered]@{
    mnm_utf16le_bom = $true
    mnm_uses_validated_ladder_smoke_shape = ($mnmText.Contains('LD R000') -and $mnmText.Contains('OUT R500'))
    global_tsv_contains_chinese_names = $global.Contains('启动')
    local_tsv_contains_state_count = ($local.Contains('State') -and $local.Contains('Count') -and $local.Contains('状态') -and $local.Contains('计数'))
  }
  $check | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $artifactRoot 'artifact_encoding_check.json') -Encoding UTF8
}

try {
  New-MvpArtifacts
  $projectPath = Join-Path (Join-Path $projectRoot $ProjectName) ($ProjectName + '.kpr')
  $mnmPath = Join-Path $mnmDir 'TrafficLight_MVP.mnm'
  $globalTsv = Join-Path $variableDir 'global_variables.tsv'
  $localTsv = Join-Path $variableDir 'local_variables.tsv'

  $createArgs = @(
    '-ProjectName', $ProjectName,
    '-ProjectRoot', $projectRoot,
    '-CpuModel', $CpuModel,
    '-OutDir', (Join-Path $artifactRoot 'create_project'),
    '-TimeoutSeconds', '120',
    '-RestartKvs'
  )
  if ($KvsExe) { $createArgs += @('-KvsExe', $KvsExe) }
  Invoke-MvpStep 'create_project' 'create_project_local_guarded.ps1' $createArgs

  Invoke-MvpStep 'import_mnm' 'import_mnm_guarded.ps1' @(
    '-MnmPath', $mnmPath,
    '-ProjectPath', $projectPath,
    '-OutDir', (Join-Path $artifactRoot 'import_mnm'),
    '-ExpectedModuleName', 'TrafficLight_MVP',
    '-ProjectSearchRoot', (Join-Path $projectRoot $ProjectName),
    '-SaveAfterImport',
    '-RestartKvs', '$true'
  )

  Invoke-MvpStep 'set_variables' 'set_variables_guarded.ps1' @(
    '-ProjectPath', $projectPath,
    '-GlobalVariablesTsv', $globalTsv,
    '-LocalVariablesTsv', $localTsv,
    '-OutDir', (Join-Path $artifactRoot 'set_variables')
  )

  Invoke-MvpStep 'compile_convert' 'compile_and_copy_result_bounded.ps1' @(
    '-ProjectPath', $projectPath,
    '-OutDir', (Join-Path $artifactRoot 'compile_convert'),
    '-WaitSeconds', '40',
    '-ConvertAction', 'CtrlF9'
  )

  Invoke-MvpStep 'copy_convert_result' 'copy_convert_result_from_tree_handle.ps1' @(
    '-ProjectNeedle', $ProjectName,
    '-OutDir', (Join-Path $artifactRoot 'copy_result'),
    '-MaxLookupMs', '1000'
  )

  $copyText = [IO.File]::ReadAllText((Join-Path (Join-Path $artifactRoot 'copy_result') 'compile_result_copied.txt'), [Text.Encoding]::UTF8)
  if ($copyText -notlike '*转换结果 OK*') {
    throw 'Copied compile result does not contain 转换结果 OK.'
  }
  Write-MvpResult $true 'pass' ''
  exit 0
} catch {
  Write-MvpResult $false 'fail' $_.Exception.ToString()
  exit 1
}

