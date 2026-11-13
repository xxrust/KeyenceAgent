# Issue #3 逐项复核（评审版本 fcf65bc）

- 被评审版本：`fcf65bc`（评审者称 `origin/main`）；本机 `git log -1` 与 `git merge-base --is-ancestor fcf65bc HEAD` 确认 **当前 HEAD 就是 fcf65bc**，评审对象未过期。
- 评审者环境：macOS，无 `pwsh`、无 Windows 桌面、无 KV STUDIO；**未执行任何 PowerShell 测试**，结论全部来自静态阅读。本机相反：Windows + pwsh 7/5.1 + 可跑脚本，所以下面每项尽量给**可复现证据**（命令 + 输出），并区分"成立 / 部分成立 / 需复核 / 不成立"。
- 结论先行：**14 项里 6 项 P1 全部成立**（其中 R01/R06 比评审描述更严重，R04 比描述略轻），P2 里 R07/R09/R11/R13/R14 部分成立，R08/R10/R12 我**没有足够证据**判定（下文标注"需复核"，不做和稀泥的"大致成立"）。

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
| R08 | P2 | **需复核** | 未核 | 未逐行核对向量降级路径，不表态 |
| R09 | P2 | 部分成立 | 静态 | `H:/models` 是候选之一，可用 `KB_MODEL_DIR` 覆盖；构建源确有硬编码 |
| R10 | P2 | **需复核** | 未核 | 需比对 planner 实际写序与文档，本轮未做完 |
| R11 | P2 | 部分成立 | 静态 | 我的新规则确实"过于绝对"（丢了整机单元例外）；"互相抵觸"更多是**歧义** |
| R12 | P2 | **需复核** | 未核 | setup 脚本本轮未细读 |
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

## R08｜向量降级与依赖安装 —— **需复核（我不下结论）**

本轮只确认 `kb_vectors.py:3` 有模型查找顺序注释，未逐行核"模型缺失时的降级是否真的回退到关键词检索"。评审也承认未跑 benchmark。**这条需要一次实跑（拔掉模型目录）才能定论**，我不在没有证据时附和。

---

## R09｜硬编码 H 盘 —— **部分成立**

`kb_rerank.py:4`、`kb_vectors.py:3` 的模型查找顺序是 `KB_MODEL_DIR/<repo>` → `H:/models/...` → `H:/models/models/<org>--<name>`，即 **`H:` 是候选而非唯一**；`kb_search.py:3` 只是注释里写了构建来源 `H:/KeyenceAgent/kb-pipeline`。真正的可重现性问题在**构建脚本的输入源**（`kb-pipeline/` 指向 H 盘资料），这条评审方向对，但"硬编码来源"的强度取决于构建脚本，我未逐行确认全部入口。

---

## R10｜写入顺序 / 原子性不一致 —— **需复核**

需要把 `new_kv_mvp_execution_plan.ps1` 的步骤生成顺序与 `references/*.md` 里写的"先变量后 FB 自变量"等规则逐条对照。本轮时间不够，不做结论。

---

## R11｜FB 提炼规则过于绝对、正反例冲突 —— **部分成立（这条批的是我上一版的改动）**

- **"过于绝对"成立**：`keyence-plc-programmer/references/fb-first-refactor.md:19` 写"永不 要为官方 FB 再包一层用户 FB"。而实际存在合法例外：把一组官方 FB + 固定参数 + 现场差异封装成"整机单元 FB"，并在 ≥2 台设备复用。我上一版删掉了这个例外，规则因此变成绝对禁令 → 应补回例外条件（何时允许、需要什么证据）。
- **"正反例互相抵觸"部分成立**：`kv-studio-operator/references/project-standard.json` 的 `reuse_principle.instance_rule` 写"每个轴/工位一个 FB 实例"，容易被读成"每轴一个**用户** FB"，而同文件 `example` 明确说轴控不该包用户 FB。这是**歧义**，不是硬矛盾；改法是把 `instance_rule` 改成"官方 FB 也是每轴一个实例；用户 FB 仅在 B 类成立时才有实例"。
- 评审未提到的一点：`fb-first-refactor.md` 与本条规则是 2026-11-13 才加入的，**同一提交里没有同步更新 `project-standard.json` 的 `instance_rule`** —— 这是真实的文档债。

---

## R12｜局部配置更新丢键、升级留旧脚本 —— **需复核**

本轮只确认仓库根有 `setup_keyence_agent.ps1`，未核它写 config 是"读-改-写"还是整体覆盖，也未核升级时是否清理已删除的脚本。评审给的定位（`kv-studio-operator/setup*`）在我这里不存在同名文件，说明**他的路径引用可能也对不上**，这条需要先定位再判定。

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
5. R08/R09/R10/R12 先补证据再改。

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