param(
  [string]$RepoRoot = '.',
  [string]$ConfigPath = '',
  [string]$OutputJson = '',
  [switch]$AllowUsersPublic
)

$ErrorActionPreference = 'Stop'

function Resolve-FullPath([string]$Path) {
  if ([IO.Path]::IsPathRooted($Path)) {
    return [IO.Path]::GetFullPath($Path)
  }
  return [IO.Path]::GetFullPath((Join-Path (Get-Location) $Path))
}

function ConvertTo-RegexObject([object]$Item, [string]$DefaultClass) {
  if ($Item -is [string]) {
    return [pscustomobject]@{ name = $Item; class = $DefaultClass; regex = $Item }
  }
  return [pscustomobject]@{
    name = [string]$Item.name
    class = if ($Item.class) { [string]$Item.class } else { $DefaultClass }
    regex = [string]$Item.regex
  }
}

$root = Resolve-FullPath $RepoRoot
if (-not (Test-Path -LiteralPath $root -PathType Container)) {
  throw "RepoRoot not found: $root"
}

$config = [pscustomobject]@{
  allow_patterns = @()
  deny_patterns = @()
}
if ($ConfigPath) {
  $configFile = Resolve-FullPath $ConfigPath
  if (-not (Test-Path -LiteralPath $configFile -PathType Leaf)) {
    throw "ConfigPath not found: $configFile"
  }
  $config = Get-Content -LiteralPath $configFile -Raw | ConvertFrom-Json
}

$deny = @(
  [pscustomobject]@{
    name = 'secret_assignment_literal'
    class = 'required_sensitive'
    regex = '(?i)\b(password|passwd|pwd|secret|token|api[_-]?key|access[_-]?key|credential)\b\s*[:=]\s*[''"](?!(|<[^>]+>|%[A-Z0-9_]+%|\$\{?[A-Z0-9_]+\}?|env:|REPLACE_ME|CHANGE_ME|placeholder|changeme|null|none))[^''"]{6,}[''"]'
  },
  [pscustomobject]@{
    name = 'windows_personal_user_path'
    class = 'optional_sensitive'
    regex = 'C:\\Users\\(?!Public\\|%USERNAME%\\|<[^\\>]+>\\|\$env:USERPROFILE\\)[^\\\s''"`]+\\'
  },
  [pscustomobject]@{
    name = 'nonportable_drive_path'
    class = 'optional_sensitive'
    regex = '(^|[\s''"=(:])([D-Z]:\\)(?!Program Files\\|ProgramData\\|Windows\\)'
  },
  [pscustomobject]@{
    name = 'private_ipv4'
    class = 'required_sensitive'
    regex = '\b(10\.\d{1,3}\.\d{1,3}\.\d{1,3}|192\.168\.\d{1,3}\.\d{1,3}|172\.(1[6-9]|2\d|3[01])\.\d{1,3}\.\d{1,3})\b'
  }
)

if ($config.deny_patterns) {
  $deny += @($config.deny_patterns | ForEach-Object { ConvertTo-RegexObject $_ 'required_sensitive' })
}
$allow = @()
if ($config.allow_patterns) { $allow += @($config.allow_patterns | ForEach-Object { [regex]$_ }) }
$allow += [regex]'C:\\Users\\Public\\'
if ($AllowUsersPublic) { $allow += [regex]'C:\\Users\\Public\\' }

$skipDir = [regex]'[\\/](\.git|node_modules|__pycache__|\.venv|venv|bin|obj|dist|build)[\\/]'
$skipFile = [regex]'\.(png|jpg|jpeg|gif|webp|ico|pdf|zip|7z|rar|dll|exe|pdb|bin|heapsnapshot)$'
$hits = New-Object System.Collections.Generic.List[object]

$gitFiles = @()
try {
  $inside = (& git -C $root rev-parse --is-inside-work-tree 2>$null)
  if ($LASTEXITCODE -eq 0 -and $inside -eq 'true') {
    $gitFiles = @(& git -C $root ls-files --cached --others --exclude-standard)
  }
} catch {
  $gitFiles = @()
}

if ($gitFiles.Count -eq 0) {
  $gitFiles = Get-ChildItem -LiteralPath $root -Recurse -File -Force |
    Where-Object { -not $skipDir.IsMatch($_.FullName) -and -not $skipFile.IsMatch($_.Name) } |
    ForEach-Object { $_.FullName.Substring($root.Length).TrimStart('\','/') }
}

$gitFiles |
  Where-Object { $_ -and -not $skipFile.IsMatch($_) } |
  ForEach-Object {
    $relative = [string]$_
    $file = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $file -PathType Leaf)) { return }
    try {
      $lines = [IO.File]::ReadAllLines($file)
    } catch {
      return
    }
    for ($i = 0; $i -lt $lines.Count; $i++) {
      $line = $lines[$i]
      foreach ($rule in $deny) {
        if ($line -match $rule.regex) {
          $allowed = $false
          foreach ($a in $allow) {
            if ($a.IsMatch($line)) { $allowed = $true; break }
          }
          if (-not $allowed) {
            $hits.Add([pscustomobject]@{
              file = $relative
              line = $i + 1
              rule = $rule.name
              class = $rule.class
              text = $line.Trim()
            })
          }
        }
      }
    }
  }

$result = [pscustomobject]@{
  ok = ($hits.Count -eq 0)
  repo_root = $root
  hit_count = $hits.Count
  hits = @($hits.ToArray())
}

if ($OutputJson) {
  $out = Resolve-FullPath $OutputJson
  New-Item -ItemType Directory -Force -Path (Split-Path -Parent $out) | Out-Null
  $result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $out -Encoding UTF8
}

if ($hits.Count -gt 0) {
  $hits | Format-Table -AutoSize file,line,rule,class,text
  exit 2
}

Write-Host 'sensitive scan ok'
