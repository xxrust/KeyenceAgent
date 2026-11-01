param(
  [string]$WorkRoot = '',
  [string]$ProjectPath = '',
  [string]$CatalogModel = 'SV630_1Axis_03713'
)

$ErrorActionPreference = 'Stop'

# Live regression for configure_kv_ethercat_nodes.ps1:
# picks the next free node address in the scratch project, adds one node with
# batch axis registration, then verifies the saved WsTreeEnv contains both the
# node and its generated axis. Skips (exit 0) when KV STUDIO/project is absent.

$skillRoot = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '..\..'))
. (Join-Path $PSScriptRoot '..\_helpers\invoke_tool.ps1')
$workflow = Join-Path $skillRoot 'scripts\workflows\configure_kv_ethercat_nodes.ps1'
$kvsExe = & (Join-Path $PSScriptRoot '..\_helpers\resolve-kvs-exe.ps1') -OperatorRoot $skillRoot -AllowMissing
$fixtureProjectPath = Join-Path $PSScriptRoot 'fixtures\KVXEcTest\KVXEcTest.kpr'
if (-not $ProjectPath) { $ProjectPath = $fixtureProjectPath }
$sourceProjectPath = [IO.Path]::GetFullPath($ProjectPath)

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-ethercat-live-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$cases = New-Object System.Collections.Generic.List[object]
$script:OwnedKvsPid = 0
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}
function Save-Result([bool]$Skipped = $false) {
  if ($script:OwnedKvsPid -gt 0) {
    Stop-Process -Id $script:OwnedKvsPid -Force -ErrorAction SilentlyContinue
    $script:OwnedKvsPid = 0
  }
  $failed = @($cases | Where-Object { -not $_.ok })
  $result = [ordered]@{ test = 'ethercat-node-live'; skipped = $Skipped; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
  $result | ConvertTo-Json -Depth 3
  if ($failed.Count -gt 0) { exit 41 }
  exit 0
}
trap {
  if ($script:OwnedKvsPid -gt 0) { Stop-Process -Id $script:OwnedKvsPid -Force -ErrorAction SilentlyContinue; $script:OwnedKvsPid = 0 }
  throw
}

if (-not (Test-Path -LiteralPath $sourceProjectPath -PathType Leaf)) {
  Add-Case 'scratch project exists' $true "skipped: project not found: $sourceProjectPath"
  Save-Result $true
}
$projectCopyRoot = Join-Path $WorkRoot 'project'
if (Test-Path -LiteralPath $projectCopyRoot) { throw "KV_ETHERCAT_LIVE_COPY_EXISTS: $projectCopyRoot" }
New-Item -ItemType Directory -Force -Path $projectCopyRoot | Out-Null
$projectCopyDir = Join-Path $projectCopyRoot (Split-Path -Leaf (Split-Path -Parent $sourceProjectPath))
Copy-Item -LiteralPath (Split-Path -Parent $sourceProjectPath) -Destination $projectCopyDir -Recurse
$ProjectPath = Join-Path $projectCopyDir (Split-Path -Leaf $sourceProjectPath)
$docInfo = Join-Path $projectCopyDir 'DocumentWindowInfo.xml'
if (Test-Path -LiteralPath $docInfo) { Remove-Item -LiteralPath $docInfo -Force }
$projectDir = Split-Path -Parent $ProjectPath
$wsPath = Join-Path $projectDir 'WsTreeEnv.xml'
if (-not (Test-Path -LiteralPath $wsPath)) {
  Add-Case 'WsTreeEnv.xml exists' $true 'skipped: no WsTreeEnv'
  Save-Result $true
}

if (-not $kvsExe) {
  Add-Case 'KV STUDIO executable exists' $true 'skipped: Kvs.exe not found'
  Save-Result $true
}
$existing = @(Get-Process Kvs -ErrorAction SilentlyContinue)
if ($existing.Count -gt 0) {
  Add-Case 'no unrelated KV STUDIO session' $false 'close the other KV STUDIO project before running this live test'
  Save-Result $false
}
$started = Start-Process -FilePath $kvsExe -ArgumentList @(('"' + $ProjectPath + '"')) -PassThru
$script:OwnedKvsPid = $started.Id
$deadline = (Get-Date).AddSeconds(60)
$process = $null
do {
  Start-Sleep -Seconds 2
  $process = Get-Process -Id $script:OwnedKvsPid -ErrorAction SilentlyContinue
} while (-not $process -and (Get-Date) -lt $deadline)
Add-Case 'KV STUDIO is running' ($null -ne $process) 'process'
$titleDeadline=(Get-Date).AddSeconds(60)
while($process -and $process.MainWindowTitle -notlike '*KVXEcTest*' -and (Get-Date) -lt $titleDeadline){ Start-Sleep -Milliseconds 500; $process.Refresh() }
if (-not $process) { Save-Result $true }
Add-Case 'project window is the scratch project' ($process.MainWindowTitle -like '*KVXEcTest*') $process.MainWindowTitle
Add-Case 'project is saved (no unsaved marker)' ($process.MainWindowTitle -notmatch '\*') $process.MainWindowTitle
if ($process.MainWindowTitle -match '\*') { Save-Result $true }

$text = [IO.File]::ReadAllText($wsPath, [Text.Encoding]::UTF8)
$addresses = @([regex]::Matches($text, '<value\.first>\[(\d+)\]\s+SV630_1Axis_03713</value\.first>') | ForEach-Object { [int]$_.Groups[1].Value })
$next = if ($addresses.Count -gt 0) { ($addresses | Measure-Object -Maximum).Maximum + 1 } else { 1 }
Add-Case 'next node address resolved' ($next -ge 1) "next=$next existing=$(($addresses | Sort-Object) -join ',')"

$nodesPath = Join-Path $WorkRoot 'nodes.json'
[ordered]@{
  schema_version = 1
  batch_axis_registration = 'Yes'
  nodes = @([ordered]@{ node_address = $next; catalog_model = $CatalogModel })
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $nodesPath -Encoding UTF8

$outDir = Join-Path $WorkRoot 'workflow'
if (Test-Path -LiteralPath $outDir) { throw "KV_ETHERCAT_LIVE_OUTPUT_EXISTS: $outDir" }
$exit = Invoke-TestTool -ScriptPath $workflow -Arguments @('-ProjectPath', $ProjectPath, '-NodesConfigPath', $nodesPath, '-OutDir', $outDir, '-TimeoutSeconds', '900')
Add-Case 'workflow exits 0' ($exit -eq 0) "exit=$exit"
$resultPath = Join-Path $outDir 'workflow_result.json'
$result = if (Test-Path -LiteralPath $resultPath) { Get-Content -LiteralPath $resultPath -Raw -Encoding UTF8 | ConvertFrom-Json } else { $null }
Add-Case 'workflow result ok' ([bool]($result -and $result.ok)) "ok=$($result.ok) msg=$($result.message)"

Start-Sleep -Seconds 1
$after = [IO.File]::ReadAllText($wsPath, [Text.Encoding]::UTF8)
Add-Case 'saved tree contains the new node' ($after -match ('<value\.first>\[' + $next + '\]\s+SV630_1Axis_03713</value\.first>')) "node=$next"
Add-Case 'saved tree contains a generated axis' ($after -match '<value\.first>轴\d+:Axis_\d+</value\.first>') 'axis'
$process2 = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
Add-Case 'project saved after configuration' ($process2 -and ($process2.MainWindowTitle -notmatch '\*')) $process2.MainWindowTitle

Save-Result $false
