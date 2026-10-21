# 工程树解析（结构优先）

> 规定：**如何在不靠字符串猜测的前提下稳定定位"程序 / 功能块"节点。**
> 适用脚本：`scripts/kv_tree_resolver.ps1`（support_library，非 customer_callable）。

## 1. 树的三层模型（实测）

```
程序(显示执行顺序): <工程名>
  ├─ 每次扫描执行型模块        ← 容器：直接子项就是全部扫描程序
  │    ├─ IO输入 [1]
  │    └─ ST00_插针_演示 [8]
  └─ 后备模块                 ← 容器：直接子项是后备执行型程序
       └─ 版本管理 [24]

功能块
  └─ level1_组件 / level2_工站 / level3_设备 / UniversalLibrary / 通信
       └─ FB_Cylinder:气缸控制 / FB_McMode:设备模式 / ModbusTCPClient_Connect:…
```

## 2. 结构指纹（唯一可靠的类型判据）

**模块节点**（程序与 FB 都成立）的直接子项必含 `局部变量` 与 `书签`。

`书签` 是**程序内部的文件夹**，其子项（书签项）是模块的**孙**节点；
因此书签项、局部变量表都**不是**模块，它们的父节点才是。

## 3. 三条铁律

1. **禁止用 `-like` 匹配树项名**：名字含 `[ ]`（如 `HMI [17]`），`[` 在通配符里是字符类开头，
   `-like '... [*'` 抛 `WildcardPatternException`；若被 `try/catch` 吞掉，表现为"模块明明存在却查不到"。
   只用 `-eq` / `String.StartsWith()` / `[regex]::Escape()`（`^名(?::显示名)?(?: \[\d+\])?$`）。
2. **禁止全树按名搜索**：存在同名不同类节点 —— `变量` 容器下可能有叫 `HMI` 的**变量组**；书签项 `HMI轴控制` 与程序 `HMI` 同前缀。
   只用**有界结构搜索**：从 `程序(显示执行顺序)` / `功能块` 出发，只穿过文件夹型节点下钻，遇到模块节点即比对名字且**不再进入其子项**。
3. **删除/重命名后不得复用缓存 UIA 元素**：元素被删后仍可读，会把"已删除"误判为"仍存在"；复核前必须作废缓存并重新取树。

## 4. 函数

| 函数 | 用途 |
| --- | --- |
| `Get-KvProjectTree -ProcessId` | 取 `ProjectTreeView`；缺失抛 `KV_PROJECT_TREE_PANEL_ABSENT` |
| `Resolve-KvTreeNodeByPath -Tree -Path` | 逐级只取直接子项精确匹配；首段可用正则 |
| `Test-KvProgramNodeFingerprint -Element` | 结构指纹（`局部变量` + `书签`） |
| `Find-KvModuleNodeBounded -Tree -ModuleName` | 有界结构搜索：程序 / 用户 FB / 库 FB 命中，书签与变量组永不命中 |

自测基线：23 个扫描程序、4 个用户 FB、库 FB 全部命中；`HMI轴控制`、`书签`、`变量/HMI` 一律 `null`。

## 5. 与路由的关系

- `runner_children/import_mnm_guarded.ps1`：结构搜索优先；兜底限定在 `程序(显示执行顺序)` / `功能块` 子树内。
- `runner_children/set_fb_program_body_guarded.ps1`：选择目标树项时结构搜索优先（就地改与删除重建共用同一解析）。

## 6. 已知限制

- 容器需展开；`Resolve-KvTreeNodeByPath` 每级会调用 `ExpandCollapsePattern.Expand()`。
- 删除 + 重建是两段式输入会话，受 UI 守卫策略约束（见 [ui-guard-contract.md](ui-guard-contract.md)）：
  确认框关闭后前台回到第三方窗口，紧随其后的导入会被确定性拒绝。**改内容优先用就地改程序体**，不要为改内容去删模块。