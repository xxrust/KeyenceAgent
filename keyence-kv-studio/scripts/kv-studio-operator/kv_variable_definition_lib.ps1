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

$script:KvNoLocalVariablesMarkerName = '__NO_LOCAL_VARIABLES__'
$script:KvNoLocalVariablesMarkerStatus = 'no_local_variables'

function Normalize-KvVariableCustomDataTypes([string[]]$AllowedCustomDataTypes = @()) {
  @(
    $AllowedCustomDataTypes |
      ForEach-Object { ([string]$_) -split ',' } |
      ForEach-Object { ([string]$_).Trim() } |
      Where-Object { $_ } |
      Select-Object -Unique
  )
}

function Get-KvVariableSupportedTypePatternText {
  param([string[]]$AllowedCustomDataTypes = @())
  $base = 'BOOL, INT, DINT, UINT, UDINT, REAL, LREAL, TIME, STRING[n], ARRAY[lower..upper] OF <supported scalar or STRING[n]>'
  $custom = @(Normalize-KvVariableCustomDataTypes $AllowedCustomDataTypes)
  if ($custom.Count -eq 0) { return $base }
  return ($base + ', custom FB instance types: ' + ($custom -join ', '))
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

function Test-KvVariableCustomDataType([string]$DataType, [string[]]$AllowedCustomDataTypes = @()) {
  $type = ([string]$DataType).Trim()
  if (-not $type) { return $false }
  return (@(Normalize-KvVariableCustomDataTypes $AllowedCustomDataTypes) -contains $type)
}

function Test-KvVariableDataType([string]$DataType, [string[]]$AllowedCustomDataTypes = @()) {
  if ([string]::IsNullOrWhiteSpace($DataType)) { return $false }
  return (Test-KvVariableScalarDataType $DataType) -or
    (Test-KvVariableStringDataType $DataType) -or
    (Test-KvVariableArrayDataType $DataType) -or
    (Test-KvVariableCustomDataType $DataType $AllowedCustomDataTypes)
}

function Test-KvSoftDeviceLikeVariableName([string]$Name) {
  if ([string]::IsNullOrWhiteSpace($Name)) { return $false }
  return ($Name -match '^(X|Y|R|MR|LR|CR|B|VB|DM|EM|FM|ZF|W|TM|TC|TS|CM|CC|CS|T|C)\d+([._][A-Za-z0-9]+)?$')
}

function Test-KvNoLocalVariablesMarkerRow([object]$Row) {
  if ($null -eq $Row) { return $false }
  return ([string]$Row.status -eq $script:KvNoLocalVariablesMarkerStatus)
}

function Get-KvExecutableVariableRows {
  param(
    [AllowEmptyCollection()]
    [AllowNull()]
    [object[]]$Rows,

    [ValidateSet('global','local')]
    [string]$Scope
  )

  if ($null -eq $Rows) { return @() }
  @($Rows | Where-Object {
    [string]$_.scope -eq $Scope -and
    [string]$_.status -ne 'display_name' -and
    [string]$_.status -ne $script:KvNoLocalVariablesMarkerStatus -and
    [string]$_.name
  })
}

function Get-KvNoLocalVariablesMarkerErrors {
  param(
    [AllowEmptyCollection()]
    [AllowNull()]
    [object[]]$Rows,

    [string]$SourcePath = '',
    [string]$ExpectedOwnerProgram = ''
  )

  if ($null -eq $Rows) { $Rows = @() }
  $errors = [System.Collections.Generic.List[object]]::new()
  $markers = @($Rows | Where-Object { Test-KvNoLocalVariablesMarkerRow $_ })
  if ($markers.Count -eq 0) { return @() }

  if ($markers.Count -gt 1) {
    $errors.Add([pscustomobject]@{
      code = 'KV_VARIABLE_NO_LOCAL_MARKER_DUPLICATE'
      source = $SourcePath
      message = 'Only one no_local_variables marker row is allowed per local variable TSV.'
    })
  }

  $executableLocalRows = @(Get-KvExecutableVariableRows -Rows $Rows -Scope local)
  if ($executableLocalRows.Count -gt 0) {
    $errors.Add([pscustomobject]@{
      code = 'KV_VARIABLE_NO_LOCAL_MARKER_CONFLICT'
      source = $SourcePath
      message = 'The no_local_variables marker cannot coexist with executable local variable rows.'
    })
  }

  foreach ($marker in $markers) {
    $scope = ([string]$marker.scope).Trim()
    $owner = ([string]$marker.owner_program).Trim()
    $name = ([string]$marker.name).Trim()
    $dataType = ([string]$marker.data_type).Trim()
    $device = ([string]$marker.device).Trim()
    $initialValue = ([string]$marker.initial_value).Trim()
    $comment = ([string]$marker.comment).Trim()
    $evidence = ([string]$marker.evidence).Trim()

    if ($scope -ne 'local') {
      $errors.Add([pscustomobject]@{
        code = 'KV_VARIABLE_NO_LOCAL_MARKER_SCOPE_INVALID'
        source = $SourcePath
        scope = $scope
        message = 'The no_local_variables marker is valid only in local variable TSV rows.'
      })
    }
    if ($ExpectedOwnerProgram -and $owner -ne $ExpectedOwnerProgram) {
      $errors.Add([pscustomobject]@{
        code = 'KV_VARIABLE_NO_LOCAL_MARKER_OWNER_MISMATCH'
        source = $SourcePath
        owner_program = $owner
        expected_owner_program = $ExpectedOwnerProgram
        message = 'The no_local_variables marker owner_program must match the target module/program.'
      })
    }
    if ($name -ne $script:KvNoLocalVariablesMarkerName) {
      $errors.Add([pscustomobject]@{
        code = 'KV_VARIABLE_NO_LOCAL_MARKER_NAME_INVALID'
        source = $SourcePath
        name = $name
        expected_name = $script:KvNoLocalVariablesMarkerName
        message = 'The no_local_variables marker must use the reserved name __NO_LOCAL_VARIABLES__.'
      })
    }
    if ($dataType -or $device -or $initialValue) {
      $errors.Add([pscustomobject]@{
        code = 'KV_VARIABLE_NO_LOCAL_MARKER_PAYLOAD_INVALID'
        source = $SourcePath
        message = 'The no_local_variables marker must not define data_type, device, or initial_value.'
      })
    }
    if (-not $comment -or -not $evidence) {
      $errors.Add([pscustomobject]@{
        code = 'KV_VARIABLE_NO_LOCAL_MARKER_EVIDENCE_MISSING'
        source = $SourcePath
        message = 'The no_local_variables marker requires non-empty comment and evidence fields.'
      })
    }
  }
  return @($errors)
}

function New-KvVariableDefinition {
  param(
    [ValidateSet('global','local')]
    [string]$Scope,

    [string]$OwnerProgram = '',

    [Parameter(Mandatory=$true)]
    [string]$Name,

    [Parameter(Mandatory=$true)]
    [string]$DataType,

    [string]$Device = '',
    [string]$InitialValue = '',
    [string]$Comment = '',
    [string]$Evidence = '',
    [string]$Status = 'defined',
    [string[]]$AllowedCustomDataTypes = @()
  )

  $definition = [pscustomobject]@{
    scope = $Scope
    owner_program = if ($Scope -eq 'local') { ([string]$OwnerProgram).Trim() } else { '' }
    name = ([string]$Name).Trim()
    data_type = ([string]$DataType).Trim()
    device = ([string]$Device).Trim()
    initial_value = [string]$InitialValue
    comment = [string]$Comment
    evidence = [string]$Evidence
    status = if ($Status) { [string]$Status } else { 'defined' }
  }

  $errors = @(Get-KvVariableDefinitionErrors -Rows @($definition) -Scope $Scope -ExpectedOwnerProgram $definition.owner_program -AllowedCustomDataTypes $AllowedCustomDataTypes)
  if ($errors.Count -gt 0) {
    $first = $errors[0]
    throw "$($first.code): $($first.message) name=$($definition.name) data_type=$($definition.data_type) supported=$(Get-KvVariableSupportedTypePatternText -AllowedCustomDataTypes $AllowedCustomDataTypes)"
  }

  return $definition
}

function ConvertTo-KvVariableTsvLine {
  param(
    [Parameter(Mandatory=$true)]
    [object]$Definition
  )

  @(
    [string]$Definition.scope
    [string]$Definition.owner_program
    [string]$Definition.name
    [string]$Definition.data_type
    [string]$Definition.device
    [string]$Definition.initial_value
    [string]$Definition.comment
    [string]$Definition.evidence
    [string]$Definition.status
  ) -join "`t"
}

function Get-KvVariableDefinitionErrors {
  param(
    [Parameter(Mandatory=$true)]
    [AllowEmptyCollection()]
    [AllowNull()]
    [object[]]$Rows,

    [ValidateSet('global','local')]
    [string]$Scope,

    [string]$SourcePath = '',
    [string]$ExpectedOwnerProgram = '',
    [string[]]$AllowedCustomDataTypes = @()
  )

  if ($null -eq $Rows) { $Rows = @() }
  $errors = [System.Collections.Generic.List[object]]::new()
  foreach ($row in @($Rows)) {
    if ([string]$row.scope -ne $Scope) { continue }
    if ([string]$row.status -eq 'display_name') { continue }
    if ([string]$row.status -eq $script:KvNoLocalVariablesMarkerStatus) {
      continue
    }

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

    if (-not (Test-KvVariableDataType $dataType $AllowedCustomDataTypes)) {
      $errors.Add([pscustomobject]@{
        code = 'KV_VARIABLE_DATA_TYPE_UNSUPPORTED'
        scope = $Scope
        name = $name
        data_type = $dataType
        source = $SourcePath
        supported = Get-KvVariableSupportedTypePatternText -AllowedCustomDataTypes $AllowedCustomDataTypes
        message = 'Variable data_type is outside the current script-supported KEYENCE type grammar.'
      })
    }

    if ($Scope -eq 'local' -and -not $ownerProgram) {
      $errors.Add([pscustomobject]@{
        code = 'KV_VARIABLE_LOCAL_OWNER_MISSING'
        scope = $Scope
        name = $name
        data_type = $dataType
        source = $SourcePath
        message = 'Local variable owner_program is required.'
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
