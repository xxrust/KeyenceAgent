# 5分钟快速开始

本教程将带你完成第一个 KeyenceAgent 项目，从安装到生成可编译的 PLC 程序。

## 前置准备

在开始前，确保你已经：

- ✅ 安装了 Windows 10/11
- ✅ 安装了 KEYENCE KV STUDIO（推荐 KVS12）
- ✅ 安装了 Claude Code CLI
- ✅ 有 KV STUDIO 的管理员账户和密码

## 步骤 1：安装 KeyenceAgent

### 1.1 克隆仓库

打开 PowerShell，执行：

```powershell
# 进入 Codex skills 目录
cd $env:USERPROFILE\.codex\skills

# 克隆仓库（如果目录不存在，整个 skills 目录就是这个仓库）
git clone https://github.com/xxrust/KeyenceAgent .
```

### 1.2 运行安装脚本

```powershell
.\setup_keyence_agent.ps1
```

安装过程会询问以下配置：

| 配置项 | 说明 | 示例 |
|--------|------|------|
| **Codex skills 目录** | 你的 skills 目录路径 | `C:\Users\你的用户名\.codex\skills` |
| **配置文件路径** | 配置保存位置（默认即可） | `%APPDATA%\Codex\kv-studio-operator\config.json` |
| **KV STUDIO 路径** | Kvs.exe 的完整路径 | `C:\Program Files\KEYENCE\KV STUDIO\Kvs.exe` |
| **工作目录** | 临时文件存放位置 | `C:\Temp\KeyenceWork` |
| **知识库路径** | KEYENCE Wiki V2 根目录 | `C:\Users\Public\Documents\KEYENCE\KVS12\ManualHelp\2052\htmlhelp` |
| **管理员用户名** | KV STUDIO 管理员用户名 | `Administrator` |
| **管理员密码** | （可选）存储密码以免每次输入 | （使用 Windows DPAPI 加密存储）|

**提示：** 所有路径都支持环境变量，如 `%USERPROFILE%`、`%TEMP%` 等。

### 1.3 验证安装

安装完成后，运行：

```powershell
.\setup_keyence_agent.ps1 -Status
```

你应该看到类似输出：

```
Configuration status
────────────────────────────────────────────
codex_skills         configured    C:\Users\...\skills
kv_studio_exe        configured    C:\Program Files\KEYENCE\...
work_root            configured    C:\Temp\KeyenceWork
wiki_root            configured    C:\Users\Public\Documents\...
credential           configured    (stored with DPAPI)

Setup completed.
```

## 步骤 2：第一个项目

### 2.1 启动 Claude Code

```powershell
claude-code chat
```

### 2.2 创建简单项目

在 Claude Code 中输入：

```
使用 /kv-studio-operator 创建一个新的 KV STUDIO 项目：

项目需求：
1. 一个启动按钮（DM100.00）
2. 一个停止按钮（DM100.01）
3. 一个运行指示灯（R0）
4. 逻辑：按下启动按钮，指示灯点亮；按下停止按钮，指示灯熄灭
```

### 2.3 AI 自动执行

你会看到 AI 按以下步骤工作：

```
1. 📖 调用 kv-studio-kb-programming 查询指令语法
2. ✏️  调用 keyence-plc-programmer 生成程序
   ├─ 创建 scaffold.model.json
   ├─ 生成主模块 MNM
   └─ 配置变量表
3. 🔍 运行静态门禁验证
4. 🚀 调用 kv-studio-operator 启动 KV STUDIO
   ├─ 创建新项目
   ├─ 导入 MNM
   ├─ 粘贴变量
   └─ 编译
5. ✅ 报告结果
```

### 2.4 查看结果

AI 会报告编译结果：

```
✅ 项目创建成功

编译结果：
  转换结果 OK
  错误数量: 0
  警告数量: 0

项目位置：
  C:\Temp\KeyenceWork\start_stop_control\start_stop_control.kpr

生成的文件：
  - modules/MAIN/MAIN.mnm         (主程序)
  - modules/MAIN/variables.tsv     (变量表)
  - scaffold.model.json            (项目模型)
```

你现在可以在 KV STUDIO 中打开 `start_stop_control.kpr`，查看生成的程序。

## 步骤 3：修改项目

假设你想增加一个计数器功能。在 Claude Code 中输入：

```
修改刚才的项目，增加一个计数器：
- 每次按下启动按钮，计数器 +1
- 计数器值存储在 DM200
- 按下复位按钮（DM100.02）时，计数器清零
```

AI 会：
1. 导出现有项目的 MNM
2. 修改程序逻辑
3. 更新变量表
4. 重新导入并编译
5. 验证修改成功

## 步骤 4：使用功能块

现在试试创建一个带功能块的项目：

```
使用 /kv-studio-operator 创建一个带功能块的项目：

功能块需求：
- 名称：AverageFilter（平均值滤波）
- 输入：RawValue（原始值，INT 型）
- 输出：FilteredValue（滤波值，INT 型）
- 参数：WindowSize（窗口大小，默认 5）
- 功能：对最近 WindowSize 个样本求平均值

主程序需求：
- 读取 4 路传感器值（EM1:CH0~CH3）
- 对每路传感器应用 AverageFilter
- 将滤波后的值输出到 DM100~DM103
```

AI 会自动：
1. 设计功能块结构
2. 生成功能块 MNM（`MODULE_TYPE:2`）
3. 创建功能块参数表
4. 在主程序中实例化 4 个功能块
5. 配置调用链路
6. 验证编译通过

## 常见问题

### Q1: 安装脚本找不到 KV STUDIO

**问题：** 提示 `kvs_exe: missing`

**解决：**
```powershell
# 手动指定 KV STUDIO 路径
.\setup_keyence_agent.ps1 -Configure kvs_exe

# 输入完整路径，例如：
# C:\Program Files (x86)\KEYENCE\KV STUDIO\Kvs.exe
```

### Q2: 知识库路径不正确

**问题：** AI 无法查询 KEYENCE 指令

**解决：**
```powershell
# 重新配置知识库路径
.\setup_keyence_agent.ps1 -Configure wiki_root

# 知识库路径通常在：
# C:\Users\Public\Documents\KEYENCE\KVS12\ManualHelp\2052\htmlhelp
```

### Q3: KV STUDIO 打开失败

**问题：** 脚本运行时 KV STUDIO 窗口异常

**解决：**
1. 确保 KV STUDIO 没有已打开的实例
2. 检查管理员权限
3. 查看工作目录下的 `artifacts/` 目录，查看错误截图

### Q4: 编译报错

**问题：** AI 报告编译失败

**解决：**
1. 将完整的错误信息反馈给 AI
2. AI 会自动分析错误原因并修复
3. 如果多次失败，可以查看生成的 MNM 文件手动检查

## 下一步

恭喜！你已经完成了第一个 KeyenceAgent 项目。接下来可以：

- 📖 阅读 [使用指南](../guide/) 了解更多功能
- 🔧 学习 [变量管理](../guide/variables.md) 的最佳实践
- 🧩 探索 [功能块开发](../guide/function-blocks.md)
- 🏗️ 理解 [架构设计](../architecture/overview.md)

---

**遇到问题？** 查看 [故障排除指南](../guide/troubleshooting.md) 或 [提交 Issue](https://github.com/xxrust/KeyenceAgent/issues)。
