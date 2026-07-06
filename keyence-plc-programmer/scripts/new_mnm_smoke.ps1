param(
  [string]$ModuleName = 'CodexMnmSmoke',
  [string]$InputDevice = 'R000',
  [string]$OutputDevice = 'R500',
  [string]$OutPath = ''
)

$ErrorActionPreference = 'Stop'

if ($ModuleName -notmatch '^[A-Za-z_][A-Za-z0-9_]*$') {
  throw "Invalid ModuleName: $ModuleName"
}
if ($InputDevice -notmatch '^[A-Z]+[0-9]+$') {
  throw "Invalid InputDevice: $InputDevice"
}
if ($OutputDevice -notmatch '^[A-Z]+[0-9]+$') {
  throw "Invalid OutputDevice: $OutputDevice"
}
if (-not $OutPath) {
  $OutPath = Join-Path (Get-Location) ($ModuleName + '.mnm')
}

$content = @(
  'DEVICE:60',
  (';MODULE:' + $ModuleName),
  ';MODULE_TYPE:0',
  ('LD ' + $InputDevice),
  ('OUT ' + $OutputDevice),
  'END',
  'ENDH'
)

$parent = Split-Path -Parent $OutPath
if ($parent) {
  New-Item -ItemType Directory -Force -Path $parent | Out-Null
}
[IO.File]::WriteAllLines($OutPath, $content, [Text.UTF8Encoding]::new($false))

[pscustomobject]@{
  OutPath = (Resolve-Path -LiteralPath $OutPath).Path
  ModuleName = $ModuleName
  InputDevice = $InputDevice
  OutputDevice = $OutputDevice
  LineCount = $content.Count
  Mnemonic = ($content -join '\n')
} | ConvertTo-Json -Depth 3
