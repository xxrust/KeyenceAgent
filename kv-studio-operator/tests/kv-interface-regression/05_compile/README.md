# 05 编译与错误树提取

## 操作内容

调用 `scripts/workflows/compile_kv_project.ps1` 执行 KV STUDIO 转换/编译，并从结果树复制文本。

## 测试目标

验证 Ctrl+F9 编译动作、结果树出现、结果文本提取以及 flat executor 的编译门禁。通过不仅要求动作完成，还要求本次复制文本包含“转换结果 OK”且不包含“转换结果 NG”。

## 当前状态

`scenario.json` is enabled after live validation. The compile workflow is published in `script_manifest.json`, and `run-all.bat` includes this scenario.

## 执行方法

需要单独运行时双击本目录 `run.bat`。调用链为公共 runner -> `compile_kv_project.ps1` -> flat executor -> `compile_and_copy_result_bounded.ps1` -> `copy_convert_result_from_tree_handle.ps1`。`-PlanOnly` 不编译。

## 通过标准

真实测试必须满足：`test_result.json` 为 `ok=true,status=pass`；`workflow/workflow_result.json` 为 `ok=true`，并记录 `compile_acceptance_required=true`、`compile_result_contains_ok=true`、`compile_result_contains_ng=false`；`workflow/artifacts/compile/result.json` 和 `workflow/artifacts/compile_result/result.json` 均为成功；`workflow/artifacts/compile_result/compile_result_copied.txt` 来自本次 receipt 所记录的哈希；统一日志包含编译和复制两个步骤。

只看到结果树、只完成 Ctrl+F9，或读取到历史结果都不算通过。

本项验证编译成功。预期编译失败和完整错误诊断提取由
[19_compile_error](../19_compile_error/README.md) 独立验证；其中测试通过不改变原 workflow 的失败结果。

## 日志与结果

输出位于 `../runs/05_compile_<时间戳>/`。编译动作证据在 `workflow/artifacts/compile/`，文本提取证据在 `workflow/artifacts/compile_result/`，统一日志在 `workflow/run.log`，总结果在 `test_result.json`。失败时优先查看两个步骤的 `step_stderr.txt`、`fail.txt` 和 receipt。
