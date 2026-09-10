# 功能块开发

一个完整 FB 包含程序体、自变量和局部变量；调用方还需要实例和实参绑定。
MNM 导入只证明相应模块导入流程，不能据此声称声明完整或编译通过。

设计先遵循 [programmer skill](../../keyence-plc-programmer/SKILL.md) 的可复用边界：
设备和全局集成变量由调用方绑定，外部交互声明为 IN、OUT、IN-OUT 等自变量，
内部状态声明为局部变量。具体 KEYENCE 调用语法以 Wiki 或真实 MNM 导出为准，
不要把通用语言伪代码当作可导入的助记符。

执行时从 [能力清单](../../kv-studio-operator/scripts/script_manifest.json) 查询操作：

1. 准备相关类型、FB MNM、自变量 TSV、局部变量 TSV 和预期结果。
2. 按依赖顺序创建数据类型，再导入 FB 程序体。
3. 写入自变量和局部变量，检查各自的读回结果。
4. 建立调用实例和实参绑定，转换/编译并检查错误文本。

已有 FB 只改一部分时调用对应接口，不必删除整个 FB。
需要整体重导入时显式处理同名模块，保留原快照与可恢复版本。

自变量快照可通过 `get_kv_capabilities.ps1 -Capability snapshot_fb_arguments`
查询接口。焦点状态判断、Ctrl+Tab 次数和粘贴顺序都由共享原子实现负责；
agent 不重复编排键盘。

字段和验证范围见 [variable-editor.md](../../kv-studio-operator/references/variable-editor.md)。
读回与保存是数据验收，编译是语法/链接验收，机械动作仍需相应行为验收。
