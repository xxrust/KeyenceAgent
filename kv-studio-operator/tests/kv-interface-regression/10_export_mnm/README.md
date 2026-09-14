# 10 项目 MNM 导出

## 操作内容

调用 `scripts/workflows/export_mnm_project_copy_default_folder.ps1`，在隔离的项目副本上通过 KV STUDIO 默认文件夹路径导出 MNM，再收集到本次运行目录。

## 测试目标

验证正式导出 workflow 的三段链路：建立隔离导出工作区、在真实 KV STUDIO 中执行 MNM 导出、将本次生成的 `.mnm` 文件收集到调用方指定目录。测试必须排除历史文件冒充本次导出。

## 固定输入

源是 harness 为本场景复制的 KVX 样例项目。导出目标是本次运行目录下 `export/`，内部工作区默认位于该目录下 `_kv_export_workspace/`。

## 执行方法

双击 `run.bat`，或运行 `run.bat -NoPause`。调用链为公共 runner -> `export_mnm_project_copy_default_folder.ps1` -> flat executor -> `new_kv_mnm_export_workspace.ps1` -> `export_mnm_browse_default_folder_guarded.ps1` -> `collect_kv_mnm_export_workspace.ps1`。`-PlanOnly` 不产生 MNM。

## 通过标准

真实测试必须满足：`test_result.json` 与 `workflow/workflow_result.json` 为成功；`workflow/export_mnm_project_copy_result.json` 为 `ok=true`；`workflow/mnm_files.json` 至少列出一个文件，列表中每个文件在 `export/` 下存在且非空；内部 UI 导出结果 `browse_folder_export_result.json` 为成功；三个步骤 receipt 均成功；`workflow/run.log` 能关联工作区、UI 导出和收集步骤。

只打开导出菜单、只生成工作区、或 `export/` 中残留旧 MNM 都不算通过。目标文件冲突时默认失败，除非调用方明确使用覆盖参数。

## 日志与结果

输出位于 `../runs/10_export_mnm_<时间戳>/`。最终文件在 `export/`；收集结果、总结果与统一日志在 `workflow/`；准备步骤证据在 `workflow/artifacts/export_workspace/`；UI 导出证据位于 `export/_kv_export_workspace/run_*/ui_export/`，其精确路径也记录在工作区计划和 workflow receipt 中。
