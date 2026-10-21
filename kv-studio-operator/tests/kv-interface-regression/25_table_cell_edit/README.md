# 25_table_cell_edit

轴控制设定「大表」—— **对象级**单元格编辑（不用像素 ✗）。

- fixture：`fixtures/QA_BlankProject`（同上）
- workflow：`scripts/workflows/set_kv_axis_table_cell.ps1` → `runner_children/set_axis_table_cell_guarded.ps1`
- 参数：`-RowIndex 39 -Column 1 -Value 1500`（第 39 行 = 运转加速度/时间，轴1）

## 通过标准（脚本内有断言 ✓）
1. 读整表（点表格 + `Ctrl+A/C`）→ 79 行 ✓
2. `Ctrl+Home` + `Down×39` + `Right×0` → **选中单元格对象** ✓（与分辨率无关 ✓）
3. `F2` → `Ctrl+A` → 键入 → `Enter` ✓
4. 整表 diff：**恰好一行变化且索引=39** ✓（`exactly one row changed at target = True` ✓）
5. 保存 ✓ → 重开回读该行 = 新值 ✓

## 已知坑
- 改表前必须**关掉向导** ✗（模态会吞键盘导航 ✗）
- **坐标单位/模式只能走向导** ✗，不能在大表改 ✓（否则报「动作环境不正确」✗）
- 必须 `F2` 进入编辑态 ✗