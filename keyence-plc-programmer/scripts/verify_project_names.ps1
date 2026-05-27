param(
  [string]$ProjectDir = 'C:\Users\Public\KVSkillPractice\official_repro\vm-103\udt_globals_rebuild4_20260505_0925\CodexOfficialReproKVX',
  [string[]]$Names = @('gStn','gdSt01Cylinder','gMcStatus','gAxis','instFB_CylinderSt01','McStatus'),
  [string]$OutDir = 'C:\Users\Public\KVSkillPractice\official_repro\vm-103\verify_project_names_20260505'
)

$ErrorActionPreference = 'Continue'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

if (-not (Test-Path -LiteralPath $ProjectDir)) {
  throw "ProjectDir not found: $ProjectDir"
}

$files = Get-ChildItem -LiteralPath $ProjectDir -File
$summary = foreach ($name in $Names) {
  $matches = $files | Select-String -Pattern $name -SimpleMatch -Encoding Unicode -List -ErrorAction SilentlyContinue
  [pscustomobject]@{
    Name = $name
    Found = [bool]$matches
    Files = (($matches | ForEach-Object { Split-Path -Leaf $_.Path }) -join ';')
  }
}

$summary | Format-Table -AutoSize | Tee-Object -FilePath (Join-Path $OutDir 'summary.txt')
$summary | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'summary.json') -Encoding UTF8
$fileText = $files | Select-Object Name,Length,LastWriteTime | Sort-Object Name | Format-Table -AutoSize | Out-String -Width 240
Set-Content -LiteralPath (Join-Path $OutDir 'project_files.txt') -Value $fileText -Encoding UTF8

if ($summary | Where-Object { -not $_.Found }) {
  exit 2
}
