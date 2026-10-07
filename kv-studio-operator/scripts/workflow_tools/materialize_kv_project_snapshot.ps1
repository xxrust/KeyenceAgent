<#
  Materialize the semantic, human-readable project tree for a completed
  read-only snapshot. The text/raw trees remain immutable evidence; this step
  creates the canonical project model from the same-run atomic outputs.
#>
param(
  [Parameter(Mandatory=$true)][string]$SnapshotRoot,
  [Parameter(Mandatory=$true)][string]$InventoryPath,
  [Parameter(Mandatory=$true)][string]$MnmRoot,
  [Parameter(Mandatory=$true)][string]$VariablesRoot,
  [Parameter(Mandatory=$true)][string]$FbArgumentsRoot,
  [Parameter(Mandatory=$true)][string]$StructureDefinitionsPath,
  [string]$RawRoot = ''
)

$ErrorActionPreference = 'Stop'

function Full([string]$Path) { [IO.Path]::GetFullPath($Path) }
function Write-Json([string]$Path,[object]$Value,[int]$Depth=24) {
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Path) | Out-Null
  $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}
function Safe([string]$Name) {
  if ($null -eq $Name -or -not $Name) { return '_unnamed' }
  $invalid = [IO.Path]::GetInvalidFileNameChars() -join ''
  $escaped = [regex]::Escape($invalid)
  $value = [regex]::Replace([string]$Name, "[$escaped]", '_').Trim().TrimEnd('.')
  if (-not $value) { $value = '_unnamed' }
  return $value
}
function Copy-Artifact([string]$Source,[string]$Destination) {
  if (-not $Source -or -not (Test-Path -LiteralPath $Source -PathType Leaf)) { return $false }
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $Destination) | Out-Null
  Copy-Item -LiteralPath $Source -Destination $Destination -Force
  return $true
}
function Hash([string]$Path) {
  if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Leaf)) { return '' }
  return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}
function Rel([string]$Base,[string]$Path) {
  $b=(Full $Base).TrimEnd('\')+'\'; $p=Full $Path
  [Uri]::UnescapeDataString(([Uri]$b).MakeRelativeUri([Uri]$p).ToString()).Replace('/','\')
}
function Read-Json([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }
  try { return Get-Content -Raw -LiteralPath $Path -Encoding UTF8 | ConvertFrom-Json } catch { return $null }
}
function Find-First([object[]]$Items,[scriptblock]$Predicate) {
  foreach ($item in @($Items)) { if (& $Predicate $item) { return $item } }
  return $null
}
function Add-Entity([object]$Entity,[string]$EntityPath,[System.Collections.Generic.List[string]]$Lines,[System.Collections.Generic.List[object]]$RestorePlan) {
  Write-Json $EntityPath $Entity 20
  $Lines.Add(($Entity | ConvertTo-Json -Depth 20 -Compress))
  $RestorePlan.Add([ordered]@{
    entity_id = $Entity.id
    kind = $Entity.kind
    path = $Entity.path
    status = $Entity.status
    restore = $Entity.restore
  })
}

$SnapshotRoot=Full $SnapshotRoot
$InventoryPath=Full $InventoryPath
$MnmRoot=Full $MnmRoot
$VariablesRoot=Full $VariablesRoot
$FbArgumentsRoot=Full $FbArgumentsRoot
$StructureDefinitionsPath=Full $StructureDefinitionsPath
$projectRoot=Join-Path $SnapshotRoot 'project'
$indexRoot=Join-Path $projectRoot '_index'
New-Item -ItemType Directory -Force -Path $projectRoot,$indexRoot | Out-Null
# Converge snapshots produced by older versions which treated display labels
# and execution suffixes as semantic directories.
foreach ($legacyProgramRoot in @(Get-ChildItem -LiteralPath $projectRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
  $_.Name -match '^程序' -and $_.Name -ne '程序'
})) {
  Remove-Item -LiteralPath $legacyProgramRoot.FullName -Recurse -Force
}
$programSemanticRoot=Join-Path $projectRoot '程序'
foreach ($legacyProgramFolder in @(Get-ChildItem -LiteralPath $programSemanticRoot -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object {
  $_.Name -match '^.+\s+\[\d+\]$'
})) {
  Remove-Item -LiteralPath $legacyProgramFolder.FullName -Recurse -Force
}

$inventory=Read-Json $InventoryPath
if (-not $inventory -or -not $inventory.tree) { throw "KV_SNAPSHOT_INVENTORY_MISSING: $InventoryPath" }
$nodes=@($inventory.tree.nodes)
$mnmInventory=@($inventory.mnm_inventory)
# Remove legacy FB directories even when this inventory has no MNM export. The
# source tree still carries the authoritative `module:display label` mapping.
$fbRootPath=Join-Path $projectRoot '功能块'
foreach ($fbNode in @($nodes | Where-Object {
  $_.path.Count -gt 1 -and [string]$_.path[0] -eq '功能块' -and
  [string]$_.text -match '^([A-Za-z_][A-Za-z0-9_\[\]]+):(.+)$'
})) {
  $fbMatch=[regex]::Match([string]$fbNode.text,'^([A-Za-z_][A-Za-z0-9_\[\]]+):(.+)$')
  $legacyName=Safe ($fbMatch.Groups[1].Value + '_' + $fbMatch.Groups[2].Value.Trim())
  foreach ($stale in @(Get-ChildItem -LiteralPath $fbRootPath -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object {$_.Name -eq $legacyName})) {
    Remove-Item -LiteralPath $stale.FullName -Recurse -Force
  }
}
$variableResult=Read-Json (Join-Path $VariablesRoot 'variable_snapshot_result.json')
$variableSnapshots=@()
if ($variableResult) { $variableSnapshots=@($variableResult.snapshots) }
$entityLines=[System.Collections.Generic.List[string]]::new()
$restorePlan=[System.Collections.Generic.List[object]]::new()
$warnings=[System.Collections.Generic.List[string]]::new()
$allEntities=[System.Collections.Generic.List[object]]::new()

function Get-TreeModuleNode([string]$Name,[string]$RootName) {
  return Find-First @($nodes) { param($n)
    [string]$n.text -eq $Name -or [string]$n.text -like "${Name}:*"
  }
}
function Get-LocalSnapshot([string]$Owner) {
  return Find-First @($variableSnapshots) { param($s) [string]$s.scope -eq 'local' -and [string]$s.owner_program -eq $Owner }
}
function Get-LocalFile([string]$Owner,[object]$Snapshot) {
  $candidate=Join-Path $VariablesRoot ("local_{0}_raw.tsv" -f (Safe $Owner))
  if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  if ($Snapshot -and $Snapshot.raw_path) {
    $name=[IO.Path]::GetFileName([string]$Snapshot.raw_path)
    $candidate=Join-Path $VariablesRoot $name
    if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  }
  return $null
}
function Get-MnmFile([string]$Name) {
  $candidate=Join-Path $MnmRoot ((Safe $Name)+'.mnm')
  if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
  $file=Get-ChildItem -LiteralPath $MnmRoot -Filter '*.mnm' -File -ErrorAction SilentlyContinue | Where-Object { $_.BaseName -eq $Name } | Select-Object -First 1
  if ($file) { return $file.FullName }
  return $null
}
function New-TreeFolder([string[]]$Parts) {
  $path=$projectRoot
  foreach ($part in @($Parts)) { $path=Join-Path $path (Safe $part) }
  New-Item -ItemType Directory -Force -Path $path | Out-Null
  return $path
}
function Normalize-PathParts([object[]]$Path,[string]$RootName,[string]$LeafName) {
  $parts=@($Path | ForEach-Object {[string]$_})
  $rootMatches = if ($RootName -eq '程序') {
    ($parts.Count -gt 0 -and $parts[0] -match '^程序')
  } else {
    ($parts.Count -gt 0 -and $parts[0] -eq $RootName)
  }
  if ($rootMatches) {
    $parts = if ($parts.Count -gt 1) { @($parts[1..($parts.Count-1)]) } else { @() }
  }
  if ($parts.Count -gt 0) {
    $leafPattern = '^' + [regex]::Escape($LeafName) + '(?::.*|\s+\[\d+\])?$'
    if ([string]$parts[-1] -match $leafPattern) {
      $parts = if ($parts.Count -gt 1) { @($parts[0..($parts.Count-2)]) } else { @() }
    }
  }
  return @($parts | Where-Object { $_ })
}
function Same-TreePath([object[]]$Left,[object[]]$Right) {
  $a=@($Left | ForEach-Object {[string]$_}); $b=@($Right | ForEach-Object {[string]$_})
  if ($a.Count -ne $b.Count) { return $false }
  for ($i=0; $i -lt $a.Count; $i++) { if ($a[$i] -cne $b[$i]) { return $false } }
  return $true
}

# Project configuration and global data are first because they are restore prerequisites.
$configRoot=New-TreeFolder @('配置')
$unitRoot=New-TreeFolder @('配置','单元')
$unitPayload=Join-Path $unitRoot 'configuration.json'
Write-Json $unitPayload ([ordered]@{
  kind='unit_configuration'
  asset_status=$inventory.asset_status
  cpu=$inventory.topology.cpu
  expansion_units=@($inventory.topology.expansion_units)
  sidecar_candidates=@($inventory.topology.expansion_unit_sidecar_candidates)
  source='project_inventory.json'
}) 20
$unitEntity=[ordered]@{id='config:单元';kind='unit_configuration';display_name='单元配置';path='配置/单元';artifacts=[ordered]@{configuration='配置/单元/configuration.json'};status=[ordered]@{configuration='complete'};restore=[ordered]@{order=10;strategy='configure_units';depends_on=@()}}
Add-Entity $unitEntity (Join-Path $unitRoot 'entity.json') $entityLines $restorePlan
$allEntities.Add($unitEntity)

$ecRoot=New-TreeFolder @('配置','EtherCAT')
$ecPayload=Join-Path $ecRoot 'topology.json'
Write-Json $ecPayload $inventory.topology.ethercat 20
$ecStatus=if ($inventory.topology.ethercat.status -eq 'tree_summary_extracted') {'complete'} else {'partial'}
$ecEntity=[ordered]@{id='config:EtherCAT';kind='ethercat_configuration';display_name='EtherCAT配置';path='配置/EtherCAT';artifacts=[ordered]@{topology='配置/EtherCAT/topology.json'};status=[ordered]@{configuration=$ecStatus};restore=[ordered]@{order=20;strategy='configure_ethercat';depends_on=@('config:单元')}}
Add-Entity $ecEntity (Join-Path $ecRoot 'entity.json') $entityLines $restorePlan
$allEntities.Add($ecEntity)

$globalRoot=New-TreeFolder @('配置','全局变量')
$globalSource=Join-Path $VariablesRoot 'global_variables_all_groups.tsv'
if (-not (Test-Path -LiteralPath $globalSource -PathType Leaf)) {
  $globalSource=Join-Path $VariablesRoot 'global_variables_raw.tsv'
}
$globalTarget=Join-Path $globalRoot 'variables.tsv'
$globalOk=Copy-Artifact $globalSource $globalTarget
$globalStatus=if ($globalOk) {'complete'} else {'missing'}
$globalEntity=[ordered]@{id='config:全局变量';kind='global_variables';display_name='全局变量';path='配置/全局变量';artifacts=[ordered]@{variables='配置/全局变量/variables.tsv'};status=[ordered]@{variables=$globalStatus};restore=[ordered]@{order=40;strategy='set_global_variables';depends_on=@('config:单元','config:EtherCAT')}}
Add-Entity $globalEntity (Join-Path $globalRoot 'entity.json') $entityLines $restorePlan
$allEntities.Add($globalEntity)

$typeRoot=New-TreeFolder @('类型')
$typeTarget=Join-Path $typeRoot 'structure_definitions.json'
$typeOk=Copy-Artifact $StructureDefinitionsPath $typeTarget
$typeStatus=if ($typeOk) {'complete'} else {'missing'}
$typeEntity=[ordered]@{id='types:structure_definitions';kind='data_types';display_name='数据类型';path='类型';artifacts=[ordered]@{definitions='类型/structure_definitions.json'};status=[ordered]@{definitions=$typeStatus};restore=[ordered]@{order=30;strategy='create_data_types';depends_on=@('config:单元')}}
Add-Entity $typeEntity (Join-Path $typeRoot 'entity.json') $entityLines $restorePlan
$allEntities.Add($typeEntity)

# Materialize every real program/FB folder reported by WsTreeEnv, including
# branches with no modules. These entities make empty workstations and
# categories explicit instead of silently disappearing from the semantic tree.
$treeFolders=@($inventory.tree.folders)
$programFolderParts=[System.Collections.Generic.List[object]]::new()
$moduleTreePaths=[System.Collections.Generic.List[object]]::new()
foreach ($module in @($inventory.program_modules)) { $moduleTreePaths.Add(@($module.tree_path)) }
foreach ($fbNode in @($nodes | Where-Object {
  $_.path.Count -gt 1 -and [string]$_.path[0] -eq '功能块' -and
  [string]$_.text -match '^[A-Za-z_][A-Za-z0-9_\[\]]+:.+$'
})) {
  $moduleTreePaths.Add(@($fbNode.path))
}
foreach ($fb in @($mnmInventory | Where-Object {[int]$_.module_type -eq 2})) {
  $fbName=[string]$fb.module_name
  $fbNode=Find-First @($nodes) { param($n) [string]$n.text -eq $fbName -or [string]$n.text -like "${fbName}:*" }
  if ($fbNode) { $moduleTreePaths.Add(@($fbNode.path)) }
}
foreach ($folderInfo in @($treeFolders)) {
  $sourceParts=@($folderInfo.path | ForEach-Object {[string]$_})
  if ($sourceParts.Count -lt 2) { continue }
  $isModuleLeaf=$false
  foreach ($modulePath in @($moduleTreePaths)) {
    if (Same-TreePath $sourceParts $modulePath) { $isModuleLeaf=$true; break }
  }
  if ($isModuleLeaf) {
    if ([string]$sourceParts[0] -eq '功能块') {
      $staleFolder=$projectRoot
      foreach ($part in $sourceParts) { $staleFolder=Join-Path $staleFolder (Safe $part) }
      if (Test-Path -LiteralPath $staleFolder -PathType Container) {
        Remove-Item -LiteralPath $staleFolder -Recurse -Force
      }
    }
    continue
  }
  $rootName=[string]$sourceParts[0]
  if ($rootName -eq '功能块') {
    $folderParts=@($sourceParts)
  } elseif ($rootName -match '^程序') {
    $folderParts=@('程序') + @($sourceParts | Select-Object -Skip 1)
    $programFolderParts.Add($folderParts)
  } else { continue }
  $folder=New-TreeFolder $folderParts
  $relative=(Rel $projectRoot $folder).Replace('\','/')
  $sourcePartsRaw=@($folderInfo.source_tree_path | ForEach-Object {[string]$_})
  $folderPayload=[ordered]@{
    kind='project_folder'
    tree_path=$sourceParts
    source_tree_path=$sourcePartsRaw
    source_tree_path_text=if($folderInfo.source_path_text){[string]$folderInfo.source_path_text}else{[string]$folderInfo.path_text}
    has_children=[bool]$folderInfo.has_children
    contents='empty_or_structural'
  }
  Write-Json (Join-Path $folder 'folder.json') $folderPayload 12
  $folderEntity=[ordered]@{
    id=('folder:'+($relative -replace '/','|'))
    kind='project_folder'
    display_name=[string]$sourceParts[-1]
    tree_path=$sourceParts
    path=$relative
    artifacts=[ordered]@{metadata=($relative+'/folder.json')}
    status=[ordered]@{structure='complete';contents='empty_or_structural'}
    restore=[ordered]@{order=5;strategy='create_folder';depends_on=@()}
  }
  Add-Entity $folderEntity (Join-Path $folder 'entity.json') $entityLines $restorePlan
  $allEntities.Add($folderEntity)
}

# Some snapshots already contain a directory produced by the old root-node
# normalization, but no longer contain its old entity record. Remove the stale
# path only after rebuilding the authoritative program folder list.
$validProgramFolders=@{}
foreach ($parts in @($programFolderParts)) {
  $validProgramFolders[(@($parts) -join '\')]=$true
}
$staleRoot=Join-Path $projectRoot '程序'
foreach ($candidate in @(Get-ChildItem -LiteralPath $staleRoot -Directory -ErrorAction SilentlyContinue | Where-Object {$_.Name -match '^程序'})) {
  if (-not $validProgramFolders.ContainsKey(('程序\'+$candidate.Name))) {
    Remove-Item -LiteralPath $candidate.FullName -Recurse -Force
  }
}

# User and library FBs are placed from the actual project tree when possible.
$fbInventory=@($mnmInventory | Where-Object {[int]$_.module_type -eq 2})
foreach ($fb in @($fbInventory | Sort-Object module_name)) {
  $name=[string]$fb.module_name
  $node=Get-TreeModuleNode $name '功能块'
  # Older materializers combined the FB entity name and display label into
  # one directory (for example `FB_Cylinder_气缸控制`). Remove those derived
  # names wherever they occur before creating the canonical module directory.
  foreach ($stale in @(Get-ChildItem -LiteralPath (Join-Path $projectRoot '功能块') -Directory -Recurse -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -like ((Safe $name) + '_*')
  })) {
    Remove-Item -LiteralPath $stale.FullName -Recurse -Force
  }
  $isOfficial=([string]$fb.classification -eq 'official_or_library_fb')
  if ($isOfficial) {
    # Library paths can be very deep and exceed Windows MAX_PATH when nested
    # under a long regression run directory. Preserve the full source tree in
    # entity.json, but keep the canonical payload location shallow.
    $folderParts=@('功能块','库',$name)
  } elseif ($node) {
    $groups=Normalize-PathParts @($node.path) '功能块' $name
    $folderParts=@('功能块') + @($groups) + @($name)
  } else {
    $folderParts=@('功能块','未解析',$name)
    $warnings.Add("FB placement unresolved: $name")
  }
  $folder=New-TreeFolder $folderParts
  $body=Get-MnmFile $name
  $bodyTarget=Join-Path $folder 'body.mnm'
  $bodyOk=Copy-Artifact $body $bodyTarget
  $argFolder=Join-Path (Join-Path $FbArgumentsRoot (Safe $name)) ''
  $argSource=Join-Path $argFolder 'fb_arguments_raw.tsv'
  $argResult=Read-Json (Join-Path $argFolder 'fb_snapshot_result.json')
  $argTarget=Join-Path $folder 'arguments.tsv'
  $argOk=Copy-Artifact $argSource $argTarget
  $argStatus=if ($argOk -and $argResult -and $argResult.ok -eq $true) {'complete'} elseif ($argResult -and $argResult.ok -eq $false) {'failed'} elseif ($isOfficial) {'not_applicable'} else {'missing'}
  $localSnapshot=Get-LocalSnapshot $name
  $localSource=Get-LocalFile $name $localSnapshot
  $localTarget=Join-Path $folder 'locals.tsv'
  $localOk=Copy-Artifact $localSource $localTarget
  $localStatus=if ($localOk -and $localSnapshot -and $localSnapshot.row_count -ge 0) {'complete'} elseif ($isOfficial) {'not_applicable'} else {'missing'}
  $status=[ordered]@{placement=if($node){'complete'}else{'unresolved'};body=if($bodyOk){'complete'}else{'missing'};arguments=$argStatus;locals=$localStatus}
  $artifacts=[ordered]@{body=if($bodyOk){(Rel $projectRoot $bodyTarget).Replace('\','/')}else{$null};arguments=if($argOk){(Rel $projectRoot $argTarget).Replace('\','/')}else{$null};locals=if($localOk){(Rel $projectRoot $localTarget).Replace('\','/')}else{$null}}
  $entity=[ordered]@{id=('fb:'+($folderParts -join '/'));kind='function_block';source_name=$name;display_name=if($node -and [string]$node.text -match ':'){([string]$node.text -split ':',2)[1]}else{$name};tree_path=if($node){@($node.path)}else{@()};path=(Rel $projectRoot $folder).Replace('\','/');artifacts=$artifacts;status=$status;restore=[ordered]@{order=50;strategy='import_body_then_set_arguments_then_set_locals';depends_on=@('types:structure_definitions','config:全局变量');source_sha256=[ordered]@{body=Hash $body;arguments=Hash $argSource;locals=Hash $localSource}}}
  Add-Entity $entity (Join-Path $folder 'entity.json') $entityLines $restorePlan
  $allEntities.Add($entity)
}

# Program modules use the category and tree path emitted by the inventory atom.
foreach ($module in @($inventory.program_modules | Sort-Object category,execution_order,module_name)) {
  $name=[string]$module.module_name
  $category=[string]$module.category
  if (-not $category -and @($module.tree_path).Count -ge 2) { $category=[string]$module.tree_path[1] }
  if (-not $category) { $category='未分类' }
  $moduleParts=Normalize-PathParts @($module.tree_path) '程序' $name
  if ($moduleParts.Count -eq 0) { $moduleParts=@($category) }
  $folder=New-TreeFolder (@('程序') + @($moduleParts) + @($name))
  $body=Get-MnmFile $name
  $bodyTarget=Join-Path $folder 'body.mnm'
  $bodyOk=Copy-Artifact $body $bodyTarget
  $localSnapshot=Get-LocalSnapshot $name
  $localSource=Get-LocalFile $name $localSnapshot
  $localTarget=Join-Path $folder 'locals.tsv'
  $localOk=Copy-Artifact $localSource $localTarget
  $status=[ordered]@{placement='complete';body=if($bodyOk){'complete'}else{'missing'};locals=if($localOk){'complete'}else{'missing'}}
  $entity=[ordered]@{id=('program:'+((@($moduleParts) + @($name)) -join '/'));kind='program_module';source_name=$name;display_name=$name;category=$category;execution_order=[int]$module.execution_order;tree_path=@($module.tree_path);path=(Rel $projectRoot $folder).Replace('\','/');artifacts=[ordered]@{body=if($bodyOk){(Rel $projectRoot $bodyTarget).Replace('\','/')}else{$null};locals=if($localOk){(Rel $projectRoot $localTarget).Replace('\','/')}else{$null}};status=$status;restore=[ordered]@{order=60;strategy='import_body_then_set_locals';depends_on=@('types:structure_definitions','config:全局变量');source_sha256=[ordered]@{body=Hash $body;locals=Hash $localSource}}}
  Add-Entity $entity (Join-Path $folder 'entity.json') $entityLines $restorePlan
  $allEntities.Add($entity)
}

function Get-StatusEntries {
  param($Status)
  if ($null -eq $Status) { return @() }
  # Normalize dictionaries and PSCustomObjects to one property enumeration shape.
  $normalized = $Status | ConvertTo-Json -Depth 8 | ConvertFrom-Json
  @($normalized.PSObject.Properties)
}

foreach ($entity in $allEntities) {
  foreach ($property in @(Get-StatusEntries $entity.status)) {
    $value=[string]$property.Value
    if ($value -in @('failed','missing','unresolved','partial')) {
      $message="{0}: {1}={2}" -f $entity.id,$property.Name,$value
      if (@($warnings) -notcontains $message) { $warnings.Add($message) }
    }
  }
}

$entityIndex=Join-Path $indexRoot 'entities.jsonl'
$entityLines | Set-Content -LiteralPath $entityIndex -Encoding UTF8
$restore=[ordered]@{schema_version=1;steps=@($restorePlan | Sort-Object {$_.restore.order},kind,entity_id);warnings=@($warnings);generated_from=(Rel $SnapshotRoot $InventoryPath).Replace('\','/')}
Write-Json (Join-Path $indexRoot 'restore_plan.json') $restore 24
$index=[ordered]@{schema_version=1;entity_count=$allEntities.Count;entities='project/_index/entities.jsonl';restore_plan='project/_index/restore_plan.json';warnings=@($warnings)}
Write-Json (Join-Path $indexRoot 'index.json') $index 12
$projectManifest=[ordered]@{schema_version=1;kind='kv_project_semantic_snapshot';source_inventory=(Rel $SnapshotRoot $InventoryPath).Replace('\','/');entity_count=$allEntities.Count;roots=@('功能块','程序','配置','类型');index='project/_index/index.json';evidence=if($RawRoot){(Rel $SnapshotRoot (Full $RawRoot)).Replace('\','/')}else{'raw'}}
Write-Json (Join-Path $projectRoot 'project.json') $projectManifest 12

$overview=[System.Collections.Generic.List[string]]::new()
$overview.Add('# KV PLC Project Snapshot')
$overview.Add('')
$overview.Add('Canonical semantic tree generated from the same-run atomic snapshots.')
$overview.Add('')
$overview.Add(('Entities: {0}' -f $allEntities.Count))
$overview.Add(('Warnings: {0}' -f $warnings.Count))
$overview.Add('')
$overview.Add('## Restore order')
$overview.Add('')
foreach($step in @($restorePlan | Sort-Object {$_.restore.order},kind,entity_id)) { $overview.Add(('- `{0}` `{1}` `{2}`' -f $step.restore.order,$step.kind,$step.entity_id)) }
$overview.Add('')
$overview.Add('## Status')
$overview.Add('')
foreach($entity in ($allEntities | Sort-Object kind,path)) {
  $state=(@(Get-StatusEntries $entity.status | ForEach-Object {[string]$_.Value} | Where-Object {$_ -in @('failed','missing','unresolved','partial')}) -join ',')
  if (-not $state) { $state='complete' }
  $overview.Add(('- `{0}` `{1}` `{2}`' -f $state,$entity.kind,$entity.path))
}
$overview | Set-Content -LiteralPath (Join-Path $projectRoot 'overview.md') -Encoding UTF8

$result=[ordered]@{ok=$true;project_root=$projectRoot;entity_count=$allEntities.Count;warning_count=$warnings.Count;warnings=@($warnings);index_path=(Join-Path $indexRoot 'index.json')}
Write-Json (Join-Path $indexRoot 'materialization_result.json') $result 12
$result | ConvertTo-Json -Depth 12
