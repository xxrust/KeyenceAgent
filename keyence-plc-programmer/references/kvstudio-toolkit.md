# KEYENCE KV STUDIO Toolkit

This directory is the central toolkit for reusable KEYENCE KV STUDIO automation.
It replaces the previous pattern where successful probes stayed scattered under VM task folders.

## Current Boundary

This toolkit is enough for repeatable smoke-level work:

1. Generate or select an MNM file.
2. Import it into KV STUDIO through the mnemonic-list route.
3. Save and verify project-file persistence.
4. Run conversion and collect evidence.
5. Package the project plus evidence for review.

It is not yet enough to claim full production-grade autonomous KEYENCE PLC delivery.
The remaining hard parts are official FB boundary handling, data-type registration shape, global/local variable registration, hardware/unit setup, and compile-error repair loops.

## Entrypoint

Run from the `htmlhelp` workspace:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\kvstudio\kvtool.ps1 list
```

Show the manifest:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\kvstudio\kvtool.ps1 manifest
```

## Stable Commands

| Command | Underlying script | Role |
| --- | --- | --- |
| `doctor` | `check_vm103_prereqs.ps1` | Host-side VM/tool preflight. |
| `stage` | `stage_vm103_script_encoded.ps1` | Copy a local script into VM 103. |
| `run-staged` | `run_vm103_staged_script.ps1` | Run a staged VM script. |
| `run-interactive` | `run_vm103_interactive_script_ssh.ps1` | Run a UI script in the logged-on VM desktop. |
| `export-mnm` | `export_mnm.ps1` | KV STUDIO mnemonic-list export. |
| `import-mnm` | `import_mnm.ps1` | KV STUDIO mnemonic-list import and optional save/persistence check. |
| `convert-collect` | `convert_collect.ps1` | Open project, run `Ctrl+F9`, collect evidence. |
| `collect-visible-errors` | `collect_visible_convert_errors.ps1` | Copy visible bottom conversion tree. |
| `verify-names` | `verify_project_names.ps1` | Weak project-file persistence check. |
| `validate-isolated-vm-smoke` | `validate_isolated_vm_smoke.ps1` | Verify VM101/102/103 can generate a minimal MNM from isolated skill/wiki assets without memory. |

## Example: Isolated VM Skill Smoke

Use this after syncing skills/wiki to the editor VMs. It verifies that each VM has:

- isolated `CODEX_HOME`
- `keyence-plc-programmer` with valid frontmatter and no UTF-8 BOM
- local `llm-wiki-v2-keyence/wiki.v2.cleaned.db`
- no `CODEX_HOME\memories`
- working `new_mnm_smoke.ps1`

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  $env:USERPROFILE\.codex\skills\keyence-plc-programmer\scripts\validate_isolated_vm_smoke.ps1
```

This is a skill/tool availability gate, not a full KV STUDIO compile gate.

## Example: Smoke MNM Import and Conversion

Run UI scripts directly in VM 103 by SSH interactive scheduled task:

```powershell
$env:VM103_SSH_PASSWORD = '<password>'

powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\kvstudio\kvtool.ps1 run-interactive `
  -LocalScriptPath .\tools\kvstudio\import_mnm.ps1 `
  -MnmPath 'C:\Users\Public\KVSkillPractice\input\Main.mnm'
```

For scripts that need arguments not represented by `kvtool.ps1`, call `run_vm103_interactive_script_ssh.ps1` directly with `-ScriptArguments`.

## Example: Conversion Evidence

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\kvstudio\kvtool.ps1 run-interactive `
  -LocalScriptPath .\tools\kvstudio\convert_collect.ps1 `
  -VmScriptPath 'C:\Users\Public\KVSkillPractice\tools\kvstudio\convert_collect.ps1' `
  -TimeoutSeconds 900
```

When invoking `convert_collect.ps1` directly in the VM, pass:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File C:\Users\Public\KVSkillPractice\tools\kvstudio\convert_collect.ps1 `
  -ProjectPath 'C:\path\to\project.kpr' `
  -OutDir 'C:\Users\Public\KVSkillPractice\evidence\convert_case_001' `
  -RestartKvs
```

## Asset Classification

Stable:

- `kvtool.ps1`
- `convert_collect.ps1`
- `export_mnm.ps1`
- `import_mnm.ps1`
- `collect_visible_convert_errors.ps1`
- `verify_project_names.ps1`
- VM staging/running helpers

Experimental or evidence-only:

- `probe_*.ps1`
- `tmp_*`
- `remote_*`
- `evidence_*`
- `vm103_*.png`
- `import_global_lbl*.ps1`
- `restore_local_vars.ps1` until the registration behavior is proven

## Operating Rule

Do not promote a probe into the stable set just because it produced screenshots.
Promotion requires a repeatable command, explicit parameters, a known output directory, and evidence that it changes the KV STUDIO project or conversion result in the intended way.
