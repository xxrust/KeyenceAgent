# Nano 单元与内置串口 CRUD

运行 `run.bat -NoPause -OutRoot C:\kvrun\nano_units_<new-name>`。
默认创建空 KV-NC32 工程；`OutRoot` 必须不存在。每次测试最终都关闭所属
进程，保留开始前的其它 KV STUDIO 进程。

覆盖 KV-NC1EP、KV-NC16EXT* 的新增、读取、修改、删除、重新添加；
CPU 内置 Port0 的模式/波特率修改与恢复。比较所有主参数表，验证旧值
不符时拒绝写入，修改/删除/重新添加在保存并重启 KV STUDIO 后仍成立。
CPU 与固有串口不能作为可删除硬件对象。

入口为 `scripts/workflows/manage_kv_nano_units.ps1`。所有桌面输入经
manifest 生成的 flat plan 执行。每次修改自动提交、保存并重开单元编辑器
回读；BAT 另行验证进程重启后的持久化。详细限制见
[Nano 单元编辑器](../../../references/nano-unit-editor.md)。

验收文件 `test_result.json` 包含每项断言、进程身份、清理结果与适用范围。
仅离线工程配置，不传送 PLC，不证明真实串口或网络通信成功。NC1EP
主表中的 `<设定>` 子窗口不在本测试范围内。

调试时可通过 `-CreatedProjectResultPath <receipt>` 显式接管本工具先前
创建的空工程；会检查 Main 为空及只有 CPU，不接受业务工程。通常直接
使用默认新建模式。

2026-11-17 实测：`C:/kvrun/nano_units_bat_20261117_f/test_result.json`，
43 项通过、0 失败，包含注释文件哈希不变与三个既有用户进程保留。
离线输入契约测试：`tests/nano-unit-contract/run.ps1 -OutDir <new-dir>`。
