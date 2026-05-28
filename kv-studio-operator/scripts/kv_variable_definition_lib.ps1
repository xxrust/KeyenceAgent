$script:KvScalarVariableDataTypes = @(
  'BOOL',
  'INT',
  'DINT',
  'UINT',
  'UDINT',
  'REAL',
  'LREAL',
  'TIME'
)

function Get-KvVariableSupportedTypePatternText {
  'BOOL, INT, DINT, UINT, UDINT, REAL, LREAL, TIME, STRING[n], ARRAY[lower..upper] OF <supported scalar or STRING[n]>'
}

function Test-KvVariableScalarDataType([string]$DataType) {
  $type = ([string]$DataType).Trim().ToUpperInvariant()
  return ($script:KvScalarVariableDataTypes -contains $type)
}

function Test-KvVariableStringDataType([string]$DataType) {
  $type = ([string]$DataType).Trim().ToUpperInvariant()
  if ($type -eq 'STRING') { return $true }
  if ($type -match '^STRING\[(\d+)\]$') {
    return ([int]$matches[1] -gt 0)
  }
  return $false
}

function Test-KvVariableArrayDataType([string]$DataType) {
  $type = ([string]$DataType).Trim()
  if ($type -notmatch '(?i)^ARRAY\[\s*(-?\d+)\s*\.\.\s*(-?\d+)\s*\]\s+OF\s+(.+)$') {
    return $false
  }
  $lower = [int]$matches[1]
  $upper = [int]$matches[2]
  $elementType = ([string]$matches[3]).Trim()
  if ($upper -lt $lower) { return $false }
  if ($elementType -match '(?i)^ARRAY\[') { return $false }
  return (Test-KvVariableScalarDataType $elementType) -or (Test-KvVariableStringDataType $elementType)
}

function Test-KvVariableDataType([string]$DataType) {
  if ([string]::IsNullOrWhiteSpace($DataType)) { return $false }
  return (Test-KvVariableScalarDataType $DataType) -or
    (Test-KvVariableStringDataType $DataType) -or
    (Test-KvVariableArrayDataType $DataType)
}

function Test-KvSoftDeviceLikeVariableName([string]$Name) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
  return ($Name -match '^(X|Y|R|MR|LR|CR|B|VB|DM|EM|FM|ZF|W|TM|TC|TS|CM|CC|CS|T|C)\d+([._][A-Za-z0-9]+)?$')
}

function Get-KvVariableDefinitionErrors {
  param(
    [Parameter(Mandatory=$true)]
    [object[]]$Rows,

    [ValidateSet('global','local')]
    [string]$Scope,

    [string]$SourcePath = '',
    [string]$ExpectedOwnerProgram = ''
  )

  $errors = [System.Collections.Generic.List[object]]::new()
  foreach ($row in @($Rows)) {
    if ([string]$row.scope -ne $Scope) { continue }
    if ([string]$row.status -eq 'display_name') { continue }

    $name = ([string]$row.name).Trim()
    $dataType = ([string]$row.data_type).Trim()
    $ownerProgram = ([string]$row.owner_program).Trim()

    if (-not $name) {
      $errors.Add([pscustomobject]@{
        code = 'KV_VARIABLE_NAME_MISSING'
        scope = $Scope
        name = $name
        data_type = $dataType
        source = $SourcePath
        message = 'Executable variable row is missing name.'
      })
      continue
    }

    if (Test-KvSoftDeviceLikeVariableName $name) {
      $errors.Add([pscustomobject]@{
        code = 'KV_VARIABLE_NAME_SOFT_DEVICE_CONFLICT'
        scope = $Scope
        name = $name
        data_type = $dataType
        source = $SourcePath
        message = 'Variable name looks like a KV soft-device name and must not be used as a variable identifier.'
      })
    }

    if (-not (Test-KvVariableDataType $dataType)) {
      $errors.Add([pscustomobject]@{
        code = 'KV_VARIABLE_DATA_TYPE_UNSUPPORTED'
        scope = $Scope
        name = $name
        data_type = $dataType
        source = $SourcePath
        supported = Get-KvVariableSupportedTypePatternText
        message = 'Variable data_type is outside the current script-supported KEYENCE type grammar.'
      })
    }

    if ($Scope -eq 'local' -and $ExpectedOwnerProgram -and $ownerProgram -ne $ExpectedOwnerProgram) {
      $errors.Add([pscustomobject]@{
        code = 'KV_VARIABLE_LOCAL_OWNER_MISMATCH'
        scope = $Scope
        name = $name
        data_type = $dataType
        owner_program = $ownerProgram
        expected_owner_program = $ExpectedOwnerProgram
        source = $SourcePath
        message = 'Local variable owner_program must match the target module/program.'
      })
    }
  }
  return @($errors)
}
