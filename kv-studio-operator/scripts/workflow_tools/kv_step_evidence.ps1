# Non-UI execution/evidence support; loaded by the flat executor.
function Get-KvStepContract([object]$Manifest, [string]$RelativePath, [object[]]$Arguments) {
  $property = $Manifest.step_result_contracts.PSObject.Properties[$RelativePath.Replace('\','/')]
  if (-not $property) { throw "KV_STEP_RESULT_CONTRACT_MISSING: $RelativePath" }
  $contract = $property.Value
  $selected = $contract
  $variants = @($contract.variants | Where-Object { $_ -and $Arguments -contains [string]$_.switch })
  if ($variants.Count -gt 1) { throw "KV_STEP_RESULT_CONTRACT_AMBIGUOUS: $RelativePath" }
  if ($variants.Count -eq 1) { $selected = $variants[0] }
  $files = @($selected.files | Where-Object { $_ })
  if ($files.Count -eq 0) { throw "KV_STEP_RESULT_CONTRACT_EMPTY: $RelativePath" }
  foreach ($file in @($files) + @($selected.artifacts | Where-Object { $_ })) {
    if ([IO.Path]::IsPathRooted($file) -or $file -match '[/\\]' -or $file -in @('.', '..')) {
      throw "KV_STEP_RESULT_CONTRACT_INVALID: result artifacts must be filenames: $file"
    }
  }
  [pscustomobject]@{files=$files;artifacts=@($selected.artifacts | Where-Object { $_ })}
}

function ConvertTo-KvProcessArgument([AllowEmptyString()][string]$Value) {
  # Windows CommandLineToArgvW escaping, including embedded quotes and trailing
  # backslashes. Start-Process joins arrays without quoting them itself.
  $escaped = [regex]::Replace($Value, '(\\*)"', '$1$1\"')
  $escaped = [regex]::Replace($escaped, '(\\+)$', '$1$1')
  return '"' + $escaped + '"'
}

function Move-KvPreviousStepEvidence([string]$OutDir, [object]$Contract, [string]$RunId) {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $names = @($Contract.files) + @($Contract.artifacts) + @('fail.txt','failure.json','exit_code.txt','timeout_result.json','runner_child_stdout.txt','runner_child_stderr.txt','step_stdout.txt','step_stderr.txt','step_receipt.json')
  foreach ($name in @($names | Select-Object -Unique)) {
    $path = Join-Path $OutDir $name
    if (Test-Path -LiteralPath $path -PathType Leaf) {
      $archive = Join-Path $OutDir (Join-Path '_history' $RunId)
      New-Item -ItemType Directory -Force -Path $archive | Out-Null
      Move-Item -LiteralPath $path -Destination (Join-Path $archive $name)
    }
  }
}

function Test-KvStepEvidence([string]$OutDir, [object]$Contract, [datetime]$StartedUtc) {
  $evidence = @()
  foreach ($name in @($Contract.files) + @($Contract.artifacts)) {
    $path = Join-Path $OutDir $name
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "KV_STEP_RESULT_MISSING: $path" }
    $item = Get-Item -LiteralPath $path
    if ($item.LastWriteTimeUtc -lt $StartedUtc) { throw "KV_STEP_RESULT_STALE: $path" }
    if (@($Contract.files) -contains $name) {
      try { $payload = Get-Content -Raw -Encoding UTF8 -LiteralPath $path | ConvertFrom-Json }
      catch { throw "KV_STEP_RESULT_INVALID_JSON: $path" }
      if ($null -eq $payload -or $payload.ok -isnot [bool] -or $payload.ok -ne $true) {
        $childCode = if ($payload -and $payload.error_code) { [string]$payload.error_code } else { 'KV_STEP_RESULT_NOT_OK' }
        throw "${childCode}: $path must contain boolean ok=true"
      }
    } elseif ($item.Length -eq 0) { throw "KV_STEP_ARTIFACT_EMPTY: $path" }
    $evidence += [pscustomobject]@{path=$path;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash;bytes=$item.Length}
  }
  foreach ($name in @('fail.txt','failure.json')) {
    if (Test-Path -LiteralPath (Join-Path $OutDir $name) -PathType Leaf) { throw "KV_STEP_FAILURE_ARTIFACT_PRESENT: $name" }
  }
  return $evidence
}

function Get-KvInputFingerprints([object[]]$Arguments) {
  $seen = @{}
  foreach ($arg in $Arguments) {
    $value = [string]$arg
    $isFile = $false
    if ($value) { try { $isFile = Test-Path -LiteralPath $value -PathType Leaf -ErrorAction Stop } catch { $isFile = $false } }
    if ($isFile) {
      $path = (Get-Item -LiteralPath $value).FullName
      if (-not $seen.ContainsKey($path)) {
        $seen[$path]=$true
        [pscustomobject]@{path=$path;sha256=(Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash}
      }
    }
  }
}

function Get-KvCodeFingerprint([string]$ScriptsRoot) {
  # Non-UI file hashing once per run. Covers shared libraries as well as children
  # so changing a dependency invalidates the evidence just like changing a caller.
  $files = @(Get-ChildItem -LiteralPath $ScriptsRoot -Recurse -File | Where-Object { $_.Extension -in @('.ps1','.json','.psm1') } | Sort-Object FullName)
  $rows = @($files | ForEach-Object {
    [pscustomobject]@{path=$_.FullName.Substring($ScriptsRoot.TrimEnd('\','/').Length+1).Replace('\','/');sha256=(Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash}
  })
  $bytes = [Text.Encoding]::UTF8.GetBytes(($rows | ConvertTo-Json -Compress -Depth 4))
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $hash = [BitConverter]::ToString($sha.ComputeHash($bytes)).Replace('-','') } finally { $sha.Dispose() }
  [pscustomobject]@{sha256=$hash;files=$rows}
}
