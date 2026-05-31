---
name: ui-automation-breakthrough
description: 指导 Codex 在陌生、脆弱或半已知的桌面 UI 软件中，结合知识库、用户提示、真实界面验证和小步脚本化，探明稳定操作链路并生成可验证自动化脚本。适用于工业软件、工程软件、PLC/IDE、WPF/Win32 工具、复杂浏览器后台等需要从 UI 探索收敛到稳定脚本的任务。
---

# UI 链路探究到稳定脚本

## 契约

```yaml
objective: verified_ui_automation_script
audience: executing_agent
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
  - script_only_verified_transitions
  - compose_large_workflows_from_verified_script_segments
  - probe_unknown_ui_only_from_a_verified_checkpoint
  - mature_primitive_scripts_are_immutable
  - unknown_behavior_uses_probe_copy_or_wrapper
```

## 输入

| 输入项 | 必需 | 校验 |
| --- | --- | --- |
| `target_state` | yes | 可观察、可复测 |
| `current_ui_state` | yes | 窗口标题 + UIA/Win32/截图/日志之一 |
| `user_hints` | no | 原文记录；纠正优先于旧假设 |
| `knowledge_sources` | no | 本地知识库/官方文档/软件产物路径 |
| `existing_scripts` | no | 只读审查；改动前确认不会覆盖无关脚本 |

## 状态机

```yaml
segment_types:
  mature_script:
    entry: script_command
    oracle: same_run_artifact
    agent_action: run_only
    patch_allowed: false
  unknown_ui_probe:
    entry: verified_checkpoint
    oracle: ui_or_artifact_delta
    agent_action: explore_one_transition
    output_script: new_probe_or_wrapper
  stable_segment_patch:
    entry: verified_probe
    oracle: clean_segment_replay
    agent_action: promote_probe_to_small_script
    patch_existing_mature_script: forbidden

states:
  S0_scope_defined:
    enter_when:
      - target_state.observable == true
      - success_oracle.defined == true
      - workflow.segmented == true
    next: S1_evidence_collected
  S1_evidence_collected:
    enter_when:
      - every_claim.source in [ui, user, kb, script, assumption]
      - assumptions_marked == true
    next: S2_transition_hypothesis
  S2_transition_hypothesis:
    enter_when:
      - transition.precondition
      - transition.action
      - transition.expected_observation
    next: S3_transition_verified
  S3_transition_verified:
    enter_when:
      - evidence.path
      - observation.matches_expected == true
    next: S4_probe_script
  S4_probe_script:
    enter_when:
      - script.outputs_structured_result == true
      - script.replays_verified_transition == true
    next: S5_chain_composed
  S5_chain_composed:
    enter_when:
      - all_segments.status in [mature_script_verified, probe_verified]
      - unsupported_branches.rejected == true
    next: S6_stable_script
  S6_stable_script:
    enter_when:
      - clean_disposable_run == pass
      - independent_oracle == pass
      - no_manual_repair == true
    next: S7_delivered
```

## 分段组合

```yaml
compound_workflow:
  required_order:
    - run_mature_script_to_checkpoint
    - assert_checkpoint_or_stop
    - probe_one_unknown_transition
    - promote_verified_probe_to_small_script
    - resume_next_mature_script_or_repeat_probe
  checkpoint:
    required:
      - window_or_artifact_identity
      - mode_editable_when_editing
      - selected_object_when_selection_matters
      - same_run_evidence_path
  forbidden:
    - explore_full_workflow_from_initial_window_when_mature_prefix_exists
    - mix_mature_segment_failure_with_unknown_ui_failure
    - continue_after_unexpected_window_without_segment_review
    - patch_mature_primitive_script_during_probe
    - enlarge_primitive_script_scope_for_one_task
```

```pseudo
for segment in workflow:
  if segment.kind == mature_script:
    run(segment.script)
    assert(segment.oracle)
    if not ok: stop("mature segment regression or wrong precondition")
  else:
    assert(previous_checkpoint.ok)
    verify_one_transition(segment)
    if verified: create_probe_copy_or_wrapper(segment)
    else: stop_or_record_failure(segment)
```

| 现象 | 分类 | 动作 |
| --- | --- | --- |
| 已有成熟前缀脚本却从初始界面直接探究 | `route_design_error` | 停止；改为先运行成熟脚本到检查点 |
| 进入从未见过的其他界面 | `checkpoint_missing_or_wrong_entry` | 记录错误入口；回到上一个成熟检查点复现 |
| 新功能失败 | `unknown_transition_failure` | 只修该 transition，不重写整条链 |
| 成熟脚本无法到达检查点 | `mature_segment_regression` | 先修成熟脚本；禁止继续探究后续新功能 |
| 为探究新功能而修改成熟脚本 | `mature_script_boundary_violation` | 立即恢复成熟脚本；把新逻辑移到探针副本或包装器 |
| 一个基础脚本开始承载多个目标 | `granularity_drift` | 拆成原子脚本 + 编排脚本 |

## 颗粒度

```yaml
script_granularity:
  primitive_script:
    scope: one_ui_goal
    examples:
      - export_mnm
      - import_one_mnm
      - compile_and_copy_result
      - configure_one_unit_address
    mutable_during_probe: false
    accepts_new_task_logic: false
  probe_script:
    scope: one_unknown_transition
    location: task_workdir_or_new_file
    mutable_during_probe: true
    promotion_requires:
      - same_transition_clean_replay
      - independent_oracle
      - no_regression_of_primitive_script
      - supported_inputs_declared
  orchestrator_script:
    scope: compose_primitive_scripts
    mutable_during_task: true
    forbidden:
      - duplicate_primitive_ui_logic
      - patch_primitive_in_place
```

```pseudo
if mature_script.needs_change_for_new_task:
  restore(mature_script)
  create(probe_or_wrapper)
  run(primitive_script_to_checkpoint)
  run(probe_or_wrapper_from_checkpoint)
  promote_only_after_repeatable_evidence()
```

## 流程

| 步骤 | 动作 | 判据 | 失败处理 |
| --- | --- | --- | --- |
| 1 | 定义 `target_state` 与 `success_oracle` | 目标可观察、判据可复测 | 停止写脚本 |
| 2 | 把工作流切成 `mature_script` 与 `unknown_ui_probe` | 每段有入口、出口、判据 | 不能切分则停止 |
| 3 | 先运行成熟脚本到最近检查点 | 同 run 证据证明检查点成立 | 成熟段失败则先修成熟段 |
| 4 | 收集 UI、用户提示、知识库、现有脚本事实 | 每条结论有 `source` | 标为 `assumption` |
| 5 | 拆成单个 `transition` | 有前置、动作、预期观察 | 继续拆小 |
| 6 | 只在检查点状态验证一个 `transition` | 产出证据路径 | 分类为 `failed/rejected/blocked` |
| 7 | 只把 `verified transition` 写成探针脚本或包装器 | JSON 结果 + 证据路径 | 禁止改成熟基础脚本 |
| 8 | 用探针脚本复现状态，再探下一步 | 下一步前置由脚本创造 | 修正片段，不拼完整链 |
| 9 | 组合全部已验证片段 | 干净运行到达 `target_state` | 删除未验证分支 |
| 10 | 用独立判据验证稳定性 | 编译/导出/回读/保存重开/结果文本通过 | 不声明稳定 |
| 11 | 记录支持范围与拒绝范围 | 支持输入、错误码、边界明确 | 拒绝发布通用能力 |

## 本地记录

```yaml
ui_chain:
  task_root: <disposable path>
  target_state: <observable end state>
  success_oracle: <compile|export|readback|save_reopen|text_result>
  current_state:
    window_title: <text>
    mode: <editable|simulator|unknown>
    evidence: <path>
  claims:
    - text: <claim>
      source: ui|user|kb|script|assumption
  transitions:
    - id: T01
      segment: mature_script|unknown_ui_probe
      precondition: <state>
      action:
        kind: keyboard|uia|win32|mouse|script
        value: <operation>
      observation: <expected UI/artifact>
      evidence: <path>
      status: hypothesis|verified|failed|rejected|blocked
  scripts:
    - path: <script>
      level: probe|stable
      supported_inputs: [...]
      unsupported_inputs: [...]
      artifacts: [...]
      oracle: <pass condition>
  rejected_entries:
    - entry: <wrong entry/action/capability>
      reason: <specific failure>
      replacement: <verified chain or explicit rejection>
```

## 用户提示处理

```pseudo
for hint in user_hints:
  record_verbatim(hint)
  transition = decompose_to_one_transition(hint)
  if hint.corrects_previous_entry:
    reject(previous_entry)
  if current_ui_state.mode in ["simulator", "read_only"]:
    recover_editable_state_before_edit()
  verify_one_transition(transition)
  if transition.status == "verified":
    write_or_patch_probe_script(transition)
  else:
    record_failure_class(transition)
```

| 条件 | 动作 |
| --- | --- |
| 用户纠正入口/对象/按键 | 立即停止旧入口；把旧入口写入 `rejected_entries` |
| 用户给出局部链路 | 先验证该片段；用脚本复现该片段作为下一步前置 |
| 新功能位于已成熟链路中间 | 先运行成熟脚本到最近检查点；只探究新 transition |
| 进入陌生或错误界面 | 判为 `checkpoint_missing_or_wrong_entry`；禁止继续沿该界面探究 |
| 成熟脚本因探究被改慢/改坏 | 立即恢复；新建 probe/wrapper；记录 `mature_script_boundary_violation` |
| 当前模式不可编辑 | 先恢复可编辑状态；恢复失败则停止编辑 |
| 自动导入/注册/识别未验证 | 只允许探针；稳定脚本返回明确错误 |

## 脚本晋级

```yaml
probe_script:
  allowed_when:
    - transition.status == verified
    - evidence.path exists
  required_output:
    - result_json
    - evidence_paths
  forbidden_claims:
    - stable
    - general_support
  forbidden_edits:
    - mature_primitive_script

stable_script:
  required:
    - clean_disposable_project_run == pass
    - independent_oracle == pass
    - no_manual_repair == true
    - unsupported_inputs_rejected == true
    - unrelated_files_untouched == true
  required_output:
    ok: boolean
    chain: string
    inputs: object
    selected_ui: object
    artifacts: array
    oracle:
      name: string
      passed: boolean
    unsupported: array
  promotion_gate:
    - primitive_scripts_unchanged_or_explicitly_versioned
    - old_primitive_use_cases_still_pass
    - new_scope_not_mixed_into_old_primitive
```

## 证据判据

| 声明 | 可接受判据 |
| --- | --- |
| 窗口已打开 | 标题 + UIA/Win32 身份 |
| 列表项已选中 | 动作前捕获选中文本或 ID |
| 字段已配置 | 值回读或保存后的配置产物 |
| 项目已改变 | 保存 + 重开/导出/回读 |
| 配置可用 | 软件官方编译/转换结果文本 |
| 脚本稳定 | 干净运行 JSON + 独立判据 |

截图只作辅助证据。

## 禁止项

| 模式 | 替代 |
| --- | --- |
| 相似菜单等同目标入口 | 验证目标对象发生正确变化 |
| 未验证界面上写完整脚本 | 先验证一个状态转换 |
| 失败后只增加等待时间 | 检查窗口、焦点、模式、状态 |
| 为新功能修改成熟基础脚本 | 新建探针脚本或包装器 |
| 让原子脚本承担编排职责 | 建立 orchestrator 调用多个原子脚本 |
| 单一型号成功后声明通用支持 | 写明已验证型号、输入、边界 |
| 静默尝试未验证能力 | 返回稳定错误码 |
| 用脏项目状态证明成功 | 一次性干净项目重跑 |
| 覆盖用户已有脚本 | 新增脚本或最小补丁 |

## 示例

```yaml
case: wrong_entry_rejected
hint: "项目树 -> 单元配置 -> CPU -> EtherNet/IP"
wrong_entry: "通信设置"
expected_action:
  - reject_entry: "通信设置"
  - verify_transition: "project_tree_unit_configuration_to_ethernet_ip"
oracle:
  - target_window_title_contains_ethernet_ip_setting
  - configured_device_appears_in_project_or_unit_state
```

```yaml
case: fragment_before_chain
verified_fragment:
  action: select_device_leaf_then_press_enter
  evidence:
    - selected_leaf_captured
    - setting_window_updated
expected_action:
  - build_probe_script_for_fragment
  - rerun_probe_to_create_next_precondition
forbidden:
  - wait_for_full_workflow_before_scripting_any_fragment
```

```yaml
case: unstable_capability_rejected
capability: automatic_file_registration
status: not_stable
script_behavior:
  if input.esi_path:
    throw: UI_CHAIN_UNSTABLE_CAPABILITY
claim_allowed: "registered devices only"
claim_forbidden: "automatic registration supported"
```

## 交付

```yaml
deliver:
  scripts:
    - path
    - command
    - parameters
    - supported_inputs
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
