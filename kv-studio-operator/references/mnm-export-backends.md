# MNM 导出：一入口 + 两后端（契约与合并判据）

状态：**设计定稿，待实现**（2026-11-16）。触发原因：KV Nano 工程（`纯48` / KV-NC32）上
`export_mnm_browse_default_folder_guarded.ps1` 实测卡住，而人工导出可用。

## 1. 为什么要两套实现

| 事实 | 证据 |
|---|---|
| KV-X / KV-8000 工程：有 `WsTreeEnv.xml`、程序在 `All.prgx` | 台州 v10 / KVX 样例 |
| KV Nano 工程：**没有 `WsTreeEnv.xml`**，每个程序一个 `.mod` | `纯48.zip` 实测，见 `nano-project-format.md` |
| Nano 导出多一个「选择注释类型」对话框 | 2026-11-16 手动 Alt+F→R→S 截屏 |
| 现有 runner 在 Nano 上卡在导出前的保存步骤（`Save-KvExportProject`），根本没走到按键 | `snapshot/nano48/raw/mnm/run.log` 只到 `export_step: start` |

所以：**实现分成两套**（动作序列不同），但**契约必须一套**，否则就是第二个 R03。

## 2. 结构

```
export_mnm_guarded.ps1                ← 唯一 runner 名称（workflow/manifest 不变）
  ├─ 判定 CPU 家族与能力（见 §2.1）
  ├─ 选定后端，记录 backend / backend_reason / cpu_model（日志 + 结果字段）
  ├─ 调 backends/export_mnm_kvx.ps1   （现有逻辑迁移）
  └─ 调 backends/export_mnm_nano.ps1  （新增：菜单 → 选择注释类型 → 文件夹）
```

### 2.1 后端判定（**正确设计**）

按 **CPU 家族**判定，工程布局只做交叉校验：

判定顺序（拿到第一个即用，并写进结果 `cpu_model` + `cpu_source`）：

| 顺序 | 来源 | 证据 |
|---|---|---|
| 1 | `WsTreeEnv.xml` 的 CPU 节点，如 `[0] KV-X520` | `references/KVX样例程序_v100/WsTreeEnv.xml:4411` |
| 2 | KVS 运行时窗口标题 `[编辑器: <CPU>]`，如 `[编辑器: KV-NC32]` | 2026-11-16 `纯48` 实测 |
| 3 | KV STUDIO「CPU 系统设定」表格内的型号（UIA 读） | 未实测 |
| 4 | 兜底：布局（有 `*.mod` 且无 `WsTreeEnv.xml`） | 仅当 1-3 全拿不到时使用，且必须记 `cpu_source=layout_fallback` 告警 |

家族映射：`KV-NC*` / `KV-N*`（KV-N14/N24/N40/N60/NC32T）→ `nano`；`KV-X*`、`KV-8000/7000/5000/3000/1000` → `kvx`。

### 2.2 当前临时实现（**TEMP，已知不正确，必须替换**）

> 用户 2026-11-16 明确：按工程布局分发不对，临时可以，后期要改。

第一版实现先用布局判定：`有 WsTreeEnv.xml → kvx`；`只有 *.mod → nano`。原因只是它**零成本、能立刻跑通**，
不代表判据正确：布局是工程保存方式的**结果**，不是身份；同型号可能因版本不同出现另一套布局，反之亦然。

替换成 §2.1 的完成判据（全部满足才可删掉 TEMP 分支）：

1. 结果 JSON 里有真实 `cpu_model` + `cpu_source`，且来自 §2.1 的 1-3 任一来源；
2. 布局只用于"型号与布局是否互相矛盾"的告警（矛盾时以型号为准并记录 `layout_mismatch=true`）；
3. 契约测试含一条反例：**布局像 nano 但型号是 KV-X**（或反向），后端选择必须跟随型号。

后端只允许写"菜单路径 + 对话框序列 + 窗口标题断言"，以下全部来自公共 helper，不许复制：

- UI guard / 前台锁定 / 窗口快照（`kv_ui_guard.ps1` 已有能力）
- 结果写入 `browse_folder_export_result.json`
- `.mnm` 产物发现（按 `runStart` 时间窗）
- 日志格式与 `run_id`

## 3. 输出契约（两后端逐字段一致）

```json
{
  "ok": true,
  "backend": "kvx | nano",
  "backend_reason": "WsTreeEnv.xml present | *.mod layout only",
  "error_code": "",
  "message": "",
  "project_path": "...",
  "export_dir": "...",
  "out_dir": "...",
  "process_id": 1234,
  "launched_by_runner": true,
  "mnm_files": ["C:\\...\\Main.mnm"],
  "mnm_file_count": 1,
  "dialogs_handled": ["选择注释类型", "文件夹选择"],
  "generated_at": "2026-11-16T..."
}
```

失败码（两后端共用，不许新造同义词）：

| 码 | 含义 |
|---|---|
| `KV_EXPORT_BACKEND_UNSUPPORTED` | 探测不出布局 / 后端不支持该工程 |
| `KV_EXPORT_BROWSE_FOLDER_DIALOG_MISSING` | 菜单点完但没等到文件夹对话框 |
| `KV_EXPORT_BROWSE_FOLDER_OK_MISSING` | 对话框没找到确定按钮 |
| `KV_MNM_EXPORT_NO_FILES` | 对话框走完但时间窗内没有新 `.mnm` |
| `KV_EXPORT_PRE_SAVE_TIMEOUT` | 导出前保存/等待超时（新增，专治本次 hang） |

## 4. 能力矩阵

| 能力 | kvx 后端 | nano 后端 |
|---|---|---|
| 助记符导出（`Alt+F,R,S`） | ✅ | ✅（多一步「选择注释类型」） |
| 助记符导入 | ✅ | 待验证 |
| 工程文本快照（含树） | ✅（`WsTreeEnv.xml`） | ❌（无树；只能逐程序导出） |
| 编译结果读取 | ✅ | 待验证 |
| 工程清点（模块列表） | ✅ | ⚠️ 需 Nano 分支（`.mod` + `CpuMb2.inf`） |

## 5. 硬性约束（写进实现，不靠自觉）

1. **一个 runner 名称**：workflow/manifest 只认 `export_mnm_guarded.ps1`，后端文件名不出现在计划里；
2. **所有等待必须有上限**：`Save-KvExportProject` 这类"保存并等标题变化"的循环必须带 timeout，超时即 `KV_EXPORT_PRE_SAVE_TIMEOUT`；
3. **进关键动作前先落日志**：日志点要在动作之前，保证"卡住"可区分阶段（本次就是因为日志在按键之后，无法判断卡在哪）；
4. **对话框序列数据化**：每后端声明 `[{title_pattern, action}`，action ∈ {accept, choose(default), wait}`，不许散落 if；
5. **禁止后端之间复制函数**：共用逻辑上移，违反即视为缺陷（对应 R02/R06 教训）。

## 6. 合并判据（满足全部才合并）

1. 同一批 fixture（KV-X 一份、Nano 一份）在两个后端上产出**逐字段同构**的结果 JSON（除 `backend*`/时序字段）；
2. 失败码集合一致，且每个失败码在两后端都有触发用例；
3. 差异已收敛为"对话框序列表 + 菜单路径"两份配置数据，代码里不再有 `if ($backend -eq ...)` 分支；
4. 契约测试里至少 1 个用例两个后端都通过。

未满足前保持分叉，但契约、helper、失败码共享。

## 7. 落地顺序

1. 抽公共 helper + 结果 schema（不改行为）；
2. 迁移 kvx 后端（行为不变，跑一次 KV-X 工程导出验证）；
3. 新增 nano 后端（`选择注释类型` → 文件夹），用 `纯48` 验证；
4. 补契约测试（本文件 §6 第 1、2 条）；
5. 清点加 Nano 分支（`.mod` + `CpuMb2.inf`），修 `project_inventory` 的 `not_found` 误判。
