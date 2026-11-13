param(
  [Parameter(Mandatory=$true)][string]$ExpectedCsv,
  [Parameter(Mandatory=$true)][string]$ActualCsv,
  [Parameter(Mandatory=$true)][string]$OutDir
)

# Non-UI verification of a device-comment import.
#
# The promise of an import is "every device/comment pair in ExpectedCsv is now
# stored in the project".  The only honest way to prove that is to export the
# table again from the project (ActualCsv) and compare entry by entry, because
# the import dialog reports nothing useful and a "0 rows" answer is ambiguous.
#
# Comparison rules
#   - devices are normalised the way KV STUDIO renders them (area letters in
#     upper case, leading zeros kept, optional .bit member kept);
#   - only devices that carry at least one non-empty comment in ExpectedCsv are
#     required to exist in ActualCsv, so an intentionally comment-free row does
#     not fabricate a failure;
#   - the comparison is made over the whole comment set of a device (banks 1..8),
#     not over a fixed column, because KV STUDIO keeps the bank a comment was
#     typed in.
#
# Exit codes: 0 = every expected entry verified, 41 = mismatch/incomplete.
$ErrorActionPreference = 'Stop'
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

# KV STUDIO normalises the device text while reading a table (MR0001 -> MR001,
# DM0001 -> DM1), so the two sides of the diff are compared on a canonical key
# instead of on the literal spelling: area letters upper case, leading zeros of
# the number dropped, optional .bit member kept.
function ConvertTo-DeviceKey([string]$Device) {
  $match = [regex]::Match($Device, '^([A-Za-z]+)0*([0-9A-Fa-f]+)(\..*)?$')
  if (-not $match.Success) { return $Device.ToUpperInvariant() }
  $member = if ($match.Groups[3].Success) { $match.Groups[3].Value.ToUpperInvariant() } else { '' }
  return ($match.Groups[1].Value.ToUpperInvariant() + '|' + $match.Groups[2].Value.ToUpperInvariant() + '|' + $member)
}
function Read-CommentCsv([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "comment table not found: $Path" }
  $bytes = [IO.File]::ReadAllBytes($Path)
  $text = ([Text.Encoding]::GetEncoding(0)).GetString($bytes)   # ANSI code page, as written by KV STUDIO
  if ($text.Length -gt 0 -and $text[0] -eq [char]0xFEFF) { $text = $text.Substring(1) }
  $lines = @($text -split "`r?`n" | Where-Object { $_.Trim().Length -gt 0 })
  $map = @{}
  foreach ($line in @($lines | Select-Object -Skip 1)) {
    $fields = @($line -split ',')
    $device = ([string]$fields[0]).Trim()
    if (-not $device) { continue }
    $comments = @()
    for ($i = 2; $i -lt [Math]::Min($fields.Count, 10); $i++) {
      $value = ([string]$fields[$i]).Trim()
      if ($value) { $comments += $value }
    }
    $key = ConvertTo-DeviceKey $device
    $map[$key] = [pscustomobject]@{ device = $device; comments = $comments; raw = $line }
  }
  return $map
}

$expected = Read-CommentCsv $ExpectedCsv
$actual = Read-CommentCsv $ActualCsv

$required = @($expected.Keys | Where-Object { @($expected[$_].comments).Count -gt 0 } | Sort-Object)
$verified = New-Object System.Collections.Generic.List[object]
$mismatches = New-Object System.Collections.Generic.List[object]

foreach ($key in $required) {
  $want = $expected[$key]
  if (-not $actual.ContainsKey($key)) {
    $mismatches.Add([pscustomobject]@{ device = $want.device; kind = 'missing_device'; expected = ($want.comments -join ' / '); actual = '' }) | Out-Null
    continue
  }
  $got = $actual[$key]
  $gotText = ($got.comments -join ' / ')
  $wantText = ($want.comments -join ' / ')
  if ($gotText -eq $wantText) {
    $verified.Add([pscustomobject]@{ device = $want.device; comment = $wantText }) | Out-Null
  } else {
    $mismatches.Add([pscustomobject]@{ device = $want.device; kind = 'comment_mismatch'; expected = $wantText; actual = $gotText }) | Out-Null
  }
}

$result = [ordered]@{
  ok              = ($mismatches.Count -eq 0 -and $verified.Count -gt 0)
  expected_path   = $ExpectedCsv
  actual_path     = $ActualCsv
  expected_devices = $expected.Count
  actual_devices  = $actual.Count
  required        = $required.Count
  verified        = $verified.Count
  mismatch_count  = $mismatches.Count
  mismatches      = $mismatches.ToArray()   # not @(): Windows PowerShell 5.1 breaks on @(List) inside a hashtable literal
  generated_at    = (Get-Date).ToString('o')
}
$result | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath (Join-Path $OutDir 'comment_import_verification.json') -Encoding UTF8
$verified | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $OutDir 'verified_comments.json') -Encoding UTF8

if (-not $result.ok) {
  $mismatches | ForEach-Object { Write-Output ("MISMATCH {0} {1}: expected='{2}' actual='{3}'" -f $_.device, $_.kind, $_.expected, $_.actual) }
  Write-Output ("FAIL: verified={0} mismatches={1}" -f $verified.Count, $mismatches.Count)
  exit 41
}
Write-Output ("OK: verified {0} of {0} required comment entries" -f $verified.Count)
exit 0
