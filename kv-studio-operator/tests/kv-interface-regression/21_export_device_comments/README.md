# 21 软元件注释导出（CSV/TXT）

## 操作内容

调用 `scripts/workflows/export_kv_device_comments.ps1`，在隔离的项目副本上通过 KV STUDIO 的
「文件(F) → 以 CSV/TXT 格式保存软元件注释(K)...」把工程注释表导出成 CSV，再收集到调用方指定目录。

## 测试目标

验证「注释列表导出」这条只读链路的三个环节：菜单项定位与调用、模态「另存为」对话框的状态校验与输入、
以及**本次运行**产物的收集与结构校验。测试必须排除历史文件冒充本次导出，也必须排除只打开菜单、
只弹出对话框这类中间状态。

## 固定输入

源是 harness 为本场景复制的项目。导出目标为本次运行目录下 `comments/`，文件名固定为
`device_comments_regression.csv`（同名目标已存在时默认失败，不覆盖）。

## 执行方法

双击 `run.bat`，或运行 `run.bat -NoPause`。调用链为公共 runner → `export_kv_device_comments.ps1`
→ flat executor（持有 `Local\KeyenceAgent.KvStudio.UI`）→ `runner_children/export_device_comments_guarded.ps1`。
`-PlanOnly` 只做派发校验，不产生 CSV。

路线固定为：绑定项目主窗口（等待标题回到干净且稳定）→ UIA 展开「文件(F)」并调用带 (K) 加速键的注释导出项
→ 等待 `#32770`「另存为」→ 校验保存类型含 `CSV`、程序选择器为 `全局` → 受保护输入唯一文件名并**读回比对**
→ `BM_CLICK` 保存按钮(IDOK) → 按运行时间收集新 CSV → 校验表头列数与行数 → 移入 `comments/`。

## 通过标准

真实测试必须满足：`test_result.json` 与 `workflow/workflow_result.json` 为成功；
`workflow/artifacts/comments/device_comments_export_result.json` 为 `ok=true`；
产物存在于 `comments/` 且非空、`artifact_rows >= 2`、`artifact_sha256` 非空；
结果里的 `dialog_evidence.file_type` 含 `CSV`、`program_selector` 为 `全局`；
`run.log` 能关联菜单调用、对话框校验、输入读回和保存步骤。

只打开菜单、只出现对话框、或 `comments/` 中残留旧 CSV 都不算通过。

## 日志与结果

输出位于 `../runs/21_export_device_comments_<时间戳>/`。最终 CSV 在 `comments/`；
UI 步骤证据与结果在 `workflow/artifacts/comments/`（含 `save_dialog_elements.json`、
`device_comments_export_result.json`、`top_windows_*.json`）；统一日志为 `workflow/run.log`。
