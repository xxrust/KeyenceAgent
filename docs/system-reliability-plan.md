# KV automation reliability work

Objective: preserve verified operations as reusable interfaces, remove ambiguous
entrypoints and duplicate implementations, and make a successful repair improve
future workflow runs. This is system work, not another sample-replication task.

## Evidence found on 2026-09-11

- FB arguments had different read and write entry routes. Commit e54bb2b made
  them share state-aware declaration focus and added live persistence regression.
- At baseline installed skills were ordinary directory copies. They are now
  verified junctions to this repository; originals are preserved in the work
  root's `system-reliability/installation-backup` directory.
- `script_manifest.json`, `capability-status.md`, and the programmer toolkit
  manifest separately advertise available operations.
- Operator root scripts include both forwarding wrappers and independent legacy
  UI implementations. In particular, root and workflow expansion-unit scripts
  have the same filename but different parameters and implementations.
- Some published workflows invoke a child directly; others use the flat runner.
  Logging, preflight, timeouts and success verification consequently differ.
- The resolver accepts absolute script paths before checking manifest class.
- An `approved` label is not bound to the implementation/dependency versions or
  a reproducible semantic test. Historical success can outlive its tested route.
- MVP examples dominate top-level guidance despite generic editing operations
  having distinct, smaller input requirements.
- Work-root research directories contain successive failures and successes with
  similar names. They are searchable alongside current code without a lifecycle
  index identifying the maintained route.

Baseline inventory: 79 operator PowerShell files, 43 manifest entries, 36
unclassified scripts, 10 duplicated leaf names, and 5 published workflows not
using the flat executor. The installed operator also contains an untracked
legacy EtherCAT implementation. The FB file byte difference is only line-ending
normalization, not a functional code difference. The 31 installed sample-project
files match the repository byte-for-byte.

## Required outcomes and acceptance

| Requirement | Completion evidence |
| --- | --- |
| One maintained source and installation | Installed code resolves to that source; configuration/sample assets are preserved; drift test passes |
| One discoverable interface per operation | Machine-readable catalog; no competing active UI implementation or unexplained executable |
| Generic, composable workflows | Project/FB/variable/structure/hardware operations do not require a synthetic MVP; plans resolve through one executor |
| Repairs reach the caller | Live tests invoke the published interface and exercise state transitions that previously failed |
| Unambiguous verification | Same-run target, inputs, code/dependency fingerprints, semantic readback and timings; failed/stale evidence cannot certify current code |
| Simple fast execution | No exploratory retries; module lookup under 1s and UI atomic actions under 10s except documented software startup |
| Clear skill guidance | Concise task-to-interface routing; programming model separated from UI mechanics; examples are examples |
| Organized code and work products | Current code, tests, maintained references and archived research have distinct locations and an index; recoverable migration |
| Regression prevention | Non-UI contract tests plus representative live tests; one documented promotion/release process checks the actual workflow |

## Work stages

1. Inventory current files, callers, installation drift, claims and evidence.
2. Establish the source of truth and retire duplicate/obsolete routing.
3. Unify workflow execution, result contracts and evidence/version tracking.
4. Rewrite skill routing and organize work products without losing history.
5. Run structural, negative and real UI regressions; fix observed failures;
   commit each verified stage. Audit every outcome above before completion.

Do not mark historical tests as tests of new code, treat blank table rows as
written content, or reduce required functionality to obtain a green result.
Preserve unrelated worktree edits. No push is requested.

## Progress and limits

- Source links are installed and verified for all three KEYENCE skills.
- Resolver now checks manifest membership and classes for absolute as well as
  relative paths. The resolver regression accepts three valid path forms and
  rejects wrong-class, outside-root, traversal, unlisted and missing routes.
- The flat executor requires exact result filenames from the manifest. It
  preserves prior result files in `_history/<run-id>` before a step and rejects
  absent, malformed, stale, false or non-Boolean results. Process failure cannot
  be overridden by an `exit_code.txt` containing zero. Windows arguments are
  quoted, including empty strings, quotes and trailing backslashes.
- Same-run receipts bind outputs to arguments, input file hashes and a hash of
  the scripts tree (including shared libraries). This is provenance, not proof
  that every child verifies every semantic field. MNM import currently reports
  route completion explicitly; its placement/content acceptance still needs
  to be made mandatory in published import workflows.
- `tests/test_flat_execution_evidence.ps1` passes 17 no-UI cases, including
  stale output reuse, a misleading helper result, process failure, timeout,
  snapshot result variants and forbidden absolute routes. Evidence is under
  `H:\kvOp\system-reliability\strict-executor\typed-tests-r2`.
- All five formerly direct-child workflows now construct flat plans. Parameters
  can retain arrays and Boolean values; older argument-vector plans remain
  supported. Five published plan tests and the atomic boundary test pass.
- Published FB snapshot regression passes all four exact-reference copies,
  both remembered-table branches, wrong-focus rejection and close/reopen.
  Maximum atomic duration is 1513ms; maximum module lookup is 196ms. Evidence:
  `H:\kvOp\system-reliability\published-fb-snapshot`.
- Published structure export passes through the typed plan/executor in 4.135s
  (child 2.619s). Evidence: `H:\kvOp\system-reliability\published-structure-snapshot`.
  This does not certify the hardware/export mutation workflows as newly live-tested.
- Remaining: remove competing active routes, simplify skills, organize history,
  finish semantic acceptance and regression promotion checks.
  The system-wide goal is not yet complete.
