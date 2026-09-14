# 06 PLC 扩展单元配置

## 操作内容

调用 `scripts/workflows/configure_kv_expansion_units.ps1`，向测试副本的单元配置加入固定模块 `KV-B16X`。

## 测试目标

验证模块型号作为 API 参数被动态定位，而不是依赖仅适用于某个型号的硬编码坐标；验证插入、确认保存和 `UnitSet.ue2` 持久化回读。每个模块的原子预算固定为小于 10 秒。

## 固定输入

`scenario.json` 传入 `-Models KV-B16X -PerModuleBudgetSeconds 10`。该场景只用 `KV-B16X` 做回归样本，不表示接口只支持此型号。

## 执行方法

双击 `run.bat` 或运行 `run.bat -NoPause`。调用链为公共 runner -> `configure_kv_expansion_units.ps1` -> flat executor -> `configure_expansion_units_guarded.ps1`。脚本先检查模块是否已存在；已存在时记录 `already_present`，否则在扁平目录中按型号查找并插入。`-PlanOnly` 不打开单元配置。

## 通过标准

真实测试必须满足：`test_result.json` 与 `workflow/workflow_result.json` 均成功；`workflow/result.json` 为 `ok=true`；`models` 和 `persisted_models` 包含 `KV-B16X`；新增动作的 `elapsed_seconds < 10`，或已有模块明确记录 `already_present`；结果记录 `unitset_path` 且文件存在；step receipt 成功，`workflow/run.log` 有同次型号、动作和持久化记录。

仅在目录列表中搜索到型号、双击了模块或 UI 上暂时出现模块，都不算通过；必须有保存后的项目文件回读。

## 日志与结果

输出位于 `../runs/06_expansion_units_<时间戳>/`。runner 结果和步骤证据直接位于 `workflow/`，统一日志是 `workflow/run.log`，总结果是根目录 `test_result.json`。
