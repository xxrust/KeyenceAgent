# 04 用户数据类型快照

## 操作内容

调用 `scripts/workflows/export_kv_structure_definitions.ps1`，从测试副本导出用户定义的数据类型及成员，不修改项目。

## 测试目标

验证 workflow 能进入项目树的数据类型分支，读取用户结构体表格，将尾部空白新增行排除，并形成结构化 JSON。系统自带 `(System)` 类型不属于创建或维护对象。

## 固定输入

本场景未传 `StructureName`，因此目标是读取项目中可访问的全部用户数据类型，而不是只读取指定名称。

## 执行方法

双击 `run.bat` 进行真实测试；`run.bat -NoPause -PlanOnly` 仅验证计划。调用链为公共 runner -> `export_kv_structure_definitions.ps1` -> flat executor -> `export_structure_definitions_guarded.ps1`。

## 通过标准

真实测试必须满足：`test_result.json` 为 `ok=true,status=pass`；`workflow/workflow_result.json` 为 `ok=true`；`workflow/structure_definitions.json` 为 `ok=true`；`structure_count` 与 `structures` 数量一致；每个结构体包含从当前 KV STUDIO 表格复制并解析的定义；step receipt 成功；`workflow/run.log` 记录同次读取。

仅发现“数据类型”树节点不算通过。结构体列表为空只有在目标项目确实没有用户类型且结果文件明确记录零项时才是有效快照；本固定 KVX 样例通常应得到非零结构体，人工审核时应检查具体名称和成员。

## 日志与结果

输出位于 `../runs/04_structures_snapshot_<时间戳>/`。本 workflow 的 runner child 直接写入 `workflow/structure_definitions.json`，相同步骤的 receipt 与 stdout/stderr 也在 `workflow/`；统一日志为 `workflow/run.log`，总结果为根部 `test_result.json`。
