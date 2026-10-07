param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$tokens=$null;$errors=$null
$ast=[Management.Automation.Language.Parser]::ParseFile((Join-Path $PSScriptRoot 'kv-interface-regression/run-workflow-test.ps1'),[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'Harness parse failed'}
$definition=$ast.Find({param($n)$n -is [Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'Get-KvsTestCleanupCandidates'},$true)
. ([scriptblock]::Create($definition.Extent.Text))
$date=[datetime]::UtcNow;$path='H:\run\workspace\sample.kpr'
$before=@([pscustomobject]@{id=10;started_utc=$date;command_line='Kvs.exe "H:\run\workspace\sample.kpr"'})
$cases=@(
  @{name='new_exact_workspace';id=20;line='Kvs.exe "H:\run\workspace\sample.kpr"';count=1},
  @{name='existing_process';id=10;line='Kvs.exe "H:\run\workspace\sample.kpr"';count=0},
  @{name='same_basename_other_directory';id=20;line='Kvs.exe "H:\other\sample.kpr"';count=0},
  @{name='path_prefix_only';id=20;line='Kvs.exe "H:\run\workspace\sample.kpr.bak"';count=0},
  @{name='substring_other_argument';id=20;line='Kvs.exe "H:\prefixH:\run\workspace\sample.kpr"';count=0},
  @{name='missing_command_line';id=20;line='';count=0},
  @{name='new_unquoted_exact_path';id=20;line='Kvs.exe H:\run\workspace\sample.kpr';count=1}
)
$results=@()
foreach($case in $cases){
  $after=@([pscustomobject]@{id=$case.id;started_utc=$date;command_line=$case.line})
  $matches=@(Get-KvsTestCleanupCandidates $before $after @($path))
  if($matches.Count -ne $case.count){throw "Candidate mismatch: $($case.name)"}
  $results+=@{name=$case.name;ok=$true}
}
New-Item -ItemType Directory -Force -Path $OutDir|Out-Null
@{ok=$true;ui_started=$false;process_operations='none';tests=$results}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($results.Count) successor ownership tests."
