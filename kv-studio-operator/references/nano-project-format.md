# KV Nano 工程格式与接口

## 识别工程

以 KV STUDIO 识别的 CPU 和实际程序树为准。KV-NC32 工程通常按模块保存 `.mod`，另有 `UnitSet.ue2`、`CpuMb2.inf`、标号及注释文件。`WsTreeEnv.xml` 可能存在。模块类别和扫描顺序从程序树读取。

冷启动发生进程转交时，按完整工程路径和实际 PID/HWND 绑定。标题用于交叉核对。软件版本以实际运行的程序为准。

## 读取 MNM

KV-NC32 实测导出头包含 `DEVICE:128`、`;MODULE:` 和 `;MODULE_TYPE:`，脚本模块可含 `;SCRIPT_TYPE:`。编码按本次文件判断。`workflow_tools/kv_mnm_text.ps1` 识别 Unicode BOM，无 BOM 时默认使用系统 ANSI 代码页。KV-NC32 在简体中文环境下有 Windows-936 导出。已知为无 BOM UTF-8 输入时显式指定 `-NoBomEncoding Utf8`。

按头部范围剥离元数据。程序中的分号行可能包含注释或原始 KV 脚本，应保留并结合上下文读取。Nano 的 MNM 可用于审查，KV STUDIO 的编辑列表无法用它还原脚本块。修改脚本使用专用脚本文本接口。

导出时的“不能读取包括ST/脚本, 数据包的程序助记符文件, 请注意。”提示指向反向读取限制。以导出文件、当次回执和模块覆盖范围判断导出结果。

## 选择公开接口

| 任务 | 入口 |
| --- | --- |
| 读取 KV-NC32 工程 | `nano_project_snapshot`。 [Nano 快照](nano-snapshot.md) |
| 导出 MNM 或编译 | 查询 manifest 中对应的公开导出与编译能力 |
| 修改普通回路、框脚本、域脚本或标号 | `manage_kv_nano_program.ps1`。 [Nano 接口契约](nano-program-interface.md) |
| 批量应用已规划的标号和源码 | `nano_program_plan`。按接口契约准备旧内容、目标内容和保存重开预期 |

支持范围以 manifest 的 `customer_callable` 和对应契约为准。接口回归使用仓库内的空白工程夹具。 [Nano 交通灯回归](../tests/kv-interface-regression/25_nano_traffic_crud/README.md)
