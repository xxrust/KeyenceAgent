# KeyenceAgent

> 🤖 让 AI 智能体为你编写和维护 KEYENCE PLC 程序

<p align="center">
  <a href="#快速开始">快速开始</a> •
  <a href="#功能展示">功能展示</a> •
  <a href="#工作原理">工作原理</a> •
  <a href="#文档">文档</a>
</p>

<p align="center">
  <a href="README.md">中文</a> •
  <a href="README.ja.md">日本語</a> •
  <a href="README.en.md">English</a>
</p>

---

## 这是什么？

KeyenceAgent 让你可以**用自然语言描述需求**，由 AI 智能体自动生成完整的 KEYENCE KV STUDIO PLC 项目。

**传统方式：**
```
1. 打开 KV STUDIO
2. 手动创建项目
3. 一个个添加模块
4. 编写梯形图/ST代码
5. 配置变量表
6. 反复编译调试
```

**使用 KeyenceAgent：**
```
你：我需要一个带平滑滤波功能块的项目，输入是传感器值，输出是滤波后的结果

AI：✅ 已创建项目
    ✅ 已生成功能块
    ✅ 已配置变量
    ✅ 编译通过（0错误 0警告）
```

## 快速开始

### 前置要求

- Windows 10/11
- KEYENCE KV STUDIO（已验证 KVS12）
- PowerShell 5.1+
- Claude Code CLI（或其他支持 Codex skills 的 AI 工具）

### 一键安装

1. **克隆仓库到你的 Codex skills 目录**
```powershell
cd %USERPROFILE%\.codex\skills
git clone https://github.com/xxrust/KeyenceAgent .
```

2. **运行安装脚本**
```powershell
.\setup_keyence_agent.ps1
```

安装脚本会：
- ✅ 安装 3 个 Codex skills
- ✅ 配置 KV STUDIO 路径
- ✅ 设置工作目录
- ✅ 配置知识库路径
- ✅ 存储 KV STUDIO 管理员凭据（可选）

3. **验证安装**
```powershell
.\setup_keyence_agent.ps1 -Status
```

### 第一个项目（5分钟）

安装完成后，在 Claude Code 中输入：

```
使用 kv-studio-operator 创建一个新的 KV STUDIO 项目，
包含一个简单的启动/停止控制逻辑
```

AI 会自动：
1. 创建项目脚手架
2. 生成 MNM 程序文件
3. 配置变量表
4. 启动 KV STUDIO 并导入
5. 编译并报告结果

## 功能展示

### ✅ 已支持的功能

| 功能 | 说明 | 状态 |
|------|------|------|
| 🆕 新建项目 | 从零创建完整的 PLC 项目 | ✅ 稳定（连续3次通过） |
| 📦 多模块支持 | 支持主模块、后备模块、中断程序 | ✅ 主模块+后备模块已验证 |
| 🧩 功能块 | 创建和调用用户功能块 | ✅ 已通过平滑滤波 FB 验证 |
| 📋 变量管理 | 自动配置全局和局部变量 | ✅ 支持粘贴验证 |
| 🔄 项目修复 | 修改现有项目并重新编译 | ✅ 支持快照门禁 |
| ✏️ MNM 导入/导出 | 批量处理程序模块 | ✅ 支持 |
| 🔍 编译验证 | 自动捕获编译结果 | ✅ 提取错误/警告文本 |

### 🎯 典型使用场景

<details>
<summary>📘 场景1：从需求生成完整项目</summary>

**你的需求：**
> 创建一个温度控制项目：
> - 读取 4 路温度传感器（EM1：CH0-CH3）
> - 当温度 > 80°C 时启动冷却风扇
> - 提供手动/自动切换开关
> - 记录最高温度值

**AI 自动完成：**
1. 设计变量表（传感器输入、风扇输出、模式切换、最高温度记录）
2. 生成主程序 MNM（温度读取、比较、风扇控制逻辑）
3. 创建 KV STUDIO 项目并导入
4. 编译验证（0错误）

</details>

<details>
<summary>📗 场景2：复用功能块</summary>

**你的需求：**
> 我有一个平滑滤波功能块，现在要用它处理 8 路振动传感器数据

**AI 自动完成：**
1. 查询已有功能块定义
2. 为每路传感器实例化滤波功能块
3. 配置功能块参数（采样窗口、输入输出变量）
4. 生成调用链路
5. 更新变量表

</details>

<details>
<summary>📕 场景3：修复现有项目</summary>

**你的需求：**
> 我的项目编译报错："变量 TempSensor1 未定义"

**AI 自动完成：**
1. 导出当前项目 MNM
2. 分析变量使用情况
3. 在变量表中补充缺失定义
4. 重新导入并编译
5. 验证修复成功

</details>

## 工作原理

### 三个核心 Skills

KeyenceAgent 由 3 个独立的 Codex skill 组成：

```
┌─────────────────────────────────────────────────────┐
│  你的需求（自然语言）                                  │
└──────────────────┬──────────────────────────────────┘
                   │
        ┌──────────┴──────────┐
        │  Claude Code Agent   │
        └──────────┬──────────┘
                   │
       ┌───────────┼───────────┐
       │           │           │
       ▼           ▼           ▼
┌──────────┐ ┌─────────┐ ┌──────────┐
│ KB查询    │ │ 程序设计 │ │ KV操作   │
│          │ │         │ │          │
│ kv-studio│ │ keyence-│ │ kv-studio│
│ -kb-     │ │ plc-    │ │ -operator│
│ program  │ │ program │ │          │
│ ming     │ │ mer     │ │          │
└──────────┘ └─────────┘ └──────────┘
     │            │            │
     └────────────┴────────────┘
                  │
                  ▼
          ┌──────────────┐
          │  KV STUDIO   │
          │  (自动操作)   │
          └──────────────┘
```

#### 1️⃣ `kv-studio-kb-programming`
- **职责**：查询 KEYENCE 知识库
- **能力**：指令语法、功能块定义、模块规格、通信协议
- **数据源**：本机 KEYENCE Wiki V2

#### 2️⃣ `keyence-plc-programmer`
- **职责**：设计 PLC 程序
- **能力**：生成 MNM、设计变量表、创建功能块、修复错误
- **输入**：需求描述、知识库证据
- **输出**：脚手架文件（scaffold.model.json、MNM、TSV）

#### 3️⃣ `kv-studio-operator`
- **职责**：操作 KV STUDIO 桌面软件
- **能力**：创建项目、导入 MNM、编辑变量、编译、捕获结果
- **特点**：完全自动化，AI 不直接操作 UI

### 执行流程

```
1. 准备阶段（AI）
   ├─ 查询知识库
   ├─ 设计程序结构
   └─ 生成脚手架文件

2. 验证阶段（脚本）
   ├─ 静态检查（变量合法性、模块完整性）
   ├─ 导入计划验证
   └─ 快照对比（修复现有项目时）

3. 执行阶段（自动化脚本）
   ├─ 启动 KV STUDIO
   ├─ 创建/打开项目
   ├─ 导入 MNM
   ├─ 粘贴变量表
   └─ 运行编译

4. 验收阶段（AI）
   ├─ 读取编译结果
   ├─ 分析错误/警告
   └─ 决定下一步操作
```

### 关键设计原则

| 原则 | 解释 | 为什么重要 |
|------|------|------------|
| 🔒 **UI 门禁** | KV STUDIO 打开前必须通过所有检查 | 避免脚本在 UI 中途失败 |
| 📸 **同次证据** | 只使用本次运行的输出文件 | 防止混淆历史记录 |
| 🛡️ **共享 UI 守卫** | 焦点检查、弹窗处理统一管理 | 提高脚本稳定性 |
| 📊 **文件化 Oracle** | 编译结果先写文件，AI 再分析 | AI 和脚本职责分离 |
| 🔄 **重复性验证** | 要求连续成功多次 | 确保稳定性 |

## 文档

### 📚 快速入门

- [5分钟教程](docs/quick-start.md) - 第一个项目
- [安装指南](docs/installation.md) - 详细安装步骤
- [配置说明](docs/configuration.md) - 自定义配置

### 🔧 使用指南

- [创建新项目](docs/guide/new-project.md)
- [修复现有项目](docs/guide/repair-project.md)
- [使用功能块](docs/guide/function-blocks.md)
- [变量管理](docs/guide/variables.md)
- [故障排除](docs/guide/troubleshooting.md)

### 🏗️ 进阶主题

- [架构设计](docs/architecture/overview.md)
- [脚手架模型](docs/architecture/scaffold-model.md)
- [Runner 协议](docs/architecture/runner-contract.md)
- [路线治理](docs/architecture/route-governance.md)

### 🔬 开发者文档

- [贡献指南](docs/dev/contributing.md)
- [添加新 Workflow](docs/dev/add-workflow.md)
- [调试技巧](docs/dev/debugging.md)
- [测试规范](docs/dev/testing.md)

## 常见问题

<details>
<summary><strong>Q: 支持哪些 KV STUDIO 版本？</strong></summary>

A: 已验证 KVS12。其他版本可能可用，但未经测试。
</details>

<details>
<summary><strong>Q: 需要安装什么 AI 工具？</strong></summary>

A: 推荐使用 Claude Code CLI。也可以使用其他支持 Codex skills 的工具。
</details>

<details>
<summary><strong>Q: 会覆盖我现有的项目吗？</strong></summary>

A: 不会。修复现有项目时，脚本会先创建快照，并有门禁检查。
</details>

<details>
<summary><strong>Q: 生成的代码质量如何？</strong></summary>

A: 代码遵循 KEYENCE 官方语法和最佳实践。所有项目都经过编译验证（0错误）。
</details>

<details>
<summary><strong>Q: 遇到问题怎么办？</strong></summary>

A: 查看 [故障排除指南](docs/guide/troubleshooting.md) 或 [提交 Issue](https://github.com/xxrust/KeyenceAgent/issues)。
</details>

## 路线图

### 🎯 当前重点

- [ ] 补全所有快速入门文档
- [ ] 增加更多使用场景示例
- [ ] 完善错误信息的中文本地化

### 🚀 下一步计划

- [ ] 支持中断程序的完整配置
- [ ] 嵌套功能块调用
- [ ] EtherCAT/EtherNet-IP 配置界面自动化
- [ ] 项目导出/导入完整闭环

### 💡 未来展望

- [ ] 支持 KV-7000/8000 系列
- [ ] 在线调试辅助
- [ ] 程序优化建议
- [ ] 多语言知识库

## 技术支持

- 📖 [文档中心](docs/)
- 💬 [GitHub Discussions](https://github.com/xxrust/KeyenceAgent/discussions)
- 🐛 [问题反馈](https://github.com/xxrust/KeyenceAgent/issues)

## 许可证

[MIT License](LICENSE)

## 致谢

感谢 KEYENCE 提供强大的 KV STUDIO 开发工具。

---

<p align="center">
Made with ❤️ by <a href="https://github.com/xxrust">xxrust</a>
</p>
