---
name: keyence-plc-programmer
description: Design, modify, and validate KEYENCE PLC programs for KV STUDIO. Use when Codex must write ladder/ST logic, reproduce or adapt official KEYENCE reference programs, edit or generate MNM mnemonic-list imports, decide variables/devices/FB instances, use the local KEYENCE Wiki V2 evidence database, import only official FBs, and pass KV STUDIO compile verification without copying or renaming an entire official reference project.
---

# KEYENCE PLC Programmer

## Scope

Use this skill for PLC logic and project-structure decisions. Use `kv-studio-operator` for KV STUDIO UI operations, MNM import/export, variable editor work, and compile/error collection. Use `kv-studio-kb-programming` as the Wiki V2 evidence retrieval helper.

Default official reference project:

`C:\Users\liangyuhang\Documents\KEYENCE\KVS12G\KVS12\KVS\PROJECT\KVX鏍蜂緥绋嬪簭_v100`


Stable KV STUDIO automation is bundled under this skill. These scripts are the only reusable automation source for this skill:

- `scripts/kvtool.ps1`: central command surface for reusable KV STUDIO tooling.
- `scripts/resolve_kvstudio_local.ps1`: resolve the local KV STUDIO shortcut to the real `Kvs.exe`; use this before assuming install paths.
- `scripts/create_project_local.ps1`: create a disposable local KV STUDIO project through Win32/UIAutomation control handles; no image recognition.
- `scripts/local_kvstudio_acceptance.ps1`: five-minute local acceptance runner: resolve KV STUDIO, create/open project, run MNM roundtrip, then run conversion evidence collection.
- `scripts/import_mnm.ps1` / `scripts/export_mnm.ps1`: mnemonic-list UI import/export. `import_mnm.ps1` process success is not an acceptance gate unless `-FailOnMissingValidationNeedles` is used.
- `scripts/roundtrip_mnm.ps1`: hard gate for mnemonic-list import/export; imports an MNM, exports it back, and fails unless the executable instruction fingerprint matches.
- `scripts/init_project_snapshot_workspace.ps1`: create a task git workspace with `source_snapshot/`, `work/`, and `validation/` folders for fresh original-project exports and rollback-safe diffs.
- `scripts/init_evidence_loop.ps1`, `scripts/watch_evidence_loop.ps1`, `scripts/invoke_evidence_review.ps1`: create and enforce a deterministic evidence-review loop. Watched changes under `source_snapshot/`, `work/`, or `validation/` trigger a reviewer through `FileSystemWatcher`; the reviewer captures `git diff`, writes review artifacts, copies `latest_review.md` to the implementation inbox, and updates `audit.html`.
- `scripts/new_mnm_smoke.ps1`: no-Python minimal MNM smoke generator for isolated VM tests.
- `scripts/convert_collect.ps1`: open a project, run `Ctrl+F9`, and collect screenshots/UI/clipboard evidence.
- `scripts/run_vm103_interactive_script_ssh.ps1`: run fragile UI scripts inside the logged-on VM desktop.
- `references/kvstudio-toolkit.md`: toolkit contract and stable-vs-experimental classification.
- `references/kvstudio-toolkit-manifest.json`: machine-readable command manifest.
- `references/mnm-smoke-reference.md`: validated minimal MNM shape for fast smoke programming.

Use these bundled scripts directly from the skill path or copy them freshly from the skill path into a task folder at runtime. Do not reuse same-named scripts already present under `C:\Users\Public\KVSkillPractice`, `C:\Users\Public\CodexRemoteTasks`, or VM-specific evidence folders; those locations are evidence/output areas, not automation sources.

KV STUDIO UI safety rule:

- Treat the ladder/program editor as a hazardous input surface. If automation cannot prove focus is inside the intended export/import/file dialog, it must fail closed.
- Do not use global `SendKeys`, paste, `Enter`, or accelerator fallback while the ladder editor can receive input. In particular, if the inline ladder edit bar (`覆盖(O)`, `插入(I)`, `取消(C)`) or `未输入任何内容。` dialog is visible, stop, save evidence, and require a dialog-specific recovery step.
- Prevent the inline ladder edit bar from being created in the first place. The 2026-05-26 failure mechanism was: MNM import route did not produce a verified file-open dialog, script treated AutomationId `1265` as a mnemonic-read path edit, wrote the MNM path into the ladder editor inline input, then misread `插入` as an import confirmation. The fix is to remove that path: MNM import may set a filename only after proving a standard file-open dialog or separately verified MNM picker. AutomationId `1265` alone is never sufficient evidence.
- Before running or patching `export_mnm.ps1`, `import_mnm.ps1`, or any copied task-local variant on a user project, run `kv-studio-operator\scripts\assert_kvstudio_ui_safe.ps1` or an equivalent UIA guard. Scripts with "fallback" keyboard paths must be reviewed and made fail-closed before use on real projects.

Old evidence quarantine rule: directories named like `C:\Users\Public\KVSkillPractice_OLD_DO_NOT_USE_*` are forbidden as automation inputs, benchmark evidence, MNM sources, or success proof. They may be read only for failure forensics when the user explicitly asks to audit history. Fresh acceptance runs must start from the active `C:\Users\Public\KVSkillPractice` directory created after the latest `reset_manifest.json`.

Local benchmark path:

- For a generated MNM on this workstation, first run `scripts/local_kvstudio_acceptance.ps1`.
- The benchmark starts when KV STUDIO is opened by the script and fails if `acceptance_result.json` is not `ok=true` within 300 seconds.
- Main automation must use Win32/UIAutomation controls, keyboard accelerators, and exported text artifacts. Do not use screenshot/image matching or visual pixel location as the primary route.
- Screenshots may be collected as evidence only; never treat an image match as the source of truth for a click target or pass/fail verdict.

Current MNM acceptance boundary:

- `import_mnm.ps1` alone proves only that the UI import route was exercised and that no recognized import-failure dialog was captured.
- `roundtrip_mnm.ps1` is the hard MNM gate: import, export back, normalize executable instructions, and compare fingerprints.
- Ctrl+F2/Ctrl+F9 conversion is valid only after MNM roundtrip fingerprint equality for the target module.
## Hard Constraints

- Do not implement by renaming the official reference project.
- Do not import the whole official reference program as the answer.
- Importing official FBs/function blocks is allowed only when they remain official and unmodified.
- For reproduction, bugfix, optimization, or modification of an existing KV STUDIO project, first open that exact source project in KV STUDIO and export a fresh text snapshot before analyzing or changing logic. Do not trust stale local `.mnm`, `.csv`, `.lbl`, or sidecar extracts as current unless they were exported in the current task run.
- The fresh source snapshot must include exported MNM program bodies for every relevant program/FB/module, variable manifests, module/program inventory, unit/device evidence, and compile/export evidence. If export is blocked, stop and report the export blocker; do not downgrade silently to structure-only reconstruction.
- Put exported MNM, variable manifests, module inventory, evidence reports, and generated/repaired sources under a task-specific git working tree before editing. Every source snapshot and every generated fix must be diffable and recoverable by git.
- Program modules other than official FBs must be created, edited, or imported through MNM.
- Variables must be reconstructed explicitly; missing variables after MNM import are not acceptable.
- A compile failure invalidates the result.
- Generic IEC assumptions are not enough; confirm KEYENCE syntax, FB calls, device maps, and module behavior with Wiki V2 or the official reference project.

## Programming Workflow

1. Identify the requested CPU family, unit configuration, axis/module/protocol, language mode, and acceptance criteria.
2. For an existing project, open the original `.kpr` in KV STUDIO and export a fresh source snapshot:
   - MNM for all relevant user programs, FBs, and modules.
   - Variable tables/manifests for global variables, local variables, FB instances, data types, arrays, and device-backed names.
   - Program/module tree, unit/device configuration evidence, comments/labels, and compile/export screenshots or logs.
   - Store the snapshot under a task folder such as `<task-root>/source_snapshot/<timestamp>/`.
3. Initialize or reuse a git repository for the task folder before editing. For implementation tasks, prefer the forced evidence-review loop:
   - Initialize with `scripts/kvtool.ps1 init-evidence-loop -TaskId <task-id>`.
   - Run `scripts/kvtool.ps1 watch-evidence -EvidenceRoot <evidence-root>` in the background while implementation proceeds.
   - Place fresh exports only under `source_snapshot/`, generated/edited files under `work/`, and compile/import evidence under `validation/`.
   - Treat `review_inbox/latest_review.md` and `audit.html` as mandatory review gates before importing or reporting success.
   - Commit or at least record the fresh exported snapshot as the baseline.
   - Keep generated MNM/ST, variable manifests, module inventories, and validation reports as text artifacts in git.
   - Use `git diff` to review every logic, variable, module, and device-map change before import or final reporting.
   - Use git history plus the recorded text snapshot for rollback; do not rely only on KV STUDIO binary project files.
4. Query Wiki V2 before writing KEYENCE-specific logic:

```powershell
python .\llm-wiki-v2-keyence\scripts\wiki_query.py "exact token or user wording" --db .\llm-wiki-v2-keyence\wiki.v2.cleaned.db --limit 5 --evidence
```

5. If recall is weak, rerun against `wiki.v2.fixed.db`.
6. Inspect the fresh exported source snapshot and, when applicable, the official reference project for architecture and behavior, not for wholesale copying.
7. Build a logic map: programs, tasks/scan order, FBs, devices, variables, and expected state transitions.
8. Create or edit MNM program bodies from the current exported baseline.
9. Update the variable manifest for global variables, local variables, FB instances, data types, arrays, and device-backed names.
10. Use bundled `scripts/kvtool.ps1` plus `kv-studio-operator` to import official FBs, import MNM, reconstruct variables, and run Ctrl+F2/Ctrl+F9.
11. Fix every compile/convert error from copied KV STUDIO error text.
12. Commit or record the final text artifacts and validation evidence. Report only after compile passes and anti-copy/version-control checks pass.


Common toolkit commands:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill>\scripts\kvtool.ps1 list
powershell -NoProfile -ExecutionPolicy Bypass -File <skill>\scripts\kvtool.ps1 manifest
powershell -NoProfile -ExecutionPolicy Bypass -File <skill>\scripts\init_project_snapshot_workspace.ps1 -TaskRoot <task-root> -TaskName <name> -ProjectPath <original.kpr>
powershell -NoProfile -ExecutionPolicy Bypass -File <skill>\scripts\kvtool.ps1 run-interactive -LocalScriptPath <skill>\scripts\convert_collect.ps1
```

Load `references/kvstudio-toolkit.md` only when you need detailed command boundaries, promotion rules, or examples.
When validating inside Windows editor VMs, first confirm a logged-on interactive Windows user with `windows-vm-codex-operator ps`, then launch VM-side agents with `windows-vm-codex-operator codex-run --transport ui`. Use all running idle editor VMs for independent validation slices instead of waiting on one VM. Require each VM to return artifacts under a VM-specific directory such as `C:\Users\Public\KVSkillPractice\vm-101\<task-id>`. The management-machine noVNC stream is too slow for primary validation; use QGA/`ps` to retrieve reports, screenshots, exported MNM, variable manifests, and error text. Do not attempt KV STUDIO UI validation through QGA-only Codex because it runs in Session 0 and cannot observe the desktop.

Current verified VM-side baseline:

- UI transport works on VM `103` as `PLC-EDITOR-03\posen`.
- Clean-project compile smoke passed for `C:\Users\Public\KVSkillPractice\Projects\CodexUiCompileSmoke`, CPU/model `KV-X550`.
- Evidence report: `C:\Users\Public\KVSkillPractice\compile_smoke_report.md`.
- This is only a baseline compile gate. Do not claim official reference reproduction until MNM import/export, official FB-only import, variable reconstruction, and reference-behavior comparison have also passed.

Parallel validation split:

- VM `101`: clean project creation, CPU/model selection, administrator settings, and compile smoke.
- VM `102`: MNM export/import, variable editor reconstruction, and copied conversion-error text.
- VM `103`: official FB import, reference-project inventory comparison, and final reproduction compile.

Do not reserve any VM long-term for noVNC. Use noVNC only for login/unlock or short visual confirmation, then run VM-side UI Codex and retrieve artifacts through QGA/`ps`.

## Reference Reproduction Method

When asked to reproduce the official reference program:

1. Open the exact source project in KV STUDIO and export a fresh MNM/variable/module snapshot. This is mandatory even if older `.mnm` files already exist beside the project.
2. Put the exported snapshot under git as the baseline for diff, rollback, and later restoration.
3. Open or inspect the official/reference source as the behavioral oracle.
4. Extract the program inventory: modules, FB dependencies, variables, device mappings, scan tasks, comments, and state-machine intent.
5. Classify each element:
   - Official FB: import from official source if needed.
   - User program logic: recreate as MNM.
   - Variable/device table: reconstruct through variable editor.
   - Unit/device mapping: set through project/unit configuration.
6. Rebuild the target project from a clean project or accepted scaffold.
7. Import only official FBs directly.
8. Import recreated MNM for other logic.
9. Recreate variables from your own manifest.
10. Compile and compare behavior/structure against the reference.

Read `references/reproduction-gate.md` before claiming a reference reproduction is valid.

## MNM Authoring Rules

- Keep MNM edits minimal and structurally consistent with KV STUDIO export style.
- For MNM imports that contain Chinese names or comments, write the `.mnm` file in the Windows system ANSI code page expected by KV STUDIO on the target machine, normally CP936 on Chinese Windows. Do not rely on terminal display: validate the bytes with `[Text.Encoding]::Default` and require the intended Chinese identifiers to round-trip before import. UTF-8 Chinese MNM is a known failure mode because KV STUDIO can read the file as ANSI and turn identifiers such as `启动`, `红LED灯`, `黄LED灯`, and `绿LED灯` into mojibake.
- Do not place IEC `VAR ... END_VAR` declaration blocks into executable ST bodies unless Wiki V2 proves KV STUDIO accepts that context.
- Treat variable declarations as project/editor objects, not inline program text.
- Use stable names for FB instances and program variables; keep the variable manifest synchronized with MNM references.
- Preserve official instruction/FB call signatures exactly as Wiki V2 or exported reference evidence shows.

## Variable Manifest

For every program change, maintain a manifest with:

- Global variables: name, data type, device assignment if any, comment.
- Local variables per program: program name, variable name, data type, comment.
- FB instances: instance name, FB type, scope, program owner.
- Device-backed items: device/register, module/axis basis, source evidence.
- Unknowns: items requiring CPU, unit, slot, axis, or user confirmation.

Do not proceed to final validation while the manifest has unresolved variables referenced by MNM.

KV STUDIO variable-editor paste rows have different schemas by scope:

- Global rows: `group name`, `variable name`, `data type`, `assignment target`, `value`, `retain`, `constant`, `OPC UA`, `file export`, `comment 1`, additional comments.
- Local rows: `variable name`, `data type`, `value`, `retain`, `constant`, `file export`, `comment 1`, additional comments.
- Do not include global-only columns such as group name, assignment target, or OPC UA in local-variable TSV rows.
- Do not paste over program default local variables. If KV STUDIO reports a variable-name overwrite confirmation, cancel and treat it as a failed row-positioning route.

## Source Snapshot And Version Control

For existing-project reproduction, optimization, or bugfix tasks, maintain a text-first version record:

- `source_snapshot/<timestamp>/mnm/`: fresh MNM exports from the original project opened in KV STUDIO.
- `source_snapshot/<timestamp>/variables/`: exported or reconstructed global/local variables, FB instances, data types, arrays, and device-backed names.
- `source_snapshot/<timestamp>/inventory/`: program/module tree, unit/device configuration, comments/labels, and sidecar evidence such as `WsTreeEnv.xml`, `PlcSended.dky`, `.lbl`, `.cm*`, and `UnitSet.ue2`.
- `work/`: generated or edited MNM/ST/manifest files intended for import.
- `validation/`: compile/convert reports, screenshots, copied KV STUDIO errors, exported post-import MNM, and comparison notes.

Use git to preserve these states:

1. Baseline commit or recorded state: fresh exported original project text snapshot.
2. Work commit or diff: generated/edited MNM, variables, module inventory, and rationale.
3. Validation commit or recorded state: imported project evidence, compile result, error text, and final exported post-import MNM.

If git is unavailable, create a timestamped folder with `BASELINE`, `WORK`, and `VALIDATION` subfolders plus a `diff_report.md`; report that rollback is weaker than a real git history.

## Evidence Priority

- `htmlhelp` / `chm`: instruction syntax, ST usage, FUN/FB semantics.
- `table`: device maps, soft-device allocation, buffer memory, address lookup.
- `dockinghelp`: motion and parameter-help fragments.
- `pdf`: broader constraints, timing, hardware behavior, examples.
- Official reference project: accepted behavior/structure oracle, not a source to copy wholesale.
- `htmlnavi_meta`: navigation only.

## Anti-Copy Validation

A result is invalid if any of these are true:

- The target project is the official project under a new name.
- All program logic was imported from official `All.prgx`/project package.
- The only meaningful change is file/project renaming.
- Non-FB program logic bypasses MNM reconstruction.
- Variable errors are hidden by deleting logic or changing acceptance criteria.

## Completion Report

Report:

- Wiki queries used and the evidence types returned.
- Original project path opened in KV STUDIO, export timestamp, and exported source snapshot path.
- Git repository path, baseline snapshot state, and relevant `git diff` / commit identifiers when available.
- Official reference path and elements inspected.
- Official FBs imported directly.
- MNM files freshly exported from the original project, then created/edited/imported.
- Variable manifest source, export timestamp, reconstruction status, and unresolved variables if any.
- Module/unit/device inventory source and changes.
- Ctrl+F2 compile result and error text if any iteration failed.
- VM-side validation artifacts, usually under `C:\Users\Public\KVSkillPractice`, including reports, screenshots, exported MNM, and copied KV STUDIO errors.
- Any remaining ambiguity about CPU, unit, axis, or device mapping.



