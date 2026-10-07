param([string]$Capability = '')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSCommandPath
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
$skillRoot=Split-Path -Parent $root
$regressionRoot=Join-Path $skillRoot 'tests/kv-interface-regression'
$scenarios=@(foreach($directory in @(Get-ChildItem -LiteralPath $regressionRoot -Directory)) {
  $scenarioPath=Join-Path $directory.FullName 'scenario.json'
  if(-not (Test-Path -LiteralPath $scenarioPath -PathType Leaf)){continue}
  $scenario=Get-Content -Raw -LiteralPath $scenarioPath -Encoding UTF8 | ConvertFrom-Json
  $fixtureDirectory=Join-Path $directory.FullName 'fixtures'
  $fixturePaths=@()
  if(Test-Path -LiteralPath $fixtureDirectory -PathType Container){$fixturePaths=@(Get-ChildItem -LiteralPath $fixtureDirectory -Recurse -File | ForEach-Object {$_.FullName})}
  [pscustomobject]@{name=$scenario.name;workflow=([string]$scenario.workflow).Replace('\','/');enabled=($scenario.enabled -ne $false);project_mode=$(if($scenario.project_mode){[string]$scenario.project_mode}else{'sample_copy'});expected_outcome=$(if($scenario.expected_outcome){[string]$scenario.expected_outcome}else{'success'});source_project=$scenario.source_project;expected_compile_result=$scenario.expected_compile_result;scenario_path=$scenarioPath;readme_path=(Join-Path $directory.FullName 'README.md');fixture_paths=$fixturePaths;command=('powershell -STA -NoProfile -ExecutionPolicy Bypass -File "'+(Join-Path $directory.FullName 'run.ps1')+'"');arguments=@($scenario.arguments)}
})
$entries=@(Get-KvStudioOperatorManifestEntries -ScriptRoot $root | Where-Object { $_.customer_callable -eq $true })
if ($Capability) { $entries=@($entries | Where-Object { $_.capabilities -contains $Capability -or [IO.Path]::GetFileNameWithoutExtension($_.path) -eq $Capability }) }
if (-not $entries.Count) { @{ok=$false;error_code='ROUTE_RESEARCH_REQUIRED';capability=$Capability} | ConvertTo-Json; exit 2 }
$operations=@(foreach ($entry in $entries) {
  $path=Resolve-KvStudioOperatorScriptPath -ScriptRoot $root -Name $entry.path -Classes @($entry.class)
  $tokens=$null;$errors=$null
  $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
  if ($errors.Count) { throw "KV_ENTRY_PARSE_ERROR: $path" }
  $parameters=@(foreach ($p in $ast.ParamBlock.Parameters) {
    $mandatory=$false
    foreach ($a in $p.Attributes) {
      if ($a -is [Management.Automation.Language.AttributeAst] -and $a.TypeName.FullName -eq 'Parameter') {
        foreach ($n in $a.NamedArguments) { if ($n.ArgumentName -eq 'Mandatory' -and ($n.ExpressionOmitted -or $n.Argument.SafeGetValue())) { $mandatory=$true } }
      }
    }
    @{name=$p.Name.VariablePath.UserPath;type=$p.StaticType.Name;required=$mandatory;default_expression=$(if($p.DefaultValue){$p.DefaultValue.Extent.Text}else{$null})}
  })
  $relativeWorkflow='scripts/'+([string]$entry.path).Replace('\','/')
  @{operation=[IO.Path]::GetFileNameWithoutExtension($entry.path);path=$path;class=$entry.class;status=$entry.status;capabilities=@($entry.capabilities);parameters=$parameters;verification=$entry.verification;regression_scenarios=@($scenarios|Where-Object {$_.workflow -eq $relativeWorkflow})}
})
@{ok=$true;manifest_path=(Join-Path $root 'script_manifest.json');operations=$operations} | ConvertTo-Json -Depth 10
