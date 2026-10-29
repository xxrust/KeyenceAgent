# EtherCAT configuration read-back

`workflows/export_kv_ethercat_configuration.ps1` opens `EtherCAT设定` read-only,
selects `设备设定`, walks every slave with the keyboard and records the
`节点设定` property grid through UI Automation `ValuePattern`.

## What is captured

- Master settings: 通信周期, PDO 通信连续超时检测次数, 启动等待时间, 自动开始 PDO 通信
- Per slave: 节点地址, 产品名称, 供应商名称, 供应商 ID, 产品代码, 版本, 端口类型,
  详细设定, 刷新时机, Explicit Device ID / 检查, 预留

The dialog is cancelled afterwards; the project is never saved by this route.

## Evidence

Live run against `references/KVX样例程序_v100` (2026-10-29):

- `C:\kvrun\ec_read2\ethercat_configuration.json` — 32 nodes, `ok=true`
- `C:\kvrun\ec_wf2\ethercat_configuration_result.json` — workflow-level result
- Full snapshot run `tests/kv-interface-regression/runs/13_project_text_snapshot_20261029_194820_384_c58d10a0`:
  `workflow_status.ethercat_configuration = completed`,
  `project/配置/EtherCAT/devices.json` exists, `entity.json.status.devices = complete`,
  `配置/单元/configuration.json.asset_status.ethercat = ui_read_complete`

## Known limits

- PDO mapping and device-specific parameters (`详细设定` sub-dialog) are not captured yet.
- The route must run while KV STUDIO has the project open; it needs the guarded UI session.
- This is a read-only probe: no OK/save is sent, the EtherCAT dialog is cancelled.
