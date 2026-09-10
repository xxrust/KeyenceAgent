param([string]$Capability = '')
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSCommandPath
. (Join-Path $root 'Resolve-KvStudioOperatorScript.ps1')
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
  @{operation=[IO.Path]::GetFileNameWithoutExtension($entry.path);path=$path;class=$entry.class;status=$entry.status;capabilities=@($entry.capabilities);parameters=$parameters;verification=$entry.verification}
})
@{ok=$true;manifest_path=(Join-Path $root 'script_manifest.json');operations=$operations} | ConvertTo-Json -Depth 10
