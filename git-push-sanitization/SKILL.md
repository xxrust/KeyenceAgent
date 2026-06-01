---
name: git-push-sanitization
description: 在执行 git push、提交前复核、发布仓库、同步远端、提交自动化脚本或 README/skill 变更前使用。要求 Codex 先扫描敏感信息、个人路径、机器路径、私网地址和凭据；若敏感值是运行必需项，改为本机配置文件或环境变量输入；若缺少该值不影响工作，直接脱敏或删除；验证通过后才允许 push。
---

# Git Push Sanitization

## 合同

```yaml
before_git_push:
  required_gate: sensitive_scan
  fail_closed: true
  scan_scope:
    - full_worktree
    - staged_changes
    - docs
    - scripts
    - examples
  pass_condition:
    - no_secret_literal
    - no_personal_user_path
    - no_private_endpoint
    - no_machine_specific_required_default
    - no_real_project_or_customer_name_when_not_required
```

## 分类

```yaml
classes:
  required_sensitive:
    examples: [password, token, license, private_endpoint, account_name, local_tool_path]
    action:
      - move_to: local_config_or_env
      - commit: template_or_placeholder_only
      - ignore_file: real_local_config
    oracle: repository_runs_with_user_supplied_config

  optional_sensitive:
    examples: [old_test_path, personal_project_name, evidence_absolute_path, cached_args, local_output_dir]
    action:
      - redact_or_delete
    oracle: repository_behavior_unchanged

  non_sensitive_portable_default:
    examples: [C:\Users\Public\..., "%APPDATA%\...", "$env:USERPROFILE\..."]
    action:
      - keep_if_documented_as_default
    oracle: works_across_users
```

## 推送流程

```yaml
procedure:
  - step: inspect_state
    command: git status --short --branch
    oracle: know pushed commits and dirty files

  - step: scan_sensitive
    command: powershell -NoProfile -ExecutionPolicy Bypass -File <skill>/scripts/scan_sensitive.ps1 -RepoRoot <repo>
    oracle: exit_code == 0
    on_fail: classify_each_hit_before_commit_or_push

  - step: remediate_required_sensitive
    when: hit.class == required_sensitive
    action:
      - remove literal from tracked files
      - add config template with placeholder
      - add or verify gitignore for real config
      - load value from env/config/credential store at runtime
    oracle: no tracked file contains real value

  - step: remediate_optional_sensitive
    when: hit.class == optional_sensitive
    action:
      - replace with placeholder
      - replace with portable default
      - delete generated residue
    oracle: scan_sensitive passes

  - step: verify
    commands:
      - git diff --check
      - git status --short --branch
      - rerun sensitive_scan
    oracle: clean scan and expected git status

  - step: push
    command: git push
    precondition: sensitive_scan passed after final commit
```

## 本机配置形态

```yaml
tracked_template:
  path: config/example.json
  values:
    password: "<set locally>"
    token: "<set locally>"
    local_tool_path: "<absolute path on this machine>"

ignored_real_config:
  path_patterns:
    - config/*.local.json
    - config/config.json
    - "**/credentials.xml"

runtime_sources_order:
  - explicit_parameter
  - environment_variable
  - ignored_local_config
  - OS_credential_store
```

## 禁止

```yaml
forbidden:
  - push_without_latest_sensitive_scan
  - commit_real_password_token_key_or_cookie
  - commit_C:\Users\<real-user>\_paths
  - commit_D_or_E_drive_personal_project_paths
  - hide_required_secret_by_empty_default_that_breaks_runtime
  - bypass_scan_because_user_asked_to_push_fast
  - claim_clean_without_reporting_scan_command_and_result
```

## 输出

```yaml
final_report:
  include:
    - scan_command
    - hits_count
    - remediation_summary
    - commit_hash
    - push_result
  if_blocked:
    include:
      - blocking_hit
      - why_config_or_user_secret_is_required
      - exact_local_config_key_needed
```
