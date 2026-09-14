# 03 变量快照

## 操作内容

以 `SnapshotOnly` 调用 `scripts/workflows/set_kv_variables.ps1`，从测试副本读取变量表，不修改项目。

## 测试目标

验证变量编辑器可以由正式 workflow 打开，名称筛选被清空、用途筛选切到全部，并从 KV STUDIO 表格复制全局变量快照。只有 `SnapshotModules` 指定模块时才会额外读取对应局部变量；本场景未指定，所以只测试全局表。

## 固定输入

固定输入只有测试项目副本。场景不提供全局或局部变量 TSV，且禁止在 `SnapshotOnly` 模式混入写入参数。

## 执行方法

双击 `run.bat`，或运行 `run.bat -NoPause`。调用链为公共 runner -> `set_kv_variables.ps1 -SnapshotOnly` -> flat executor -> `set_variables_guarded.ps1 -SnapshotOnly`。`-PlanOnly` 不会打开变量编辑器或复制表格。

## 通过标准

真实测试必须满足：`test_result.json` 为 `ok=true,status=pass`；`workflow/variable_workflow_result.json` 为 `ok=true`；`workflow/artifacts/variables/variable_snapshot_result.json` 为 `ok=true,read_only=true`；其中至少有 `scope=global` 的 snapshot，且其 `raw_path` 文件存在；step receipt 成功；`workflow/run.log` 记录筛选归一化和复制过程。

快照允许表为空；空表必须被记录为真实的空 TSV，而不能用旧文件或缺失文件冒充。`all_columns_preserved=true` 只表示复制文本保留表格列；`unfiltered_completeness_verified=false` 明确表示当前结果没有独立证明 KV STUDIO 内部不存在不可见数据。

## 日志与结果

输出位于 `../runs/03_variables_snapshot_<时间戳>/`。变量原始 TSV、`variable_snapshot_result.json` 和 `step_receipt.json` 位于 `workflow/artifacts/variables/`；统一日志在 `workflow/run.log`；总结果在 `test_result.json`。
