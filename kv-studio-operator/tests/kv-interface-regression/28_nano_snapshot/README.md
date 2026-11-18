# Nano project snapshot

Run `run.bat -OutRoot C:\kvrun\nano_snap_test` with a new, short output directory. Set `KV_TEST_NO_PAUSE=1` for automation. `-PlanOnly` prepares the blank fixture plan and does not claim live verification.

The harness creates a blank KV-NC32 traffic-light project using the existing frozen example plan, then calls `export_kv_nano_snapshot.ps1` once. Assertions compare complete box/area script sources and the planned label TSV, check a ladder output, six page row counts, Port0, every indexed artifact hash, unchanged source hashes, and closure of owned processes. Existing KVS processes must survive. No PLC transfer is performed.

The richer three-unit, nine-program source-copy acceptance is recorded separately from this blank-fixture case. A successful snapshot is scoped to the assets documented in `references/nano-snapshot.md`; nested NC1EP setting windows are excluded explicitly.

To replay only snapshot collection against the same saved blank-project fixture, pass `-FixtureResultPath C:\kvrun\previous\fixture\test_result.json`. The source project is copied again; it is never edited. Script checks compare the exact exported `;`-prefixed block and the complete readable comment block, while preserving the original MNM.

Actual BAT replay: `C:/kvrun/nsbat3/test_result.json`, 87 passed / 0 failed, KVS 12.41 / KV-NC32. Fixture creation and saved/reopened content evidence: `C:/kvrun/nsbat1/fixture/test_result.json`. Original three user processes survived; no additional processes remained.
