# 对 review-d663fa0 的逐条回应

基线：`d663fa0`。本文件随修复提交更新；状态分「已修 / 部分修 / 未修」。

| ID | 结论 | 本批动作 |
| --- | --- | --- |
| R01 | 已修（本批） | `run_kv_execution_plan` 现在：共享 `Local\KeyenceAgent.KvStudio.UI` mutex；只有本次写入的 `exit_code.txt` 才被采信（旧文件先删、按 mtime 校验）；首个失败步骤后停止（`skipped_after_failure`）；runner 必须在 `script_manifest.json` 中登记。 |
| R02 | 已修（本批） | 步骤名→runner/stage 映射显式化（含 `repair_*`）；未知步骤直接拒绝；plan 参数按 runner 参数块校验；`CreatedProjectResultPath` 只传给声明它的 runner；去掉硬编码 `FB_Cylinder`/强制 `SkipGlobal`；无 `import_structures` 的 Main-only 计划可运行；空 stage 选集拒绝。 |
| R03 | 已修 | 空剪贴板重试、节点标签去重；删除前复制整列“节点”标签，保存后重开再复制一次：目标节点的所有标签必须消失，非目标标签逐项不变；Modify 要求整列完全不变。|
| R04 | 已修 | `devices.Count > 1` 与 `Modify/Delete + PreflightOnly` 在 UI 之前直接拒绝；契约测试新增两条反例。 |
| R05 | 已修 | EIP 两个 runner 登记 `ui_guard_required`，全部 `SendWait` 改走 guard 的 `Invoke-KvGuardedSendKeysScoped`（校验 foreground 属于本 KVS 进程，误发到别的窗口会失败）；多 KVS 匹配报 `KV_EIP_PROJECT_AMBIGUOUS`，`ProjectPath` 校验命令行。`rename_kv_axes` 也支持 `-ProjectPath` 并按命令行匹配唯一进程。 |
| R06 | 已修 | 保存后重开回读 + 节点列身份校验（见 R03）：Delete 要求目标节点标签全部消失且非目标不变，Modify 要求节点列不变；`post_ips` 为重开集合，`in_window_ips` 保留窗口内证据。 |
| R07 | 已修 | `Set-StrictMode`；`$failed` 由 cases 计算；`KV_EIP_CONTRACT_SELFTEST=1` 注入故意失败用例，实测 exit=41。 |
| R08 | 已修 | live 测试拒绝外部 KVS（`KV_*_KVS_BUSY`），只清理自己启动的 PID；repo 路径由 `$PSScriptRoot` 解析，KVS 路径支持 `KV_STUDIO_EXE`。 |
| R09 | 已修 | skip 不计 passed；no-summary/stale-result/timeout/missing 均为失败；空 `-Only` 选集 exit 41；`eip-live-cycle` 接入 live 套件；`test_system_layout` 通过新 `tests/system-layout` wrapper 接入 offline 套件。 |
| R10 | 部分修复 | EIP workflow 登记 customer_callable；9 个未分类脚本全部登记；两组同名脚本改为 `*_core.ps1` 并更新引用；layout gate 现在只对 published 非 composed workflow 要求 runner_children。pending/public 分层与 capability 去重仍在。 |
| R11 | 已修 | `setup_keyence_agent.ps1` 与 `install_keyence_dev_links.ps1` 的 skill 清单加入 `kv-eip-nodes`、`windows-ui-automation`。 |
| R12 | 已修（EIP/轴改名） | EIP runner 状态注释、`verification-contract.md` 改为当前路线（节点列选行、整串 IP、树遍历删除、保存后重开）；轴改名文档改为属性对话框路线。统一能力状态索引仍待建。 |

## 既有风险 S01–S07

S 系列在本批一并处理：

- S01 已修：计划声明了 `set_fb_arguments_*` / `verify_module_placement_*` 时，缺少对应 receipt 记为 incomplete（`fb_arguments_receipt_missing` / `placement_receipt_missing`）；无 steps 的计划仍按旧语义保持兼容。
- S02 已修：步骤顺序改为「全部 import/placement → 全部 FB arguments → 全部 variables」，避免在 FB 型别尚未导入时写全局变量。
- S03 已修：`runtime_global_path` 真正传给 `set_variables`，并在计划中暴露 `runtime_global_variables_tsv`、`deferred_axis_variables`。
- S04 已修：只有 scan program（`Name [n]`）才触发“最后一个 program 不能删”，FB 定义可正常替换。
- S05 已修：`GlobalGroupName` 补 `Ctrl+V` 再 `Enter`。
- S06 已修：repair 路径分别以 `Scope global`（带 `AllowGlobalAttributes`）和 `Scope local` 调用 `Get-KvVariableWriteCapabilityErrors`。
- S07 已修：usage 检查先剥离 `(* *)` 块注释、`'...'`/`"..."` 字符串与 `//` 行注释；配置的 MNM 文件缺失记为 `mnm_missing` 并使预检失败。

## 本批验证

- `tests/eip-write-contract`：28 cases，含自测（`KV_EIP_CONTRACT_SELFTEST=1` → exit 41）。
- `tests/run_all.ps1 -Only eip-write-contract`：exit 0；`-Only no-such-suite`：exit 41。
- `tests/eip-live-cycle`：新逻辑（保存后重开回读）实机通过，add/modify/delete 全绿。
- `script-hygiene`、`inventory-expansion`：exit 0。`plan-runner`：新增 6 条反例/绑定用例后 exit 0（未知步骤、未声明参数、repair_*、Main-only、CreatedProjectResultPath 绑定）。

## 需要用户协助

1. **轴 PDO（1203）**：真实工程仍报“PDO 条目未分配给运动功能映射”。自动分配此前未成功，需要一条你们惯用的手工路径（轴设定 → 运动功能映射的具体操作）。
2. **缺失 FB 型别**：`调用轴控FB` 的 1540/1546/709 指向 `MC_MultiParameter*` 等类型在重建工程中不存在；需要确认用 MNM 导入还是从模板复制类型定义（MNM 导入 runner 目前卡在浏览对话框）。

