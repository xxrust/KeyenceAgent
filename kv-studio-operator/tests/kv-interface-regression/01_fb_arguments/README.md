# 01 FB 自变量整表写入

## 操作内容

调用 `scripts/workflows/set_kv_fb_arguments.ps1`，把固定 TSV 整表写入测试副本中的 `FB_Cylinder` 自变量表。该表用于声明 FB 的 `IN`、`OUT`、`IN-OUT` 接口，不是局部变量表。

## 测试目标

验证正式 workflow 能定位指定 FB、进入当前记忆状态下正确的自变量表、按需清空旧表、整表粘贴、复制回读并保存项目。测试还验证 workflow 通过 flat executor 串行运行，且每一步受 UI guard 和结果契约约束。

## 固定输入

`fixtures/fb_arguments.tsv` 当前写入一行：`bExeToWorkManual / IN / BOOL`，并包含 KV STUDIO 所需的其余布尔列。目标模块固定为 `FB_Cylinder`。

## 执行方法

双击 `run.bat` 进行真实桌面测试；无人值守可运行 `run.bat -NoPause`。`run.bat -NoPause -PlanOnly` 只检查参数展开和执行计划，不能证明写入成功。

每次运行会复制一份 KVX 样例项目，启动真实 `Kvs.exe`，调用本目录 `run.ps1` -> 公共 `run-workflow-test.ps1` -> `set_kv_fb_arguments.ps1` -> flat executor -> `set_fb_arguments_guarded.ps1`。已存在表使用“复制探测 -> Shift+Delete -> 删除确认 -> 整表粘贴”；空表直接整表粘贴。最终复制回读并执行 `Ctrl+S`。

## 通过标准

真实测试必须同时满足：进程退出码为 0；`test_result.json` 为 `ok=true,status=pass`；`workflow/fb_declaration_workflow_result.json` 为 `ok=true`；`workflow/artifacts/fb_arguments/set_fb_arguments_result.json` 为 `ok=true`；其 `copyback_path` 文件包含与 fixture 一致的名称、方向和类型；同目录 `step_receipt.json` 为成功；同次 `workflow/run.log` 记录选择、清空或空表分支、粘贴、回读和保存。

仅打开自变量窗口、完成粘贴或得到 `status=planned` 均不算通过。

## 日志与结果

输出位于 `../runs/01_fb_arguments_<时间戳>/`。总结果是 `test_result.json`，workflow 总结果是 `workflow/fb_declaration_workflow_result.json`，统一日志是 `workflow/run.log`，原子步骤证据位于 `workflow/artifacts/fb_arguments/`。标准输出和错误输出分别是 `workflow_stdout.txt`、`workflow_stderr.txt`。

## 当前验证边界

本场景证明 FB 自变量整表写入、表格复制回读和保存链路；它不写局部变量、不替换程序体，也不执行编译。
