# Nano 脚本、普通梯形图和标号接口

公开入口：`scripts/workflows/manage_kv_nano_program.ps1`。接口通过 manifest 生成 flat execution plan，使用共享 UI mutex、输入指纹、守卫和步骤回执。

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File scripts/workflows/manage_kv_nano_program.ps1 `
  -ProjectPath C:\work\Traffic\Traffic.kpr -OutDir C:\work\read_phase `
  -Action ReadScript -ProgramName Main -Row 1
```

| 参数 / 动作 | 契约 |
|---|---|
| ProjectPath / ProgramName | 完整工程路径、精确的每次扫描模块名；拒绝同一路径多进程歧义 |
| Row | 从 1 开始的折叠后梯形图回路行号，空行也计数；每次操作先折叠转换梯形图。不是转换后的指令编号。域脚本后的空行须按实际回读保留计数 |
| CreateScript | 在 Row **插入完整新回路**，第 5 列建立脚本，第 1 列执行条件默认 CR2002，补齐第 2～4 列连接线；已有回路向下移动 |
| ReadScript | 打开独立“ST/脚本编辑窗口”，复制全部源文，返回 source；可用 ExpectedSourcePath 断言内容 |
| UpdateScript | 必须给 SourcePath、ExpectedSourcePath；先读取旧源码，逐字比较后替换，再回读应用结果 |
| DeleteScript | 必须给 ExpectedSourcePath；匹配后删除框和整个回路，后续回路上移 |
| CreateAreaScript / ReadAreaScript / UpdateAreaScript / DeleteAreaScript | 域脚本占完整回路，从第 1 列打开独立文本窗；新增先插入完整空行，更新/删除先比较 ExpectedSourcePath。域脚本每次扫描执行，无框脚本条件接点 |
| ReadLabels | 读取 LabelScope=Global 或 Local 的完整四列表格；Local 必须实际选中 ProgramName，当前实测 Main，程序不符即停止 |
| WriteLabels | SourcePath 为多行四列无表头 TSV，一次粘贴整个块；Row 是首行号。可在末行后追加，或覆盖对应数量的既有行，不隐式删除块外行；ExpectedSourcePath 必须是操作前完整旧表，空表用零字节文件。所有行写后与完整预期表比较 |
| DeleteLabel | 以 ExpectedSourcePath 比较完整旧表后，选中 Row 的四个单元格直接 Delete；只确认精确“是否删除？”弹窗，回读整表并核对其他行 |
| InsertLadder | 在 Row 前插入 SourcePath 中的普通助记符回路，可一次插入多个回路 |
| ReadLadder | 通过“编辑列表”只读选中回路，返回 source；可用 ExpectedSourcePath 断言 |
| UpdateLadder / DeleteLadder | 必须提供完整旧回路 ExpectedSourcePath；匹配后替换 / 删除选中回路 |
| Save / Close / Reopen | 保存；保存后关闭并确认原进程退出；或关闭后重开同一工程并返回新 PID / HWND |
| CreatedProjectResultPath | 使用 create_project 返回的创建回执绑定首次无项目命令行的进程。首次写入会先关闭重开，建立完整路径绑定；后续调用不再传旧回执 |
| ChecklistPath | 写操作编译阶段使用的检查清单 |
| PlanOnly | 只生成计划和预检证据，不操作桌面 |

源文件必须是非空 UTF-8 文本。脚本比较只归一化 CRLF/LF 和末尾换行，保留其余空格及大小写。梯形图比较额外归一化软元件地址的前导零（KV STUDIO 会将 `MR10` 显示为 `MR010`），结果文件仍保留实际回读。普通梯形图接口不接收 BOX_ST、BOX_SCRIPT、END、MNM 头或 `;` 脚本内容；脚本使用独立窗口路线。更新和删除旧源码不符时返回 `KV_NANO_EXPECTED_SOURCE_MISMATCH`，不执行目标修改。

标号 TSV 四列为名称、数据格式、软元件/常数（局部为常数，可空）、标号注释。使用 KV STUDIO 的数据格式文字，如 `位`、`1 字无符号整数`、`2 字有符号整数`。写入名接受 ASCII 字母/下划线或常用汉字起头，后续可含数字；按 ASCII 1、汉字 2 计宽，总宽不超过 32。中文标号及中文注释已真实验证，见 [中文交通灯示例](../examples/nano-traffic-labels/README.md)。表格仅归一化换行及完全空白行，其余内容逐字比较。表格读取复用已提交 `export_nano_labels_guarded.ps1` 的全选复制路线（68a5e7a、6048e57、5a32578），现在通过正式 workflow 守卫执行并检查复制哨兵；不会把读取失败当作空表。删除声明前先移除脚本引用，避免产生未登录标号编译错误。

每次写操作都执行转换、复制完整编译结果并保存，任何阶段失败则整个 workflow 失败；成功编译不能替代保存重开验证。批量编辑后调用 Reopen，再按预期源码逐项读取。Delete 不伪造源码回读，调用者通过后续回路的准确内容与位置验证删除结果。

完整工程修改使用 `scripts/workflows/apply_kv_nano_program_plan.ps1 -ProjectPath ... -ContractPath program.json -OutDir ...`。契约指定完整标号 TSV、旧标号表、脚本修改及旧源码、最终梯形图逐行预期；所有文件在写入前准备。该接口一次生成 flat plan，冻结契约和所有输入 SHA256，整块写标号、写源码、编译、保存重开、逐项读取并关闭。输入文件变化或回读不符即失败；`PlanOnly` 只证明规划，不证明工程一致。普通 `manage_kv_nano_program` 的单步回执不能替代整个工程的验收。

标号优先，注释仅补充名称之外的信息。完全重复名称的注释在写入前拒绝；无需补充时保留空的第四列。禁止给有系统注释的软元件登记标号，禁止修改或清空系统注释。当前输入检查保护 CR/CM 整区，其他有系统注释的地址须按目标 CPU 和工程证据排除。此保护适用于标号写入和设备注释导入；读取允许包含系统点。不要通过尝试粘贴系统地址来判断能否使用。

KV STUDIO 覆盖粘贴会忽略空字段。目标空字段需清空旧值时，接口先核对完整旧表并检查所有旧行均不含受保护系统点，再选中整块四列、核对精确“选择范围是否删除？”确认框、清除并一次粘贴完整目标表。回读仍逐字比较所有行；回执 `rebuilt_table_for_empty_fields` 标记该分支，`paste_count=1`，`pasted_row_count` 为本次整块行数。

完整计划 BAT 见 [中文交通灯示例](../examples/nano-traffic-labels/README.md)。空项目实测证据：`C:/kvrun/nano_batch_plan_20261117/blank_b/test_result.json`，14 行一次粘贴、完整计划 21 步、152 步 / 116 指令，保存重开后整表、两段脚本与七条回路一致并正常关闭。

旧表清空重复注释的实测证据：`C:/kvrun/nano_batch_plan_20261117/overwrite_c/test_result.json`，整表重建后 14 行一次粘贴，完整计划 19 步通过，保存重开全部预期一致；源工程未变、副本 `.cm1/.cm2` 哈希不变，测试进程正常关闭。

本接口在 UI 输入前验证 Nano CPU。KV-X 不走此路径。源码全选仅发生在已验证的脚本文本窗；不会在梯形图里使用 Ctrl+Home / Ctrl+Shift+End 全选或导入脚本。

结果：`workflow_result.json` 和 `artifacts/operation/nano_operation_result.json`；后者含 action、project_path、program、row、before_source、source 和 session。写操作另有 `artifacts/compile_result/compile_result_copied.txt`，每步均有当次 `step_receipt.json`。普通 Read 会临时设置窗口编辑方式，但不改目标源码；调用 Save 可保存编辑器设置。

可运行验收：[空白 Nano 交通灯 BAT](../tests/kv-interface-regression/25_nano_traffic_crud/README.md)。测试默认清理自己打开的进程；普通接口的生命周期由调用者显式调用 Close 管理，防止关闭调用者仍要使用的项目。

扩展验收：[域脚本与标号 BAT](../tests/kv-interface-regression/26_nano_area_labels_crud/README.md)。2026-11-17，KV-NC32 / KV STUDIO 12.41.0.0，空项目真实运行 59 项通过，最终转换为 149 步 / 116 指令。覆盖域脚本增删改查、全局/Main 局部标号追加/覆盖/直接删除、旧表不符拒绝、脚本引用标号、保存重开及七条输出回路完整性；finally 正常关闭，前后 Kvs 进程均为空。结果：`C:/kvrun/nano_area_labels_bat_20261117_e/test_result.json`。未连接 PLC，不作为运行时交通时序验证。

2026-11-17 另行真实验证共享创建接口仍可创建 KV-X520 空工程；随后对该工程调用本接口 ReadScript，返回 `KV_NANO_CPU_REQUIRED`，日志仅初始化 guard，未开始 UI 输入会话。按创建回执复核 PID、启动时间与可执行文件后清理该已保存的空白测试进程，最终 Kvs 进程快照为空。证据：`C:/kvrun/nano_traffic_api_20261117/kvx_compat/kvx_rejection_result.json`。本项证明创建兼容性与 Nano 路径拒绝行为，不扩展 KV-X 的编辑验收范围。
