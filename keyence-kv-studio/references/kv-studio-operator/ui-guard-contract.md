# UI Guard Contract

Read this file only when modifying KV STUDIO UI automation scripts or diagnosing a UI guard failure.

## Boundary

All process-wide input must go through `scripts\guards\kv_ui_guard.ps1`.

Process-wide input means:

- `SendKeys`
- virtual-key APIs such as `keybd_event`
- mouse APIs such as `SetCursorPos` and `mouse_event`
- clipboard paste used with keyboard submission
- menu accelerators such as `Alt+F,R,R`

Direct control APIs such as UIAutomation `InvokePattern`, UIAutomation `ValuePattern`, and Win32 `SendMessage` to a resolved child HWND may be used when the target control identity is already known.

These APIs are owned by workflow, runner_child, guard, or explicitly authorized research_mode code. Customer-mode agent work starts the manifest-resolved entrypoint and reads its artifacts.

## Guarded Action Contract

Every guarded action must:

1. Know the target HWND before input.
2. Capture `foreground_before`.
3. Prove the foreground HWND matches the target.
4. Attempt at most one controlled foreground restore.
5. Send input only after the foreground proof passes.
6. Capture `foreground_after`.
7. Stop before input if the target is still not foreground.

The guard writes JSON checkpoints under the step output directory. A failed guard emits `KV_UI_GUARD_FAILED` with a JSON payload on stderr.

## Static Gate

Before any scaffold runner touches KV STUDIO, run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File <skill-root>\scripts\gates\assert_kv_mvp_ui_guard_usage.ps1 `
  -ScriptsRoot <skill-root>\scripts `
  -OutDir <work-root>\guard_static_probe
```

Success means runner child scripts no longer contain raw global input outside `scripts\guards\kv_ui_guard.ps1`.

Failure code:

- `KV_UI_GUARD_STATIC_VIOLATION`

Failure action:

- Stop before launching KV STUDIO.
- Inspect `kv_ui_guard_usage_findings.json`.
- Move each reported input operation into `scripts\guards\kv_ui_guard.ps1` or a wrapper that calls it.

## Error Codes

| Code | Emitted by | Meaning | Next action |
| --- | --- | --- | --- |
| `KV_TARGET_WINDOW_MISSING` | `kv_ui_guard.ps1` | Target HWND is zero or unavailable. | Re-resolve the intended window/control before input. |
| `KV_TARGET_WINDOW_NOT_FOREGROUND` | `kv_ui_guard.ps1` | KV STUDIO is foreground, but not the target window. | Stop at checkpoint and inspect the foreground owner. |
| `KV_FOCUS_LOST` | `kv_ui_guard.ps1` | Foreground belongs to an unrelated window. | Stop and inspect foreground owner. |
| `KV_FOCUS_LOST_TERMINAL` | `kv_ui_guard.ps1` | Foreground is a shell/terminal. | Stop; this prevents pasting variables into the agent terminal. |
| `KV_MODAL_PRESENT` | `kv_ui_guard.ps1` | A modal dialog is foreground or blocking. | Handle the modal with a dialog-specific route, or fail. |
