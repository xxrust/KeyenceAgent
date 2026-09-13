param(
  [Parameter(Mandatory=$true)][string]$ScenarioPath,
  [string]$OutRoot = '',
  [switch]$PlanOnly,
  [switch]$KeepProjectOpen
)
$ErrorActionPreference = 'Stop'
$scenarioRunnerDir = Split-Path -Parent $PSCommandPath
$testRoot = Split-Path -Parent $scenarioRunnerDir
$skillRoot = Split-Path -Parent $testRoot
$scenarioPath = [IO.Path]::GetFullPath($ScenarioPath)
$scenario = Get-Content -Raw -LiteralPath $scenarioPath -Encoding UTF8 | ConvertFrom-Json
if (-not $scenario.name -or -not $scenario.workflow) { throw 'Scenario requires name and workflow.' }
function Expand-TestValue([string]$Value, [string]$ProjectPath, [string]$ProjectDirectory, [string]$RunDirectory, [string]$FixtureDirectory) {
  $result = [string]$Value
  return $result.Replace('${skill_root}', $skillRoot).Replace('${project}', $ProjectPath).Replace('${project_dir}', $ProjectDirectory).Replace('${out}', $RunDirectory).Replace('${fixture_dir}', $FixtureDirectory)
}
function Get-ConfiguredKvsExe {
  $loader = Join-Path $skillRoot 'scripts\Import-KvStudioOperatorConfig.ps1'
  $cfg = & $loader -ScriptRoot (Join-Path $skillRoot 'scripts')
  if ($cfg -and $cfg.kvs_exe) { return [IO.Path]::GetFullPath([string]$cfg.kvs_exe) }
  throw 'KV_TEST_KVS_EXE_NOT_CONFIGURED'
}
function Wait-KvsProcess([string]$ProjectNeedle, [int]$Seconds = 20) {
  $deadline = (Get-Date).AddSeconds($Seconds)
  do {
    $found = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowTitle -like "*$ProjectNeedle*" })
    if ($found.Count -eq 1) { return $found[0] }
    if ($found.Count -gt 1) { throw "KV_TEST_PROJECT_WINDOW_AMBIGUOUS: $ProjectNeedle" }
    Start-Sleep -Milliseconds 250
  } while ((Get-Date) -lt $deadline)
  throw "KV_TEST_PROJECT_WINDOW_TIMEOUT: $ProjectNeedle"
}
function Expand-Arguments([object[]]$Values, [string]$ProjectPath, [string]$ProjectDirectory, [string]$RunDirectory, [string]$FixtureDirectory) {
  $out = [System.Collections.Generic.List[string]]::new()
  foreach ($value in @($Values)) { $out.Add((Expand-TestValue ([string]$value) $ProjectPath $ProjectDirectory $RunDirectory $FixtureDirectory)) }
  return $out.ToArray()
}
$sampleProjects = @(Get-ChildItem -LiteralPath (Join-Path $skillRoot 'references') -Recurse -Filter '*.kpr' -File | Where-Object { $_.BaseName -like '*v100*' })
if ($sampleProjects.Count -ne 1) { throw "Expected one KVX sample .kpr under references, found $($sampleProjects.Count)" }
$sourceProjectPath = $sampleProjects[0].FullName
$sourceProjectDirectory = Split-Path -Parent $sourceProjectPath
if (-not $OutRoot) { $OutRoot = Join-Path $scenarioRunnerDir 'runs' }
$runDirectory = Join-Path ([IO.Path]::GetFullPath($OutRoot)) (($scenario.name -replace '[^A-Za-z0-9_.-]','_') + '_' + (Get-Date -Format 'yyyyMMdd_HHmmss_fff'))
$projectDirectory = Join-Path $runDirectory (Join-Path 'project' (Split-Path -Leaf $sourceProjectDirectory))
$projectPath = Join-Path $projectDirectory (Split-Path -Leaf $sourceProjectPath)
$fixtureDirectory = Join-Path (Split-Path -Parent $scenarioPath) 'fixtures'
New-Item -ItemType Directory -Force -Path $runDirectory | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $projectDirectory) | Out-Null
Copy-Item -LiteralPath $sourceProjectDirectory -Destination (Split-Path -Parent $projectDirectory) -Recurse -Force
$workflowPath = Join-Path $skillRoot ([string]$scenario.workflow)
if (-not (Test-Path -LiteralPath $workflowPath -PathType Leaf)) { throw "Workflow missing: $workflowPath" }
$arguments = Expand-Arguments @($scenario.arguments) $projectPath $projectDirectory $runDirectory $fixtureDirectory
if ($PlanOnly -and $arguments -notcontains '-PlanOnly') { $arguments += '-PlanOnly' }
$invokeArguments = @('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',$workflowPath) + @($arguments)
$stdoutPath = Join-Path $runDirectory 'workflow_stdout.txt'
$stderrPath = Join-Path $runDirectory 'workflow_stderr.txt'
$startedProcess = $null; $workflowExit = 1; $workflowError = ''
try {
  if (-not $PlanOnly -and $scenario.open_project -ne $false) {
    $kvsExe = Get-ConfiguredKvsExe
    if (-not (Test-Path -LiteralPath $kvsExe -PathType Leaf)) { throw "KV_TEST_KVS_EXE_MISSING: $kvsExe" }
    $projectNeedle = [IO.Path]::GetFileNameWithoutExtension($sourceProjectPath)
    $existing = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 -and $_.MainWindowTitle -like 'KV STUDIO*' -and $_.MainWindowTitle -like "*$projectNeedle*" })
    if ($existing.Count -gt 0) { throw 'KV_TEST_PROJECT_ALREADY_OPEN' }
    $startedProcess = Start-Process -FilePath $kvsExe -WorkingDirectory (Split-Path -Parent $kvsExe) -ArgumentList ('"' + $projectPath + '"') -PassThru
    $null = Wait-KvsProcess $projectNeedle
  }
  & powershell @invokeArguments *> $stdoutPath
  $workflowExit = if ($LASTEXITCODE -is [int]) { [int]$LASTEXITCODE } else { 0 }
} catch {
  $workflowError = $_.Exception.ToString(); $workflowError | Set-Content -LiteralPath $stderrPath -Encoding UTF8; $workflowExit = 1
} finally {
  if ($startedProcess -and -not $KeepProjectOpen) { try { Stop-Process -Id $startedProcess.Id -Force -ErrorAction SilentlyContinue } catch {} }
}
$resultPath = if ($scenario.result_file) { Join-Path $runDirectory ([string]$scenario.result_file) } else { '' }
$result = $null
if ($resultPath -and (Test-Path -LiteralPath $resultPath -PathType Leaf)) { try { $result = Get-Content -Raw -LiteralPath $resultPath -Encoding UTF8 | ConvertFrom-Json } catch {} }
$ok = ($workflowExit -eq 0 -and $result -and $result.ok -eq $true)
$record = [ordered]@{ok=[bool]($PlanOnly -or $ok);status=if($PlanOnly){'planned'}elseif($ok){'pass'}else{'fail'};scenario=$scenario.name;workflow=$workflowPath;project_path=$projectPath;run_directory=$runDirectory;workflow_exit_code=$workflowExit;result_path=$resultPath;result_ok=if($result){[bool]$result.ok}else{$false};error=$workflowError;stdout_path=$stdoutPath;stderr_path=$stderrPath;generated_utc=(Get-Date).ToUniversalTime().ToString('o')}
$record | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runDirectory 'test_result.json') -Encoding UTF8
$record | ConvertTo-Json -Depth 8
if ($ok -or $PlanOnly) { exit 0 } else { exit 1 }
