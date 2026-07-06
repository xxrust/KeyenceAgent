# 故障排除指南

本指南涵盖使用 KeyenceAgent 时的常见问题和解决方案。

## 目录

- [安装问题](#安装问题)
- [配置问题](#配置问题)
- [运行时问题](#运行时问题)
- [编译错误](#编译错误)
- [性能问题](#性能问题)
- [调试技巧](#调试技巧)

---

## 安装问题

### 找不到 KV STUDIO

**症状：**
```
kvs_exe: missing
```

**原因：** KV STUDIO 未安装或路径不正确

**解决方案：**

1. 确认 KV STUDIO 已安装
2. 查找 Kvs.exe：
   ```powershell
   Get-ChildItem "C:\Program Files" -Recurse -Filter "Kvs.exe" -ErrorAction SilentlyContinue
   Get-ChildItem "C:\Program Files (x86)" -Recurse -Filter "Kvs.exe" -ErrorAction SilentlyContinue
   ```
3. 重新配置路径：
   ```powershell
   .\setup_keyence_agent.ps1 -Configure kvs_exe
   ```

### Skills 未安装

**症状：** Claude Code 提示找不到 skill

**原因：** Skills 未复制到正确位置

**解决方案：**
```powershell
# 检查 skills 目录
ls $env:USERPROFILE\.codex\skills

# 应该看到：
# - kv-studio-kb-programming/
# - keyence-plc-programmer/
# - kv-studio-operator/

# 如果缺失，重新运行安装
.\setup_keyence_agent.ps1 -Configure skills
```

### 知识库路径错误

**症状：** AI 无法查询指令语法

**原因：** Wiki 路径不正确

**解决方案：**
```powershell
# 检查知识库是否存在
$config = Get-Content "$env:KV_STUDIO_OPERATOR_CONFIG" | ConvertFrom-Json
Test-Path $config.wiki_root

# 如果返回 False，重新配置
.\setup_keyence_agent.ps1 -Configure wiki_root

# 常见路径：
# C:\Users\Public\Documents\KEYENCE\KVS12\ManualHelp\2052\htmlhelp (中文)
# C:\Users\Public\Documents\KEYENCE\KVS12\ManualHelp\1041\htmlhelp (日文)
```

---

## 配置问题

### 配置文件未找到

**症状：**
```
Cannot find config file at: ...
```

**原因：** 环境变量未设置或路径错误

**解决方案：**
```powershell
# 检查环境变量
echo $env:KV_STUDIO_OPERATOR_CONFIG

# 如果为空，手动设置
$configPath = "$env:APPDATA\Codex\kv-studio-operator\config.json"
$env:KV_STUDIO_OPERATOR_CONFIG = $configPath

# 永久设置（重启后生效）
[Environment]::SetEnvironmentVariable('KV_STUDIO_OPERATOR_CONFIG', $configPath, 'User')
```

### 凭据存储失败

**症状：** 每次运行都要求输入密码

**原因：** 凭据未正确存储

**解决方案：**
```powershell
# 重新存储凭据
.\setup_keyence_agent.ps1 -Configure credential

# 检查凭据文件是否存在
Test-Path "$env:APPDATA\Codex\kv-studio-operator\credentials.xml"
```

### 工作目录权限问题

**症状：** 无法创建项目文件

**原因：** 工作目录没有写入权限

**解决方案：**
```powershell
# 检查工作目录权限
$config = Get-Content "$env:KV_STUDIO_OPERATOR_CONFIG" | ConvertFrom-Json
$acl = Get-Acl $config.work_root
$acl.Access | Format-Table -AutoSize

# 或更改工作目录到有权限的位置
.\setup_keyence_agent.ps1 -Configure work_root
```

---

## 运行时问题

### KV STUDIO 启动失败

**症状：** 脚本卡住，KV STUDIO 窗口未出现

**可能原因：**
1. KV STUDIO 已经在运行
2. 路径错误
3. 权限不足

**解决方案：**

**步骤 1：** 关闭现有 KV STUDIO 实例
```powershell
# 查找 KV STUDIO 进程
Get-Process -Name "Kvs" -ErrorAction SilentlyContinue

# 强制关闭（如果存在）
Stop-Process -Name "Kvs" -Force -ErrorAction SilentlyContinue
```

**步骤 2：** 检查路径
```powershell
$config = Get-Content "$env:KV_STUDIO_OPERATOR_CONFIG" | ConvertFrom-Json
Test-Path $config.kvs_exe
```

**步骤 3：** 手动测试启动
```powershell
& $config.kvs_exe
```

### 脚本超时

**症状：**
```
Runner timeout after 300 seconds
```

**原因：** 操作复杂或系统慢

**解决方案：**

编辑配置文件，增加超时时间：
```json
{
  "runner_timeout_seconds": 600
}
```

或使用安装脚本：
```powershell
.\setup_keyence_agent.ps1 -Configure advanced
# 输入新的超时时间（秒）
```

### UI 焦点丢失

**症状：** 脚本报错 "Window focus lost"

**原因：** 运行过程中切换了窗口

**解决方案：**
1. **不要在脚本运行时操作其他窗口**
2. 重新运行脚本
3. 如果频繁发生，检查 `artifacts/` 目录中的错误截图

### 弹窗阻塞

**症状：** 脚本卡在某个步骤

**原因：** KV STUDIO 弹出未预期的对话框

**解决方案：**
1. 手动关闭弹窗
2. 查看工作目录下的 `artifacts/` 文件夹
3. 找到 `failure.json` 或错误截图
4. 将错误信息反馈给 AI

---

## 编译错误

### 变量未定义

**症状：**
```
错误: 变量 'XXX' 未定义
```

**原因：** 变量表未正确导入

**解决方案：**

让 AI 重新生成变量表：
```
我的项目编译报错："变量 TempSensor1 未定义"，请修复
```

AI 会：
1. 分析当前变量表
2. 找出缺失的变量
3. 更新变量表
4. 重新导入

### 指令语法错误

**症状：**
```
错误: 指令 'XXX' 语法不正确
```

**原因：** 生成的 MNM 语法错误

**解决方案：**

1. 将完整错误信息反馈给 AI
2. AI 会查询知识库确认正确语法
3. 修复 MNM 并重新导入

### 功能块调用错误

**症状：**
```
错误: 功能块 'XXX' 未找到
```

**原因：** 功能块未正确导入或名称不匹配

**解决方案：**

检查功能块状态：
```
检查项目中的功能块定义，确认 AverageFilter 是否正确导入
```

AI 会：
1. 导出项目清单
2. 检查功能块定义
3. 修复名称或重新导入

### 类型不匹配

**症状：**
```
错误: 类型不匹配，期望 INT，实际 BOOL
```

**原因：** 变量类型定义错误

**解决方案：**

让 AI 修复类型：
```
编译报错类型不匹配，请检查并修复所有变量类型定义
```

---

## 性能问题

### 脚本运行缓慢

**症状：** 每个操作都很慢

**可能原因：**
1. 工作目录在机械硬盘上
2. 系统资源不足
3. 超时设置过长

**解决方案：**

**优化 1：** 迁移工作目录到 SSD
```powershell
.\setup_keyence_agent.ps1 -Configure work_root
# 输入 SSD 上的路径
```

**优化 2：** 减少超时时间（如果操作通常很快完成）
```json
{
  "runner_timeout_seconds": 120
}
```

**优化 3：** 清理工作目录
```powershell
$config = Get-Content "$env:KV_STUDIO_OPERATOR_CONFIG" | ConvertFrom-Json
Remove-Item -Recurse -Force "$($config.work_root)\*" -Exclude "*.kpr"
```

### AI 响应缓慢

**症状：** AI 思考时间很长

**原因：** 知识库查询或程序生成复杂

**解决方案：**
1. 将复杂需求拆分成小步骤
2. 先创建简单项目，再逐步增加功能
3. 使用更快的 AI 模型（如果可选）

---

## 调试技巧

### 查看运行日志

每次运行后，工作目录下会生成 `artifacts/` 文件夹：

```
work_root/
└── your_project/
    ├── artifacts/
    │   ├── result.json           # 运行结果
    │   ├── failure.json          # 失败详情（如果失败）
    │   ├── screenshot_*.png      # 错误截图
    │   ├── compile_result.txt    # 编译输出
    │   └── runner.log            # 详细日志
    ├── scaffold.model.json       # 项目模型
    ├── modules/                  # MNM 文件
    └── your_project.kpr          # KV STUDIO 项目
```

### 检查 result.json

```powershell
# 查看最近一次运行结果
$config = Get-Content "$env:KV_STUDIO_OPERATOR_CONFIG" | ConvertFrom-Json
$latestProject = Get-ChildItem "$($config.work_root)" -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
Get-Content "$($latestProject.FullName)\artifacts\result.json" | ConvertFrom-Json | Format-List
```

关键字段：
- `ok`: 是否成功（`true`/`false`）
- `error_code`: 错误代码
- `step`: 失败的步骤
- `clean_end_state`: KV STUDIO 是否正常关闭

### 查看编译输出

```powershell
Get-Content "$($latestProject.FullName)\artifacts\compile_result.txt"
```

### 查看错误截图

```powershell
# 打开最新的错误截图
$screenshots = Get-ChildItem "$($latestProject.FullName)\artifacts" -Filter "screenshot_*.png"
if ($screenshots) {
    & $screenshots[0].FullName
}
```

### 手动检查 KV STUDIO 项目

1. 打开 KV STUDIO
2. 打开项目：`work_root\your_project\your_project.kpr`
3. 检查：
   - 程序模块是否正确导入
   - 变量表是否完整
   - 功能块是否存在
4. 手动编译，查看详细错误

### 启用详细日志

编辑配置文件，添加调试选项：

```json
{
  "advanced": {
    "verbose_logging": true,
    "screenshot_on_success": true
  }
}
```

### 重现问题

如果问题不稳定，使用 repeat runner：

```powershell
cd "work_root\your_project"
# 重复运行 3 次
.\run_kv_mvp_repeat.ps1 -RequiredPasses 3
```

### 联系支持

如果以上方法都无法解决问题，请：

1. 收集以下信息：
   - Windows 版本：`(Get-WmiObject -class Win32_OperatingSystem).Caption`
   - KV STUDIO 版本
   - `result.json` 内容
   - `failure.json` 内容（如果存在）
   - 错误截图

2. 提交 Issue：https://github.com/xxrust/KeyenceAgent/issues/new

3. 包含以下内容：
   - 问题描述
   - 重现步骤
   - 预期行为
   - 实际行为
   - 收集的日志和截图

---

## 常见错误代码

| 错误代码 | 含义 | 解决方法 |
|----------|------|----------|
| `KV_CHECKLIST_MISSING` | 缺少必需的 checklist 文件 | 重新生成脚手架 |
| `KV_SOURCE_SNAPSHOT_STALE` | 项目快照过期 | 重新导出项目快照 |
| `KV_MNM_SAME_NAME_IMPORT_REQUIRES_PREDELETE` | 模块名称冲突 | 删除现有模块或重命名 |
| `KV_VARIABLE_PASTE_NOT_PERSISTED` | 变量粘贴未保存 | 检查变量表格式 |
| `KV_COMPILE_FAILED` | 编译失败 | 查看编译输出详情 |
| `KV_WINDOW_FOCUS_LOST` | 窗口焦点丢失 | 重新运行，不要切换窗口 |
| `KV_UNEXPECTED_POPUP` | 未预期的弹窗 | 查看截图，手动处理 |
| `KV_TIMEOUT` | 操作超时 | 增加超时设置 |

---

## 最佳实践

### 避免问题的建议

1. **运行前准备：**
   - 确保 KV STUDIO 未在后台运行
   - 关闭不必要的窗口
   - 不要在运行时操作电脑

2. **项目管理：**
   - 使用有意义的项目名称
   - 定期清理工作目录
   - 保留重要项目的备份

3. **调试习惯：**
   - 遇到错误先查看 `artifacts/` 目录
   - 保存 `result.json` 和 `failure.json`
   - 记录重现步骤

4. **性能优化：**
   - 工作目录放在 SSD
   - 控制项目复杂度
   - 分步骤创建复杂项目

---

**还有问题？**
- 📖 查看 [完整文档](../README.md)
- 💬 加入 [GitHub Discussions](https://github.com/xxrust/KeyenceAgent/discussions)
- 🐛 [报告 Bug](https://github.com/xxrust/KeyenceAgent/issues)
