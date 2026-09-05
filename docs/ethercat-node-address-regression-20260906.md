# EtherCAT Node Address Commit Regression

The previous runner changed a WinForms PropertyGrid editor through UIA
ValuePattern.SetValue and immediately read the same editor. This reported the
requested address even though the device retained its original address.
Switching devices restored the original value. SetValue followed by Enter was
also insufficient in the observed editor state. The earlier claim that KV
STUDIO automatically compacts nonconsecutive addresses was unsupported.

The corrected runner focuses the resolved address value cell, checks the
focused Edit control's process and bounds, sends actual editing keystrokes,
commits with Enter, and refreshes the property surface before readback. The
existing exact node/model persistence check remains mandatory.

## Live Validation

Environment: KV STUDIO 12, KV-X520, Windows desktop. A disposable copy of the
built-in KVX v100 sample was used; the original 31 files match their baseline
SHA-256 hashes after testing. The original sample includes reserved nodes.

| Catalog Model | Requested Address | Full Node Operation | Saved Readback |
| --- | ---: | ---: | --- |
| YAKO MS-MINI3E | 40 | 5724 ms | passed |
| SV630_1Axis_03713 | 41 | 5421 ms | passed |
| KV-EC01 | 47 | 6264 ms | passed |
| CL3C-EC503(COE) | 53 | 5008 ms | passed |

Both batches used the published configure_kv_ethercat_nodes.ps1 workflow.
After closing the saved project, restarting KV STUDIO, reopening EtherCAT
settings, accepting and saving again, all four exact mappings still passed.
End state: one main project window, no EtherCAT settings or modal dialogs.
The UI guard static gate and git diff whitespace check passed.

Before the successful runs, two trials failed the new focus gate and cancelled
unsaved changes. UIA SetFocus had selected the PropertyGrid row (TreeItem), not
the Edit control. Clicking inside the resolved value-cell bounds fixed this.

The installed guard was missing 78 lines already present in the repository,
including unified run.log and action timing. Its prior version was backed up
and the repository guard synchronized to the installed skill. The second
batch and restart audit include guarded atomic actions in their run.log.

## Local Evidence

Evidence root: H:\kvOp\ethercat_address_fix

- regression1/run.log and regression2/run.log: focus failures, clean cancellation.
- regression3/run.log: successful addresses 40 and 41.
- regression4/run.log: successful addresses 47 and 53, unified guard actions.
- inspection/run.log: investigation and saved-project restart audit.
- inspection/reopened_persistence.json: all four mappings after restart.
- nodes.json and nodes2.json: published workflow inputs.
- static_final/kv_ui_guard_usage_findings.json: guard audit artifacts directory.

This validates address commit and persistence across four device models. It
does not assert that the entire sample (reserved states, PDOs, axis parameters,
variables and program logic) has been reconstructed.
