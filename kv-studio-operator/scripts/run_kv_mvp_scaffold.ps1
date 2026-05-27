param(
  [Parameter(Mandatory=$true)]
  [string]$ScaffoldRoot,

  [string]$OutRoot = 'C:\Users\Public\KVSkillPractice\mvp_runs',
  [string]$ProjectName = '',
  [string]$CpuModel = '',
  [string]$KvsExe = '',
  [string]$ChecklistPath = '',
  [int]$TimeoutSeconds = 300
)

$ErrorActionPreference = 'Stop'
$start = Get-Date
$scriptRoot = Split-Path -Parent $PSCommandPath
$mvpScriptRoot = Join-Path $scriptRoot 'mvp'
$steps = [System.Collections.Generic.List[object]]::new()
$script:currentStep = 'init'

function New-Cn([int[]]$CodePoints) {
  -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Resolve-ScaffoldPath([string]$RelativePath) {
  if ([IO.Path]::IsPathRooted($RelativePath)) { return [IO.Path]::GetFullPath($RelativePath) }
  return [IO.Path]::GetFullPath((Join-Path $ScaffoldRoot $RelativePath))
}

function Get-ElapsedSeconds {
  [math]::Round(((Get-Date) - $start).TotalSeconds, 3)
}

function Assert-TimeBudget([string]$Stage) {
  $elapsed = ((Get-Date) - $start).TotalSeconds
  if ($elapsed -gt $TimeoutSeconds) {
    throw "MVP time budget exceeded at ${Stage}: $([math]::Round($elapsed, 3))s > ${TimeoutSeconds}s"
  }
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

$ScaffoldRoot = [IO.Path]::GetFullPath($ScaffoldRoot)
$manifestPath = Join-Path $ScaffoldRoot 'scaffold.json'
if (-not (Test-Path -LiteralPath $manifestPath)) {
  throw "scaffold.json not found: $manifestPath"
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath -Encoding UTF8 | ConvertFrom-Json
$manifestChecklist = ''
if ($manifest.checklist) { $manifestChecklist = Resolve-ScaffoldPath ([string]$manifest.checklist) }
if (-not $ChecklistPath -and $manifestChecklist) { $ChecklistPath = $manifestChecklist }
$checklistGuard = Join-Path $scriptRoot 'assert_kv_operation_checklist.ps1'
if (-not (Test-Path -LiteralPath $checklistGuard)) { throw "Checklist guard script not found: $checklistGuard" }
$global:LASTEXITCODE = 0
$checklistJson = & $checklistGuard -ChecklistPath $ChecklistPath -SearchRoots @($ScaffoldRoot, $OutRoot) -OperationName 'run KV STUDIO MVP scaffold'
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
$checklistResult = ($checklistJson | ConvertFrom-Json)
$ChecklistPath = [string]$checklistResult.checklist_path

if (-not $ProjectName) { $ProjectName = [string]$manifest.project.name }
if (-not $CpuModel) { $CpuModel = [string]$manifest.project.cpu_model }
if (-not $ProjectName) { throw 'Project name is missing from parameter and scaffold.json.' }
if (-not $CpuModel) { throw 'CPU model is missing from parameter and scaffold.json.' }

$localProgramName = [string]$manifest.variables.local_program
if (-not $localProgramName) { $localProgramName = [string]$manifest.project.local_program }
if (-not $localProgramName) { throw 'Local program name is missing from scaffold.json.' }

$runRoot = Join-Path $OutRoot $ProjectName
$artifactRoot = Join-Path $runRoot 'artifacts'
$projectRoot = Join-Path $runRoot 'Projects'
$scaffoldArtifactRoot = Join-Path $artifactRoot 'scaffold'
$reportPath = Join-Path $runRoot 'mvp_result.json'
New-Item -ItemType Directory -Force -Path $runRoot, $artifactRoot, $projectRoot, $scaffoldArtifactRoot | Out-Null

$globalTsv = Resolve-ScaffoldPath ([string]$manifest.variables.global_tsv)
$localTsv = Resolve-ScaffoldPath ([string]$manifest.variables.local_tsv)
if (-not (Test-Path -LiteralPath $globalTsv)) { throw "Global variable TSV not found: $globalTsv" }
if (-not (Test-Path -LiteralPath $localTsv)) { throw "Local variable TSV not found: $localTsv" }

$mnmEntries = @($manifest.mnm_files)
if ($mnmEntries.Count -eq 0) { throw 'scaffold.json must contain at least one mnm_files entry.' }
$resolvedMnmFiles = @()
foreach ($entry in $mnmEntries) {
  $mnmPath = Resolve-ScaffoldPath ([string]$entry.path)
  if (-not (Test-Path -LiteralPath $mnmPath)) { throw "MNM file not found: $mnmPath" }
  $moduleName = [string]$entry.module_name
  if (-not $moduleName) { $moduleName = [IO.Path]::GetFileNameWithoutExtension($mnmPath) }
  $moduleType = 0
  if ($null -ne $entry.module_type -and [string]$entry.module_type -ne '') {
    $moduleType = [int]$entry.module_type
  }
  $resolvedMnmFiles += [pscustomobject]@{
    path = $mnmPath
    module_name = $moduleName
    module_type = $moduleType
  }
}

Get-ChildItem -LiteralPath $ScaffoldRoot -Force | ForEach-Object {
  Copy-Item -LiteralPath $_.FullName -Destination $scaffoldArtifactRoot -Recurse -Force
}

$firstMnmBytes = [IO.File]::ReadAllBytes($resolvedMnmFiles[0].path)
$globalText = [IO.File]::ReadAllText($globalTsv, [Text.Encoding]::Default)
$localText = [IO.File]::ReadAllText($localTsv, [Text.Encoding]::Default)
$encodingCheck = [ordered]@{
  mnm_first_file = $resolvedMnmFiles[0].path
  mnm_utf16le_bom = ($firstMnmBytes.Length -ge 2 -and $firstMnmBytes[0] -eq 0xFF -and $firstMnmBytes[1] -eq 0xFE)
  global_tsv_has_rows = (($globalText -split "(`r`n|`n|`r)").Count -gt 1)
  local_tsv_has_rows = (($localText -split "(`r`n|`n|`r)").Count -gt 1)
  local_program_name = $localProgramName
}
$encodingCheck | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $artifactRoot 'artifact_encoding_check.json') -Encoding UTF8

function Write-MvpResult([bool]$Ok, [string]$Status, [string]$Message = '') {
  $compileResultPath = Join-Path (Join-Path $artifactRoot 'copy_result') 'compile_result_copied.txt'
  $compileText = ''
  if (Test-Path -LiteralPath $compileResultPath) {
    $compileText = [IO.File]::ReadAllText($compileResultPath, [Text.Encoding]::UTF8)
  }
  $okNeedle = (New-Cn @(0x8F6C,0x6362,0x7ED3,0x679C)) + ' OK'
  $ngNeedle = (New-Cn @(0x8F6C,0x6362,0x7ED3,0x679C)) + ' NG'
  $result = [ordered]@{
    ok = $Ok
    status = $Status
    message = $Message
    elapsed_seconds = Get-ElapsedSeconds
    timeout_seconds = $TimeoutSeconds
    checklist_path = $ChecklistPath
    current_step = $script:currentStep
    scaffold_root = $ScaffoldRoot
    scaffold_manifest = $manifestPath
    project_name = $ProjectName
    cpu_model = $CpuModel
    project_path = (Join-Path (Join-Path $projectRoot $ProjectName) ($ProjectName + '.kpr'))
    local_program_name = $localProgramName
    mnm_files = @($resolvedMnmFiles)
    global_variables_tsv = $globalTsv
    local_variables_tsv = $localTsv
    compile_result_path = $compileResultPath
    compile_result_contains_ok = ($compileText.Contains($okNeedle))
    compile_result_contains_ng = ($compileText.Contains($ngNeedle))
    compile_result_length = $compileText.Length
    steps = @($steps)
  }
  $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $reportPath -Encoding UTF8
}

function Get-ProjectTreeModuleCategory([string]$ProjectTreePath, [string]$ModuleName) {
  if (-not (Test-Path -LiteralPath $ProjectTreePath)) {
    throw "Project tree evidence file not found: $ProjectTreePath"
  }

  $functionBlockCategory = New-Cn @(0x529F,0x80FD,0x5757)
  $scanModuleCategory = New-Cn @(0x6BCF,0x6B21,0x626B,0x63CF,0x6267,0x884C,0x578B,0x6A21,0x5757)
  $knownCategories = @($functionBlockCategory, $scanModuleCategory)
  $text = [IO.File]::ReadAllText($ProjectTreePath, [Text.Encoding]::UTF8)
  $matches = [regex]::Matches($text, '<value\.first>(.*?)</value\.first>', [Text.RegularExpressions.RegexOptions]::Singleline)
  $currentCategory = ''
  for ($i = 0; $i -lt $matches.Count; $i++) {
    $value = [System.Net.WebUtility]::HtmlDecode($matches[$i].Groups[1].Value).Trim()
    if ($knownCategories -contains $value) {
      $currentCategory = $value
      continue
    }
    if ($value -eq $ModuleName -or $value -match ('^' + [regex]::Escape($ModuleName) + '\s+\[\d+\]$')) {
      return $currentCategory
    }
  }
  return ''
}

function Assert-ImportedModulePlacement([object]$Entry) {
  $script:currentStep = "verify_module_placement_$($Entry.module_name)"
  $stepStart = Get-Date
  $treePath = Join-Path (Join-Path $projectRoot $ProjectName) 'WsTreeEnv.xml'
  $actualCategory = Get-ProjectTreeModuleCategory $treePath $Entry.module_name
  $functionBlockCategory = New-Cn @(0x529F,0x80FD,0x5757)
  $scanModuleCategory = New-Cn @(0x6BCF,0x6B21,0x626B,0x63CF,0x6267,0x884C,0x578B,0x6A21,0x5757)
  $expectedCategory = if ([int]$Entry.module_type -eq 2) { $functionBlockCategory } else { $scanModuleCategory }
  $ok = ($actualCategory -eq $expectedCategory)
  $placement = [pscustomobject]@{
    module_name = $Entry.module_name
    module_type = [int]$Entry.module_type
    expected_category = $expectedCategory
    actual_category = $actualCategory
    ok = $ok
    project_tree_path = $treePath
  }
  $placementDir = Join-Path $artifactRoot 'module_placement'
  New-Item -ItemType Directory -Force -Path $placementDir | Out-Null
  $placement | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $placementDir ($Entry.module_name + '.json')) -Encoding UTF8
  $steps.Add([pscustomobject]@{
    name = "verify_module_placement_$($Entry.module_name)"
    script = 'internal'
    exit_code = if ($ok) { 0 } else { 1 }
    elapsed_seconds = [math]::Round(((Get-Date) - $stepStart).TotalSeconds, 3)
  })
  if (-not $ok) {
    throw "Imported module placement mismatch for $($Entry.module_name): expected '$expectedCategory' for MODULE_TYPE=$($Entry.module_type), actual '$actualCategory'."
  }
}

try {
  $projectPath = Join-Path (Join-Path $projectRoot $ProjectName) ($ProjectName + '.kpr')

  $createArgs = @(
    '-ProjectName', $ProjectName,
    '-ProjectRoot', $projectRoot,
    '-CpuModel', $CpuModel,
    '-OutDir', (Join-Path $artifactRoot 'create_project'),
    '-ChecklistPath', $ChecklistPath,
    '-TimeoutSeconds', '120',
    '-RestartKvs'
  )
  if ($KvsExe) { $createArgs += @('-KvsExe', $KvsExe) }
  Invoke-MvpStep 'create_project' 'create_project_local_guarded.ps1' $createArgs

  for ($i = 0; $i -lt $resolvedMnmFiles.Count; $i++) {
    $entry = $resolvedMnmFiles[$i]
    $importArgs = @(
      '-MnmPath', $entry.path,
      '-ProjectPath', $projectPath,
      '-OutDir', (Join-Path $artifactRoot ("import_mnm_$($i + 1)")),
      '-ExpectedModuleName', $entry.module_name,
      '-ProjectSearchRoot', (Join-Path $projectRoot $ProjectName),
      '-ChecklistPath', $ChecklistPath,
      '-SaveAfterImport',
      '-RestartKvs', '$true'
    )
    if ($KvsExe) { $importArgs += @('-KvsExe', $KvsExe) }
    Invoke-MvpStep "import_mnm_$($i + 1)" 'import_mnm_guarded.ps1' $importArgs
    Assert-ImportedModulePlacement $entry
  }

  Invoke-MvpStep 'set_variables' 'set_variables_guarded.ps1' @(
    '-ProjectPath', $projectPath,
    '-GlobalVariablesTsv', $globalTsv,
    '-LocalVariablesTsv', $localTsv,
    '-LocalProgramName', $localProgramName,
    '-ChecklistPath', $ChecklistPath,
    '-OutDir', (Join-Path $artifactRoot 'set_variables')
  )

  Invoke-MvpStep 'compile_convert' 'compile_and_copy_result_bounded.ps1' @(
    '-ProjectPath', $projectPath,
    '-OutDir', (Join-Path $artifactRoot 'compile_convert'),
    '-WaitSeconds', '40',
    '-ChecklistPath', $ChecklistPath,
    '-ConvertAction', 'CtrlF9'
  )

  Invoke-MvpStep 'copy_convert_result' 'copy_convert_result_from_tree_handle.ps1' @(
    '-ProjectNeedle', $ProjectName,
    '-OutDir', (Join-Path $artifactRoot 'copy_result'),
    '-ChecklistPath', $ChecklistPath,
    '-MaxLookupMs', '1000'
  )

  $compileResultPath = Join-Path (Join-Path $artifactRoot 'copy_result') 'compile_result_copied.txt'
  $copyText = [IO.File]::ReadAllText($compileResultPath, [Text.Encoding]::UTF8)
  $okNeedle = (New-Cn @(0x8F6C,0x6362,0x7ED3,0x679C)) + ' OK'
  if (-not $copyText.Contains($okNeedle)) {
    throw 'Copied compile result does not contain the OK conversion result.'
  }
  Write-MvpResult $true 'pass' ''
  exit 0
} catch {
  Write-MvpResult $false 'fail' $_.Exception.ToString()
  exit 1
}

