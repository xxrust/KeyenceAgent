---
name: ui-automation-breakthrough
description: 指导 Codex 在陌生、脆弱或半已知的桌面 UI 软件中，结合知识库、用户提示、真实界面验证和小步脚本化，探明稳定操作链路并生成可验证自动化脚本。适用于工业软件、工程软件、PLC/IDE、WPF/Win32 工具、复杂浏览器后台等需要从 UI 探索收敛到稳定脚本的任务。
---

# UI 链路探究到稳定脚本

## 契约

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

## 流程

| 步骤 | 动作 | 判据 | 失败处理 |
| --- | --- | --- | --- |
| 1 | 定义目标界面/项目状态 | 目标状态可观察、可测试 | 停止并先定义成功判据 |
| 2 | 收集知识库、用户提示、当前界面事实 | 每条结论有来源：`知识库/用户/界面/脚本` | 无来源结论标为假设 |
| 3 | 拆成最小状态转换 | 每段有前置、动作、观察 | 不写连续大脚本 |
| 4 | 在一次性项目/窗口中探测一个转换 | 有截图、UIA、日志、JSON 或文本证据 | 先分类失败再重试 |
| 5 | 只脚本化已验证转换 | 脚本输出结构化结果和证据路径 | 仅标为探针脚本，不标稳定 |
| 6 | 组合已验证转换 | 干净运行到达目标状态 | 删除或拒绝未验证分支 |
| 7 | 用独立判据验证 | 编译、导出、回读、保存重开或结果文本通过 | 不声明稳定 |
| 8 | 记录接口和边界 | 命令、参数、证据、错误、不支持项明确 | 不发布为稳定能力 |

## 状态记录

使用任务本地记录。保持机器可读。

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

## 用户提示处理

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

规则：

| 情况 | 动作 |
| --- | --- |
| 用户纠正入口或动作 | 立即停止使用旧入口 |
| 用户指出当前模式不能编辑 | 编辑前先检测、恢复或重启 |
| 用户给出局部链路 | 先验证该片段，用它构造下一步探针环境 |
| 用户要求“先成功再脚本” | 先跑手工/探针路径；只脚本化已验证片段 |

## 脚本晋级

```yaml
promotion:
  probe_script:
    allowed_when:
      - one_transition_verified
      - evidence_path_emitted
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

结构化结果形状：

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

## 证据判据

| 声明 | 可接受判据 |
| --- | --- |
| 窗口已打开 | 标题 + UIA/Win32 身份 |
| 设备/列表项已选中 | 动作前捕获选中文本或 ID |
| 字段已配置 | 值回读或已保存配置产物 |
| 项目已改变 | 保存项目 + 重开/导出/回读 |
| 程序/配置可编译 | 官方编译/转换结果文本 |
| 脚本稳定 | 干净运行结果 JSON + 独立判据 |

截图只能辅助；不能单独证明稳定。

## 禁止项

| 模式 | 替代 |
| --- | --- |
| 把相似菜单当成同一操作 | 验证目标对象确实改变 |
| 基于未验证界面猜测写完整脚本 | 先探测一个状态转换 |
| 无新证据就增加等待时间 | 检查状态、焦点、窗口身份 |
| 从单一设备扩大为通用支持 | 写明已验证型号和路径 |
| 静默尝试未验证导入/注册 | 用稳定错误码拒绝 |
| 用当前脏界面状态证明成功 | 在一次性干净项目重跑 |
| 覆盖用户已有脚本 | 新增脚本或只做局部补丁 |

## 示例

正确入口：

```yaml
hint: "项目树 -> 单元配置 -> CPU -> EtherNet/IP"
wrong_entry: "通信设置"
rule:
  action: use_project_tree_unit_configuration
  reject: toolbar_or_menu_communication_settings
oracle:
  - target_window_title_contains_ethernet_ip_setting
  - configured_device_appears_in_project_or_unit_state
```

先片段后链路：

```yaml
verified_fragment:
  action: select_device_leaf_then_press_enter
  evidence:
    - selected_leaf_captured
    - setting_window_updated
next:
  - build_script_for_this_fragment
  - rerun_fragment_to_create_stable_state_for_next_dialog
forbidden:
  - wait_for_full_workflow_before_scripting_any_fragment
```

边界：

```yaml
capability: automatic_file_registration
status: not_stable
script_behavior:
  if input.esi_path:
    throw: UI_CHAIN_UNSTABLE_CAPABILITY
claim_allowed: "registered devices only"
claim_forbidden: "automatic registration supported"
```

## 最终交付

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
