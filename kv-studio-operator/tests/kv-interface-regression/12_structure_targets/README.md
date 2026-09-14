# 12 指定数据类型读取

## 操作内容

这是独立的精确目标回归场景。它调用与 `04_structures_snapshot` 相同的 workflow 和 runner child，但通过 `-StructureName` 固定读取两个指定数据类型：`strAxis` 与 `strCylinderCtrl`。

## 测试目标

验证 agent 可以把一个或多个数据类型名称作为 API 参数传入，而无需遍历整个数据类型树。每个目标仍通过同一个已验证的 `ExtractOne` 原子操作完成：定位树项、打开结构体编辑器、聚焦表格、复制成员表、解析成员名/类型/注释并输出 JSON。

## 固定输入

目标类型固定为 `strAxis`、`strCylinderCtrl`，两者应存在于 KVX 样例项目的用户数据类型分支。`(System)` 不在请求列表中，也不会被读取或修改。

## 执行方法

双击 `run.bat` 进行真实桌面测试；无人值守使用 `run.bat -NoPause`；`run.bat -NoPause -PlanOnly` 只验证参数和调度计划。调用链为：

```text
run.bat
  -> run.ps1
    -> run-workflow-test.ps1
      -> workflows/export_kv_structure_definitions.ps1 -StructureName strAxis,strCylinderCtrl
        -> flat executor
          -> runner_children/export_structure_definitions_guarded.ps1
            -> ExtractOne(strAxis)
            -> ExtractOne(strCylinderCtrl)
```

## 通过标准

真实测试必须同时满足：`test_result.json` 为 `ok=true,status=pass`；`workflow/workflow_result.json` 为 `ok=true`；`workflow/structure_definitions.json` 为 `ok=true` 且 `structure_count=2`；`structures` 中的名称集合恰好为 `strAxis`、`strCylinderCtrl`，没有额外类型；每个结构体的 `member_count` 大于 0 且成员字段含 `name` 和 `data_type`；step receipt 成功；同次 `workflow/run.log` 记录两个目标各自的打开、复制和解析。

若任一指定名称不存在，脚本应失败并记录 `KV_STRUCTURE_NOT_FOUND`，不能退化为遍历全部类型后返回成功。仅生成计划、打开结构体窗口或产生旧快照均不算通过。

## 日志与结果

输出位于 `../runs/12_structure_targets_<时间戳>/`。总结果是 `test_result.json`；workflow 结果是 `workflow/workflow_result.json`；目标结构体快照是 `workflow/structure_definitions.json`；原子步骤 receipt、TSV 和 UI 证据在 `workflow/`；统一日志为 `workflow/run.log`。

## 与 04 场景的关系

`04_structures_snapshot` 不传 `-StructureName`，测试“发现并读取全部用户类型”；本场景传入一个或多个名称，测试“只读取指定目标”。两者复用同一个原子脚本，不复制 UI 操作逻辑。
