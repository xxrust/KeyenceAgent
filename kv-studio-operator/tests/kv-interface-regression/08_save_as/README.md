# 08 项目另存为

## 操作内容

调用 `scripts/workflows/save_kv_project_as.ps1`，把本次测试副本另存为运行目录中的新项目。

## 测试目标

验证正式 workflow 能在目标项目上打开“另存为”窗体，在弹窗自动焦点不被主窗口 guard 抢回的前提下填写项目名、位置和注释，确认保存，并验证目标项目文件确实产生。

## 固定输入

项目名为 `KVX_SaveAs_Test`，目标目录为本次运行目录下的 `saved/`，注释为 `interface regression`，超时为 30 秒。每次运行目录隔离，因此不会复用上次目标。

## 执行方法

双击 `run.bat` 或运行 `run.bat -NoPause`。调用链为公共 runner -> `save_kv_project_as.ps1` -> flat executor -> `save_as_project_guarded.ps1`。`-PlanOnly` 不打开另存为弹窗，也不创建目标项目。

## 通过标准

真实测试必须满足：`test_result.json` 为 `ok=true,status=pass`；`workflow/save_as_workflow_result.json` 为 `ok=true`；`workflow/artifacts/save_as/save_as_result.json` 为 `ok=true`；结果声明的目标 `.kpr` 位于 `saved/` 且真实存在；目标项目名为 `KVX_SaveAs_Test`；step receipt 成功；`workflow/run.log` 记录打开弹窗、连续输入、确认和目标文件验证。

只出现另存为弹窗、输入了项目名、或当前窗口标题变化但目标文件不存在，均不算通过。出现校验错误弹窗时应记录文本并安全退出，而不是抢回主窗口焦点继续输入。

## 日志与结果

输出位于 `../runs/08_save_as_<时间戳>/`。另存为目标在 `saved/`；原子结果与弹窗证据在 `workflow/artifacts/save_as/`；统一日志在 `workflow/run.log`；总结果在根部 `test_result.json`。
