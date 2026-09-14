# 11 用户数据类型增删改

## 操作内容

调用 `scripts/workflows/mutate_kv_structure_definitions.ps1`，按固定计划创建、回读、修改并删除用户数据类型。该场景会真实改变测试副本，因此默认禁用。

## 测试目标

验证数据类型 CRUD 原子路径：按依赖顺序创建被嵌套类型和外层类型，粘贴成员整表，关闭并重新打开复制回读，清空旧成员后更新，再按逆依赖顺序删除。workflow 必须拒绝修改 `(System)` 分支。

## 固定输入

`fixtures/structure_plan.json` 在 `数据类型/zzMutationSimple` 下依次创建 `zzMutationInner`、创建引用它的 `zzMutationOuter`、把 Inner 的 `count` 从 `UINT` 改为 `UDINT` 并增加 `fault`，最后先删除 Outer、再删除 Inner。计划不创建文件夹，所以目标父文件夹必须预先存在于测试项目。

## 当前状态

`scenario.json` 设置 `enabled=false`。根目录 `run-all.bat` 不会执行它，因为这是破坏性、依赖项目前置结构的 opt-in 场景。运行前必须人工核对 fixture 与测试副本；不得对用户生产项目执行。

## 执行方法

确认前置文件夹存在后，双击 `run.bat` 或运行 `run.bat -NoPause`。调用链为公共 runner -> `mutate_kv_structure_definitions.ps1` -> flat executor -> `mutate_structure_definitions_guarded.ps1`。`-PlanOnly` 只检查计划，不执行 CRUD。

## 通过标准

真实测试必须满足：`test_result.json` 和 `workflow/workflow_result.json` 为成功；`workflow/result.json` 为 `ok=true` 且 `structure_operations=5`；创建和更新阶段的日志包含关闭/重开后的成员名与类型回读成功；删除阶段确认两个临时类型已不在项目树中；step receipt 成功；统一日志覆盖每个计划动作。最终不存在临时类型是本计划的预期结果，不是失败。

仅弹出新建窗体、创建空类型、粘贴成员但未重新打开回读，或只完成删除弹窗确认，都不算通过。

## 日志与结果

输出位于 `../runs/11_structure_mutation_<时间戳>/`。runner 结果、失败证据、步骤 receipt 和结构体复制证据位于 `workflow/`，统一日志为 `workflow/run.log`，总结果为根部 `test_result.json`。
