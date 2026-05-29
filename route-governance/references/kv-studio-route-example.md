# KV STUDIO Route Example

Use this example when the user gives a fixed KV STUDIO workflow.

## MNM Import Route

```json
{
  "route_id": "kv_mnm_import_accelerator_v1",
  "owner": "user_specified",
  "commitment_level": "locked",
  "status": "active",
  "preconditions": [
    "KV STUDIO visible main window exists",
    "foreground window title starts with KV STUDIO",
    "foreground project title matches target project",
    "no modal dialog is visible",
    "no ladder inline edit bar is visible",
    "MNM file exists and passes encoding guardrail"
  ],
  "action_surface": {
    "allowed": [
      "keyboard_accelerator",
      "win32_window_probe",
      "uia_observation",
      "file_dialog_valuepattern",
      "process_control"
    ],
    "forbidden": [
      "uia_menu_click",
      "mouse_click",
      "coordinate_click",
      "editor_text_input",
      "clipboard_fallback"
    ]
  },
  "observation_surface": [
    "After Alt+F a Win32 popup menu is visible",
    "After first R the mnemonic-list menu state is visible or file dialog transition is observed",
    "After second R a standard file-open dialog is verified",
    "The file path is set only in the verified dialog filename control"
  ],
  "failure_boundary": [
    "If the standard file dialog is absent, close KV STUDIO and mark the route blocked or failed",
    "Do not switch to UIA menu clicking without user approval",
    "If the ladder inline edit bar appears, record this as a route violation and close KV STUDIO"
  ]
}
```

## Required Interpretation

- UIA can observe state. UIA must not click or expand KV STUDIO menus in this route.
- Win32 can detect foreground windows, popup menus, and dialogs. Win32 must not replace the user route.
- Closing KV STUDIO after a hazardous state is cleanup, not progress.
- Creating the inline edit bar and then closing it is a failed route attempt.

## Example Commands

```powershell
python C:\Users\liangyuhang\.codex\skills\route-governance\scripts\route_guard.py init `
  --state E:\personal_project\rust_plc\out\traffic_light_min_loop_20260525\route-state.json `
  --task "KV STUDIO MNM import MVP" `
  --route-id kv_mnm_import_accelerator_v1 `
  --owner user_specified `
  --commitment locked `
  --allowed keyboard_accelerator `
  --allowed win32_window_probe `
  --allowed uia_observation `
  --allowed file_dialog_valuepattern `
  --allowed process_control `
  --forbidden uia_menu_click `
  --forbidden mouse_click `
  --forbidden coordinate_click `
  --forbidden editor_text_input `
  --forbidden clipboard_fallback `
  --precondition "KV STUDIO foreground title matches target project" `
  --precondition "no ladder inline edit bar is visible" `
  --observation-rule "standard file-open dialog appears after Alt+F,R,R" `
  --failure-boundary "absence of verified file dialog stops the route"
```
