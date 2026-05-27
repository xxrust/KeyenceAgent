---
name: kv-studio-operator
description: Operate KEYENCE KV STUDIO from Codex or a Windows editor VM. Use when the task requires creating KV STUDIO projects, selecting CPU/unit configuration, exporting or importing mnemonic list MNM files, importing official FB/function block libraries, editing global/local variables through the variable editor, running Ctrl+F2 compile/convert verification, or collecting KV STUDIO error text without relying on mouse clicks.
---

# KV STUDIO Operator

## Scope

Use this skill for KV STUDIO UI and project-operation work. Pair it with `keyence-plc-programmer` when logic must be designed or modified, and with `plc-editor-cluster-access` / `windows-vm-codex-operator` when work happens on one of the Windows editor VMs.

Verified VM baseline:

- KV STUDIO Ver.12G launcher: `C:\Program Files (x86)\KEYENCE\KVS12G\KvsLauncher.exe`
- KV STUDIO Ver.12G main executable: `C:\Program Files (x86)\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe`
- On the current local workstation, the Start Menu shortcut resolves to `D:\KEYENCE\KVS12G\KvsLauncher.exe`, with the main executable at `D:\KEYENCE\KVS12G\KVS12\KVS\Kvs.exe`. Do not hard-code `C:\Program Files (x86)`; resolve the Start Menu shortcut or use `keyence-plc-programmer\scripts\resolve_kvstudio_local.ps1` before launching KV STUDIO.
- Observed version: `12.40.0.0`
- Start Menu shortcut: `C:\ProgramData\Microsoft\Windows\Start Menu\Programs\KEYENCE KV STUDIO Ver.12G\KV STUDIO Ver.12G.lnk`

## Operating Rules

- Reserve an idle Windows editor VM before touching KV STUDIO in a VM.
- For UI work in a VM, prefer `windows-vm-codex-operator` with `codex-run --transport ui`; do not rely on noVNC except as a slow visual fallback.
- Before UI work, verify a logged-on Windows desktop session exists. `codex-run --transport ui` uses the logged-on user's `InteractiveToken`; it cannot operate KV STUDIO from QGA Session 0 when no interactive user is logged on.
- Return VM evidence through files under `C:\Users\Public\KVSkillPractice` or `C:\Users\Public\CodexRemoteTasks`, then read them back through QGA/`ps`.
- Keyboard sequences and clipboard operations are allowed only after the exact target dialog/control has been identified. Do not use global `SendKeys`, typed text, paste, `Enter`, or accelerator fallback when KV STUDIO focus could be in the ladder/program editor.
- KV STUDIO operation scripts must be checklist-gated. Before launching, restarting, importing, editing variables, compiling, or copying KV STUDIO result text, the script must find a non-empty `CHECKLIST.md` / `kv_operation_checklist.md`, an explicit `-ChecklistPath`, or `KV_STUDIO_OPERATION_CHECKLIST`. If the checklist is missing, the script must fail before initializing UIAutomation or touching KV STUDIO.
- Before sending any user-validated accelerator such as `Alt+F,R,S`, explicitly verify the foreground window title starts with `KV STUDIO` and matches the intended project. A passing UIA safety scan alone is not enough; accelerators go to the foreground window.
- Before sending accelerators, prove KV STUDIO is actually restored and foreground, not merely running or visible in the taskbar. If the window is minimized or another window remains foreground, the route is blocked; do not send accelerators.
- Before sending accelerators, normalize and record keyboard/input state. On this workstation, use a deterministic CapsLock/English-keyboard path for menu accelerator delivery; a Chinese IME state can consume or alter shortcut characters.
- Before any script sends keyboard input or clicks a generic OK/Insert/Overwrite control, run `scripts/assert_kvstudio_ui_safe.ps1` or perform an equivalent UIA guard check. If the ladder edit inline bar (`覆盖(O)`, `插入(I)`, `取消(C)`) is visible in the editor area, it is not an MNM import confirmation. Immediately verify KV STUDIO is foreground, invoke the identified `取消(C)` button through UIA `InvokePattern`, record evidence, and stop the current workflow for root-cause analysis. `Alt+C` is not a deterministic automation recovery unless the target control focus has been proven in that run. A KV STUDIO modal message such as `未输入任何内容。` is also a fail-closed state.
- Do not create the ladder inline edit bar as part of recovery or probing. The root cause observed on 2026-05-26 was treating AutomationId `1265` as an MNM file-path field; the same edit control belongs to the ladder inline edit bar. Writing an MNM path there creates the hazardous input state. MNM import scripts must require a verified standard file-open dialog or a separately proven MNM picker. If that dialog is absent, fail and close the bad KV STUDIO state.
- UI automation must fail closed: if the expected export/import/file dialog is not found by class/name/control identity, write a failure report and exit. Never fall back to typing into the active window.
- User-validated accelerator workflows from `C:\Users\liangyuhang\Documents\Obsidian Vault\KV_Agent操作指南.md` are authoritative. Use them first when their preconditions are satisfied. If you do not use one, record the exact missing precondition, interference, or timing evidence; do not silently replace it with a slower UIA/menu-click path.
- Prefer MNM export/edit/import for program changes; use direct UI editing only when MNM import cannot express the change.
- Import official FBs/modules only from the official project/package path chosen for the task; do not import whole user program logic as a shortcut.
- Rebuild variables explicitly after MNM import; imported MNM program bodies can lose variable definitions.
- Treat successful compile/convert verification as the required gate; a project that fails Ctrl+F2 is not complete.

## Scaffold-First MVP Workflow

Use this workflow for new simple KV STUDIO tasks. Do not hard-code the traffic-light program as the automation route. The repeatable route is: generate a scaffold, let the agent edit the scaffold files for the task, then run the one-click scaffold runner against KV STUDIO.

Create a scaffold:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  C:\Users\liangyuhang\.codex\skills\kv-studio-operator\scripts\new_kv_mvp_scaffold.ps1 `
  -ScaffoldRoot C:\Users\Public\KVSkillPractice\scaffolds\<task-id> `
  -ProjectName <project-name> `
  -CpuModel KV-X310 `
  -ModuleName Main_MVP `
  -Template Minimal `
  -TaskSummary '<task summary>'
```

The scaffold contains:

- `scaffold.json`: manifest with project name, CPU model, local program name, MNM list, and variable TSV paths.
- `mnm\*.mnm`: mnemonic-list files imported into KV STUDIO. These are the primary program-body handoff files. For ordinary scan-executed user programs, use `;MODULE_TYPE:0`; `;MODULE_TYPE:2` creates a function block and is not a replacement for a scan-executed module.
- `variables\global_variables.tsv`: global variable rows using the scaffold schema.
- `variables\local_variables.tsv`: local variable rows using the scaffold schema and the target local program.
- `TASK.md`: task intent and acceptance notes.
- `VERSION.md`: project/scaffold version notes.
- `CHECKLIST.md`: mandatory operation checklist. The one-click runner and all KV STUDIO MVP sub-scripts refuse to operate without this file or an explicit checklist path.

Agent fill rule:

1. Read `scaffold.json`.
2. Edit `mnm\*.mnm` for the requested PLC behavior.
3. Edit `variables\global_variables.tsv` and `variables\local_variables.tsv` for required variables.
4. Update `TASK.md` and `VERSION.md` with implemented behavior, IO mapping, assumptions, and validation target.
5. Complete or update `CHECKLIST.md` before running any KV STUDIO script.
6. Run the scaffold through KV STUDIO:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  C:\Users\liangyuhang\.codex\skills\kv-studio-operator\scripts\run_kv_mvp_scaffold.ps1 `
  -ScaffoldRoot C:\Users\Public\KVSkillPractice\scaffolds\<task-id> `
  -OutRoot C:\Users\Public\KVSkillPractice\mvp_runs `
  -TimeoutSeconds 300
```

The scaffold runner owns the same validated KV STUDIO route as the traffic-light MVP: guarded project creation, MNM import, project-tree placement verification, global-variable paste by first-name `Tab`, local-variable paste by `Tab -> PgDn -> Ctrl+V`, Ctrl+F9 conversion, and conversion-result copy from the verified bottom `SysTreeView32` handle. The result gate is still `mvp_result.json` with `ok=true`, `module_placement\<module>.json` showing the expected category, and copied conversion text containing `转换结果 OK`.

## Traffic-Light Compatibility Entrypoint

Use this compatibility wrapper only when the task is specifically to reproduce the traffic-light MVP from skill/knowledge. The wrapper now creates a `TrafficLight` scaffold and then delegates to `run_kv_mvp_scaffold.ps1`; keep new tasks on the scaffold-first route above.

Run the bundled entrypoint directly; do not reconstruct the workflow from chat history or temporary validation logs:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  C:\Users\liangyuhang\.codex\skills\kv-studio-operator\scripts\run_traffic_light_mvp.ps1 `
  -OutRoot C:\Users\Public\KVSkillPractice\mvp_runs `
  -ProjectName TrafficLightMVP_<timestamp> `
  -CpuModel KV-X310 `
  -TimeoutSeconds 300
```

The scaffold runner owns the route:

- Creates a disposable KV STUDIO project.
- Generates a UTF-16LE MNM import file that contains the required Chinese names in comments and uses ASCII executable identifiers for ST parser compatibility.
- Imports the MNM file; it must never type program text into the ladder/program editor.
- Opens the MNM read/import command first by the user-validated `Alt+F,R,R` route. If foreground/project/input-state preconditions are proven but no standard file-open dialog appears, the bundled script may invoke the same File-menu MNM read command through UIA menu patterns. This is a controlled route correction, not permission to click coordinates or type into the editor.
- Reconstructs global variables and local variables with their different table shapes.
- Runs Ctrl+F2 conversion.
- Copies the bottom conversion-result tree through the verified Win32 child HWND to UIA TreeItem route.

Required output contract:

- `mvp_result.json`: primary pass/fail artifact. `ok` must be `true`, `elapsed_seconds` must be `<= 300`, and `compile_result_contains_ok` must be `true`.
- `artifacts\copy_result\compile_result_copied.txt`: copied KV STUDIO conversion result. It must contain `转换结果 OK`.
- `artifacts\artifact_encoding_check.json`: confirms MNM/variable artifacts contain the required Chinese names before import.

Failure criteria:

- More than 300 seconds elapsed.
- KV STUDIO was not opened and operated.
- Any direct editor text entry or ladder inline edit bar route was used.
- The copied result text is missing, stale, coordinate-derived without same-run verification, or lacks `转换结果 OK`.
- The route depends on task-local process logs such as `E:\personal_project\rust_plc\out\...` instead of bundled skill scripts.

## Project Creation Workflow

1. Start KV STUDIO and use `Ctrl+N` for a new project.
2. Confirm the modal window titled `新建项目` appears.
3. Fill the project name in the `项目名(&N)` edit field.
4. Press `Tab` to reach `支持的机型(&K)`; use arrow keys to choose the requested model.
5. Press `Tab` to reach `位置(&P)`; enter the target directory.
6. Press `Tab` twice to reach `注释(&C)`; enter the project note if needed.
7. Press `Tab` three times to focus `OK`, then press `Enter`.
8. In administrator settings, keep `admin` unless the task requires another user.
9. Enter the password twice. Default local test password: `a82701767`.
10. For custom passwords, enforce 8-64 characters. Use `Alt+E` to disable user authentication and `Alt+S` to disable the two-character-class requirement only when the user requests that policy.
11. Complete unit configuration deliberately; do not guess module families or slots when the task depends on hardware mapping.

Unit configuration prompt rule:

- The dialog titled `确认单元配置设定` has fixed access keys: `Alt+N` selects `否(N)` and closes the dialog; `Alt+Y` selects `是(Y)` and opens the unit editor.
- For minimal programming/MNM/variable/compile validation where unit configuration is not part of the task, use `Alt+N` only after proving this exact dialog title and class `#32770` are foreground. Do not search generic buttons or treat an arbitrary `#32770` as a file dialog.
- Use `Alt+Y` only when the current task explicitly requires entering the unit editor.

Verified new-project dialog controls include:

- `项目名(&N)` edit field
- `支持的机型(&K)` combo box
- `位置(&P)` edit field
- `参照(&S)...` button
- `注释(&C)` edit field
- `OK` and `取消`

On the tested VM, the default project location was `C:\Users\posen\Documents\KEYENCE\KVS12G\KVS12\KVS\PROJECT`; override it to a disposable task folder such as `C:\Users\Public\KVSkillPractice\Projects\<task-name>` during validation.

## VM Data Return Workflow

Use this pattern instead of noVNC for slow tunnels:

```powershell
python "$env:USERPROFILE\.codex\skills\windows-vm-codex-operator\scripts\windows_vm_operator.py" ps --vmid 103 --holder-id codex-kv-skill-validation --require-reserved -- "(Get-CimInstance Win32_ComputerSystem).UserName; query user"
python "$env:USERPROFILE\.codex\skills\windows-vm-codex-operator\scripts\windows_vm_operator.py" codex-run --vmid 103 --holder-id codex-kv-skill-validation --transport ui --workdir "C:\Windows\Temp" --prompt "Operate KV STUDIO and write reports/screenshots under C:\Users\Public\KVSkillPractice."
python "$env:USERPROFILE\.codex\skills\windows-vm-codex-operator\scripts\windows_vm_operator.py" ps --vmid 103 --holder-id codex-kv-skill-validation --require-reserved -- "Get-ChildItem C:\Users\Public\KVSkillPractice -Recurse"
```

If the first command shows no logged-on user, stop and perform the VM login/unlock step first. Do not try to drive KV STUDIO through QGA-only Codex; QGA can retrieve files and run shell commands but cannot see the interactive desktop.

For multi-VM validation, do not write all reports to the same flat directory. Assign each VM its own artifact root:

```text
C:\Users\Public\KVSkillPractice\vm-101\<task-id>\
C:\Users\Public\KVSkillPractice\vm-102\<task-id>\
C:\Users\Public\KVSkillPractice\vm-103\<task-id>\
```

Use all running idle editor VMs for independent slices:

- VM `101`: disposable project creation, administrator settings, safe CPU selection, and `Ctrl+F2` compile smoke test.
- VM `102`: MNM export/import, import-dialog behavior, and variable editor paste/reconstruction tests. Do not reserve it long-term for noVNC; use noVNC only for short login/unlock if required.
- VM `103`: official FB import path, official-reference comparison, and compile-error collection.

Each VM-side prompt must include its own VM id, task id, target project path, evidence path, and "do not modify user projects" constraint. Retrieve results through QGA/`ps`; noVNC screenshots are fallback evidence only.

Verified smoke-test evidence:

- VM `103` UI transport returned `UI_CODEX_USER=PLC-EDITOR-03\posen`.
- The VM-side task wrote `C:\Users\Public\KVSkillPractice\ui_transport_smoke.md`.
- It reported the interactive desktop was accessible and KV STUDIO was intentionally not opened.

Verified compile smoke evidence:

- VM `103` created disposable project `C:\Users\Public\KVSkillPractice\Projects\CodexUiCompileSmoke`.
- Selected/default CPU model was `KV-X550`.
- `Ctrl+F2` compile/convert produced no visible error dialog and updated `PlcSended.dky`.
- PASS report: `C:\Users\Public\KVSkillPractice\compile_smoke_report.md`.
- Screenshots were written under `C:\Users\Public\KVSkillPractice\screens`.
- This smoke test proves project creation and compile gating only; it does not prove official reference-program reproduction, MNM import/export, official FB-only import, or variable reconstruction.

Require the VM-side agent to write:

- Markdown report with exact steps and pass/fail status.
- Screenshots under `C:\Users\Public\KVSkillPractice\screens` when visual state matters.
- Copied KV STUDIO error text or compile logs when validation fails.

## MNM Export And Import

Export mnemonic list:

Preconditions: KV STUDIO main project window is foreground, no ladder inline edit bar is visible, no modal error dialog is visible, and `scripts/assert_kvstudio_ui_safe.ps1` passes.

1. Use the user-validated accelerator path: `Alt+F`, `R`, `S`.
2. Confirm the foreground window is the expected comment-type dialog titled `选择注释类型`; this dialog is not a failure.
3. Press `Down` once so the comment type becomes `注释1`.
4. Press `Enter`; a directory picker/file-list window opens for the MNM export folder. This picker/list is an expected workflow state, not a failure dialog.
5. If this path fails, first verify preconditions, timing, active window, and external interference. Do not conclude the accelerator path is wrong without evidence.
6. Select the export folder from the picker/list only after proving the picker window/control identity by UIA or equivalent structured evidence.
7. Folder selection still needs a separately validated deterministic method; do not type into the ladder editor or use coordinate fallback.

Import modified mnemonic list:

1. Prepare edited `.mnm` files outside KV STUDIO.
2. If the MNM contains Chinese variable names or comments, store the import file as the Windows system ANSI code page used by KV STUDIO on the target machine, normally CP936 on Chinese Windows. Verify by reading the bytes with `[Text.Encoding]::Default`: names such as `启动`, `红LED灯`, `黄LED灯`, and `绿LED灯` must round-trip before import. A UTF-8-only MNM can display correctly in terminals while importing as mojibake in KV STUDIO.
3. Use the user-validated accelerator path: `Alt+F`, `R`, `R`.
4. Select the folder and file only through a validated deterministic picker method. A valid method must prove a standard file-open dialog or a specific MNM picker before setting the path. AutomationId `1265` alone is forbidden because it aliases the ladder inline edit bar.
5. Import the MNM into the target program/module.
6. Recreate global and local variables before validating.

## Official FB Import

Use this only for official FB/function block resources that should remain unmodified.

1. Use `Alt+F`, `I`, `M`.
2. Select the official program/package directory.
3. Select `All.pregx`.
4. Use arrow keys and `Space` to select only the official FBs/modules allowed by the task.
5. Press `Tab` three times to focus `OK`, then `Enter`.

Do not use this path to import an entire official reference program as the implementation.

## Variable Editor Workflow

1. Use `Alt+V`, then `L` to open variable editing.
2. The default focus is usually the global variable group-name cell.
3. Paste prepared global variable rows from a text/table source.
4. Use `Ctrl+Tab` to switch to local variables.
5. Use arrow keys to choose the target program, then paste local variables for that program.
6. After MNM import, verify every referenced variable, FB instance, structure, array, and data type exists in the correct global/local scope.

Read `references/variable-editor.md` before large variable reconstruction.

Verified KV STUDIO variable-table paste columns:

- Global variable rows are not the same shape as local variable rows. Do not reuse a global TSV row for local variables.
- Global variable paste order: `group name`, `variable name`, `data type`, `assignment target`, `value`, `retain`, `constant`, `OPC UA`, `file export`, `comment 1`, then additional comment columns.
- Example global row shape: `(Default)`, `StartIn`, `BOOL`, `R000`, blank value, `False`, `False`, `非公开`, `False`, `Input IO Start`.
- Local variable paste order: `variable name`, `data type`, `value`, `retain`, `constant`, `file export`, `comment 1`, then additional comment columns.
- Example local row shape: `statu`, `UINT`, blank value, `False`, `False`, `False`, then comments/blanks.
- Each program can contain default local variables that cannot be modified. Add user variables on valid blank rows for the selected program; if a paste confirmation says a variable name will be overwritten, cancel and fail the route.
- Modal gate: when any KV STUDIO popup is present, the only permitted automation is a popup-specific classifier/handler. Do not run variable-edit, import, compile, close-window, or save scripts on top of an unresolved popup. For a `粘贴数据中存在错误，已跳过部分数据粘贴。` popup, press `确定/OK`, then analyze the current variable table against the intended TSV before any further action.

## Compile And Error Collection

1. Run compile/convert verification with `Ctrl+F2`.
2. After every compile/convert attempt, whether success or failure, copy the compile/edit result area text as evidence. The simple manual-equivalent path is: verify the result/error area, select/right-click it, choose copy, then save clipboard text. Do not report compile success or failure without this copied text or an explicitly recorded reason it could not be copied.
3. Determine pass/fail from KV STUDIO state, status text, exported logs, or copied error text. Screenshots are acceptable during exploration, but repeatable validation should use scriptable text/log evidence when possible.
4. If a conversion failure dialog appears, press `Enter` to close it.
5. Focus the error window containing `转换` / conversion messages.
6. Right-click any error row and press `C` to copy all error messages.
7. Use the copied messages to fix MNM and variables, then re-import and rerun `Ctrl+F2`.

Stable conversion-result copy route:

- For automation closure, prefer direct result-tree extraction over coordinate right-click. The verified fast route is:
  1. Resolve the visible KV STUDIO main window for the target project.
  2. Enumerate child HWNDs under that main window with Win32 `EnumChildWindows`.
  3. Select the visible `SysTreeView32` child nearest the bottom of the KV window; this is the conversion result tree.
  4. Create an AutomationElement from that tree HWND only, then read descendant `TreeItem.Name` values.
  5. Join non-empty TreeItem names with CRLF, write them to `compile_result_copied.txt`, and set the clipboard to the same text.
  6. Verify lookup time is under 1000 ms, clipboard is non-empty, and text contains `转换结果 OK` or the expected NG diagnostic.
- Do not use stale coordinates for the result tree. Re-verify the tree HWND and TreeItem text in the same run before claiming copied evidence.
- A successful validated run on 2026-05-26 used `copy_convert_result_from_tree_handle.ps1`: lookup 531 ms, 7 lines, clipboard length 299, `contains_ok=true`, `contains_ng=false`.

## Completion Gate

Before reporting success:

- Confirm the correct project, CPU/model, unit configuration, and imported FB set.
- Confirm program logic was imported or edited as MNM, not by renaming or wholesale importing the official reference program.
- Confirm variables were reconstructed in KV STUDIO.
- Confirm Ctrl+F2 compile/convert passes.
- Record the exact evidence used: VM id or local machine, project path, changed/imported MNM files, imported official FBs, variable source, and compile result.
