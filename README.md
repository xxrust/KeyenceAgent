# KeyenceAgent

KeyenceAgent 是面向 KEYENCE KV STUDIO 的 Codex skill 套件。它把 KEYENCE 专有知识查询、PLC 程序设计和 KV STUDIO 桌面执行分成三个独立责任边界。

```text
自然语言任务
    |
    v
知识查询 -> PLC 程序与脚手架 -> 客户态 workflow -> 同次运行 artifacts
    |              |                    |                 |
    v              v                    v                 v
官方证据      MNM/变量/FB          KV STUDIO UI      result.json
```

## 组成

| Skill | 职责 |
| --- | --- |
| `kv-studio-kb-programming` | 查询本机 KEYENCE Wiki V2，提供语法、模块、地址和通信证据。 |
| `keyence-plc-programmer` | 设计和修复 PLC 程序、MNM、变量、用户 FB 与项目复刻方案。 |
| `kv-studio-operator` | 通过已发布 workflow、scaffold tool 和 Gate 操作 KV STUDIO。 |

## 当前能力边界

| 能力 | 状态 |
| --- | --- |
| 新建 KV-X310 项目、导入 MNM、写入变量、转换并复制结果 | 已发布客户态 workflow |
| 多 MNM、用户功能块、功能块自变量、已有项目修复 | 已发布或受 Gate 约束 |
| MNM 导出和项目 inventory | 已发布入口 |
| EtherCAT、EtherNet/IP、扩展单元、单元首地址 | `ROUTE_RESEARCH_REQUIRED` |
| EtherCAT ESI 注册 | `KV_ETHERCAT_ESI_REGISTRATION_UNSTABLE` |

客户态入口只来自 [`kv-studio-operator/scripts/script_manifest.json`](kv-studio-operator/scripts/script_manifest.json) 中 `customer_callable=true` 的条目。`runner_children`、`workflow_tools`、`guards`、`probes` 和根级 `configure_kv_*.ps1` 属于内部实现或研究路线。

## 运行条件

- Windows 10/11
- Windows PowerShell 5.1
- KEYENCE KV STUDIO KVS12
- Codex
- 本机 KEYENCE Wiki V2 知识库；大型数据库不包含在本 Git 仓库中

## 普通安装

仓库放在独立目录，安装脚本把三个 skill 复制到 Codex skills 目录。

```powershell
git clone https://github.com/xxrust/KeyenceAgent.git `
  "$env:USERPROFILE\KeyenceAgent"

cd "$env:USERPROFILE\KeyenceAgent"

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\setup_keyence_agent.ps1
```

The initial `Bypass` is required only for a ZIP-downloaded checkout: Windows
may mark its unsigned PowerShell files with `Zone.Identifier`. The setup
script removes that download mark from the repository and installed skills
while leaving `RemoteSigned` unchanged. Later script calls can run normally.

不要把仓库直接克隆到 `%USERPROFILE%\.codex\skills`。安装脚本会配置：

- 三个 KEYENCE skills
- KV STUDIO `Kvs.exe` 路径
- 一次性工作目录
- Wiki V2 根目录
- 可选的 Windows DPAPI 管理员凭据

检查安装状态：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\setup_keyence_agent.ps1 -Status
```

## 开发模式

开发机使用目录联接。独立仓库是唯一物理源码，Codex 仍从 `.codex\skills` 自动发现三个 skill。

```powershell
cd "$env:USERPROFILE\KeyenceAgent"

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\install_keyence_dev_links.ps1 `
  -BackupExisting

powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\assert_keyence_dev_links.ps1
```

开发链路：

```text
编辑独立仓库
    -> 目录联接即时呈现到 .codex\skills
    -> Codex 调用真实 skill
    -> Gate 与 artifacts 验证
    -> Git commit
    -> GitHub push
```

目录联接消除了仓库与测试副本之间的双向同步。新增或修改 skill 元数据后，启动新 Codex 会话以重新加载。

完整开发规则见 [CONTRIBUTING.md](CONTRIBUTING.md)。

## 知识库配置

Wiki V2 保持为外部数据资产，例如：

```text
C:\Users\Public\Documents\KEYENCE\KVS12\ManualHelp\2052\htmlhelp\llm-wiki-v2-keyence
```

本机配置文件位于：

```text
%APPDATA%\Codex\kv-studio-operator\config.json
```

核心字段：

```json
{
  "kvs_exe": "D:\\KEYENCE\\KVS12G\\KVS12\\KVS\\Kvs.exe",
  "work_root": "C:\\KvAgentWork",
  "wiki_root": "C:\\path\\to\\llm-wiki-v2-keyence",
  "timeout_seconds": 600,
  "local_paste_format": "NameType"
}
```

`kvs_exe` 是机器相关配置。README 中的路径仅用于展示字段格式。

## 验证

修改 operator 后至少运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File .\scripts\test_keyence_agent.ps1
```

该检查把开发联接、agent boundary Gate、UI guard Gate 和 `git diff --check` 汇总到同次运行的 `result.json`。PLC 项目成功仍以同次运行的 `mvp_result.json`、转换结果文本和 clean-state 证据为准。

## 文档

- [安装说明](docs/installation.md)
- [快速开始](docs/quick-start.md)
- [开发与同步](CONTRIBUTING.md)
- [配置说明](docs/configuration.md)
- [项目结构](docs/project-structure.md)

## 许可证

仓库代码采用 [MIT License](LICENSE)。KEYENCE、KV STUDIO 和相关产品名称归其权利人所有。KEYENCE 官方手册和本地 Wiki 数据库不随本仓库再分发。
