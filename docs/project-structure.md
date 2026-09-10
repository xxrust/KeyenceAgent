# 项目结构

运行入口和脚本分类以 [operator manifest](../kv-studio-operator/scripts/script_manifest.json)
为准。用 `get_kv_capabilities.ps1` 查询实际文件和参数，不从目录中的文件名猜入口。

```text
KeyenceAgent/
  kv-studio-kb-programming/       Wiki 查询
  keyence-plc-programmer/         PLC 程序语义与非 UI 校验
  kv-studio-operator/
    SKILL.md                     agent 操作入口
    scripts/
      script_manifest.json       唯一执行清单和结果契约
      workflows/                 公开操作
      workflow_tools/            计划、执行器、结果收集
      runner_children/           内部 UI 实现
      guards/                    输入与焦点保护
      gates/                     非 UI 门禁
      scaffold_tools/            可选完整程序示例
      harnesses/                 复现/重复回归
    references/                  schema、操作契约和样例项目
  tests/                         回归测试与隔离夹具
  scripts/                       安装链接、系统审计和仓库检查
  docs/                          使用与维护说明
  archive/                       退役源码文本；不安装、不执行
```

维护时安装目录链接到仓库源；`install_keyence_dev_links.ps1` 创建链接并备份原目录，
`assert_keyence_dev_links.ps1` 检查漂移。下载版安装流程见 [installation.md](installation.md)。
配置和 DPAPI 凭据位于用户 AppData，不能进入源码或日志。

任务数据按 source_snapshot、work、validation 保存；工作流运行目录保存
execution_plan.json、run.log、workflow 结果及步骤 receipt。每次调用使用新的输出目录。
历史结果可以查询，不作为当前代码的通过证明。迁移旧目录时保留原路径到归档路径的映射。

完整程序示例使用 scaffold.model.json；这不是修改一张变量表的强制前提。
当前重整进度和已知验证范围见 [system-reliability-plan.md](system-reliability-plan.md)。
