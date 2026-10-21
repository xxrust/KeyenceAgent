param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'scripts/kv_tree_resolver.ps1')
$cases=@(
  @{m='HMI'; n='HMI'; e=$true},
  @{m='HMI'; n='HMI [17]'; e=$true},
  @{m='HMI'; n='HMI轴控制'; e=$false},
  @{m='HMI'; n='书签'; e=$false},
  @{m='HMI'; n='HMI_EXTRA'; e=$false},
  @{m='HMI'; n='HMI [17]x'; e=$false},
  @{m='HMI'; n='HMI:面板'; e=$true},
  @{m='FB_McMode'; n='FB_McMode'; e=$true},
  @{m='FB_McMode'; n='FB_McMode:设备模式'; e=$true},
  @{m='FB_McMode'; n='FB_McMode2:设备模式'; e=$false},
  @{m='版本管理'; n='版本管理 [24]'; e=$true},
  @{m='ModbusTCPClient_Connect'; n='ModbusTCPClient_Connect:Modbus TCP客户端 连接'; e=$true},
  @{m='A.B'; n='AXB'; e=$false},
  @{m='A.B'; n='A.B [1]'; e=$true},
  @{m='[A]'; n='[A] [3]'; e=$true},
  @{m='[A]'; n='A [3]'; e=$false}
)
$rows=@(); $failed=0
foreach($c in $cases){
  $actual=[bool](Test-KvModuleNameMatch -ModuleName $c.m -CandidateName $c.n)
  $pass=($actual -eq $c.e)
  if(-not $pass){ $failed++ }
  $rows += [pscustomobject]@{module=$c.m;candidate=$c.n;expected=$c.e;actual=$actual;pass=$pass}
}
$null=New-Item -ItemType Directory -Force -Path $OutDir
[pscustomobject]@{
  ok=($failed -eq 0); total=$rows.Count; failed=$failed; cases=$rows;
  sample_pattern=(Get-KvModuleNamePattern -ModuleName 'FB_McMode:设备模式');
  sample_pattern_bracket=(Get-KvModuleNamePattern -ModuleName '[A]')
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'tree_resolution_result.json') -Encoding UTF8
if($failed -ne 0){
  $rows | Where-Object { -not $_.pass } | ForEach-Object { Write-Host ("FAIL module={0} candidate={1} expected={2} actual={3}" -f $_.module,$_.candidate,$_.expected,$_.actual) }
  throw "Tree resolution matching failed: $failed of $($rows.Count)"
}
"Passed $($rows.Count) tree-name matching cases"