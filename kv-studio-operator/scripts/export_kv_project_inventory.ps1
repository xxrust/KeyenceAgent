param(
  [Parameter(Mandatory=$true)]
  [string]$ProjectPath,

  [string]$MnmDir = '',
  [Parameter(Mandatory=$true)]
  [string]$OutDir
)

$ErrorActionPreference = 'Stop'

function Write-JsonFile {
  param([string]$Path, $Value, [int]$Depth = 24)
  $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $Path -Encoding UTF8
}

function Normalize-Text {
  param([string]$Text)
  if ($null -eq $Text) { return '' }
  ([System.Net.WebUtility]::HtmlDecode($Text) -replace '\s+', ' ').Trim()
}

function Get-RelativePathCompat {
  param([string]$BasePath, [string]$ChildPath)
  $baseFull = [IO.Path]::GetFullPath($BasePath).TrimEnd('\') + '\'
  $childFull = [IO.Path]::GetFullPath($ChildPath)
  $baseUri = New-Object System.Uri($baseFull)
  $childUri = New-Object System.Uri($childFull)
  [Uri]::UnescapeDataString($baseUri.MakeRelativeUri($childUri).ToString()).Replace('/', '\')
}

function Get-ProjectDir {
  param([string]$Path)
  if (Test-Path -LiteralPath $Path -PathType Leaf) { return (Split-Path -Parent $Path) }
  if (Test-Path -LiteralPath $Path -PathType Container) { return $Path }
  throw "ProjectPath not found: $Path"
}

function Read-WsTreeNodes {
  param([string]$WsTreePath)
  if (-not (Test-Path -LiteralPath $WsTreePath -PathType Leaf)) { return @() }
  [xml]$xml = Get-Content -LiteralPath $WsTreePath -Raw -Encoding UTF8
  $nodes = New-Object System.Collections.ArrayList
  $nextId = 0

  function Walk-Tree {
    param($Container, [string[]]$Path, $ParentId, [int]$Depth)
    foreach ($child in @($Container.Child)) {
      $text = Normalize-Text ([string]$child.'value.first')
      $currentPath = $Path
      $currentParent = $ParentId
      $currentDepth = $Depth
      if ($text) {
        $script:nextId++
        $id = $script:nextId
        $currentPath = @($Path) + $text
        $expanded = $null
        try { $expanded = [int]$child.'value.second'.Expanded } catch {}
        [void]$script:nodes.Add([ordered]@{
          id = $id
          parent_id = if ($null -ne $ParentId) { [int]$ParentId } else { $null }
          depth = $Depth
          text = $text
          path = $currentPath
          path_text = ($currentPath -join ' > ')
          expanded = $expanded
        })
        $currentParent = $id
        $currentDepth = $Depth + 1
      }
      $second = $child.'value.second'
      if ($second) {
        Walk-Tree -Container $second -Path $currentPath -ParentId $currentParent -Depth $currentDepth
      }
    }
  }

  $script:nodes = $nodes
  $script:nextId = 0
  Walk-Tree -Container $xml.Root -Path @() -ParentId $null -Depth 0
  @($nodes)
}

function Get-Descendants {
  param($Nodes, [int]$NodeId)
  $childrenByParent = @{}
  foreach ($n in $Nodes) {
    if ($null -ne $n.parent_id) {
      $key = [string]$n.parent_id
      if (-not $childrenByParent.ContainsKey($key)) { $childrenByParent[$key] = @() }
      $childrenByParent[$key] += $n
    }
  }
  $out = New-Object System.Collections.ArrayList
  $stack = @($NodeId)
  while ($stack.Count -gt 0) {
    $id = $stack[-1]
    if ($stack.Count -eq 1) { $stack = @() } else { $stack = $stack[0..($stack.Count - 2)] }
    $key = [string]$id
    foreach ($child in @($childrenByParent[$key])) {
      [void]$out.Add($child)
      $stack += $child.id
    }
  }
  @($out)
}

function Get-MnmModuleInfo {
  param([string]$Path)
  $moduleName = [IO.Path]::GetFileNameWithoutExtension($Path)
  $moduleType = $null
  $lines = Get-Content -LiteralPath $Path -TotalCount 40 -ErrorAction Stop
  foreach ($line in $lines) {
    if ($line -match '^;MODULE:(.+)$') { $moduleName = $Matches[1].Trim() }
    if ($line -match '^;MODULE_TYPE:(\d+)\s*$') { $moduleType = [int]$Matches[1] }
  }
  [pscustomobject]@{
    module_name = $moduleName
    module_type = $moduleType
  }
}

function Get-OfficialFbReason {
  param([string]$Name, [string[]]$OfficialNames)
  if (@($OfficialNames) -contains $Name) { return 'project_tree_official_or_library_item' }
  if ($Name -match '^(MC_|_MC_|\[MC\]_|_\[MC\]_)') { return 'motion_control_library_pattern' }
  if ($Name -match '^(ModbusTCPClient_|SocketTCP_)') { return 'communication_library_pattern' }
  if ($Name -match '^(KV_|KL_|NU_|DL_).+_FB$') { return 'keyence_module_library_pattern' }
  ''
}

function Get-LimitedStringEvidence {
  param([string]$FilePath, [string[]]$Patterns, [int]$LimitPerPattern = 30)
  if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) { return $null }
  $bytes = [IO.File]::ReadAllBytes($FilePath)
  $views = [ordered]@{
    ascii = [Text.Encoding]::ASCII.GetString($bytes)
    default = [Text.Encoding]::Default.GetString($bytes)
    utf16le = [Text.Encoding]::Unicode.GetString($bytes)
  }
  $patternResults = @()
  foreach ($pattern in $Patterns) {
    $samples = New-Object System.Collections.ArrayList
    foreach ($viewName in $views.Keys) {
      $matches = [regex]::Matches($views[$viewName], $pattern)
      foreach ($m in $matches) {
        $value = $m.Value.Trim()
        if ($value -and -not (@($samples) -contains $value)) {
          [void]$samples.Add($value)
          if ($samples.Count -ge $LimitPerPattern) { break }
        }
      }
      if ($samples.Count -ge $LimitPerPattern) { break }
    }
    $patternResults += [ordered]@{
      pattern = $pattern
      count_limited = $samples.Count
      samples = @($samples)
    }
  }
  [ordered]@{
    file = $FilePath
    length = (Get-Item -LiteralPath $FilePath).Length
    patterns = $patternResults
  }
}

try {
  $projectDir = Get-ProjectDir $ProjectPath
  $projectPathFull = if (Test-Path -LiteralPath $ProjectPath -PathType Leaf) { [IO.Path]::GetFullPath($ProjectPath) } else { '' }
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null

  $files = @()
  foreach ($file in Get-ChildItem -LiteralPath $projectDir -File) {
    $files += [ordered]@{
      relative_path = Get-RelativePathCompat $projectDir $file.FullName
      length = $file.Length
      last_write_time = $file.LastWriteTime.ToString('o')
      sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash
    }
  }

  $treePath = Join-Path $projectDir 'WsTreeEnv.xml'
  $treeNodes = @(Read-WsTreeNodes -WsTreePath $treePath)
  $cpuNodes = @($treeNodes | Where-Object { $_.text -match '^\[(\d+)\]\s+(KV-[A-Z0-9*]+)' } | ForEach-Object {
    $_ | Add-Member -NotePropertyName slot -NotePropertyValue ([int]([regex]::Match($_.text, '^\[(\d+)\]').Groups[1].Value)) -PassThru
  })
  $cpuNode = @($cpuNodes | Where-Object { $_.slot -eq 0 } | Select-Object -First 1)
  $cpu = $null
  if ($cpuNode) {
    $m = [regex]::Match($cpuNode.text, '^\[(\d+)\]\s+(KV-[A-Z0-9*]+)')
    $cpu = [ordered]@{
      slot = [int]$m.Groups[1].Value
      model = $m.Groups[2].Value
      tree_text = $cpuNode.text
      evidence = 'WsTreeEnv.xml'
    }
  }

  $expansionUnits = @()
  foreach ($n in @($cpuNodes | Where-Object { $_.slot -ne 0 })) {
    $m = [regex]::Match($n.text, '^\[(\d+)\]\s+(KV-[A-Z0-9*]+)(?:\s+(R\d+))?(?:\s+(DM\d+|-----))?')
    $expansionUnits += [ordered]@{
      slot = [int]$m.Groups[1].Value
      model = $m.Groups[2].Value
      relay_start = if ($m.Groups[3].Success) { $m.Groups[3].Value } else { $null }
      dm_start = if ($m.Groups[4].Success) { $m.Groups[4].Value } else { $null }
      tree_text = $n.text
      evidence = 'WsTreeEnv.xml'
    }
  }

  $ethercat = [ordered]@{ nodes = @(); evidence = 'WsTreeEnv.xml'; status = 'not_found' }
  if ($cpuNode) {
    $ecRoot = @($treeNodes | Where-Object { $_.parent_id -eq $cpuNode.id -and $_.text -eq 'EtherCAT' } | Select-Object -First 1)
    if ($ecRoot) {
      $ecNodes = @($treeNodes | Where-Object { $_.parent_id -eq $ecRoot.id -and $_.text -match '^\[(\d+)\]\s*:\s*(.+)$' } | ForEach-Object {
        $m = [regex]::Match($_.text, '^\[(\d+)\]\s*:\s*(.+)$')
        [ordered]@{
          node = [int]$m.Groups[1].Value
          device_name = $m.Groups[2].Value.Trim()
          tree_text = $_.text
        }
      })
      $ethercat = [ordered]@{
        status = 'tree_summary_extracted'
        root_tree_text = $ecRoot.text
        nodes = $ecNodes
        evidence = 'WsTreeEnv.xml'
        missing_for_clone = @('device catalog path or ESI origin', 'PDO/object mapping details', 'per-device parameter details')
      }
    }
  }

  $ethernetIp = [ordered]@{ devices = @(); evidence = 'WsTreeEnv.xml'; status = 'not_found' }
  if ($cpuNode) {
    $eipRoot = @($treeNodes | Where-Object { $_.parent_id -eq $cpuNode.id -and $_.text -match '^EtherNet/IP\b' } | Select-Object -First 1)
    if ($eipRoot) {
      $rMatch = [regex]::Match($eipRoot.text, '\bR(\d+)\b')
      $dmMatch = [regex]::Match($eipRoot.text, '\bDM(\d+)\b')
      $eipDevices = @($treeNodes | Where-Object { $_.parent_id -eq $eipRoot.id -and $_.text -match '^\[(\d+)\]\s+(.+)$' } | ForEach-Object {
        $m = [regex]::Match($_.text, '^\[(\d+)\]\s+(.+)$')
        [ordered]@{
          node = [int]$m.Groups[1].Value
          device_name = $m.Groups[2].Value.Trim()
          tree_text = $_.text
        }
      })
      $ethernetIp = [ordered]@{
        status = 'tree_summary_extracted'
        root_tree_text = $eipRoot.text
        relay_start = if ($rMatch.Success) { 'R' + $rMatch.Groups[1].Value } else { $null }
        dm_start = if ($dmMatch.Success) { 'DM' + $dmMatch.Groups[1].Value } else { $null }
        devices = $eipDevices
        evidence = 'WsTreeEnv.xml'
        missing_for_clone = @('device IP address', 'variable names from device-variable dialog', 'connection assemblies and detailed EDS mapping if not reconstructable from local EDS cache')
      }
    }
  }

  $motionAxes = @($treeNodes | Where-Object { $_.text -match 'Axis_[0-9]+' } | ForEach-Object {
    $axisNo = $null
    $mNo = [regex]::Match($_.text, '([0-9]+):Axis_([0-9]+)|Axis_([0-9]+)')
    if ($mNo.Success) {
      if ($mNo.Groups[1].Success) { $axisNo = [int]$mNo.Groups[1].Value }
      elseif ($mNo.Groups[3].Success) { $axisNo = [int]$mNo.Groups[3].Value }
    }
    [ordered]@{
      axis_no = $axisNo
      axis_name = [regex]::Match($_.text, 'Axis_[0-9]+').Value
      tree_text = $_.text
      path_text = $_.path_text
    }
  })

  $dataTypes = @($treeNodes | Where-Object { $_.text -match '^(_[A-Z0-9_]+|AXIS)(?::|$)' } | ForEach-Object {
    $m = [regex]::Match($_.text, '^([^:]+)(?::(.*))?$')
    [ordered]@{
      name = $m.Groups[1].Value.Trim()
      description = if ($m.Groups[2].Success) { $m.Groups[2].Value.Trim() } else { '' }
      path_text = $_.path_text
    }
  })

  $programModules = @($treeNodes | Where-Object { $_.text -match '^[A-Za-z_][A-Za-z0-9_]*\s+\[\d+\]$' } | ForEach-Object {
    $m = [regex]::Match($_.text, '^([A-Za-z_][A-Za-z0-9_]*)\s+\[(\d+)\]$')
    [ordered]@{
      module_name = $m.Groups[1].Value
      execution_order = [int]$m.Groups[2].Value
      tree_text = $_.text
      path_text = $_.path_text
    }
  })

  $officialNames = @($treeNodes | Where-Object { $_.text -match '^([A-Za-z_][A-Za-z0-9_\[\]]+):' } | ForEach-Object {
    $name = [regex]::Match($_.text, '^([A-Za-z_][A-Za-z0-9_\[\]]+):').Groups[1].Value
    if ($name -match '^(MC_|_MC_|\[MC\]_|_\[MC\]_|ModbusTCPClient_|SocketTCP_|UniversalLibrary$)') { $name }
  } | Where-Object { $_ } | Sort-Object -Unique)

  $mnmInventory = @()
  if ($MnmDir -and (Test-Path -LiteralPath $MnmDir -PathType Container)) {
    foreach ($mnm in Get-ChildItem -LiteralPath $MnmDir -File -Filter '*.mnm') {
      $info = Get-MnmModuleInfo -Path $mnm.FullName
      $classification = 'program_or_non_fb'
      $reason = 'module_type_is_not_2'
      if ($info.module_type -eq 2) {
        $officialReason = Get-OfficialFbReason -Name $info.module_name -OfficialNames $officialNames
        if ($officialReason) {
          $classification = 'official_or_library_fb'
          $reason = $officialReason
        } else {
          $classification = 'user_fb'
          $reason = 'module_type_2_without_official_evidence'
        }
      } elseif ($null -eq $info.module_type) {
        $classification = 'unknown_mnm'
        $reason = 'module_type_missing'
      }
      $mnmInventory += [ordered]@{
        file = $mnm.FullName
        relative_path = Get-RelativePathCompat $MnmDir $mnm.FullName
        module_name = $info.module_name
        module_type = $info.module_type
        classification = $classification
        reason = $reason
        length = $mnm.Length
        sha256 = (Get-FileHash -LiteralPath $mnm.FullName -Algorithm SHA256).Hash
      }
    }
  }

  $stringPatterns = @(
    'KV-[A-Za-z0-9*]+',
    'MBDLN25BE',
    'TM-X5000(?: Series)?',
    'EtherNet/IP',
    'EtherCAT',
    'Axis_[0-9]+',
    'DM[0-9]+',
    'R[0-9]+',
    'EipData',
    'Nd[0-9]+'
  )
  $sidecarEvidence = @()
  foreach ($name in @('UnitSet.ue2','UnitSet.bak','DevInit.dvi','PlcDeviceValue.csv','PlcSended.dky')) {
    $path = Join-Path $projectDir $name
    $e = Get-LimitedStringEvidence -FilePath $path -Patterns $stringPatterns
    if ($e) { $sidecarEvidence += $e }
  }

  $sidecarUnitNames = New-Object 'System.Collections.Generic.HashSet[string]'
  $sidecarRelayStarts = New-Object 'System.Collections.Generic.HashSet[string]'
  $sidecarDmStarts = New-Object 'System.Collections.Generic.HashSet[string]'
  foreach ($e in @($sidecarEvidence | Where-Object { $_.file -match 'UnitSet\.(ue2|bak)$' })) {
    foreach ($p in @($e.patterns)) {
      if ($p.pattern -eq 'KV-[A-Za-z0-9*]+') {
        foreach ($sample in @($p.samples)) {
          if ($sample -and $sample -notmatch '^KV-X') { [void]$sidecarUnitNames.Add($sample) }
        }
      }
      if ($p.pattern -eq 'R[0-9]+') {
        foreach ($sample in @($p.samples)) {
          if ($sample -and $sample -ne 'R0') { [void]$sidecarRelayStarts.Add($sample) }
        }
      }
      if ($p.pattern -eq 'DM[0-9]+') {
        foreach ($sample in @($p.samples)) { if ($sample) { [void]$sidecarDmStarts.Add($sample) } }
      }
    }
  }
  $sidecarExpansionCandidates = @()
  foreach ($unitName in @($sidecarUnitNames | Sort-Object)) {
    $sidecarExpansionCandidates += [ordered]@{
      model = $unitName
      relay_start_samples = @($sidecarRelayStarts | Sort-Object)
      dm_start_samples = @($sidecarDmStarts | Sort-Object)
      evidence = @('UnitSet.ue2','UnitSet.bak')
      status = 'sidecar_string_candidate_not_promoted_without_tree_or_ui_evidence'
    }
  }

  $assetStatus = [ordered]@{
    plc_cpu = if ($cpu) { 'extracted_from_WsTreeEnv' } else { 'missing' }
    plc_expansion_units = if ($expansionUnits.Count -gt 0) { 'extracted_from_WsTreeEnv' } elseif ($sidecarExpansionCandidates.Count -gt 0) { 'none_in_tree_but_sidecar_candidates_found' } else { 'none_in_tree_or_not_expanded' }
    ethernet_ip = $ethernetIp.status
    ethercat = $ethercat.status
    motion_axes = if ($motionAxes.Count -gt 0) { 'axis_names_extracted_from_WsTreeEnv' } else { 'missing' }
    axis_parameters = 'missing_ui_export_or_binary_parser_required'
    mnm = if ($mnmInventory.Count -gt 0) { 'fresh_mnm_inventory_extracted' } else { 'not_supplied' }
  }

  $resultPath = Join-Path $OutDir 'project_inventory.json'
  $result = [ordered]@{
    ok = $true
    schema_version = 1
    generated_at = (Get-Date).ToString('o')
    project_path = $projectPathFull
    project_dir = [IO.Path]::GetFullPath($projectDir)
    mnm_dir = if ($MnmDir) { [IO.Path]::GetFullPath($MnmDir) } else { '' }
    asset_status = $assetStatus
    file_inventory = $files
    tree = [ordered]@{
      source = $treePath
      node_count = $treeNodes.Count
      nodes = $treeNodes
    }
    topology = [ordered]@{
      cpu = $cpu
      expansion_units = $expansionUnits
      expansion_unit_sidecar_candidates = $sidecarExpansionCandidates
      ethercat = $ethercat
      ethernet_ip = $ethernetIp
      motion = [ordered]@{
        status = if ($motionAxes.Count -gt 0) { 'tree_summary_extracted' } else { 'not_found' }
        axes = $motionAxes
        missing_for_clone = @('axis control parameters', 'axis group settings', 'point parameters', 'motion common settings')
      }
    }
    data_types = $dataTypes
    program_modules = $programModules
    official_or_library_names_from_tree = $officialNames
    mnm_inventory = $mnmInventory
    sidecar_string_evidence = $sidecarEvidence
    clone_dependency_order = @(
      'create clean project with matching CPU',
      'configure PLC expansion units and start addresses',
      'configure EtherCAT devices and required libraries',
      'configure motion and axis settings',
      'configure EtherNet/IP devices, addresses, IP, and generated variables',
      'allow official/library FBs to be generated by configuration',
      'import filtered user MNM and variable manifests',
      'run Ctrl+F9 conversion and compare exported inventory'
    )
    clone_readiness = [ordered]@{
      ready_for_full_1_to_1_import = $false
      reason = 'inventory extraction is partial; axis parameters, EtherCAT detailed mapping, and EtherNet/IP IP/variable details still need dedicated export/probe evidence'
    }
    result_path = $resultPath
  }

  Write-JsonFile -Path $resultPath -Value $result
  [ordered]@{
    ok = $true
    result_path = $resultPath
    cpu_model = if ($cpu) { $cpu.model } else { $null }
    expansion_unit_count = $expansionUnits.Count
    ethercat_node_count = @($ethercat.nodes).Count
    ethernet_ip_device_count = @($ethernetIp.devices).Count
    motion_axis_count = $motionAxes.Count
    mnm_count = $mnmInventory.Count
    ready_for_full_1_to_1_import = $false
  } | ConvertTo-Json -Depth 4
} catch {
  New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
  $failure = [ordered]@{
    ok = $false
    project_path = $ProjectPath
    mnm_dir = $MnmDir
    out_dir = $OutDir
    error = $_.Exception.ToString()
  }
  $resultPath = Join-Path $OutDir 'project_inventory.json'
  Write-JsonFile -Path $resultPath -Value $failure
  $failure | ConvertTo-Json -Depth 8
  exit 1
}
