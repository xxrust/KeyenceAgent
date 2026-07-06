# KV STUDIO Script Status

## Useful Artifacts Already Extracted

- `matrix_prepare.ps1`: candidate project matrix builder.
- `open_convert_collect_errors_clean.ps1`: conversion runner and error collector.
- `full_local_restore.ps1`: local-variable bulk paste runner with a direct `.lbl` copy workaround recorded as historical evidence.
- `export_mnm.ps1`: validated MNM export helper for disposable `CodexUiCompileSmoke`; VM-103 evidence produced `Main.mnm` and `exit_code.txt=0`.
- `import_mnm.ps1`: validated on VM-103 for disposable-project UI import and save persistence. It imported the non-empty `FB_Vacuum.mnm`, self-checked `FoundExpectedModule=true` in the KV STUDIO UI tree, sent `Ctrl+S`, and self-checked `FoundInProjectFiles=true` in `persistence_validation.json`. Compile acceptance is established by a later `Ctrl+F9` evidence step.
- `check_vm103_prereqs.ps1`: host-side guardrail before touching VM 103.
- `stage_vm103_script_encoded.ps1`: validated bulk script staging helper for normal cases; when the PVE tunnel drops or QGA emits unexpected CLIXML, direct QGA base64 staging is the safer fallback.
- `run_vm103_interactive_script.ps1`: VM-103 interactive Scheduled Task runner. It now launches child PowerShell hidden and propagates task exit code, but UI automation still depends on actual foreground desktop state.
- `run_vm103_interactive_script_ssh.ps1`: validated SSH-based interactive Scheduled Task runner for VM 103. Use it when direct VM SSH is reachable; supply the host through `-HostName` or `VM103_SSH_HOST`.
- `collect_visible_convert_errors.ps1`: validated for the latest run after minimizing the variable editor. It copied the bottom conversion tree (`ConvertControl/outputTreeControl1`) and produced real `Ctrl+F9` error text.
- `restore_local_vars.ps1`: opens the real standalone variable editor (`AutomationId=KvVariableForm`) and can paste local variable rows. Compiler acceptance is measured by the later `Ctrl+F9` result. The `-RegisterAfterPaste $true` path is recorded as a failed probe because `_buttonRegistration` caused the variable editor to close/hide after several modules and the Scheduled Task had to be stopped.
- `verify_project_names.ps1`: VM-side evidence collector for project variable persistence.

## Acceptance Evidence

- Official `.lbl` import requires KV STUDIO import evidence plus conversion/compile evidence.
- `.lbl` content with matching names is supporting evidence.
- Smoke compile and screenshots are supporting evidence.
- Variable-editor grid screenshots and paste logs are supporting evidence.
- Local-variable acceptance is measured by compiler error movement and final `Ctrl+F9` result.

## Current Evidence Snapshot

- LAN endpoint is available and preferred when the local VM operator reports `active_endpoint_name=lan`; supply the PVE SSH endpoint through `-PveSsh` or `KV_PVE_SSH`.
- VM 103 target project is stored under `<configured-work-root>\official_repro\vm-103\...\CodexOfficialReproKVX.kpr`.
- Latest visible conversion evidence is stored under `<configured-work-root>\official_repro\vm-103\visible_convert_errors_<timestamp>`.
- Error comparison artifacts are stored under `<configured-work-root>\official_repro\vm-103\convert_error_compare_<timestamp>.json`.
- Baseline `visible_convert_errors_20260506_100603`: `13036` header errors; code counts included `214=7798`, `1232=4309`, `1546=871`, `709=36`.
- Latest `visible_convert_errors_20260506_124401`: `13012` header errors; code counts included `214=7798`, `1232=4250`, `1546=871`, `709=37`.
- The unchanged `错误214=7798` proves local-variable UI paste did not materially resolve unresolved variable references.
- The target `.lbl` now contains names such as `gStn`, `gdSt01Cylinder`, `gMcStatus`, and `gAxis`; conversion still reports invalid variable definitions. The current diagnosis is a data-type/global/local registration-shape problem.

## Next Verification Sequence

1. Use the LAN endpoint rather than restoring the old local PVE tunnel.
2. Keep VM `103` reserved by `codex-official-repro-103`.
3. Use `collect_visible_convert_errors.ps1` or its existing evidence when comparing conversion progress.
4. Resume `restore_local_vars.ps1 -RegisterAfterPaste $true` after the registration/close behavior has a verified recovery route.
5. Investigate the KV STUDIO-native data-type/global registration shape that removes `错误709` and reduces `错误214`.
6. After a candidate fix, run real `Ctrl+F9`, then compare `错误214`, `错误1232`, `错误1546`, and `错误709` against `visible_convert_errors_20260506_124401`.
