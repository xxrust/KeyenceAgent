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
|-- docs/
|   `-- images/
|-- kv-studio-operator/
|   |-- config/
|   |-- SKILL.md
|   |-- references/
|   `-- scripts/
|       |-- run_kv_mvp_scaffold.ps1
|       |-- run_kv_mvp_repair_existing_project.ps1
|       |-- run_kv_mvp_repeat.ps1
|       `-- mvp/
|-- keyence-plc-programmer/
`-- route-governance/
```

## VM Deployment

Deploy the repository as a text-first harness on the Windows VM that runs KV STUDIO.

Copy or clone these runtime folders:

| Folder | Required | Purpose |
| --- | --- | --- |
| `kv-studio-operator/` | Yes | Runner scripts, guarded UI actions, scaffold renderer, validator, config template. |
| `keyence-plc-programmer/` | Recommended | PLC authoring rules and KEYENCE programming workflow. |
| `kv-studio-kb-programming/` | Recommended | Local Wiki V2 query wrapper and workflow for KEYENCE syntax and manuals. |
| `llm-wiki-v2-keyence/` | Required for programming evidence | Local Wiki V2 database and query script. It may stay under KEYENCE `htmlhelp` or be copied beside the harness if the config points to it. |
| `docs/` and `README*.md` | Recommended | Human deployment and architecture documentation. |

The safe default is to copy the whole repository to the VM, for example:

```powershell
git clone https://github.com/xxrust/KeyenceAgent.git C:\Users\Public\KeyenceAgent
```

The runner writes disposable projects and evidence under `C:\Users\Public\KVSkillPractice` by default. Keep that directory outside the repository so generated `.kpr` projects, screenshots, logs, and compile artifacts are not committed.

## VM Configuration

Create one non-secret config file per VM. Start from:

```text
kv-studio-operator\config\kv-studio-operator.example.json
```

Place the local copy at either path:

```text
%APPDATA%\Codex\kv-studio-operator\config.json
kv-studio-operator\config\kv-studio-operator.local.json
```

The config stores machine-specific paths for both KV STUDIO operation and KEYENCE Wiki V2 retrieval:

```json
{
  "kvs_exe": "D:\\KEYENCE\\KVS12G\\KVS12\\KVS\\Kvs.exe",
  "work_root": "C:\\Users\\Public\\KVSkillPractice",
  "mvp_out_root": "C:\\Users\\Public\\KVSkillPractice\\mvp_runs",
  "repair_out_root": "C:\\Users\\Public\\KVSkillPractice\\mvp_repair_runs",
  "repeat_out_root": "C:\\Users\\Public\\KVSkillPractice\\mvp_repeat_runs",
  "admin_credential_path": "%APPDATA%\\Codex\\kv-studio-operator\\credentials.xml",
  "htmlhelp_root": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\ManualHelp\\2052\\htmlhelp",
  "wiki_root": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\ManualHelp\\2052\\htmlhelp\\llm-wiki-v2-keyence",
  "wiki_cleaned_db": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\ManualHelp\\2052\\htmlhelp\\llm-wiki-v2-keyence\\wiki.v2.cleaned.db",
  "wiki_fixed_db": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\ManualHelp\\2052\\htmlhelp\\llm-wiki-v2-keyence\\wiki.v2.fixed.db",
  "wiki_query_script": "C:\\Users\\Public\\Documents\\KEYENCE\\KVS12\\ManualHelp\\2052\\htmlhelp\\llm-wiki-v2-keyence\\scripts\\wiki_query.py",
  "timeout_seconds": 600,
  "local_paste_format": "NameType"
}
```

Do not store KV STUDIO administrator passwords in JSON. Store the credential once per Windows user with DPAPI:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\KeyenceAgent\kv-studio-operator\scripts\set_kv_admin_credential.ps1
```

Runner commands can use the config automatically from `%APPDATA%`, or explicitly:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\KeyenceAgent\kv-studio-operator\scripts\run_kv_mvp_scaffold.ps1 `
  -ConfigPath "$env:APPDATA\Codex\kv-studio-operator\config.json" `
  -ScaffoldRoot C:\Users\Public\KVSkillPractice\scaffolds\example
```

Knowledge-base queries use the same config automatically:

```powershell
python C:\Users\Public\KeyenceAgent\kv-studio-kb-programming\scripts\query_keyence_kb.py "ST assignment" --limit 5 --evidence
```

Override order for Wiki paths is: command-line `--db/--query-script`, `KEYENCE_WIKI_*` environment variables, shared KeyenceAgent config, then built-in defaults.

## Key Scripts

| Script | Purpose |
| --- | --- |
| `kv-studio-operator/scripts/Import-KvStudioOperatorConfig.ps1` | Loads VM-local KV STUDIO path, output roots, timeout, and credential file path. |
| `kv-studio-operator/scripts/render_kv_mvp_scaffold_model.ps1` | Renders structured project models into per-module MNM and variable files. |
| `kv-studio-operator/scripts/validate_kv_mvp_scaffold.ps1` | Validates checklist, schema, module type, variables, FB declarations, and scaffold consistency. |
| `kv-studio-operator/scripts/assert_kv_mnm_import_plan.ps1` | Blocks same-name MNM imports unless pre-delete is explicitly planned. |
| `kv-studio-operator/scripts/run_kv_mvp_scaffold.ps1` | Creates a fresh KV STUDIO project and runs the full MVP path. |
| `kv-studio-operator/scripts/run_kv_mvp_repair_existing_project.ps1` | Applies a scaffold update to an existing project with snapshot gating. |
| `kv-studio-operator/scripts/run_kv_mvp_repeat.ps1` | Requires consecutive successful full runs. |
| `kv-studio-operator/scripts/mvp/kv_ui_guard.ps1` | Shared focus, modal, keyboard, mouse, and clipboard guard library for all KV UI scripts. |

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
