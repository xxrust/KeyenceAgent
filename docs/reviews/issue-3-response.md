# Issue #3 逐项复核（评审版本 fcf65bc）

- 被评审版本：`fcf65bc`（评审者称 `origin/main`）；本机 `git log -1` 与 `git merge-base --is-ancestor fcf65bc HEAD` 确认 **当前 HEAD 就是 fcf65bc**，评审对象未过期。
- 评审者环境：macOS，无 `pwsh`、无 Windows 桌面、无 KV STUDIO；**未执行任何 PowerShell 测试**，结论全部来自静态阅读。本机相反：Windows + pwsh 7/5.1 + 可跑脚本，所以下面每项尽量给**可复现证据**（命令 + 输出），并区分"成立 / 部分成立 / 需复核 / 不成立"。
- 结论先行：**14 项全部有结论**——6 项 P1 全部成立（其中 R01/R06 比评审描述更严重，R04 比描述略轻）；P2 里 R12 成立，R07/R08/R09/R10/R11/R13/R14 部分成立，**没有一项被判为完全不成立**；另有 4 处评审说得不准（见文末）。

---

## 速览表

| ID | 等级 | 我的结论 | 证据类型 | 与评审的差异 |
|---|---|---|---|---|
| R01 | P1 | **成立（比描述更严重）** | 实跑复现 | 评审说"结果文件名对不上"——**不成立**，三个文件名都对得上 |
| R02 | P1 | **成立** | 实跑复现 | 无 |
| R03 | P1 | **成立** | 静态 + 代码定位 | DryRun 副作用只有建目录，程度比描述轻 |
| R04 | P1 | **部分成立** | 静态 | 评审低估了：runner 已做节点列身份断言；缺的是 IP↔节点绑定 |
| R05 | P1 | **成立** | 静态 | 无 |
| R06 | P1 | **成立** | 实跑复现 | 评审表述不精确：只有 `variable_sets: []` 才 0/0，属性缺失反而报错 |
| R07 | P2 | 部分成立 | 静态 | 运行期只有 v3m 一套，V2 只是回退；问题是**文档三处口径不一** |
| R08 | P2 | **部分成立（降级可用但无提示）** | 实跑 | 模型目录清空后检索仍正常返回，属静默降级 |
| R09 | P2 | 部分成立 | 静态 | `H:/models` 是候选之一，可用 `KB_MODEL_DIR` 覆盖；构建源确有硬编码 |
| R10 | P2 | **部分成立** | 静态 + 本会话实证 | planner 是「先导入完整 MNM，再写 locals/arguments」，与「先声明再引用」的实测顺序冲突 |
| R11 | P2 | 部分成立 | 静态 | 我的新规则确实"过于绝对"（丢了整机单元例外）；"互相抵觸"更多是**歧义** |
| R12 | P2 | **成立** | 静态 | config 整体重写丢未知键；skill 安装是覆盖复制、不清理上游已删文件 |
| R13 | P2 | 部分成立 | 实跑 | 参数不统一成立；但 aggregator 有 legacy 分支，不会因此误判失败 |
| R14 | P2 | 成立（有保留） | 度量 | operator SKILL.md 576 行/47 KB，确属案例堆积 |

---

## R01｜blocked 依赖仍被标 pass —— **成立，且比评审说的更严重**

**代码**（与评审给的定位一致）：

- `kv-studio-operator/scripts/workflows/verify_kv_plan_integrity.ps1:50` 调 `plan_kv_variable_dependencies.ps1` 只传 `-VariablesTsv`、`-OutDir`；`:52` 按 **退出码** 判 `pass/fail`。
- `plan_kv_variable_dependencies.ps1:129` 只有带 `-RequireReady` 且 blocked>0 才 `exit 41`，否则 `exit 0`。

**实跑复现**（评审者做不到的部分）：

```
plan.json: merged_global_variables_tsv = vars.tsv（含一个 AXIS 结构类型变量）
          variable_sets = []，steps = []
→ verify_kv_plan_integrity.ps1
   exit=0   ok=True
   module_completion     pass
   variable_dependencies pass        ← 下面是它的真实报告
   variable_usage        skipped
依赖报告： ok=False  blocked_count=1  (missing_type:AXIS)
```

即：**依赖明确 blocked、整体 integrity 仍然 ok=true、退出码 0。**

**比评审更严重的一点**：wrapper 从不传 `-StructureDefinitionsPath`，而 `plan_kv_variable_dependencies.ps1:67` 对任何非标量类型都返回 `missing_type:<t>`。也就是说，在这个入口下**任何自定义结构类型（哪怕是工程里合法存在的）都会被判 blocked**，而这个 blocked 又不影响结论——这个检查目前等于"永远通过，或者永远说 blocked 但没人看"。

**评审说的不准处**：他说"helper 尋找的結果檔位置也與子工具的子目錄不同"。我逐个核对：`module_completion.json`、`variable_dependency_report.json`、`variable_usage_report.json` 三个**都**与 wrapper 期望的路径一致（`verify_kv_variable_usage.ps1:216` 也确认是 `variable_usage_report.json`）。这条不成立。

**另一条他没说、但同样要修的**：`:53-55`、`:63-65` 把"没有输入"标成 `skipped`，而 `:67` 只统计 `fail` —— 缺输入 ≠ 通过，但代码里两者等价。

---

## R02｜skip 掩盖失败 —— **成立**

**代码**：`kv-studio-operator/tests/run_all.ps1:87-91` —— 只要报告里 `skipped=true`，就 `status='skip'`、`passed=0`，**`$failed` 不清零、`exitCode` 不看**；`:118` 的 `$failures` 不含 `skip`；`:121` `ok = failures.Count -eq 0`。

**实跑复现**：造一个 suite，写 `{"passed":0,"failed":3,"skipped":true}` 并 `exit 1`，用仓库里的 `run_all.ps1` 跑：

```
KV_TESTS: suites=1 passed=0 failed=0 skipped=1 cases_passed=0 cases_failed=3
run_all exit=0
ok=True  suites_failed=0  cases_failed=3
```

**ok=true 且 cases_failed=3 同时出现**，与评审描述完全一致。根因就是末尾 `$failed` 没有被 skip 分支清掉（`passed` 清了、`failed` 没清）。

---

## R03｜两套 executor 契约不一致 —— **成立（DryRun 程度较轻）**

**代码**：

- 第二套：`kv-studio-operator/scripts/workflow_tools/run_kv_execution_plan.ps1:60-74`，**只认 4 类步骤名**：`(import|repair)_structures`、`(import|repair)_mnm_*`、`(set|repair)_fb_arguments_*`、`(set|repair)_variables_*`，其余 `throw KV_PLAN_STEP_UNSUPPORTED`。
- 正式 planner 产出的步骤含 `verify_module_placement_*`、`assert_*` 等（`get_kv_module_completion.ps1:40` 就按这两种名字做期望判断），第二套 executor 无法消费 → **同一条 plan 只能走 flat executor**。

**DryRun**：`:144` 先 `New-Item -ItemType Directory`、`:146` 删 `exit_code.txt`，`$DryRun` 判断在 `:153` 之后 —— 有副作用，但只是文件系统痕迹，不启动 runner、不碰 KV STUDIO。评审说"修正 DryRun 副作用"成立，严重度低于与 P1 并列的观感。

---

## R04｜EIP Modify 回读未绑定节点 —— **部分成立（评审低估了已有防护）**

**代码**：`edit_eip_devices_guarded.ps1:448-467` 已经做了节点列身份断言：

- Delete：目标节点标签必须全部消失、非目标标签逐项不变；
- Modify：**整列标签必须完全一致**（设备集合与顺序都不许变）；
- `:444` 若重开后读不到节点列，直接 `KV_EIP_NODE_IDENTITY_UNAVAILABLE` 失败。

**真正缺的**是 `:475`：`$ok = ($persistedIps -contains $newIp)`，`persistedIps` 来自 `Read-DeviceIps`（`:428`）是**平铺 IP 列**，没有 (节点 → IP) 的配对。所以"把 IP 写到错误的行、但该 IP 在列表里唯一"这种错误仍会 pass。

→ 评审的**结论成立**、**理由不完整**：不是"只证明 IP 存在"，而是"节点集合与 IP 集合分别验证，缺二者的关联"。修复应把回读改成 `(node, ip)` 对，再断言目标节点那一行的 IP。

---

## R05｜未知弹窗被通用确认 —— **成立**

**代码**：`edit_eip_devices_guarded.ps1:365-383` 与 `:395-411` 两处对话框循环：对任何未被过滤的窗口，只要找到「是(Y)」或「确定」就点。过滤条件是窗口标题为空/`tooltips*`/`Afx*`/编辑器标题，**不区分是否已知类型**。

**与文档冲突**：`kv-studio-operator/SKILL.md:175-186` 写的是"验证过的弹窗固化为已知类型；不要再保留通用遍历 + 默认按钮"，即未知弹窗应停止。

**补充**：循环有 20 s 上限，且「变量设置」窗口是发 `WM_CLOSE` 而不是点确定——比纯粹"无脑点是"好一点，但仍属通用确认，规则与实现确实分叉。注：`:379-380` 的顺序是先「是(Y)」再「确定」，对"是否保存"这类语义相反的弹窗，点错的风险实存。

---

## R06｜模块完整度接受旧回执 / 空集合 —— **成立（表述需修正）**

**代码**：`get_kv_module_completion.ps1:32-45` 只从固定目录读 `step_receipt.json` / `set_variables_result.json`，只判 `.ok`；**没有 run_id、project_identity、input hash、时间戳**任何校验。

**实跑复现**：

```
artifacts/import_mnm_1/step_receipt.json      = {"ok":true,"verified":true}
artifacts/set_variables/module_01_MyMod/set_variables_result.json = {"ok":true}
→ get_kv_module_completion.ps1  exit=0
   ok=True  total_modules=1  complete_modules=1
```

即：**没跑过任何步骤，只手写两个 `{"ok":true}` 文件，模块就算"完整"。**

空集合那条要精确化：`variable_sets: []` → `ok=true, total=0, complete=0`（实跑确认）；但**属性缺失**（不是空数组）时 `@($plan.variable_sets)` 会得到一个 `$null` 元素，反而生成 1 个空名模块并 `ok=false`。两种情况都算缺陷，但评审的"空模組集合也算成功"只在显式空数组时成立。

---

## R07｜V2 / V3 / V3m 三套契约 —— **部分成立（是文档口径不一，不是运行期双实现）**

`kv-studio-kb-programming/SKILL.md`：`:12` 仍写 `primary: <wiki_root>/v3/wiki.v3.db`；`:92-93` 说"检索库已固定为 `wiki.v3m.db`，`wiki.v3.db` 只作对照"；`:101` 说 V2 入口 `query_keyence_kb.py` 保留为回退（并注明中文口语召回差）。

运行期确实只有一条主路径（v3m）+ 一条显式回退，但**同文件三处口径不一**，安装器/配置文件里 `wiki_v3_db` 与 `wiki_root\v3\wiki.v3.db` 也并存 → 评审"三套契约同時存在"成立，但性质是**文档与配置漂移**，不是两套并行实现。

---

## R08｜向量降级与依赖安装 —— **部分成立（降级可用，但无提示）**

实跑对照（同一 DB、同一 query）：

```
KB_MODEL_DIR 指向空目录 → kb_search.py --db ... 'MC_Jog 寸动' -k 2
→ 与有模型时输出一致，exit=0，没有报错
```

即模型不可用时**不会崩**，会退回关键词检索继续工作（降级是"静默"的）。所以"降级保证不完整"这条要分开说：

- **不成立**的部分：降级本身可用，不是"缺模型就不可用"；
- **成立**的部分：没有任何输出提示"现在是降级模式"，上层无法知道自己拿到的是语义排序还是关键词排序；`--mode/--explain` 也没标出来。依赖安装契约（谁装 sentence-transformers / 模型放哪）仍只在注释里，没有正式入口。

---

## R09｜硬编码 H 盘 —— **部分成立**

`kb_rerank.py:4`、`kb_vectors.py:3` 的模型查找顺序是 `KB_MODEL_DIR/<repo>` → `H:/models/...` → `H:/models/models/<org>--<name>`，即 **`H:` 是候选而非唯一**；`kb_search.py:3` 只是注释里写了构建来源 `H:/KeyenceAgent/kb-pipeline`。真正的可重现性问题在**构建脚本的输入源**（`kb-pipeline/` 指向 H 盘资料），这条评审方向对，但"硬编码来源"的强度取决于构建脚本，我未逐行确认全部入口。

---

## R10｜写入顺序 / 原子性不一致 —— **部分成立**

planner 的实际步骤顺序（`new_kv_mvp_execution_plan.ps1:266-455`）：

```
assert_ui_guard_usage → assert_agent_boundary → validate_scaffold → assert_existing_project_source_snapshot
→ assert_mnm_import_plan → create_project → import_structures → stage_default_program
→ import_mnm_N → verify_module_placement_<module> → delete_staged_program
→ set_fb_arguments_* → set_variables_* → compile_convert → copy_convert_result
→ export_project_inventory → verify_saved_scan_order
```

而 `references/complete-module.md:124-126` 写的是"先导入 MNM → 移动到父节点 → `locals` 写入局部变量"。

冲突点不在文档之间，而在**实现与 KV 的实际约束**：本会话在 v9/v10 上实际遇到的是——**程序体里引用了尚未声明的局部实例时，导入直接失败**（`读取助记符列表失败`），必须先建空体、再 `set_variables`、再覆盖正文。也就是说 planner 把"导入完整 MNM"放在 `set_variables_*` **之前**，只对"正文引用不到新局部变量"的工程成立；一旦模块正文引用了新局部实例，这个顺序就会失败。

→ 评审说"写入顺序、模块原子性与实际 planner 不一致"成立，但**证据不是文档互斥，而是 planner 顺序与 KV 导入约束冲突**；修法是 planner 对"正文引用新局部"的模块生成 empty→locals→body 三步，或在文档里明确禁止这种模块一次导入。

---

## R11｜FB 提炼规则过于绝对、正反例冲突 —— **部分成立（这条批的是我上一版的改动）**

- **"过于绝对"成立**：`keyence-plc-programmer/references/fb-first-refactor.md:19` 写"永不 要为官方 FB 再包一层用户 FB"。而实际存在合法例外：把一组官方 FB + 固定参数 + 现场差异封装成"整机单元 FB"，并在 ≥2 台设备复用。我上一版删掉了这个例外，规则因此变成绝对禁令 → 应补回例外条件（何时允许、需要什么证据）。
- **"正反例互相抵觸"部分成立**：`kv-studio-operator/references/project-standard.json` 的 `reuse_principle.instance_rule` 写"每个轴/工位一个 FB 实例"，容易被读成"每轴一个**用户** FB"，而同文件 `example` 明确说轴控不该包用户 FB。这是**歧义**，不是硬矛盾；改法是把 `instance_rule` 改成"官方 FB 也是每轴一个实例；用户 FB 仅在 B 类成立时才有实例"。
- 评审未提到的一点：`fb-first-refactor.md` 与本条规则是 2026-11-13 才加入的，**同一提交里没有同步更新 `project-standard.json` 的 `instance_rule`** —— 这是真实的文档债。

---

## R12｜局部配置更新丢键、升级留旧脚本 —— **成立（两半都成立）**

- **配置丢键**：`setup_keyence_agent.ps1:430-446` 每次用**新建的** `$configObject`（只有 `kvs_exe / work_root / admin_credential_path / admin_user_default / wiki_root`，高级项再多两键）整体 `Set-Content` 覆盖 config.json。用户在配置里加的任何其他键（例如 `wiki_v3_db`、自定义 runner 默认值）在跑 `-Configure kvs_exe` 这类局部更新后会**消失**。
- **升级留旧脚本**：`Copy-SkillDirectory`（`:176-188`）只做 `Copy-Item -Recurse -Force`，不删除目标目录里上游已移除的文件 → 旧脚本会一直留到用户手工清理。

**评审定位不准处**：他引用 `kv-studio-operator/setup*`，仓库里实际的安装器是**根目录** `setup_keyence_agent.ps1`（另有 `scripts/install_keyence_dev_links.ps1`）；结论对，路径错。

---

## R13｜测试入口参数/结果不统一 —— **部分成立**

实测 18 个离线 suite 的 `run.ps1` 参数：**17 个接受 `-WorkRoot`，`variable-attributes` 不接受**（它只有 `-RepoRoot`）。实跑：

```
tests/variable-attributes/run.ps1 -WorkRoot <dir>
→ Cases: 13  Passed: 13  Failed: 0   exit=0   产物=（空，没有 test_result.json）
```

`run_all.ps1` 仍能判它 pass，靠的是 `:99-106` 的 legacy 分支去正则抓 stdout 的 `Passed: N Failed: N`。所以"参数/结果契约不统一"成立，但**不会因此产生假失败**；真正的风险是 legacy 分支只认文本摘要，一旦 suite 改输出格式就会掉进 `no-evidence`。

live 侧 `eip-live-cycle/run.ps1` 同样没有 `-WorkRoot`。

---

## R14｜skill 混入案例规则、与"唯一入口"冲突 —— **成立（有保留）**

度量：`kv-studio-operator/SKILL.md` **576 行 / 46,995 字节**；`keyence-plc-programmer/SKILL.md` 231 行；`kv-studio-kb-programming/SKILL.md` 147 行。operator 这份里确实塞了大量具体弹窗/操作案例（例如 `:169-186` 的弹窗固化清单）。

"与唯一能力入口宣告冲突"：SKILL 里既声明走 manifest/workflow 入口，又在多处直接给出脚本路径调用方式——两种口径并存。是否"必须拆文件"是编辑取舍，但**同一份 SKILL 里两种调用口径并存**这一点成立。

---

## 我认为评审说得不准 / 需要修正的地方

1. **R01 的"结果文件名对不上"** —— 不成立，三个文件名与 wrapper 期望完全一致。
2. **R06 的"空模組集合也算成功"** —— 只有 `variable_sets: []` 成立；属性缺失时反而报 1 个空名模块。
3. **R04 的"只證明 IP 存在"** —— 低估了已有的节点列身份断言；缺的是 IP↔节点绑定，不是"什么都没验"。
4. **R12 的定位** —— 他引用的 `kv-studio-operator/setup*` 在仓库里没有同名文件，需重新定位。
5. **R08 / R10 他也没跑过** —— 和我一样只有静态推断，不宜写成已确认缺陷。
6. **他的整体判断"不宜描述成具有一致保证的自动化交付系统"** —— 方向同意，但把 R01/R06 这类"门禁失效"与 R11/R14 这类"文档口径"并列成同一批 P1/P2 叙事，容易让人以为测试整体不可信；实际 18 个 suite 的**用例逻辑**本身没被质疑，坏的是**汇总与门禁的判据**。

## 我的修复排序（与评审略有不同）

1. **先修"错误成功"的三处判据**（R02 的 `$failed` 清零、R01 的 `-RequireReady` + 读 JSON 而非退出码、R06 的回执绑定 run_id/project/时间）；
2. **再统一入口**（R03 第二套 executor 要么删、要么改成调用 flat executor；R13 给 `variable-attributes` 补 `-WorkRoot` 并输出 `test_result.json`）；
3. **EIP 两处**（R04 回读改 (node,ip) 对、R05 未知弹窗改停止）；
4. **文档收敛**（R11 补回整机单元例外并同步 `instance_rule`、R07 三处口径统一、R14 拆案例到 references）；
5. R09/R12 可按上面结论直接改；R08 只需补"降级要显式上报"；R10 需改 planner 的模块级步骤序列（空体→locals→body）。

---

### 附：本轮用到的复现脚本位置

- R01：`C:\kvrun\issue\R01b\`（plan.json + vars.tsv + integrity 输出）
- R02：`C:\kvrun\issue\R02\tests\`（run_all 副本 + 反例 suite）
- R06：`C:\kvrun\issue\R06\`（手写回执 + module_completion 输出）
- R13：`C:\kvrun\issue\R13\`（suite 实跑）

---

## 附：当前离线套件基线（本轮实跑）

```
kv-studio-operator\tests\run_all.ps1 -WorkRoot C:\kvrun\issue\suite_baseline
→ KV_TESTS: suites=18 passed=18 failed=0 skipped=0 cases_passed=186 cases_failed=0
→ run_all exit=0
```

即评审者标注为"作者纪录、本次未独立重现"的 **18 suite / 186 例全绿**，在本机可复现，且当前没有任何 suite 报告 `skipped`——所以 R02 的缺陷虽然机制成立，**没有污染本次基线**；它污染的是"以后某个 suite 用 skipped 表达环境不满足"时的结论。