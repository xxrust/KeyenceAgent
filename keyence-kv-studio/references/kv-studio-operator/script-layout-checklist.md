# 脚本分层规则

本 reference 用于理解 `scripts` 目录的稳定角色边界。客户态入口以 `scripts/script_manifest.json` 为准，文件存在不代表客户态可直接运行。

```yaml
role_directories:
  workflows: customer_callable orchestration
  harnesses: customer_callable repeatability/regression harnesses
  scaffold_tools: customer_callable scaffold/preflight tools
  root_customer_non_ui_tools: customer_callable preparation, read-only extraction, or filtering tools listed in manifest
  runner_children: workflow-called UI or KV STUDIO atomic steps
  guards: shared UI input libraries
  probes: research-only route exploration
  gates: customer_callable non-UI validation
```

```yaml
manifest_rule:
  customer_mode:
    - run entries with customer_callable == true
    - prefer role-directory path from manifest
    - treat unlisted root-level scripts as unclassified
  runner_children:
    callable_by:
      - customer_workflow
      - regression_harness
  customer_workflow:
    calls:
      - workflow_tool
      - runner_child
    flat_rule: no customer_workflow calling customer_workflow
    structure:
      - generate_execution_plan
      - invoke_shared_flat_execution_runner
      - read_same_run_result
  shared_flat_execution_runner:
    path: workflow_tools/invoke_kv_flat_execution_plan.ps1
    owns:
      - step_execution
      - timeout
      - failure_collection
      - result_json
    calls:
      - runner_child
      - workflow_tool
      - gate
  guards:
    callable_by:
      - runner_child
  probes:
    callable_by:
      - research_mode
```

Customer-facing documentation and workflow composition use the role-directory path recorded in manifest. Root-level scripts that are not listed in manifest are unclassified. Classify them in manifest, add evidence, and define a role before using them as customer-mode entrypoints.
