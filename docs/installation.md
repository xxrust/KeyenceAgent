# 安装指南

本指南将详细说明如何在你的系统上安装和配置 KeyenceAgent。

## 系统要求

### 必需组件

| 组件 | 最低版本 | 推荐版本 | 说明 |
|------|----------|----------|------|
| Windows | 10 | 11 | 必须是 Windows 系统 |
| PowerShell | 5.1 | 7.x | 执行安装和运行脚本 |
| KV STUDIO | KVS12 | KVS12 | KEYENCE PLC 编程软件 |
| Claude Code | 最新 | 最新 | AI 智能体运行环境 |

### 磁盘空间

- **安装大小：** ~50 MB（skills + 脚本）
- **知识库：** ~200 MB（KEYENCE 官方手册）
- **工作目录：** 建议预留 1 GB（用于临时项目和日志）

## 安装方式

### 方式一：使用安装脚本（推荐）

这是最简单的安装方式，适合大多数用户。

#### 1. 克隆仓库

```powershell
# 方法 A：克隆到 Codex skills 目录
cd $env:USERPROFILE\.codex\skills
git clone https://github.com/xxrust/KeyenceAgent .

# 方法 B：克隆到临时目录，稍后由脚本复制
git clone https://github.com/xxrust/KeyenceAgent
cd KeyenceAgent
```

#### 2. 运行安装脚本

```powershell
# 完整安装（包括所有配置）
.\setup_keyence_agent.ps1

# 或者查看帮助
.\setup_keyence_agent.ps1 -h
```

#### 3. 按提示输入配置

安装脚本会依次询问：

**a. Codex skills 目录**
```
Codex skills directory [C:\Users\你的用户名\.codex\skills]:
```
- 按 Enter 使用默认路径
- 或输入自定义路径

**b. 配置文件路径**
```
Local config file path or directory [%APPDATA%\Codex\kv-studio-operator\config.json]:
```
- 推荐使用默认路径
- 也可以指定自定义目录

**c. KV STUDIO 可执行文件**
```
KV STUDIO Kvs.exe path [C:\Program Files\KEYENCE\KV STUDIO\Kvs.exe]:
```
- 输入你的 KV STUDIO 安装路径
- 常见路径：
  - `C:\Program Files\KEYENCE\KV STUDIO\Kvs.exe`
  - `C:\Program Files (x86)\KEYENCE\KV STUDIO\Kvs.exe`

**d. 工作目录**
```
Disposable work root [C:\Temp\KeyenceWork]:
```
- 用于存放临时项目和日志
- 建议使用 SSD 路径以提高性能

**e. 知识库根目录**
```
KEYENCE Wiki V2 root [C:\Users\Public\Documents\KEYENCE\KVS12\ManualHelp\2052\htmlhelp]:
```
- KEYENCE 官方手册的 HTML 目录
- 语言版本：
  - `2052` = 中文
  - `1041` = 日文
  - `1033` = 英文

**f. 管理员用户名**
```
KV STUDIO administrator user name [Administrator]:
```
- KV STUDIO 登录用户名
- 通常是 `Administrator`

**g. 存储凭据（可选）**
```
Store KV STUDIO administrator credential now [Y/n]:
```
- 选择 `Y` 将密码加密存储（推荐）
- 选择 `n` 每次运行时手动输入

如果选择存储凭据：
```
KV STUDIO administrator password for Administrator (stored with Windows DPAPI, not written to JSON):
```
- 输入密码（不会显示在屏幕上）
- 使用 Windows DPAPI 加密，安全存储在 `%APPDATA%\Codex\kv-studio-operator\credentials.xml`

#### 4. 验证安装

安装完成后，你会看到配置状态表：

```
Configuration status
────────────────────────────────────────────
codex_skills         configured    C:\Users\...\skills
kv_studio_exe        configured    C:\Program Files\KEYENCE\KV STUDIO\Kvs.exe
work_root            configured    C:\Temp\KeyenceWork
wiki_root            configured    C:\Users\Public\Documents\KEYENCE\KVS12\...
admin_user           configured    Administrator
credential           configured    (stored with DPAPI)

Setup completed.
```

### 方式二：手动安装

如果你想要更细粒度的控制，可以手动安装。

#### 1. 安装 Skills

```powershell
# 创建 skills 目录（如果不存在）
$skillsDir = "$env:USERPROFILE\.codex\skills"
New-Item -ItemType Directory -Force -Path $skillsDir

# 复制 skill 文件夹
Copy-Item -Recurse -Force ".\kv-studio-kb-programming" "$skillsDir\"
Copy-Item -Recurse -Force ".\keyence-plc-programmer" "$skillsDir\"
Copy-Item -Recurse -Force ".\kv-studio-operator" "$skillsDir\"
```

#### 2. 创建配置文件

创建 `%APPDATA%\Codex\kv-studio-operator\config.json`：

```json
{
  "kvs_exe": "C:\\Program Files\\KEYENCE\\KV STUDIO\\Kvs.exe",
  "work_root": "C:\\Temp\\KeyenceWork",
  "wiki_root": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\ManualHelp\\2052\\htmlhelp",
  "admin_user": "Administrator",
  "runner_timeout_seconds": 300,
  "local_variable_paste_format": "kv_default"
}
```

#### 3. 设置环境变量

```powershell
# 设置配置路径（用户级）
$configPath = "$env:APPDATA\Codex\kv-studio-operator\config.json"
[Environment]::SetEnvironmentVariable('KEYENCE_AGENT_CONFIG', $configPath, 'User')
[Environment]::SetEnvironmentVariable('KV_STUDIO_OPERATOR_CONFIG', $configPath, 'User')

# 刷新当前会话
$env:KEYENCE_AGENT_CONFIG = $configPath
$env:KV_STUDIO_OPERATOR_CONFIG = $configPath
```

#### 4. 存储凭据（可选）

如果要存储 KV STUDIO 管理员密码：

```powershell
# 使用安装脚本的凭据存储功能
.\setup_keyence_agent.ps1 -Configure credential
```

或者手动创建（需要密码学知识，不推荐）。

## 配置详解

### 配置文件格式

完整的 `config.json` 包含以下字段：

```json
{
  "kvs_exe": "KV STUDIO 可执行文件的完整路径",
  "work_root": "工作目录（存放临时项目和日志）",
  "wiki_root": "KEYENCE 知识库根目录",
  "admin_user": "KV STUDIO 管理员用户名",
  "runner_timeout_seconds": 300,
  "local_variable_paste_format": "kv_default",
  "advanced": {
    "ui_guard_retry_count": 3,
    "focus_check_interval_ms": 500,
    "clipboard_safety_enabled": true
  }
}
```

### 配置项说明

| 字段 | 类型 | 必需 | 默认值 | 说明 |
|------|------|------|--------|------|
| `kvs_exe` | String | ✅ | - | KV STUDIO 可执行文件路径 |
| `work_root` | String | ✅ | - | 工作目录，用于存放项目和日志 |
| `wiki_root` | String | ✅ | - | KEYENCE Wiki V2 根目录 |
| `admin_user` | String | ✅ | `Administrator` | KV STUDIO 登录用户名 |
| `runner_timeout_seconds` | Number | ❌ | `300` | 脚本超时时间（秒） |
| `local_variable_paste_format` | String | ❌ | `kv_default` | 变量粘贴格式 |
| `advanced.*` | Object | ❌ | - | 高级配置（一般不需要修改） |

### 环境变量

KeyenceAgent 使用以下环境变量：

| 变量名 | 优先级 | 说明 |
|--------|--------|------|
| `KV_STUDIO_OPERATOR_CONFIG` | 最高 | 配置文件路径（推荐） |
| `KEYENCE_AGENT_CONFIG` | 次高 | 配置文件路径（兼容旧版本） |

设置后需要重启 PowerShell 才能生效，或使用 `$env:变量名 = 值` 临时设置。

### 凭据存储

密码使用 Windows DPAPI 加密存储在：
```
%APPDATA%\Codex\kv-studio-operator\credentials.xml
```

**安全说明：**
- 只有当前 Windows 用户可以解密
- 不会写入 JSON 配置文件
- 如果不存储凭据，每次运行时会提示输入密码

## 验证安装

### 检查配置状态

```powershell
.\setup_keyence_agent.ps1 -Status
```

输出示例：

```
Configuration status
────────────────────────────────────────────
codex_skills         configured    C:\Users\你的用户名\.codex\skills
kv_studio_exe        configured    C:\Program Files\KEYENCE\KV STUDIO\Kvs.exe
work_root            configured    C:\Temp\KeyenceWork
wiki_root            configured    C:\Users\Public\Documents\KEYENCE\KVS12\...
admin_user           configured    Administrator
credential           configured    (stored with DPAPI)
```

### 测试 KV STUDIO 路径

```powershell
# 检查 Kvs.exe 是否存在
$config = Get-Content "$env:KV_STUDIO_OPERATOR_CONFIG" | ConvertFrom-Json
Test-Path $config.kvs_exe

# 应该输出 True
```

### 测试知识库

```powershell
# 检查知识库目录
$config = Get-Content "$env:KV_STUDIO_OPERATOR_CONFIG" | ConvertFrom-Json
Get-ChildItem $config.wiki_root -Filter "*.html" | Select-Object -First 5

# 应该列出一些 HTML 文件
```

### 测试 Skills

在 Claude Code 中输入：

```
/kv-studio-kb-programming 查询 LD 指令的语法
```

如果能返回查询结果，说明 skill 安装成功。

## 更新

### 更新到最新版本

```powershell
# 进入 skills 目录
cd $env:USERPROFILE\.codex\skills

# 拉取最新代码
git pull

# 重新运行安装脚本（只更新 skills，不改配置）
.\setup_keyence_agent.ps1 -Configure skills
```

### 查看更新日志

```powershell
git log --oneline --graph -10
```

## 卸载

### 完全卸载

```powershell
# 1. 删除 skills
Remove-Item -Recurse -Force "$env:USERPROFILE\.codex\skills\kv-studio-kb-programming"
Remove-Item -Recurse -Force "$env:USERPROFILE\.codex\skills\keyence-plc-programmer"
Remove-Item -Recurse -Force "$env:USERPROFILE\.codex\skills\kv-studio-operator"

# 2. 删除配置文件
Remove-Item -Recurse -Force "$env:APPDATA\Codex\kv-studio-operator"

# 3. 删除环境变量
[Environment]::SetEnvironmentVariable('KEYENCE_AGENT_CONFIG', $null, 'User')
[Environment]::SetEnvironmentVariable('KV_STUDIO_OPERATOR_CONFIG', $null, 'User')

# 4. 删除工作目录（可选，包含你的项目）
# Remove-Item -Recurse -Force "C:\Temp\KeyenceWork"
```

### 保留配置卸载

只删除 skills，保留配置和工作目录：

```powershell
Remove-Item -Recurse -Force "$env:USERPROFILE\.codex\skills\kv-studio-*"
Remove-Item -Recurse -Force "$env:USERPROFILE\.codex\skills\keyence-plc-programmer"
```

## 常见安装问题

### 问题 1：找不到 KV STUDIO

**症状：** 安装脚本提示找不到 `Kvs.exe`

**解决方案：**

1. 确认 KV STUDIO 已安装
2. 查找 Kvs.exe 位置：
   ```powershell
   Get-ChildItem "C:\Program Files" -Recurse -Filter "Kvs.exe" -ErrorAction SilentlyContinue
   ```
3. 手动指定路径：
   ```powershell
   .\setup_keyence_agent.ps1 -Configure kvs_exe
   ```

### 问题 2：知识库路径错误

**症状：** AI 无法查询指令语法

**解决方案：**

1. 确认知识库已安装（随 KV STUDIO 安装）
2. 检查路径：
   ```powershell
   Test-Path "C:\Users\Public\Documents\KEYENCE\KVS12\ManualHelp"
   ```
3. 根据你的语言版本选择：
   - `2052\htmlhelp` = 中文
   - `1041\htmlhelp` = 日文
   - `1033\htmlhelp` = 英文

### 问题 3：权限不足

**症状：** 安装脚本报错 "Access Denied"

**解决方案：**

以管理员身份运行 PowerShell：
```powershell
Start-Process powershell -Verb RunAs
```

### 问题 4：环境变量未生效

**症状：** 配置后仍然找不到配置文件

**解决方案：**

1. 重启 PowerShell
2. 或手动设置：
   ```powershell
   $env:KV_STUDIO_OPERATOR_CONFIG = "$env:APPDATA\Codex\kv-studio-operator\config.json"
   ```
3. 验证：
   ```powershell
   echo $env:KV_STUDIO_OPERATOR_CONFIG
   ```

## 下一步

安装完成后，可以：

- 📖 继续阅读 [5分钟快速开始](quick-start.md)
- 🔧 学习 [配置说明](configuration.md)
- 🎯 查看 [使用指南](../guide/)

---

**需要帮助？** 查看 [故障排除](../guide/troubleshooting.md) 或 [提交 Issue](https://github.com/xxrust/KeyenceAgent/issues)。
