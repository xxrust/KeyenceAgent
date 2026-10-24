# PLC scaffold 审计复验（codex 意见核对）

审计原文：`docs/plc-scaffold-audit-20260906.md`，与
`C:\Users\Administrator\Downloads\plc-scaffold-audit-20260906.md` 哈希一致（SHA256
`BB01ED07...C519D9`）。复验日期：2026-10-24。复验对象：当前仓库 HEAD `e3896ca` +
本次改动。证据目录：`C:\kvrun\`（`inv_now`、`scaffold_gate`、`cap_final`、
`scan_order_test`、`gates_syntax2`、`gates_guard`）。

## 结论

审计意见**基本正确**。第 1–4 节描述的缺陷在 2026-09-06 已由 `6309f84` /
`d3483ba` / `bdb981a` 修复；用当前代码重跑，这些结论仍然成立。第 5 节列出的
"复刻未完成"缺口有 3 项仍然成立，本次关闭其中 1 项（saved scan-order
verification），并补了可重复的离线测试与文档。

## 逐条判定与证据

| # | 审计说法 | 判定 | 复验证据 |
|---|---|---|---|
| 1 | 清单缺陷：ASCII 过滤漏 22/24 程序；类型匹配漏用户结构；`SV630_1Axis_03713` 造成 26 个假轴 | **正确，已修复** | 当前 `export_kv_project_inventory.ps1` 对样例输出 `program_modules=24`、`mnm_inventory=64`、`data_types=76`、`official_names=63`、`ethercat=32`，与审计的 `inventory_fixed\project_inventory.json` 完全一致；`motion_axis_count=0`，没有假轴 |
| 2 | 旧 gate 接受 7 类被篡改的 scaffold | **正确，已修复** | 当前 `validate_kv_mvp_scaffold.ps1` 重跑 `fixed_gate_tests`：`unchanged` 接受（exit 0），7 个篡改全部 exit 41；6 个报 `KV_SCAFFOLD_MODEL_RENDER_MISMATCH`，`local_type_drift` 报 `KV_VARIABLE_WRITE_CAPABILITY_UNSUPPORTED` |
| 3 | 校验器重渲染并逐字节比较、保留 acceptance、空/null/省略 locals 有显式标记、拒绝非法路径/混合 ST/未支持字段 | **正确** | `capability_tests_final` 重跑：`empty_local`/`null_local`/`omitted_local` 接受；`mixed_body`→`KV_SCAFFOLD_MNM_BODY_AMBIGUOUS`，`reserved_name`→`KV_SCAFFOLD_MODULE_NAME_INVALID`，`retain_field`→`KV_SCAFFOLD_VARIABLE_FIELD_UNSUPPORTED`，`undeclared_type_route`→`KV_SCAFFOLD_DEPENDENCY_ROUTE_UNSUPPORTED` |
| 4 | 变量写入/读回范围只有 name + data_type；device/非默认初值/retain/constant 失败关闭；默认初值只允许新建工程 | **正确** | `Get-KvVariableWriteCapabilityErrors` 探针：name/type → ALLOW；device、initial_value=5、retain=True、constant=True、group_name → REJECT；initial_value=0 仅在 `-AllowDefaultInitialValues` 下 ALLOW，直接写入仍 REJECT |
| 5 | 新工程自带 Main 的替换路线未验证/未修复 | **正确（仍成立）** | `run_kv_mvp_scaffold.ps1` 没有 Main 处理；同名冲突仍由 `KV_MNM_SAME_NAME_IMPORT_REQUIRES_PREDELETE` 前置拒绝，`-DeleteExistingModulesBeforeImport` 只服务 repair 路线 |
| 6 | 编译结果 owner-drawn 行读不到文本（`KV_COMPILE_RESULT_TEXT_UNAVAILABLE`），NG 已能锁定但文本仍为空 | **正确（仍成立）** | `copy_convert_result_from_tree_handle.ps1` 第 333 行仍在 TreeItem 无文本时抛该码；`$conversionFailed` 时只保证错误码为 `KV_COMPILE_RESULT_NG`，没有结果文本或截图 |
| 7 | 8 秒查找预算不是所有同步 UIA 调用的硬上限 | **正确（仍成立）** | 该预算只约束 `copy_convert_result_from_tree_handle.ps1` 的查找循环；同步 `FindAll`/`FromHandle` 没有取消机制 |
| 8 | 完整复刻缺失：global/local 变量与 FB 接口导出、结构体/联合成员定义与创建、官方库依赖安装、完整变量属性写读回、已保存扫描顺序验证 | **部分成立** | 结构体导出/增删改（`export_kv_structure_definitions.ps1`、`mutate_kv_structure_definitions.ps1`）已落地；全局变量、FB 局部变量、FB 自变量快照已有；**普通程序局部变量导出仍缺失**（`assert_kv_snapshot_semantic_coverage.ps1` 明确记录 program locals 未捕获）；官方库依赖安装、完整变量属性、扫描顺序验证见下 |

## 本次修改（关闭第 8 项中的"已保存扫描顺序验证"）

新增 `scripts/workflow_tools/assert_kv_scan_order.ps1`（manifest：
`customer_non_ui_tool` / `published`，capabilities
`verify_saved_scan_order`、`verify_source_target_execution_order`）：

- 输入一：`-ExpectedInventory <源 project_inventory.json>`，比较期望模块的相对顺序；
  加 `-RequireExactNumbers` 再比较执行序号。
- 输入二：`-ScaffoldPath <scaffold.json>`，按 `mnm_files[]` 声明顺序比较；
  `module_type: 0` 才进入扫描顺序，FB 自动排除。
- 输出 `scan_order_verification.json`；失败码：
  `KV_SCAN_ORDER_MODULE_MISSING` / `_MODULE_EXTRA` / `_MISMATCH` /
  `_NUMBER_MISMATCH` / `_DUPLICATE_MODULE`。
- 默认把多出来的模块判失败；`-AllowExtraModules` 允许 extra 但相对顺序仍必须一致。

为什么能离线做：`WsTreeEnv.xml` 的"程序(显示执行顺序)"节点里每个模块都带 `[n]`，
`export_kv_project_inventory.ps1` 早已把 `[n]` 读成 `execution_order`，此前只是没有比较器。

测试：`tests\scan-order\run.bat`（11 例，全部 PASS，含真实 24 模块清单自比较）。
真实审计 scaffold 的 scaffold 模式也已验证：`unchanged` → 期望 2 个扫描模块
（Main、Worker），Reusable 作为 FB 被排除，`ok=true`。

已接入执行计划：new_project / repair 的 plan 在 compile 结果复制后追加
`export_project_inventory.ps1`（读已保存工程树）和
`assert_kv_scan_order.ps1 -ScaffoldPath ... -AllowExtraModules`（比较已保存扫描顺序）；
plan 暴露 `project_inventory_path` 与 `scan_order_result_path`。
`tests\scaffold-variable-attributes` 已断言这两个步骤和参数（11/11）。
已用真实打开的工程手工执行这两步：inventory `ok=true`，匹配的 scaffold 下
`scan_order_verification.json ok=true`。

文档：`references/mvp-runner-contract.md` 已把"尚未证明扫描顺序"改为
"用 assert_kv_scan_order.ps1 比较"，并写明参数、失败码、计划集成与测试位置。

## 2026-10-24 端到端结果

`ScaffoldAttrPlan10`（真实 KV STUDIO，new_project）完整通过：

```
validate_scaffold → create_project → stage_default_program
→ import_mnm_1..3（Main 预删除成功）→ delete_staged_program
→ set_fb_arguments → set_variables → compile_convert → copy_convert_result
→ export_project_inventory → verify_saved_scan_order
```

- `mvp_result.json`: `ok=true`，最后一步 `verify_saved_scan_order`。
- 编译结果：`转换结果 OK / 转换成功。 / 总步数：14/1536000（总指令数: 12）`。
- 扫描顺序：expected `[Main, Worker]`，actual `[Main, Worker]`，`extra=[]`。
- 工程树：`Reusable`（FB）+ `Main [1]` + `Worker [2]`；占位程序与默认 Main 都已清理。
- 证据：`C:\kvrun\scaffold_attr\runs10\ScaffoldAttrPlan10`。

## 仍未关闭（按建议优先级）

1. **完整变量属性写入/读回**：全局变量的 device、initial_value、comment 已由
   `set_kv_variables.ps1 -FullGlobalAttributes` 写入并读回（2026-10-24 实测：
   `DM9002`、INT `789`→`+789`、BOOL `TRUE`、comment 全部在关闭/重开后保留）。
   device 与 initial_value 同时声明会被 `KV_VARIABLE_DEVICE_INITIAL_VALUE_CONFLICT`
   拒绝（KV STUDIO 对已绑定设备的变量不保留初值）。scaffold 已接入：
   renderer 生成 `scaffold.json variables.attributes=full`，validator 按该模式放行
   并在 `variable_write_verified_fields` 中报告，execution plan 自动给每个
   `set_variables` 步骤加 `-FullGlobalAttributes`；`tests\scaffold-variable-attributes`
   9/9 通过，且 scaffold 产出的 merged TSV 已在真实工程上跑通
   （`R_Flag/R100`、`Init_Flag/TRUE`、`Note_Flag/comment` 均回读保留）。
   仍缺：retain/constant/group_name 与局部变量属性。
2. ~~**官方库依赖安装**~~：**2026-10-24 已澄清并关闭**。36 个官方/库 FB 是
   Universal Library 的机型固有 FB，不是独立安装包：新建工程无
   `功能块 > UniversalLibrary`；配置 `SV630_1Axis_03713` 节点后出现
   `Motor > Inovance_SV630N_V100` 的 8 个 `MC_*` FB；`QA_BlankProject`
   的 SV630N + YAKO 节点对应两套库。依赖顺序：装 `.ecsup`/ESI → 配 EtherCAT 节点
   → 再导入用户 MNM。新增
   `workflow_tools/assert_kv_library_dependencies.ps1` 做前置断言
   （`KV_LIBRARY_TREE_MISSING` / `_VENDOR_MISSING` / `_FB_MISSING`），
   `tests\library-dependencies` 7/7 通过；细节见
   `references/library-dependencies.md`。系统库（SystemFB/DataUtilization）仍不在覆盖内。
3. ~~**普通程序局部变量导出**~~：**2026-10-24 已关闭**。
   `export_kv_project_text_snapshot.ps1` 现在把普通程序模块加入同一个局部变量
   快照会话（`-SnapshotModules` 逗号连接；`-SkipProgramLocals` 可退回旧行为）。
   样例实测：`discovered_program_local_modules=24`，24/24 都有 local 快照，
   `text\variables` 共 28 个 local raw（24 程序 + 4 FB），24 个 program entity
   全部 `locals=complete`，快照 `status=ready`、`semantic=complete`、`missing=[]`，
   总耗时 8.5 分钟。证据：`C:\kvrun\snapshot_sample\out2\snapshot_20261024_091005`。
   `13_project_text_snapshot\run.ps1` 也加了后置断言，防止以后回退。
4. ~~**新工程 Main 替换**~~：**2026-10-24 路线已打通**。KV STUDIO 拒绝删除最后一个
   程序（"不能删除。项目必须登录 1 个以上的程序。"），所以删除式替换必须先让工程有
   2 个程序。实测序列（`MainReplaceTest`）：导入 `MainStage` 占位 → 带
   `-DeleteExistingModuleBeforeImport` 导入 `Main`（删除确认对话框用 `BM_CLICK IDOK`
   对象级确认）→ `-DeleteOnly -ExpectedModuleName MainStage`。保存后树里只有
   `Main [1]`，转换结果对话框为 `转换成功。`（0 错误，4 步）。
   runner 还加了 `Main [1]` 数字后缀查找、树焦点+选中证明、以及
   `KV_MNM_DELETE_LAST_PROGRAM_FORBIDDEN` 快速失败。已自动化进 execution plan：
   `stage_default_program`（生成并导入 `KV_Stage_Temp`）→ 正常导入（Main 带预删除）
   → `delete_staged_program`；scaffold 不含 Main 时改为 `delete_default_program`。
   `tests\scaffold-variable-attributes` 13/13 断言这两个步骤与生成的 MNM。
   2026-10-24 真机全流程（`ScaffoldAttrPlan7`）：validate → create → stage →
   3 个模块导入（Main 预删除成功）→ 删除占位 → FB 自变量 → 变量写入，全部走通；
   期间修掉两个真实回归：execution plan 未把 UI guard/agent boundary 两门禁放前两位
   （`KV_PLAN_REQUIRED_GATE_ORDER`），以及 Ctrl+N 创建的 KVS 命令行不含工程路径导致
   import/compile/copy 绑定失败（现统一用 `-CreatedProjectResultPath`）。
   变量 reopen 复制失败已定位并修复：焦点未证明落在 `_grid` 时 Ctrl+C 会触发 KV 的
   “向剪贴板复制失败。”；现在 Alt+L/Shift+Tab 最多 3 次并校验焦点祖先含 `_grid`，
   启动时还检查遗留模态框。修复后同一工程连续 3 次写入+重开回读全部 ok。
5. **编译结果文本/截图**：**成功与 NG 都已实测可回读**。成功：
   `转换结果 OK / 转换成功。 / 总步数 14`；NG（未注册变量）：
   `转换结果 NG (错误数量:1  警告数量:1)` + `NgProbe(行:00001)[错误214]…[UndefinedTag]`。
   子结果 `message` 现在直接带 NG 行并标记 `text_available=true`；
   flat workflow 结果也带 `error_code=KV_COMPILE_RESULT_NG` 与 `child_message=…`。
   若 owner-drawn 行确实读不到，子结果报 `text_available=false` 并指向
   编译步骤截图与 fail.txt，不再出现空 message。
6. **同步 UIA 硬超时**：plan 给 `copy_convert_result` 显式 `timeout_seconds=120`，
   `compile_convert` 300、每个 `import_mnm_*` 240、`set_variables_*` 600；
   由 flat executor 在预算到点时杀进程树，作为硬兜底。
   子进程内的 8 秒查找预算仍只是协作式检查（单个阻塞的 COM/UIA 调用无法在进程内取消），
   这一点如实保留。
