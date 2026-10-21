param(
    [Parameter(Mandatory = $true)][string]$ProjectPath,
    [Parameter(Mandatory = $true)][string]$OutDir
)
# 离线单元配置快照：解析 WsTreeEnv.xml（工程树状态）→ 单元 / EtherCAT 从站 / 轴 清单
# 不启动 KVS ✓ 不碰 UI ✓ 可重复 ✓
$ErrorActionPreference = 'Stop'
$null = New-Item -ItemType Directory -Force -Path $OutDir
function W([string]$m) { Write-Output ((Get-Date).ToString('HH:mm:ss.fff') + '  ' + $m) }

$projectDir = Split-Path -Parent ([IO.Path]::GetFullPath($ProjectPath))
$xmlPath = Join-Path $projectDir 'WsTreeEnv.xml'
W ('project dir = ' + $projectDir)
if (-not (Test-Path -LiteralPath $xmlPath -PathType Leaf)) { throw ('KV_UNIT_SNAPSHOT_NO_TREE_XML: ' + $xmlPath) }
W ('tree xml = ' + $xmlPath + '  ' + (Get-Item $xmlPath).Length + ' B')

[xml]$doc = Get-Content -Raw -LiteralPath $xmlPath -Encoding UTF8
$rows = New-Object System.Collections.ArrayList

function Walk([System.Xml.XmlNode]$node, [int]$depth, [string]$parentPath) {
    if ($null -eq $node) { return }
    foreach ($child in @($node.SelectNodes('Child'))) {
        $name = ''
        $vf = $child.SelectSingleNode('value.first')
        if ($vf) { $name = [string]$vf.InnerText }
        $vs = $child.SelectSingleNode('value.second')
        $expanded = ''
        if ($vs) {
            $ex = $vs.SelectSingleNode('Expanded')
            if ($ex) { $expanded = [string]$ex.InnerText }
        }
        if ($name -and $name.Trim()) {
            $path = if ($parentPath) { $parentPath + ' / ' + $name } else { $name }
            [void]$rows.Add([pscustomobject]@{ depth = $depth; name = $name.Trim(); expanded = $expanded; path = $path })
            if ($vs) { Walk $vs ($depth + 1) $path }
        } elseif ($vs) {
            Walk $vs $depth $parentPath
        }
    }
}

$root = $doc.SelectSingleNode('/Root')
if (-not $root) { throw 'KV_UNIT_SNAPSHOT_BAD_XML' }
Walk $root 0 ''
W ('tree rows = ' + $rows.Count)

$rows | Export-Csv -LiteralPath (Join-Path $OutDir 'unit_tree.tsv') -Delimiter "`t" -NoTypeInformation -Encoding UTF8

# 轴清单：名字形如 轴N:名称
$axes = @($rows | Where-Object { $_.name -match '^轴\d+\s*[:：]' } | ForEach-Object {
        $no = 0
        if ($_.name -match '^轴(\d+)') { $no = [int]$Matches[1] }
        [pscustomobject]@{ axis_no = $no; axis_label = $_.name; path = $_.path }
    } | Sort-Object axis_no)
$axes | Export-Csv -LiteralPath (Join-Path $OutDir 'axis_list.tsv') -Delimiter "`t" -NoTypeInformation -Encoding UTF8

# EtherCAT 从站：名字形如 [N] 型号...（在 EtherCAT 节点下）
$ecParent = @($rows | Where-Object { $_.name -eq 'EtherCAT' } | Select-Object -First 1)
$slaves = @()
if ($ecParent) {
    $slaves = @($rows | Where-Object { $_.path.StartsWith($ecParent.path + ' / ') -and $_.name -match '^\[\d+\]' } | ForEach-Object {
            $addr = 0
            if ($_.name -match '^\[(\d+)\]') { $addr = [int]$Matches[1] }
            [pscustomobject]@{ node_address = $addr; name = $_.name; path = $_.path }
        } | Sort-Object node_address)
}
$slaves | Export-Csv -LiteralPath (Join-Path $OutDir 'ethercat_slaves.tsv') -Delimiter "`t" -NoTypeInformation -Encoding UTF8

# 顶层单元（单元配置 的直接子节点）
$unitParent = @($rows | Where-Object { $_.name -eq '单元配置' } | Select-Object -First 1)
$units = @()
if ($unitParent) {
    $units = @($rows | Where-Object {
            $_.path.StartsWith($unitParent.path + ' / ') -and
            ($_.path.Substring($unitParent.path.Length + 3) -notmatch ' / ')
        } | ForEach-Object { [pscustomobject]@{ unit = $_.name; path = $_.path } })
}
$units | Export-Csv -LiteralPath (Join-Path $OutDir 'units.tsv') -Delimiter "`t" -NoTypeInformation -Encoding UTF8

$result = [ordered]@{
    ok           = $true
    project_path = $ProjectPath
    tree_xml     = $xmlPath
    tree_rows    = $rows.Count
    unit_count   = $units.Count
    slave_count  = $slaves.Count
    axis_count   = $axes.Count
    outputs      = [ordered]@{
        unit_tree        = (Join-Path $OutDir 'unit_tree.tsv')
        units            = (Join-Path $OutDir 'units.tsv')
        ethercat_slaves  = (Join-Path $OutDir 'ethercat_slaves.tsv')
        axis_list        = (Join-Path $OutDir 'axis_list.tsv')
    }
    axes         = $axes
    slaves       = $slaves
    units        = $units
}
$result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $OutDir 'unit_snapshot_result.json') -Encoding UTF8

W ('units=' + $units.Count + '  slaves=' + $slaves.Count + '  axes=' + $axes.Count)
$slaves | ForEach-Object { W ('  slave [' + $_.node_address + '] ' + $_.name) }
$axes | Select-Object -First 6 | ForEach-Object { W ('  axis ' + $_.axis_no + '  ' + $_.axis_label) }
W 'done'
exit 0
