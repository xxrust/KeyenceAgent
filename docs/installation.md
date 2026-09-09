# 安装说明

KeyenceAgent 仓库保存三个 KEYENCE skill 的发布源码。Codex 安装目录保存运行入口，本机配置和工作产物保存在仓库外。

## 运行结构

```text
独立 Git 仓库
    -> setup_keyence_agent.ps1
    -> %USERPROFILE%\.codex\skills\<skill>
    -> %APPDATA%\Codex\kv-studio-operator\config.json
    -> %LOCALAPPDATA%\KeyenceAgent\Work
```

## 前置条件

- Windows 10/11
- Windows PowerShell 5.1
- Git
- KEYENCE KV STUDIO KVS12
- Codex
- 已准备的 `llm-wiki-v2-keyence` 目录

## 普通用户安装

```powershell
git clone https://github.com/xxrust/KeyenceAgent.git `
  "$env:USERPROFILE\KeyenceAgent"

cd "$env:USERPROFILE\KeyenceAgent"

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\setup_keyence_agent.ps1
```

The first invocation uses `-ExecutionPolicy Bypass` because a ZIP download may
carry Windows `Zone.Identifier` metadata and `RemoteSigned` will block unsigned
scripts. Setup removes that metadata from the repository and installed skill
PowerShell files without changing the system execution policy. After setup,
scripts can be loaded directly in the normal user session.

按提示填写 `Kvs.exe`、一次性工作目录和 Wiki V2 根目录。管理员凭据使用 Windows DPAPI 写入用户配置目录，不进入 Git 仓库。

验证：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\setup_keyence_agent.ps1 -Status
```

## 开发者安装

开发者使用目录联接，让 Codex 直接运行独立仓库中的源码：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\install_keyence_dev_links.ps1 `
  -BackupExisting

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\assert_keyence_dev_links.ps1
```

原有 skill 目录会移动到 `%LOCALAPPDATA%\KeyenceAgent\DevLinkBackups\<timestamp>`。联接安装器拒绝覆盖已有备份和指向其他位置的联接。

开发流程见 [../CONTRIBUTING.md](../CONTRIBUTING.md)。

## 更新

普通安装：

```powershell
cd "$env:USERPROFILE\KeyenceAgent"
git pull --ff-only
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\setup_keyence_agent.ps1 -Configure skills
```

开发联接安装：

```powershell
cd "$env:USERPROFILE\KeyenceAgent"
git pull --ff-only
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\assert_keyence_dev_links.ps1
```

开发联接始终读取当前工作树，不需要再次复制。
