param(
  [Parameter(Mandatory=$true)]
  [string]$DeviceNamePattern,
  [string]$EdsRoot = 'C:\ProgramData\KEYENCE\KVS\EIP_Eds',
  [string[]]$Assembly = @(),
  [string]$VariableNamePrefix = '',
  [string]$OutPath = '',
  [switch]$Json
)

$ErrorActionPreference = 'Stop'

function ConvertTo-BoundaryRegex {
  param([string]$Pattern)
  if ($Pattern -match '[\*\?]') {
    $escaped = [regex]::Escape($Pattern).Replace('\*', '.*').Replace('\?', '.')
    return "(?i)$escaped"
  }
  $escaped = [regex]::Escape($Pattern)
  "(?i)(^|[^A-Za-z0-9])$escaped([^A-Za-z0-9]|$)"
}

function Get-FirstMatch {
  param([string]$Text, [string]$Pattern)
  $m = [regex]::Match($Text, $Pattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
  if ($m.Success) { return $m.Groups[1].Value.Trim() }
  ''
}

function ConvertTo-KvTypePrefix {
  param([string]$Name)
  $base = ($Name -replace '\[[^\]]+\]', '')
  $base = ($base -replace '[^A-Za-z0-9]+', '_').Trim('_')
  if (-not $base) { $base = 'EtherNetIP_Device' }
  $base
}

function ConvertTo-StCandidate {
  param([string]$Name)
  if ($Name -match '^[A-Za-z_][A-Za-z0-9_]*$') { return $Name }
  ''
}

function Convert-OffsetType {
  param([string]$OffsetDataType, [string]$OffsetSize)
  switch ($OffsetDataType) {
    '1' { 'BOOL' }
    '2' { 'BYTE' }
    '3' { if ($OffsetSize -eq '4') { 'UDINT' } else { 'UINT' } }
    '4' { if ($OffsetSize -eq '4') { 'DINT' } else { 'INT' } }
    '9' { 'WORD' }
    default { "OffsetDataType_$OffsetDataType" }
  }
}

function Read-EdsSummary {
  param([string]$Path)
  $text = Get-Content -LiteralPath $Path -Raw
  [pscustomobject]@{
    path = $Path
    desc_text = Get-FirstMatch $text 'DescText\s*=\s*"([^"]*)"'
    prod_name = Get-FirstMatch $text 'ProdName\s*=\s*"([^"]*)"'
    catalog = Get-FirstMatch $text 'Catalog\s*=\s*"([^"]*)"'
  }
}

function Read-XmlSummary {
  param([string]$Path)
  $text = Get-Content -LiteralPath $Path -Raw
  [pscustomobject]@{
    path = $Path
    text = $text
    default_node_name = Get-FirstMatch $text '<DefaultNodeName>\s*([^<]+)'
    vend_code = Get-FirstMatch $text '<VendCode>\s*([^<]+)'
    prod_type = Get-FirstMatch $text '<ProdType>\s*([^<]+)'
    prod_code = Get-FirstMatch $text '<ProdCode>\s*([^<]+)'
    maj_rev = Get-FirstMatch $text '<MajRev>\s*([^<]+)'
    min_rev = Get-FirstMatch $text '<MinRev>\s*([^<]+)'
  }
}

if (-not (Test-Path -LiteralPath $EdsRoot)) {
  throw "EIP EDS root not found: $EdsRoot"
}

$matchRegex = ConvertTo-BoundaryRegex $DeviceNamePattern
$candidates = @()
foreach ($eds in Get-ChildItem -LiteralPath $EdsRoot -Filter '*.eds' -File) {
  $stem = [System.IO.Path]::GetFileNameWithoutExtension($eds.Name)
  $xmlPath = Join-Path $EdsRoot ($stem + '.xml')
  if (-not (Test-Path -LiteralPath $xmlPath)) { continue }
  $edsInfo = Read-EdsSummary $eds.FullName
  $xmlInfo = Read-XmlSummary $xmlPath
  $haystack = @($edsInfo.desc_text, $edsInfo.prod_name, $edsInfo.catalog, $xmlInfo.default_node_name, $eds.Name) -join "`n"
  if ($haystack -match $matchRegex) {
    $candidates += [pscustomobject]@{
      eds = $edsInfo
      xml = $xmlInfo
      display_name = if ($xmlInfo.default_node_name) { $xmlInfo.default_node_name } else { $edsInfo.prod_name }
    }
  }
}

if ($candidates.Count -eq 0) {
  throw "No EtherNet/IP EDS entry matched DeviceNamePattern '$DeviceNamePattern' under $EdsRoot."
}

$selected = $candidates | Sort-Object @{Expression={ if ($_.display_name -match ("(?i)^" + [regex]::Escape($DeviceNamePattern))) { 0 } else { 1 }}}, display_name | Select-Object -First 1
$assemblies = @()
if ($Assembly.Count -gt 0) {
  foreach ($item in $Assembly) {
    foreach ($part in ([string]$item -split ',')) {
      $trimmed = $part.Trim()
      if ($trimmed) { $assemblies += $trimmed }
    }
  }
} else {
  $assemblies = @('100','101')
}
$typePrefix = ConvertTo-KvTypePrefix $selected.display_name

$members = @()
$blocks = [regex]::Matches($selected.xml.text, '(?s)<IOComment>.*?</IOComment>')
foreach ($m in $blocks) {
  $block = $m.Value
  $asm = Get-FirstMatch $block '<Assembly>\s*([^<]+)'
  if (-not $asm -or ($assemblies -notcontains $asm)) { continue }
  $name = Get-FirstMatch $block '<ENG>\s*([^<]+)'
  if (-not $name) { continue }
  $offset = Get-FirstMatch $block '<Offset>\s*([^<]+)'
  $bitIndex = Get-FirstMatch $block '<BitIndex>\s*([^<]+)'
  $offsetDataType = Get-FirstMatch $block '<OffsetDataType>\s*([^<]+)'
  $offsetSize = Get-FirstMatch $block '<OffsetSize>\s*([^<]+)'
  $direction = if ($asm -eq '100') { 'IN' } elseif ($asm -eq '101') { 'OUT' } else { "ASM$asm" }
  $variableName = ''
  if ($VariableNamePrefix) { $variableName = "{0}_{1}{2}" -f $VariableNamePrefix, $direction.ToLowerInvariant(), $asm }
  $stMember = ConvertTo-StCandidate $name
  $members += [pscustomobject]@{
    assembly = [int]$asm
    direction = $direction
    kv_data_type = "{0}_{1}{2}" -f $typePrefix, $direction, $asm
    variable_name = $variableName
    member = $name
    st_member_candidate = $stMember
    st_reference_candidate = if ($variableName -and $stMember) { "$variableName.$stMember" } else { '' }
    offset = [int]$offset
    bit_index = [int]$bitIndex
    offset_data_type = $offsetDataType
    offset_size_bytes = if ($offsetSize) { [int]$offsetSize } else { 0 }
    inferred_kv_type = Convert-OffsetType $offsetDataType $offsetSize
    source = $selected.xml.path
  }
}

$result = [pscustomobject]@{
  ok = $true
  device_name_pattern = $DeviceNamePattern
  selected_device = $selected.display_name
  eds_path = $selected.eds.path
  xml_path = $selected.xml.path
  vend_code = $selected.xml.vend_code
  prod_type = $selected.xml.prod_type
  prod_code = $selected.xml.prod_code
  revision = "$($selected.xml.maj_rev).$($selected.xml.min_rev)"
  kv_data_type_prefix = $typePrefix
  assemblies = $assemblies
  member_count = $members.Count
  members = $members
}

if ($OutPath) {
  $parent = Split-Path -Parent $OutPath
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutPath -Encoding UTF8
}

if ($Json -or $OutPath) {
  $result | ConvertTo-Json -Depth 8
} else {
  $members | Select-Object assembly,direction,kv_data_type,variable_name,member,st_member_candidate,st_reference_candidate,offset,bit_index,inferred_kv_type | Format-Table -AutoSize
}
