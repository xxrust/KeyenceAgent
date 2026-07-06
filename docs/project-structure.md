# 项目结构说明

本文档说明 KeyenceAgent 仓库的目录结构和文件组织。

## 仓库根目录

```
KeyenceAgent/
├── README.md                       # 项目主页（中文）
├── README.en.md                    # 英文版说明
├── README.ja.md                    # 日文版说明
├── setup_keyence_agent.ps1         # 一键安装脚本
├── LICENSE                         # 开源许可证
│
├── docs/                           # 文档目录
│   ├── quick-start.md              # 5分钟快速开始
│   ├── installation.md             # 详细安装指南
│   ├── configuration.md            # 配置说明
│   ├── guide/                      # 使用指南
│   │   ├── new-project.md
│   │   ├── repair-project.md
│   │   ├── function-blocks.md
│   │   ├── variables.md
│   │   └── troubleshooting.md
│   ├── architecture/               # 架构文档
│   │   ├── overview.md
│   │   ├── scaffold-model.md
│   │   ├── runner-contract.md
│   │   └── route-governance.md
│   ├── dev/                        # 开发者文档
│   │   ├── contributing.md
│   │   ├── add-workflow.md
│   │   ├── debugging.md
│   │   └── testing.md
│   └── images/                     # 文档图片
│       ├── architecture.png
│       └── workflow.png
│
├── kv-studio-kb-programming/       # Skill 1: 知识库查询
│   ├── SKILL.md                    # Skill 定义
│   ├── agents/                     # 子智能体
│   ├── references/                 # 知识库索引
│   └── scripts/                    # 辅助脚本
│
├── keyence-plc-programmer/         # Skill 2: 程序设计
│   ├── SKILL.md                    # Skill 定义
│   ├── agents/                     # 子智能体
│   ├── references/                 # 设计参考
│   └── scripts/                    # 渲染器脚本
│
└── kv-studio-operator/             # Skill 3: KV STUDIO 操作
    ├── SKILL.md                    # Skill 定义
    ├── scripts/                    # 自动化脚本
    │   ├── script_manifest.json    # 脚本清单
    │   ├── workflow/               # 工作流
    │   ├── workflow_tool/          # 工作流工具
    │   ├── runner_children/        # 原子操作
    │   ├── guards/                 # UI 守卫
    │   ├── gates/                  # 静态门禁
    │   └── probes/                 # 探针工具
    ├── references/                 # 参考文档
    │   ├── mvp-runner-contract.md
    │   ├── ui-guard-contract.md
    │   ├── variable-editor.md
    │   ├── capability-status.md
    │   ├── sample-project.md
    │   ├── project-configuration.md
    │   ├── fb-filter.md
    │   └── project-replication.md
    └── templates/                  # 项目模板
```

## 核心目录说明

### 📚 文档目录 (`docs/`)

用户文档和开发者文档的集中位置。

```
docs/
├── quick-start.md          # 新用户的第一站
├── installation.md         # 详细安装步骤
├── configuration.md        # 配置文件说明
├── guide/                  # 按场景组织的使用指南
├── architecture/           # 深入理解系统设计
└── dev/                    # 贡献者和维护者文档
```

**适用对象：**
- `quick-start.md` → 所有新用户
- `guide/` → 日常使用者
- `architecture/` → 高级用户和贡献者
- `dev/` → 开发者

### 🔧 Skills 目录

三个独立的 Codex skill，各司其职。

#### `kv-studio-kb-programming/`

**职责：** 查询 KEYENCE 知识库

```
kv-studio-kb-programming/
├── SKILL.md                # Skill 定义（AI 读取）
├── agents/                 # 子智能体定义
├── references/             # 知识库索引和缓存
└── scripts/                # 查询辅助脚本
    └── query_wiki.ps1
```

**关键文件：**
- `SKILL.md` - 定义 skill 的触发条件和能力
- `references/` - 知识库索引，加速查询

#### `keyence-plc-programmer/`

**职责：** 设计 PLC 程序

```
keyence-plc-programmer/
├── SKILL.md                # Skill 定义
├── agents/                 # 子智能体
│   ├── scaffold-designer/  # 脚手架设计
│   └── mnm-generator/      # MNM 生成
├── references/             # 设计参考
│   ├── scaffold-schema.json
│   ├── mnm-syntax.md
│   └── variable-rules.md
└── scripts/                # 渲染器
    ├── render_scaffold.ps1
    └── validate_model.ps1
```

**关键文件：**
- `references/scaffold-schema.json` - 脚手架模型的 JSON Schema
- `scripts/render_scaffold.ps1` - 将模型转换为 KV STUDIO 文件

#### `kv-studio-operator/`

**职责：** 操作 KV STUDIO

```
kv-studio-operator/
├── SKILL.md                # Skill 定义
├── scripts/
│   ├── script_manifest.json        # 所有脚本的索引
│   ├── workflow/                   # 客户态工作流
│   │   ├── run_kv_mvp_scaffold.ps1
│   │   └── run_kv_mvp_repair.ps1
│   ├── workflow_tool/              # 工作流引擎
│   │   └── invoke_kv_flat_execution_plan.ps1
│   ├── runner_children/            # 原子操作
│   │   ├── create_new_project.ps1
│   │   ├── import_mnm.ps1
│   │   └── paste_variables.ps1
│   ├── guards/                     # UI 守卫库
│   │   ├── focus_guard.ps1
│   │   └── popup_handler.ps1
│   ├── gates/                      # 静态门禁
│   │   ├── checklist_gate.ps1
│   │   └── snapshot_gate.ps1
│   └── probes/                     # 研发工具
│       └── window_probe.ps1
├── references/                     # 参考文档
└── templates/                      # 项目模板
```

**关键文件：**
- `script_manifest.json` - AI 从这里选择入口脚本
- `workflow/` - AI 可直接调用的工作流
- `references/` - 详细的技术文档

### 📦 安装脚本

`setup_keyence_agent.ps1` - 一键安装脚本

**功能：**
1. 复制 3 个 skills 到 Codex 目录
2. 创建配置文件
3. 设置环境变量
4. 存储凭据（可选）
5. 验证安装

**使用方法：**
```powershell
# 完整安装
.\setup_keyence_agent.ps1

# 只更新 skills
.\setup_keyence_agent.ps1 -Configure skills

# 查看状态
.\setup_keyence_agent.ps1 -Status

# 查看帮助
.\setup_keyence_agent.ps1 -h
```

## 运行时生成的文件

### 配置文件

**位置：** `%APPDATA%\Codex\kv-studio-operator\`

```
%APPDATA%\Codex\kv-studio-operator\
├── config.json         # 主配置文件
└── credentials.xml     # 加密的凭据（可选）
```

**config.json 示例：**
```json
{
  "kvs_exe": "C:\\Program Files\\KEYENCE\\KV STUDIO\\Kvs.exe",
  "work_root": "C:\\Temp\\KeyenceWork",
  "wiki_root": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\...",
  "admin_user": "Administrator",
  "runner_timeout_seconds": 300
}
```

### 工作目录

**位置：** 配置文件中的 `work_root`

```
work_root/
├── project_name_1/
│   ├── project_name_1.kpr          # KV STUDIO 项目
│   ├── scaffold.model.json         # 项目模型
│   ├── scaffold.json               # 脚手架配置
│   ├── modules/                    # MNM 和变量文件
│   │   ├── MAIN/
│   │   │   ├── MAIN.mnm
│   │   │   └── variables.tsv
│   │   └── FB_AverageFilter/
│   │       ├── FB_AverageFilter.mnm
│   │       └── fb_arguments.tsv
│   ├── artifacts/                  # 运行产物
│   │   ├── result.json             # 运行结果
│   │   ├── failure.json            # 失败详情
│   │   ├── compile_result.txt      # 编译输出
│   │   ├── screenshot_*.png        # 错误截图
│   │   └── runner.log              # 详细日志
│   ├── TASK.md                     # 任务描述
│   └── VERSION.md                  # 版本信息
└── project_name_2/
    └── ...
```

## 文件类型说明

### Skill 定义 (`SKILL.md`)

**格式：** Markdown with YAML frontmatter

```markdown
---
name: skill-name
description: Skill 的简短描述
---

# 详细说明
...
```

**用途：**
- AI 读取此文件了解 skill 的能力
- 定义触发条件和使用场景
- 说明输入输出格式

### 脚本清单 (`script_manifest.json`)

**格式：** JSON

```json
{
  "version": "1.0",
  "classes": {
    "customer_workflow": [
      {
        "name": "run_kv_mvp_scaffold",
        "path": "workflow/run_kv_mvp_scaffold.ps1",
        "customer_callable": true,
        "capability": "run_kv_mvp_scaffold",
        "description": "创建新的 KV STUDIO 项目"
      }
    ]
  }
}
```

**用途：**
- AI 从这里选择要执行的脚本
- 定义脚本的分类和权限
- 管理脚本版本

### 脚手架模型 (`scaffold.model.json`)

**格式：** JSON

```json
{
  "project": {
    "name": "MyProject",
    "cpu_type": "KV-7500"
  },
  "modules": [
    {
      "name": "MAIN",
      "type": "main",
      "mnm_source": "..."
    }
  ],
  "variables": {
    "global": [...],
    "local": [...]
  }
}
```

**用途：**
- 描述整个 PLC 项目的结构
- AI 编辑此文件来修改项目
- 渲染器读取此文件生成 KV STUDIO 文件

### 运行结果 (`result.json`)

**格式：** JSON

```json
{
  "ok": true,
  "error_code": null,
  "step": "compile",
  "clean_end_state": true,
  "compile_result": {
    "status": "OK",
    "errors": 0,
    "warnings": 0
  }
}
```

**用途：**
- AI 读取此文件判断运行是否成功
- 失败时包含错误代码和失败步骤
- 决定下一步操作

## 扩展指南

### 添加新的 Workflow

1. 在 `kv-studio-operator/scripts/workflow/` 创建 `.ps1` 文件
2. 在 `script_manifest.json` 中注册
3. 在 `references/` 中添加文档
4. 测试并标记 `customer_callable`

### 添加新的参考文档

1. 在对应 skill 的 `references/` 目录创建 `.md` 文件
2. 在 `SKILL.md` 中添加引用
3. 使用清晰的标题和代码示例

### 添加新的模板

1. 在 `kv-studio-operator/templates/` 创建模板文件
2. 包含完整的 `scaffold.model.json`
3. 提供注释说明各字段含义

## 版本控制

### 建议的 `.gitignore`

```gitignore
# 工作目录
work_root/

# 用户配置
*.local.json
credentials.xml

# 临时文件
*.tmp
*.log
artifacts/

# KV STUDIO 项目文件（可选，根据需要调整）
*.kpr
*.kvbak
```

### 不应提交的文件

- 用户特定的配置路径
- 加密的凭据
- 生成的项目文件
- 运行日志和截图

### 应该提交的文件

- Skill 定义 (`SKILL.md`)
- 脚本和工作流
- 参考文档和模板
- 安装脚本
- Schema 和示例文件

---

## 快速查找

**我想...**

| 需求 | 查看文件 |
|------|----------|
| 快速上手 | `docs/quick-start.md` |
| 详细安装 | `docs/installation.md` |
| 配置说明 | `docs/configuration.md` |
| 解决问题 | `docs/guide/troubleshooting.md` |
| 理解架构 | `docs/architecture/overview.md` |
| 贡献代码 | `docs/dev/contributing.md` |
| 了解 Skill 能力 | 各 skill 的 `SKILL.md` |
| 查看可用脚本 | `kv-studio-operator/scripts/script_manifest.json` |
| 理解脚手架模型 | `keyence-plc-programmer/references/scaffold-schema.json` |
| 调试脚本 | 工作目录的 `artifacts/` 文件夹 |

---

**下一步：** 阅读 [快速开始](quick-start.md) 开始使用 KeyenceAgent。
