param(
  [Parameter(Mandatory=$true)][string]$SnapshotRoot,
  [Parameter(Mandatory=$true)][string]$OutPath
)
$ErrorActionPreference = 'Stop'
$snapshotRoot = [IO.Path]::GetFullPath($SnapshotRoot)
$inventoryPath = Join-Path $snapshotRoot 'text\project_inventory.json'
if (-not (Test-Path -LiteralPath $inventoryPath -PathType Leaf)) { throw "KV_SYMBOLS_INVENTORY_MISSING: $inventoryPath" }
$inventory = Get-Content -Raw -LiteralPath $inventoryPath -Encoding UTF8 | ConvertFrom-Json

# Ladder mnemonics and ST keywords are not symbols; everything else that is used with
# a member or index access is a symbol that must resolve to a declaration or to a
# system object.  Anything left over is reported as unresolved instead of dropped.
$mnemonics = @('LD','LDB','LDN','AND','ANB','ANDN','OR','ORB','ORN','OUT','SET','RES','SHOT','TMR','TMH','TMS','TMU','MOV','FMOV','DMOV','BMOV','SPRD','SPWR','FBEXEC','FBEAND','FUNAND','BOX_ST','END','ENDH','BOOKMARK','CON','IF','ELSE','THEN','ELSIF','END_IF','WHILE','TRUE','FALSE','CASE','FOR','TO','DO')

$globalsPath = Join-Path $snapshotRoot 'text\variables\global_variables_all_groups.tsv'
$variableType = [ordered]@{}
if (Test-Path -LiteralPath $globalsPath -PathType Leaf) {
  $lines = Get-Content -LiteralPath $globalsPath -Encoding UTF8
  for ($i = 1; $i -lt $lines.Count; $i++) {
    $cells = $lines[$i] -split "`t"
    if ($cells.Count -ge 3 -and $cells[1]) { $variableType[$cells[1]] = $cells[2] }
  }
}
$userTypes = @(@($inventory.data_types) | Where-Object { $_.path_text -notmatch '\(System\)' } | ForEach-Object { [string]$_.name })
$systemTypes = @(@($inventory.data_types) | Where-Object { $_.path_text -match '\(System\)' } | ForEach-Object { [string]$_.name })

$fbInstances = [ordered]@{}
$mnmPre = @(Get-ChildItem -LiteralPath (Join-Path $snapshotRoot 'text\mnm') -Filter '*.mnm' -File -Recurse -ErrorAction SilentlyContinue)
foreach ($pf in $mnmPre) {
  $pb = [IO.File]::ReadAllBytes($pf.FullName)
  $pt = if ($pb.Length -ge 2 -and $pb[0] -eq 0xFF -and $pb[1] -eq 0xFE) { [Text.Encoding]::Unicode.GetString($pb, 2, $pb.Length - 2) } else { [Text.Encoding]::GetEncoding(936).GetString($pb) }
  foreach ($pm in [regex]::Matches($pt, '(?m)^(FBEXEC|FBEAND|FUNAND)\s+(\S+)\s+(\S+)')) { $fbInstances[$pm.Groups[3].Value] = $pm.Groups[2].Value }
}
$symbols = [ordered]@{}
$memberPaths = New-Object System.Collections.Generic.List[object]
$mnmDir = Join-Path $snapshotRoot 'text\mnm'
foreach ($file in @(Get-ChildItem -LiteralPath $mnmDir -Filter '*.mnm' -File -Recurse -ErrorAction SilentlyContinue)) {
  $bytes = [IO.File]::ReadAllBytes($file.FullName)
  $text = if ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) { [Text.Encoding]::Unicode.GetString($bytes, 2, $bytes.Length - 2) } else { [Text.Encoding]::GetEncoding(936).GetString($bytes) }
  $lines = @($text -split "`r?`n")
  for ($n = 0; $n -lt $lines.Count; $n++) {
    $line = $lines[$n]
    foreach ($m in [regex]::Matches($line, '(?m)^(FBEXEC|FBEAND|FUNAND)\s+(\S+)\s+(\S+)')) { $fbInstances[$m.Groups[3].Value] = $m.Groups[2].Value }
    foreach ($m in [regex]::Matches($line, '([A-Za-z_][A-Za-z0-9_]*)((?:\s*(?:\[[^\]]*\]|\.[A-Za-z_][A-Za-z0-9_]*))+)')) {
      $root = $m.Groups[1].Value
      if ($mnemonics -contains $root) { continue }
      $path = ($m.Groups[1].Value + $m.Groups[2].Value) -replace '\s+', ''
      $class = 'unresolved'
      $typeName = ''
      if ($root -match '^(MR|LR|CR|DM|EM|FM|CM|ZF|R|B|W|T|C|Z|L|V)\d') { $class = 'device'; $typeName = 'device' }
      elseif ($variableType.Contains($root)) { $class = 'variable'; $typeName = [string]$variableType[$root] }
      elseif ($fbInstances.Contains($root)) { $class = 'fb_instance'; $typeName = [string]$fbInstances[$root] }
      elseif ($root.StartsWith('_')) { $class = 'system_object'; $typeName = 'declaration_not_exported' }
      if (-not $symbols.Contains($root)) {
        $symbols[$root] = [pscustomobject]@{ name = $root; class = $class; data_type = $typeName; first_module = $file.BaseName; first_line = $n + 1 }
      }
      if ($memberPaths.Count -lt 400) {
        $memberPaths.Add([pscustomobject]@{ module = $file.BaseName; line = $n + 1; path = $path; root = $root; class = $class; data_type = $typeName }) | Out-Null
      }
    }
  }
}

$byClass = [ordered]@{}
foreach ($k in $symbols.Keys) {
  $c = $symbols[$k].class
  if (-not $byClass.Contains($c)) { $byClass[$c] = 0 }
  $byClass[$c]++
}
$programNames = @(@($inventory.program_modules) | ForEach-Object { [string]$_.module_name })
$unresolved = @($symbols.Keys | Where-Object { $symbols[$_].class -eq 'unresolved' } | ForEach-Object { [pscustomobject]@{ name = $_; first_module = $symbols[$_].first_module; first_line = $symbols[$_].first_line; scope = $(if ($programNames -contains $symbols[$_].first_module) { 'program' } else { 'body' }) } })

$result = [ordered]@{
  schema_version = 1
  generated_at = (Get-Date).ToUniversalTime().ToString('o')
  source = [ordered]@{ snapshot_root = $snapshotRoot; inventory = $inventoryPath; globals = $(if (Test-Path -LiteralPath $globalsPath -PathType Leaf) { $globalsPath } else { '' }) }
  counts = [ordered]@{
    symbols = $symbols.Count
    by_class = $byClass
    variables_declared_in_snapshot = $variableType.Count
    user_types = $userTypes.Count
    system_types = $systemTypes.Count
    unresolved = $unresolved.Count
    unresolved_in_programs = @($unresolved | Where-Object { $_.scope -eq 'program' }).Count
    unresolved_in_bodies = @($unresolved | Where-Object { $_.scope -ne 'program' }).Count
  }
  unresolved_symbols = $unresolved
  symbols = @($symbols.Keys | ForEach-Object { $symbols[$_] })
  member_paths = $memberPaths.ToArray()
  omissions = @(
    'system object member lists are not exported by any snapshot route; the member path is recorded from usage and must be confirmed against the manual',
    'program local variable tables are only present when the variables route captured them; a symbol that is local to a program can therefore appear as unresolved'
  )
}
$out = [IO.Path]::GetFullPath($OutPath)
$parent = Split-Path -Parent $out
if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
[IO.File]::WriteAllText($out, ($result | ConvertTo-Json -Depth 10), (New-Object System.Text.UTF8Encoding($false)))
Write-Output ('symbols=' + $symbols.Count + ' unresolved=' + $unresolved.Count)
