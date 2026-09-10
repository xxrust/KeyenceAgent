param(
  [Parameter(Mandatory=$true)][string]$WorkRoot,
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string[]]$Names=@(),
  [string]$ApplyPlanPath=''
)
$ErrorActionPreference='Stop'
$WorkRoot=[IO.Path]::GetFullPath($WorkRoot).TrimEnd('\','/')
if ($WorkRoot -eq [IO.Path]::GetPathRoot($WorkRoot).TrimEnd('\') -or $WorkRoot -eq $env:USERPROFILE) { throw 'WorkRoot must be a dedicated work directory' }
$OutDir=[IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$archive=Join-Path $WorkRoot 'archive/before-20260911'
if ($ApplyPlanPath) {
  $plan=Get-Content -Raw -Encoding UTF8 -LiteralPath $ApplyPlanPath | ConvertFrom-Json
  if ($plan.work_root -ne $WorkRoot) { throw 'Archive plan WorkRoot mismatch' }
} else {
  $Names=@($Names | ForEach-Object { $_ -split ',' } | Where-Object { $_ })
  $moves=@(foreach ($name in $Names) {
    if ($name -match '[/\\]' -or $name -in @('.','..','archive','system-reliability')) { throw "Invalid archive name: $name" }
    @{source=(Join-Path $WorkRoot $name);destination=(Join-Path $archive $name)}
  })
  if ($moves.Count -eq 0) { throw 'Supply explicit immediate-child directory names' }
  $plan=@{ok=$true;work_root=$WorkRoot;archive_root=$archive;moves=$moves;mode='plan_only'}
  $plan | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'archive_plan.json') -Encoding UTF8
}
# Resolve every source/destination before the first move. Never overwrite,
# delete, cross a workspace boundary or move through a junction.
foreach ($move in $plan.moves) {
  $source=[IO.Path]::GetFullPath($move.source)
  $destination=[IO.Path]::GetFullPath($move.destination)
  if ((Split-Path -Parent $source) -ne $WorkRoot -or (Split-Path -Parent $destination) -ne [IO.Path]::GetFullPath($archive)) { throw 'Archive target escaped the planned boundary' }
  $item=Get-Item -LiteralPath $source -Force
  if (-not $item.PSIsContainer -or $item.Attributes -band [IO.FileAttributes]::ReparsePoint) { throw "Archive source is not an ordinary directory: $source" }
  if (Test-Path -LiteralPath $destination) { throw "Archive destination already exists: $destination" }
}
if (-not $ApplyPlanPath) { @{ok=$true;planned_directories=$plan.moves.Count;plan_path=(Join-Path $OutDir 'archive_plan.json')} | ConvertTo-Json; return }
New-Item -ItemType Directory -Force -Path $archive | Out-Null
$log=Join-Path $OutDir 'migration.jsonl'
foreach ($move in $plan.moves) {
  Move-Item -LiteralPath $move.source -Destination $move.destination
  @{source=$move.source;destination=$move.destination;timestamp=(Get-Date).ToString('o');moved=$true} | ConvertTo-Json -Compress | Add-Content -LiteralPath $log -Encoding UTF8
}
@{ok=$true;moved_directories=$plan.moves.Count;migration_log=$log;recovery='Move each destination back to its source after checking the source is absent.'} | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $OutDir 'migration_result.json') -Encoding UTF8
Get-Content -LiteralPath (Join-Path $OutDir 'migration_result.json')
