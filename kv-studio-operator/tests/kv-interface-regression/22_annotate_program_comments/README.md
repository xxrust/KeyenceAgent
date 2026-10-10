# 22 程序体 × 软元件注释 join（非 UI，纯计算）

## 操作内容

调用 `scripts/workflows/annotate_kv_program_with_comments.ps1`，把 KV STUDIO 导出的注释表与已导出的
MNM 程序体做 join，产出**独立的**注释/覆盖率文件。程序体只读：MNM 文件在整个过程中保持字节不变，
测试会逐个文件比对 sha256 来证明这一点。

## 测试目标

验证 join 的四件事：设备键归一化（`MR0013`/`MR13`、`W012`/`W12` 是同一软元件且不改变进制）、
注释分类（手写 / 型号档 / 系统）、覆盖率口径（默认只统计用户程序体，库 FB 体另计）、
以及**不修改输入**。这是 21 号场景（UI 导出注释）之后的纯离线步骤，不需要桌面。

## 固定输入

`fixtures/JoinSample/` 是手工构造的确定性输入，命名与真实导出器一致：

| 文件 | 作用 |
|---|---|
| `comments.csv` | CP936 注释表；含补零设备名、空注释行（`T0020`）、型号档注释、系统区注释 |
| `程序__每次扫描执行型模块__Main__body.mnm` | UTF-16LE 程序体；含 `LD MR13`、`MOV.L W12 DM80`、`TMR 20 #5`、`LD T20`、`;MR106:=TRUE;`、`BOOKMARK` 标签 |
| `功能块__库__Sample_lib__body.mnm` | UTF-16LE 库 FB 体，只引用 `DM5000`，用于验证默认统计口径会排除它 |
| `JoinSample.kpr` | harness `fixture_copy` 需要的占位工程文件（本场景从不打开 KV STUDIO） |

## 执行方法

双击 `run.bat`，或运行 `run.bat -NoPause`。调用链为公共 runner → `annotate_kv_program_with_comments.ps1`
（workflow 包装）→ `annotate_kv_program_with_comments.ps1`（工具本体）。全程不启动 KVS。

## 通过标准

真实测试必须满足：`test_result.json` 与 `workflow/workflow_result.json` 为成功；
`workflow/coverage.json` 的 `scope=program`、`body_counts.program=1`、`body_counts.unknown=0`、`body_counts.library=1`；
`referenced_documentable=5`、`used_annotated=4`、`used_unannotated=1`、`annotated_unused=5`；
`used_unannotated` 恰为 `MR106`（`T20` 只计数、不算文档缺口）；
`annotated_unused_handwritten` 恰为 `DM860,MR9999`；
四个产物 `comments.tsv`/`usage.tsv`/`coverage.json`/`program_annotations.md` 都存在且非空；
`coverage.json` 记录了注释表与两个程序体的 sha256。

离线单元断言另见 `tests/test_kv_program_comment_join.ps1`（61 项，含"输入未被修改"的硬约束）。

## 日志与结果

输出位于 `../runs/22_annotate_program_comments_<时间戳>/`。计算结果在 `workflow/`；
被测项目副本（含被 join 的输入）在 `project/JoinSample/`；统一日志为 `workflow/run.log`。
