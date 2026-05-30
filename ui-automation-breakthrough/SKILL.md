---
name: ui-automation-breakthrough
description: 指导 Codex 在陌生、脆弱或半已知的桌面 UI 软件中，结合知识库、用户提示、真实界面验证和小步脚本化，探明稳定操作链路并生成可验证自动化脚本。适用于工业软件、工程软件、PLC/IDE、WPF/Win32 工具、复杂浏览器后台等需要从 UI 探索收敛到稳定脚本的任务。
---

# UI 链路探究到稳定脚本

## Contract

```yaml
objective: verified_ui_automation_script
input_priority:
  - current_ui_evidence
  - user_hint_or_correction
  - official_or_local_knowledge_base
  - existing_scripts
  - model_inference
invariants:
  - never_claim_stable_without_clean_run_evidence
  - never_expand_scope_from_one_success
  - never_overwrite_unrelated_user_scripts_or_projects
  - reject_unverified_capability_explicitly
```

## Procedure

| step | action | oracle | on_fail |
| --- | --- | --- | --- |
| 1 | define target UI/project state | target state is observable and testable | stop and define success oracle |
| 2 | collect KB/user hints/current UI facts | each claim has source: `kb/user/ui/script` | mark unsupported claims as hypothesis |
| 3 | split workflow into smallest state transitions | each transition has precondition/action/observation | do not write continuous script |
| 4 | probe one transition in disposable project/window | artifact exists: screenshot/UIA/log/json/text | classify failure before retry |
| 5 | script only verified transition | script emits structured result and evidence path | keep as probe script, not stable script |
| 6 | compose verified transitions | clean run reaches target state | remove or reject unverified branch |
| 7 | validate with independent oracle | compile/export/readback/save-reopen/result text passes | no stability claim |
| 8 | document interface and boundary | command, params, artifacts, errors, unsupported cases are explicit | do not publish as stable |

## State Record

Use a task-local record. Keep it machine-readable.

```yaml
ui_chain:
  task_root: <disposable path>
  target_state: <observable end state>
  current_state: <window/project/mode>
  transitions:
    - id: T01
      precondition: <state>
      action: <keyboard/uia/win32/mouse/script>
      observation: <expected UI/artifact>
      evidence: <path>
      status: hypothesis|verified|failed|rejected
  stable_scripts:
    - path: <script>
      supported_inputs: [...]
      artifacts: [...]
      oracle: <pass condition>
  rejected_entries:
    - entry: <wrong entry/action>
      reason: <specific failure>
      replacement: <verified chain or stop>
  boundaries:
    - capability: <not supported>
      behavior: reject|probe_only|requires_user
```

## User Hint Handling

```pseudo
for hint in user_hints:
  record(hint)
  hypothesis = decompose_to_ui_transition(hint)
  if hypothesis.conflicts_with_current_ui:
    prefer(user_correction, current_ui_evidence)
  verify_one_transition(hypothesis)
  if verified:
    convert_to_script_step(hypothesis)
  else:
    store_as_failed_or_blocked(hypothesis)
```

Rules:

| case | action |
| --- | --- |
| user corrects entry/action | stop using old entry immediately |
| user says current mode cannot edit | detect/recover/restart before edit |
| user gives partial chain | verify that segment first; use it to build next probe environment |
| user asks “先成功再脚本” | run manual/probe path first; script only verified fragment |

## Script Promotion

```yaml
promotion:
  probe_script:
    allowed_when:
      - one transition verified
      - evidence path emitted
    forbidden_claims:
      - stable
      - general_device_support
  stable_script:
    required:
      - clean_disposable_project_run
      - no_manual_repair
      - structured_result_json
      - independent_oracle_passed
      - unsupported_inputs_rejected
      - no_unrelated_file_overwrite
```

Result JSON shape:

```json
{
  "ok": true,
  "chain": "verified-ui-chain-id",
  "inputs": {},
  "selected_ui": {},
  "artifacts": [],
  "oracle": {
    "name": "compile/export/readback/save_reopen",
    "passed": true
  },
  "unsupported": []
}
```

## Evidence Oracles

| claim | acceptable oracle |
| --- | --- |
| window opened | title + UIA/Win32 identity |
| device/list item selected | selected text/id captured before action |
| field configured | value readback or saved config artifact |
| project changed | saved project + reopen/export/readback |
| program/config compiles | official compile/convert result text |
| script stable | clean run result JSON + independent oracle |

截图只能辅助；不能单独证明稳定。

## Forbidden

| pattern | replacement |
| --- | --- |
| treating similar menu as same operation | verify target object changed |
| writing full script from unverified UI guess | probe one transition first |
| increasing sleep without new evidence | inspect state/focus/window identity |
| claiming broad support from one device | state exact verified model/path |
| silently trying unverified import/registration | reject with stable error code |
| using current dirty UI state as proof | rerun in disposable clean project |
| overwriting existing user scripts | add new script or patch scoped file only |

## Examples

Correct-entry example:

```yaml
hint: "项目树 -> 单元配置 -> CPU -> EtherNet/IP"
wrong: "通信设置"
rule:
  action: use project-tree unit configuration
  reject: toolbar/menu communication settings
oracle:
  - target window title contains EtherNet/IP setting
  - configured device appears in project/unit state
```

Fragment-before-chain example:

```yaml
verified_fragment:
  action: select device leaf then press Enter
  evidence: selected_leaf captured + setting window updates
next:
  build script for this fragment
  rerun fragment to create stable state for next dialog breakthrough
forbidden:
  - wait for entire workflow knowledge before scripting any part
```

Boundary example:

```yaml
capability: automatic_file_registration
status: not_stable
script_behavior:
  if input.esi_path:
    throw: UI_CHAIN_UNSTABLE_CAPABILITY
claim_allowed: "registered devices only"
claim_forbidden: "automatic registration supported"
```

## Final Deliverable

```yaml
deliver:
  scripts:
    - path
    - command
    - parameters
    - unsupported_inputs
  evidence:
    - clean_run_result
    - oracle_artifact
  docs:
    - verified_chain
    - rejected_entries
    - boundaries
  git:
    - commit_if_skill_or_script_changed
```
