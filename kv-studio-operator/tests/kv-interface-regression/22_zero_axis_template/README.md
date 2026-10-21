# 22_zero_axis_template

标准模板的"零轴起点"判据（UI 侧只做一次编译，其余为离线断言）。

- fixture：`fixtures/BlankStart_v1`（`KV-X520`，**0 轴 / 0 EtherCAT 从站**，`All.prgx` 583 B）
- workflow：`scripts/workflows/compile_kv_project.ps1`（fixture_copy 模式）
- 期望：`expected_compile_result.txt`（空白工程的编译结果文本）

离线判据（不依赖 KVS，可单独跑）：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File ..\..\test_zero_axis_project.ps1 `
  -ProjectPath fixtures\BlankStart_v1 -OutDir <dir>
```

断言项：`axis_count <= 0`、`no_ethercat_slaves == 0`、`cpu == KV-X520`、`unit_nodes == 1`、`All.prgx < 5000 B`。
负向（32 轴模板）必须失败，否则判据无效。
## 补记：轴导入那一步**首次通过依赖人工按键**（2026-10-20）

- 0 轴起点本身是**程序生成 + 程序断言**通过 ✓（`test_zero_axis_project.ps1` ✓）。
- 往 0 轴工程"导入 2 个轴并保存"**首次跑通时，最后的 `Alt+Y` 由项目所有者手动按下** ✓。
  程序侧完成了：插入 2 个 EtherCAT 从站 ✓、批量登录轴 ✓、填螺距（20/40）✓、执行计算 ✓、点「退出向导」✓；
  **未完成**：退出确认弹窗的 `Alt+Y` 投递 ✗（UIA `Invoke()` 会先 `Control.Focus()` → 焦点抖动 ✗；按键又需要前台 ✗）。
- 因此本条当前定性：**半自动通过（人工 1 次按键）** ✗ —— 不得记为"全自动通过" ✗。
- 待办：对这些 KVS 自家弹窗改用"**消息投递 + 回读断言**"（`PostMessage` `BM_CLICK`/`WM_SYSKEYDOWN` ✓，不打断前台 ✓），改完再改回"全自动" ✓。
## 补记 2：轴导入已改为**全自动**（2026-10-20 晚）

- 手法：`#32770` 经典对话框用 **Win32 枚举子按钮 + `PostMessage(BM_CLICK)`** ✓（不取前台 ✓）；
  向导输入框用 UIA 读结构 + `WM_SETTEXT` 写值 + `BM_CLICK` 点「执行计算」✓；
  **保存**是唯一需要守卫（一次前台）✓ 的步骤。
- 结果：轴数 = 2 ✓、从站 = 2 ✓、`test_axis_import.ps1` PASS ✓、**人工按键 0 次** ✓。
- 历史：首次跑通时最后的 `Alt+Y` 由项目所有者手动按下 ✓（保留此记录以说明演进过程 ✓）。