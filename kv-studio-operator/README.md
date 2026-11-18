# KEYENCE KV STUDIO 操作技能（kv-studio-operator）

用脚本**驱动 KV STUDIO 桌面**完成工程操作（创建工程、EtherCAT 从站、轴参数、编译、导出、快照、结构变更……），
每一步都有**守卫**（焦点/输入/证据）和**回归场景**。

> 本仓库是一个 **DSH skill**，通过 `.dsh/skills/` 下的 junction 暴露给 agent。
> 面向使用者的契约在 [`SKILL.md`](SKILL.md)；这里只讲**能力清单、怎么跑、怎么验收**。

---

## 1. 环境

| 项 | 值 |
|---|---|
| KV STUDIO | KV-X 使用 KVS12；Nano 本次实测 12.41.0.0，安装路径 `H:\Keyence\KVS11\KVS\Kvs.exe`；按完整工程路径绑定进程 |
| 共享样例工程 | `references\KVX样例程序_v100\KVX样例程序_v100.kpr`（31 轴 + EtherCAT 从站）|
| 测试运行目录 | 建议用**短路径**（如 `C:\kvrun\...`）——守卫有路径长度预算，超长会报 `KV_UI_GUARD_CHECKPOINT_PATH_TOO_LONG` |

---

## 2. 能力清单

| 能力 | 入口 | 状态 |
|---|---|---|
| 新建工程 | `scripts/workflows/create_kv_project.ps1` | ✅ |
| 编译 | `scripts/workflows/compile_kv_project.ps1` | ✅ |
| **EtherCAT 插从站 / 改节点地址** | `scripts/workflows/configure_kv_ethercat_nodes.ps1` | ✅ |
| **批量登录轴 + 坐标转换向导** | `scripts/workflows/complete_kv_axis_registration.ps1` | ✅ |
| **改轴参数（移动量/螺距）** | `scripts/workflows/set_kv_axis_pitch.ps1` | ✅ |
| **改轴控制大表单元格** | `scripts/workflows/set_kv_axis_table_cell.ps1` | ⚠️ 脚本可用，缺"导航到页"步骤（见 §5）|
| 结构变更 / 变量 / FB / ST / MNM 导入导出 / 快照 | `scripts/workflows/*.ps1` | ✅ |
| **KV Nano：脚本 / 梯形图 / 标号增删改查** | `scripts/workflows/manage_kv_nano_program.ps1` | 空项目编译、保存重开回读通过；用例 25 / 26 分别 32 / 59 项 |
| **KV Nano：完整程序计划** | `scripts/workflows/apply_kv_nano_program_plan.ps1` | 冻结完整 TSV 和源码，批量写入、编译、重开逐项比较；[交通灯示例](examples/nano-traffic-labels/README.md) |
| **KV Nano：工程快照** | `scripts/workflows/export_kv_nano_snapshot.ps1` | 九程序三单元副本通过；空项目交通灯 BAT 87 项；[范围与证据](references/nano-snapshot.md) |
| **KV Nano：单元 / 内置 Port0** | `scripts/workflows/manage_kv_nano_units.ps1` | NC32/NC1EP/NC16EXT 主表及增删改查，BAT 43 项通过；不含嵌套设定窗口 |
| **KV Nano：CPU 定位参数** | `scripts/workflows/manage_kv_nano_cpu_position.ps1` | 六页完整读取；I/O 输出模式与 JOG 四项写入、重开、恢复通过 |
| **KV Nano：MNM 导出** | `scripts/workflows/export_kv_project_mnm.ps1` | 本次实机通过，详见 [Nano 适配记录](references/nano-project-format.md) |
| **删除 EtherCAT 从站** | `scripts/runner_children/delete_ethercat_slave_guarded.ps1` | ❌ 未跑通（网络树是自绘控件，待用对象级键盘方案）|

---

## 3. 怎么跑

### 3.1 单个能力（bat 范例，双击即可）

```
examples\axis-registration\run.bat   插 2 个从站 + 登录 2 个轴 + 填螺距
examples\axis-table-edit\run.bat     改轴控制大表的某个单元格（对象级选中）
tests\axis-pitch\run.bat             改轴参数 + 断言 + 重开回读
tests\table-cell\run.bat             改大表单元格 + 整表 diff 断言
tests\kv-interface-regression\28_nano_snapshot\run.bat  空项目交通灯快照验收
import_kv_device_comments.bat        软元件注释表写回工程（导入 → 保存 → 回读 diff）
```

> ⚠️ **bat 必须纯 ASCII**：中文参数不要写进 `.bat`（cmd 会把它变成 `?`）；
> 用脚本默认值或让 `.ps1` 里带中文。

### Nano 单次快照

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File scripts/workflows/export_kv_nano_snapshot.ps1 `
  -ProjectPath C:\projects\Nano\Nano.kpr -OutDir C:\kvrun\nano_snap
```

输出目录须不存在且位于源工程目录之外。结果在 `snapshot/source_snapshot_manifest.json`，可读文件位于 `snapshot/project`，完整源文件与 MNM 位于 `snapshot/raw`。入口校验源哈希、关闭自己的副本并保留原有窗口；`ready` 要求全部必需读取和清理通过。读取已保存的离线工程，不采集 NC1EP 嵌套设定或 PLC 实时值。宏创建/导入尚未验证；KV-X 保持原路线。

### 3.2 全量回归（harness）

```powershell
# 一次性跑全部启用场景（每个场景自动起连拍截图）
powershell -NoProfile -ExecutionPolicy Bypass -File tests\run-all-with-shots.ps1 `
  -OutRoot C:\kvrun\final -Skip none -IntervalMs 1500
```

- 结果：`<OutRoot>\suite_result.json` + `<场景>\shots\f*.png`（每场景几十~几百帧 + `index.txt`）
- 单场景：`tests\kv-interface-regression\<场景>\run.bat`

**三种场景模式**（`scenario.json` 的 `project_mode`）：

| 模式 | 工程来源 | 用途 |
|---|---|---|
| `sample_copy`（默认）| 复制 `references\KVX样例程序_v100` | 绝大多数场景 |
| `fixture_copy` | 复制场景自带 `fixtures\` | **专用/异常工程**（只允许跑 `compile_kv_project.ps1`）|
| `new_project` | 从零新建 | 只给建工程流程 |

---

## 4. 三条硬规矩（都是踩过的坑）

1. **切机械配置会重置参数，并连带改坐标单位/模式** ✗
   → 必须先切类型，再填值；`坐标单位/坐标模式只能在「坐标转换计算」向导里改`，**不能在大表里改** ✗
2. **文本字段必须真实键盘输入** ✗（`WM_SETTEXT`/`ValuePattern.SetValue` 只改显示，不进模型）
   → 点进去 + `Ctrl+A` + 键入 + `Tab`；下拉框用 UIA `SelectionItem.Select` ✓
3. **`Write-Host` = stderr = step 失败** ✗
   → flat executor 把"stderr 非空"判为失败；子脚本的进度日志必须用 `Write-Output`（stdout）或写文件

---

## 5. 已知问题

| 问题 | 说明 | 修法 |
|---|---|---|
| `16_create_project` **flaky** | 「新建项目」对话框与 `Ctrl+N` 竞争，偶发 `Refusing Ctrl+N` | 该步应先判断对话框是否已开，已开则直接填表 |
| `25_table_cell_edit` **disabled** | harness 只打开工程，不打开「轴控制设定」页 → 复制到的是别的东西（`rows=1`）| 把 `set_axis_pitch_guarded.ps1` 的导航段移植到 `set_axis_table_cell_guarded.ps1` |
| **删除 EtherCAT 从站** 未实现 | 网络结构树是自绘控件，UIA 无节点 | 用"选中对象 + 键盘 DEL"方案（同 §4.1 的对象级思路）|

---

## 6. 对象级选中（重要设计决定）

**不要用像素坐标点单元格/行** ✗ —— 分辨率、缩放、字体一变就偏。

```
① 点一下控件（只是把焦点交给它，位置不重要 ✓）
② 用控件自己的选区导航：Ctrl+Home → Down×行 → Right×列   ← 选中的是"对象" ✓
③ Ctrl+C 读回当前格 → 校验指向 ✓
④ F2 → Ctrl+A → 键入 → Enter
⑤ Ctrl+A/C 整表 diff → 必须**恰好一行变化且索引=目标行** ✓
```

实测：`轴控制设定` 是**多轴并排表格**，选中**目标轴那一列**再点「坐标转换计算」，
向导才会是**该轴**（否则永远跟"当前轴"= 轴1）✓

---

## 7. 测试与证据

- **每个动作都截图**：`scripts\Capture-KvFrame.ps1`（单帧 / 连拍 `-Continuous -IntervalMs`）
- 截图**不影响流程**：GDI 读屏，不碰窗口/焦点；每帧约 120–200 ms，异常不抛出
- 失败时**先看图**（新的 skill `kv-ui-screenshot-verification` 把这个定成铁律）

详见 → [`tests/README.md`](tests/README.md)

## Nano 当前验收状态（2026-11-18）

- 空项目交通灯快照 BAT：**87 通过 / 0 失败**，核对框脚本、域脚本全文、全部计划梯形图指令、标号表、六页参数及产物哈希；见 [用例 28](tests/kv-interface-regression/28_nano_snapshot/README.md)。
- 语法/编码检查：292 个 PS1 文件零失败；本体覆盖检查 3 项通过。以上均为工程离线验收，未在实体 PLC 上验证。

## KV-X 历史验收状态（2026-11-01）

- 离线：16 suites / 175 cases（`tests/run_all.ps1`），**不包含 live UI**。
- 最近一次完整快照：`status=ready`；EtherCAT PDO 32/32；EIP 3 条连接 + 3 份软元件分配。
- 自动 1:1 导入：`false`（EtherCAT per-device parameters 只有截图）；人工复刻：`true`。
- live 验收（EtherCAT 节点、EIP 读写、轴参数、13 快照 bat）必须在目标 KV STUDIO 环境单独执行，并在运行目录保留结果。
- 已知边界：`高级设定` 无结构化导出路径（UIA/剪贴板/菜单/OCR 均失败），只保留截图。
> 机器可读状态汇总见 [references/capability-status.generated.md](references/capability-status.generated.md)（由 manifest/ontology/最近测试与快照生成）。
