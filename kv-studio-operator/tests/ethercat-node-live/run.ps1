param(
  [string]$WorkRoot = '',
  [string]$ProjectPath = 'C:\kvrun\ec_test\KVXEcTest\KVXEcTest.kpr',
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

if (-not $WorkRoot) { $WorkRoot = Join-Path $env:TEMP ('kv-ethercat-live-' + [guid]::NewGuid().ToString('N').Substring(0, 8)) }
$WorkRoot = [IO.Path]::GetFullPath($WorkRoot)
New-Item -ItemType Directory -Force -Path $WorkRoot | Out-Null

$cases = New-Object System.Collections.Generic.List[object]
function Add-Case([string]$Name, [bool]$Ok, [string]$Detail = '') {
  $cases.Add([pscustomobject]@{ name = $Name; ok = $Ok; detail = $Detail })
}
function Save-Result([bool]$Skipped = $false) {
  $failed = @($cases | Where-Object { -not $_.ok })
  $result = [ordered]@{ test = 'ethercat-node-live'; skipped = $Skipped; passed = @($cases | Where-Object { $_.ok }).Count; failed = $failed.Count; cases = $cases.ToArray(); work_root = $WorkRoot }
  $result | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $WorkRoot 'test_result.json') -Encoding UTF8
  $result | ConvertTo-Json -Depth 3
  if ($failed.Count -gt 0) { exit 41 }
  exit 0
}

if (-not (Test-Path -LiteralPath $ProjectPath -PathType Leaf)) {
  Add-Case 'scratch project exists' $true 'skipped: project not found'
  Save-Result $true
}
$projectDir = Split-Path -Parent $ProjectPath
$wsPath = Join-Path $projectDir 'WsTreeEnv.xml'
if (-not (Test-Path -LiteralPath $wsPath)) {
  Add-Case 'WsTreeEnv.xml exists' $true 'skipped: no WsTreeEnv'
  Save-Result $true
}

$process = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
if (-not $process) {
  Start-Process -FilePath 'H:\Keyence\KVS12\KVS\Kvs.exe' -ArgumentList @(('"' + $ProjectPath + '"')) | Out-Null
  $deadline = (Get-Date).AddSeconds(60)
  do {
    Start-Sleep -Seconds 2
    $process = @(Get-Process Kvs -ErrorAction SilentlyContinue | Where-Object { $_.MainWindowHandle -ne 0 }) | Select-Object -First 1
  } while (-not $process -and (Get-Date) -lt $deadline)
}
Add-Case 'KV STUDIO is running' ($null -ne $process) 'process'
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
