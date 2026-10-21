param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$OutDir,[int]$MaxAxes=0,[string]$ExpectedCpu='KV-X520')
$ErrorActionPreference='Stop'
$dir=[IO.Path]::GetFullPath($ProjectPath)
if(Test-Path -LiteralPath $dir -PathType Leaf){ $dir=Split-Path -Parent $dir }
$ws=Join-Path $dir 'WsTreeEnv.xml'
if(-not (Test-Path -LiteralPath $ws)){ throw "KV_ZERO_AXIS_FIXTURE_MISSING: $ws" }
$xml=[IO.File]::ReadAllText($ws)
$axisPairs=@([regex]::Matches($xml,'轴(\d{1,2})[:：]') | ForEach-Object { [int]$_.Groups[1].Value })
$axisCount=$axisPairs.Count
$unitNodes=@([regex]::Matches($xml,'<value\.first>(\[\d+\]\s{0,3}[^<]{1,30})</value\.first>') | ForEach-Object { ($_.Groups[1].Value -replace '\s+',' ').Trim() } | Select-Object -Unique)
$slaveNodes=@([regex]::Matches($xml,'\[\d+\]\s*(SV630|KV-EC01|SGDXS|CL3C|YAKO)') | ForEach-Object { $_.Value })
$cpu=@([regex]::Matches($xml,'KV-X\d{3}') | ForEach-Object { $_.Value } | Select-Object -Unique)
$prgx=Join-Path $dir 'All.prgx'
$prgxSize=if(Test-Path -LiteralPath $prgx){ (Get-Item $prgx).Length } else { -1 }
$checks=@(
  [pscustomobject]@{check='axis_count_le_max'; expected=("<= "+$MaxAxes); actual=$axisCount; pass=($axisCount -le $MaxAxes)},
  [pscustomobject]@{check='no_ethercat_slaves'; expected=0; actual=$slaveNodes.Count; pass=($slaveNodes.Count -eq 0)},
  [pscustomobject]@{check='cpu_matches'; expected=$ExpectedCpu; actual=($cpu -join ','); pass=($cpu -contains $ExpectedCpu)},
  [pscustomobject]@{check='unit_nodes_only_cpu'; expected=1; actual=$unitNodes.Count; pass=($unitNodes.Count -eq 1)},
  [pscustomobject]@{check='empty_program_image'; expected='<5000'; actual=$prgxSize; pass=($prgxSize -ge 0 -and $prgxSize -lt 5000)}
)
$failed=@($checks | Where-Object { -not $_.pass })
$null=New-Item -ItemType Directory -Force -Path $OutDir
[pscustomobject]@{ ok=($failed.Count -eq 0); project_path=$dir; axis_count=$axisCount; axis_numbers=($axisPairs | Sort-Object); slave_nodes=$slaveNodes; unit_nodes=$unitNodes; cpu=$cpu; all_prgx_size=$prgxSize; checks=$checks } |
  ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'zero_axis_project_result.json') -Encoding UTF8
if($failed.Count -gt 0){
  $failed | ForEach-Object { Write-Host ("FAIL {0}: expected {1} actual {2}" -f $_.check,$_.expected,$_.actual) }
  throw "Zero-axis template assertion failed: $($failed.Count) of $($checks.Count)"
}
"Passed zero-axis assertion: 0 axes, 0 EtherCAT slaves, CPU $ExpectedCpu, empty program image"