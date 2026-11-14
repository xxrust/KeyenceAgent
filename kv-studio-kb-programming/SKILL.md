---
name: kv-studio-kb-programming
description: 当 Codex 需要基于本机 KEYENCE 知识库（Wiki v3：手册 + 本体卡片 + 实测经验）回答 KV STUDIO 编程问题、设计 PLC 逻辑、写 ST、草拟梯形图思路、查询指令/FB/FUN、设备映射、缓冲存储器、运动控制、Socket、EtherNet/IP、EtherCAT、模块手册或 KEYENCE 文档术语时使用。禁止只凭通用 PLC 记忆回答 KEYENCE 专有语法和行为。
---

# KV STUDIO 知识库编程

## 合同

```yaml
source_of_truth:
  # 唯一运行时知识库（2026-11-14 起）：仓库内 dist/kb-v3m-*/wiki.v3m.db
  # 只有这一个库；V2 cleaned DB 与 wiki.v3.db 已删除，不再提供回退。
  primary: dist/kb-v3m-*/wiki.v3m.db        # 清洗切块 + 混合索引 + 本体卡片（kb-pipeline 构建）
  query_script: scripts/kb_search.py
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

使用本 skill 时，先查知识库，再写结论或代码。唯一库路径按 `--db` > `KEYENCE_WIKI_V3_DB` >
operator 配置 `wiki_db` > 配置 `wiki_root`\v3\wiki.v3m.db > 仓库内 `dist/kb-v3m-*/wiki.v3m.db` 解析。库由仓库内 `kb-pipeline/`
构建并用 benchmark 验收（见 `kb-pipeline/PROGRESS.md`），不要自行重建检索引擎。

当前项目的语义快照可作为“这个项目实际包含什么”的证据，例如程序树归属、变量类型、
FB 接口和单元/EtherCAT 配置；优先读取 `snapshot/project/`，必要时追溯 `text/` 和 `raw/`。
它不能替代知识库对 KEYENCE 指令语法、产品约束和模块行为的确认。反过来，知识库的通用说明
也不能证明当前项目已经配置或声明了某个对象。回答时分别标注知识库依据与项目快照依据。

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
   - `textbook`: 基恩士教材（程序标准化、ST 语言实例、运动控制篇）——**讲方法与步骤**，
     可作为“怎么写/怎么组织”的依据，但不替代手册对语法和约束的说明
   - `program_example`: 官方示例程序（SH04PL 轴控 20 例、常用主模块 44 例）——**参考实现**
   - `project_snapshot`: 标准化工程 `KVX样例程序_v100`——真实 FB 接口/局部变量/程序体与程序分层，
     回答“标准程序怎么写/怎么分层/某个 FB 内部怎么实现”时用它
   - `kb_note`: 本库维护者写的说明（变量命名规范对照、资料构成、分层结构），范围窄但可直接引用
   - `htmlnavi_meta`: 只作导航，不作实质证据
   手册讲**语法与约束**，教材讲**方法与步骤**，示例/快照是**参考实现**：三者不能互相替代，
   也不要用示例程序的写法去否定手册。变量命名规范有两套（教材 `x/ui/…` versus 样例程序
   `b/inst/str`），`kb_note` 里有对照，回答命名问题时说明用的是哪一套。
5. 输出时区分：
   - Wiki 已确认
   - 当前实现假设
   - 仍需 CPU/模块/轴/型号确认的问题

## 查询模板

```powershell
# 自然语言或标识符都可以，中文口语直接问；先输出匹配卡片，再输出证据块
python <skill-root>\scripts\kb_search.py "伺服回原点怎么写" -k 5
python <skill-root>\scripts\kb_search.py "MC_MoveAbsolute" -k 3 --text
# 已知名称时直接取卡片（FB/FUN 签名、参数方向/类型、动作说明、证据 chunk_id）
python <skill-root>\scripts\kb_search.py --card MC_Home
# 结构化输出（cards + results，含完整正文、chunk_id、source、series）
python <skill-root>\scripts\kb_search.py "KV-XH 软元件分配" --json
```

结果怎么用：

- `[card:FunctionBlock]` / `[card:Instruction]`：从官方帮助的结构化表格解析（confidence=manual），
  可直接作为签名和参数依据；写代码前仍用 `--text` 或 `--json` 读一次其证据正文。
- `[card:ErrorCode]` / `[card:FieldFinding]`：实机验证的经验（confidence=field_verified），
  `origin` 指向记录它的 skill 文档；优先于手册泛述，但只在相同 KVS 版本/CPU 前提下成立。
- `[card:Concept]`（confidence=extracted）只是“口语 → 指令名”的导航，不是证据。
- 每条结果带 `chunk_id`、`source`、`series`。series 为空表示文档未标明系列，跨系列使用前要确认。
- 退出码：0 有结果，2 无结果，4 库不存在（此时直接报缺库，不要退回旧库或凭记忆作答）。
- 向量通道需要 torch + sentence-transformers 和本地 bge-m3；模型目录通过 `KB_MODEL_DIR` 显式配置，未配置时只使用模型 ID 的客户端解析，不依赖固定盘符；
  不可用时自动退回不含向量的混合检索。带向量冷启动约 8 秒，`--fast` 跳过向量约 1 秒，
  但口语化问题召回明显下降（120 条手册盲测 hit@5 0.89 → 0.68，50 条旧 holdout 0.96 → 0.94）。
  先用默认模式问口语问题，已知精确名称时用 `--card` 或 `--fast`。
- 检索库只有 `dist/kb-v3m-*/wiki.v3m.db` 一个（PDF 乱码页用 MinerU 文本替换，且补齐了 card 与向量）；
  `wiki.v3.db` 已删除；不要再引用它，也不要用 `--db` 指向旧库。

为完整模块准备依据时，将本次查询的 `--json` 输出保存在任务目录的证据文件中，记录查询词、
`chunk_id`、`source` 和适用 CPU/上下文。阅读返回的正文，确认所用指令、BOOL 操作数和
FB IN/OUT/局部变量语义；标题相似或系统局部变量条目不能代替用户局部变量依据。
提供给 operator 完整模块契约的 `evidence_paths` 应引用这些非空文件；文件存在仅证明依据可追溯，
不证明 MNM 可编译或运行行为正确。查询失败时保留错误并修复查询入口，不用空文件冒充证据。

旧入口 `query_keyence_kb.py`（Wiki V2）已随 V2 库删除而失效，仅作历史参考，不要作为回退
（benchmark holdout hit@5 = 0.14），只在 v3 库不可用时使用。

弱召回时：

```yaml
Legacy note: `query_keyence_kb.py` is an explicit V2 compatibility tool only when a V2 database path is supplied; it is never an automatic fallback for the v3m runtime.

weak_recall:
  actions:
    - split_query_into_exact_identifier_and_semantic_terms
    - try_user_original_wording
    - try_keyence_manual_wording   # 例：回原点→原点复归，拼接→字符串结合
    - read: references/retrieval-playbook.md
  forbidden:
    - answer_from_generic_memory
    - switch_to_legacy_database
```

## 编程规则

- 不要用通用 IEC 61131-3 经验冒充 KEYENCE 已确认语法。
- ST 程序体中不要输出 `VAR ... END_VAR` 这类 IEC 声明块，除非手册明确证明 KV STUDIO 在该上下文接受。
- 默认把变量当作 KV STUDIO 工程/变量编辑器对象：先在全局/局部变量表中登记，再在 ST 程序体里只写可执行语句。
- 写 ST 时分开输出：
  - `需要在 KV STUDIO 登记的变量/设备`
  - `ST 程序体`
- 不要凭空发明模块地址、继电器号、缓冲地址、轴号或信号名。没有证据时用占位名，并说明必须按实际设备分配映射。
- 运动/JOG 程序必须说明正/负方向、请求、完成、错误等信号需要来自实际单元设备分配。
- 如果检索结果跨模块系列含义不同，明确标出每条证据对应的系列。

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
