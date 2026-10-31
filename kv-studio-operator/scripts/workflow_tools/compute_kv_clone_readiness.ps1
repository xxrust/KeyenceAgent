param(
  [Parameter(Mandatory=$true)]$Inventory
)
# Computes clone readiness from structured statuses; narrative text is generated,
# never hand-written. A gap may only be emitted when its own status/evidence says
# so (e.g. expansion units can only be a gap when the topology actually has some).
$status = $Inventory.asset_status
$gaps = @()
function Add-Gap([string]$Id, [string]$Text) { $script:gaps += [pscustomobject]@{ id = $Id; text = $Text } }
if ([string]$status.program_fb -ne 'complete') { Add-Gap 'program_fb' '程序/FB 未成功采集' }
if ([string]$status.variables -ne 'complete') { Add-Gap 'variables' '变量未成功采集' }
if ([string]$status.data_types -ne 'complete') { Add-Gap 'data_types' '数据类型未成功采集' }
if ([string]$status.ethercat_pdo -ne 'ui_read_complete') { Add-Gap 'ethercat_pdo' 'EtherCAT PDO 映射未完整采集' }
if ([string]$status.ethercat_device_parameters -ne 'structured') { Add-Gap 'ethercat_device_parameters' 'EtherCAT per-device parameters 仅截图，无结构化键值' }
if ([string]$status.ethernet_ip -ne 'ui_read_complete') { Add-Gap 'ethernet_ip' 'EtherNet/IP 设备/连接未完整采集' }
if ([string]$status.eip_connection -ne 'ui_read_complete') { Add-Gap 'eip_connection' 'EtherNet/IP 软元件分配未完整采集' }
if ([string]$status.motion_axes -ne 'ui_dump_complete') { Add-Gap 'motion_axes' '运动轴未采集' }
if ([string]$status.axis_parameters -ne 'ui_dump_complete') { Add-Gap 'axis_parameters' '轴控制参数未采集' }
if ([string]$status.motion_axis_groups -ne 'ui_dump_complete') { Add-Gap 'motion_axis_groups' '轴组设定未采集' }
if ([string]$status.motion_point_parameters -ne 'ui_dump_complete') { Add-Gap 'motion_point_parameters' '点参数未采集' }
if ([string]$status.motion_common_settings -ne 'ui_dump_complete') { Add-Gap 'motion_common_settings' '运动通用设定未采集' }
$expansionUnits = @($Inventory.topology.expansion_units)
if ($expansionUnits.Count -gt 0 -and [string]$status.plc_expansion_units -notin @('captured', 'ui_read_complete', 'extracted_from_WsTreeEnv')) {
  Add-Gap 'plc_expansion_units' ("CPU 扩展单元已存在但未采集 (" + $expansionUnits.Count + " 个)")
}
$manualGaps = @($gaps | Where-Object { $_.id -ne 'ethercat_device_parameters' })
$ready = ($gaps.Count -eq 0)
$manualReady = ($manualGaps.Count -eq 0)
$captured = '程序/FB/变量/类型/注释/EIP/轴参数/运动点参数/运动通用设定/EtherCAT PDO'
$reason = if ($ready) { "全部结构化资产已采集；$captured" } else { ("未完成：" + (($gaps | ForEach-Object { $_.text }) -join '；') + "；已采集：$captured") }
[pscustomobject]@{
  ready_for_full_1_to_1_import = $ready
  ready_for_manual_1_to_1_rebuild = $manualReady
  blocking_gaps = @($gaps)
  reason = $reason
}
