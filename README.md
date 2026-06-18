# KeyenceAgent

<p align="center">
  <img src="docs/images/keyenceagent-harness-overview.png" alt="KeyenceAgent 架构概览">
</p>

<p align="center">
  <a href="https://github.com/xxrust/KeyenceAgent/commits/master"><img alt="最近提交" src="https://img.shields.io/github/last-commit/xxrust/KeyenceAgent?style=flat-square&logo=git"></a>
  <a href="https://github.com/xxrust/KeyenceAgent"><img alt="仓库大小" src="https://img.shields.io/github/repo-size/xxrust/KeyenceAgent?style=flat-square"></a>
  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=flat-square&logo=powershell&logoColor=white">
  <img alt="KV STUDIO" src="https://img.shields.io/badge/KV%20STUDIO-%E8%84%9A%E6%9C%AC%E6%89%98%E7%AE%A1-008C95?style=flat-square">
  <img alt="MVP" src="https://img.shields.io/badge/MVP-3%E6%AC%A1%E8%BF%9E%E7%BB%AD%E9%80%9A%E8%BF%87-22A06B?style=flat-square">
  <img alt="UI guard" src="https://img.shields.io/badge/UI%E9%97%A8%E7%A6%81-%E5%85%B1%E4%BA%AB%E5%BA%93-0B5FFF?style=flat-square">
</p>

<p align="center">
  <a href="README.md"><img alt="中文" src="https://img.shields.io/badge/%E4%B8%AD%E6%96%87-008C95?style=for-the-badge"></a>
  <a href="README.ja.md"><img alt="日本語" src="https://img.shields.io/badge/%E6%97%A5%E6%9C%AC%E8%AA%9E-22A06B?style=for-the-badge"></a>
</p>

KeyenceAgent 是面向 KEYENCE KV STUDIO 的脚本托管执行框架，用于在智能体参与下创建、更新和验证 PLC 项目。

智能体负责准备意图和验收证据。KV STUDIO 打开之后，从创建项目到捕获编译结果，全部由 runner 脚本执行。

已验证目标环境：

- Windows 10
- Windows 11
- KEYENCE KV STUDIO KVS12

KV STUDIO 本身只适用于 Windows。本仓库以 KVS12 作为说明和测试边界；其他 KV STUDIO 版本可能可用，但不在当前验证承诺内。

对外部署的 Codex skill 是单个打包目录 `keyence-kv-studio/`。它的 `SKILL.md` 是唯一的 KV STUDIO skill 入口；编程、知识库和桌面操作资料都在该目录的 `references/` 与 `scripts/` 内。

## 架构

KeyenceAgent 把推理、执行和验收分成明确边界。

```text
任务请求
  -> 脚手架模型
  -> 脚手架渲染器
  -> 静态门禁
  -> 受保护 KV runner
  -> 同次运行 artifacts
  -> 智能体验收
```

| 层级 | 职责 | 主要产物 |
| --- | --- | --- |
| 脚手架模型 | 描述模块、MNM 源、变量、功能块自变量、项目元数据和验收说明。 | `scaffold.model.json`、`TASK.md`、`VERSION.md` |
| 渲染器 | 把结构化模型转换为 KV STUDIO 可导入文件。 | `modules/<module>/*.mnm`、`modules/<module>/*.tsv`、`scaffold.json` |
| 静态门禁 | 在 KV STUDIO 打开前拒绝危险或不完整输入。 | checklist、变量验证、导入计划、脚手架验证 |
| 受保护 runner | 创建或打开项目、导入 MNM、写入变量、写入功能块自变量、编译并捕获结果文本。 | `mvp_result.json`、`repair_result.json`、`artifacts/` |
| 路线治理 | 记录当前执行路线，防止在键盘、UIA、鼠标和脚本策略之间无证据切换。 | `route-state.json` |

## 核心机制

KeyenceAgent 使用硬执行协议。

| 阶段 | 责任方 | 协议 |
| --- | --- | --- |
| KV STUDIO 打开前 | 智能体 | 编辑脚手架文件，运行验证门禁，然后启动一个 runner 命令。 |
| KV STUDIO 打开期间 | 脚本 | 通过共享 UI guard 执行焦点检查、键盘、鼠标、粘贴、弹窗识别和失败边界控制。 |
| runner 退出后 | 智能体 | 只读取同次运行 artifacts，并根据结果 JSON 与 KV STUDIO 文本决定下一次修改。 |

这个协议控制桌面 IDE 自动化的主要失败模式：智能体一边观察实时 UI，一边临时操作，一边把旧错误错误归因到新动作。

## 当前能力

| 能力 | 状态 |
| --- | --- |
| 新建项目 | 已通过 repeat runner 验证。 |
| 多 MNM 导入 | 支持多模块，并使用每个模块独立的变量文件。 |
| 全局与局部变量重建 | 粘贴前验证，粘贴后通过 runner 证据验收。 |
| 已有项目更新 | 修改 `.kpr` 前使用快照门禁和导入计划门禁。 |
| 编译结果捕获 | 从结果树提取文本写入 `compile_result_copied.txt`，剪贴板只是可选镜像证据。 |
| 功能块创建 | `MODULE_TYPE:2` 的 MNM 可导入为用户功能块。 |
| 功能块自变量表 | 已通过受保护 runner 写入必需列。 |
| 功能块实例和调用链路 | 已在可编译通过的平滑滤波功能块项目中验证。 |
| 后备模块导入 | 已通过 `category=standby` 验证；runner 在 KV STUDIO 的“选择程序种类”窗口选择“后备模块”。 |
| 重复性门禁 | 要求连续成功；最新 FB MVP 已连续 3 次通过。 |

## Runner 流程

<p align="center">
  <img src="docs/images/kv-repair-loop.png" alt="确定性 KV STUDIO runner 闭环">
</p>

1. 创建或更新脚手架模型。
2. 渲染 MNM 和变量适配文件。
3. 在 KV STUDIO 打开前运行静态门禁。
4. 新项目运行 `run_kv_mvp_scaffold.ps1`，已有项目运行 `run_kv_mvp_repair_existing_project.ps1`。
5. 子步骤第一次失败时停止，并检查同次 artifact 目录。
6. 只用结果 JSON 和编译结果文本判定成功。
7. 使用 `run_kv_mvp_repeat.ps1` 证明稳定性。

## 仓库结构

```text
.
|-- README.md
|-- README.zh-CN.md
|-- README.ja.md
|-- setup_keyence_agent.ps1
|-- docs/
|   `-- images/
|-- keyence-kv-studio/
|   |-- SKILL.md
|   |-- references/
|   |-- scripts/
|   `-- assets/
|-- agent-harness-project-standard/
`-- route-governance/
```

## Windows 本机部署

KeyenceAgent 在运行 KV STUDIO 的 Windows 机器上作为文本化 harness 部署；这台机器可以是物理 Windows 电脑，也可以是 Windows 虚拟机。

KV STUDIO 相关工作安装或复制单个打包 skill `keyence-kv-studio/` 即可。

需要拷贝或克隆这些运行目录：

| 目录 | 是否必须 | 作用 |
| --- | --- | --- |
| `keyence-kv-studio/` | 必须 | KV STUDIO 路由、references、scripts 和样例 assets 的单一发布包。 |
| `agent-harness-project-standard/` | 建议 | agent 准备、脚本执行、artifact 验收的 harness 标准。 |
| `route-governance/` | 建议 | 脆弱 UI 自动化和重复失败复盘中的路线变更约束。 |
| `llm-wiki-v2-keyence/` | 编程依据必需 | 本地 Wiki V2 数据库和查询脚本。它可以保留在 KEYENCE `htmlhelp` 下，也可以拷贝到 harness 旁边，只要配置文件指向实际路径。 |
| `docs/` 与 `README*.md` | 建议 | 人类部署说明和架构文档。 |

最稳妥的部署方式是直接复制或克隆整个仓库：

```powershell
git clone https://github.com/xxrust/KeyenceAgent.git "$env:USERPROFILE\KeyenceAgent"
cd "$env:USERPROFILE\KeyenceAgent"
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_keyence_agent.ps1
```

`setup_keyence_agent.ps1` 是非 AI 交互式配置脚本。它会通过命令行问答完成 `keyence-kv-studio` 打包 skill 安装、KV STUDIO 路径、工作目录、Wiki V2 知识库路径、默认管理员账号和 DPAPI 凭据写入。

常用安装模式：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_keyence_agent.ps1 -h
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_keyence_agent.ps1 -Status
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_keyence_agent.ps1 -Configure credential
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_keyence_agent.ps1 -Configure kvs_exe,wiki_root
```

`-Status` 会报告哪些项目已配置、哪些项目缺失。`-Configure` 支持 `all`、`skills`、`config`、`kvs_exe`、`work_root`、`wiki_root`、`admin_user`、`credential`、`advanced`。脚本会检测中/日/英系统语言；为了兼容 Windows PowerShell，命令行提示保持 ASCII-safe，中文说明写在本文档中。

runner 默认把一次性项目和证据写到 `%LOCALAPPDATA%\KeyenceAgent\Work`。这个目录应放在仓库外，避免把 `.kpr`、截图、日志和编译 artifacts 提交进 git。

## 本机配置

每个 Windows 用户需要一个本机配置文件。模板在：

```text
keyence-kv-studio\scripts\kv-studio-operator\config\kv-studio-operator.example.json
```

本机配置文件放在以下任一路径：

```text
%APPDATA%\Codex\kv-studio-operator\config.json
keyence-kv-studio\scripts\kv-studio-operator\config\kv-studio-operator.local.json
```

普通配置只保存机器相关根路径。派生路径由脚本解析：

```json
{
  "kvs_exe": "C:\\Program Files (x86)\\KEYENCE\\KVS12G\\KVS12\\KVS\\Kvs.exe",
  "work_root": "%LOCALAPPDATA%\\KeyenceAgent\\Work",
  "admin_credential_path": "%APPDATA%\\Codex\\kv-studio-operator\\credentials.xml",
  "admin_user_default": "Administrator",
  "wiki_root": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\ManualHelp\\2052\\htmlhelp\\llm-wiki-v2-keyence"
}
```

`work_root` 会派生 `mvp_runs`、`mvp_repair_runs` 和 `mvp_repeat_runs`。`wiki_root` 会派生 `wiki.v2.cleaned.db` 和 `scripts\wiki_query.py`。`timeout_seconds`、`local_paste_format`、`mvp_out_root`、`repair_out_root`、`repeat_out_root`、`wiki_cleaned_db`、`wiki_query_script` 等高级字段仍可作为显式覆盖，但安装流程默认不询问这些字段。

`Local config file path or directory` 可以直接回车使用默认配置文件，也可以输入目录，例如 `$env:LOCALAPPDATA\KeyenceAgent\Config`；安装脚本会在该目录写入 `config.json`。

不要把 KV STUDIO 管理员密码写入 JSON。安装时，`setup_keyence_agent.ps1` 会自动使用 `%APPDATA%\Codex\kv-studio-operator\credentials.xml`，只要求用户输入 KV STUDIO 管理员账号和密码，并自动创建目录/文件，再用 Windows DPAPI 保存凭据。新用户不需要填写凭据文件路径。也可以单独运行：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\KeyenceAgent\keyence-kv-studio\scripts\kv-studio-operator\set_kv_admin_credential.ps1"
```

runner 会自动读取 `%APPDATA%` 下的配置，也可以显式传入：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\KeyenceAgent\keyence-kv-studio\scripts\kv-studio-operator\run_kv_mvp_scaffold.ps1" `
  -ConfigPath "$env:APPDATA\Codex\kv-studio-operator\config.json" `
  -ScaffoldRoot "$env:LOCALAPPDATA\KeyenceAgent\Work\scaffolds\example"
```

知识库查询也自动读取同一份配置：

```powershell
python "$env:USERPROFILE\KeyenceAgent\keyence-kv-studio\scripts\kv-studio-kb-programming\query_keyence_kb.py" "ST 赋值语句" --limit 5 --evidence
```

Wiki 路径优先级是：命令行 `--db/--query-script`、`KEYENCE_WIKI_*` 环境变量、共享 KeyenceAgent 配置、脚本内置默认路径。

## 关键脚本

| 脚本 | 用途 |
| --- | --- |
| `setup_keyence_agent.ps1` | clone 后的一键本机配置入口：安装 skills、生成本机 config、保存 DPAPI 凭据、设置配置路径环境变量。 |
| `keyence-kv-studio/scripts/kv-studio-operator/Import-KvStudioOperatorConfig.ps1` | 读取本机 KV STUDIO 路径、输出目录、超时和凭据文件路径。 |
| `keyence-kv-studio/scripts/kv-studio-operator/render_kv_mvp_scaffold_model.ps1` | 把结构化项目模型渲染为按模块分组的 MNM 与变量文件。 |
| `keyence-kv-studio/scripts/kv-studio-operator/validate_kv_mvp_scaffold.ps1` | 验证 checklist、schema、模块类型、变量、功能块声明和脚手架一致性。 |
| `keyence-kv-studio/scripts/kv-studio-operator/assert_kv_mnm_import_plan.ps1` | 同名 MNM 导入前要求明确预删除计划。 |
| `keyence-kv-studio/scripts/kv-studio-operator/run_kv_mvp_scaffold.ps1` | 创建全新 KV STUDIO 项目并运行完整 MVP 路径。 |
| `keyence-kv-studio/scripts/kv-studio-operator/run_kv_mvp_repair_existing_project.ps1` | 基于快照门禁把脚手架更新应用到已有项目。 |
| `keyence-kv-studio/scripts/kv-studio-operator/run_kv_mvp_repeat.ps1` | 执行连续成功门禁。 |
| `keyence-kv-studio/scripts/kv-studio-operator/guards/kv_ui_guard.ps1` | 所有 KV UI 子脚本共用的焦点、弹窗、键盘、鼠标和剪贴板保护库。 |

## 验证证据

最新功能块 MVP 已完成完整链路：

```text
功能块 MNM 导入
-> 扫描模块 MNM 导入
-> 功能块自变量表粘贴
-> 全局/局部变量粘贴
-> 编译
-> 结果树文本捕获
-> 基线快照写入
```

最新 repeat gate：

```text
required_consecutive_passes: 3
attempts_completed: 3
consecutive_passes: 3
status: pass
```

编译 oracle 是同次运行的 KV STUDIO 结果文本：

```text
转换结果 OK
错误数量: 0
警告数量: 0
```

## 设计原则

| 原则 | 含义 |
| --- | --- |
| 先构建 harness | 手工成功路线必须变成脚本托管 harness，才能进入 skill 承诺。 |
| UI 前置 checklist | 缺少 checklist 时 KV STUDIO 脚本直接失败。 |
| 同次证据 | 旧截图、旧日志和旧项目状态不作为成功证明。 |
| 共享 UI guard | 焦点和弹窗处理放在同一套库里，而不是每个脚本局部修补。 |
| 文件化 oracle | 编译与粘贴结果先落成 artifacts，再由智能体推理。 |
| 路线治理 | 路线变化必须说明失败机制和新控制手段。 |

## 未来规划

| 方向 | 计划 |
| --- | --- |
| 功能块 | 在格式探针证明稳定后，扩展功能块自变量注释和更多可选列。 |
| 已有项目 | 为非 harness 创建的项目建立更完整的导出/导入快照闭环。 |
| 模块类别 | 后备模块已验证；中断程序仍需完成 CPU 系统中断设置与中断允许路径脚本化。 |
| 功能块组合 | 覆盖嵌套 FB 实例、多调用点和实例作用域审计。 |
| 速度 | 在保持 bounded 失败行为的前提下减少不必要等待。 |
| 子智能体验证 | 要求独立子智能体只按 skill 调用 runner，完成同一 MVP 的连续成功。 |
| 文档 | 增加架构图、失败分类和 runner contract 示例。 |
