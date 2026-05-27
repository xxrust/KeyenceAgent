---
name: kv-studio-kb-programming
description: Use when Codex needs to answer questions, design logic, write ST code, draft ladder-oriented logic, map devices, or troubleshoot behavior for KEYENCE KV STUDIO using the local LLM Wiki V2 query database instead of generic memory. Trigger for KV STUDIO programming requests involving PLC instructions, ST syntax, FB/FUN usage, device maps, buffer memory, motion control, socket communication, module manuals, or KEYENCE document codes such as TON, END, ENDH, SocketTCP_ActiveOpen, KV-XH, KV-XLE, DeviceMap, and soft-device allocation.
---

# KV Studio Wiki Programming

## Overview

Use the local KEYENCE LLM Wiki V2 database before writing or explaining KV STUDIO code. Treat `llm-wiki-v2-keyence/wiki.v2.cleaned.db` as the default source of truth for KEYENCE-specific syntax, module behavior, device maps, motion terminology, and manual evidence. If recall is weak or the result set is unexpectedly empty, rerun the same query against `llm-wiki-v2-keyence/wiki.v2.fixed.db` as a Wiki V2 fallback.

Use Wiki V2 as the only retrieval path described by this skill. Do not use the legacy `knowledge-base/knowledge.db` or `kb_tools/query_kb.py` path for this skill.

## Workflow

1. Classify the request before writing code.
   Typical buckets:
   - ST syntax or expressions
   - ladder or instruction semantics
   - module or buffer memory mapping
   - motion control, positioning, JOG, or servo setup
   - socket, EtherNet/IP, EtherCAT, Modbus, or serial communication
   - error handling, scan timing, conversion, or PLC verification

2. Query Wiki V2 before answering.
   Run `llm-wiki-v2-keyence/scripts/wiki_query.py ... --db llm-wiki-v2-keyence/wiki.v2.cleaned.db` from the htmlhelp workspace.
   Run at least one exact query and one semantic query when the request is non-trivial.
   If the user asks in Chinese, reuse the user's original wording as one of the queries.

3. Prefer evidence by source type.
   - `htmlhelp` / `chm`: instruction syntax, ST usage, FUN/FB semantics
   - `table`: device maps, soft-device allocation, buffer memory, address lookup
   - `dockinghelp`: motion and parameter-help fragments
   - `pdf`: broader manual context, constraints, timing, examples
   - `htmlnavi_meta`: navigation only, not substantive evidence

4. Synthesize only what Wiki V2 supports.
   Separate confirmed Wiki evidence, reasonable implementation assumptions, and open questions requiring CPU, module, axis, or model details.

5. Produce KV STUDIO-oriented output.
   Prefer exact instruction names, exact KEYENCE terminology, device names, module names, request/complete/error signals, and mapping notes.

## Wiki Query Patterns

Use short, iterative Wiki V2 searches instead of one oversized string.

### Exact Identifier Queries

```powershell
python .\llm-wiki-v2-keyence\scripts\wiki_query.py TON --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py ENDH --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py SocketTCP_ActiveOpen --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
```

### Semantic Queries

```powershell
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "赋值语句" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "全局变量 在哪里 设置" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "编译 验证" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
```

### ST And KV STUDIO Editor Queries

For ST programming requests, always query both the language construct and the KV STUDIO editor/workflow concept.

```powershell
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "ST 赋值语句" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "变量编辑器" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "变量设置" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
```

### Motion/JOG Queries

```powershell
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "JOG" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "JOG 正方向 负方向" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "定位 轴 软元件 分配" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
```

### Weak Recall Fallback

If `wiki.v2.cleaned.db` returns no useful evidence, rerun the exact query with `wiki.v2.fixed.db`:

```powershell
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "KV-XH DeviceMap" --db .\llm-wiki-v2-keyence\wiki.v2.fixed.db --limit 5 --evidence
```

## Programming Rules

- Do not answer KEYENCE-specific behavior from memory when Wiki V2 is available.
- Do not infer module addresses, relay numbers, buffer addresses, axis numbers, or signal names without Wiki evidence or explicit user-provided mapping.
- Do not present generic IEC 61131-3 syntax as KEYENCE-confirmed unless Wiki V2 evidence supports it.
- For KV STUDIO ST code, do not emit IEC-style declaration blocks such as `VAR ... END_VAR` inside the ST program body unless retrieved KEYENCE evidence explicitly supports that exact form.
- Treat variables as KV STUDIO project/editor objects by default: define global/local variables in the Variable Editor (`变量编辑器`) or variable settings (`变量设置`), then write only executable ST statements in the ST body.
- When writing ST that uses variables, separate the answer into `Variables/devices to register in KV STUDIO` and `ST program body`.
- If local variables are needed, say they must be registered/configured as local variables in KV STUDIO; do not imply they are declared inline in the ST text.
- For motion/JOG programs, do not invent relay addresses. Use placeholder names only after saying they must be mapped to the unit's actual JOG positive/negative direction relays from device allocation.
- If Wiki V2 results are ambiguous across module families, say which family each result appears to target.
- If the user asks for a program, include only the minimum assumptions needed to make the code executable.

## Answer Shape

For programming tasks, structure the response in this order:

1. Applicable assumption
   Example: CPU family, unit family, axis number, language mode, ST vs ladder.

2. Confirmed Wiki basis
   Mention retrieved titles or concepts briefly, not a long quote dump.

3. Variables/devices to register in KV STUDIO
   List variables, data types, and mapping placeholders. Do not put `VAR ... END_VAR` in the ST code unless Wiki evidence confirms inline declarations.

4. ST program body or ladder-oriented logic
   Provide executable statements tailored to KV STUDIO.

5. Integration notes
   Mention device allocation, request/complete/error bits, conversion, PLC verification, scan behavior, motion safety, and missing model details.

## Read More

Read `references/retrieval-playbook.md` only when the Wiki V2 query needs better recall, source prioritization, or ambiguity handling.
