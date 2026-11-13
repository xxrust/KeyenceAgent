# Agent 常犯错误（都是本仓库真机踩过的，照做即可避免）

每条格式：**症状 → 根因 → 规则 → 自检**。这些不是假设，都是 2026-11 在真实 KV STUDIO 上发生过的失败。

## 1. 没实跑就说"验证过"
- 症状：声称"R10 已验证"，实际只跑了 planner 生成计划和离线断言，没有一次 KV STUDIO 执行。
- 根因：把"计划层通过"当成"执行层通过"。
- 规则：结论凡涉及"在 KV STUDIO 里成立"，必须有 **live 回执或编译结果**；否则只能说"计划层已验证，执行层未验证"。
- 自检：回答里能不能给出 exit code / 编译输出 / 产物路径？给不出就改口。

## 2. 手搓 plan JSON 喂 flat executor
- 症状：`KV_PLAN_REQUIRED_GATE_ORDER: gates/assert_kv_mvp_ui_guard_usage.ps1`、`KV_PLAN_STEP_OUT_DIR_MISMATCH`。
- 根因：执行器要求 planner 产出的完整形状（前置 gate、固定 out_dir 约定、步骤顺序）。
- 规则：**不要手拼计划**。要么用 planner 产出，要么直接按顺序调 `runner_children/*.ps1` 单步。
- 自检：计划 JSON 是你写的还是 planner 写的？是自己写的就别喂执行器。

## 3. 用字符串替换盲改"一名字多处用"
- 症状：改完 `Parser` 报语法错（如 187 行 unexpected token），或步骤名/目录名错位。
- 根因：`import_mnm_$($i+1)` 同时用作**步骤名、-OutDir 子目录、artifact 路径**，一次正则替换三处全中。
- 规则：先 grep 出现次数与上下文；把"命名"和"路径"分开改；纯增量优先（新名字 + 新步骤），不要动老标识符。
- 自检：改完必须 `[Parser]::ParseFile` 返回 0 错 + 跑对应套件。

## 4. `git add -A -- <dir>`
- 症状：把无关的既有 untracked 文件（如 `tests/table-cell/1500`、`qa_card.png`）带进提交。
- 规则：**永远显式列文件**；提交前 `git status --porcelain` 核对；发现误加用 `git rm --cached` 撤。
- 自检：提交信息里点到的文件 = 实际 diff 里的文件。

## 5. 写回 .ps1 丢 UTF-8 BOM
- 症状：`script-hygiene` → `non_ascii_without_utf8_bom`，整套测试从 186 掉到 183。
- 根因：用 `UTF8Encoding($false)` 或普通 `Set-Content` 覆盖了含非 ASCII 的脚本。
- 规则：改含非 ASCII 的 `.ps1` 必须保留/补 BOM（`EF BB BF`）；先读原文件 BOM 再决定编码。
- 自检：跑 `kv-studio-operator/scripts/gates/assert_kv_script_syntax.ps1`，`encoding_failure_count=0`。

## 6. 把"进度框"当成"未知弹窗"
- 症状：live EIP 保存在 `正在应用更改` 弹窗处 `KV_UI_UNKNOWN_DIALOG` 停机。
- 规则：弹窗分三类——**等待类**（正在应用更改/正在保存/请稍候/処理中：只 sleep，不点键）、**已知确认类**（白名单标题才允许点 是/确定）、**未知类**（停止 + 截图）。
- 自检：白名单里有没有进度类？未知类是否真的 `Fail`？

## 7. 假设"列复制可以按行配对"
- 症状：`ip/node column counts differ (ip=5 node=12); node-ip binding unverifiable`；或修错为 `$preIps[$null]` 这种荒唐索引。
- 根因：KV 的 IP 列是**过滤后的列表**，节点列含连接行，行数天然不等。
- 规则：不要按行配对；用**集合增量**证明（旧地址消失、新地址唯一出现、其他不变），重复行用 `Select-Object -Unique`。
- 自检：断言里用的是行号还是地址集合？

## 8. 夹具/示例变量名像软元件
- 症状：`KV_VARIABLE_NAME_SOFT_DEVICE_CONFLICT`。
- 规则：变量名用语义名（`bR10Probe`、`diStart`），不要 `MR9000`/`DM100` 这类软元件样式。
- 自检：新写的 TSV 里有没有 `^(MR|DM|W|B|R)\d` ？

## 9. 猜 runner 参数
- 症状：`NamedParameterNotFound,set_fb_program_body_guarded.ps1`。
- 根因：`set_fb_program_body_guarded.ps1` 只接受 `-ProjectPath -FbModuleName -MnmPath -OutDir`，没有 `-ChecklistPath`。
- 规则：调 runner 前读它的 `param()` 或 `script_manifest.json` 登记；不要照抄相近脚本的参数。
- 自检：参数名能否在 param 块里逐字找到？

## 10. 没准备 CHECKLIST.md 就跑 runner
- 症状：先 `KV_CHECKLIST_MISSING`，补了文件后 `KV_CHECKLIST_INVALID`（缺标记）。
- 规则：checklist 必须含 **`# Checklist` / `## KV STUDIO` / `## Steps`** 三个标记段；放在 run 树或用 `-ChecklistPath` 传入。
- 自检：三个标记齐全？runner 是否支持该参数（见第 9 条）？

## 11. 模块正文引用"本次才声明的局部实例"
- 症状：`读取助记符列表失败`。
- 规则：这种模块必须**三步**：先导入空体（`empty_body_mnm`）→ 声明 locals/arguments → 用 `set_fb_program_body_guarded.ps1` 覆盖正文。planner 已在 `new_kv_module_execution_plan.ps1` 支持 `empty_body_mnm` 字段（产出 `import_mnm_empty_N` + `set_fb_program_body_<module>`）。
- 自检：正文里出现的局部实例，是否都在本次 `locals.tsv` 里？那就要走三步。

## 12. 在"改名"上顺手改行为
- 症状：为了去掉历史名字，连带改了步骤名/路径约定，导致计划校验失败。
- 规则：改名只改名字，行为零变化；改名后全仓 grep 旧名 = 0，再跑全量套件。
- 自检：`git show --stat` 里是否出现非命中的逻辑改动？