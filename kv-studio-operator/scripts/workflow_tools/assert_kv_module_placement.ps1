param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectTreePath,

  [Parameter(Mandatory=$true)]
  [string]$ModuleName,

  [Parameter(Mandatory=$true)]
  [ValidateSet('scan','standby','function_block')]
  [string]$Category,

  [Parameter(Mandatory=$true)]
  [string]$OutDir
)

$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

function New-Cn([int[]]$CodePoints) {
  -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Write-PlacementResult([object]$Payload) {
  $path = Join-Path $OutDir 'module_placement_result.json'
  $Payload | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $path -Encoding UTF8
  $Payload | ConvertTo-Json -Depth 6
}

try {
  $ProjectTreePath = [IO.Path]::GetFullPath($ProjectTreePath)
  if (-not (Test-Path -LiteralPath $ProjectTreePath -PathType Leaf)) {
    throw "Project tree evidence file not found: $ProjectTreePath"
  }

  $functionBlockCategory = New-Cn @(0x529F,0x80FD,0x5757)
  $scanModuleCategory = New-Cn @(0x6BCF,0x6B21,0x626B,0x63CF,0x6267,0x884C,0x578B,0x6A21,0x5757)
  $standbyModuleCategory = New-Cn @(0x540E,0x5907,0x6A21,0x5757)
  $knownCategories = @($functionBlockCategory, $scanModuleCategory, $standbyModuleCategory)
  $expectedCategory = if ($Category -eq 'function_block') { $functionBlockCategory } elseif ($Category -eq 'standby') { $standbyModuleCategory } else { $scanModuleCategory }

  $text = [IO.File]::ReadAllText($ProjectTreePath, [Text.Encoding]::UTF8)
  $matches = [regex]::Matches($text, '<value\.first>(.*?)</value\.first>', [Text.RegularExpressions.RegexOptions]::Singleline)
  $currentCategory = ''
  $actualCategory = ''
  for ($i = 0; $i -lt $matches.Count; $i++) {
    $value = [System.Net.WebUtility]::HtmlDecode($matches[$i].Groups[1].Value).Trim()
    if ($knownCategories -contains $value) {
      $currentCategory = $value
      continue
    }
    if ($value -eq $ModuleName -or $value -match ('^' + [regex]::Escape($ModuleName) + '\s+\[\d+\]$')) {
      $actualCategory = $currentCategory
      break
    }
  }

  $ok = ($actualCategory -eq $expectedCategory)
  $payload = [ordered]@{
    ok = $ok
    error_code = if ($ok) { '' } else { 'KV_MODULE_PLACEMENT_MISMATCH' }
    operation = 'assert KV imported module placement'
    module_name = $ModuleName
    category = $Category
    expected_category = $expectedCategory
    actual_category = $actualCategory
    project_tree_path = $ProjectTreePath
    message = if ($ok) { '' } else { "Imported module placement mismatch: module=$ModuleName category=$Category expected=$expectedCategory actual=$actualCategory" }
  }
  Write-PlacementResult $payload
  if ($ok) { exit 0 }
  exit 1
} catch {
  $payload = [ordered]@{
    ok = $false
    error_code = 'KV_MODULE_PLACEMENT_ASSERT_FAILED'
    operation = 'assert KV imported module placement'
    module_name = $ModuleName
    category = $Category
    project_tree_path = $ProjectTreePath
    message = $_.Exception.ToString()
  }
  $_.Exception.ToString() | Set-Content -LiteralPath (Join-Path $OutDir 'fail.txt') -Encoding UTF8
  Write-PlacementResult $payload
  exit 1
}
