param([string]$OutDir = (Join-Path ([IO.Path]::GetTempPath()) ('kv_ethercat_contract_' + [guid]::NewGuid().ToString('N'))))
$ErrorActionPreference = 'Stop'
$runner = Join-Path (Split-Path -Parent $PSScriptRoot) 'kv-studio-operator\scripts\runner_children\configure_ethercat_nodes_guarded.ps1'
$tokens = $null; $errors = $null
$ast = [Management.Automation.Language.Parser]::ParseFile($runner, [ref]$tokens, [ref]$errors)
if ($errors.Count) { throw ($errors | Out-String) }
# Load pure functions only; never initialize or execute the desktop runner.
foreach ($name in @('Get-BatchNodeRequests','Get-PersistedEtherCatMappings','Resolve-BatchNodeRequests')) {
  $definition = $ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq $name }
  . ([scriptblock]::Create($definition.Extent.Text))
}
New-Item -ItemType Directory -Path $OutDir -Force | Out-Null
$ProjectPath = Join-Path $OutDir 'fixture.kpr'
[IO.File]::WriteAllText($ProjectPath, 'test fixture, not a KVS project')
$treePath = Join-Path $OutDir 'WsTreeEnv.xml'
$fixture = '<Root><Child><value.first>OtherNetwork</value.first><value.second><Child><value.first>[60] NotEtherCAT</value.first></Child></value.second></Child><Child><value.first>EtherCAT</value.first><value.second><Child><value.first>[40] Drive &amp; IO</value.first></Child><Child><value.first>[47]: KV-EC01</value.first><value.second><Child><value.first>[60] NestedModule</value.first></Child></value.second></Child></value.second></Child></Root>'
[IO.File]::WriteAllText($treePath, $fixture)
$checks = @()
function Check([string]$Name, [bool]$Condition) {
  if (-not $Condition) { throw "FAILED: $Name" }
  $script:checks += $Name
}
function Expect-Error([string]$Name, [scriptblock]$Action, [string]$Code) {
  $caught = $null
  try { & $Action | Out-Null } catch { $caught = $_.Exception.Message }
  Check $Name ($null -ne $caught -and $caught.StartsWith($Code))
}
$rows = @(Get-PersistedEtherCatMappings)
Check 'scope is direct EtherCAT children only' ($rows.Count -eq 2)
Check 'XML entities are decoded' ($rows[0].catalog_model -eq 'Drive & IO')
Check 'colon labels supported' ($rows[1].node_address -eq 47 -and $rows[1].catalog_model -eq 'KV-EC01')
$requests = @([pscustomobject]@{node_address=40;catalog_model='Drive & IO'},[pscustomobject]@{node_address=60;catalog_model='New drive'})
$plan = Resolve-BatchNodeRequests $requests
Check 'mixed plan skips only existing exact mapping' ($plan.skipped.Count -eq 1 -and $plan.pending.Count -eq 1 -and $plan.pending[0].node_address -eq 60)
$plan = Resolve-BatchNodeRequests @($requests[0])
Check 'retry is empty plan' ($plan.pending.Count -eq 0 -and $plan.skipped.Count -eq 1)
Expect-Error 'occupied address rejected' { Resolve-BatchNodeRequests @([pscustomobject]@{node_address=40;catalog_model='Wrong model'}) } 'KV_ETHERCAT_NODE_ADDRESS_CONFLICT'
$NodesConfigPath = Join-Path $OutDir 'nodes.json'
foreach ($bad in @('1.5','"40"','true','null','0','65536')) {
  [IO.File]::WriteAllText($NodesConfigPath, ('{"schema_version":1,"nodes":[{"node_address":' + $bad + ',"catalog_model":"Drive"}]}'))
  Expect-Error "invalid address $bad" { Get-BatchNodeRequests } 'KV_ETHERCAT_NODE_ADDRESS_INVALID'
}
[IO.File]::WriteAllText($NodesConfigPath, '{"schema_version":1,"nodes":[{"node_address":1,"catalog_model":"Drive"},{"node_address":1,"catalog_model":"Drive"}]}')
Expect-Error 'duplicate request rejected' { Get-BatchNodeRequests } 'KV_ETHERCAT_NODE_ADDRESS_DUPLICATE'
[IO.File]::WriteAllText($NodesConfigPath, '{"schema_version":1,"nodes":[{"node_address":1,"catalog_model":"Drive"},{"node_address":65535,"catalog_model":"IO"}]}')
$normalized = @(Get-BatchNodeRequests)
Check 'integer boundaries preserved' ($normalized.Count -eq 2 -and $normalized[1].node_address -eq 65535)
$result = [pscustomobject]@{ok=$true;checks=$checks;count=$checks.Count;desktop_input=$false}
$result | ConvertTo-Json -Depth 5 | Set-Content (Join-Path $OutDir 'result.json') -Encoding UTF8
$result | ConvertTo-Json -Depth 5
