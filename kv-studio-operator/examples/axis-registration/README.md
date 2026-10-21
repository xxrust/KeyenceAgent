# 轴登记范例（已验证 2026-10-20 ✓）

## 怎么用
双击 `run.bat`（或命令行运行）。它会：

1. 把 `fixtures\QA_BlankProject`（**0 轴**工程 ✓）复制到临时目录
2. 启动 KV STUDIO 并打开它
3. 插 2 个 EtherCAT 从站（`nodes.json`，`batch_axis_registration=Yes`）
4. 跑 **已验证** 的轴登记脚本：
   `scripts\runner_children\complete_axis_registration_guarded.ps1`
   —— 处理「批量登录轴」→「轴的批量登录已经完成」→「是否进行新建轴的坐标转换设定」→
   坐标转换向导（**填螺距 20/40 + 执行计算**）→ 退出向导 → 保存
5. 打印判据

## 通过标准（只看产物 ✓）
```
轴数   = 2
从站   = 2
标题   无 *（已保存）
```

## 已验证事实（可作为回归基线 ✓）
- 「批量登录轴」出现后 **~0.9 s** 内被点掉 ✓
- 向导里 `_textBoxParameter` 写 20 → `执行计算` → `_textBoxRatio` 有值 ✓
- 保存：`PostMessage` 的 Ctrl+S **无效** ✗ → 只用**守卫 Ctrl+S 一次** ✓
- 实测：**轴数=2 ✓ 从站=2 ✓ 标题无 `*` ✓**（全自动、零人工按键 ✓）

## 两个关键文件
| 文件 | 作用 |
| --- | --- |
| `scripts\workflows\configure_kv_ethercat_nodes.ps1` | 插 From站（未改动 ✓）|
| `scripts\runner_children\complete_axis_registration_guarded.ps1` | 弹窗 + 向导 + 保存（**成功版原样** ✓）|