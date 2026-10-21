param(
  [string]$RepoRoot = '',
  [Parameter(Mandatory=$true)][string]$OutDir
)
$ErrorActionPreference = 'Stop'
if (-not $RepoRoot) { $RepoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) }
$RepoRoot = [IO.Path]::GetFullPath($RepoRoot)
$outRoot = [IO.Path]::GetFullPath($OutDir)
New-Item -ItemType Directory -Force -Path $outRoot | Out-Null

# Two defect classes that the other gates cannot see, because they only inspect behaviour:
#   1. a script that does not parse at all (an edit that mangled a brace or a quote), and
#   2. a script that contains non-ASCII text but no UTF-8 BOM, which Windows PowerShell 5.1
#      reads as ANSI and therefore turns into mojibake at runtime (this is how a Chinese
#      device or window name silently stops matching).
# Known debt is listed in the baseline file so the check is green today and fails for any
# newly introduced or newly edited offender.
$baselinePath = Join-Path $PSScriptRoot 'script_syntax_baseline.json'
$baseline = @()
if (Test-Path -LiteralPath $baselinePath -PathType Leaf) {
  $baseline = @((Get-Content -Raw -LiteralPath $baselinePath -Encoding UTF8 | ConvertFrom-Json).allow_no_bom_with_non_ascii)
}

$syntaxFailures = New-Object System.Collections.Generic.List[object]
$encodingFailures = New-Object System.Collections.Generic.List[object]
$checked = 0
$strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
foreach ($file in @(Get-ChildItem -LiteralPath $RepoRoot -Recurse -File -Filter '*.ps1' -ErrorAction SilentlyContinue)) {
  $checked++
  $tokens = $null; $errors = $null
  [void][Management.Automation.Language.Parser]::ParseFile($file.FullName, [ref]$tokens, [ref]$errors)
  if (@($errors).Count -gt 0) {
    $syntaxFailures.Add([pscustomobject]@{
      path = $file.FullName.Substring($RepoRoot.Length).TrimStart('\')
      error_count = @($errors).Count
      first_line = $errors[0].Extent.StartLineNumber
      message = $errors[0].Message
    }) | Out-Null
  }
  $bytes = [IO.File]::ReadAllBytes($file.FullName)
  $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)
  $hasNonAscii = $false
  foreach ($b in $bytes) { if ($b -gt 126) { $hasNonAscii = $true; break } }
  if ($hasNonAscii -and -not $hasBom) {
    $rel = $file.FullName.Substring($RepoRoot.Length).TrimStart('\')
    if ($baseline -notcontains $rel) {
      $encodingFailures.Add([pscustomobject]@{ path = $rel; reason = 'non_ascii_without_utf8_bom' }) | Out-Null
    }
  }
}

$result = [ordered]@{
  schema_version = 1
  ok = ($syntaxFailures.Count -eq 0 -and $encodingFailures.Count -eq 0)
  operation = 'assert KV script syntax and encoding'
  repo_root = $RepoRoot
  checked_files = $checked
  baseline_allowlisted = @($baseline).Count
  syntax_failure_count = $syntaxFailures.Count
  encoding_failure_count = $encodingFailures.Count
  syntax_failures = [object[]]$syntaxFailures.ToArray()
  encoding_failures = [object[]]$encodingFailures.ToArray()
  rule = 'every .ps1 must parse; a .ps1 containing non-ASCII must be UTF-8 with BOM so Windows PowerShell 5.1 does not read it as ANSI'
}
[IO.File]::WriteAllText((Join-Path $outRoot 'script_syntax_result.json'), ($result | ConvertTo-Json -Depth 6), (New-Object System.Text.UTF8Encoding($false)))
$result | ConvertTo-Json -Depth 5
if (-not $result.ok) { exit 1 }
exit 0