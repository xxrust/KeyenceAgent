# KeyenceAgent

<p align="center">
  <img src="docs/images/keyenceagent-harness-overview.png" alt="KeyenceAgent architecture overview">
</p>

<p align="center">
  <a href="https://github.com/xxrust/KeyenceAgent/commits/master"><img alt="Last commit" src="https://img.shields.io/github/last-commit/xxrust/KeyenceAgent?style=flat-square&logo=git"></a>
  <a href="https://github.com/xxrust/KeyenceAgent"><img alt="Repository size" src="https://img.shields.io/github/repo-size/xxrust/KeyenceAgent?style=flat-square"></a>
  <img alt="PowerShell" src="https://img.shields.io/badge/PowerShell-5.1%2B-5391FE?style=flat-square&logo=powershell&logoColor=white">
  <img alt="KV STUDIO" src="https://img.shields.io/badge/KV%20STUDIO-script--owned-008C95?style=flat-square">
  <img alt="MVP" src="https://img.shields.io/badge/MVP-3x%20repeat%20passed-22A06B?style=flat-square">
  <img alt="UI guard" src="https://img.shields.io/badge/UI%20guard-shared%20library-0B5FFF?style=flat-square">
</p>

<p align="center">
  <a href="README.md"><img alt="English" src="https://img.shields.io/badge/English-0B5FFF?style=for-the-badge"></a>
  <a href="README.zh-CN.md"><img alt="Chinese" src="https://img.shields.io/badge/%E4%B8%AD%E6%96%87-008C95?style=for-the-badge"></a>
  <a href="README.ja.md"><img alt="Japanese" src="https://img.shields.io/badge/%E6%97%A5%E6%9C%AC%E8%AA%9E-22A06B?style=for-the-badge"></a>
</p>

KeyenceAgent is a script-owned harness for creating, updating, and validating KEYENCE KV STUDIO PLC projects with agent assistance.

The agent prepares intent and checks evidence. The runner owns every KV STUDIO UI action from project creation through compile-result capture.

Validated target environment:

- Windows 10
- Windows 11
- KEYENCE KV STUDIO KVS12

KV STUDIO is Windows-only. KVS12 is the documented and tested target for this repository; other KV STUDIO versions may work, but they are outside the current validation contract.

The deployable Codex skill is the single package `keyence-kv-studio/`. Its `SKILL.md` is the only KV STUDIO skill entry; programming, knowledge-base, and desktop-operation material lives inside that package under `references/` and `scripts/`.

## Architecture

KeyenceAgent separates reasoning, execution, and verification into explicit boundaries.

```text
Task request
  -> scaffold model
  -> scaffold renderer
  -> static gates
  -> guarded KV runner
  -> same-run artifacts
  -> agent verification
```

| Layer | Responsibility | Main artifacts |
| --- | --- | --- |
| Scaffold model | Describes modules, MNM sources, variables, FB arguments, project metadata, and acceptance notes. | `scaffold.model.json`, `TASK.md`, `VERSION.md` |
| Renderer | Converts structured model data into KV STUDIO adapter files. | `modules/<module>/*.mnm`, `modules/<module>/*.tsv`, `scaffold.json` |
| Static gates | Reject unsafe or incomplete input before KV STUDIO opens. | checklist, variable validation, import plan, scaffold validation |
| Guarded runner | Creates or opens the project, imports MNM, writes variables, writes FB arguments, compiles, and captures result text. | `mvp_result.json`, `repair_result.json`, `artifacts/` |
| Route governance | Records the active route and prevents uncontrolled switching between keyboard, UIA, mouse, and script strategies. | `route-state.json` |

## Core Mechanism

KeyenceAgent uses a hard execution contract.

| Phase | Owner | Contract |
| --- | --- | --- |
| Before KV STUDIO opens | Agent | Edit scaffold files, run validation gates, then launch one runner command. |
| While KV STUDIO is open | Scripts | Use shared guarded UI actions for focus checks, keyboard input, mouse input, paste, modal detection, and recovery boundaries. |
| After runner exits | Agent | Read only same-run artifacts and decide the next change from result JSON and copied KV STUDIO text. |

This contract prevents the main failure mode of desktop IDE automation: an agent watching a live UI, improvising actions, and misattributing stale errors to the latest operation.

## Current Capabilities

| Capability | Status |
| --- | --- |
| Fresh project creation | Verified through repeat runner. |
| Multi-MNM import | Supports multiple modules with per-module variable files. |
| Global and local variable reconstruction | Validated before paste and checked through runner evidence. |
| Existing-project update flow | Uses snapshot and import-plan gates before modifying a `.kpr`. |
| Compile result capture | Extracts result-tree text into `compile_result_copied.txt`; clipboard mirroring is optional evidence. |
| Function block creation | Imports `MODULE_TYPE:2` MNM files as user function blocks. |
| Function block argument table | Writes the required argument columns through guarded runner operation. |
| Function block instance and call path | Verified in a compile-passing smooth-filter project. |
| Standby module import | Verified through `category=standby`; the runner selects `后备模块` in KV STUDIO's program-kind dialog. |
| Repeatability gate | Requires consecutive passing runs; the latest FB MVP passed three consecutive attempts. |

## Runner Workflow

<p align="center">
  <img src="docs/images/kv-repair-loop.png" alt="Deterministic KV STUDIO runner loop">
</p>

1. Build or update a scaffold model.
2. Render MNM and variable adapter files.
3. Run static gates before KV STUDIO opens.
4. Run `run_kv_mvp_scaffold.ps1` for a fresh project or `run_kv_mvp_repair_existing_project.ps1` for an existing project.
5. Stop at the first failed child step and inspect the same-run artifact directory.
6. Accept success only from result JSON plus copied compile text.
7. Prove stability with `run_kv_mvp_repeat.ps1`.

## Repository Layout

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

## Windows Deployment

Deploy the repository as a text-first harness on the Windows machine that runs KV STUDIO. This can be a physical Windows PC or a Windows VM.

For KV STUDIO work, install or copy the single packaged skill `keyence-kv-studio/`.

Copy or clone these runtime folders:

| Folder | Required | Purpose |
| --- | --- | --- |
| `keyence-kv-studio/` | Yes | Single deployable KV STUDIO package with routing, references, scripts, and sample assets. |
| `agent-harness-project-standard/` | Recommended | Harness rules for agent-owned preparation, script-owned execution, and artifact-owned verification. |
| `route-governance/` | Recommended | Route-change discipline for fragile UI automation and repeated-failure review. |
| `llm-wiki-v2-keyence/` | Required for programming evidence | Local Wiki V2 database and query script. It may stay under KEYENCE `htmlhelp` or be copied beside the harness if the config points to it. |
| `docs/` and `README*.md` | Recommended | Human deployment and architecture documentation. |

The safe default is to copy the whole repository to the target Windows machine, for example:

```powershell
git clone https://github.com/xxrust/KeyenceAgent.git "$env:USERPROFILE\KeyenceAgent"
cd "$env:USERPROFILE\KeyenceAgent"
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_keyence_agent.ps1
```

`setup_keyence_agent.ps1` is a non-AI interactive setup script. It asks command-line questions and installs the packaged `keyence-kv-studio` skill, writes KV STUDIO paths, writes the work root, writes Wiki V2 knowledge-base paths, records the default administrator user name, and stores the administrator credential with DPAPI.

Useful setup modes:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_keyence_agent.ps1 -h
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_keyence_agent.ps1 -Status
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_keyence_agent.ps1 -Configure credential
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup_keyence_agent.ps1 -Configure kvs_exe,wiki_root
```

`-Status` reports which items are configured or missing. `-Configure` accepts `all`, `skills`, `config`, `kvs_exe`, `work_root`, `wiki_root`, `admin_user`, `credential`, and `advanced`. The script detects Chinese/Japanese/English UI culture; command prompts are kept ASCII-safe for Windows PowerShell compatibility, with localized instructions in `README.zh-CN.md` and `README.ja.md`.

The runner writes disposable projects and evidence under `%LOCALAPPDATA%\KeyenceAgent\Work` by default. Keep that directory outside the repository so generated `.kpr` projects, screenshots, logs, and compile artifacts are not committed.

## Local Configuration

Create one non-secret config file per Windows user. Start from:

```text
keyence-kv-studio\scripts\kv-studio-operator\config\kv-studio-operator.example.json
```

Place the local copy at either path:

```text
%APPDATA%\Codex\kv-studio-operator\config.json
keyence-kv-studio\scripts\kv-studio-operator\config\kv-studio-operator.local.json
```

The normal config stores only machine-specific roots. Derived paths are resolved by scripts:

```json
{
  "kvs_exe": "C:\\Program Files (x86)\\KEYENCE\\KVS12G\\KVS12\\KVS\\Kvs.exe",
  "work_root": "%LOCALAPPDATA%\\KeyenceAgent\\Work",
  "admin_credential_path": "%APPDATA%\\Codex\\kv-studio-operator\\credentials.xml",
  "admin_user_default": "Administrator",
  "wiki_root": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\ManualHelp\\2052\\htmlhelp\\llm-wiki-v2-keyence"
}
```

`work_root` derives `mvp_runs`, `mvp_repair_runs`, and `mvp_repeat_runs`. `wiki_root` derives `wiki.v2.cleaned.db` and `scripts\wiki_query.py`. Advanced fields such as `timeout_seconds`, `local_paste_format`, `mvp_out_root`, `repair_out_root`, `repeat_out_root`, `wiki_cleaned_db` and `wiki_query_script` remain supported as explicit overrides, but the setup flow does not ask for them by default.

For `Local config file path or directory`, press Enter for the default file or enter a directory such as `$env:LOCALAPPDATA\KeyenceAgent\Config`; setup will write `config.json` in that directory.

Do not store KV STUDIO administrator passwords in JSON. During setup, `setup_keyence_agent.ps1` automatically uses `%APPDATA%\Codex\kv-studio-operator\credentials.xml`, asks for the KV STUDIO administrator user name and password, creates the directory/file, and stores the credential with Windows DPAPI. New users should leave the credential file path alone. You can also run the credential writer directly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\KeyenceAgent\keyence-kv-studio\scripts\kv-studio-operator\set_kv_admin_credential.ps1"
```

Runner commands can use the config automatically from `%APPDATA%`, or explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File "$env:USERPROFILE\KeyenceAgent\keyence-kv-studio\scripts\kv-studio-operator\run_kv_mvp_scaffold.ps1" `
  -ConfigPath "$env:APPDATA\Codex\kv-studio-operator\config.json" `
  -ScaffoldRoot "$env:LOCALAPPDATA\KeyenceAgent\Work\scaffolds\example"
```

Knowledge-base queries use the same config automatically:

```powershell
python "$env:USERPROFILE\KeyenceAgent\keyence-kv-studio\scripts\kv-studio-kb-programming\query_keyence_kb.py" "ST assignment" --limit 5 --evidence
```

Override order for Wiki paths is: command-line `--db/--query-script`, `KEYENCE_WIKI_*` environment variables, shared KeyenceAgent config, then built-in defaults.

## Key Scripts

| Script | Purpose |
| --- | --- |
| `setup_keyence_agent.ps1` | One-command local setup after clone: installs skills, writes local config, stores DPAPI credential, and sets config-path environment variables. |
| `keyence-kv-studio/scripts/kv-studio-operator/Import-KvStudioOperatorConfig.ps1` | Loads local KV STUDIO path, output roots, timeout, and credential file path. |
| `keyence-kv-studio/scripts/kv-studio-operator/render_kv_mvp_scaffold_model.ps1` | Renders structured project models into per-module MNM and variable files. |
| `keyence-kv-studio/scripts/kv-studio-operator/validate_kv_mvp_scaffold.ps1` | Validates checklist, schema, module type, variables, FB declarations, and scaffold consistency. |
| `keyence-kv-studio/scripts/kv-studio-operator/assert_kv_mnm_import_plan.ps1` | Blocks same-name MNM imports unless pre-delete is explicitly planned. |
| `keyence-kv-studio/scripts/kv-studio-operator/run_kv_mvp_scaffold.ps1` | Creates a fresh KV STUDIO project and runs the full MVP path. |
| `keyence-kv-studio/scripts/kv-studio-operator/run_kv_mvp_repair_existing_project.ps1` | Applies a scaffold update to an existing project with snapshot gating. |
| `keyence-kv-studio/scripts/kv-studio-operator/run_kv_mvp_repeat.ps1` | Requires consecutive successful full runs. |
| `keyence-kv-studio/scripts/kv-studio-operator/guards/kv_ui_guard.ps1` | Shared focus, modal, keyboard, mouse, and clipboard guard library for all KV UI scripts. |

## Validation Evidence

The latest function-block MVP completed the full path:

```text
FB MNM import
-> scan module MNM import
-> FB argument table paste
-> global/local variable paste
-> compile
-> result-tree text capture
-> baseline snapshot write
```

Latest repeat gate:

```text
required_consecutive_passes: 3
attempts_completed: 3
consecutive_passes: 3
status: pass
```

The compile oracle is the same-run KV STUDIO result text:

```text
Conversion result OK
error count: 0
warning count: 0
```

## Design Principles

| Principle | Meaning |
| --- | --- |
| Harness first | A successful manual route becomes a script-owned harness before it becomes a skill claim. |
| Checklist before UI | KV STUDIO scripts fail fast when the required checklist is missing. |
| Same-run evidence | Old screenshots, logs, and project state are not success proof. |
| Shared UI guard | Focus and modal handling live in one library instead of per-script patches. |
| Fileized oracles | Compile and paste results are written as artifacts before the agent reasons about them. |
| Route governance | Route changes require evidence about the failed mechanism and the new control. |

## Roadmap

| Area | Planned work |
| --- | --- |
| Function blocks | Expand FB argument support to comments and richer optional columns after format probes prove stable paste behavior. |
| Existing projects | Complete stronger export/import snapshots for projects not created by the harness. |
| Module categories | Standby modules are verified; interrupt programs remain gated until CPU-system interrupt settings and enable path are scripted. |
| Function block composition | Cover nested FB instances, multiple call sites, and instance scope audits. |
| Speed | Reduce unnecessary waits after each guarded step while keeping bounded failure behavior. |
| Sub-agent validation | Require independent agents to complete the same MVP through the skill without live-UI reasoning. |
| Documentation | Add architecture diagrams, failure taxonomy, and runner contract examples for new contributors. |
