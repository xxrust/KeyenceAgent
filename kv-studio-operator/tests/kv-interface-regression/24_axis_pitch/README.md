# 24_axis_pitch

改轴参数（移动量/螺距）—— **对象级**走「坐标转换计算」向导。

- fixture：`fixtures/QA_BlankProject`（KV-X520，2 从站，2 轴，轴1 = 其它/PLS/线性，移动量 10）
- workflow：`scripts/workflows/set_kv_axis_pitch.ps1` → `runner_children/set_axis_pitch_guarded.ps1`
- 参数：`-AxisLabel 轴1:Axis_1 -Pitch 25`

## 通过标准（脚本内有断言 ✓）
1. `_textBoxParameter` 用**真实键盘**输入 25 ✓（`WM_SETTEXT` 只改框不改模型 ✗）
2. `执行计算` 后 `_textBoxRatio` = **400** ✓（= 10000/25 ✓ 证明模型用了 25 ✓）
3. 向导 `OK(W)` ✓ → 「映射设定吗？」`是(Y)` ✓ → 向导关闭 ✓
4. 保存后标题无 `*` ✓
5. 重开回读 `_textBoxParameter` = **25** ✓（人工复核过一次 ✓）

## 已知坑
- `WM_SETTEXT` 对文本字段**无效** ✗（只改显示 ✓）→ 必须点进去 + Ctrl+A + 键入 ✓
- 下拉字段（机械配置/单位/模式/精度）用 UIA `SelectionItem.Select` ✓ 有效 ✓