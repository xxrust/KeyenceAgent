# 内置样例项目

本 reference 定义 skill 内的 KV STUDIO 样例项目。测试、示例和回归命令使用 `SkillRoot` 派生路径，避免引用个人工作区、桌面、下载目录或外部绝对项目路径。

```yaml
sample_project:
  id: kvx_sample_v100
  root: assets\kv-studio-operator\KVX样例程序_v100
  project_file: assets\kv-studio-operator\KVX样例程序_v100\KVX样例程序_v100.kpr
  purpose:
    - example_architecture
    - inventory_export_fixture
    - project_replication_reference
    - non_destructive_workflow_input
```

```powershell
$SampleProjectRoot = Join-Path $SkillRoot 'assets\kv-studio-operator\KVX样例程序_v100'
$SampleProjectPath = Join-Path $SampleProjectRoot 'KVX样例程序_v100.kpr'
```

使用规则：

- 将样例项目复制到 disposable work root 后再执行会修改项目的 workflow。
- 只读解析、inventory 导出、结构识别可以直接读取样例目录。
- 输出目录使用调用方传入的 `OutDir`、`ExportDir` 或 workflow run root。
- 样例项目用于验证脚本能力，不代表客户项目的固定硬件配置。
