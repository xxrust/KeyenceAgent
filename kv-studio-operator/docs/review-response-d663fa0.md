# 对 review-d663fa0 的逐条回应

基线：`d663fa0`。本文件随修复提交更新；状态分「已修 / 部分修 / 未修」。

| ID | 结论 | 本批动作 |
| --- | --- | --- |
| R01 | 已修（本批） | `run_kv_execution_plan` 现在：共享 `Local\KeyenceAgent.KvStudio.UI` mutex；只有本次写入的 `exit_code.txt` 才被采信（旧文件先删、按 mtime 校验）；首个失败步骤后停止（`skipped_after_failure`）；runner 必须在 `script_manifest.json` 中登记。 |
| R02 | 已修（本批） | 步骤名→runner/stage 映射显式化（含 `repair_*`）；未知步骤直接拒绝；plan 参数按 runner 参数块校验；`CreatedProjectResultPath` 只传给声明它的 runner；去掉硬编码 `FB_Cylinder`/强制 `SkipGlobal`；无 `import_structures` 的 Main-only 计划可运行；空 stage 选集拒绝。 |
| R03 | 部分修复 | 空剪贴板重试一次后跳过；同一节点标签去重，不再把采样次数当序号；仍缺“删除前核对当前树节点身份”。 |
| R04 | 已修 | `devices.Count > 1` 与 `Modify/Delete + PreflightOnly` 在 UI 之前直接拒绝；契约测试新增两条反例。 |
| R05 | 部分修复 | 本批未统一 guard 绑定；EIP/axis 测试已改为“只操作自己启动的 KVS”。runner 的工程身份绑定留待下一批。 |
| R06 | 部分修复 | 增加**保存后重开**回读：`post_ips` 改为重开后的集合，`in_window_ips` 保留窗口内证据；仍缺 node→IP 全映射，目标 IP 原本已被占用时判据不足。 |
| R07 | 已修 | `Set-StrictMode`；`$failed` 由 cases 计算；`KV_EIP_CONTRACT_SELFTEST=1` 注入故意失败用例，实测 exit=41。 |
| R08 | 已修 | live 测试拒绝外部 KVS（`KV_*_KVS_BUSY`），只清理自己启动的 PID；repo 路径由 `$PSScriptRoot` 解析，KVS 路径支持 `KV_STUDIO_EXE`。 |
| R09 | 已修 | skip 不计 passed；no-summary/stale-result/timeout/missing 均为失败；空 `-Only` 选集 exit 41；`eip-live-cycle` 接入 live 套件。 |
| R10 | 部分修复 | `configure_kv_eip_devices.ps1` 登记为 customer_callable（capability `ethernet_ip_device_crud`）；同名脚本/重复 capability/未分类脚本仍在。 |
| R11 | 已修 | `setup_keyence_agent.ps1` 与 `install_keyence_dev_links.ps1` 的 skill 清单加入 `kv-eip-nodes`、`windows-ui-automation`。 |
| R12 | 已修（EIP/轴改名） | EIP runner 状态注释、`verification-contract.md` 改为当前路线（节点列选行、整串 IP、树遍历删除、保存后重开）；轴改名文档改为属性对话框路线。统一能力状态索引仍待建。 |

## 既有风险 S01–S07

均属本批之前的实现，未在本批声称修复；作为独立 backlog 处理：

- S01 completion receipt 缺省即 complete
- S02 交错 import/args/variables
- S03 轴型别 defer 产物未接线
- S04 最后一个 program 保护未区分实体类型
- S05 GlobalGroupName 只设剪贴板未粘贴
- S06 FullGlobalAttributes repair 缺 scope
- S07 variable usage 词法边界

## 本批验证

- `tests/eip-write-contract`：28 cases，含自测（`KV_EIP_CONTRACT_SELFTEST=1` → exit 41）。
- `tests/run_all.ps1 -Only eip-write-contract`：exit 0；`-Only no-such-suite`：exit 41。
- `tests/eip-live-cycle`：新逻辑（保存后重开回读）实机通过，add/modify/delete 全绿。
- `script-hygiene`、`inventory-expansion`：exit 0。`plan-runner`：新增 6 条反例/绑定用例后 exit 0（未知步骤、未声明参数、repair_*、Main-only、CreatedProjectResultPath 绑定）。

## 需要用户协助

1. **轴 PDO（1203）**：真实工程仍报“PDO 条目未分配给运动功能映射”。自动分配此前未成功，需要一条你们惯用的手工路径（轴设定 → 运动功能映射的具体操作）。
2. **缺失 FB 型别**：`调用轴控FB` 的 1540/1546/709 指向 `MC_MultiParameter*` 等类型在重建工程中不存在；需要确认用 MNM 导入还是从模板复制类型定义（MNM 导入 runner 目前卡在浏览对话框）。

