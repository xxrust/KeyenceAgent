# KEYENCE 参考项目复刻门限

复刻参考项目时，用本清单确认目标项目、程序、变量、FB、单元配置和编译证据已经形成闭环。

## 需求到产物映射

每项需求都绑定到可检查证据：

- CPU/型号 -> 项目设定或截图/日志证据。
- 单元配置 -> 单元配置证据。
- 参考行为 -> 已检查的参考程序、变量和设备映射。
- 官方 FB 依赖 -> 直接导入的 FB 清单和来源包。
- 用户业务逻辑 -> 编写或编辑后的 MNM 文件。
- 变量 -> 全局/局部变量 manifest 和 KV STUDIO 变量编辑器重建结果。
- 编译 -> `Ctrl+F2` 或 `Ctrl+F9` 通过证据。

## 有效复刻证据

复刻结果包含：

1. 目标项目的 CPU、单元配置、程序树和变量表均有当前项目证据。
2. 官方 FB 来自 `All.pregx` 或官方包，并在交付记录中列出来源。
3. 用户业务逻辑通过 MNM 导入或明确的 KV STUDIO UI 编辑进入项目。
4. 变量在 KV STUDIO 中重建，包括局部变量和 FB 实例。
5. `Ctrl+F2` 或 `Ctrl+F9` 转换/编译通过。
6. 程序 inventory 与参考意图一致：模块、扫描/任务位置、主要状态转移和设备交互。

## 完整性检查

复刻完整性由以下条件共同证明：

- 目标项目拥有独立的当前项目路径、source snapshot 和验证证据。
- 官方 FB 作为库依赖存在；用户逻辑以 MNM/变量 manifest/单元配置证据表达。
- 编译错误清单为空。
- MNM 引用的变量都能在全局/局部变量表、FB 实例或设备映射中解析。
- 程序行为覆盖参考项目的关键状态、互锁、输出和设备交互。

## 迭代链路

1. Compile with Ctrl+F2.
2. Copy all error messages from the conversion/error window.
3. Categorize errors as missing variable, missing FB type, device/map issue, syntax issue, or scope/type mismatch.
4. Fix variables before changing logic when the error is name/scope/type related.
5. Re-import MNM only after updating the manifest.
6. Repeat until compile passes.
