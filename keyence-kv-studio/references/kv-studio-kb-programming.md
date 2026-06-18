# kv-studio-kb-programming

> 本文由原 kv-studio-kb-programming/SKILL.md 转为统一入口 skill 的 reference。路径按 keyence-kv-studio 包内结构解析。

# KV STUDIO 知识库编程

## 合同

```yaml
source_of_truth:
  primary: llm-wiki-v2-keyence/wiki.v2.cleaned.db
  query_script: scripts/kv-studio-kb-programming/query_keyence_kb.py
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

使用本 skill 时，先查 Wiki V2，再写结论或代码。`kv-studio-operator` 的本机配置优先提供 `wiki_root`；命令行参数和 `KEYENCE_WIKI_*` 环境变量仍可覆盖。

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

- `references/kv-studio-kb-programming/retrieval-playbook.md`
