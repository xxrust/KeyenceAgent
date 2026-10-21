param([Parameter(Mandatory=$true)][string]$ProjectPath,[Parameter(Mandatory=$true)][string]$OutDir,[int]$ExpectedAxes=2,[int]$ExpectedSlaves=2,[string]$ExpectedCpu='KV-X520')
$ErrorActionPreference='Stop'
$dir=[IO.Path]::GetFullPath($ProjectPath)
if(Test-Path -LiteralPath $dir -PathType Leaf){ $dir=Split-Path -Parent $dir }
$ws=Join-Path $dir 'WsTreeEnv.xml'
if(-not (Test-Path -LiteralPath $ws)){ throw "KV_AXIS_IMPORT_FIXTURE_MISSING: $ws" }
$xml=[IO.File]::ReadAllText($ws)
$axes=@([regex]::Matches($xml,'轴(\d{1,2})[:：]([^<\r\n]{0,30})') | ForEach-Object { [pscustomobject]@{ no=[int]$_.Groups[1].Value; name=$_.Groups[2].Value.Trim() } })
$slaves=@([regex]::Matches($xml,'\[\d+\]\s*(SV630_1Axis[^<\r\n]{0,20}|KV-EC01|SGDXS[^<\r\n]{0,40}|CL3C[^<\r\n]{0,20}|YAKO[^<\r\n]{0,20})') | ForEach-Object { ($_.Value -replace '\s+',' ').Trim() })
$cpu=@([regex]::Matches($xml,'KV-X\d{3}') | ForEach-Object { $_.Value } | Select-Object -Unique)
$checks=@(
  [pscustomobject]@{check='axis_count'; expected=$ExpectedAxes; actual=$axes.Count; pass=($axes.Count -eq $ExpectedAxes)},
  [pscustomobject]@{check='slave_count'; expected=$ExpectedSlaves; actual=$slaves.Count; pass=($slaves.Count -eq $ExpectedSlaves)},
  [pscustomobject]@{check='cpu_matches'; expected=$ExpectedCpu; actual=($cpu -join ','); pass=($cpu -contains $ExpectedCpu)},
  [pscustomobject]@{check='axis_names_present'; expected='non-empty'; actual=@($axes | Where-Object { $_.name }).Count; pass=(@($axes | Where-Object { $_.name }).Count -eq $axes.Count)}
)
$failed=@($checks | Where-Object { -not $_.pass })
$null=New-Item -ItemType Directory -Force -Path $OutDir
[pscustomobject]@{ ok=($failed.Count -eq 0); project_path=$dir; axis_count=$axes.Count; axes=$axes; slave_count=$slaves.Count; slaves=$slaves; cpu=$cpu; checks=$checks } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $OutDir 'axis_import_result.json') -Encoding UTF8
if($failed.Count -gt 0){
  $failed | ForEach-Object { Write-Host ("FAIL {0}: expected {1} actual {2}" -f $_.check,$_.expected,$_.actual) }
  throw "Axis import assertion failed: $($failed.Count) of $($checks.Count)"
}
"Passed axis import assertion: $($axes.Count) axes, $($slaves.Count) EtherCAT slaves, CPU $ExpectedCpu"