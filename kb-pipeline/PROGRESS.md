# KB pipeline progress

Goal: 清洗和切块 → trigram + jieba 混合检索 + 同义词 → 定本体 → 抽取卡片并挂证据 → 向量检索，每步用 benchmark 测。
Status: **all stages done (2026-11-02)**.

**2026-11-14 起只有一本库**：`dist/kb-v3m-2026-11-03/wiki.v3m.db`（仓库内，451.9 MB，运行时唯一来源）。
旧的 `wiki.v2.cleaned.db`、`wiki.v3.db`、以及 `H:\llm-wiki-v2-keyence\v3\wiki.v3m.db` 副本已删除，
stage1 的 V2 源不再随仓库提供；需要重建时请先重新取得原始 V2 库。
各 stage 脚本的默认库路径已改为仓库内 `dist/kb-v3m-2026-11-03/wiki.v3m.db`，可用环境变量 `KB_DB` 覆盖。
Runtime entry (in the skill): `kv-studio-kb-programming/scripts/kb_search.py` (+ `kb_vectors.py`, `kb_rerank.py`);
`search_v3.py` here is a shim.
Model: bge-m3 from ModelScope at `H:\models\models\BAAI--bge-m3\snapshots\master` (huggingface.co and hf-mirror unreachable from Python);
bge-reranker-v2-m3 (only for experiments, off by default) at `H:\models\models\BAAI--bge-reranker-v2-m3\snapshots\master`.
Python deps: jieba; optional torch 2.5.1+cu118 (driver is CUDA 11.2), transformers 4.46.3, sentence-transformers 3.3.1 (newer transformers breaks on torch 2.5).

Rebuild all (**wiki.v3m.db is the only runtime library**; the v3 control library is archived, see above):
```
# v3m (runtime): MinerU text for the PDF pages whose text layer is garbled
KB_SOURCE_DB=<path-to-v2-cleaned.db> KB_DB=dist/kb-v3m-2026-11-03/wiki.v3m.db python stage1_clean_chunk.py --mineru
KB_DB=dist/kb-v3m-2026-11-03/wiki.v3m.db python stage2_index.py
KB_DB=dist/kb-v3m-2026-11-03/wiki.v3m.db python stage4_cards.py
KB_DB=dist/kb-v3m-2026-11-03/wiki.v3m.db python stage5_vectors.py --model bge-m3
# optional control build (not needed for the runtime; stage4/stage5 default to this DB name)
python stage1_clean_chunk.py && python stage2_index.py && python stage4_cards.py && python stage5_vectors.py --model bge-m3
# measure
KB_DB=dist/kb-v3m-2026-11-03/wiki.v3m.db python benchmark/run_benchmark.py --retriever v3 --mode hybrid \
       --cases benchmark/cases_holdout.jsonl        # add --rerank / --hit content as needed
```
`stage2` now takes ~4-5 min (it scans title/section/text once to fill `term_df`) and reports dead synonym
targets in its stats. Adding a synonym also changes `jieba_userdict.txt`, hence query segmentation for every
query — re-run two sets before believing a ±1 case change. Vector artefacts are
`vectors.<db-stem>.<model>.npy`; never build two databases in one directory under the old flat name.

Benchmark sets (2026-11-03): `cases.jsonl` (90, dev — the old synonym table was tuned on it), `cases_holdout.jsonl`
(50, held out before synonyms), `cases_holdout_93.jsonl` (the 110-case set minus 17 cases whose expected names do not
exist in the corpus), `blind_120.jsonl` (120 doc-grounded colloquial questions, written from the manuals by four
independent agents), `sealed_60.jsonl` (60 more, written last and only run once, as a regression check).
The 110-case file and its numbers are kept for the record; see the 2026-11-03 section for why it is not a target.

## Stages
- [x] 0 benchmark + v2 baseline
- [x] 1 clean/chunk (`stage1_clean_chunk.py`): 20595 → 52950 chunks (5497 dup merged, p95 1791 chars, max 2600; was 35.9M)
- [x] 2 hybrid index (`stage2_index.py`, `synonyms.tsv`): trigram + jieba FTS, 2024 manual name↔desc pairs + ~140 curated synonyms
- [x] 3 ontology (`ontology/ontology.yaml`, 12 types)
- [x] 4 cards (`stage4_cards.py`, `ontology/field_findings.yaml`): 481 FB, 281 Instruction, 44 Unit, 847 Concept, 14 field; 0 without evidence
- [x] 5 vectors (`stage5_vectors.py`): bge-m3, 18780 chunks + 1653 cards, 158 s on RTX A4000
- [x] 6 skill wired (`kv-studio-kb-programming/SKILL.md`, `kb_search.py`); old `query_keyence_kb.py` kept as fallback

## Results
| stage | dev hit@1 | dev hit@5 | dev MRR | holdout hit@1 | holdout hit@5 | holdout MRR | latency |
|---|---|---|---|---|---|---|---|
| v2 baseline | 0.278 | 0.344 | 0.31 | 0.04 | 0.14 | 0.09 | 0.4–5 s/q |
| v3 fts (stage 1+2) | 0.767 | 0.911 | 0.831 | 0.26 | 0.50 | 0.37 | ~20 ms/q |
| v3 + cards (stage 4, card_weak=0) | 0.80 | 0.956 | 0.861 | 0.48 | 0.64 | 0.557 | ~23 ms/q; CLI cold 0.9 s |
| v3 vectors only | 0.811 | 0.922 | 0.859 | 0.62 | 0.76 | 0.682 | ~105 ms/q |
| **v3 hybrid (all, vec w=2.0)** | **0.856** | **0.967** | **0.906** | **0.56** | **0.76** | **0.653** | ~120–180 ms/q warm; CLI cold 8.5 s |

## Notes / decisions
- Label fixes (valid answers missing from expect): dev cn_circular, cn_fb_args, hw_ad; holdout h_fifo. Made once, logged here.
  Holdout still under-credits: h_bitcount top-1 is BCNT, h_capacity hits MFREE — both correct, left unfixed (score is conservative).
- synonyms.tsv: 43 entries removed because they were written after reading holdout questions.
- Parameters chosen on dev only: card_weak=0 (sweep 0/0.3/1.0), vec weight 2.0 (sweep 1.2/2/3/5, best dev MRR).
- Vectors-only beats hybrid on holdout hit@1 (0.62 vs 0.56): lexical channels + synonyms still dominate fusion for wording
  they were not tuned on. Next lever: a cross-encoder reranker (bge-reranker-v2-m3) over top-30, judged on holdout once.
- `related_cards()` is lexical only; for colloquial queries it can show unrelated cards (e.g. 取字符串左边 → FIND) while the
  chunk list is right (LEFT). Next: rank cards by vector similarity too.
- stage1 collapses empty table cells, which can shift column headers of the htmlhelp name table; cards parse from v2 raw text.
- Hardware/selection questions are weakest (dev hardware hit@1 0.5): Unit cards only have doc-level info; no CPU/unit spec
  table exists in the sources. Selection needs a curated spec dataset (not derivable from current manuals chunking).

## Post-release fixes (2026-11-02, from a blind agent test on two engineer questions)
- Manual-pair lexicon contained everyday words as instruction names (读取→MRD, 连接→CON, 脉冲→MPS); they expanded most
  queries and put MPS/CON/TP on top. stage2 now prunes names with len<=2 & DF>2%, or DF>10% (13 pruned).
  After: dev hit@1 0.867 / hit@5 0.967 / MRR 0.915; holdout hit@1 0.56 / hit@5 0.78 / MRR 0.664.
- Series bug: KVSHARDX5H/X3H (KV-X500/X300 manuals) were tagged KV-XH; fixed in stage1 and in place (459 chunks).
- Still missing (seen in the test): concept "电脑/上位机读写PLC" → 上位链路 (RDS/WRS, port 8501) / MC 协议;
  "IO电机 CW/CCW" → 脉冲串定位 (KV-SH04PL) vs 正反转输出; CPU/unit selection & compatibility tables; PDF chunks with
  garbled glyph text (font-encoding) in spec pages.

## Selection tables (kb-pipeline/selection/, 2026-11-02)
- 4 CSVs (cpu 8, motion 9, io 29, special 38 rows) built by blind subagents from wiki.v3.db, every numeric cell carries chunk_id evidence;
  `build_page.py` + `selection.template.html` -> `selection.html` (local file; Artifact publish needs a claude.ai login).
- Original PDFs live in `C:\Users\Public\Documents\KEYENCE\KVS12\ManualHelp\2052` (installed with KV STUDIO; 166 files).
  `render_pages.py <pdf> <first> <last>` renders PDF pages to PNG (PyMuPDF) for visual checking; DB "pNN" = PDF page, printed page ≈ PDF page - 22.
- Verified against the PDFs so far: X3H p33-34/56/58, X5H p26/30, SH04PL p26/43. Found: KV-C16XTD output is 0.3A and OFF→ON 100µs
  (subagent had inferred 0.2A/150µs from a merged cell); X310 built-in inputs and C16XTD inputs are polarity-free; X5xx have no built-in I/O.
  Lesson: merged table cells cannot be resolved from extracted text; spec tables need visual check, not column-position inference.
- CORRECTION (same day): the "KV-C16XTD = 0.3A" finding above was WRONG. At 2.6x zoom the "30VDC 0.3A" text is centred on the B8XTD column
  only; "0.2A" spans C16XTD+C32XTD (KVSHARDX3H p56 and KVSHARDG4 p62 agree). The subagent's original 0.2A was right; its 150µs OFF→ON for C16XTD was wrong (100µs).
  I misread a low-res full-page image, then put that unverified reading into the X3H verifier's prompt, which "confirmed" it (anchoring);
  the independent legacy-manual verifier caught it. Rules: judge merged cells from a >=2.5x crop (text centre vs column edges),
  never hand a verifier my own unverified reading, and give each verifier an independent source when two manuals cover the same unit.
- All four verifier patch files are merged (`merge_patches.py`, idempotent): confirmed 160, corrected 31, new 16, unreadable 2.
  Unresolved (manual's own typos / contradictions, left as printed): KV-B16RA "22A" (inferred 2A), KV-C64TA/TAP common terminals "2 vs 4",
  KV-AD40/DA40 4-20mA resolution "1μA", KV-DA40V accuracy column label, KvsMotion appendix-5 prints XH64EC as 16 axes (XHECL says 64).
- Still to verify: groups not covered by the four verifiers (rest of special units, KV-XH/ML chapters beyond the listed pages).
- Parsing defect to fix in stage1: "μ" lost in KV-X300 / KV-TP40 text ("10μs" -> "10s", "100μA" -> "100A").

## MinerU trial (2026-11-02)
- Installed in an isolated venv `H:\envs\mineru` (mineru 4.1.3, torch 2.5.1+cu118); models via ModelScope into `C:\Users\Administrator\.mineru\models`
  (standard tier: torch + onnx small models + MinerU2.5-Pro GGUF VLM). NEVER use `--remote` (uploads to mineru.net).
- `mineru parse` (managed local server) does not work here: parse-server restart fails with WinError 10013 / control channel timeout.
  `mineru-kit parse <pdf> -o <dir> --pages N --tier standard|basic --ocr-mode ocr` works directly (no server).
- Test on KVSHARDX3H.pdf p56 (merged-cell table, garbled text layer): standard tier returns an HTML table with correct colspan/rowspan
  (0.3A only under B8XTD, 0.2A under C16XTD+C32XTD; OFF→ON 100µs spans B8+C16, 150µs C32; ON→OFF 300µs spans all) and keeps μ ("100μA", "25μs").
  basic tier: faster (infer 4.5 s vs 14.5 s per page) but coarser column grid (relative merge ratios only).
- Scale: 26578 indexed PDF pages, **5970 (22%) have a garbled text layer**, 433 pages are titled "规格". Standard ≈15 s/page, basic ≈5 s/page.
  Plan if pursued: standard for the ~430 spec pages (~2 h), basic for the other garbled pages (~8 h, overnight batch), then re-chunk by page
  and rebuild v3 (stage 1 variant that prefers MinerU text for flagged pages); benchmark before/after.

## Next (not done)
1. Reranker on top-30; 2. vector-ranked cards; 3. curated CPU/unit spec cards for 选型; 4. grow holdout to ~150 real user
questions (from actual sessions) and re-check; 5. skill boundary cleanup (remove 编程规则/回答形状 from KB skill, see chat).

## 2026-11-03 v3m channel repair + synonym rebuild + benchmark integrity

### 1. v3m was missing two of the four retrieval channels
`stage4_cards.py` / `stage5_vectors.py` default `DB` is `wiki.v3.db`; v3m only ever ran stage1+stage2. So every
"v3m is 20 points worse" number compared a **two-channel** retriever (seg/tri/name) against a four-channel one.
The 8x "speed advantage" (13 ms vs 106 ms) was also just the missing vector encoder.
- `stage5_vectors.py` now writes `vectors.<db-stem>.<model>.npy`; `kb_vectors.find_base()` reads that name and
  falls back to the legacy `vectors.<model>.npy`. Without this, building v3m vectors overwrote v3's matrix (same dir).
- v3m now has cards (1737: 481 FB / 281 Instruction / 44 Unit / 917 Concept / 6 ErrorCode / 8 FieldFinding,
  0 without evidence) and vectors (18622 chunks + 1723 cards, dim 1024, 153 s on the A4000).

### 2. The 110-case holdout is not a usable target
- **17 of 110 cases expect names that do not exist anywhere in the corpus**: `MC_CamIn`, `MC_GearIn`,
  `StorageGetFileStatus`, `FSTAT`, `StorageWriteLine`, `StorageOpenFile`, `INT_TO_STRING`, `DINT_TO_STRING`,
  `STRING_COMPARE`, `STREQ`, `EIP_ExplicitMessage`, `EIP_SendExplicitMsg`, `SocketUDP_SendTo`, `PN_WriteRecord`,
  `CCL_RefreshIO`, `HEX_TO_INT`, `RAD_TO_DEG`, `AverageFilter`, `TempRead`, `U_TempRead`, `HSC_Read`, `U_HSCRead`,
  `AnalogOut`, `U_AnalogOut`, `EncoderRead`, `U_EncoderRead`, `MC_ReadActualPosition`. These are PLCopen / IEC /
  other-vendor names; a case whose every `expect` is absent can never hit, so the set's ceiling is 93/110 = 0.845.
- The 60 `h_new_*` cases were added in the same pass as the 96 new synonyms and mirror them one-to-one
  (`h_new_05 关闭TCP连接` ↔ `关闭连接`, `h_new_06 查看SD卡空间` ↔ `查看空间`, `h_new_07 小数四舍五入` ↔ `四舍五入`…),
  so gains on that set measure table lookup, not retrieval.
- The metric only looked at `title`/`source`. For RAG what matters is whether the answer is in the returned
  context, so `run_benchmark.py --hit content` also matches the chunk text.
- New tooling: `benchmark/validate_cases.py` (expect in evidence chunk title/source? expect inside the question?
  question shares a ≥6-char run with the page title?), `benchmark/compare_results.py`, `benchmark/rank_diff.py`,
  `benchmark/blind_report.py`, `tool_synonyms.py` (df of every surface/target, dead-target list).
- Sets now used: `cases.jsonl` (90, dev), `cases_holdout.jsonl` (50, old honest), `cases_holdout_93.jsonl`
  (110 minus the 17 unanswerable), `blind_120.jsonl` (120 doc-grounded colloquial questions written from the
  manuals by four independent agents that never saw the other sets).

### 3. Synonym layer rebuilt
- 409 → **1676** (term,target) pairs: 758 Chinese surface forms → 620 targets, **0 dead targets** (checked by
  `tool_synonyms.py`; the old table had 58).
- `synonyms.tsv` is now organised as concept blocks, and `_curated_expansions` treats curated rows as an
  undirected graph (union-find): 回原点 / 原点复归 / MC_Home / 找零点 all sit in one group and any of them in the
  query pulls in the others. Replaces the old "curated term → target, then one manual-pair hop" hack.
- `stage2` now fills `term_df(term, df)` + `lexicon.df` (one substring pass over title/section/text). The runtime
  drops `df=0` targets (dead) and `df>6%` targets (too generic to discriminate), and orders expansions
  rare-first. `df>10%` *triggers* (位置/软元件/缓冲存储器…) do not expand.
- Chinese negation guard: a surface preceded by 不/别/非/否/没 or followed by 不是/不要/不用… does not expand
  ("不是急停那种" must not pull MC_ImmediateStop).
- Numeric flags for experiments: `KB_SYN`, `KB_MANPAIR`, `KB_DF_MATCH`, `KB_DF_EXP`, `KB_EXP_CAP`, `KB_WEIGHTS`,
  `KB_W_SEGX`, `KB_W_TRIX`.

### 4. Channel ablation (blind_120, v3m, 1676 pairs)
| configuration | hit@1 | hit@5 | MRR | ms/q |
|---|---|---|---|---|
| words only (no expansion, no cards, no vectors) | 0.150 | 0.325 | 0.235 | 41 |
| + curated synonyms (this table) | 0.375 | 0.608 | 0.482 | 44 |
| + cards + vectors (full) | 0.525 | 0.892 | 0.673 | 128 |
| full, no synonyms | 0.458 | 0.800 | 0.600 | 127 |
| full, no manual-pair channel | 0.525 | 0.892 | 0.671 | 129 |
On hard colloquial questions the synonym table is worth **+28 pp hit@5 over words-only**, and the two missing
channels were worth +28 pp on their own. The manual-pair channel (`manual_pair` rows from htmlhelp tables) has
become redundant now that curated synonyms + cards + vectors exist.
Weight ablation (same set): `tri_x 0.6→0` **+5.9 pp hit@5** and 3x faster (trigram over expansions was noise);
`seg_x 0.7→0.35` neutral on hit@5, +2 pp hit@1 on holdout 50. New defaults: `tri_x=0`, `seg_x=0.35`.

### 5. Results (same code, same synonym table, 4 channels)
| set | n | v3m hit@5 | v3m hit@1 | v3m MRR | ms/q | v3 hit@5 | v3 MRR |
|---|---|---|---|---|---|---|---|
| **sealed_60** (written last, never tuned on) | 60 | **0.817** | 0.617 | 0.690 | 178 | – | – |
| ″ motion+instruction (sealed_a) | 30 | 0.633 | 0.533 | 0.574 | 294 | – | – |
| ″ comm+modules (sealed_b) | 30 | 1.000 | 0.700 | 0.804 | 300 | – | – |
| blind_120 (doc-grounded, first pass untuned) | 120 | 0.892 | 0.525 | 0.674 | 128 | 0.875 | 0.667 |
| holdout 50 | 50 | 0.96 | 0.84 | 0.894 | 183 | 0.96 | 0.867 |
| holdout 93 (110 minus the 17 unanswerable) | 93 | 0.86 | 0.731 | 0.792 | 115 | 0.849 | 0.757 |
| dev 90 | 90 | 0.956 | 0.789 | 0.865 | 124 | 0.956 | 0.861 |
v3m is ahead of v3 everywhere and clearly better at top-1 on holdout 50 (0.84 vs 0.80) and holdout 93 (0.731 vs
0.677): MinerU text pays off in precision, not recall. **v3m is the runtime library; v3 stays as the control.**
The 0.9 target is met on holdout 50 (0.96) and blind_120 (0.892) but not on sealed_60 (0.817), where the weak
family is motion+instruction (0.633) and the strong one is comm+modules (1.000) — the same split as blind_120
(comm 1.000 / instruction 0.900 / motion 0.867 / module 0.800).

Ablation on sealed_60 (60 cases, same code):
| condition | hit@1 | hit@5 | MRR |
|---|---|---|---|
| full | 0.617 | 0.817 | 0.690 |
| no curated synonyms | 0.550 | 0.750 | 0.627 |
| no expansion at all | 0.567 | 0.750 | 0.639 |
| no cards, no vectors | 0.450 | 0.583 | 0.509 |
So on hard colloquial questions: cards+vectors +23 pp, the curated synonym table +6.7 pp, the manual-pair
channel ~0 pp. Caveat: the two sealed-set authors sanity-checked their own cases with `kb_search`, so those
absolute numbers are optimistic; sealed_a (checked with `--fast` only) is the harder, more believable half.

### 6. Known traps found while doing this
- Rewriting `synonyms.tsv` wholesale silently dropped coverage (按一下/脉冲/固定宽度…); dev hit@1 fell 0.878→0.756
  until the old rows were merged back. Never replace the file without merging.
- A short surface collides with longer compounds: `断电 → MC_Power` hijacked "累计计时 断电保持" and pushed MC_Power
  to rank 1 (holdout 50 0.96 → 0.94). Bare 断电 removed; 伺服断电/电机断电/断使能 kept. Check every new short
  surface against the compounds that contain it (断电保持, 上电初始化, 位置 vs 当前位置).
- Adding a synonym changes `jieba_userdict.txt` and therefore query segmentation globally, so unrelated cases can
  move by one rank between builds. Compare at least two sets before believing a ±1 case change.
- Dev hit@1 is not a good tuning signal: several dev labels accept only one of two valid answers (SEC vs
  WriteCalendarTime, BMOV vs StorageCopy), and the old table had been hand-fitted to them.
- `stage2` writes `jieba_userdict.txt` to the DB directory, so v3 and v3m share one userdict (last build wins).
  Harmless today (same lexicon) but it should be per-database before the two diverge.
- `KB_SYN=0` does not disable the manual-pair hop inside `_curated_expansions`; it only disables curated triggers.


### 7. Next (from 2026-11-03)
1. **Motion + instruction is the weak family** (sealed_a 0.633 vs comm 1.000). The misses are mostly "plausible
   sibling" answers (MC_MoveToPoint when the question is about the 动作模式 page) plus page titles that differ by a
   word between manuals, so the hit rule fails on a page that is semantically right. Next: per-family "page title →
   manual wording" dictionary, and expect_any alternative labels in the benchmark.
2. Reranker over top-30 (bge-reranker-v2-m3) — still the largest un-tried lever, and the only one likely to move
   hit@1 (0.53-0.62) rather than hit@5.
3. Remaining 27 % of garbled pages: rerun MinerU with the page flag lowered (ad>=1), then stage1 --mineru +
   stage2 + stage4 + stage5 (>8 h, overnight); expect a further gain mostly in the spec-table family.
4. Make jieba_userdict.txt per database (shared file today; the last build wins).
5. Retire enchmark/cases_holdout_110.jsonl in favour of cases_holdout_93.jsonl + lind_120.jsonl + sealed_60.jsonl;
   keep the 110 file only as a record of the broken label set.

## 2026-11-03 reranker: tried, measured, left off

Model: `BAAI/bge-reranker-v2-m3` (XLM-R large, 2.27 GB) pulled from ModelScope to
`H:\models\models\BAAI--bge-reranker-v2-m3\snapshots\master` (516 s). Loads in 5.7 s on the A4000 and scores
24 pairs in 45 ms, so a query costs +~300 ms end to end (127 ms -> 425 ms).
Code: `kv-studio-kb-programming/scripts/kb_rerank.py` + `Searcher._rerank`; off by default, `KB_RERANK=1` or
`--rerank` turns it on; `KB_RERANK_N` (candidates), `KB_RERANK_A` (blend), `KB_RERANK_CARD` (passage shape).

Passage shapes tried: (1) `title | section | text[:900]`; (2) card summary + title/section/text;
(3) card summary alone. Blends 1.0 / 0.7 / 0.5 / 0.4; candidate depth 24 and 3.

| set | baseline hit@5 / hit@1 / MRR | best rerank config | result |
|---|---|---|---|
| holdout 50 | 0.96 / 0.84 / 0.894 | card+text, A=0.7 | 0.94 / 0.66 / 0.754 |
| holdout 50 (content-hit) | 1.00 / 0.90 / 0.945 | card+text, A=0.7 | 0.96 / 0.80 / 0.851 |
| sealed_60 | 0.817 / 0.617 / 0.690 | card-only, A=0.7 | 0.800 / 0.517 / 0.633 |
| blind_120 | 0.892 / 0.525 / 0.674 | card-only, A=0.7 | 0.892 / **0.583** / **0.707** |

No configuration improves hit@5 on any set; the only positive is +5.8 pp hit@1 on blind_120, against -0.9 pp
hit@5 on sealed_60 and -10 pp hit@1 on holdout 50. Pure rerank (A=1.0) is far worse everywhere
(blind 0.70 hit@5, sealed 0.583), so the model's ordering is not a better ordering than the fusion.

Why: the cross-encoder judges "which passage explains this topic", and our labels (and an agent's need) are
"which page documents this instruction". A raw FB page chunk is a parameter table, so the model prefers any
prose page that mentions the same words — e.g. for "找零点 原点传感器" it scores `定位控制的步骤(p322-325)` 0.84
and `MC_Home` 0.31, while the fusion (correctly, for this library) puts `MC_Home` #2 and
`MC_InternalHomeSensor` #1. Sanity check of the model itself: 原点复归 vs the MC_Home page = 0.995, vs a PID
page = 0.002, so the loader and the scoring are not the problem.

To make a reranker useful here it would need one of: labels expressed as "any correct answer page"
(`expect_any`, so a procedure page also counts), a reranker fine-tuned on the "API page" preference, or
reranking at card level with a card-specific objective. Until then it stays off and the fusion order wins.

Side result worth keeping: with content-level hits (answer string allowed to appear in the returned text),
holdout 50 is **1.00 hit@5 / 0.90 hit@1**, i.e. the answer is always inside the five chunks the agent reads;
doc-level misses on that set are mostly "the same fact on a different page".

## 2026-11-03 扩展资料入库：教材 / 官方示例程序 / 标准化工程

用户提供 `H:\KeyenceAgent\其他文件`（7 本 PDF + `official-examples.zip`）与 `KVX样例程序_v100` 工程快照。按用户要求
**PDF 一律用 MinerU 重新识别，不用 Python 直接抽文本**（旧库 22% 的 PDF 页文字层是乱码，同样的坑不想再踩）。

### 入库了什么（`ingest_extra.py`，`x:` 前缀，幂等可重跑）
| 类型 | 来源 | 块数 | 说明 |
|---|---|---|---|
| `textbook` | AS_155351 使用实例 ST 语言（140p）、AS_147562 程序标准化（92p）、AS_143610 运动控制篇（92p） | 160 | MinerU standard 档，630 s / 339 s / 300 s，产物在 `extra_docs/mineru/<key>/` |
| `program_example` | SH04PL轴控程序示例（20 个 .mnm）、常用主模块程序（44 个 .mnm） | 119 | 官方示例梯形图/ST 原码 |
| `project_snapshot` | KVX样例程序_v100（`H:\kvOp\regression13_real_20260923_final`） | 72 | 40 个 FB（自变量/局部变量/ST 体）、24 个程序模块、全局变量表、结构体、总览 |
| `kb_note` | 手写 | 3 | 命名规范对照、资料构成、程序分层结构 |

### 为什么是 stage1 之后、stage2 之前
`stage1` 会重建 `chunks` 表，所以扩展资料不能进 stage1 的输入；`ingest_extra.py` 在 stage1 之后追加，
再由 stage2 重建 FTS/lexicon/term_df、stage4 重建卡片、stage5 重建向量。重跑 `stage1` 后必须重新执行一次。
`--only <type>` 只重写该类型的父块（`write(reset_all=False)`），不会误删其他扩展资料。

### 先验权重（`PRIOR`）
`textbook 0.8 / program_example 0.75 / project_snapshot 0.8 / kb_note 1.0` —— 故意低于手册（`pdf 0.85`、
`chm 0.95`、`htmlhelp 1.0`）：教材覆盖同一主题时不能顶掉工程师要引用的手册页；`kb_note` 是手写规范，
可以排在最前。

### 被排除的资料及理由
- `AS_108654` 设备数据的 PLC 管理（7p）：营销页（用户判断，完全没必要）
- `AS_143609` 基础编程篇（90p）：与 `KVSPRG` / `KVSINTRO` / `KVSUSE` 高度重复
- `AS_151508` 实时时序图监控器（16p）：库里已有 156 块涉及该工具，且属 operator 技能域
- `AS_167121` 运转记录活用指南（28p）：库里已有 297 块涉及运转记录
- `T语言示例.md`：与库里 57 条 `t_language_example` 逐编号对应，重复

### 教材与样例程序的"配对"实情（查过了，不是配套）
- 名字零交集：教材全文对 `FB_Cylinder` / `FB_Motion` / `KVX样例程序` 等 0 命中，全文"下载"0 次；教材里的示例
  都是书内代码片段。
- **命名规范两套**：教材 p12 教 `x/ui/i/udi/di/r/lr/str/tim/a/st/un/fb` + 作用域 `g/l`；KVX样例程序实际用
  `b`（BOOL）、`inst`（FB 实例）、`str`（结构体），全局变量 135/145 直接中文命名。两者不可混用，
  这一点写进了 `kb_note`，并在每块的 `keywords` 里标 `convention=textbook|sample`。

### 入库结果与复测（同日 15:00 完成）

MinerU standard 档解析三本教材（**不用 Python 直接抽文本**）：
ST 语言实例 140 页 / 630 s、程序标准化 92 页 / 339 s、运动控制篇 92 页 / 300 s，产物在 `extra_docs/mineru/<key>/`。
`mineru-kit` 的 markdown 输出里 3.8–6.7 MB 大部分是 base64 图片，去掉后正文约 113 k / 43 k / 29 k 字符。

最终入库 **354 块**（`x:` 前缀，`ingest_extra.py` 幂等）：
`textbook 160`（按标题合并到约 1600 字/块）、`program_example 119`（每个 .mnm 一块，标题带上代码里的中文注释）、
`project_snapshot 72`（40 FB + 24 程序 + 全局变量表 + 结构体 + 总览）、`kb_note 3`。

复测（同代码、同评测集，仅把新资料放进库里）：

| 评测集 | 入库前 hit@5 / hit@1 / MRR | 入库后 hit@5 / hit@1 / MRR |
|---|---|---|
| holdout 50 | 0.96 / 0.84 / 0.894 | **0.98** / 0.80 / 0.881 |
| blind_120 | 0.892 / 0.525 / 0.674 | **0.900** / **0.583** / **0.712** |
| sealed_60 | 0.817 / 0.617 / 0.690 | **0.833** / **0.650** / **0.724** |

holdout 50 的 hit@1 掉了 4 个百分点，逐条查过：全是手册之间的名次微调（TCH/LDF/DataSearch/U_ADRead），
**不是新资料顶掉了手册**——新块在那几条的 top-3 里根本没出现；原因是重建 stage2 换了 jieba 词表引起的分词漂移
（这条坑之前记过）。hit@5 反而从 0.96 升到 0.98。

### 检索验证（人工 QA）
- "程序标准化 变量命名前缀怎么定" → #1 `kb_note 变量命名规范`，#2-3 `textbook 1 面向程序的标准化`
- "变量命名规范 教材还是样例" → 两条 `kb_note` 包揽前二
- "ST语言 四则运算 示例" → #1-3 全是 `textbook 1章 四则运算`
- "轴1原点回归 示例程序" → #4 `program_example OriginReturn.mnm（轴1原点回归，示例程序）`（前三名是手册 MC_Home/ORG）
- "标准程序 功能块分层怎么分" → #5 `kb_note 标准化程序的分层结构`
- "绝对位置跟随控制 示例程序" → 前八名仍是手册（MC_MoveAbsolute 等）：手册确实更贴题，按设计 `PRIOR` 让教材/示例低于手册

### 顺带修掉的问题
1. `SH04PL轴控程序示例.md` 里混着"📈 转换总结"这种生成器小标题，被当成程序块且能排第一；现在只接收标题里含
   `.mnm` 的段。
2. 示例程序的标题原本是英文文件名（`OriginReturn.mnm`），中文问句命中率低；现在从代码里的中文注释提取
   描述，变成 `OriginReturn.mnm（轴1原点回归，示例程序）`。

`SKILL.md` 的证据优先级已补上 `textbook` / `program_example` / `project_snapshot` / `kb_note` 四类，并写明
"手册讲语法与约束、教材讲方法与步骤、示例/快照是参考实现，三者不能互相替代"。

### 手册到底有多少本（2026-11-03 更正）
之前写"155 本参考手册"是错的，实际：

- `C:\Users\Public\Documents\KEYENCE\KVS12\ManualHelp\2052` 里有 **162 个文件**：144 PDF + 10 CHM + 6 XLS + 2 XLSX
- 进库的 PDF 是 **137 本**：6 本因内容与别的书完全相同被去重合并（原名记在 `also_in`：
  `KV-LH_OrientalmotorAZ.pdf`→`KV-LH_Orientalmotor.pdf`、`KvsPtcNanoHardDiff.pdf`→`KvsPtcDevDiff.pdf`、
  `KvsPtcParamCpupos.pdf`→`KvsPtcInstCpumb.pdf`、`SV2_GainSearchPro2_without_command.pdf`→`_with_command`、
  `SV3_GainSearchPro_without_order.pdf`→`_with_order`、`UnitTrace_KVS11.pdf`→`UnitTrace.pdf`），
  `CPUErrorList.pdf`（51 页 CPU 错误代码表）在旧库构建时就没被导入 —— **已知缺口，未入库**
- 137 本的块数分布：≥200 块 30 本、50–199 块 25 本、10–49 块 28 本、**1–9 块 54 本**（单页速查/便签，
  如 `KV-XH_ControlCycle.pdf`、`EpGraph.pdf`、各伺服调谐速查）。所以"137 本"按文件算，不等于 137 本大部头
- 另外 8 个 Excel 设备映射表（`DeviceMap(KV-X/XH/XHEC/ML_MC/SH04PL)`、`DeviceMap(MV-L40)`、CR/CM 转换表）
  逐地址展开后占 **33,167 块 = 全库 62%**；CHM/HTML 帮助（598 + 70 + 11 + 51 个页面）合计约 5,940 块
