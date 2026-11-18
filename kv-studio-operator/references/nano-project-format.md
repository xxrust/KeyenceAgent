# KV Nano 适配状态与工程证据

本页记录当前结论；此前按尝试顺序追加的记录已被本页取代。不能把旧 runner 的 `ok=true` 当作保存、回读或编译证据。

样本为用户提供的 `纯48/纯48.kpr`，原件不修改。2026-11-17 在独立副本上，实际窗口为
`KV STUDIO - [编辑器: KV-NC32] - [纯48]`，工程树 CPU 节点为 `[0] KV-NC32 R000/R500`。
本机实际接手工程的程序路径为 `H:/Keyence/KVS11/KVS/Kvs.exe`，其文件版本为 `12.41.0.0`。
安装目录名不能证明运行版本；默认 KVS12 启动器可能转交给另一进程。

## 工程与文本格式

此样本有 9 个 `.mod`、`UnitSet.ue2`、`CpuMb2.inf`、`.lbl`、`.cm1/.cm2`，没有 `WsTreeEnv.xml`。
`.mod` 文件名只能证明目录里有这些文件，不能证明 CPU 型号、模块类别或扫描顺序。
实际工程树顺序为 Main、正向移动、反向移动、测试、往复测试、增量移动、IO测试、正常运行、采图；按文件名排序会改变顺序。

实际 MNM 头为 `DEVICE:128`、`;MODULE:`、`;MODULE_TYPE:0`、`;SCRIPT_TYPE:`。
**本机导出的无 BOM 文本是 Windows-936（GBK），不是 UTF-8。**
例如 Main 的第 66 字节起出现不能按严格 UTF-8 解码的字节；按 936 解码可还原中文标号和行注释。
旧 `export_try2/mnm/Main.mnm` 与本次导出都如此，旧文档的 UTF-8 结论错误。
通用读取器 `workflow_tools/kv_mnm_text.ps1` 按 BOM 识别 Unicode；无 BOM 时使用系统 ANSI 代码页。
无 BOM UTF-8 输入须显式指定 `-NoBomEncoding Utf8`，不能通过“恰好能解码”猜编码。

元数据只能从文件头剥离；不要把 `;SCRIPT_TYPE:` 粘进编辑列表。
程序里的分号行不能统一删除：其中可能含行注释或脚本内容。

## 正式入口与当前验收

| 能力 | 当前结论 |
| --- | --- |
| MNM 导出 | 复用既有 `workflows/export_kv_project_mnm.ps1` 或 `workflows/export_mnm_project_copy_default_folder.ps1`；本次 Nano 实机通过 |
| 编译 | 复用 `workflows/compile_kv_project.ps1`；旧样本转换记录为 879 步 / 782 指令，修改后必须重新编译 |
| 框脚本 / 普通梯形图增删改查 | 正式入口 `workflows/manage_kv_nano_program.ps1`；空白交通灯 BAT 32 项通过，见 [接口契约](nano-program-interface.md) 和 [验收用例](../tests/kv-interface-regression/25_nano_traffic_crud/README.md) |
| 域脚本增删改查 | `workflows/manage_kv_nano_program.ps1` 支持完整回路的新增、读取、覆盖修改及删除；2026-11-17 专用空项目 BAT 59 项通过，149 步 / 116 指令，见 [域脚本与标号 BAT](../tests/kv-interface-regression/26_nano_area_labels_crud/README.md) |
| 标号读取/写入 | 既有提交 `68a5e7a`、`6048e57`、`5a32578` 已固化导出读取；正式 `manage_kv_nano_program.ps1` 复用其表格路线，增加全局/Main 局部标号的追加、直接覆盖/删除、完整旧表比较、复制失败检测与保存重开验收，见 [接口契约](nano-program-interface.md) |
| 程序正文替换 | 旧 `write_nano_program_guarded.ps1` 不可作为成功依据：未确保选中完整程序、未验编辑列表关闭/正文回读，旧运行记录还存在错误 400 |
| 新建/导入程序或宏 | 旧 `.mod/.mcr` 导入脚本仅证明出现完成提示和树项；缺完整路径绑定、保存重开、内容核对、编译和正式入口 |
| 工程快照 | 仍待修复：当前把部分失败改为 `skipped + ok=true`，且未接入标号；`status=ready` 不能证明完整 |
| 注释读写 | 既有公开接口可复用；DeepSeek 增加的默认目录恢复、CSV 清理与弹窗处理仍需审计和实机回归 |
| Nano CPU 能力范围 | 应依据真实型号和项目配置做规划；不能仅因目录中出现 `.mod` 就把变量、网络或运动检查全部跳过 |

公开入口以 `scripts/script_manifest.json` 的 `customer_callable` 为准。禁止直接调用未发布的 Nano runner。
Nano 不支持 ST/FBD 的编程约束见 programmer 的 `keyence-basics-and-pitfalls.md` §12；KV 脚本与 ST 要区分。

## 本次 MNM 导出修复

同一个共享 runner 完成路径绑定、菜单点击、文件夹选择、文件验证与结果写入，不再为 Nano 复制一条不受控 UI 路径。
完整路径绑定允许同时打开同名副本，并能在冷启动转交后取得实际 PID/HWND；标题只用于交叉检查。

菜单使用有名称的受保护控件点击。此前只发 R/S 键会被中文输入法截获，截图中能看到输入法组合串与未关闭的文件菜单。
导出明确选中本次新建的空目录，通过 shell 树逐段定位并核对选中状态。
只接受经过标题、正文和按钮核对的导出提示；未知消息立即失败。
仅收集该目录中实际生成、头部合法且模块名匹配的 MNM，复制到请求输出目录后核对 SHA256。
已删除扫描用户下载/文档目录、移动近期文件、任意 KV STUDIO 弹窗按确定的逻辑。

`不能读取包括ST/脚本, 数据包的程序助记符文件, 请注意。` 是保存时出现的**反向读取限制提醒**；
它不表示保存失败，更不能据此宣称“ST 工程永远不能导出 MNM”。
后续 `保存了助记符表。` 与本次真实文件共同构成导出证据。

证据根：`C:/kvrun/nano_audit_20261117`。

- `original_hashes.json`：原工程文件指纹。
- `export_fixed/workflow_result.json`：真实打开的副本，9 个 MNM，约 12 秒，统一日志与 step receipt。
- `cold_workflow/workflow_result.json`：从原件建立独立导出副本，冷启动路径，9 个 MNM，约 18 秒。
- `contracts2/test_result.json`：8 个编码、头部校验与完整路径边界测试通过。
- `baseline_export*`：保留启动 PID 等待失败及输入法拦截失败，不能作为通过证据。
- KV-X 共享导出回归：`C:/kvrun/n17kvx/workflow/workflow_result.json` 为失败，`export_mnm` 步骤超时（`KV_FLAT_WORKFLOW_STEP_TIMEOUT`），尚未完成兼容性验收；不能由 Nano 通过推断 KV-X 通过。

上述导出验证不证明正文写入、标号写入或完整 Nano 项目创建已经完成。后续验收必须在相应正式 workflow 内完成保存、重新读取和实际编译。

## Nano 框脚本文本输入路线实测（2026-11-17）

在 KV-NC32、KV STUDIO 12.41.0.0 的独立工程副本上，已实测通过以下路线：

1. 新建扫描模块 `NanoBoxProbe_Run`，通过实际菜单选择 `ST/脚本 → 转换编辑方法 → 窗口`。
2. 选择 `插入框脚本`，在 `ST/脚本编辑窗口` 内粘贴源码，再用
   `Ctrl+Home → Ctrl+Shift+End → Ctrl+C` 完整回读比较。
3. 应用并转换脚本；在第 1 列添加 `CR2002` 常时 ON 接点，作为第 5～10 列框脚本的执行条件。
4. 通过公开 `compile_kv_project.ps1` 编译整个工程，保存工程。
5. 从磁盘上已保存的工程另建副本并由新 Kvs 进程打开，再次进入框脚本文本窗口，完整回读比较并重新编译。

本次测试源码：

```text
'NanoBoxProbe_Run
DM0 = DM0 + 1
```

重开前后均为 `转换结果 OK`、896 步 / 795 条指令。新进程回读的两行源码与输入一致。
原件 31 个文件的 SHA256 均未变化；原有 9 个程序的导出 MNM 在前后两次导出中逐文件一致。
测试只在离线副本进行，未连接或下装 PLC。

必须保留的输入前提：

- 输入方式需要在当前进程显式选择。此次新进程默认进入直接输入，不能依赖上次设置。
- 框脚本的执行条件必须完整。空白测试行未加接点时，整工程编译出现错误 40 / 76；补齐接点后通过。
- 接点操作数窗口和脚本文本窗口不同。此次前者使用剪贴板粘贴后留下无效操作数，报错误 62；
  使用受守卫的 `CR2002` 键入并离开字段后成功。该观察不代表所有接点窗口都禁止粘贴。
- 模块名不能以 `_` 或 `_数字` 结尾；测试模块名使用 `NanoBoxProbe_Run`。
- 含框脚本的整段程序仍不能通过编辑列表或 MNM 读取还原。本路线只向脚本文本窗口输入源码，
  不把导出 MNM 当作脚本导入文件。

**本路线仅为 Nano 专用研究验证，尚未发布为通用正文替换或完整工程导入能力。**
研究探针 `probes/inspect_nano_editor.ps1` 在任何输入前校验实际 CPU；对实际打开的 KV-X520 调用
`PasteProbeScript` 得到 `KV_NANO_CPU_REQUIRED`，未执行 UI 输入。KV-X 继续使用既有流程。

知识库依据：`pdf::ScriptUse::chunk-020`（输入方法与标准复制粘贴）、
`pdf::ScriptUse::chunk-021#p3` / `#p4`（框脚本编程与第 5～10 列布局）、
`pdf::KVSUSE_KVS11::chunk-050`（含脚本程序的 MNM 反向读取限制）。

本次证据根：`C:/kvrun/nano_box_20261117`。

- `paste_script_retry/script_readback_result.json`：首次源码输入及完整回读。
- `compile_valid_condition/workflow_result.json`：保存前整工程编译。
- `reopen/workflow/workflow_result.json`：从保存结果建立副本，由新进程打开并导出 10 个 MNM。
- `persisted_readback/script_readback_result.json`：新进程从磁盘工程回读源码，PID 9404。
- `compile_reopened/workflow_result.json`：重开后整工程编译。
- `integrity_result.json`：原件指纹与原有 9 个程序内容核对。
- `kvx_rejected/probe_failure.json`：KV-X 在输入前被拒绝的证据。

## 框脚本增删改查实测（2026-11-17）

在 `C:/kvrun/nano_crud_20261117` 的新副本中，继续使用 KV-NC32 / 12.41.0.0，
完成了以下研究验证。每次持久化检查均从已保存工程建立另一份副本，由新 Kvs 进程打开；
没有用 MNM 反向导入代替工程重开。

| 操作 | 真实操作及验收 | 证据（相对本次证据根） |
| --- | --- | --- |
| 查 | 文本窗口完整复制原脚本；分别读取两个相邻脚本，并核对中文注释及源码 | `read_original`、`sentinel_persisted_read`、`final_sentinel_read` |
| 改 | `DM0 = DM0 + 1` 改为 `DM0 = DM0 + 7`，添加中文注释及 `DM2 = 42`；保存重开回读一致 | `modify_paste`、`modified_persisted_read`；`modified_compile` 为 OK，899 步 / 797 指令 |
| 增 | 在第二行插入另一框脚本 `DM4 = 123`，补齐条件及连接线；保存重开分别读回两个脚本 | `sentinel_paste`、`sentinel_persisted_read`；`two_boxes_valid_compile` 为 OK，905 步 / 800 指令 |
| 删语句 | 从目标框源码中删除 `DM2 = 42`，保留 `DM0 = DM0 + 7`；重开回读确认，相邻脚本一致 | `target_trim_statement`、`trimmed_persisted_read` |
| 删框 | 先完整读回目标作为删除凭据，再选中第一行第 5 列按 Delete；另删不再使用的空回路 | `delete_target_box`、`deletion_remove_empty_rung` |
| 删后核对 | 新进程导出中目标注释和语句均消失，相邻 `DM4 = 123` 框完整回读 | `deleted_persist/absence_result.json`、`deleted_sentinel_read`；`deleted_compile` 为 OK，890 步 / 789 指令 |
| 重新增 | 删除后重新插入 `DM0 = DM0 + 9` 框；再次保存重开，目标与相邻脚本分别回读一致 | `readd_paste`、`final_readded_read`、`final_sentinel_read`；`final_compile` 为 OK，905 步 / 800 指令 |

当前探针新增 `ScriptSourcePath`、`ScriptRow` 与删除前的 `VerifiedReadbackPath`，
只用于测试模块 `NanoBoxProbe_Run` 的前两行研究。删除凭据必须来自同工程、同 PID、同脚本行且源码一致的读取结果。
源码查验使用窗口中的实际复制文本；导出仅用于检查删除后的源码缺失和原程序内容一致。

本次进一步确认的边界：

- 应先打开目标程序页，再明确选择窗口输入。只在其他程序页选择后切换目标页，仍可能进入直接输入。
- 新行插入框脚本不一定补齐第 2～4 列连接线；本次在接点后逐列输入横向连接线，解决错误 400 / 76。
- Delete 删除框脚本后保留其执行条件及连接线；若整行不再使用，应另行删除该空回路，避免留下不完整逻辑。
- 工程树定位使用已按完整工程路径绑定的编辑器 HWND，避免转换结果面板成为 `MainWindowHandle` 后找不到工程树。
- 首次使用 KVS12 启动器时曾遇到暂态 `KV_PROJECT_PROCESS_AMBIGUOUS`，取证后绑定已实际接手的进程完成导出；
  后续副本启动显式指定本机实际接手 Nano 的可执行文件，未修改 KV-X 的启动或编辑流程。

`integrity_result.json` 证明原件 31 个文件未变化；4 次持久化导出中，原有 9 个程序共 36 次 SHA256 比较均一致。
`kvx_delete_rejected/probe_failure.json` 及其日志证明实际 KV-X520 在输入前得到 `KV_NANO_CPU_REQUIRED`。
探针语法、UTF-8 BOM 和 UI 守卫使用检查通过；这不代表全仓门禁已通过。

汇总证据：`C:/kvrun/nano_crud_20261117/crud_result.json`。
本轮确认的是这组真实增删改查操作，不是任意模块、任意位置的正式批量导入接口；探针仍为 `research`。

## 空白交通灯工程正式接口验收（2026-11-17）

后续已将路径与 CPU 绑定、独立脚本文本窗、完整回路插入、旧源码比较、编译和关闭重开整理为正式 workflow `manage_kv_nano_program.ps1`，不再使用上文研究探针完成客户态增删改查。范围是 Nano 框脚本和普通梯形图回路；不是带脚本 MNM 反向导入。

真实创建空白 KV-NC32 工程，在 Main 写入双向交通灯框脚本、诊断脚本和 7 条普通梯形图回路。完整 BAT 当次通过 32 项：脚本新增/读取/修改/删除语句/旧源码不符拒绝/删除整个框和回路/重新新增，普通回路新增/读取/修改/删除，相邻内容保持，以及保存关闭重开后两个脚本和全部回路回读。

最终转换成功，146 步 / 113 指令，错误 0、警告 0。全过程串行使用同一工程，重开前确认原 PID 退出；测试正常结束后的进程快照为空，未遗留 Kvs 进程。测试失败同样在 finally 中清理本次拥有的进程，保留失败证据。

当次证据：`C:/kvrun/nano_traffic_bat_20261117_pass/test_result.json`、`19_script_readd/artifacts/compile_result/compile_result_copied.txt`、`21_persisted_phase`、`22_persisted_diagnostic`、`23_persisted_ladder_1`～`7`。真实项目为 `projects/NanoTraffic/NanoTraffic.kpr`。

测试捕获并修复了“插入”只打开子菜单、没有选择“空行”导致非空位置被覆盖的问题；最终用例要求删除后重新新增，并在重开后核对全部回路。KV STUDIO 将 `MR10` 显示为 `MR010`，梯形图比较对地址前导零做归一化，实际回读原文保留。

`logic_verification.json` 对真实回读源码执行离线语义检查，20 组启动初值、3 个周期 / 8400 次扫描、16 种请求组合通过。未连接真实 PLC，不把此结果作为下载或现场运行验收。
