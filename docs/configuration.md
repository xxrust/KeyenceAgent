# 配置说明

本文档详细说明 KeyenceAgent 的配置选项和自定义方法。

## 配置文件位置

KeyenceAgent 使用 JSON 格式的配置文件，默认位置：

```
%APPDATA%\Codex\kv-studio-operator\config.json
```

实际路径示例：
```
C:\Users\你的用户名\AppData\Roaming\Codex\kv-studio-operator\config.json
```

## 配置文件结构

### 完整配置示例

```json
{
  "kvs_exe": "C:\\Program Files\\KEYENCE\\KV STUDIO\\Kvs.exe",
  "work_root": "C:\\Temp\\KeyenceWork",
  "wiki_root": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\ManualHelp\\2052\\htmlhelp",
  "admin_user": "Administrator",
  "runner_timeout_seconds": 300,
  "local_variable_paste_format": "kv_default",
  "advanced": {
    "ui_guard_retry_count": 3,
    "focus_check_interval_ms": 500,
    "clipboard_safety_enabled": true,
    "screenshot_on_success": false,
    "verbose_logging": false
  }
}
```

## 基本配置项

### kvs_exe

**说明：** KV STUDIO 可执行文件的完整路径

**类型：** String

**必需：** ✅ 是

**示例：**
```json
"kvs_exe": "C:\\Program Files\\KEYENCE\\KV STUDIO\\Kvs.exe"
```

**常见路径：**
- `C:\Program Files\KEYENCE\KV STUDIO\Kvs.exe`
- `C:\Program Files (x86)\KEYENCE\KV STUDIO\Kvs.exe`
- `D:\KEYENCE\KV STUDIO\Kvs.exe`

**注意事项：**
- 使用双反斜杠 `\\` 或正斜杠 `/`
- 路径必须指向 `Kvs.exe` 文件本身
- 文件必须存在且可执行

### work_root

**说明：** 工作目录，用于存放临时项目和运行日志

**类型：** String

**必需：** ✅ 是

**示例：**
```json
"work_root": "C:\\Temp\\KeyenceWork"
```

**建议：**
- 使用 SSD 路径以提高性能
- 预留至少 1 GB 空间
- 避免使用网络驱动器
- 定期清理旧项目

**目录结构：**
```
work_root/
├── project1/
│   ├── project1.kpr
│   ├── scaffold.model.json
│   ├── modules/
│   └── artifacts/
└── project2/
    └── ...
```

### wiki_root

**说明：** KEYENCE 知识库（Wiki V2）根目录

**类型：** String

**必需：** ✅ 是

**示例：**
```json
"wiki_root": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\ManualHelp\\2052\\htmlhelp"
```

**语言版本：**
- `2052\htmlhelp` - 中文（简体）
- `1041\htmlhelp` - 日文
- `1033\htmlhelp` - 英文

**验证：**
```powershell
# 检查知识库是否存在
Test-Path "C:\Users\Public\Documents\KEYENCE\KVS12\ManualHelp\2052\htmlhelp"

# 查看知识库文件
Get-ChildItem "...\htmlhelp" -Filter "*.html" | Select-Object -First 5
```

### admin_user

**说明：** KV STUDIO 管理员用户名

**类型：** String

**必需：** ✅ 是

**默认值：** `Administrator`

**示例：**
```json
"admin_user": "Administrator"
```

**注意：**
- 必须是 KV STUDIO 中已存在的用户
- 区分大小写
- 如果未设置密码，配合凭据存储使用

## 可选配置项

### runner_timeout_seconds

**说明：** Runner 脚本的超时时间（秒）

**类型：** Number

**必需：** ❌ 否

**默认值：** `300` (5 分钟)

**示例：**
```json
"runner_timeout_seconds": 600
```

**调整建议：**
- 简单项目：120-180 秒
- 复杂项目：300-600 秒
- 大型项目：600-900 秒

**注意：**
- 超时不会损坏项目，但会中断操作
- 如果经常超时，增加此值
- 过大的值会导致卡死时等待过久

### local_variable_paste_format

**说明：** 变量粘贴格式

**类型：** String

**必需：** ❌ 否

**默认值：** `kv_default`

**可选值：**
- `kv_default` - KV STUDIO 默认格式
- `tab_separated` - 制表符分隔
- `csv` - 逗号分隔（实验性）

**示例：**
```json
"local_variable_paste_format": "kv_default"
```

**一般不需要修改此项。**

## 高级配置

### advanced.ui_guard_retry_count

**说明：** UI 守卫重试次数

**类型：** Number

**默认值：** `3`

**示例：**
```json
"advanced": {
  "ui_guard_retry_count": 5
}
```

**说明：**
- 当窗口焦点丢失或弹窗检测失败时的重试次数
- 增加此值可提高稳定性，但会延长运行时间
- 建议范围：3-10

### advanced.focus_check_interval_ms

**说明：** 焦点检查间隔（毫秒）

**类型：** Number

**默认值：** `500`

**示例：**
```json
"advanced": {
  "focus_check_interval_ms": 300
}
```

**说明：**
- 检查 KV STUDIO 窗口焦点的间隔
- 减小可以更快检测焦点丢失
- 过小会增加 CPU 占用
- 建议范围：200-1000

### advanced.clipboard_safety_enabled

**说明：** 剪贴板保护开关

**类型：** Boolean

**默认值：** `true`

**示例：**
```json
"advanced": {
  "clipboard_safety_enabled": true
}
```

**说明：**
- `true`: 自动备份和恢复剪贴板内容
- `false`: 不保护剪贴板（不推荐）

**建议保持 `true`，除非遇到剪贴板相关问题。**

### advanced.screenshot_on_success

**说明：** 成功时也截图

**类型：** Boolean

**默认值：** `false`

**示例：**
```json
"advanced": {
  "screenshot_on_success": true
}
```

**说明：**
- `false`: 只在失败时截图
- `true`: 成功时也截图（用于调试）

**注意：**
- 开启会增加磁盘占用
- 仅用于调试目的

### advanced.verbose_logging

**说明：** 详细日志模式

**类型：** Boolean

**默认值：** `false`

**示例：**
```json
"advanced": {
  "verbose_logging": true
}
```

**说明：**
- `false`: 标准日志
- `true`: 详细日志（包含所有 UI 操作细节）

**用途：**
- 调试脚本问题
- 分析性能瓶颈
- 排查偶发性错误

## 环境变量

KeyenceAgent 通过环境变量指定配置文件路径。

### KV_STUDIO_OPERATOR_CONFIG

**优先级：** 最高

**说明：** 指向配置文件的完整路径

**设置方法：**

**临时设置（当前会话）：**
```powershell
$env:KV_STUDIO_OPERATOR_CONFIG = "C:\MyConfig\config.json"
```

**永久设置（用户级）：**
```powershell
[Environment]::SetEnvironmentVariable(
    'KV_STUDIO_OPERATOR_CONFIG', 
    'C:\MyConfig\config.json', 
    'User'
)
```

**永久设置（系统级）：**
```powershell
[Environment]::SetEnvironmentVariable(
    'KV_STUDIO_OPERATOR_CONFIG', 
    'C:\MyConfig\config.json', 
    'Machine'
)
```

**验证：**
```powershell
echo $env:KV_STUDIO_OPERATOR_CONFIG
```

### KEYENCE_AGENT_CONFIG

**优先级：** 次高（兼容旧版本）

**说明：** 与 `KV_STUDIO_OPERATOR_CONFIG` 作用相同

**优先顺序：**
1. `KV_STUDIO_OPERATOR_CONFIG`
2. `KEYENCE_AGENT_CONFIG`
3. 默认路径

## 凭据管理

### 凭据存储位置

```
%APPDATA%\Codex\kv-studio-operator\credentials.xml
```

实际路径：
```
C:\Users\你的用户名\AppData\Roaming\Codex\kv-studio-operator\credentials.xml
```

### 存储凭据

**使用安装脚本：**
```powershell
.\setup_keyence_agent.ps1 -Configure credential
```

**手动存储（高级）：**
```powershell
# 加载凭据存储函数
. .\kv-studio-operator\scripts\guards\credential_guard.ps1

# 存储凭据
$password = Read-Host -AsSecureString "密码"
Write-DpapiCredential -UserName "Administrator" -Password $password
```

### 删除凭据

```powershell
Remove-Item "$env:APPDATA\Codex\kv-studio-operator\credentials.xml"
```

### 安全性

- ✅ 使用 Windows DPAPI 加密
- ✅ 只有当前用户可以解密
- ✅ 不存储在配置文件中
- ✅ 不会通过网络传输

## 配置验证

### 检查配置状态

```powershell
.\setup_keyence_agent.ps1 -Status
```

### 手动验证

```powershell
# 读取配置文件
$config = Get-Content "$env:KV_STUDIO_OPERATOR_CONFIG" | ConvertFrom-Json

# 检查 KV STUDIO 路径
Test-Path $config.kvs_exe

# 检查工作目录
Test-Path $config.work_root

# 检查知识库
Test-Path $config.wiki_root

# 检查凭据
Test-Path "$env:APPDATA\Codex\kv-studio-operator\credentials.xml"
```

## 多配置管理

### 场景：不同环境使用不同配置

**开发配置：**
```json
{
  "kvs_exe": "C:\\Program Files\\KEYENCE\\KV STUDIO\\Kvs.exe",
  "work_root": "D:\\Dev\\KeyenceWork",
  "wiki_root": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\ManualHelp\\2052\\htmlhelp",
  "runner_timeout_seconds": 600,
  "advanced": {
    "verbose_logging": true,
    "screenshot_on_success": true
  }
}
```

**生产配置：**
```json
{
  "kvs_exe": "C:\\Program Files\\KEYENCE\\KV STUDIO\\Kvs.exe",
  "work_root": "C:\\Production\\KeyenceWork",
  "wiki_root": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\ManualHelp\\2052\\htmlhelp",
  "runner_timeout_seconds": 300,
  "advanced": {
    "verbose_logging": false,
    "screenshot_on_success": false
  }
}
```

**切换配置：**
```powershell
# 使用开发配置
$env:KV_STUDIO_OPERATOR_CONFIG = "C:\Config\dev_config.json"

# 使用生产配置
$env:KV_STUDIO_OPERATOR_CONFIG = "C:\Config\prod_config.json"
```

## 常见配置问题

### 问题 1：配置文件未找到

**症状：**
```
Error: Cannot find config file
```

**解决：**
```powershell
# 检查环境变量
echo $env:KV_STUDIO_OPERATOR_CONFIG

# 如果为空，设置它
$env:KV_STUDIO_OPERATOR_CONFIG = "$env:APPDATA\Codex\kv-studio-operator\config.json"

# 检查文件是否存在
Test-Path $env:KV_STUDIO_OPERATOR_CONFIG
```

### 问题 2：路径包含中文

**症状：**
路径解析错误或文件找不到

**解决：**
- ✅ 使用 UTF-8 编码保存配置文件
- ✅ 或避免使用中文路径

### 问题 3：JSON 格式错误

**症状：**
```
Error: Invalid JSON
```

**解决：**
```powershell
# 验证 JSON 格式
Get-Content "config.json" | ConvertFrom-Json

# 如果报错，使用在线 JSON 验证工具修复
```

**常见错误：**
- 缺少逗号或多余逗号
- 缺少引号
- 反斜杠未转义（应为 `\\`）

## 配置模板

### 最小配置

```json
{
  "kvs_exe": "C:\\Program Files\\KEYENCE\\KV STUDIO\\Kvs.exe",
  "work_root": "C:\\Temp\\KeyenceWork",
  "wiki_root": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\ManualHelp\\2052\\htmlhelp",
  "admin_user": "Administrator"
}
```

### 推荐配置

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

### 高级配置

```json
{
  "kvs_exe": "C:\\Program Files\\KEYENCE\\KV STUDIO\\Kvs.exe",
  "work_root": "D:\\KeyenceWork",
  "wiki_root": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\ManualHelp\\2052\\htmlhelp",
  "admin_user": "Administrator",
  "runner_timeout_seconds": 600,
  "local_variable_paste_format": "kv_default",
  "advanced": {
    "ui_guard_retry_count": 5,
    "focus_check_interval_ms": 300,
    "clipboard_safety_enabled": true,
    "screenshot_on_success": false,
    "verbose_logging": false
  }
}
```

## 下一步

- 📖 阅读 [安装指南](installation.md) 了解如何设置配置
- 🚀 查看 [快速开始](quick-start.md) 开始使用
- 🔧 参考 [故障排除](guide/troubleshooting.md) 解决配置问题

---

**需要帮助？** 查看 [故障排除](guide/troubleshooting.md) 或 [提交 Issue](https://github.com/xxrust/KeyenceAgent/issues)。
