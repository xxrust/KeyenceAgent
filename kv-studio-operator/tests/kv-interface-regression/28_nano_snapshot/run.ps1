param([string]$OutRoot='', [string]$KvsExe='H:/Keyence/KVS11/KVS/Kvs.exe', [string]$FixtureResultPath='', [switch]$PlanOnly)
$ErrorActionPreference='Stop'
if(-not $OutRoot){$OutRoot=Join-Path $env:TEMP ('nano_snap_'+(Get-Date -Format 'yyyyMMdd_HHmmss'))}
$OutRoot=[IO.Path]::GetFullPath($OutRoot)
if(Test-Path $OutRoot){throw 'KV_TEST_OUTPUT_MUST_BE_NEW'}
New-Item -ItemType Directory $OutRoot|Out-Null
$skill=[IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../../..'))
$cases=[Collections.Generic.List[object]]::new();$errorText=''
$before=@(Get-Process Kvs -ErrorAction SilentlyContinue|ForEach-Object {@{id=$_.Id;start=$_.StartTime.ToUniversalTime().ToString('o')}})
function Check([string]$Name,[bool]$Ok){$cases.Add(@{name=$Name;ok=$Ok});if(-not $Ok){throw ('KV_NANO_SNAPSHOT_TEST_FAILED:'+ $Name)}}
try{
 # Reuse the public frozen traffic-light plan to construct a genuinely empty-project fixture.
 if(-not $FixtureResultPath){
  $fixture=Join-Path $OutRoot 'fixture'
  $fixtureArgs=@('-STA','-NoProfile','-ExecutionPolicy','Bypass','-File',(Join-Path $skill 'examples/nano-traffic-labels/run.ps1'),'-OutRoot',$fixture,'-KvsExe',$KvsExe)
  if($PlanOnly){$fixtureArgs+='-PlanOnly'}
  & powershell @fixtureArgs
  Check 'blank traffic fixture workflow' ($LASTEXITCODE -eq 0)
  if($PlanOnly){return}
  $FixtureResultPath=Join-Path $fixture 'test_result.json'
 }
 $f=Get-Content $FixtureResultPath -Raw -Encoding UTF8|ConvertFrom-Json
 Check 'fixture saved and closed' ($f.ok -and $f.closed)
 $dest=Join-Path $OutRoot 'snap'
 & powershell -STA -NoProfile -ExecutionPolicy Bypass -File (Join-Path $skill 'scripts/workflows/export_kv_nano_snapshot.ps1') -ProjectPath $f.project_path -OutDir $dest -KvsExe $KvsExe
 Check 'snapshot command succeeds' ($LASTEXITCODE -eq 0)
 $m=Get-Content (Join-Path $dest 'snapshot/source_snapshot_manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Check 'ready has all required stages' ($m.ok -and $m.status -eq 'ready' -and @($m.stages).Count -eq 3 -and -not @($m.stages|Where-Object {$_.status -ne 'complete'}).Count)
 Check 'source hashes unchanged and owned process closed' ($m.source_unchanged -and $m.owned_process_closed)
 Check 'live Main inventory is exact' (@($m.modules).Count -eq 1 -and $m.modules[0].name -ceq 'Main' -and $m.modules[0].order -eq 1)
 $project=Join-Path $dest 'snapshot/project'
 $body=[IO.File]::ReadAllText((Join-Path $project 'program_1/program.mnm.txt'))
 $blocks=Get-Content (Join-Path $project 'program_1/mnm_comment_blocks.json') -Raw -Encoding UTF8|ConvertFrom-Json
 foreach($source in @('phase.txt','area.txt')){
  $expected=[IO.File]::ReadAllText((Join-Path $skill ('examples/nano-traffic-labels/'+$source))).Replace("`r`n","`n").TrimEnd("`r","`n")
  $exported=';'+$expected.Replace("`n","`n;")
  Check ($source+' full source preserved in MNM') ($body.Replace("`r`n","`n").Contains($exported))
  Check ($source+' complete readable comment block') (@($blocks|Where-Object {("`n"+$_.text+"`n").Contains("`n"+$expected+"`n")}).Count -gt 0)
 }
 foreach($line in @(Get-Content (Join-Path $skill 'examples/nano-traffic-labels/ladder.txt') -Encoding UTF8|Where-Object {$_})){
  Check ('ladder instruction '+$line) ($body.Replace("`r`n","`n").Contains($line))
 }
 $expected=[IO.File]::ReadAllText((Join-Path $skill 'examples/nano-traffic-labels/labels.tsv')).Replace("`r`n","`n").TrimEnd("`r","`n")
 $actual=[IO.File]::ReadAllText((Join-Path $project 'global_labels.tsv')).Replace("`r`n","`n").TrimEnd("`r","`n")
 Check 'global labels match frozen plan' ($actual -ceq $expected)
 Check 'empty local labels still have an explicit artifact' ((Test-Path (Join-Path $project 'program_1/labels.tsv')) -and (Get-Item (Join-Path $project 'program_1/labels.tsv')).Length -eq 0)
 $units=Get-Content (Join-Path $project 'units.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Check 'CPU main table' (@($units).Count -eq 1 -and $units[0].model -eq 'KV-NC32' -and @($units[0].rows).Count -eq 11)
 $port=Get-Content (Join-Path $project 'serial_port0.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Check 'serial Port0 baud row' (@($port.rows|Where-Object {$_[1] -eq '波特率'}).Count -eq 1)
 $rowCounts=@(60,1,12,9,4,6)
 for($i=1;$i -le 6;$i++){
  $rows=@(Get-Content (Join-Path $project "cpu_position/$i.tsv") -Encoding UTF8|Where-Object {$_})
  Check ('position page '+$i+' full row count') ($rows.Count -eq $rowCounts[$i-1])
 }
 Check 'global comments exported' ((Get-Item (Join-Path $project 'global_comments.csv')).Length -gt 0)
 foreach($a in $m.artifacts){Check ('artifact hash '+$a.path) ((Get-FileHash -LiteralPath (Join-Path (Join-Path $dest 'snapshot') $a.path)).Hash -eq $a.sha256)}
 $owned=Get-Content (Join-Path $dest 'ownership.json') -Raw -Encoding UTF8|ConvertFrom-Json
 Check 'snapshot process no longer exists' (-not(Get-Process -Id $owned.process_id -ErrorAction SilentlyContinue))
}catch{$errorText=$_.Exception.Message;Write-Host $errorText}
finally{
 foreach($p in $before){$now=Get-Process -Id $p.id -ErrorAction SilentlyContinue;$cases.Add(@{name=('preserve user process '+$p.id);ok=($now -and $now.StartTime.ToUniversalTime().ToString('o') -eq $p.start)})}
 $after=@(Get-Process Kvs -ErrorAction SilentlyContinue)
 $leaked=@($after|Where-Object {$_.Id -notin @($before.id)})
 $cases.Add(@{name='no additional KVS processes';ok=($leaked.Count -eq 0)})
 $failed=@($cases|Where-Object {-not $_.ok}).Count
 @{ok=(-not $errorText -and $failed -eq 0);planned=[bool]$PlanOnly;passed=($cases.Count-$failed);failed=$failed;error=$errorText;cases=@($cases)}|ConvertTo-Json -Depth 8|Set-Content (Join-Path $OutRoot 'test_result.json') -Encoding UTF8
}
if($errorText -or $failed){exit 1}
