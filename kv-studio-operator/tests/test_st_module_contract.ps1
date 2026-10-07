param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$scripts=Join-Path $root 'scripts'
. (Join-Path $scripts 'workflow_tools/kv_st_module_contract.ps1')
$fixture=Join-Path ([IO.Path]::GetFullPath($OutDir)) 'fixture'
$null=New-Item -ItemType Directory -Force -Path $fixture
Copy-Item -Path (Join-Path $PSScriptRoot 'kv-interface-regression/17_st_numeric_scan/fixtures/*') -Destination $fixture
$project=Join-Path $fixture 'Fixture.kpr';[IO.File]::WriteAllText($project,'not a real project; contract test only')
$scan=-join([char[]]@(0x6BCF,0x6B21,0x626B,0x63CF,0x6267,0x884C,0x578B,0x6A21,0x5757))
$fb=-join([char[]]@(0x529F,0x80FD,0x5757))
$tree='<Root><Child><value.first>[0] KV-X520</value.first><value.second /></Child><Child><value.first>'+$scan+'</value.first><value.second /></Child><Child><value.first>'+$fb+'</value.first><value.second><Child><value.first>ExistingFB</value.first><value.second /></Child></value.second></Child></Root>'
$treePath=Join-Path $fixture 'WsTreeEnv.xml'
$contractPath=Join-Path $fixture 'contract.json'
$original=Get-Content -LiteralPath $contractPath -Raw -Encoding UTF8
$localPath=Join-Path $fixture 'locals.tsv';$locals=Get-Content -LiteralPath $localPath -Raw -Encoding UTF8
$sourcePath=Join-Path $fixture 'QA_STNumericScan.st';$source=Get-Content -LiteralPath $sourcePath -Raw -Encoding UTF8
$results=@()
foreach($case in @('valid','wrong_cpu','unknown_field','unsupported_type','unsupported_attribute','duplicate_local','reserved_name','source_mismatch','missing_fb_type','valid_fb_type','custom_type_not_array','wrong_parent')){
  [IO.File]::WriteAllText($treePath,$tree,[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($localPath,$locals,[Text.UTF8Encoding]::new($false))
  [IO.File]::WriteAllText($sourcePath,$source,[Text.UTF8Encoding]::new($false))
  $c=$original|ConvertFrom-Json
  switch($case){
    'wrong_cpu' {[IO.File]::WriteAllText($treePath,$tree.Replace('KV-X520','KV-X310'),[Text.UTF8Encoding]::new($false))}
    'unknown_field' {$c|Add-Member NoteProperty unchecked_route 'yes'}
    'unsupported_type' {[IO.File]::WriteAllText($localPath,$locals.Replace('LREAL','LINT'),[Text.UTF8Encoding]::new($false))}
    'unsupported_attribute' {$rows=@($locals|ConvertFrom-Csv -Delimiter "`t");$rows[0]|Add-Member NoteProperty retain TRUE;$rows|Export-Csv -LiteralPath $localPath -Delimiter "`t" -Encoding UTF8 -NoTypeInformation}
    'duplicate_local' {[IO.File]::WriteAllText($localPath,$locals+($locals -split '\r?\n')[1]+"`r`n",[Text.UTF8Encoding]::new($false))}
    'reserved_name' {[IO.File]::WriteAllText($localPath,$locals.Replace('sampleMean','REAL'),[Text.UTF8Encoding]::new($false))}
    'source_mismatch' {[IO.File]::WriteAllText($sourcePath,$source.Replace('4.0;','5.0;'),[Text.UTF8Encoding]::new($false))}
    'missing_fb_type' {$c|Add-Member NoteProperty allowed_custom_data_types @('MissingFB')}
    'valid_fb_type' {$c|Add-Member NoteProperty allowed_custom_data_types @('ExistingFB')}
    'custom_type_not_array' {$c|Add-Member NoteProperty allowed_custom_data_types 'ExistingFB'}
    'wrong_parent' {$c.parent_path=@($scan,'MissingGroup')}
  }
  $c|ConvertTo-Json -Depth 8|Set-Content -LiteralPath $contractPath -Encoding UTF8
  $errorText='';try{$checked=Read-KvStModuleContract $contractPath $project}catch{$errorText=$_.Exception.Message}
  if(([string]::IsNullOrEmpty($errorText)) -ne ($case -in @('valid','valid_fb_type'))){throw "Unexpected contract case: $case error=$errorText"}
  $results+=@{case=$case;ok=$true;observed_error=$errorText}
}
@{ok=$true;ui_started=$false;tests=$results}|ConvertTo-Json -Depth 6|Set-Content -LiteralPath (Join-Path $OutDir 'test_result.json') -Encoding UTF8
"Passed $($results.Count) complete ST contract tests"
