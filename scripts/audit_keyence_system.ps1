param(
 [string]$RepoRoot='',
 [string]$SkillsRoot=(Join-Path $env:USERPROFILE '.codex\skills'),
 [Parameter(Mandatory=$true)][string]$OutDir
)
$ErrorActionPreference='Stop'
if(-not $RepoRoot){$RepoRoot=Split-Path -Parent (Split-Path -Parent $PSCommandPath)}
$RepoRoot=[IO.Path]::GetFullPath($RepoRoot)
New-Item -ItemType Directory -Force -Path $OutDir|Out-Null
$scriptRoot=Join-Path $RepoRoot 'kv-studio-operator\scripts'
$manifest=Get-Content (Join-Path $scriptRoot 'script_manifest.json') -Raw -Encoding UTF8|ConvertFrom-Json
$entries=@(foreach($class in $manifest.classes.PSObject.Properties){foreach($entry in $class.Value){
 [pscustomobject]@{path=$entry.path;class=$class.Name;customer_callable=[bool]$entry.customer_callable;status=$entry.status;exists=(Test-Path -LiteralPath (Join-Path $scriptRoot $entry.path))}
}})
$files=@(Get-ChildItem -LiteralPath $scriptRoot -Recurse -File -Filter '*.ps1')
$inventory=@(foreach($f in $files){
 $relative=$f.FullName.Substring($scriptRoot.Length+1).Replace('\','/')
 $tokens=$null;$errors=$null
 $ast=[Management.Automation.Language.Parser]::ParseFile($f.FullName,[ref]$tokens,[ref]$errors)
 $commands=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.CommandAst]},$true)|ForEach-Object {$_.GetCommandName()}|Where-Object {$_}|Sort-Object -Unique)
 $strings=@($ast.FindAll({param($n)$n -is [Management.Automation.Language.StringConstantExpressionAst]},$true)|ForEach-Object {$_.Value}|Where-Object {$_ -match '\.ps1$'}|Sort-Object -Unique)
 $text=[IO.File]::ReadAllText($f.FullName)
 [pscustomobject]@{path=$relative;hash=(Get-FileHash -LiteralPath $f.FullName -Algorithm SHA256).Hash;lines=@($text -split '\n').Count;manifest_classes=@($entries|Where-Object path -eq $relative|ForEach-Object {$_.class});wrapper=($text -match 'Invoke-KvStudioOperatorWrapper');flat_executor=($text -match 'invoke_kv_flat_execution_plan|Submit-KvWorkflowPlan');raw_input=($text -match 'SendKeys\]::|keybd_event\(|mouse_event\(');script_references=$strings;parse_errors=@($errors|ForEach-Object {$_.Message})}
})
$installation=@(foreach($skill in @('kv-studio-operator','keyence-plc-programmer','kv-studio-kb-programming')){
 $source=Join-Path $RepoRoot $skill;$installed=Join-Path $SkillsRoot $skill
 $item=Get-Item -LiteralPath $installed -Force -ErrorAction SilentlyContinue
 $diff=@();$extra=@()
 $sourceFiles=@(Get-ChildItem -LiteralPath $source -File -Recurse|Where-Object {$_.Extension -in @('.ps1','.py','.md','.json','.yaml') -and $_.Name -notlike '*.local.json'})
 foreach($f in $sourceFiles){
  $relative=$f.FullName.Substring($source.Length+1);$target=Join-Path $installed $relative
  if(-not(Test-Path -LiteralPath $target)){$diff+=@{path=$relative;kind='missing_installed'}}
  elseif((Get-FileHash -LiteralPath $f.FullName).Hash -ne (Get-FileHash -LiteralPath $target).Hash){
   $sameText=[IO.File]::ReadAllText($f.FullName).Replace("`r`n","`n") -ceq [IO.File]::ReadAllText($target).Replace("`r`n","`n")
   $diff+=@{path=$relative;kind=if($sameText){'encoding_or_newline_only'}else{'content_diff'}}
  }
 }
 if($item){$extra=@(Get-ChildItem -LiteralPath $installed -File -Recurse|Where-Object {$_.Extension -in @('.ps1','.py','.md','.json','.yaml') -and $_.Name -notlike '*.local.json'}|ForEach-Object {$relative=$_.FullName.Substring($installed.Length+1);if(-not(Test-Path -LiteralPath (Join-Path $source $relative))){$relative}})}
 [pscustomobject]@{skill=$skill;link_type=$item.LinkType;target=@($item.Target);code_files=$sourceFiles.Count;differences=$diff;installed_only=$extra}
})
$result=[ordered]@{
 schema_version=1;timestamp=(Get-Date).ToString('o');repo_root=$RepoRoot
 manifest_entries=$entries;operator_scripts=$inventory;installation=$installation
 duplicate_leaf_names=@($inventory|Group-Object {Split-Path $_.path -Leaf}|Where-Object Count -gt 1|ForEach-Object {@{name=$_.Name;paths=@($_.Group.path)}})
 unclassified=@($inventory|Where-Object {$_.manifest_classes.Count -eq 0}|ForEach-Object {$_.path})
 published_without_flat_executor=@($inventory|Where-Object {$_.manifest_classes -contains 'customer_workflow' -and -not $_.flat_executor}|ForEach-Object {$_.path})
}
$result|ConvertTo-Json -Depth 12|Set-Content -LiteralPath (Join-Path $OutDir 'system_inventory.json') -Encoding UTF8
@{operator_script_count=$inventory.Count;manifest_entry_count=$entries.Count;unclassified_count=$result.unclassified.Count;duplicate_names=$result.duplicate_leaf_names;published_without_flat_executor=$result.published_without_flat_executor;installation=@($installation|ForEach-Object {@{skill=$_.skill;link_type=$_.link_type;changed=$_.differences.Count;extra=$_.installed_only.Count}})}|ConvertTo-Json -Depth 6
