# UI Guard Contract

Read this file only when modifying KV STUDIO UI automation scripts or diagnosing a UI guard failure.

## Boundary

All process-wide input must go through `scripts\guards\kv_ui_guard.ps1`.

Being implemented in the guard library is not sufficient for customer-mode
use. `scripts\script_manifest.json` classifies atomic actions as `approved` or
`pending`, and approved runner children may call only approved actions. A new
or changed input route remains pending until its isolated evidence and repeat
regression have passed. Published UI workflows must run the guard-usage gate
before invoking their manifest-declared runner child.

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

Success means runner child scripts contain no raw global input outside the
guard library and call no unregistered or pending atomic action.

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

## Foreground activation is refused after the input session starts

A dialog or embedded editor owns the focus once the runner's input session has begun.
Activating the main window in that state moves the focus off the dialog, which leaves the
panel on screen and makes every later keystroke land in the editor. The rule is therefore
enforced in code, not only documented: Invoke-KvUiGuardForceForeground throws
KV_FOREGROUND_FORBIDDEN_AFTER_INPUT_SESSION in that state, and a workflow that meets a
confirmation panel must answer that panel (its own buttons or keys), never the main window.
## 实测：删除 + 导入是两段式（delete-then-import）必然被拒

- 现象：`DELETE` 模块 → 确认框按名应答成功 → **4 ms** 后导入即报
  `Refusing MNM import route: foreground window is not KV STUDIO`；
  主动补一次置前则被守卫以 `KV_FOREGROUND_FORBIDDEN_AFTER_INPUT_SESSION`（`input_session_already_started`）拒绝。
- 原因：确认框关闭后前台交还第三方窗口，而输入会话已开始，守卫禁止再取前台（本文件既有条款）。
- 结论：**不要用"删除 + 重建"去改内容**。改程序体用 `set_fb_program_body`（就地编辑，对扫描程序同样有效）；
  确需移除模块时单独删除，并与后续导入分成两次独立运行。