# 测试与回归

## 1. 两种跑道

| 跑道 | 位置 | 特点 |
|---|---|---|
| **harness 场景** | `tests\kv-interface-regression\<NN_xxx>\` | 统一框架：规划 → 静态门禁 → 生命周期 → 执行 → **证据校验**；可全量跑 |
| **自包含 bat** | `tests\axis-pitch\`、`tests\table-cell\` | 不经过框架：复制工程 → 开 KVS → 直接调脚本 → 断言 → 关 KVS；适合现场/演示 |

## 2. 全量回归（推荐）

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all-with-shots.ps1 `
  -OutRoot C:\kvrun\final -Skip none -IntervalMs 1500
```

- `-Skip none`：**不跳过任何场景**（脚本默认会跳 `24_axis_pitch`）
- 每个场景**自动起连拍截图** → `<OutRoot>\<场景>\shots\f*.png` + `index.txt`
- 输出：`<OutRoot>\suite_result.json`（`ok` / `exit` / `status` 逐场景）
- 单场景：`tests\kv-interface-regression\<场景>\run.bat`

> 必须用**短路径**（`C:\kvrun\...`）。长路径会触发 `KV_UI_GUARD_CHECKPOINT_PATH_TOO_LONG`。

## 3. 场景模式（`scenario.json` 的 `project_mode`）

| 模式 | 工程来源 | 用途 |
|---|---|---|
| `sample_copy`（**默认**）| 复制 `references\KVX样例程序_v100`（31 轴 + 从站）| 绝大多数场景 |
| `fixture_copy` | 复制场景自带 `fixtures\` | 专用/异常工程；**只允许** `compile_kv_project.ps1` |
| `new_project` | 从零新建 | 只给建工程流程 |

## 4. 当前场景清单与状态（2026-10-21）

**启用 24 个**：`01`–`22` + `22_zero_axis_template` + `24_axis_pitch`

最近一次全量（`C:\kvrun\final`，24 个）：**PASS=23 / FAIL=1**

| 场景 | 状态 | 备注 |
|---|---|---|
| `01`–`15`、`17`–`22`、`22_zero_axis_template`、`24_axis_pitch` | ✅ PASS | |
| `16_create_project` | ✅ PASS（已修）| UIA 点「新建项目」按钮会挂死（`FromHandle ... timed out`）→ 已改为直接走守卫 `Ctrl+N` |
| `22_zero_axis_template` | ⚠️ **偶发 flaky** | 套件里偶发 `KV_COMPILE_UNEXPECTED_MODAL: 转换结果`（上一场景残留模态）；**单跑必过** |
| `25_table_cell_edit` | ⏸ **disabled** | harness 只打开工程，未打开「轴控制设定」页 → `rows=1` |

> 说明：最近三次全量结果为 `23/24`、`23/24`、`23/24`，**每次失败的场景不同**（先后是
> `16_create_project` → `22_zero_axis_template`）→ 属于**桌面状态偶发**，不是固定缺陷；
> 每个失败项**单独重跑均 PASS**。

禁用原因写在各自 `scenario.json` 的 `disabled_reason` 字段里。

## 5. 本次修复的真实 bug（回归价值）

| 现象 | 根因 | 修法 |
|---|---|---|
| 4 个 `import` 场景失败 | `import_mnm_guarded.ps1` 的 WIP 改动（+72 行）✗ | 恢复 HEAD（WIP 存 `.wip-mixed`）|
| `11_structure_mutation` | `mutate_structure_definitions_guarded.ps1` WIP（+38 行）✗ | 恢复 HEAD |
| `02_fb_program_body` | 工作流多声明了一个类 `runner_child_pending` ✗ | 只保留 `runner_child_approved` |
| `10_export_mnm` | 重启后没等 KVS 退出 → 下一行看到"正在退出"的进程 ✗ | 杀全部匹配进程 + 等退出（≤20 s）|
| `13` / `20` | 我的测试路径过长 ✗ | 改短路径 |
| **新脚本一律被判 step 失败** | 进度日志用 `Write-Host` ✗ → 进 **stderr** ✗ → executor 判失败 | 改 `Write-Output`（stdout）|

## 6. 常用命令

```powershell
# 单场景
powershell -STA -NoProfile -ExecutionPolicy Bypass -File tests\kv-interface-regression\07_ethercat_nodes\run.ps1 -OutRoot C:\kvrun\s07

# 自包含用例
tests\axis-pitch\run.bat
tests\table-cell\run.bat

# 只看表格（不修改）
powershell -NoProfile -ExecutionPolicy Bypass -File scripts\runner_children\set_axis_table_cell_guarded.ps1 -OutDir C:\kvrun\t1 -ListOnly
```

## 7. 硬规矩

- **bat 必须纯 ASCII** ✗（中文参数会被 cmd 变成 `?`）→ 用脚本默认值
- **fixture 必须干净** ✗（残留 `execution_plan.json` 会让 harness 判 `STALE`）
- 改大表前**先关向导** ✗（模态会吞键盘导航）
- **失败先看截图** ✗ 不要先看退出码（见技能 `kv-ui-screenshot-verification`）
