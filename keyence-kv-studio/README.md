# KEYENCE KV STUDIO 统一入口

这个 skill 是 KEYENCE KV STUDIO 的统一入口。`SKILL.md` 负责路由；编程、知识库和桌面操作模块的核心说明放在 `references/`；可执行脚本放在 `scripts/`。

## 验证范围

已验证目标环境：

- Windows 10
- Windows 11
- KEYENCE KV STUDIO KVS12

KV STUDIO 本身只适用于 Windows。其他 KV STUDIO 版本可能可用，但当前未验证。

## 结构

```text
+---------------------------+
| keyence-kv-studio         |
| 统一入口 / 路由            |
+-------------+-------------+
              |
              +--> kv-studio-kb-programming
              |    references/kv-studio-kb-programming.md
              |    scripts/kv-studio-kb-programming/
              |    KEYENCE Wiki V2 查询、指令/FB/模块/协议事实
              |
              +--> keyence-plc-programmer
              |    references/keyence-plc-programmer.md
              |    scripts/keyence-plc-programmer/
              |    ST、梯形图、MNM、变量、FB、源码快照、编译修复
              |
              +--> kv-studio-operator
                   references/kv-studio-operator.md
                   scripts/kv-studio-operator/
                   KV STUDIO workflow、导入导出、变量粘贴、转换/编译
```

## Codex 如何读取

Codex 会先通过 `SKILL.md` 的 `name` 和 `description` 触发这个入口。入口触发后，Codex 读取 `SKILL.md` 中的路由规则，再按任务类型读取 `references/*.md` 中的细节。

`scripts/` 保存配套脚本。打包、迁移或换 session 时，只需要携带 `keyence-kv-studio` 一个目录。

`references/routing.md` 保存更细的任务分类规则。

## 路由表

| 用户任务 | 读取的 reference | 关键规则 |
| --- | --- | --- |
| 查询 KEYENCE 指令、FB、FUN、软元件、缓冲存储器、模块、EtherNet/IP、EtherCAT | `kv-studio-kb-programming` | 先查本机 Wiki V2，再输出结论 |
| 写 ST、改梯形图、生成/修复 MNM、设计变量、设计用户 FB | `keyence-plc-programmer` | 先建立变量和 FB 复用边界，再生成源码 |
| 打开 `.kpr`、创建项目、导入/导出 MNM、导入变量、转换/编译、复制转换结果 | `kv-studio-operator` | 只运行 manifest 中 `customer_callable=true` 的入口 |
| 复刻或修复现有项目 | 三者组合 | 先导出新鲜快照，再改源码，最后用 workflow 验证 |
| PLC 扩展单元、EtherNet/IP、EtherCAT、轴设定等项目配置 | `kv-studio-kb-programming` + `kv-studio-operator` | 先确认事实，再要求 manifest 中存在匹配的 `customer_workflow`；缺失时报 `ROUTE_RESEARCH_REQUIRED` |

## 典型流程

```text
+----------------------+
| User request          |
+----------+-----------+
           |
           v
+----------------------+
| keyence-kv-studio    |
| classify task         |
+----------+-----------+
           |
           +--> Need KEYENCE fact?
           |    +--------------------------+
           |    | kv-studio-kb-programming |
           |    +--------------------------+
           |
           +--> Need source or variables?
           |    +--------------------------+
           |    | keyence-plc-programmer   |
           |    +--------------------------+
           |
           +--> Need KV STUDIO operation?
                +--------------------------+
                | kv-studio-operator       |
                +--------------------------+
```

## 边界

KV STUDIO 桌面操作由 `scripts/kv-studio-operator` 的 workflow 拥有。客户态 agent 读取 `scripts/kv-studio-operator/script_manifest.json`，选择已发布入口，运行后读取同次产物和结果文件。

PLC 源码、变量、FB 和 MNM 的设计由 `keyence-plc-programmer` 拥有。KEYENCE 专有事实由 `kv-studio-kb-programming` 查询确认。

项目配置能力以 `kv-studio-operator` manifest 为准。没有客户态 workflow 的配置项进入研发态突破，而不是在客户态临时探索 UI。

## 打包边界

```text
keyence-kv-studio/
  SKILL.md
  README.md
  agents/openai.yaml
  references/
    routing.md
    kv-studio-kb-programming.md
    keyence-plc-programmer.md
    kv-studio-operator.md
    kv-studio-kb-programming/
    keyence-plc-programmer/
    kv-studio-operator/
  scripts/
    kv-studio-kb-programming/
    keyence-plc-programmer/
    kv-studio-operator/
  assets/
    kv-studio-operator/
      KVX样例程序_v100/
```

打包目标是上面的整个 `keyence-kv-studio/` 目录。说明文档、脚本、manifest、references、assets 和样例项目随目录一起移动。
