# Nano 域脚本与标号增删改查

```bat
run.bat -NoPause -OutRoot C:\kvrun\nano_area_labels_acceptance
```

输出目录必须不存在。默认新建空白 KV-NC32 工程，回读 Main 为空后，写入交通灯框脚本、七条输出回路及一条域脚本。只使用这个工程；finally 保存关闭，失败时只清理本次拥有的进程。工程保留在 `<out>/projects/NanoAreaLabels/NanoAreaLabels.kpr`。支持 `-KvsExe`、`-PlanOnly`；计划生成不算真实桌面验收。

域脚本覆盖新增、全文读取、覆盖修改、删除语句、旧源码不符拒绝、删除整条回路、删除后重新新增。修改后、删除后、最终状态分别保存关闭重开并回读，最终逐项核对框脚本和全部七条原有输出回路。

折叠后的空行也计入 Row。当前域脚本在第 2 行，其后第 3 行为空行，七条输出回路位于第 4～10 行；最终验收同时核对该空行和七条回路。早期 C 轮错误地从第 3 行核对输出，返回空内容而被拦截；同一工程导出及第 4～10 行逐项读取确认程序没有丢失，证据保留于 `C:/kvrun/nano_area_labels_20261117/final_diagnose_export`、`final_row_4` 至 `final_row_10`。该轮结果保持失败，不改写为通过。

全局和 Main 局部标号分别从空表新增，再追加保留行，直接覆盖第一行的名称、数据格式、设备（全局）及中文注释。核对整表，拒绝旧表不符；重开回读两张表。域脚本真实引用全局与局部标号并编译，删除标号前恢复软元件源码。直接删除首行并核对保留行，删除最后一行回到空表，重开核对删除持久化。

全局覆盖测试使用 `DM14` 的 2 字有符号整数，保留行使用 `DM20`，避免地址范围重叠。早期夹具将保留行设为 `DM15`，与 `DM14～DM15` 重叠，真实回读拦住了 KV STUDIO 清空目标分配的变化；该失败记录保留在 `C:/kvrun/nano_area_labels_bat_20261117_a/test_result.json`，其 finally 已正常关闭进程。

表格读取复用已提交 `export_nano_labels_guarded.ps1` 的 Ctrl+Home / Ctrl+Shift+End / Ctrl+C 路线（68a5e7a、6048e57、5a32578），通过正式 workflow 的共享守卫执行；不把所有复制失败吞成空表。只确认 Main 局部作用域，选中的程序与 ProgramName 不符时停止。

读取按原导出脚本的节奏分步定位、选择、复制。粘贴前核对剪贴板全文，复制和粘贴使用共享守卫的物理 Ctrl 组合键，写后离开单元格再读回整表。早期 D 轮覆盖中出现首列被清空，整表比较返回 `KV_NANO_LABEL_WRITE_READBACK_MISMATCH` 并停止，未被当作成功；输入方式修正后，在同一工程连续 8 次交替覆盖及编译通过，回执位于 `C:/kvrun/nano_area_labels_20261117/labels_physical2/overwrite_1` 至 `overwrite_8`，其 `99_close` 正常退出。此单步证据不替代完整 BAT 结果。

每个写操作必须转换成功、保存，并按完整旧表/旧源码核对。查看 `test_result.json`、各步骤 `workflow_result.json`、`artifacts/operation/nano_operation_result.json`、`labels_raw.tsv`、`source_readback.txt` 与转换结果。预期拒绝的 workflow 本身必须失败。BAT 返回 0 表示通过，41 表示验收失败。

知识库：`pdf::ScriptUse::chunk-023#p1`（域脚本建立/重编辑/删除），`pdf::ScriptUse::chunk-029#p2`（局部标号），`pdf::KVSUSE_KVS11::chunk-078`（全局/局部表及数据格式）。范围是编辑、编译、保存重开；未连接 PLC。KV-X 在输入前拒绝，保持原路线。

2026-11-17 真实验收通过：`C:/kvrun/nano_area_labels_bat_20261117_e/test_result.json`，`ok=true`、59 项检查。KV-NC32，KV STUDIO 文件版本 12.41.0.0；最终转换成功，149 步 / 116 指令（引用标号时 150 步 / 116 指令）。最终逐项回读空表、域脚本、空行、交通灯框脚本及七条输出回路；`99_close` 正常保存关闭，前后进程和泄漏列表均为空。工程保留在 `C:/kvrun/nano_area_labels_bat_20261117_e/projects/NanoAreaLabels/NanoAreaLabels.kpr`。
