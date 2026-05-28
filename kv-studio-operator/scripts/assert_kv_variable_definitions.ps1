param(
  [Parameter(Mandatory=$true)]
  [string[]]$TsvPath,

  [ValidateSet('global','local','any')]
  [string]$Scope = 'any',

  [string]$ExpectedOwnerProgram = '',
  [string]$OutPath = ''
)

$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $PSCommandPath
. (Join-Path $scriptRoot 'kv_variable_definition_lib.ps1')

function Read-KvVariableTsv([string]$Path) {
  if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
    throw "Variable TSV not found: $Path"
  }
  $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::Default)
  if ([string]::IsNullOrWhiteSpace($text)) {
    throw "Variable TSV is empty: $Path"
  }
  $firstLine = @($text -split "(`r`n|`n|`r)" | Where-Object { $_ -ne '' } | Select-Object -First 1)
  if ($firstLine.Count -eq 0) {
    throw "Variable TSV has no header: $Path"
  }
  $rows = @($text | ConvertFrom-Csv -Delimiter "`t")
  $required = @('scope','owner_program','name','data_type','device','initial_value','comment','evidence','status')
  $actual = @([string]$firstLine[0] -split "`t")
  $missing = @($required | Where-Object { $actual -notcontains $_ })
  if ($missing.Count -gt 0) {
    return [pscustomobject]@{
      rows = @()
      errors = @([pscustomobject]@{
        code = 'KV_VARIABLE_TSV_SCHEMA_INVALID'
        source = $Path
        missing_columns = $missing
        message = "Variable TSV missing required column(s): $($missing -join ', ')"
      })
    }
  }
  [pscustomobject]@{ rows = $rows; errors = @() }
}

$allErrors = [System.Collections.Generic.List[object]]::new()
$checked = [System.Collections.Generic.List[object]]::new()

foreach ($path in $TsvPath) {
  $fullPath = [IO.Path]::GetFullPath($path)
  try {
    $read = Read-KvVariableTsv $fullPath
    foreach ($errorItem in @($read.errors)) { $allErrors.Add($errorItem) }
    if (@($read.errors).Count -eq 0) {
      $scopesToCheck = if ($Scope -eq 'any') { @('global','local') } else { @($Scope) }
      foreach ($scopeItem in $scopesToCheck) {
        $errors = Get-KvVariableDefinitionErrors -Rows @($read.rows) -Scope $scopeItem -SourcePath $fullPath -ExpectedOwnerProgram $ExpectedOwnerProgram
        foreach ($errorItem in @($errors)) { $allErrors.Add($errorItem) }
      }
    }
    $checked.Add([pscustomobject]@{ path = $fullPath })
  } catch {
    $allErrors.Add([pscustomobject]@{
      code = 'KV_VARIABLE_TSV_READ_FAILED'
      source = $fullPath
      message = $_.Exception.Message
    })
  }
}

$payload = [ordered]@{
  ok = ($allErrors.Count -eq 0)
  checked = @($checked)
  supported_type_pattern = Get-KvVariableSupportedTypePatternText
  errors = @($allErrors)
}

if ($OutPath) {
  $OutPath = [IO.Path]::GetFullPath($OutPath)
  $parent = Split-Path -Parent $OutPath
  if ($parent) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
  $payload | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutPath -Encoding UTF8
}

if (-not $payload.ok) {
  [Console]::Error.WriteLine('KV_VARIABLE_DEFINITION_VALIDATION_FAILED ' + (($payload | ConvertTo-Json -Depth 8 -Compress)))
  exit 42
}

$payload | ConvertTo-Json -Depth 8
