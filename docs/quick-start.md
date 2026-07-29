# 快速开始

本流程验证知识查询、skill 安装和客户态 KV STUDIO workflow 的入口条件。

## 1. 安装

```powershell
git clone https://github.com/xxrust/KeyenceAgent.git `
  "$env:USERPROFILE\KeyenceAgent"
cd "$env:USERPROFILE\KeyenceAgent"
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_keyence_agent.ps1
```

开发者改用：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\install_keyence_dev_links.ps1 `
  -BackupExisting
```

## 2. 验证安装

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\setup_keyence_agent.ps1 -Status
```

开发者同时运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\assert_keyence_dev_links.ps1
```

## 3. 查询 KEYENCE 证据

在 Codex 中提出：

```text
根据本机 KEYENCE Wiki V2，查询 KV STUDIO 中 ST 赋值语句和 BOOL 变量的官方语法。
```

查询结果应包含来源类型和可打开的证据路径。

## 4. 创建 PLC 脚手架

在 Codex 中提出：

```text
使用 keyence-plc-programmer 和 kv-studio-operator，创建一个一次性 KV-X310 项目，
包含启动、停止和自保持逻辑。先生成并验证 scaffold，再运行客户态 workflow。
```

Agent 应执行：

1. 查询 KEYENCE 专有语法。
2. 生成 `scaffold.model.json`、MNM 和变量文件。
3. 完成 `CHECKLIST.md` 并运行 scaffold validator。
4. 从 `script_manifest.json` 选择客户态 workflow。
5. 读取同次运行的 `mvp_result.json` 和转换结果。

## 5. 验收

有效成功证据包括：

- `scaffold_validation.json.ok == true`
- `mvp_result.json.ok == true`
- `compile_result_contains_ok == true`
- 当前运行的转换结果文件存在
- KV STUDIO 无遗留配置窗口

EtherCAT、EtherNet/IP、扩展单元和 ESI 注册当前不属于客户态快速开始。相关请求应返回 `ROUTE_RESEARCH_REQUIRED`。
