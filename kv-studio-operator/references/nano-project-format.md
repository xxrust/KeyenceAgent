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
| 标号读取/写入 | `export_nano_labels_guarded.ps1` 仍为研究实现；缺正式 workflow、守卫化、空表与失败区分、保存回读及回归 |
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
