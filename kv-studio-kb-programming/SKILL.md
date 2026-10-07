---
name: kv-studio-kb-programming
description: 当 Codex 需要基于本机 KEYENCE Wiki V2 资料回答 KV STUDIO 编程问题、设计 PLC 逻辑、写 ST、草拟梯形图思路、查询指令/FB/FUN、设备映射、缓冲存储器、运动控制、Socket、EtherNet/IP、EtherCAT、模块手册或 KEYENCE 文档术语时使用。禁止只凭通用 PLC 记忆回答 KEYENCE 专有语法和行为。
---

# KV STUDIO 知识库编程

## 合同

```yaml
source_of_truth:
  primary: llm-wiki-v2-keyence/wiki.v2.cleaned.db
  query_script: scripts/query_keyence_kb.py
  legacy_forbidden:
    - knowledge-base/knowledge.db
    - kb_tools/query_kb.py
must_query_before:
  - KEYENCE-specific syntax
  - FB_or_FUN_usage
  - device_or_buffer_map
  - motion_or_axis_behavior
  - socket_or_network_communication
  - module_manual_claim
```

使用本 skill 时，先查 Wiki V2，再写结论或代码。`kv-studio-operator` 的本机配置优先提供 `wiki_root`。
`--db`、`--query-script` 可显式覆盖；`KEYENCE_WIKI_DB`、`KEYENCE_WIKI_QUERY_SCRIPT` 的有效文件候选也优先于配置。
`KEYENCE_WIKI_ROOT` / `KEYENCE_KB_ROOT` 是配置路径不可用时的发现候选，不覆盖已有有效配置；
需要切换资料根时使用显式文件参数或 `--config` 指定本次配置，勿只改根目录环境变量后假定已切换。

当前项目的语义快照可作为“这个项目实际包含什么”的证据，例如程序树归属、变量类型、
FB 接口和单元/EtherCAT 配置；优先读取 `snapshot/project/`，必要时追溯 `text/` 和 `raw/`。
它不能替代 Wiki V2 对 KEYENCE 指令语法、产品约束和模块行为的确认。反过来，Wiki 的通用说明
也不能证明当前项目已经配置或声明了某个对象。回答时分别标注 Wiki 依据与项目快照依据。

## 工作流

1. 先分类请求：
   - ST 语法或表达式
   - 梯形图/指令语义
   - 模块、设备、缓冲存储器映射
   - 运动控制、定位、JOG、伺服
   - Socket、EtherNet/IP、EtherCAT、Modbus、串口通信
   - 错误处理、扫描周期、转换/编译、PLC 验证
2. 至少运行一次精确查询。复杂问题再运行一次语义查询。
3. 用户用中文提问时，保留用户原始中文词作为一个查询项。
4. 按证据类型排序：
   - `htmlhelp` / `chm`: 指令语法、ST 用法、FUN/FB 语义
   - `table`: 设备映射、软元件分配、缓冲存储器、地址表
   - `dockinghelp`: 运动和参数帮助片段
   - `pdf`: 手册上下文、约束、时序、示例
   - `htmlnavi_meta`: 只作导航，不作实质证据
5. 输出时区分：
   - Wiki 已确认
   - 当前实现假设
   - 仍需 CPU/模块/轴/型号确认的问题

## 查询模板

优先使用本 skill 的包装器，自动读取 operator 本机配置；配置文件允许 UTF-8 BOM。
`KEYENCE_WIKI_ROOT` 可直接指向包含 `scripts/wiki_query.py` 和 `wiki.v2.cleaned.db` 的目录。
路径含空格时为参数加引号；PowerShell 读取技能、JSON 或中文证据时显式使用 `-Encoding UTF8`。

```powershell
python <skill-root>\scripts\query_keyence_kb.py ANB --limit 3 --evidence
python <skill-root>\scripts\query_keyence_kb.py "功能块 自变量" --limit 3 --evidence
```

`--evidence` 直接输出命中 chunk 的完整正文、源标识和校验信息；`--json` 提供同样正文的结构化结果。
搜索及排序仍使用现有 Wiki V2 查询 CLI，正文按其返回的 `chunk_id` 从同一个 cleaned DB 只读取得。
库中的 `path` 可能指向未随数据库部署的 Markdown；包装器仅在文件实际存在时返回 `resolved_path`，
否则明确显示无可验证本机文件，正文的 `content_origin` 标明数据库、表及 chunk 标识。
不要把原始记录路径当作已存在文件，也不要因为 Markdown 缺失改查旧库或自行重建检索引擎。

已知 chunk 或需要减少错误召回时使用同一公开入口：

```powershell
python <skill-root>\scripts\query_keyence_kb.py --chunk-id "<returned-chunk-id>" --json
python <skill-root>\scripts\query_keyence_kb.py "<instruction-or-user-term>" --profile programming --source-type htmlhelp --source-type chm --limit 2 --evidence --strict
```

`--chunk-id` 与查询词互斥，不存在或正文为空时返回非零；`--strict` 让关键词无命中也返回非零。
`--source-type` 可重复指定，按资料类型缩小检索范围；`--profile` 使用 Wiki 已有的任务排序。
正文未截断，优先 `--limit 1` 或 `2` 再按需扩大；不要把检索工具的 snippet 当成完整正文。

为完整模块准备依据时，将本次成功查询输出保存在任务目录的证据文件中，记录查询词、
`chunk_id`、`source`、`source_anchor` 和适用 CPU/上下文。阅读同次返回的正文，确认所用
指令、BOOL 操作数和 FB IN/OUT/局部变量语义；标题相似或系统局部变量条目不能代替用户局部变量依据。
保留用户原始中文词，同时以 `LD`、`AND`、`ANB`、`OUT` 等精确标识分别检索。
提供给 operator 完整模块契约的 `evidence_paths` 应引用这些非空文件；文件存在仅证明依据可追溯，
不证明 MNM 可编译或运行行为正确。查询失败时保留错误并修复查询入口，不用空文件冒充证据。

以下直接入口适用于显式指定 Wiki V2 目录，仅用于检索导航；它的默认输出不包含完整正文，
`resolved_path` 也可能失效。正式取证优先用上述包装器；需要精确正文时把其 chunk 标识传给 `--chunk-id`：

```powershell
python .\llm-wiki-v2-keyence\scripts\wiki_query.py TON --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py ENDH --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py SocketTCP_ActiveOpen --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "ST 赋值语句" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "变量编辑器" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "JOG 正方向 负方向" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
```

弱召回时：

```yaml
weak_recall:
  actions:
    - split_query_into_exact_identifier_and_semantic_terms
    - try_user_original_wording
    - read: references/retrieval-playbook.md
  forbidden:
    - answer_from_generic_memory
    - switch_to_legacy_database
```

## 编程规则

- 不要用通用 IEC 61131-3 经验冒充 KEYENCE 已确认语法。
- ST 程序体中不要输出 `VAR ... END_VAR` 这类 IEC 声明块，除非 Wiki V2 明确证明 KV STUDIO 在该上下文接受。
- 默认把变量当作 KV STUDIO 工程/变量编辑器对象：先在全局/局部变量表中登记，再在 ST 程序体里只写可执行语句。
- 写 ST 时分开输出：
  - `需要在 KV STUDIO 登记的变量/设备`
  - `ST 程序体`
- 不要凭空发明模块地址、继电器号、缓冲地址、轴号或信号名。没有证据时用占位名，并说明必须按实际设备分配映射。
- 运动/JOG 程序必须说明正/负方向、请求、完成、错误等信号需要来自实际单元设备分配。
- 如果 Wiki V2 结果跨模块系列含义不同，明确标出每条证据对应的系列。

## 回答形状

```yaml
answer_order:
  - applicable_assumptions
  - confirmed_wiki_basis
  - variables_or_devices_to_register
  - st_body_or_ladder_logic
  - integration_notes
```

`confirmed_wiki_basis` 只简述检索到的标题/概念，不长篇复制资料。`integration_notes` 应覆盖设备分配、请求/完成/错误位、转换/编译、PLC 验证、扫描周期、运动安全和缺失型号信息。

## 参考

仅当需要改进检索、判断证据优先级或处理歧义时读取：

- `references/retrieval-playbook.md`
