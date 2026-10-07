# 13 Project Text Snapshot

This is the read-only Agent-oriented export scenario. It opens the copied test project itself and composes the existing inventory, MNM, all-global-variable-groups, local-variable, structure, and FB-argument snapshot routes into one version-control-friendly directory. The global-variable artifact is produced through the variable-group selector (`Alt+G`, select all, confirm) and is not limited to `(Default)`.

The accepted output is `workflow/workflow_result.json` with `ok=true`, plus the referenced `workflow/snapshot/source_snapshot_manifest.json`, `workflow/snapshot/project/` semantic tree, and `workflow/snapshot/text_index.json`. The manifest must bind the snapshot to a SHA-256 project fingerprint and report `status=ready`; `semantic_project_status` reports whether the canonical tree is complete. Official/library FBs that are not exposed as project-tree items are recorded in `skipped_capabilities` with an explicit reason; unsupported data is never fabricated.

The semantic tree also materializes every `程序`/`功能块` folder reported by `WsTreeEnv.xml`, including folders with no modules. Such folders contain `folder.json` and a `project_folder` entity so an empty workstation/category is not lost.
Module display labels such as `FB_Cylinder:气缸控制` are retained in the FB entity's `display_name`; they are not materialized as an additional folder beside the `FB_Cylinder` module entity.

Run with `run.bat -NoPause`, or use `run.ps1 -PlanOnly` for dispatch validation only.
