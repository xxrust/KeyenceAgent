param(
  [string]$ExpectedInventory = '',
  [string]$ActualInventory = '',
  [string]$ScaffoldPath = '',
  [Parameter(Mandatory=$true)][string]$OutDir,
  [string]$Label = '',
  [switch]$RequireExactNumbers,
  [switch]$AllowExtraModules
)

$ErrorActionPreference = 'Stop'

# Saved scan-order verification.
#
# KV STUDIO numbers every saved program module in the project tree
# ("Programs (displayed execution order) ... <name> [n]").  export_kv_project_inventory.ps1 already
# records that number as program_modules[].execution_order, but until now nothing
# compared a restored project against the intended schedule.  This tool closes
# that gap offline: it compares the expected module schedule (a source inventory
# or a scaffold.json import list) with the saved target inventory.
#
# Semantics:
# - Relative order of the expected modules is the hard requirement.
# - Absolute numbers are compared only with -RequireExactNumbers, because a
#   repair import into an existing project can legitimately shift them.
# - Unexpected modules fail by default; -AllowExtraModules records them as
#   warnings while keeping the relative-order check hard.
#
# Exit codes: 0 = verified, 1 = verification failed or input invalid.

function Resolve-FullPath([string]$Path, [string]$ParameterName) {
  if ([string]::IsNullOrWhiteSpace($Path)) {
    throw "KV_SCAN_ORDER_INPUT_INVALID: $ParameterName is required."
  }
  $full = [IO.Path]::GetFullPath($Path)
  if (-not (Test-Path -LiteralPath $full -PathType Leaf)) {
    throw "KV_SCAN_ORDER_INPUT_INVALID: $ParameterName not found: $full"
  }
  return $full
}

function Read-JsonFile([string]$Path, [string]$ParameterName) {
  $text = [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8)
  if ([string]::IsNullOrWhiteSpace($text)) {
    throw "KV_SCAN_ORDER_INPUT_INVALID: $ParameterName is empty: $Path"
  }
  try {
    return ($text | ConvertFrom-Json)
  } catch {
    throw "KV_SCAN_ORDER_INPUT_INVALID: $ParameterName is not valid JSON: $Path ($($_.Exception.Message))"
  }
}

function Get-NameFromScaffoldEntry($Entry) {
  $name = [string]$Entry.module_name
  if ([string]::IsNullOrWhiteSpace($name)) {
    $path = [string]$Entry.path
    if ($path) { $name = [IO.Path]::GetFileNameWithoutExtension($path) }
  }
  return $name.Trim()
}

function Read-ScannedModulesFromInventory([string]$Path) {
  $inventory = Read-JsonFile $Path '-ActualInventory/-ExpectedInventory'
  $property = $inventory.PSObject.Properties['program_modules']
  if (-not $property) {
    throw "KV_SCAN_ORDER_INPUT_INVALID: inventory has no program_modules: $Path"
  }
  $modules = New-Object System.Collections.Generic.List[object]
  $index = 0
  foreach ($item in @($property.Value)) {
    $index++
    if ($null -eq $item) { continue }
    $name = ([string]$item.module_name).Trim()
    if (-not $name) {
      throw "KV_SCAN_ORDER_INPUT_INVALID: inventory program_modules[$index] has no module_name: $Path"
    }
    $order = 0
    try { $order = [int]$item.execution_order } catch { $order = 0 }
    if ($order -le 0) {
      throw "KV_SCAN_ORDER_INPUT_INVALID: module '$name' has no positive execution_order in $Path"
    }
    $category = ''
    if ($item.PSObject.Properties['category']) { $category = ([string]$item.category).Trim() }
    $modules.Add([pscustomobject]@{
      name = $name
      order = $order
      category = $category
      source = $Path
    })
  }
  return $modules.ToArray()
}

function Read-ScannedModulesFromScaffold([string]$Path) {
  $scaffold = Read-JsonFile $Path '-ScaffoldPath'
  $property = $scaffold.PSObject.Properties['mnm_files']
  if (-not $property) {
    throw "KV_SCAN_ORDER_INPUT_INVALID: scaffold has no mnm_files: $Path"
  }
  $modules = New-Object System.Collections.Generic.List[object]
  $order = 0
  foreach ($entry in @($property.Value)) {
    if ($null -eq $entry) { continue }
    $moduleType = 0
    if ($entry.PSObject.Properties['module_type']) {
      try { $moduleType = [int]$entry.module_type } catch { $moduleType = -1 }
    }
    $category = ''
    if ($entry.PSObject.Properties['category']) { $category = ([string]$entry.category).Trim() }
    # Function blocks are declared in the FB tree, not in the scan schedule.
    if ($moduleType -eq 2 -or $category -eq 'function_block') { continue }
    $name = Get-NameFromScaffoldEntry $entry
    if (-not $name) {
      throw "KV_SCAN_ORDER_INPUT_INVALID: scaffold mnm entry has neither module_name nor path: $Path"
    }
    $order++
    $modules.Add([pscustomobject]@{
      name = $name
      order = $order
      category = $category
      source = $Path
    })
  }
  return $modules.ToArray()
}

function Get-DuplicateNames([object[]]$Modules) {
  return @($Modules | Group-Object name | Where-Object { $_.Count -gt 1 } | ForEach-Object { $_.Name } | Sort-Object)
}

function Format-Sequence([string[]]$Names) {
  if ($Names.Count -eq 0) { return '(none)' }
  return ($Names -join ' > ')
}

try {
  if ([string]::IsNullOrWhiteSpace($ActualInventory)) {
    throw 'KV_SCAN_ORDER_INPUT_INVALID: -ActualInventory is required.'
  }
  $hasExpectedInventory = -not [string]::IsNullOrWhiteSpace($ExpectedInventory)
  $hasScaffold = -not [string]::IsNullOrWhiteSpace($ScaffoldPath)
  if ($hasExpectedInventory -eq $hasScaffold) {
    throw 'KV_SCAN_ORDER_INPUT_INVALID: supply exactly one of -ExpectedInventory or -ScaffoldPath.'
  }

  $actualPath = Resolve-FullPath $ActualInventory '-ActualInventory'
  $expectedPath = ''
  $mode = ''
  if ($hasExpectedInventory) {
    $expectedPath = Resolve-FullPath $ExpectedInventory '-ExpectedInventory'
    $mode = 'inventory'
    $expected = @(Read-ScannedModulesFromInventory $expectedPath)
  } else {
    $expectedPath = Resolve-FullPath $ScaffoldPath '-ScaffoldPath'
    $mode = 'scaffold'
    $expected = @(Read-ScannedModulesFromScaffold $expectedPath)
  }
  $actual = @(Read-ScannedModulesFromInventory $actualPath)

  if ($expected.Count -eq 0) {
    throw "KV_SCAN_ORDER_INVENTORY_EMPTY: expected schedule has no scan modules: $expectedPath"
  }
  if ($actual.Count -eq 0) {
    throw "KV_SCAN_ORDER_INVENTORY_EMPTY: saved project has no scan modules: $actualPath"
  }

  $expectedSorted = @($expected | Sort-Object order, name)
  $actualSorted = @($actual | Sort-Object order, name)
  $expectedDuplicates = @(Get-DuplicateNames $expected)
  $actualDuplicates = @(Get-DuplicateNames $actual)

  $expectedByName = @{}
  foreach ($module in $expectedSorted) {
    if (-not $expectedByName.ContainsKey($module.name)) { $expectedByName[$module.name] = $module }
  }
  $actualByName = @{}
  foreach ($module in $actualSorted) {
    if (-not $actualByName.ContainsKey($module.name)) { $actualByName[$module.name] = $module }
  }

  $missing = @($expectedSorted | Where-Object { -not $actualByName.ContainsKey($_.name) } | ForEach-Object { $_.name })
  $extra = @($actualSorted | Where-Object { -not $expectedByName.ContainsKey($_.name) } | ForEach-Object { $_.name })

  $expectedSequence = @($expectedSorted | Where-Object { $actualByName.ContainsKey($_.name) } | ForEach-Object { $_.name })
  $actualSequence = @($actualSorted | Where-Object { $expectedByName.ContainsKey($_.name) } | ForEach-Object { $_.name })

  $firstDivergence = -1
  $limit = [Math]::Min($expectedSequence.Count, $actualSequence.Count)
  for ($i = 0; $i -lt $limit; $i++) {
    if ($expectedSequence[$i] -ne $actualSequence[$i]) { $firstDivergence = $i; break }
  }
  if ($firstDivergence -lt 0 -and $expectedSequence.Count -ne $actualSequence.Count) {
    $firstDivergence = $limit
  }
  $relativeOrderOk = ($firstDivergence -lt 0)

  $expectedPosition = @{}
  for ($i = 0; $i -lt $expectedSequence.Count; $i++) { $expectedPosition[$expectedSequence[$i]] = $i }
  $actualPosition = @{}
  for ($i = 0; $i -lt $actualSequence.Count; $i++) { $actualPosition[$actualSequence[$i]] = $i }
  $numberDrift = New-Object System.Collections.Generic.List[object]
  $moduleRows = New-Object System.Collections.Generic.List[object]
  foreach ($module in $expectedSorted) {
    if ($actualByName.ContainsKey($module.name)) {
      $actualOrder = [int]$actualByName[$module.name].order
      $status = 'ok'
      if ($RequireExactNumbers -and $actualOrder -ne $module.order) {
        $status = 'number_drift'
        $numberDrift.Add([pscustomobject]@{ name = $module.name; expected_order = $module.order; actual_order = $actualOrder })
      } elseif ($actualPosition[$module.name] -ne $expectedPosition[$module.name]) {
        $status = 'order_drift'
      }
      $moduleRows.Add([pscustomobject]@{
        name = $module.name
        expected_order = $module.order
        actual_order = $actualOrder
        category = $actualByName[$module.name].category
        status = $status
      })
    } else {
      $moduleRows.Add([pscustomobject]@{
        name = $module.name
        expected_order = $module.order
        actual_order = $null
        category = ''
        status = 'missing'
      })
    }
  }
  foreach ($name in $extra) {
    $moduleRows.Add([pscustomobject]@{
      name = $name
      expected_order = $null
      actual_order = [int]$actualByName[$name].order
      category = $actualByName[$name].category
      status = 'extra'
    })
  }

  $errorCode = ''
  $message = ''
  if ($expectedDuplicates.Count -gt 0 -or $actualDuplicates.Count -gt 0) {
    $errorCode = 'KV_SCAN_ORDER_DUPLICATE_MODULE'
    $message = "Duplicate module names. expected=[$($expectedDuplicates -join ', ')] actual=[$($actualDuplicates -join ', ')]."
  } elseif ($missing.Count -gt 0) {
    $errorCode = 'KV_SCAN_ORDER_MODULE_MISSING'
    $message = "Saved project is missing expected scan module(s): $($missing -join ', ')."
  } elseif ($extra.Count -gt 0 -and -not $AllowExtraModules) {
    $errorCode = 'KV_SCAN_ORDER_MODULE_EXTRA'
    $message = "Saved project has unexpected scan module(s): $($extra -join ', ')."
  } elseif (-not $relativeOrderOk) {
    $errorCode = 'KV_SCAN_ORDER_MISMATCH'
    $message = "Saved scan order differs from expected. Expected: $(Format-Sequence $expectedSequence). Actual: $(Format-Sequence $actualSequence). First divergence index=$firstDivergence."
  } elseif ($RequireExactNumbers -and $numberDrift.Count -gt 0) {
    $errorCode = 'KV_SCAN_ORDER_NUMBER_MISMATCH'
    $drifting = @($numberDrift | ForEach-Object { "$($_.name) expected=$($_.expected_order) actual=$($_.actual_order)" })
    $message = "Execution numbers differ while relative order matches: $($drifting -join '; ')."
  }
  $ok = [string]::IsNullOrEmpty($errorCode)
  $outRoot = [IO.Path]::GetFullPath($OutDir)
  New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
  $resultPath = Join-Path $outRoot 'scan_order_verification.json'

  $result = [ordered]@{
    ok = $ok
    error_code = $errorCode
    message = $message
    label = $Label
    mode = $mode
    expected_path = $expectedPath
    actual_path = $actualPath
    expected_count = $expected.Count
    actual_count = $actual.Count
    relative_order_ok = $relativeOrderOk
    exact_numbers_required = [bool]$RequireExactNumbers
    exact_numbers_ok = ($numberDrift.Count -eq 0)
    allow_extra_modules = [bool]$AllowExtraModules
    missing = $missing
    extra = $extra
    duplicates = [ordered]@{ expected = $expectedDuplicates; actual = $actualDuplicates }
    expected_sequence = $expectedSequence
    actual_sequence = $actualSequence
    first_divergence_index = $firstDivergence
    number_drift = $numberDrift.ToArray()
    modules = $moduleRows.ToArray()
    evidence = @($resultPath)
    generated_at = (Get-Date).ToString('o')
  }
  $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $resultPath -Encoding UTF8

  if (-not $ok) {
    [Console]::Error.WriteLine("$errorCode : $message")
    [Console]::Error.WriteLine("KV_SCAN_ORDER_EVIDENCE: $resultPath")
    exit 1
  }

  [ordered]@{
    ok = $true
    mode = $mode
    expected_count = $expected.Count
    actual_count = $actual.Count
    relative_order_ok = $relativeOrderOk
    result_path = $resultPath
  } | ConvertTo-Json -Depth 4
} catch {
  $message = $_.Exception.Message
  if ($message -notmatch '^(KV_[A-Z0-9_]+)') { $message = "KV_SCAN_ORDER_INTERNAL_ERROR: $message" }
  $detail = $_.Exception.ToString()
  $outRoot = $OutDir
  try {
    if (-not $outRoot) { throw 'OutDir missing' }
    $outRoot = [IO.Path]::GetFullPath($OutDir)
    New-Item -ItemType Directory -Force -Path $outRoot | Out-Null
    $resultPath = Join-Path $outRoot 'scan_order_verification.json'
    [ordered]@{
      ok = $false
      error_code = if ($message -match '^(KV_[A-Z0-9_]+)') { $Matches[1] } else { 'KV_SCAN_ORDER_INTERNAL_ERROR' }
      message = $message
      detail = $detail
      label = $Label
      expected_path = $ExpectedInventory
      actual_path = $ActualInventory
      scaffold_path = $ScaffoldPath
      evidence = @($resultPath)
      generated_at = (Get-Date).ToString('o')
    } | ConvertTo-Json -Depth 6 | Set-Content -LiteralPath $resultPath -Encoding UTF8
    [Console]::Error.WriteLine($message)
    [Console]::Error.WriteLine($detail)
    [Console]::Error.WriteLine("KV_SCAN_ORDER_EVIDENCE: $resultPath")
  } catch {
    [Console]::Error.WriteLine($message)
  }
  exit 1
}
