# KeyenceAgent 开发与同步

KeyenceAgent 使用一个独立 Git 仓库管理源码，并通过 Windows 目录联接把三个开发中 skill 暴露给 Codex。

## 唯一真源

```text
C:\Users\<user>\KeyenceAgent\       Git 仓库和唯一源码
    |
    +-- kv-studio-kb-programming\
    +-- keyence-plc-programmer\
    `-- kv-studio-operator\

C:\Users\<user>\.codex\skills\     Codex 发现入口
    |
    +-- kv-studio-kb-programming -> 仓库目录
    +-- keyence-plc-programmer   -> 仓库目录
    `-- kv-studio-operator       -> 仓库目录
```

开发机不维护第二份 skill 副本。目录联接让仓库修改立即出现在 `.codex\skills`。新增、删除或修改 `SKILL.md` 后，启动新的 Codex 会话以重新加载 skill 元数据。

## 首次建立开发入口

```powershell
git clone https://github.com/xxrust/KeyenceAgent.git "$env:USERPROFILE\KeyenceAgent"
cd "$env:USERPROFILE\KeyenceAgent"

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\install_keyence_dev_links.ps1 `
  -BackupExisting

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\assert_keyence_dev_links.ps1
```

`-BackupExisting` 会把已有安装目录移到 `%LOCALAPPDATA%\KeyenceAgent\DevLinkBackups\<timestamp>`，然后创建联接。脚本不会覆盖已有备份，也不会替换指向其他位置的联接。

## 日常开发流程

1. 在独立仓库创建分支。
2. 只编辑仓库内文件。
3. 从 `.codex\skills` 路径调用 skill，执行真实 Codex 测试。
4. 运行开发联接检查和 KV operator Gate。
5. 检查 `git diff --check`、`git status` 和暂存差异。
6. 提交并推送分支。

```powershell
cd "$env:USERPROFILE\KeyenceAgent"
git fetch origin
git switch -c feature/<name> origin/master

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\test_keyence_agent.ps1

git status --short
```

## 版本边界

- Git commit SHA 是开发版本标识。
- `kv-studio-operator/scripts/script_manifest.json` 是客户态可调用入口的唯一清单。
- `customer_callable=false` 的配置脚本保持研究状态。
- 本机配置、凭据、工作项目、截图和运行 artifacts 位于仓库外。
- 普通用户安装使用 `setup_keyence_agent.ps1` 复制已提交版本；开发机使用目录联接。

## 禁止的同步方式

- 不在仓库和 `.codex\skills` 之间执行双向覆盖复制。
- 不把 `.codex\skills` 根目录初始化为 KeyenceAgent 仓库。
- 不把本机配置、DPAPI 凭据、Wiki 数据库或运行 artifacts 提交到 Git。
- 不使用 force push 覆盖远端历史。
