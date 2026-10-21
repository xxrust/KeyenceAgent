param([Parameter(Mandatory=$true)][string]$OutDir)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$source=Join-Path $root 'scripts/runner_children/import_mnm_guarded.ps1'
$tokens=$null;$errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($source,[ref]$tokens,[ref]$errors)
if($errors.Count){throw 'import_mnm_guarded parse failed'}
$all=[IO.File]::ReadAllText($source)

$fn=$ast.Find({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $n.Name -eq 'FindProjectModuleTreeItem'},$true)
if(-not $fn){throw 'FindProjectModuleTreeItem not found'}
$body=$fn.Extent.Text

# 1) 结构解析优先
if($body -notmatch 'Find-KvModuleNodeBounded'){throw 'structure-first lookup missing (must call Find-KvModuleNodeBounded)'}

# 2) 查找函数内禁止通配符运算符（树项名含 [ ]，-like 会抛异常或被静默吞掉）。
#    用 AST 运算符判断；注释里出现 "-like" 字样不算（注释不是 AST 节点）。
$likeKinds=@(
  [System.Management.Automation.Language.TokenKind]::Like,
  [System.Management.Automation.Language.TokenKind]::Ilike,
  [System.Management.Automation.Language.TokenKind]::NotLike,
  [System.Management.Automation.Language.TokenKind]::InotLike,
  [System.Management.Automation.Language.TokenKind]::CLike
)
$wild=@($fn.FindAll({param($n) $n -is [System.Management.Automation.Language.BinaryExpressionAst] -and $likeKinds -contains $n.Operator},$true))
if($wild.Count -gt 0){throw "wildcard operator forbidden inside tree module lookup (found $($wild.Count))"}

# 3) 禁止对整棵树做 Descendants 枚举（同名不同类：变量/HMI、书签 HMI轴控制）
if($body -match '\$tree\.FindAll\(\[System\.Windows\.Automation\.TreeScope\]::Descendants'){throw 'global descendant enumeration must not be used for module lookup'}
if($body -notmatch '\$scopeRoots'){throw 'scoped fallback missing ($scopeRoots)'}

# 4) 删除后的存在性复核必须先作废缓存的树
$cacheIdx=$all.IndexOf('ImportProjectTreeCache=$null')
$recheckIdx=$all.IndexOf('$remaining=FindProjectModuleTreeItem')
if($cacheIdx -lt 0){throw 'cache invalidation before recheck missing'}
if($recheckIdx -lt 0){throw 'post-delete recheck not found'}
if($cacheIdx -gt $recheckIdx){throw 'cache invalidation must precede the post-delete recheck'}

$null=New-Item -ItemType Directory -Force -Path $OutDir
[pscustomobject]@{
  ok=$true
  function_found=$true
  structure_first_lookup=($body -match 'Find-KvModuleNodeBounded')
  wildcard_operations_in_lookup=$wild.Count
  global_descendant_enumeration=$false
  scoped_fallback=($body -match '\$scopeRoots')
  cache_invalidated_before_recheck=($cacheIdx -lt $recheckIdx)
} | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'module_lookup_contract_result.json') -Encoding UTF8
'Passed module lookup contract checks (structure-first, no wildcard operator, scoped fallback, cache invalidated before recheck)'