# KV STUDIO Operator 脚本分层 Checklist

日期：2026-06-04

范围：验证 `scripts/script_manifest.json` 已分类的脚本是否完成 role 目录分离，并确认 legacy `scripts/mvp/*.ps1` 只作为兼容 wrapper。根目录中未纳入 manifest 的配置脚本、通用工具和旧入口不在本轮“已分离”结论内。

## 检查项

| 项 | 状态 | 证据 |
| --- | --- | --- |
| role 目录存在：`workflows`、`runner_children`、`guards`、`probes`、`gates`、`scaffold_tools` | 通过 | `ROLE_DIRECTORIES_OK workflows,runner_children,guards,probes,gates,scaffold_tools` |
| `scripts/script_manifest.json` 可解析，`layout_policy=role_directories_with_legacy_wrappers` | 通过 | `MANIFEST_PATHS_OK` |
| manifest 中每个声明路径都存在 | 通过 | `MANIFEST_PATHS_OK` |
| resolver 能解析代表性 workflow、runner child、guard、gate、scaffold tool、probe | 通过 | 样例解析到 `scripts\workflows`、`scripts\runner_children`、`scripts\guards`、`scripts\gates`、`scripts\scaffold_tools`、`scripts\probes` |
| 所有 `scripts/**/*.ps1` PowerShell 语法解析通过 | 通过 | `ALL_PARSE_OK count=58` |
| 新 role 路径 gate 可运行并返回 `ok=true` | 通过 | `scripts\gates\assert_kv_mvp_agent_boundary.ps1`、`scripts\gates\assert_kv_mvp_ui_guard_usage.ps1` |
| legacy wrapper 路径 gate 可运行并返回 `ok=true` | 通过 | `scripts\assert_kv_mvp_agent_boundary.ps1`、`scripts\assert_kv_mvp_ui_guard_usage.ps1` |
| `scripts/mvp/kv_ui_guard.ps1` 可 dot-source，且不 `exit` 调用进程 | 通过 | `MVP_GUARD_DOTSOURCE_OK command=Invoke-KvGuardedCtrlChord` |
| legacy `scripts/mvp/*.ps1` 文件为薄 wrapper | 通过 | `LEGACY_MVP_WRAPPERS_THIN_OK count=10` |
| `README.md`、`SKILL.md`、HTML 报告不把 `scripts/mvp` 写作正式入口 | 通过 | 残留扫描只剩两处 legacy wrapper 说明 |
| workflow 通过 resolver 调用 runner child，不复制 child UI 逻辑 | 通过（静态） | `scripts\workflows\*.ps1` 使用 `Resolve-KvStudioOperatorScriptPath` 解析 child/gate/scaffold tool；真实 UI 路径需另跑端到端 |
| 本轮未运行 KV STUDIO UI 端到端 | 已记录 | 本次只做结构分离与非 UI 验证 |

## 剩余分类边界

根目录仍存在未纳入 manifest 的脚本，例如配置类脚本、通用断言脚本、配置导入脚本和旧示例 runner。它们不能被本 checklist 自动认定为 customer workflow 或 runner child；后续要逐个补 manifest、补 resolver、补回归证据，再移动到 role 目录或保留为明确的根目录工具。
