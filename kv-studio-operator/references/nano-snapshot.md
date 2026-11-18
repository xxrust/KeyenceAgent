# Nano snapshot

Use the dedicated public workflow for a saved KV-NC32 project:

```powershell
powershell -STA -NoProfile -ExecutionPolicy Bypass -File scripts/workflows/export_kv_nano_snapshot.ps1 -ProjectPath C:\projects\Nano\Nano.kpr -OutDir C:\kvrun\nano_snap
```

`OutDir` must be new and outside the project directory. `KvsExe` may select the installed editor. Short output paths keep UI evidence within the guard's path budget. The workflow copies the complete project directory, verifies its hashes, opens only that copy, and closes its owned process. Existing user windows are preserved. It reads saved disk state; unsaved changes in another editor are outside the snapshot.

Required collection stages:

- Live program tree: category, module name and order; compare the exact name set with this run's MNM export.
- All exported ladder/script text decoded using the MNM encoding contract. Nano prefixes original script lines with `;` and also exports compiled ladder. Each module's `mnm_comment_blocks.json` removes exactly one prefix from contiguous comment blocks and records their MNM line numbers; ordinary rung comments can occur in these blocks too. Nano script MNM is useful for reading; it cannot be used to import script blocks.
- Global labels and each program's local labels, copied as complete TSV tables. Empty tables have explicit empty files.
- Every installed unit's complete main parameter table, model, R/DM allocation; Port0 serial settings are also indexed separately.
- CPU positioning: point parameters, common point settings, I/O, home return, JOG and comparator tables.
- Global device comments CSV, plus the complete original source directory including original comment banks.

The snapshot is **offline and scoped**. NC1EP's nested `<setting>` windows (connections, FTP/mail/PLC-link etc.), online PLC/runtime state and unverified CPU models are excluded explicitly. KV-X continues to use its own workflow. The snapshot is a reading/backup artifact, not a claim that every asset has an automated restore route.

Artifacts are under `snapshot/project` (readable programs, labels, units, Port0, six positioning TSVs and global CSV), `snapshot/raw` (original files and MNM), `snapshot/text_index.json` (hashes), and `snapshot/source_snapshot_manifest.json`. Phase execution plans and raw receipts remain beside the snapshot. `status=ready` requires complete collection, exact program coverage, unchanged source hashes and successful owned-process closure. A failed required reader stays failed; it is never converted to `skipped` success.

`-PlanOnly` prepares the copy and inventory plan without opening KV STUDIO; it reports `planned` with `live_verified=false`. Dynamic collection is planned only after live inventory. Use `tests/kv-interface-regression/28_nano_snapshot/run.bat` for the blank traffic fixture acceptance.

Verified on KVS 12.41 / KV-NC32, 2026-11-17–18:

- `C:/kvrun/nsbat3/test_result.json`: blank traffic-light fixture replay through BAT, 87 passed / 0 failed. Both complete original script blocks, every planned ladder instruction, full label TSV, six page sizes, every indexed artifact hash and no additional KVS processes were checked. The fixture itself was created from an empty project in `C:/kvrun/nsbat1/fixture` and saved/reopened through its frozen plan.
- Syntax and encoding: 292 PS1 files, zero failures; write ontology coverage: three passed / zero failed, `C:/kvrun/nano_snap_checks/ontology_release/test_result.json`.
